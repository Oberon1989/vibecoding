#ifndef VOXEL_DENSITY_TOPOLOGY_INCLUDED
#define VOXEL_DENSITY_TOPOLOGY_INCLUDED


#include "VoxelDensityTypes.hlsl"
#include "VoxelDensityMath.hlsl"


// ============================================================
// TRANSITION TOPOLOGY
// ============================================================
//
// Face state:
//
//     0 = NONE
//     1 = COARSE_TO_FINE
//     2 = FINE_TO_COARSE
//     3 = MIXED
//
// Face order:
//
//     0 = -X
//     1 = +X
//     2 = -Y
//     3 = +Y
//     4 = -Z
//     5 = +Z
// ============================================================

static const uint TRANSITION_NONE =
    0u;


static const uint TRANSITION_COARSE_TO_FINE =
    1u;


static const uint TRANSITION_FINE_TO_COARSE =
    2u;


static const uint TRANSITION_MIXED =
    3u;


// ============================================================
// TRANSITION TOPOLOGY DATA
// ============================================================

struct VoxelActiveLeafTransitionTopology
{
    uint negX;
    uint posX;

    uint negY;
    uint posY;

    uint negZ;
    uint posZ;
};


RWStructuredBuffer<VoxelActiveLeafTransitionTopology>
    ActiveLeafTransitionTopologyBuffer;


// ============================================================
// MAXIMUM INDEX COUNT
// ============================================================
//
// Current C# allocation:
//
//     maxIndexCount = 18 * resolution^3
//
// This is the fixed capacity of the GPU index buffer.
//
// The actual generated index count is usually much smaller.
// ============================================================

uint GetMaxIndexCount()
{
    int resolution =
        CellCount - 1;


    if (resolution <= 0)
    {
        return 0u;
    }


    uint r =
        (uint) resolution;


    return
        18u *
        r *
        r *
        r;
}


// ============================================================
// CLASSIFY TRANSITION FACE
// ============================================================
//
// Smaller numeric LOD means finer detail.
//
// Therefore:
//
//     neighbour.lod < leafLod
//         => neighbour is finer
//
//     neighbour.lod > leafLod
//         => neighbour is coarser
//
// Because the hierarchy is intended to remain 2:1 balanced,
// a valid coarse-to-fine face normally contains four children
// of the same finer LOD.
// ============================================================

uint ClassifyTransitionFace(
    int leafLod,
    uint q0,
    uint q1,
    uint q2,
    uint q3)
{
    bool hasFiner =
        false;


    bool hasCoarser =
        false;


    uint neighborNodeIndex;


    // ========================================================
    // Q0
    // ========================================================

    neighborNodeIndex =
        q0;


    if (neighborNodeIndex !=
        VOXEL_INVALID_NODE_INDEX)
    {
        VoxelOctreeNode neighbour =
            OctreeNodeBuffer[
                neighborNodeIndex
            ];


        if (neighbour.state ==
            OCTREE_NODE_LEAF)
        {
            if (neighbour.lod <
                leafLod)
            {
                hasFiner =
                    true;
            }
            else if (neighbour.lod >
                     leafLod)
            {
                hasCoarser =
                    true;
            }
        }
    }


    // ========================================================
    // Q1
    // ========================================================

    neighborNodeIndex =
        q1;


    if (neighborNodeIndex !=
        VOXEL_INVALID_NODE_INDEX)
    {
        VoxelOctreeNode neighbour =
            OctreeNodeBuffer[
                neighborNodeIndex
            ];


        if (neighbour.state ==
            OCTREE_NODE_LEAF)
        {
            if (neighbour.lod <
                leafLod)
            {
                hasFiner =
                    true;
            }
            else if (neighbour.lod >
                     leafLod)
            {
                hasCoarser =
                    true;
            }
        }
    }


    // ========================================================
    // Q2
    // ========================================================

    neighborNodeIndex =
        q2;


    if (neighborNodeIndex !=
        VOXEL_INVALID_NODE_INDEX)
    {
        VoxelOctreeNode neighbour =
            OctreeNodeBuffer[
                neighborNodeIndex
            ];


        if (neighbour.state ==
            OCTREE_NODE_LEAF)
        {
            if (neighbour.lod <
                leafLod)
            {
                hasFiner =
                    true;
            }
            else if (neighbour.lod >
                     leafLod)
            {
                hasCoarser =
                    true;
            }
        }
    }


    // ========================================================
    // Q3
    // ========================================================

    neighborNodeIndex =
        q3;


    if (neighborNodeIndex !=
        VOXEL_INVALID_NODE_INDEX)
    {
        VoxelOctreeNode neighbour =
            OctreeNodeBuffer[
                neighborNodeIndex
            ];


        if (neighbour.state ==
            OCTREE_NODE_LEAF)
        {
            if (neighbour.lod <
                leafLod)
            {
                hasFiner =
                    true;
            }
            else if (neighbour.lod >
                     leafLod)
            {
                hasCoarser =
                    true;
            }
        }
    }


    // ========================================================
    // CLASSIFICATION
    // ========================================================

    if (hasFiner &&
        hasCoarser)
    {
        return
            TRANSITION_MIXED;
    }


    if (hasFiner)
    {
        return
            TRANSITION_COARSE_TO_FINE;
    }


    if (hasCoarser)
    {
        return
            TRANSITION_FINE_TO_COARSE;
    }


    return
        TRANSITION_NONE;
}


