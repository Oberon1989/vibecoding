#ifndef VOXEL_DENSITY_MESH_MC_TRANSVOXEL_INCLUDED
#define VOXEL_DENSITY_MESH_MC_TRANSVOXEL_INCLUDED

#include "VoxelDensityTypes.hlsl"
#include "VoxelDensityMath.hlsl"
#include "VoxelDensityDensity.hlsl"

// The tables are immutable lookup data uploaded once from
// VoxelTransvoxelTables.cs. Every density sample, case selection, interpolation,
// normal, triangle, and output index is computed by this compute shader.
StructuredBuffer<uint> RegularCellClassTable;
StructuredBuffer<uint> RegularCellDataTable;
StructuredBuffer<uint> RegularVertexDataTable;
StructuredBuffer<uint> TransitionCellClassTable;
StructuredBuffer<uint> TransitionCellDataTable;
StructuredBuffer<uint> TransitionVertexDataTable;

static const uint MC_FACE_NEG_X = 0u;
static const uint MC_FACE_POS_X = 1u;
static const uint MC_FACE_NEG_Y = 2u;
static const uint MC_FACE_POS_Y = 3u;
static const uint MC_FACE_NEG_Z = 4u;
static const uint MC_FACE_POS_Z = 5u;
static const uint MC_NODE_INVALID = 0xFFFFFFFFu;
static const uint MC_TRANSITION_HALF_RES = 2u;
static const uint MC_TRANSITION_CELL_SCALE_NUMERATOR = 1u;
static const uint MC_TRANSITION_CELL_SCALE_DENOMINATOR = 4u;
static const uint MC_MAX_REGULAR_VERTICES = 12u;

uint GetLeafSlot(uint3 groupId)
{
    return groupId.x + groupId.y * 32768u;
}

bool IsActiveLeafSlot(uint leafSlot)
{
    return leafSlot < ActiveLeafCountReadBuffer[0];
}

float GetLeafStep(VoxelActiveLeaf leaf)
{
    return BASE_LATTICE_SIZE * exp2((float)leaf.lod);
}

float3 GetLeafOrigin(VoxelActiveLeaf leaf)
{
    return (float3)leaf.canonicalOrigin * BASE_LATTICE_SIZE;
}

float3 GetFaceNormal(uint face)
{
    if (face == MC_FACE_NEG_X) return float3(-1.0f, 0.0f, 0.0f);
    if (face == MC_FACE_POS_X) return float3(1.0f, 0.0f, 0.0f);
    if (face == MC_FACE_NEG_Y) return float3(0.0f, -1.0f, 0.0f);
    if (face == MC_FACE_POS_Y) return float3(0.0f, 1.0f, 0.0f);
    if (face == MC_FACE_NEG_Z) return float3(0.0f, 0.0f, -1.0f);
    return float3(0.0f, 0.0f, 1.0f);
}

void GetFaceAxes(uint face, out uint uAxis, out uint vAxis, out uint normalAxis)
{
    // U x V points along the positive face normal for every axis pair.
    if (face < 2u)
    {
        uAxis = 1u;
        vAxis = 2u;
        normalAxis = 0u;
    }
    else if (face < 4u)
    {
        uAxis = 2u;
        vAxis = 0u;
        normalAxis = 1u;
    }
    else
    {
        uAxis = 0u;
        vAxis = 1u;
        normalAxis = 2u;
    }
}

uint GetFaceNeighborNodeIndex(VoxelActiveLeafNeighborTopology topology, uint face, uint quadrant)
{
    if (face == MC_FACE_NEG_X) return topology.negX[quadrant];
    if (face == MC_FACE_POS_X) return topology.posX[quadrant];
    if (face == MC_FACE_NEG_Y) return topology.negY[quadrant];
    if (face == MC_FACE_POS_Y) return topology.posY[quadrant];
    if (face == MC_FACE_NEG_Z) return topology.negZ[quadrant];
    return topology.posZ[quadrant];
}

