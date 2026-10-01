#ifndef VOXEL_DENSITY_TYPES_INCLUDED
#define VOXEL_DENSITY_TYPES_INCLUDED


// ============================================================
// CURRENT VOXEL / DENSITY PARAMETERS
// ============================================================

int CellCount;

float3 Origin;
float Step;

float3 PlanetCenter;
float PlanetRadius;


// ============================================================
// NOISE
// ============================================================

int NoiseSeed;
float NoiseFrequency;
float NoiseHeight;

struct DensityEditStamp
{
    float4 centerRadius;
    float4 parameters;
};

StructuredBuffer<DensityEditStamp> DensityEditBuffer;
int DensityEditCount;
float3 DensityEditBoundsMin;
float3 DensityEditBoundsMax;


// ============================================================
// GPU HIERARCHY PARAMETERS
// ============================================================

int RootLod;
int MinLod;
int MaxLod;

int MaxOctreeNodes;
int MaxActiveLeaves;

int3 RootCanonicalOrigin;

float3 LodTargetPosition;

float LodSplitDistanceMultiplier;
float LodMergeDistanceMultiplier;


// ============================================================
// LEAF MESH ARENA PARAMETERS
// ============================================================
//
// MeshVertexArenaCapacity:
//     total number of float3 vertices available.
//
// MeshIndexArenaCapacity:
//     total number of uint indices available.
//
// MeshVertexHashCapacity:
//     number of open-addressing hash slots used to map
//     (leaf slot, local vertex index) -> global vertex index.
//
// These are independent from the octree capacities.
// ============================================================

int MeshVertexArenaCapacity;
int MeshIndexArenaCapacity;
int MeshVertexHashCapacity;


// ============================================================
// CURRENT / GLOBAL GPU MESH BUFFERS
// ============================================================
//
// These buffers are now used as global mesh arenas.
//
// VertexBuffer / NormalBuffer:
//     global vertex arena.
//
// VertexValid:
//     global validity flags for the vertex arena.
//
// IndexBuffer:
//     global index arena.
//
// VertexCountBuffer:
//     total number of actually written vertices.
//
// IndexCountBuffer:
//     total number of actually written indices.
// ============================================================

RWStructuredBuffer<float3> VertexBuffer;

RWStructuredBuffer<float3> NormalBuffer;

RWStructuredBuffer<uint> VertexValid;

RWStructuredBuffer<uint> VertexCountBuffer;

RWStructuredBuffer<uint> IndexBuffer;

RWStructuredBuffer<uint> IndexCountBuffer;


// ============================================================
// NUMERICAL CONSTANTS
// ============================================================

static const float EPSILON =
    0.000001f;


static const float NORMAL_EPSILON =
    0.000000000001f;


static const float INTERSECTION_EPSILON =
    0.00000001f;


// ============================================================
// GPU OCTREE NODE STATES
// ============================================================

static const uint OCTREE_NODE_LEAF =
    0u;


static const uint OCTREE_NODE_INTERNAL =
    1u;


static const uint OCTREE_NODE_PENDING =
    2u;


static const uint OCTREE_NODE_FREE =
    3u;


// ============================================================
// GPU OCTREE NODE FLAGS
// ============================================================

static const uint OCTREE_FLAG_SURFACE =
    1u << 0;


static const uint OCTREE_FLAG_MESH_DIRTY =
    1u << 1;


static const uint OCTREE_FLAG_TOPOLOGY_DIRTY =
    1u << 2;


static const uint OCTREE_FLAG_LOD_DIRTY =
    1u << 3;


static const uint OCTREE_FLAG_ACTIVE =
    1u << 4;


static const uint OCTREE_FLAG_SPLIT_REQUEST =
    1u << 5;


static const uint OCTREE_FLAG_MERGE_REQUEST =
    1u << 6;


static const uint OCTREE_FLAG_NEIGHBOR_PENDING =
    1u << 7;


// ============================================================
// NEIGHBOR LOD STATES
// ============================================================

static const uint NEIGHBOR_LOD_SAME =
    0u;


static const uint NEIGHBOR_LOD_FINER =
    1u;


static const uint NEIGHBOR_LOD_COARSER =
    2u;


static const uint NEIGHBOR_LOD_INVALID =
    3u;


// ============================================================
// NEIGHBOR FACE IDS
// ============================================================

static const uint NEIGHBOR_FACE_NEG_X =
    0u;


static const uint NEIGHBOR_FACE_POS_X =
    1u;


static const uint NEIGHBOR_FACE_NEG_Y =
    2u;


static const uint NEIGHBOR_FACE_POS_Y =
    3u;


static const uint NEIGHBOR_FACE_NEG_Z =
    4u;


static const uint NEIGHBOR_FACE_POS_Z =
    5u;


// ============================================================
// INVALID OCTREE NODE INDEX
// ============================================================

static const uint VOXEL_INVALID_NODE_INDEX =
    0xFFFFFFFFu;


// ============================================================
// MESH OVERFLOW FLAGS
// ============================================================