// ============================================================
// BUILD TRANSITION TOPOLOGY
// ============================================================
//
// The already computed exact neighbor topology is used here.
//
// No spatial search is performed.
//
// No hierarchy mutation occurs.
//
// This kernel creates only a compact six-face transition state
// for every active surface leaf.
// ============================================================

[numthreads(64, 1, 1)]
void CSBuildTransitionTopology(
    uint3 id : SV_DispatchThreadID)
{
    int nodeIndex =
        (int) id.x;


    if (MaxOctreeNodes <= 0)
    {
        return;
    }


    if (nodeIndex >=
        MaxOctreeNodes)
    {
        return;
    }


    VoxelOctreeNode node =
        OctreeNodeBuffer[
            nodeIndex
        ];


    // --------------------------------------------------------
    // Only active surface leaves receive transition topology.
    // --------------------------------------------------------

    if (node.state !=
        OCTREE_NODE_LEAF)
    {
        return;
    }


    if (!HasOctreeFlag(
        node.flags,
        OCTREE_FLAG_SURFACE))
    {
        return;
    }


    if (!HasOctreeFlag(
        node.flags,
        OCTREE_FLAG_ACTIVE))
    {
        return;
    }


    // ========================================================
    // READ EXACT NEIGHBOR TOPOLOGY
    // ========================================================

    VoxelActiveLeafNeighborTopology topology =
        ActiveLeafNeighborTopologyBuffer[
            nodeIndex
        ];


    // ========================================================
    // CLASSIFY SIX FACES
    // ========================================================

    VoxelActiveLeafTransitionTopology transition;


    transition.negX =
        ClassifyTransitionFace(
            node.lod,
            topology.negX.x,
            topology.negX.y,
            topology.negX.z,
            topology.negX.w
        );


    transition.posX =
        ClassifyTransitionFace(
            node.lod,
            topology.posX.x,
            topology.posX.y,
            topology.posX.z,
            topology.posX.w
        );


    transition.negY =
        ClassifyTransitionFace(
            node.lod,
            topology.negY.x,
            topology.negY.y,
            topology.negY.z,
            topology.negY.w
        );


    transition.posY =
        ClassifyTransitionFace(
            node.lod,
            topology.posY.x,
            topology.posY.y,
            topology.posY.z,
            topology.posY.w
        );


    transition.negZ =
        ClassifyTransitionFace(
            node.lod,
            topology.negZ.x,
            topology.negZ.y,
            topology.negZ.z,
            topology.negZ.w
        );


    transition.posZ =
        ClassifyTransitionFace(
        node.lod,
        topology.posZ.x,
        topology.posZ.y,
        topology.posZ.z,
        topology.posZ.w
    );


    // ========================================================
    // WRITE RESULT
    // ========================================================

    ActiveLeafTransitionTopologyBuffer[
        nodeIndex
    ] =
        transition;
}