uint GetFaceQuadrant(uint face, float3 localGridPosition)
{
    float halfResolution = (float)CellCount * 0.5f;
    // The octree topology builder numbers face quadrants using X/Z on Y faces;
    // the Transvoxel face basis uses Z/X there to keep its winding consistent.
    uint uHalf;
    uint vHalf;
    if (face == MC_FACE_NEG_Y || face == MC_FACE_POS_Y)
    {
        uHalf = localGridPosition.x >= halfResolution ? 1u : 0u;
        vHalf = localGridPosition.z >= halfResolution ? 1u : 0u;
    }
    else
    {
        uint uAxis;
        uint vAxis;
        uint normalAxis;
        GetFaceAxes(face, uAxis, vAxis, normalAxis);
        uHalf = localGridPosition[uAxis] >= halfResolution ? 1u : 0u;
        vHalf = localGridPosition[vAxis] >= halfResolution ? 1u : 0u;
    }
    return uHalf | (vHalf << 1u);
}

uint GetNeighborNodeAtFacePosition(
    VoxelActiveLeaf leaf,
    uint face,
    float3 localGridPosition)
{
    VoxelActiveLeafNeighborTopology topology =
        ActiveLeafNeighborTopologyReadBuffer[leaf.nodeIndex];
    uint quadrant = GetFaceQuadrant(face, localGridPosition);
    return GetFaceNeighborNodeIndex(topology, face, quadrant);
}

float3 EstimateDensityGradient(float3 position, float cellStep)
{
    float h = max(cellStep * 0.25f, BASE_LATTICE_SIZE * 0.01f);
    float3 gradient = float3(
        SampleDensity(position + float3(h, 0.0f, 0.0f)) - SampleDensity(position - float3(h, 0.0f, 0.0f)),
        SampleDensity(position + float3(0.0f, h, 0.0f)) - SampleDensity(position - float3(0.0f, h, 0.0f)),
        SampleDensity(position + float3(0.0f, 0.0f, h)) - SampleDensity(position - float3(0.0f, 0.0f, h))
    );
    return SafeNormalize(gradient, float3(0.0f, 1.0f, 0.0f));
}

float3 OffsetRegularBoundaryVertex(VoxelActiveLeaf leaf, float3 position, float cellStep)
{
    float3 localGrid = (position - GetLeafOrigin(leaf)) / cellStep;
    const float edgeEpsilon = 0.0001f;
    [unroll]
    for (uint face = 0u; face < 6u; ++face)
    {
        uint uAxis;
        uint vAxis;
        uint normalAxis;
        GetFaceAxes(face, uAxis, vAxis, normalAxis);

        bool onNegativeFace = (face & 1u) == 0u && abs(localGrid[normalAxis]) <= edgeEpsilon;
        bool onPositiveFace = (face & 1u) != 0u && abs(localGrid[normalAxis] - (float)CellCount) <= edgeEpsilon;
        if (!onNegativeFace && !onPositiveFace)
            continue;

        uint neighborIndex = GetNeighborNodeAtFacePosition(leaf, face, localGrid);
        if (neighborIndex == MC_NODE_INVALID || neighborIndex >= (uint)MaxOctreeNodes)
            continue;

        VoxelOctreeNode neighbor = OctreeNodeReadBuffer[neighborIndex];
        if (neighbor.state != OCTREE_NODE_LEAF || neighbor.lod == (int)leaf.lod)
            continue;

        float neighborStep = BASE_LATTICE_SIZE * exp2((float)neighbor.lod);
        float transitionWidth = min(cellStep, neighborStep) *
            ((float)MC_TRANSITION_CELL_SCALE_NUMERATOR / (float)MC_TRANSITION_CELL_SCALE_DENOMINATOR);
        position -= GetFaceNormal(face) * transitionWidth;
    }
    return position;
}

void GetRegularCellSamples(
    VoxelActiveLeaf leaf,
    uint3 cell,
    out float3 positions[8],
    out float densities[8],
    float step)
{
    float3 origin = GetLeafOrigin(leaf) + (float3)cell * step;
    positions[0] = origin;
    positions[1] = origin + float3(step, 0.0f, 0.0f);
    positions[2] = origin + float3(0.0f, step, 0.0f);
    positions[3] = origin + float3(step, step, 0.0f);
    positions[4] = origin + float3(0.0f, 0.0f, step);
    positions[5] = origin + float3(step, 0.0f, step);
    positions[6] = origin + float3(0.0f, step, step);
    positions[7] = origin + float3(step, step, step);

    [unroll]
    for (uint i = 0u; i < 8u; ++i)
        densities[i] = SampleDensity(positions[i]);
}

