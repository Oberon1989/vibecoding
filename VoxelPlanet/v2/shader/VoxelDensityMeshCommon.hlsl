#ifndef VOXEL_DENSITY_MESH_COMMON_INCLUDED
#define VOXEL_DENSITY_MESH_COMMON_INCLUDED

#include "VoxelDensityTypes.hlsl"
#include "VoxelDensityMath.hlsl"
#include "VoxelDensityDensity.hlsl"
static const uint LEAF_SLOT_GROUPS_X = 32768u;
static const uint LEAF_MESH_THREADS_PER_LEAF = 128u;
static const uint LEAF_MESH_HASH_MAX_PROBE = 256u;

uint GetLeafSlot(uint3 groupId)
{
    return groupId.x + groupId.y * LEAF_SLOT_GROUPS_X;
}

bool IsActiveLeafSlot(uint leafSlot)
{
    return leafSlot < ActiveLeafCountReadBuffer[0];
}

float GetLeafStep(VoxelActiveLeaf leaf)
{
    return BASE_LATTICE_SIZE * exp2((float) leaf.lod);
}

float3 GetLeafOrigin(VoxelActiveLeaf leaf)
{
    return (float3) leaf.canonicalOrigin * BASE_LATTICE_SIZE;
}

float3 GetCellWorldPosition(VoxelActiveLeaf leaf, int3 cell)
{
    return GetLeafOrigin(leaf) + (float3) cell * GetLeafStep(leaf);
}

uint MakeLeafVertexKey(uint leafSlot, uint localVertexIndex)
{
    return (leafSlot << 16u) | ((localVertexIndex + 1u) & 0xFFFFu);
}

uint HashLeafVertexKey(uint key)
{
    uint value = key;
    value ^= value >> 16u;
    value *= 0x7FEB352Du;
    value ^= value >> 15u;
    value *= 0x846CA68Bu;
    value ^= value >> 16u;
    return value;
}

bool InsertLeafVertexHash(uint leafSlot, uint localVertexIndex, uint globalVertexIndex)
{
    uint key = MakeLeafVertexKey(leafSlot, localVertexIndex);
    uint hashCapacity = (uint) MeshVertexHashCapacity;
    if (hashCapacity == 0u) return false;

    uint hashStart = HashLeafVertexKey(key) % hashCapacity;
    for (uint probe = 0u; probe < LEAF_MESH_HASH_MAX_PROBE; ++probe)
    {
        uint hashIndex = (hashStart + probe) % hashCapacity;
        uint observedKey;

        InterlockedCompareExchange(
            ActiveLeafMeshVertexHashKeyBuffer[hashIndex],
            0u,
            key,
            observedKey
        );

        if (observedKey == 0u || observedKey == key)
        {
            ActiveLeafMeshVertexHashValueBuffer[hashIndex] = globalVertexIndex;
            return true;
        }
    }

    return false;
}

bool TryGetLeafVertex(uint leafSlot, uint localVertexIndex, out uint globalVertexIndex)
{
    globalVertexIndex = VOXEL_INVALID_NODE_INDEX;

    uint key = MakeLeafVertexKey(leafSlot, localVertexIndex);
    uint hashCapacity = (uint) MeshVertexHashCapacity;
    if (hashCapacity == 0u) return false;

    uint hashStart = HashLeafVertexKey(key) % hashCapacity;
    for (uint probe = 0u; probe < LEAF_MESH_HASH_MAX_PROBE; ++probe)
    {
        uint hashIndex = (hashStart + probe) % hashCapacity;
        uint observedKey = ActiveLeafMeshVertexHashKeyReadBuffer[hashIndex];

        if (observedKey == 0u) return false;

        if (observedKey == key)
        {
            globalVertexIndex = ActiveLeafMeshVertexHashValueReadBuffer[hashIndex];
            return globalVertexIndex != VOXEL_INVALID_NODE_INDEX;
        }
    }

    return false;
}

bool CellHasSurface(float3 cellMin, float cellStep)
{
    float3 p0 = cellMin;
    float3 p1 = cellMin + float3(cellStep, 0.0f, 0.0f);
    float3 p2 = cellMin + float3(0.0f, cellStep, 0.0f);
    float3 p3 = cellMin + float3(cellStep, cellStep, 0.0f);
    float3 p4 = cellMin + float3(0.0f, 0.0f, cellStep);
    float3 p5 = cellMin + float3(cellStep, 0.0f, cellStep);
    float3 p6 = cellMin + float3(0.0f, cellStep, cellStep);
    float3 p7 = cellMin + float3(cellStep, cellStep, cellStep);

    float d0 = SampleDensity(p0);
    float d1 = SampleDensity(p1);
    float d2 = SampleDensity(p2);
    float d3 = SampleDensity(p3);
    float d4 = SampleDensity(p4);
    float d5 = SampleDensity(p5);
    float d6 = SampleDensity(p6);
    float d7 = SampleDensity(p7);

    bool hasInside =
        d0 < 0.0f || d1 < 0.0f || d2 < 0.0f || d3 < 0.0f ||
        d4 < 0.0f || d5 < 0.0f || d6 < 0.0f || d7 < 0.0f;

    bool hasOutside =
        d0 >= 0.0f || d1 >= 0.0f || d2 >= 0.0f || d3 >= 0.0f ||
        d4 >= 0.0f || d5 >= 0.0f || d6 >= 0.0f || d7 >= 0.0f;

    return hasInside && hasOutside;
}

#endif
