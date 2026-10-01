#ifndef VOXEL_DENSITY_MESH_BOUNDARY_INCLUDED
#define VOXEL_DENSITY_MESH_BOUNDARY_INCLUDED

#include "VoxelDensityTypes.hlsl"
#include "VoxelDensityMath.hlsl"
#include "VoxelDensityDensity.hlsl"
#include "VoxelDensityTopology.hlsl"
#include "VoxelDensityMeshCommon.hlsl"

uint GetBoundaryNeighborNodeIndex(VoxelActiveLeafNeighborTopology topology, uint face, uint quadrant)
{
    if (quadrant >= 4u)
        return VOXEL_INVALID_NODE_INDEX;

    if (face == 0u)
    {
        if (quadrant == 0u)
            return topology.negX.x;
        if (quadrant == 1u)
            return topology.negX.y;
        if (quadrant == 2u)
            return topology.negX.z;
        return topology.negX.w;
    }

    if (face == 1u)
    {
        if (quadrant == 0u)
            return topology.posX.x;
        if (quadrant == 1u)
            return topology.posX.y;
        if (quadrant == 2u)
            return topology.posX.z;
        return topology.posX.w;
    }

    if (face == 2u)
    {
        if (quadrant == 0u)
            return topology.negY.x;
        if (quadrant == 1u)
            return topology.negY.y;
        if (quadrant == 2u)
            return topology.negY.z;
        return topology.negY.w;
    }

    if (face == 3u)
    {
        if (quadrant == 0u)
            return topology.posY.x;
        if (quadrant == 1u)
            return topology.posY.y;
        if (quadrant == 2u)
            return topology.posY.z;
        return topology.posY.w;
    }

    if (face == 4u)
    {
        if (quadrant == 0u)
            return topology.negZ.x;
        if (quadrant == 1u)
            return topology.negZ.y;
        if (quadrant == 2u)
            return topology.negZ.z;
        return topology.negZ.w;
    }

    if (face == 5u)
    {
        if (quadrant == 0u)
            return topology.posZ.x;
        if (quadrant == 1u)
            return topology.posZ.y;
        if (quadrant == 2u)
            return topology.posZ.z;
        return topology.posZ.w;
    }

    return VOXEL_INVALID_NODE_INDEX;
}

bool IsDuplicateBoundaryNeighbor(VoxelActiveLeafNeighborTopology topology, uint face, uint quadrant, uint nodeIndex)
{
    if (quadrant == 0u)
        return false;

    for (uint q = 0u; q < quadrant; ++q)
    {
        uint previousNodeIndex = GetBoundaryNeighborNodeIndex(topology, face, q);
        if (previousNodeIndex == nodeIndex)
            return true;
    }

    return false;
}

bool TryResolveBoundaryNeighborSlot(uint neighborNodeIndex, out uint neighborLeafSlot)
{
    neighborLeafSlot = 0u;

    if (neighborNodeIndex == VOXEL_INVALID_NODE_INDEX)
        return false;
    if (neighborNodeIndex >= (uint) MaxOctreeNodes)
        return false;

    uint candidateSlot = ActiveLeafMeshSlotBuffer[neighborNodeIndex];
    if (candidateSlot >= (uint) MaxActiveLeaves)
        return false;

    VoxelLeafMeshInfo info = ActiveLeafMeshInfoBuffer[candidateSlot];
    if (info.nodeIndex != neighborNodeIndex)
        return false;

    neighborLeafSlot = candidateSlot;
    return true;
}

float3 GetBoundaryFaceSamplePoint(VoxelActiveLeaf leaf, uint face, uint orientation, uint s0, uint s1)
{
    float step = GetLeafStep(leaf);
    float3 origin = GetLeafOrigin(leaf);

    float normalCoordinate = ((face & 1u) != 0u) ? (float) CellCount : 0.0f;
    float3 local;

    if (face == 0u || face == 1u)
    {
        if (orientation == 0u)
            local = float3(normalCoordinate, (float) s0, (float) s1);
        else
            local = float3(normalCoordinate, (float) s1, (float) s0);
    }
    else if (face == 2u || face == 3u)
    {
        if (orientation == 0u)
            local = float3((float) s0, normalCoordinate, (float) s1);
        else
            local = float3((float) s1, normalCoordinate, (float) s0);
    }
    else
    {
        if (orientation == 0u)
            local = float3((float) s0, (float) s1, normalCoordinate);
        else
            local = float3((float) s1, (float) s0, normalCoordinate);
    }

    return origin + local * step;
}

