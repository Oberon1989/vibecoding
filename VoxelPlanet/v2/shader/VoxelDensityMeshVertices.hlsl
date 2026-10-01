#ifndef VOXEL_DENSITY_MESH_VERTICES_INCLUDED
#define VOXEL_DENSITY_MESH_VERTICES_INCLUDED
#include "VoxelDensityMeshCommon.hlsl"
#include "VoxelDensityQEF.hlsl"
void CSResetLeafMeshImpl(uint3 id : SV_DispatchThreadID)
{
    uint index = id.x;

    if (index < (uint) MaxActiveLeaves)
    {
        VoxelLeafMeshInfo info;
        info.nodeIndex = VOXEL_INVALID_NODE_INDEX;
        info.vertexBase = 0u;
        info.vertexCapacity = 0u;
        info.vertexCount = 0u;
        info.indexBase = 0u;
        info.indexCapacity = 0u;
        info.indexCount = 0u;

        ActiveLeafMeshInfoBuffer[index] = info;
        ActiveLeafMeshVertexCounterBuffer[index] = 0u;
        ActiveLeafMeshIndexCounterBuffer[index] = 0u;
    }

    if (index < (uint) MeshVertexHashCapacity)
    {
        ActiveLeafMeshVertexHashKeyBuffer[index] = 0u;
        ActiveLeafMeshVertexHashValueBuffer[index] = VOXEL_INVALID_NODE_INDEX;
    }

    if (index == 0u)
    {
        VertexCountBuffer[0] = 0u;
        IndexCountBuffer[0] = 0u;
        MeshOverflowFlagsBuffer[0] = 0u;
    }
}

void CSCountLeafMeshVerticesImpl(
    uint3 groupId : SV_GroupID,
    uint3 groupThreadId : SV_GroupThreadID)
{
    uint leafSlot = GetLeafSlot(groupId);
    if (!IsActiveLeafSlot(leafSlot)) return;

    VoxelActiveLeaf leaf = ActiveLeafReadBuffer[leafSlot];
    int resolution = CellCount;
    if (resolution <= 0) return;

    float leafStep = GetLeafStep(leaf);
    float3 leafOrigin = GetLeafOrigin(leaf);
    uint resolutionU = (uint) resolution;
    uint totalCells = resolutionU * resolutionU * resolutionU;
    uint localCount = 0u;
    uint threadIndex = groupThreadId.x;

    for (uint linearIndex = threadIndex;
         linearIndex < totalCells;
         linearIndex += LEAF_MESH_THREADS_PER_LEAF)
    {
        uint x = linearIndex % resolutionU;
        uint layer = linearIndex / resolutionU;
        uint y = layer % resolutionU;
        uint z = layer / resolutionU;

        float3 cellMin = leafOrigin + float3(x, y, z) * leafStep;
        if (CellHasSurface(cellMin, leafStep)) localCount++;
    }

    if (localCount > 0u)
    {
        InterlockedAdd(
            ActiveLeafMeshVertexCounterBuffer[leafSlot],
            localCount
        );
    }
}

void CSScanLeafMeshVertexOffsetsImpl(uint3 id : SV_DispatchThreadID)
{
    if (id.x != 0u) return;

    uint activeCount = ActiveLeafCountReadBuffer[0];
    uint safeActiveCount = min(activeCount, (uint) MaxActiveLeaves);
    uint arenaCursor = 0u;
    uint arenaCapacity = (uint) MeshVertexArenaCapacity;

    for (uint leafSlot = 0u; leafSlot < safeActiveCount; ++leafSlot)
    {
        uint requestedCapacity = ActiveLeafMeshVertexCounterBuffer[leafSlot];
        VoxelActiveLeaf leaf = ActiveLeafReadBuffer[leafSlot];

        VoxelLeafMeshInfo info;
        info.nodeIndex = leaf.nodeIndex;
        info.vertexBase = arenaCursor;
        info.vertexCount = 0u;
        info.indexBase = 0u;
        info.indexCapacity = 0u;
        info.indexCount = 0u;

        uint available = 0u;
        if (arenaCursor < arenaCapacity)
            available = arenaCapacity - arenaCursor;

        uint reservedCapacity = min(requestedCapacity, available);
        info.vertexCapacity = reservedCapacity;

        if (reservedCapacity < requestedCapacity)
        {
            InterlockedOr(
                MeshOverflowFlagsBuffer[0],
                MESH_OVERFLOW_VERTEX_ARENA
            );
        }

        ActiveLeafMeshInfoBuffer[leafSlot] = info;
        ActiveLeafMeshVertexCounterBuffer[leafSlot] = 0u;
        arenaCursor += reservedCapacity;
    }

    VertexCountBuffer[0] = 0u;
}

