#ifndef VOXEL_DENSITY_MESH_INTERNAL_FACES_INCLUDED
#define VOXEL_DENSITY_MESH_INTERNAL_FACES_INCLUDED

#include "VoxelDensityTypes.hlsl"
#include "VoxelDensityMeshCommon.hlsl"
#include "VoxelDensityMeshBoundary.hlsl"


void CSCountLeafMeshIndicesImpl(
    uint3 groupId : SV_GroupID,
    uint3 groupThreadId : SV_GroupThreadID)
{
    uint leafSlot = GetLeafSlot(groupId);
    if (!IsActiveLeafSlot(leafSlot)) return;

    int resolution = CellCount;
    if (resolution < 2) return;

    VoxelActiveLeaf leaf = ActiveLeafBuffer[leafSlot];
    float leafStep = GetLeafStep(leaf);
    float3 leafOrigin = GetLeafOrigin(leaf);

    uint resolutionU = (uint) resolution;
    uint minorResolution = resolutionU - 1u;
    uint edgesPerAxis = resolutionU * minorResolution * minorResolution;
    uint totalEdges = edgesPerAxis * 3u;
    uint localIndexCount = 0u;
    uint threadIndex = groupThreadId.x;

    for (uint linearIndex = threadIndex;
         linearIndex < totalEdges;
         linearIndex += LEAF_MESH_THREADS_PER_LEAF)
    {
        uint orientation = linearIndex / edgesPerAxis;
        uint edgeIndex = linearIndex - orientation * edgesPerAxis;

        int x;
        int y;
        int z;

        if (orientation == 0u)
        {
            uint xU = edgeIndex % resolutionU;
            uint yz = edgeIndex / resolutionU;
            uint yU = yz % minorResolution;
            uint zU = yz / minorResolution;

            x = (int) xU;
            y = (int) yU + 1;
            z = (int) zU + 1;
        }
        else if (orientation == 1u)
        {
            uint yU = edgeIndex % resolutionU;
            uint xz = edgeIndex / resolutionU;
            uint xOffset = xz % minorResolution;
            uint zU = xz / minorResolution;

            x = (int) xOffset + 1;
            y = (int) yU;
            z = (int) zU + 1;
        }
        else
        {
            uint zU = edgeIndex % resolutionU;
            uint xy = edgeIndex / resolutionU;
            uint xOffset = xy % minorResolution;
            uint yOffset = xy / minorResolution;

            x = (int) xOffset + 1;
            y = (int) yOffset + 1;
            z = (int) zU;
        }

        float3 sampleA = leafOrigin + float3(x, y, z) * leafStep;
        float3 sampleB;

        if (orientation == 0u)
            sampleB = sampleA + float3(leafStep, 0.0f, 0.0f);
        else if (orientation == 1u)
            sampleB = sampleA + float3(0.0f, leafStep, 0.0f);
        else
            sampleB = sampleA + float3(0.0f, 0.0f, leafStep);

        float da = SampleDensity(sampleA);
        float db = SampleDensity(sampleB);

        if (IsSignChange(da, db)) localIndexCount += 6u;
    }

    VoxelActiveLeafNeighborTopology topology =
        ActiveLeafNeighborTopologyBuffer[leaf.nodeIndex];

    uint boundaryEdgeCount = resolutionU * minorResolution;
    uint boundaryOrientationCount = boundaryEdgeCount * 2u;
    uint boundaryQuadrantCount = boundaryOrientationCount * 4u;
    uint boundaryWorkCount = boundaryQuadrantCount * 6u;

    for (uint boundaryLinearIndex = threadIndex;
         boundaryLinearIndex < boundaryWorkCount;
         boundaryLinearIndex += LEAF_MESH_THREADS_PER_LEAF)
    {
        uint face;
        uint quadrant;
        uint orientation;
        uint edgeA;
        uint edgeB;

        DecodeBoundaryWorkIndex(
            boundaryLinearIndex,
            face,
            quadrant,
            orientation,
            edgeA,
            edgeB);

        uint neighborNodeIndex = GetBoundaryNeighborNodeIndex(topology, face, quadrant);
        if (neighborNodeIndex == VOXEL_INVALID_NODE_INDEX) continue;
        if (neighborNodeIndex >= (uint) MaxOctreeNodes) continue;
        if (IsDuplicateBoundaryNeighbor(topology, face, quadrant, neighborNodeIndex)) continue;

        uint neighborLeafSlot;
        if (!TryResolveBoundaryNeighborSlot(neighborNodeIndex, neighborLeafSlot)) continue;

        VoxelActiveLeaf neighborLeaf = ActiveLeafBuffer[neighborLeafSlot];
        int lodDelta = (int) leaf.lod - (int) neighborLeaf.lod;

        if (lodDelta == 0)
        {
            if ((face & 1u) == 0u) continue;

            float3 p0;
            float3 p1;
            GetBoundaryFaceEdgePoints(
                leaf, face, orientation, edgeA, edgeB, p0, p1);

            float da = SampleDensity(p0);
            float db = SampleDensity(p1);
            if (IsSignChange(da, db)) localIndexCount += 6u;
        }
        else if (lodDelta == 1)
        {
            float3 p0;
            float3 p1;
            GetBoundaryFaceEdgePoints(
                neighborLeaf,
                face ^ 1u,
                orientation,
                edgeA,
                edgeB,
                p0,
                p1);

            float da = SampleDensity(p0);
            float db = SampleDensity(p1);
            if (IsSignChange(da, db)) localIndexCount += 6u;
        }
    }

    uint intersectionWorkCount = resolutionU * 3u;

    for (uint intersectionLinearIndex = threadIndex;
         intersectionLinearIndex < intersectionWorkCount;
         intersectionLinearIndex += LEAF_MESH_THREADS_PER_LEAF)
    {
        uint intersectionFace;
        uint intersectionOrientation;
        uint intersectionEdgeA;

        DecodeBoundaryIntersectionWorkIndex(
            intersectionLinearIndex,
            resolutionU,
            intersectionFace,
            intersectionOrientation,
            intersectionEdgeA);

        if (IsSameLodBoundaryIntersectionEdge(
            leaf,
            topology,
            intersectionFace,
            intersectionOrientation,
            intersectionEdgeA))
        {
            localIndexCount += 6u;
        }
    }

    if (localIndexCount > 0u)
    {
        InterlockedAdd(
            ActiveLeafMeshIndexCounterBuffer[leafSlot],
            localIndexCount
        );
    }
}

