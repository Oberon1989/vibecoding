#ifndef VOXEL_DENSITY_MESH_FINALIZE_INCLUDED
#define VOXEL_DENSITY_MESH_FINALIZE_INCLUDED


#include "VoxelDensityTypes.hlsl"
#include "VoxelDensityMath.hlsl"
void CSFinalizeLeafMeshImpl(uint3 id : SV_DispatchThreadID)
{
    if (id.x != 0u) return;

    uint activeCount = ActiveLeafCountReadBuffer[0];
    uint safeActiveCount = min(activeCount, (uint) MaxActiveLeaves);
    uint totalVertexCount = 0u;
    uint totalIndexCount = 0u;

    for (uint leafSlot = 0u; leafSlot < safeActiveCount; ++leafSlot)
    {
        VoxelLeafMeshInfo info = ActiveLeafMeshInfoBuffer[leafSlot];

        uint vertexCursor = ActiveLeafMeshVertexCounterBuffer[leafSlot];
        uint indexCursor = ActiveLeafMeshIndexCounterBuffer[leafSlot];

        info.vertexCount = min(vertexCursor, info.vertexCapacity);
        info.indexCount = min(indexCursor, info.indexCapacity);

        totalVertexCount += info.vertexCount;
        totalIndexCount += info.indexCount;

        ActiveLeafMeshInfoBuffer[leafSlot] = info;
    }

    VertexCountBuffer[0] = totalVertexCount;
    IndexCountBuffer[0] = totalIndexCount;
}

#endif