static const uint MESH_OVERFLOW_VERTEX_ARENA =
    1u << 0;


static const uint MESH_OVERFLOW_INDEX_ARENA =
    1u << 1;


static const uint MESH_OVERFLOW_VERTEX_HASH =
    1u << 2;


static const uint MESH_OVERFLOW_INDEX_WRITE =
    1u << 3;


static const uint MESH_DIAGNOSTIC_TRANSITION_MISSING_VERTICES =
    1u << 4;


static const uint MESH_DIAGNOSTIC_BOUNDARY_NEIGHBOR_SLOT =
    1u << 5;


static const uint MESH_DIAGNOSTIC_BOUNDARY_MISSING_NEIGHBOR =
    1u << 6;


// A sign-changing primal edge owned by this LOD was not emitted because
// fewer than three distinct incident dual vertices could be resolved.
static const uint MESH_DIAGNOSTIC_DROPPED_EDGE_POLYGON =
    1u << 7;


// ============================================================
// PERSISTENT GPU OCTREE NODE
// ============================================================

struct VoxelOctreeNode
{
    int3 coord;

    int lod;

    int3 canonicalOrigin;

    int parentIndex;

    int firstChildIndex;

    uint state;

    uint flags;

    uint neighborLODMask;
};


// ============================================================
// ACTIVE GPU LEAF DESCRIPTION
// ============================================================

struct VoxelActiveLeaf
{
    uint nodeIndex;

    uint lod;

    int3 canonicalOrigin;

    uint neighborLODMask;
};


// ============================================================
// LEAF MESH INFO
// ============================================================
//
// One entry per active-leaf slot.
//
// vertexBase / vertexCapacity:
//     reserved range inside VertexBuffer.
//
// vertexCount:
//     actually generated vertices.
//
// indexBase / indexCapacity:
//     reserved range inside IndexBuffer.
//
// indexCount:
//     actually generated indices.
//
// vertexCapacity and indexCapacity are conservative reservation
// sizes calculated before the actual mesh build:
//
//     vertex capacity = number of sign-changing cells
//
//     index capacity = number of sign-changing oriented edges × 6
//
// Actual generated counts can therefore be smaller.
// ============================================================

struct VoxelLeafMeshInfo
{
    uint nodeIndex;

    uint vertexBase;
    uint vertexCapacity;
    uint vertexCount;

    uint indexBase;
    uint indexCapacity;
    uint indexCount;
};


// ============================================================
// EXACT ACTIVE LEAF NEIGHBOR TOPOLOGY
// ============================================================

struct VoxelActiveLeafNeighborTopology
{
    uint4 negX;

    uint4 posX;

    uint4 negY;

    uint4 posY;

    uint4 negZ;

    uint4 posZ;
};


// ============================================================
// PERSISTENT GPU HIERARCHY BUFFERS
// ============================================================

RWStructuredBuffer<VoxelOctreeNode> OctreeNodeBuffer;

RWStructuredBuffer<VoxelActiveLeaf> ActiveLeafBuffer;

RWStructuredBuffer<uint> OctreeFreeNodeStack;

RWStructuredBuffer<uint> OctreeFreeNodeCountBuffer;

RWStructuredBuffer<uint> ActiveLeafCountBuffer;

RWStructuredBuffer<uint> HierarchyChangedCountBuffer;


// ============================================================
// ACTIVE LEAF MESH SLOT BUFFER
// ============================================================
//
// Indexed by octree node index.
//
// [nodeIndex] contains the compact active-leaf slot.
//
// This is an indirection:
//
//     octree node
//         ↓
//     active leaf slot
//         ↓
//     leaf mesh info
//         ↓
//     vertex/index arena
// ============================================================

RWStructuredBuffer<uint>
    ActiveLeafMeshSlotBuffer;


// ============================================================
// ACTIVE LEAF MESH INFO BUFFER
// ============================================================

RWStructuredBuffer<VoxelLeafMeshInfo>
    ActiveLeafMeshInfoBuffer;


// ============================================================
// ACTIVE LEAF MESH COUNTERS
// ============================================================
//
// Vertex counter:
//
//     count pass:
//         conservative vertex capacity
//
//     build pass:
//         local vertex cursor
//
// Index counter:
//
//     count pass:
//         conservative index capacity
//
//     face build:
//         local index cursor
// ============================================================

RWStructuredBuffer<uint>
    ActiveLeafMeshVertexCounterBuffer;


RWStructuredBuffer<uint>
    ActiveLeafMeshIndexCounterBuffer;


// ============================================================
// ACTIVE LEAF MESH VERTEX HASH
// ============================================================
//
// Open-addressing table.
//
// key:
//     packed leaf slot + local vertex index.
//
// value:
//     global VertexBuffer index.
//
// key == 0 means empty.
//
// Valid keys are never zero because local vertex index is stored
// as localIndex + 1 in the low 16 bits.
// ============================================================