void CSBuildVerticesImpl(
    uint3 groupId : SV_GroupID,
    uint3 groupThreadId : SV_GroupThreadID)
{
    uint leafSlot = GetLeafSlot(groupId);
    if (!IsActiveLeafSlot(leafSlot)) return;

    VoxelActiveLeaf leaf = ActiveLeafReadBuffer[leafSlot];
    VoxelLeafMeshInfo info = ActiveLeafMeshInfoReadBuffer[leafSlot];

    int resolution = CellCount;
    if (resolution <= 0) return;

    float leafStep = GetLeafStep(leaf);
    float3 leafOrigin = GetLeafOrigin(leaf);
    uint resolutionU = (uint) resolution;
    uint totalCells = resolutionU * resolutionU * resolutionU;
    uint threadIndex = groupThreadId.x;

    for (uint linearIndex = threadIndex;
         linearIndex < totalCells;
         linearIndex += LEAF_MESH_THREADS_PER_LEAF)
    {
        uint x = linearIndex % resolutionU;
        uint layer = linearIndex / resolutionU;
        uint y = layer % resolutionU;
        uint z = layer / resolutionU;

        float3 cellMin = leafOrigin + float3(x, y, z) * leafStep;
        float3 cellMax = cellMin + float3(leafStep, leafStep, leafStep);
        float3 cellCenter = (cellMin + cellMax) * 0.5f;

        float3 p0 = cellMin;
        float3 p1 = cellMin + float3(leafStep, 0.0f, 0.0f);
        float3 p2 = cellMin + float3(0.0f, leafStep, 0.0f);
        float3 p3 = cellMin + float3(leafStep, leafStep, 0.0f);
        float3 p4 = cellMin + float3(0.0f, 0.0f, leafStep);
        float3 p5 = cellMin + float3(leafStep, 0.0f, leafStep);
        float3 p6 = cellMin + float3(0.0f, leafStep, leafStep);
        float3 p7 = cellMax;

        float d0 = SampleDensity(p0);
        float d1 = SampleDensity(p1);
        float d2 = SampleDensity(p2);
        float d3 = SampleDensity(p3);
        float d4 = SampleDensity(p4);
        float d5 = SampleDensity(p5);
        float d6 = SampleDensity(p6);
        float d7 = SampleDensity(p7);

        if (!IsFiniteFloat(d0) || !IsFiniteFloat(d1) ||
            !IsFiniteFloat(d2) || !IsFiniteFloat(d3) ||
            !IsFiniteFloat(d4) || !IsFiniteFloat(d5) ||
            !IsFiniteFloat(d6) || !IsFiniteFloat(d7))
        {
            continue;
        }

        bool hasInside =
            d0 < 0.0f || d1 < 0.0f || d2 < 0.0f || d3 < 0.0f ||
            d4 < 0.0f || d5 < 0.0f || d6 < 0.0f || d7 < 0.0f;

        bool hasOutside =
            d0 >= 0.0f || d1 >= 0.0f || d2 >= 0.0f || d3 >= 0.0f ||
            d4 >= 0.0f || d5 >= 0.0f || d6 >= 0.0f || d7 >= 0.0f;

        if (!hasInside || !hasOutside) continue;

        QEFData qef;
        ResetQEF(qef);

        AccumulateConstraint(qef, p0, p1, d0, d1, cellCenter);
        AccumulateConstraint(qef, p2, p3, d2, d3, cellCenter);
        AccumulateConstraint(qef, p4, p5, d4, d5, cellCenter);
        AccumulateConstraint(qef, p6, p7, d6, d7, cellCenter);
        AccumulateConstraint(qef, p0, p2, d0, d2, cellCenter);
        AccumulateConstraint(qef, p1, p3, d1, d3, cellCenter);
        AccumulateConstraint(qef, p4, p6, d4, d6, cellCenter);
        AccumulateConstraint(qef, p5, p7, d5, d7, cellCenter);
        AccumulateConstraint(qef, p0, p4, d0, d4, cellCenter);
        AccumulateConstraint(qef, p1, p5, d1, d5, cellCenter);
        AccumulateConstraint(qef, p2, p6, d2, d6, cellCenter);
        AccumulateConstraint(qef, p3, p7, d3, d7, cellCenter);

        if (qef.intersectionCount == 0u) continue;

        float3 vertex = SolveCellVertex(
            qef,
            cellCenter,
            cellMin,
            cellMax,
            leafStep
        );

        if (!IsFiniteFloat3(vertex)) continue;

        float3 vertexNormal = EstimateNormal(vertex);

        if (!IsFiniteFloat3(vertexNormal))
        {
            vertexNormal = float3(0.0f, 1.0f, 0.0f);
        }
        else
        {
            vertexNormal = SafeNormalize(
                vertexNormal,
                float3(0.0f, 1.0f, 0.0f)
            );
        }

        uint localVertexIndex = GetVertexIndex(
            (int) x,
            (int) y,
            (int) z
        );

        uint localVertexOrdinal;
        InterlockedAdd(
            ActiveLeafMeshVertexCounterBuffer[leafSlot],
            1u,
            localVertexOrdinal
        );

        if (localVertexOrdinal >= info.vertexCapacity)
        {
            InterlockedOr(
                MeshOverflowFlagsBuffer[0],
                MESH_OVERFLOW_VERTEX_ARENA
            );
            continue;
        }

        uint globalVertexIndex = info.vertexBase + localVertexOrdinal;
        if (globalVertexIndex >= (uint) MeshVertexArenaCapacity) continue;

        VertexBuffer[globalVertexIndex] = vertex;
        NormalBuffer[globalVertexIndex] = vertexNormal;

        if (!InsertLeafVertexHash(
            leafSlot,
            localVertexIndex,
            globalVertexIndex
        ))
        {
            InterlockedOr(
                MeshOverflowFlagsBuffer[0],
                MESH_OVERFLOW_VERTEX_HASH
            );
        }
    }
}

#endif