uint GetRegularCase(float densities[8])
{
    uint caseCode = 0u;
    [unroll]
    for (uint i = 0u; i < 8u; ++i)
        if (densities[i] < 0.0f)
            caseCode |= 1u << i;
    return caseCode;
}

uint GetRegularTriangleCount(uint caseCode)
{
    uint equivalenceClass = RegularCellClassTable[caseCode] & 0x7Fu;
    uint geometry = RegularCellDataTable[equivalenceClass * 16u];
    return geometry & 0x0Fu;
}

uint GetTransitionTriangleCount(uint caseCode)
{
    uint equivalenceClass = TransitionCellClassTable[caseCode] & 0x7Fu;
    uint geometry = TransitionCellDataTable[equivalenceClass * 37u];
    return geometry & 0x0Fu;
}

void GetTransitionSampleLocalPosition(
    uint face,
    uint cellU,
    uint cellV,
    uint sampleIndex,
    out float3 localGrid)
{
    uint uAxis;
    uint vAxis;
    uint normalAxis;
    GetFaceAxes(face, uAxis, vAxis, normalAxis);

    uint sampleU = sampleIndex % 3u;
    uint sampleV = sampleIndex / 3u;
    localGrid = 0.0f;
    localGrid[uAxis] = (float)(cellU * 2u + sampleU);
    localGrid[vAxis] = (float)(cellV * 2u + sampleV);
    localGrid[normalAxis] = (face & 1u) == 0u ? 0.0f : (float)CellCount;
}

uint GetTransitionCase(float densities[13])
{
    // The official table bit order differs from row-major sample order.
    uint caseCode = 0u;
    if (densities[0] < 0.0f) caseCode |= 1u << 0u;
    if (densities[1] < 0.0f) caseCode |= 1u << 1u;
    if (densities[2] < 0.0f) caseCode |= 1u << 2u;
    if (densities[5] < 0.0f) caseCode |= 1u << 3u;
    if (densities[8] < 0.0f) caseCode |= 1u << 4u;
    if (densities[7] < 0.0f) caseCode |= 1u << 5u;
    if (densities[6] < 0.0f) caseCode |= 1u << 6u;
    if (densities[3] < 0.0f) caseCode |= 1u << 7u;
    if (densities[4] < 0.0f) caseCode |= 1u << 8u;
    return caseCode;
}