void GetBoundaryFaceEdgePoints(
    VoxelActiveLeaf leaf,
    uint face,
    uint orientation,
    uint edgeA,
    uint edgeB,
    out float3 p0,
    out float3 p1)
{
    p0 = GetBoundaryFaceSamplePoint(leaf, face, orientation, edgeA, edgeB);
    p1 = GetBoundaryFaceSamplePoint(leaf, face, orientation, edgeA + 1u, edgeB);
}

void GetSameLodBoundaryCells(
    uint face, uint orientation, uint edgeA, uint edgeB,
    out int3 current0, out int3 current1,
    out int3 neighbor0, out int3 neighbor1)
{
    int lastCell = CellCount - 1;
    int currentNormal = ((face & 1u) != 0u) ? lastCell : 0;
    int neighborNormal = ((face & 1u) != 0u) ? 0 : lastCell;
    int tangentLow = (int) edgeB - 1;
    int tangentHigh = (int) edgeB;
    int edge = (int) edgeA;

    current0 = int3(0, 0, 0);
    current1 = int3(0, 0, 0);
    neighbor0 = int3(0, 0, 0);
    neighbor1 = int3(0, 0, 0);

    if (face == 0u || face == 1u)
    {
        if (orientation == 0u)
        {
            current0 = int3(currentNormal, edge, tangentLow);
            current1 = int3(currentNormal, edge, tangentHigh);
            neighbor0 = int3(neighborNormal, edge, tangentLow);
            neighbor1 = int3(neighborNormal, edge, tangentHigh);
        }
        else
        {
            current0 = int3(currentNormal, tangentLow, edge);
            current1 = int3(currentNormal, tangentHigh, edge);
            neighbor0 = int3(neighborNormal, tangentLow, edge);
            neighbor1 = int3(neighborNormal, tangentHigh, edge);
        }
        return;
    }

    if (face == 2u || face == 3u)
    {
        if (orientation == 0u)
        {
            current0 = int3(edge, currentNormal, tangentLow);
            current1 = int3(edge, currentNormal, tangentHigh);
            neighbor0 = int3(edge, neighborNormal, tangentLow);
            neighbor1 = int3(edge, neighborNormal, tangentHigh);
        }
        else
        {
            current0 = int3(tangentLow, currentNormal, edge);
            current1 = int3(tangentHigh, currentNormal, edge);
            neighbor0 = int3(tangentLow, neighborNormal, edge);
            neighbor1 = int3(tangentHigh, neighborNormal, edge);
        }
        return;
    }

    if (orientation == 0u)
    {
        current0 = int3(edge, tangentLow, currentNormal);
        current1 = int3(edge, tangentHigh, currentNormal);
        neighbor0 = int3(edge, tangentLow, neighborNormal);
        neighbor1 = int3(edge, tangentHigh, neighborNormal);
    }
    else
    {
        current0 = int3(tangentLow, edge, currentNormal);
        current1 = int3(tangentHigh, edge, currentNormal);
        neighbor0 = int3(tangentLow, edge, neighborNormal);
        neighbor1 = int3(tangentHigh, edge, neighborNormal);
    }
}

void GetFineBoundaryCells(
    uint face, uint orientation, uint edgeA, uint edgeB,
    out int3 fine0, out int3 fine1)
{
    int lastCell = CellCount - 1;
    int fineNormal = ((face & 1u) != 0u) ? 0 : lastCell;
    int tangentLow = (int) edgeB - 1;
    int tangentHigh = (int) edgeB;
    int edge = (int) edgeA;

    fine0 = int3(0, 0, 0);
    fine1 = int3(0, 0, 0);

    if (face == 0u || face == 1u)
    {
        if (orientation == 0u)
        {
            fine0 = int3(fineNormal, edge, tangentLow);
            fine1 = int3(fineNormal, edge, tangentHigh);
        }
        else
        {
            fine0 = int3(fineNormal, tangentLow, edge);
            fine1 = int3(fineNormal, tangentHigh, edge);
        }
        return;
    }

    if (face == 2u || face == 3u)
    {
        if (orientation == 0u)
        {
            fine0 = int3(edge, fineNormal, tangentLow);
            fine1 = int3(edge, fineNormal, tangentHigh);
        }
        else
        {
            fine0 = int3(tangentLow, fineNormal, edge);
            fine1 = int3(tangentHigh, fineNormal, edge);
        }
        return;
    }

    if (orientation == 0u)
    {
        fine0 = int3(edge, tangentLow, fineNormal);
        fine1 = int3(edge, tangentHigh, fineNormal);
    }
    else
    {
        fine0 = int3(tangentLow, edge, fineNormal);
        fine1 = int3(tangentHigh, edge, fineNormal);
    }
}