RWStructuredBuffer<uint>
    ActiveLeafMeshVertexHashKeyBuffer;


RWStructuredBuffer<uint>
    ActiveLeafMeshVertexHashValueBuffer;


// ============================================================
// GLOBAL MESH OVERFLOW FLAGS
// ============================================================

RWStructuredBuffer<uint>
    MeshOverflowFlagsBuffer;


// ============================================================
// DEBUG / ANALYSIS BUFFERS
// ============================================================

RWStructuredBuffer<uint> ActiveLeafMinLodBuffer;

RWStructuredBuffer<uint> ActiveLeafMaxLodBuffer;


// ============================================================
// EXACT NEIGHBOR TOPOLOGY BUFFER
// ============================================================

RWStructuredBuffer<VoxelActiveLeafNeighborTopology>
    ActiveLeafNeighborTopologyBuffer;

// SRV aliases used by mesh build kernels. Keeping read-only data out of UAV
// slots leaves room under the D3D12 eight-UAV compute-kernel limit.
StructuredBuffer<VoxelOctreeNode> OctreeNodeReadBuffer;
StructuredBuffer<VoxelActiveLeaf> ActiveLeafReadBuffer;
StructuredBuffer<uint> ActiveLeafCountReadBuffer;
StructuredBuffer<VoxelLeafMeshInfo> ActiveLeafMeshInfoReadBuffer;
StructuredBuffer<uint> ActiveLeafMeshSlotReadBuffer;
StructuredBuffer<uint> ActiveLeafMeshVertexHashKeyReadBuffer;
StructuredBuffer<uint> ActiveLeafMeshVertexHashValueReadBuffer;
StructuredBuffer<VoxelActiveLeafNeighborTopology>
    ActiveLeafNeighborTopologyReadBuffer;


// ============================================================
// CHUNK DESCRIPTION
// ============================================================

struct VoxelChunkData
{
    int3 chunkCoord;

    int lod;

    int3 canonicalOrigin;

    int resolution;

    uint neighborLODMask;
};


// ============================================================
// NEIGHBOR LOD MASK HELPERS
// ============================================================

uint GetNeighborLODState(
    uint neighborLODMask,
    uint face)
{
    uint shift =
        face * 2u;


    return
        (neighborLODMask >> shift) &
        3u;
}


// ============================================================
// SET NEIGHBOR LOD STATE
// ============================================================

uint SetNeighborLODState(
    uint neighborLODMask,
    uint face,
    uint state)
{
    uint shift =
        face * 2u;


    uint faceMask =
        3u << shift;


    neighborLODMask &=
        ~faceMask;


    neighborLODMask |=
        (state & 3u) << shift;


    return
        neighborLODMask;
}


// ============================================================
// OCTREE CHILD INDEX
// ============================================================

int GetChildIndex(
    int x,
    int y,
    int z)
{
    return
        x |
        (y << 1) |
        (z << 2);
}


// ============================================================
// OCTREE CHILD COORDINATE
// ============================================================

int3 GetChildCoordinate(
    int3 parentCoordinate,
    uint childIndex)
{
    return
        parentCoordinate *
        2 +
        int3(
            (int) (childIndex & 1u),
            (int) ((childIndex >> 1u) & 1u),
            (int) ((childIndex >> 2u) & 1u)
        );
}


// ============================================================
// OCTREE CHILD LOD
// ============================================================

int GetChildLod(
    int parentLod)
{
    return
        parentLod -
        1;
}


// ============================================================
// OCTREE PARENT LOD
// ============================================================

int GetParentLod(
    int childLod)
{
    return
        childLod +
        1;
}


// ============================================================
// BALANCED LOD PAIR
// ============================================================

bool IsBalancedLodPair(
    int lodA,
    int lodB)
{
    int difference =
        lodA -
        lodB;


    if (difference < 0)
    {
        difference =
            -difference;
    }


    return
        difference <= 1;
}


// ============================================================
// NODE FLAG HELPERS
// ============================================================

bool HasOctreeFlag(
    uint flags,
    uint flag)
{
    return
        (flags & flag) != 0u;
}


uint SetOctreeFlag(
    uint flags,
    uint flag)
{
    return
        flags | flag;
}


uint ClearOctreeFlag(
    uint flags,
    uint flag)
{
    return
        flags & ~flag;
}


// ============================================================
// NEIGHBOR FACE HELPERS
// ============================================================

static const uint NEIGHBOR_NEG_X =
    NEIGHBOR_FACE_NEG_X;


static const uint NEIGHBOR_POS_X =
    NEIGHBOR_FACE_POS_X;


static const uint NEIGHBOR_NEG_Y =
    NEIGHBOR_FACE_NEG_Y;


static const uint NEIGHBOR_POS_Y =
    NEIGHBOR_FACE_POS_Y;


static const uint NEIGHBOR_NEG_Z =
    NEIGHBOR_FACE_NEG_Z;


static const uint NEIGHBOR_POS_Z =
    NEIGHBOR_FACE_POS_Z;


#endif