bool GetTransitionSamples(
    VoxelActiveLeaf leaf,
    uint face,
    uint cellU,
    uint cellV,
    out float3 positions[13],
    out float densities[13],
    out float3 gradients[13],
    out uint caseCode)
{
    float step = GetLeafStep(leaf);
    uint quadrant;
    if (face == MC_FACE_NEG_Y || face == MC_FACE_POS_Y)
        quadrant = (cellV >= (uint)CellCount / 4u ? 1u : 0u) |
            ((cellU >= (uint)CellCount / 4u ? 1u : 0u) << 1u);
    else
        quadrant = (cellU >= (uint)CellCount / 4u ? 1u : 0u) |
            ((cellV >= (uint)CellCount / 4u ? 1u : 0u) << 1u);
    VoxelActiveLeafNeighborTopology topology =
        ActiveLeafNeighborTopologyReadBuffer[leaf.nodeIndex];
    uint neighborIndex = GetFaceNeighborNodeIndex(topology, face, quadrant);
    caseCode = 0u;

    if (neighborIndex == MC_NODE_INVALID || neighborIndex >= (uint)MaxOctreeNodes)
        return false;
    VoxelOctreeNode neighbor = OctreeNodeReadBuffer[neighborIndex];
    if (neighbor.state != OCTREE_NODE_LEAF || neighbor.lod <= (int)leaf.lod)
        return false;

    float coarseStep = BASE_LATTICE_SIZE * exp2((float)neighbor.lod);
    float width = min(step, coarseStep) *
        ((float)MC_TRANSITION_CELL_SCALE_NUMERATOR / (float)MC_TRANSITION_CELL_SCALE_DENOMINATOR);
    float3 outward = GetFaceNormal(face);
    float3 leafOrigin = GetLeafOrigin(leaf);

    [unroll]
    for (uint sampleIndex = 0u; sampleIndex < 9u; ++sampleIndex)
    {
        float3 localGrid;
        GetTransitionSampleLocalPosition(face, cellU, cellV, sampleIndex, localGrid);
        float3 boundaryPosition = leafOrigin + localGrid * step;
        densities[sampleIndex] = SampleDensity(boundaryPosition);
        gradients[sampleIndex] = EstimateDensityGradient(boundaryPosition, step);
        positions[sampleIndex] = boundaryPosition - outward * width;
    }

    densities[9] = densities[0];
    densities[10] = densities[2];
    densities[11] = densities[6];
    densities[12] = densities[8];
    gradients[9] = gradients[0];
    gradients[10] = gradients[2];
    gradients[11] = gradients[6];
    gradients[12] = gradients[8];
    positions[9] = positions[0] + outward * (2.0f * width);
    positions[10] = positions[2] + outward * (2.0f * width);
    positions[11] = positions[6] + outward * (2.0f * width);
    positions[12] = positions[8] + outward * (2.0f * width);

    caseCode = GetTransitionCase(densities);
    return caseCode != 0u && caseCode != 511u;
}

void InterpolateEdge(
    float3 positionA,
    float3 positionB,
    float densityA,
    float densityB,
    float3 normalA,
    float3 normalB,
    out float3 position,
    out float3 normal)
{
    float denominator = densityA - densityB;
    float t = abs(denominator) > INTERSECTION_EPSILON
        ? saturate(densityA / denominator)
        : 0.5f;
    position = lerp(positionA, positionB, t);
    normal = SafeNormalize(lerp(normalA, normalB, t), float3(0.0f, 1.0f, 0.0f));
}

void WriteTriangle(
    uint leafSlot,
    VoxelLeafMeshInfo info,
    float3 p0,
    float3 n0,
    float3 p1,
    float3 n1,
    float3 p2,
    float3 n2)
{
    if (dot(cross(p1 - p0, p2 - p0), n0 + n1 + n2) < 0.0f)
    {
        float3 pSwap = p1;
        p1 = p2;
        p2 = pSwap;
        float3 nSwap = n1;
        n1 = n2;
        n2 = nSwap;
    }

    uint writeOffset;
    InterlockedAdd(ActiveLeafMeshVertexCounterBuffer[leafSlot], 3u, writeOffset);
    if (writeOffset + 3u > info.vertexCapacity || writeOffset + 3u > info.indexCapacity)
    {
        InterlockedOr(MeshOverflowFlagsBuffer[0], MESH_OVERFLOW_INDEX_WRITE);
        return;
    }

    uint globalIndex0 = info.vertexBase + writeOffset;
    uint globalIndex1 = globalIndex0 + 1u;
    uint globalIndex2 = globalIndex0 + 2u;
    VertexBuffer[globalIndex0] = p0;
    VertexBuffer[globalIndex1] = p1;
    VertexBuffer[globalIndex2] = p2;
    NormalBuffer[globalIndex0] = n0;
    NormalBuffer[globalIndex1] = n1;
    NormalBuffer[globalIndex2] = n2;
    IndexBuffer[info.indexBase + writeOffset] = globalIndex0;
    IndexBuffer[info.indexBase + writeOffset + 1u] = globalIndex1;
    IndexBuffer[info.indexBase + writeOffset + 2u] = globalIndex2;
}

void CountRegularCell(VoxelActiveLeaf leaf, uint3 cell, inout uint vertexCount)
{
    float3 positions[8];
    float densities[8];
    GetRegularCellSamples(leaf, cell, positions, densities, GetLeafStep(leaf));
    uint caseCode = GetRegularCase(densities);
    vertexCount += GetRegularTriangleCount(caseCode) * 3u;
}