int3 MapFineCellToCoarseCell(VoxelActiveLeaf fineLeaf, int3 fineCell, VoxelActiveLeaf coarseLeaf)
{
    int fineStride = GetLODLatticeStride((int) fineLeaf.lod);
    int coarseStride = GetLODLatticeStride((int) coarseLeaf.lod);

    if (fineStride <= 0 || coarseStride <= 0)
        return int3(-1, -1, -1);

    int3 fineCellCanonicalOrigin = fineLeaf.canonicalOrigin + fineCell * fineStride;
    int3 relative = fineCellCanonicalOrigin - coarseLeaf.canonicalOrigin;
    float3 coarseCellFloat = floor((float3) relative / (float) coarseStride);
    int3 coarseCell = (int3) coarseCellFloat;

    int lastCell = CellCount - 1;
    coarseCell = clamp(coarseCell, int3(0, 0, 0), int3(lastCell, lastCell, lastCell));
    return coarseCell;
}

void DecodeBoundaryWorkIndex(
    uint linearIndex,
    out uint face, out uint quadrant, out uint orientation,
    out uint edgeA, out uint edgeB)
{
    uint resolutionU = (uint) CellCount;
    uint minorResolutionU = (resolutionU > 0u) ? resolutionU - 1u : 0u;
    uint edgeCount = resolutionU * minorResolutionU;
    uint orientationCount = edgeCount * 2u;
    uint quadrantCount = orientationCount * 4u;

    if (quadrantCount == 0u)
    {
        face = 0u;
        quadrant = 0u;
        orientation = 0u;
        edgeA = 0u;
        edgeB = 1u;
        return;
    }

    face = linearIndex / quadrantCount;
    uint faceRemainder = linearIndex - face * quadrantCount;
    quadrant = faceRemainder / orientationCount;
    uint quadrantRemainder = faceRemainder - quadrant * orientationCount;
    orientation = quadrantRemainder / edgeCount;
    uint edgeIndex = quadrantRemainder - orientation * edgeCount;

    edgeA = edgeIndex % resolutionU;
    edgeB = edgeIndex / resolutionU;
    edgeB += 1u;

    if (face >= 6u)
        face = 5u;
    if (quadrant >= 4u)
        quadrant = 3u;
    if (orientation >= 2u)
        orientation = 1u;
}

void DecodeBoundaryIntersectionWorkIndex(
    uint linearIndex,
    uint resolution,
    out uint face, out uint orientation, out uint edgeA)
{
    uint group = linearIndex / resolution;
    edgeA = linearIndex - group * resolution;

    if (group == 0u)
    {
        face = 2u;
        orientation = 0u;
        return;
    }

    if (group == 1u)
    {
        face = 0u;
        orientation = 0u;
        return;
    }

    face = 0u;
    orientation = 1u;
}

uint GetBoundaryIntersectionSecondFace(uint face, uint orientation)
{
    if (face == 2u && orientation == 0u)
        return 4u;
    if (face == 0u && orientation == 0u)
        return 4u;
    return 2u;
}

void GetBoundaryIntersectionCells(
    uint face, uint orientation, uint edgeA,
    out int3 currentCell,
    out int3 faceNeighborCell,
    out int3 secondNeighborCell,
    out int3 diagonalCell)
{
    int lastCell = CellCount - 1;

    if (face == 2u && orientation == 0u)
    {
        currentCell = int3((int) edgeA, 0, 0);
        faceNeighborCell = int3((int) edgeA, lastCell, 0);
        secondNeighborCell = int3((int) edgeA, 0, lastCell);
        diagonalCell = int3((int) edgeA, lastCell, lastCell);
        return;
    }

    if (face == 0u && orientation == 0u)
    {
        currentCell = int3(0, (int) edgeA, 0);
        faceNeighborCell = int3(lastCell, (int) edgeA, 0);
        secondNeighborCell = int3(0, (int) edgeA, lastCell);
        diagonalCell = int3(lastCell, (int) edgeA, lastCell);
        return;
    }

    currentCell = int3(0, 0, (int) edgeA);
    faceNeighborCell = int3(lastCell, 0, (int) edgeA);
    secondNeighborCell = int3(0, lastCell, (int) edgeA);
    diagonalCell = int3(lastCell, lastCell, (int) edgeA);
}