void CSScanLeafMeshIndexOffsetsImpl(uint3 id : SV_DispatchThreadID)
{
    if (id.x != 0u) return;

    uint activeCount = ActiveLeafCountBuffer[0];
    uint safeActiveCount = min(activeCount, (uint) MaxActiveLeaves);
    uint arenaCursor = 0u;
    uint arenaCapacity = (uint) MeshIndexArenaCapacity;

    for (uint leafSlot = 0u; leafSlot < safeActiveCount; ++leafSlot)
    {
        uint requestedCapacity = ActiveLeafMeshIndexCounterBuffer[leafSlot];
        VoxelLeafMeshInfo info = ActiveLeafMeshInfoBuffer[leafSlot];

        info.indexBase = arenaCursor;
        info.indexCount = 0u;

        uint available = 0u;
        if (arenaCursor < arenaCapacity)
            available = arenaCapacity - arenaCursor;

        uint reservedCapacity = min(requestedCapacity, available);
        reservedCapacity = (reservedCapacity / 6u) * 6u;
        info.indexCapacity = reservedCapacity;

        if (reservedCapacity < requestedCapacity)
        {
            InterlockedOr(
                MeshOverflowFlagsBuffer[0],
                MESH_OVERFLOW_INDEX_ARENA
            );
        }

        ActiveLeafMeshInfoBuffer[leafSlot] = info;
        ActiveLeafMeshIndexCounterBuffer[leafSlot] = 0u;
        arenaCursor += reservedCapacity;
    }

    IndexCountBuffer[0] = 0u;
}