void BuildRegularCell(uint leafSlot, VoxelActiveLeaf leaf, uint3 cell, VoxelLeafMeshInfo info)
{
    float step = GetLeafStep(leaf);
    float3 cornerPositions[8];
    float cornerDensities[8];
    GetRegularCellSamples(leaf, cell, cornerPositions, cornerDensities, step);

    uint caseCode = GetRegularCase(cornerDensities);
    uint cellClass = RegularCellClassTable[caseCode];
    uint classIndex = cellClass & 0x7Fu;
    uint classOffset = classIndex * 16u;
    uint geometry = RegularCellDataTable[classOffset];
    uint triangleCount = geometry & 0x0Fu;
    if (triangleCount == 0u)
        return;

    float3 edgePositions[12];
    float3 edgeNormals[12];
    uint edgeReady[12];
    float3 cornerGradients[8];
    uint gradientReady[8];
    [unroll]
    for (uint clearIndex = 0u; clearIndex < MC_MAX_REGULAR_VERTICES; ++clearIndex)
        edgeReady[clearIndex] = 0u;
    [unroll]
    for (uint gradientIndex = 0u; gradientIndex < 8u; ++gradientIndex)
        gradientReady[gradientIndex] = 0u;

    [loop]
    for (uint triangleIndex = 0u; triangleIndex < triangleCount; ++triangleIndex)
    {
        float3 trianglePositions[3];
        float3 triangleNormals[3];
        [unroll]
        for (uint corner = 0u; corner < 3u; ++corner)
        {
            uint localVertex = RegularCellDataTable[classOffset + 1u + triangleIndex * 3u + corner];
            if (localVertex >= MC_MAX_REGULAR_VERTICES)
                return;

            if (edgeReady[localVertex] == 0u)
            {
                uint edgeCode = RegularVertexDataTable[caseCode * MC_MAX_REGULAR_VERTICES + localVertex];
                uint cornerA = (edgeCode >> 4u) & 0x0Fu;
                uint cornerB = edgeCode & 0x0Fu;
                if (cornerA >= 8u || cornerB >= 8u)
                    return;

                float3 position;
                float3 normal;
                if (gradientReady[cornerA] == 0u)
                {
                    cornerGradients[cornerA] = EstimateDensityGradient(cornerPositions[cornerA], step);
                    gradientReady[cornerA] = 1u;
                }
                if (gradientReady[cornerB] == 0u)
                {
                    cornerGradients[cornerB] = EstimateDensityGradient(cornerPositions[cornerB], step);
                    gradientReady[cornerB] = 1u;
                }
                InterpolateEdge(
                    cornerPositions[cornerA],
                    cornerPositions[cornerB],
                    cornerDensities[cornerA],
                    cornerDensities[cornerB],
                    cornerGradients[cornerA],
                    cornerGradients[cornerB],
                    position,
                    normal
                );
                edgePositions[localVertex] = OffsetRegularBoundaryVertex(leaf, position, step);
                edgeNormals[localVertex] = normal;
                edgeReady[localVertex] = 1u;
            }

            trianglePositions[corner] = edgePositions[localVertex];
            triangleNormals[corner] = edgeNormals[localVertex];
        }

        WriteTriangle(
            leafSlot,
            info,
            trianglePositions[0], triangleNormals[0],
            trianglePositions[1], triangleNormals[1],
            trianglePositions[2], triangleNormals[2]
        );
    }
}

uint CountTransitionCell(VoxelActiveLeaf leaf, uint face, uint cellU, uint cellV)
{
    float3 positions[13];
    float densities[13];
    float3 gradients[13];
    uint caseCode;
    if (!GetTransitionSamples(leaf, face, cellU, cellV, positions, densities, gradients, caseCode))
        return 0u;
    return GetTransitionTriangleCount(caseCode) * 3u;
}