bool TryResolveBoundaryIntersectionLeafSlots(
    VoxelActiveLeafNeighborTopology topology,
    uint face,
    uint orientation,
    out uint faceNeighborSlot,
    out uint secondNeighborSlot,
    out uint diagonalSlot)
{
    faceNeighborSlot = 0u;
    secondNeighborSlot = 0u;
    diagonalSlot = 0u;

    uint secondFace = GetBoundaryIntersectionSecondFace(face, orientation);
    if (secondFace >= 6u)
        return false;

    uint faceNeighborNode = GetBoundaryNeighborNodeIndex(topology, face, 0u);
    if (!TryResolveBoundaryNeighborSlot(faceNeighborNode, faceNeighborSlot))
        return false;

    uint secondNeighborNode = GetBoundaryNeighborNodeIndex(topology, secondFace, 0u);
    if (!TryResolveBoundaryNeighborSlot(secondNeighborNode, secondNeighborSlot))
        return false;

    VoxelActiveLeafNeighborTopology faceNeighborTopology =
        ActiveLeafNeighborTopologyBuffer[faceNeighborNode];

    uint diagonalNode = GetBoundaryNeighborNodeIndex(
        faceNeighborTopology,
        secondFace,
        0u
    );

    if (!TryResolveBoundaryNeighborSlot(diagonalNode, diagonalSlot))
        return false;
    if (diagonalNode == VOXEL_INVALID_NODE_INDEX)
        return false;

    return true;
}

bool IsSameLodBoundaryIntersectionEdge(
    VoxelActiveLeaf currentLeaf,
    VoxelActiveLeafNeighborTopology topology,
    uint face, uint orientation, uint edgeA)
{
    uint faceNeighborSlot;
    uint secondNeighborSlot;
    uint diagonalSlot;

    if (!TryResolveBoundaryIntersectionLeafSlots(
        topology, face, orientation,
        faceNeighborSlot, secondNeighborSlot, diagonalSlot))
        return false;

    VoxelActiveLeaf faceNeighborLeaf = ActiveLeafBuffer[faceNeighborSlot];
    VoxelActiveLeaf secondNeighborLeaf = ActiveLeafBuffer[secondNeighborSlot];
    VoxelActiveLeaf diagonalLeaf = ActiveLeafBuffer[diagonalSlot];

    if (faceNeighborLeaf.lod != currentLeaf.lod)
        return false;
    if (secondNeighborLeaf.lod != currentLeaf.lod)
        return false;
    if (diagonalLeaf.lod != currentLeaf.lod)
        return false;

    float3 p0;
    float3 p1;
    GetBoundaryFaceEdgePoints(currentLeaf, face, orientation, edgeA, 0u, p0, p1);

    float da = SampleDensity(p0);
    float db = SampleDensity(p1);
    return IsSignChange(da, db);
}

float3 GetBoundaryExpectedNormal(float3 p0, float3 p1)
{
    float3 boundaryCenter = (p0 + p1) * 0.5f;
    float3 normal = EstimateNormal(boundaryCenter);
    return SafeNormalize(normal, float3(0.0f, 1.0f, 0.0f));
}

float3 GetBoundaryPolygonNormal(float3 p0, float3 p1, float3 p2, float3 p3)
{
    float3 normal = cross(p1 - p0, p2 - p0);
    float normalLengthSquared = dot(normal, normal);
    if (normalLengthSquared < 1e-12f)
        normal = cross(p2 - p0, p3 - p0);

    return SafeNormalize(normal, float3(0.0f, 1.0f, 0.0f));
}

bool ShouldReverseBoundaryPolygonWinding(
    float3 p0, float3 p1, float3 p2, float3 p3,
    float3 expectedNormal)
{
    float3 polygonNormal = GetBoundaryPolygonNormal(p0, p1, p2, p3);
    return dot(polygonNormal, expectedNormal) < 0.0f;
}

void WriteBoundaryTriangle(uint baseIndex, uint a, uint b, uint c)
{
    IndexBuffer[baseIndex + 0u] = a;
    IndexBuffer[baseIndex + 1u] = b;
    IndexBuffer[baseIndex + 2u] = c;
    IndexBuffer[baseIndex + 3u] = a;
    IndexBuffer[baseIndex + 4u] = c;
    IndexBuffer[baseIndex + 5u] = c;
}

void WriteBoundaryQuad(uint baseIndex, uint a, uint b, uint c, uint d)
{
    IndexBuffer[baseIndex + 0u] = a;
    IndexBuffer[baseIndex + 1u] = b;
    IndexBuffer[baseIndex + 2u] = c;
    IndexBuffer[baseIndex + 3u] = a;
    IndexBuffer[baseIndex + 4u] = c;
    IndexBuffer[baseIndex + 5u] = d;
}