void AddLeafQuad(
    uint leafSlot,
    uint a, uint b, uint c, uint d,
    float densityA, float densityB,
    bool positiveAxis)
{
    uint localIndexOffset;
    InterlockedAdd(
        ActiveLeafMeshIndexCounterBuffer[leafSlot],
        6u,
        localIndexOffset
    );

    VoxelLeafMeshInfo info = ActiveLeafMeshInfoBuffer[leafSlot];
    if (info.indexCapacity < 6u) return;
    if (localIndexOffset > info.indexCapacity - 6u) return;

    uint globalIndexBase = info.indexBase + localIndexOffset;
    bool densityAscending = densityA < densityB;

    if (positiveAxis)
    {
        if (densityAscending)
        {
            IndexBuffer[globalIndexBase + 0u] = a;
            IndexBuffer[globalIndexBase + 1u] = b;
            IndexBuffer[globalIndexBase + 2u] = c;
            IndexBuffer[globalIndexBase + 3u] = a;
            IndexBuffer[globalIndexBase + 4u] = c;
            IndexBuffer[globalIndexBase + 5u] = d;
        }
        else
        {
            IndexBuffer[globalIndexBase + 0u] = a;
            IndexBuffer[globalIndexBase + 1u] = d;
            IndexBuffer[globalIndexBase + 2u] = c;
            IndexBuffer[globalIndexBase + 3u] = a;
            IndexBuffer[globalIndexBase + 4u] = c;
            IndexBuffer[globalIndexBase + 5u] = b;
        }
    }
    else
    {
        if (densityAscending)
        {
            IndexBuffer[globalIndexBase + 0u] = a;
            IndexBuffer[globalIndexBase + 1u] = d;
            IndexBuffer[globalIndexBase + 2u] = c;
            IndexBuffer[globalIndexBase + 3u] = a;
            IndexBuffer[globalIndexBase + 4u] = c;
            IndexBuffer[globalIndexBase + 5u] = b;
        }
        else
        {
            IndexBuffer[globalIndexBase + 0u] = a;
            IndexBuffer[globalIndexBase + 1u] = b;
            IndexBuffer[globalIndexBase + 2u] = c;
            IndexBuffer[globalIndexBase + 3u] = a;
            IndexBuffer[globalIndexBase + 4u] = c;
            IndexBuffer[globalIndexBase + 5u] = d;
        }
    }
}