void BuildTransitionCell(
    uint leafSlot,
    VoxelActiveLeaf leaf,
    uint face,
    uint cellU,
    uint cellV,
    VoxelLeafMeshInfo info)
{
    float3 positions[13];
    float densities[13];
    float3 gradients[13];
    uint caseCode;
    if (!GetTransitionSamples(leaf, face, cellU, cellV, positions, densities, gradients, caseCode))
        return;

    uint cellClass = TransitionCellClassTable[caseCode];
    uint classIndex = cellClass & 0x7Fu;
    uint classOffset = classIndex * 37u;
    uint geometry = TransitionCellDataTable[classOffset];
    uint triangleCount = geometry & 0x0Fu;
    [loop]
    for (uint triangleIndex = 0u; triangleIndex < triangleCount; ++triangleIndex)
    {
        float3 trianglePositions[3];
        float3 triangleNormals[3];
        [unroll]
        for (uint corner = 0u; corner < 3u; ++corner)
        {
            uint localVertex = TransitionCellDataTable[classOffset + 1u + triangleIndex * 3u + corner];
            if (localVertex >= 12u)
                return;
            uint edgeCode = TransitionVertexDataTable[caseCode * 12u + localVertex];
            uint cornerA = (edgeCode >> 4u) & 0x0Fu;
            uint cornerB = edgeCode & 0x0Fu;
            if (cornerA >= 13u || cornerB >= 13u)
                return;
            InterpolateEdge(
                positions[cornerA], positions[cornerB],
                densities[cornerA], densities[cornerB],
                gradients[cornerA], gradients[cornerB],
                trianglePositions[corner], triangleNormals[corner]
            );
        }

        WriteTriangle(
            leafSlot,
            info,
            trianglePositions[0], triangleNormals[0],
            trianglePositions[1], triangleNormals[1],
            trianglePositions[2], triangleNormals[2]
        );
    }
}

void CSResetLeafMeshImpl(uint3 id : SV_DispatchThreadID)
{
    uint index = id.x;
    if (index < (uint)MaxActiveLeaves)
    {
        VoxelLeafMeshInfo info;
        info.nodeIndex = MC_NODE_INVALID;
        info.vertexBase = 0u;
        info.vertexCapacity = 0u;
        info.vertexCount = 0u;
        info.indexBase = 0u;
        info.indexCapacity = 0u;
        info.indexCount = 0u;
        ActiveLeafMeshInfoBuffer[index] = info;
        ActiveLeafMeshVertexCounterBuffer[index] = 0u;
    }
    if (index == 0u)
    {
        VertexCountBuffer[0] = 0u;
        IndexCountBuffer[0] = 0u;
        MeshOverflowFlagsBuffer[0] = 0u;
    }
}

void CSCountLeafMeshVerticesImpl(uint3 groupId : SV_GroupID, uint3 groupThreadId : SV_GroupThreadID)
{
    uint leafSlot = GetLeafSlot(groupId);
    if (!IsActiveLeafSlot(leafSlot)) return;

    VoxelActiveLeaf leaf = ActiveLeafReadBuffer[leafSlot];
    uint resolution = (uint)CellCount;
    uint totalCells = resolution * resolution * resolution;
    uint localCount = 0u;
    [loop]
    for (uint linearIndex = groupThreadId.x; linearIndex < totalCells; linearIndex += 128u)
    {
        uint x = linearIndex % resolution;
        uint y = (linearIndex / resolution) % resolution;
        uint z = linearIndex / (resolution * resolution);
        CountRegularCell(leaf, uint3(x, y, z), localCount);
    }

    uint halfResolution = resolution / MC_TRANSITION_HALF_RES;
    uint transitionCellsPerFace = halfResolution * halfResolution;
    for (uint transitionIndex = groupThreadId.x; transitionIndex < transitionCellsPerFace * 6u; transitionIndex += 128u)
    {
        uint face = transitionIndex / transitionCellsPerFace;
        uint cellIndex = transitionIndex % transitionCellsPerFace;
        uint cellU = cellIndex % halfResolution;
        uint cellV = cellIndex / halfResolution;
        localCount += CountTransitionCell(leaf, face, cellU, cellV);
    }

    if (localCount > 0u)
        InterlockedAdd(ActiveLeafMeshVertexCounterBuffer[leafSlot], localCount);
}