void AppendBoundaryQuad(uint leafSlot, uint a, uint b, uint c, uint d)
{
    uint localIndexOffset;
    InterlockedAdd(ActiveLeafMeshIndexCounterBuffer[leafSlot], 6u, localIndexOffset);

    VoxelLeafMeshInfo info = ActiveLeafMeshInfoBuffer[leafSlot];
    if (info.indexCapacity < 6u)
        return;
    if (localIndexOffset > info.indexCapacity - 6u)
        return;

    uint baseIndex = info.indexBase + localIndexOffset;
    WriteBoundaryQuad(baseIndex, a, b, c, d);
}

void AppendBoundaryTriangle(uint leafSlot, uint a, uint b, uint c)
{
    uint localIndexOffset;
    InterlockedAdd(ActiveLeafMeshIndexCounterBuffer[leafSlot], 6u, localIndexOffset);

    VoxelLeafMeshInfo info = ActiveLeafMeshInfoBuffer[leafSlot];
    if (info.indexCapacity < 6u)
        return;
    if (localIndexOffset > info.indexCapacity - 6u)
        return;

    uint baseIndex = info.indexBase + localIndexOffset;
    WriteBoundaryTriangle(baseIndex, a, b, c);
}

void AppendBoundaryPolygon(
    uint leafSlot,
    uint a, uint b, uint c, uint d,
    bool validA, bool validB, bool validC, bool validD,
    bool reverseWinding)
{
    uint unique0 = 0u;
    uint unique1 = 0u;
    uint unique2 = 0u;
    uint unique3 = 0u;
    uint uniqueCount = 0u;

    if (validA)
    {
        unique0 = a;
        uniqueCount = 1u;
    }

    if (validB)
    {
        bool duplicate = validA && b == a;
        if (!duplicate)
        {
            if (uniqueCount == 0u)
            {
                unique0 = b;
                uniqueCount = 1u;
            }
            else if (uniqueCount == 1u)
            {
                unique1 = b;
                uniqueCount = 2u;
            }
        }
    }

    if (validC)
    {
        bool duplicateA = validA && c == a;
        bool duplicateB = validB && c == b;
        if (!duplicateA && !duplicateB)
        {
            if (uniqueCount == 0u)
            {
                unique0 = c;
                uniqueCount = 1u;
            }
            else if (uniqueCount == 1u)
            {
                unique1 = c;
                uniqueCount = 2u;
            }
            else if (uniqueCount == 2u)
            {
                unique2 = c;
                uniqueCount = 3u;
            }
        }
    }

    if (validD)
    {
        bool duplicateA = validA && d == a;
        bool duplicateB = validB && d == b;
        bool duplicateC = validC && d == c;
        if (!duplicateA && !duplicateB && !duplicateC)
        {
            if (uniqueCount == 0u)
            {
                unique0 = d;
                uniqueCount = 1u;
            }
            else if (uniqueCount == 1u)
            {
                unique1 = d;
                uniqueCount = 2u;
            }
            else if (uniqueCount == 2u)
            {
                unique2 = d;
                uniqueCount = 3u;
            }
            else if (uniqueCount == 3u)
            {
                unique3 = d;
                uniqueCount = 4u;
            }
        }
    }

    if (uniqueCount < 3u)
        return;

    if (reverseWinding)
    {
        if (uniqueCount == 3u)
        {
            uint tempTriangle = unique1;
            unique1 = unique2;
            unique2 = tempTriangle;
        }
        else
        {
            uint tempQuad = unique1;
            unique1 = unique3;
            unique3 = tempQuad;
        }
    }

    if (uniqueCount == 3u)
    {
        AppendBoundaryTriangle(leafSlot, unique0, unique1, unique2);
        return;
    }

    AppendBoundaryQuad(leafSlot, unique0, unique1, unique2, unique3);
}