void BuildLeafAxisFacesImpl(
    uint3 groupId,
    uint3 groupThreadId,
    uint axis)
{
    uint leafSlot = GetLeafSlot(groupId);
    if (!IsActiveLeafSlot(leafSlot)) return;

    VoxelActiveLeaf leaf = ActiveLeafBuffer[leafSlot];
    int resolution = CellCount;
    if (resolution < 2) return;

    float leafStep = GetLeafStep(leaf);
    float3 leafOrigin = GetLeafOrigin(leaf);
    uint resolutionU = (uint) resolution;
    uint minorResolution = resolutionU - 1u;
    uint edgesPerAxis = resolutionU * minorResolution * minorResolution;
    uint threadIndex = groupThreadId.x;

    for (uint edgeIndex = threadIndex;
         edgeIndex < edgesPerAxis;
         edgeIndex += LEAF_MESH_THREADS_PER_LEAF)
    {
        int x;
        int y;
        int z;
        float3 sampleA;
        float3 sampleB;

        if (axis == 0u)
        {
            uint xU = edgeIndex % resolutionU;
            uint yz = edgeIndex / resolutionU;
            uint yU = yz % minorResolution;
            uint zU = yz / minorResolution;

            x = (int) xU;
            y = (int) yU + 1;
            z = (int) zU + 1;

            sampleA = leafOrigin + float3((float)x, (float)y, (float)z) * leafStep;
            sampleB = sampleA + float3(leafStep, 0.0f, 0.0f);
        }
        else if (axis == 1u)
        {
            uint yU = edgeIndex % resolutionU;
            uint xz = edgeIndex / resolutionU;
            uint xU = xz % minorResolution;
            uint zU = xz / minorResolution;

            x = (int) xU + 1;
            y = (int) yU;
            z = (int) zU + 1;

            sampleA = leafOrigin + float3((float)x, (float)y, (float)z) * leafStep;
            sampleB = sampleA + float3(0.0f, leafStep, 0.0f);
        }
        else
        {
            uint zU = edgeIndex % resolutionU;
            uint xy = edgeIndex / resolutionU;
            uint xU = xy % minorResolution;
            uint yU = xy / minorResolution;

            x = (int) xU + 1;
            y = (int) yU + 1;
            z = (int) zU;

            sampleA = leafOrigin + float3((float)x, (float)y, (float)z) * leafStep;
            sampleB = sampleA + float3(0.0f, 0.0f, leafStep);
        }

        float densityA = SampleDensity(sampleA);
        float densityB = SampleDensity(sampleB);

        if (!IsFiniteFloat(densityA) || !IsFiniteFloat(densityB)) continue;
        if (!IsSignChange(densityA, densityB)) continue;

        int3 cellA;
        int3 cellB;
        int3 cellC;
        int3 cellD;

        if (axis == 0u)
        {
            cellA = int3(x, y - 1, z - 1);
            cellB = int3(x, y, z - 1);
            cellC = int3(x, y, z);
            cellD = int3(x, y - 1, z);
        }
        else if (axis == 1u)
        {
            cellA = int3(x - 1, y, z - 1);
            cellB = int3(x, y, z - 1);
            cellC = int3(x, y, z);
            cellD = int3(x - 1, y, z);
        }
        else
        {
            cellA = int3(x - 1, y - 1, z);
            cellB = int3(x, y - 1, z);
            cellC = int3(x, y, z);
            cellD = int3(x - 1, y, z);
        }

        int lastCell = resolution - 1;

        if (cellA.x < 0 || cellA.y < 0 || cellA.z < 0 ||
            cellB.x < 0 || cellB.y < 0 || cellB.z < 0 ||
            cellC.x < 0 || cellC.y < 0 || cellC.z < 0 ||
            cellD.x < 0 || cellD.y < 0 || cellD.z < 0)
            continue;

        if (cellA.x > lastCell || cellA.y > lastCell || cellA.z > lastCell ||
            cellB.x > lastCell || cellB.y > lastCell || cellB.z > lastCell ||
            cellC.x > lastCell || cellC.y > lastCell || cellC.z > lastCell ||
            cellD.x > lastCell || cellD.y > lastCell || cellD.z > lastCell)
            continue;

        uint localA = GetVertexIndex(cellA.x, cellA.y, cellA.z);
        uint localB = GetVertexIndex(cellB.x, cellB.y, cellB.z);
        uint localC = GetVertexIndex(cellC.x, cellC.y, cellC.z);
        uint localD = GetVertexIndex(cellD.x, cellD.y, cellD.z);

        uint globalA;
        uint globalB;
        uint globalC;
        uint globalD;

        bool validA = TryGetLeafVertex(leafSlot, localA, globalA);
        bool validB = TryGetLeafVertex(leafSlot, localB, globalB);
        bool validC = TryGetLeafVertex(leafSlot, localC, globalC);
        bool validD = TryGetLeafVertex(leafSlot, localD, globalD);

        if (!validA || !validB || !validC || !validD) continue;

        AddLeafQuad(
            leafSlot,
            globalA,
            globalB,
            globalC,
            globalD,
            densityA,
            densityB,
            axis != 1u
        );
    }
}

void CSBuildXFacesImpl(uint3 groupId, uint3 groupThreadId)
{
    BuildLeafAxisFacesImpl(groupId, groupThreadId, 0u);
}

void CSBuildYFacesImpl(uint3 groupId, uint3 groupThreadId)
{
    BuildLeafAxisFacesImpl(groupId, groupThreadId, 1u);
}

void CSBuildZFacesImpl(uint3 groupId, uint3 groupThreadId)
{
    BuildLeafAxisFacesImpl(groupId, groupThreadId, 2u);
}

#endif