// ============================================================
// ADD QUAD
// ============================================================
//
// One sign-changing grid edge is surrounded by up to four
// Dual Contouring cell vertices:
//
//             c ---- b
//             |      |
//             d ---- a
//
// The exact winding is determined from:
//
//     da
//     db
//     baseNormalMatchesPositiveAxis
//
// The current convention is kept identical to the working
// single-chunk implementation:
//
//     X = true
//     Y = false
//     Z = true
//
// A quad is emitted as two triangles.
// ============================================================

void AddQuad(
    uint a,
    uint b,
    uint c,
    uint d,

    bool validA,
    bool validB,
    bool validC,
    bool validD,

    float da,
    float db,

    bool baseNormalMatchesPositiveAxis)
{
    // --------------------------------------------------------
    // All four surrounding cells must have valid DC vertices.
    // --------------------------------------------------------

    if (!validA ||
        !validB ||
        !validC ||
        !validD)
    {
        return;
    }


    // --------------------------------------------------------
    // Determine surface orientation.
    // --------------------------------------------------------

    bool insideToOutside =
        da < 0.0f &&
        db >= 0.0f;


    bool reverse =
        insideToOutside !=
        baseNormalMatchesPositiveAxis;


    // --------------------------------------------------------
    // Reserve six consecutive indices.
    //
    // The atomic allocation is intentionally kept even for the
    // current single-chunk implementation because the same
    // mechanism will remain valid when multiple GPU chunks are
    // built independently later.
    // --------------------------------------------------------

    uint baseIndex =
        0u;


    InterlockedAdd(
        IndexCountBuffer[0],
        6u,
        baseIndex
    );


    // --------------------------------------------------------
    // Capacity check.
    //
    // Never write beyond the allocated IndexBuffer.
    // --------------------------------------------------------

    uint maxIndexCount =
        GetMaxIndexCount();


    if (maxIndexCount < 6u)
    {
        return;
    }


    if (baseIndex >= maxIndexCount)
    {
        return;
    }


    // --------------------------------------------------------
    // Avoid:
    //
    //     baseIndex + 5 >= maxIndexCount
    //
    // because the addition itself could theoretically overflow
    // an unsigned integer.
    //
    //     baseIndex <= maxIndexCount - 6
    // --------------------------------------------------------

    if (baseIndex >
        maxIndexCount - 6u)
    {
        return;
    }


    // ========================================================
    // WRITE TRIANGLES
    // ========================================================

    if (reverse)
    {
        // ----------------------------------------------------
        // Triangle 1:
        //
        //     a c b
        //
        // Triangle 2:
        //
        //     a d c
        // ----------------------------------------------------

        IndexBuffer[
            baseIndex + 0u
        ] =
            a;


        IndexBuffer[
            baseIndex + 1u
        ] =
            c;


        IndexBuffer[
            baseIndex + 2u
        ] =
            b;


        IndexBuffer[
            baseIndex + 3u
        ] =
            a;


        IndexBuffer[
            baseIndex + 4u
        ] =
            d;


        IndexBuffer[
            baseIndex + 5u
        ] =
            c;
    }
    else
    {
        // ----------------------------------------------------
        // Triangle 1:
        //
        //     a b c
        //
        // Triangle 2:
        //
        //     a c d
        // ----------------------------------------------------

        IndexBuffer[
            baseIndex + 0u
        ] =
            a;


        IndexBuffer[
            baseIndex + 1u
        ] =
            b;


        IndexBuffer[
            baseIndex + 2u
        ] =
            c;


        IndexBuffer[
            baseIndex + 3u
        ] =
            a;


        IndexBuffer[
            baseIndex + 4u
        ] =
            c;


        IndexBuffer[
            baseIndex + 5u
        ] =
            d;
    }
}


#endif