void BuildSameLodBoundaryIntersectionEdge(
    uint currentLeafSlot,
    VoxelActiveLeaf currentLeaf,
    VoxelActiveLeafNeighborTopology topology,
    uint face, uint orientation, uint edgeA)
{
    uint faceNeighborSlot;
    uint secondNeighborSlot;
    uint diagonalSlot;

    if (!TryResolveBoundaryIntersectionLeafSlots(
        topology, face, orientation,
        faceNeighborSlot, secondNeighborSlot, diagonalSlot))
        return;

    VoxelActiveLeaf faceNeighborLeaf = ActiveLeafBuffer[faceNeighborSlot];
    VoxelActiveLeaf secondNeighborLeaf = ActiveLeafBuffer[secondNeighborSlot];
    VoxelActiveLeaf diagonalLeaf = ActiveLeafBuffer[diagonalSlot];

    if (faceNeighborLeaf.lod != currentLeaf.lod)
        return;
    if (secondNeighborLeaf.lod != currentLeaf.lod)
        return;
    if (diagonalLeaf.lod != currentLeaf.lod)
        return;

    float3 p0;
    float3 p1;
    GetBoundaryFaceEdgePoints(currentLeaf, face, orientation, edgeA, 0u, p0, p1);

    float da = SampleDensity(p0);
    float db = SampleDensity(p1);
    if (!IsSignChange(da, db))
        return;

    int3 currentCell;
    int3 faceNeighborCell;
    int3 secondNeighborCell;
    int3 diagonalCell;

    GetBoundaryIntersectionCells(
        face, orientation, edgeA,
        currentCell, faceNeighborCell, secondNeighborCell, diagonalCell);

    uint localCurrent = GetVertexIndex(currentCell.x, currentCell.y, currentCell.z);
    uint localFaceNeighbor = GetVertexIndex(faceNeighborCell.x, faceNeighborCell.y, faceNeighborCell.z);
    uint localSecondNeighbor = GetVertexIndex(secondNeighborCell.x, secondNeighborCell.y, secondNeighborCell.z);
    uint localDiagonal = GetVertexIndex(diagonalCell.x, diagonalCell.y, diagonalCell.z);

    uint currentVertex;
    uint faceNeighborVertex;
    uint secondNeighborVertex;
    uint diagonalVertex;

    bool validCurrent = TryGetLeafVertex(currentLeafSlot, localCurrent, currentVertex);
    bool validFaceNeighbor = TryGetLeafVertex(faceNeighborSlot, localFaceNeighbor, faceNeighborVertex);
    bool validSecondNeighbor = TryGetLeafVertex(secondNeighborSlot, localSecondNeighbor, secondNeighborVertex);
    bool validDiagonal = TryGetLeafVertex(diagonalSlot, localDiagonal, diagonalVertex);

    if (!validCurrent || !validFaceNeighbor || !validSecondNeighbor || !validDiagonal)
        return;

    float3 polygonP0 = GetCellWorldPosition(currentLeaf, currentCell);
    float3 polygonP1 = GetCellWorldPosition(faceNeighborLeaf, faceNeighborCell);
    float3 polygonP2 = GetCellWorldPosition(diagonalLeaf, diagonalCell);
    float3 polygonP3 = GetCellWorldPosition(secondNeighborLeaf, secondNeighborCell);

    float3 expectedNormal = GetBoundaryExpectedNormal(p0, p1);
    bool reverseWinding = ShouldReverseBoundaryPolygonWinding(
        polygonP0, polygonP1, polygonP2, polygonP3, expectedNormal);

    AppendBoundaryPolygon(
        currentLeafSlot,
        currentVertex,
        faceNeighborVertex,
        diagonalVertex,
        secondNeighborVertex,
        true, true, true, true,
        reverseWinding);
}

void BuildSameLodBoundaryEdge(
    uint currentLeafSlot,
    VoxelActiveLeaf currentLeaf,
    uint neighborLeafSlot,
    VoxelActiveLeaf neighborLeaf,
    uint face, uint orientation,
    uint edgeA, uint edgeB)
{
    float3 p0;
    float3 p1;
    GetBoundaryFaceEdgePoints(currentLeaf, face, orientation, edgeA, edgeB, p0, p1);

    float da = SampleDensity(p0);
    float db = SampleDensity(p1);
    if (!IsSignChange(da, db))
        return;

    int3 current0;
    int3 current1;
    int3 neighbor0;
    int3 neighbor1;

    GetSameLodBoundaryCells(
        face, orientation, edgeA, edgeB,
        current0, current1, neighbor0, neighbor1);

    float3 polygonP0 = GetCellWorldPosition(currentLeaf, current0);
    float3 polygonP1 = GetCellWorldPosition(currentLeaf, current1);
    float3 polygonP2 = GetCellWorldPosition(neighborLeaf, neighbor1);
    float3 polygonP3 = GetCellWorldPosition(neighborLeaf, neighbor0);

    float3 expectedNormal = GetBoundaryExpectedNormal(p0, p1);
    bool reverseWinding = ShouldReverseBoundaryPolygonWinding(
        polygonP0, polygonP1, polygonP2, polygonP3, expectedNormal);

    uint localCurrent0 = GetVertexIndex(current0.x, current0.y, current0.z);
    uint localCurrent1 = GetVertexIndex(current1.x, current1.y, current1.z);
    uint localNeighbor0 = GetVertexIndex(neighbor0.x, neighbor0.y, neighbor0.z);
    uint localNeighbor1 = GetVertexIndex(neighbor1.x, neighbor1.y, neighbor1.z);

    uint currentVertex0;
    uint currentVertex1;
    uint neighborVertex0;
    uint neighborVertex1;

    bool validCurrent0 = TryGetLeafVertex(currentLeafSlot, localCurrent0, currentVertex0);
    bool validCurrent1 = TryGetLeafVertex(currentLeafSlot, localCurrent1, currentVertex1);
    bool validNeighbor0 = TryGetLeafVertex(neighborLeafSlot, localNeighbor0, neighborVertex0);
    bool validNeighbor1 = TryGetLeafVertex(neighborLeafSlot, localNeighbor1, neighborVertex1);

    if (!validCurrent0 || !validCurrent1 || !validNeighbor0 || !validNeighbor1)
        return;

    AppendBoundaryPolygon(
        currentLeafSlot,
        currentVertex0,
        currentVertex1,
        neighborVertex1,
        neighborVertex0,
        true, true, true, true,
        reverseWinding);
}