void CSScanLeafMeshVertexOffsetsImpl(uint3 id : SV_DispatchThreadID)
{
    if (id.x != 0u) return;
    uint activeCount = min(ActiveLeafCountReadBuffer[0], (uint)MaxActiveLeaves);
    uint cursor = 0u;
    uint arenaCapacity = min((uint)MeshVertexArenaCapacity, (uint)MeshIndexArenaCapacity);

    [loop]
    for (uint leafSlot = 0u; leafSlot < activeCount; ++leafSlot)
    {
        uint requested = ActiveLeafMeshVertexCounterBuffer[leafSlot];
        VoxelActiveLeaf leaf = ActiveLeafReadBuffer[leafSlot];
        VoxelLeafMeshInfo info;
        info.nodeIndex = leaf.nodeIndex;
        info.vertexBase = cursor;
        info.indexBase = cursor;
        info.vertexCount = 0u;
        info.indexCount = 0u;
        uint available = cursor < arenaCapacity ? arenaCapacity - cursor : 0u;
        uint reserved = min(requested, available);
        reserved = (reserved / 3u) * 3u;
        info.vertexCapacity = reserved;
        info.indexCapacity = reserved;
        if (reserved < requested)
            InterlockedOr(MeshOverflowFlagsBuffer[0], MESH_OVERFLOW_VERTEX_ARENA | MESH_OVERFLOW_INDEX_ARENA);
        ActiveLeafMeshInfoBuffer[leafSlot] = info;
        ActiveLeafMeshVertexCounterBuffer[leafSlot] = 0u;
        cursor += reserved;
    }
    VertexCountBuffer[0] = 0u;
    IndexCountBuffer[0] = 0u;
}

void CSBuildVerticesImpl(uint3 groupId : SV_GroupID, uint3 groupThreadId : SV_GroupThreadID)
{
    uint leafSlot = GetLeafSlot(groupId);
    if (!IsActiveLeafSlot(leafSlot)) return;

    VoxelActiveLeaf leaf = ActiveLeafReadBuffer[leafSlot];
    VoxelLeafMeshInfo info = ActiveLeafMeshInfoReadBuffer[leafSlot];
    uint resolution = (uint)CellCount;
    uint totalCells = resolution * resolution * resolution;

    [loop]
    for (uint linearIndex = groupThreadId.x; linearIndex < totalCells; linearIndex += 128u)
    {
        uint x = linearIndex % resolution;
        uint y = (linearIndex / resolution) % resolution;
        uint z = linearIndex / (resolution * resolution);
        BuildRegularCell(leafSlot, leaf, uint3(x, y, z), info);
    }

    uint halfResolution = resolution / MC_TRANSITION_HALF_RES;
    uint transitionCellsPerFace = halfResolution * halfResolution;
    for (uint transitionIndex = groupThreadId.x; transitionIndex < transitionCellsPerFace * 6u; transitionIndex += 128u)
    {
        uint face = transitionIndex / transitionCellsPerFace;
        uint cellIndex = transitionIndex % transitionCellsPerFace;
        uint cellU = cellIndex % halfResolution;
        uint cellV = cellIndex / halfResolution;
        BuildTransitionCell(leafSlot, leaf, face, cellU, cellV, info);
    }
}

void CSFinalizeLeafMeshImpl(uint3 id : SV_DispatchThreadID)
{
    if (id.x != 0u) return;
    uint activeCount = min(ActiveLeafCountReadBuffer[0], (uint)MaxActiveLeaves);
    uint totalVertexCount = 0u;
    [loop]
    for (uint leafSlot = 0u; leafSlot < activeCount; ++leafSlot)
    {
        VoxelLeafMeshInfo info = ActiveLeafMeshInfoBuffer[leafSlot];
        uint count = min(ActiveLeafMeshVertexCounterBuffer[leafSlot], info.vertexCapacity);
        count = (count / 3u) * 3u;
        info.vertexCount = count;
        info.indexCount = count;
        ActiveLeafMeshInfoBuffer[leafSlot] = info;
        totalVertexCount += count;
    }
    VertexCountBuffer[0] = totalVertexCount;
    IndexCountBuffer[0] = totalVertexCount;
}

#endif