void BuildCoarseFineTransitionEdge(
    uint coarseLeafSlot,
    VoxelActiveLeaf coarseLeaf,
    uint fineLeafSlot,
    VoxelActiveLeaf fineLeaf,
    uint face, uint orientation,
    uint edgeA, uint edgeB)
{
    if ((int) coarseLeaf.lod != (int) fineLeaf.lod + 1)
        return;

    // The primal edge is sampled on the fine side.  Its direction is the
    // canonical DC edge direction used by the ordinary mesh generator.
    float3 p0;
    float3 p1;
    GetBoundaryFaceEdgePoints(
        fineLeaf,
        face ^ 1u,
        orientation,
        edgeA,
        edgeB,
        p0,
        p1);

    float da = SampleDensity(p0);
    float db = SampleDensity(p1);
    if (!IsSignChange(da, db))
        return;

    int3 fineCell0;
    int3 fineCell1;
    GetFineBoundaryCells(
        face, orientation, edgeA, edgeB,
        fineCell0, fineCell1);

    int3 coarseCell0 = MapFineCellToCoarseCell(fineLeaf, fineCell0, coarseLeaf);
    int3 coarseCell1 = MapFineCellToCoarseCell(fineLeaf, fineCell1, coarseLeaf);

    uint localFine0 = GetVertexIndex(fineCell0.x, fineCell0.y, fineCell0.z);
    uint localFine1 = GetVertexIndex(fineCell1.x, fineCell1.y, fineCell1.z);
    uint localCoarse0 = GetVertexIndex(coarseCell0.x, coarseCell0.y, coarseCell0.z);
    uint localCoarse1 = GetVertexIndex(coarseCell1.x, coarseCell1.y, coarseCell1.z);

    uint fineVertex0;
    uint fineVertex1;
    uint coarseVertex0;
    uint coarseVertex1;

    bool validFine0 = TryGetLeafVertex(fineLeafSlot, localFine0, fineVertex0);
    bool validFine1 = TryGetLeafVertex(fineLeafSlot, localFine1, fineVertex1);
    bool validCoarse0 = TryGetLeafVertex(coarseLeafSlot, localCoarse0, coarseVertex0);
    bool validCoarse1 = TryGetLeafVertex(coarseLeafSlot, localCoarse1, coarseVertex1);

    if (!validFine0 && !validFine1 && !validCoarse0 && !validCoarse1)
        return;

    // Keep one fixed topological cycle.  This is the transition analogue of
    // current0 -> current1 -> neighbor1 -> neighbor0 in the same-LOD path.
    uint v0 = coarseVertex0;
    uint v1 = coarseVertex1;
    uint v2 = fineVertex1;
    uint v3 = fineVertex0;

    bool val0 = validCoarse0;
    bool val1 = validCoarse1;
    bool val2 = validFine1;
    bool val3 = validFine0;

    // -------------------------------------------------------------------------
    // TRANSITION WINDING: exact parity of the FIXED cycle
    //
    // The cycle above is:
    //     coarse0 -> coarse1 -> fine1 -> fine0
    //
    // IMPORTANT: face/orientation describe the actual local tangent basis
    // used by GetFineBoundaryCells().  For this exact vertex order, the
    // cycle normal is parallel to the primal-edge direction for the following
    // combinations:
    //
    //     -X : orientation 0 = yes, orientation 1 = no
    //     +X : orientation 0 = no,  orientation 1 = yes
    //     -Y : orientation 0 = no,  orientation 1 = yes
    //     +Y : orientation 0 = yes, orientation 1 = no
    //     -Z : orientation 0 = yes, orientation 1 = no
    //     +Z : orientation 0 = no,  orientation 1 = yes
    //
    // This is derived from the DC stencil itself, not from QEF positions,
    // SDF gradients, or an empirical normal table.
    // -------------------------------------------------------------------------
    bool baseNormalMatchesPositiveEdge = false;

    if (face == 0u) // -X
        baseNormalMatchesPositiveEdge = (orientation == 0u);
    else if (face == 1u) // +X
        baseNormalMatchesPositiveEdge = (orientation == 1u);
    else if (face == 2u) // -Y
        baseNormalMatchesPositiveEdge = (orientation == 1u);
    else if (face == 3u) // +Y
        baseNormalMatchesPositiveEdge = (orientation == 0u);
    else if (face == 4u) // -Z
        baseNormalMatchesPositiveEdge = (orientation == 0u);
    else if (face == 5u) // +Z
        baseNormalMatchesPositiveEdge = (orientation == 1u);
    else
        return;

    // Same rule as AddLeafQuad/AddQuad:
    //
    //   inside -> outside  => desired dual-face normal = +primal edge
    //   outside -> inside  => desired dual-face normal = -primal edge
    //
    // Here p0 -> p1 is already the positive world-axis direction selected by
    // GetBoundaryFaceSamplePoint/GetBoundaryFaceEdgePoints.
    bool insideToOutside = (da < 0.0f) && (db >= 0.0f);
    bool reverseWinding = (insideToOutside == baseNormalMatchesPositiveEdge);

    AppendBoundaryPolygon(
        coarseLeafSlot,
        v0, v1, v2, v3,
        val0, val1, val2, val3,
        reverseWinding);
}

void CSBuildLeafBoundaryFacesImpl(
    uint3 groupId : SV_GroupID,
    uint3 groupThreadId : SV_GroupThreadID)
{
    uint currentLeafSlot = GetLeafSlot(groupId);
    if (currentLeafSlot >= (uint) MaxActiveLeaves)
        return;

    VoxelLeafMeshInfo currentInfo = ActiveLeafMeshInfoBuffer[currentLeafSlot];
    if (currentInfo.nodeIndex == VOXEL_INVALID_NODE_INDEX)
        return;

    VoxelActiveLeaf currentLeaf = ActiveLeafBuffer[currentLeafSlot];
    VoxelActiveLeafNeighborTopology topology =
        ActiveLeafNeighborTopologyBuffer[currentLeaf.nodeIndex];

    uint resolutionU = (uint) CellCount;
    uint minorResolutionU = resolutionU > 0u ? resolutionU - 1u : 0u;
    uint edgeCount = resolutionU * minorResolutionU;
    uint orientationCount = edgeCount * 2u;
    uint quadrantCount = orientationCount * 4u;
    uint totalWork = quadrantCount * 6u;
    uint threadIndex = groupThreadId.x;

    for (uint linearIndex = threadIndex;
         linearIndex < totalWork;
         linearIndex += LEAF_MESH_THREADS_PER_LEAF)
    {
        uint face;
        uint quadrant;
        uint orientation;
        uint edgeA;
        uint edgeB;

        DecodeBoundaryWorkIndex(
            linearIndex,
            face,
            quadrant,
            orientation,
            edgeA,
            edgeB);

        uint neighborNodeIndex = GetBoundaryNeighborNodeIndex(topology, face, quadrant);
        if (neighborNodeIndex == VOXEL_INVALID_NODE_INDEX)
            continue;
        if (neighborNodeIndex >= (uint) MaxOctreeNodes)
            continue;

        if (IsDuplicateBoundaryNeighbor(topology, face, quadrant, neighborNodeIndex))
            continue;

        uint neighborLeafSlot;
        if (!TryResolveBoundaryNeighborSlot(neighborNodeIndex, neighborLeafSlot))
            continue;

        VoxelActiveLeaf neighborLeaf = ActiveLeafBuffer[neighborLeafSlot];
        int lodDelta = (int) currentLeaf.lod - (int) neighborLeaf.lod;

        if (lodDelta == 0)
        {
            if ((face & 1u) == 0u)
                continue;

            BuildSameLodBoundaryEdge(
                currentLeafSlot,
                currentLeaf,
                neighborLeafSlot,
                neighborLeaf,
                face,
                orientation,
                edgeA,
                edgeB);

            continue;
        }

        if (lodDelta == 1)
        {
            BuildCoarseFineTransitionEdge(
                currentLeafSlot,
                currentLeaf,
                neighborLeafSlot,
                neighborLeaf,
                face,
                orientation,
                edgeA,
                edgeB);
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

        BuildSameLodBoundaryIntersectionEdge(
            currentLeafSlot,
            currentLeaf,
            topology,
            intersectionFace,
            intersectionOrientation,
            intersectionEdgeA);
    }
}

#endif
