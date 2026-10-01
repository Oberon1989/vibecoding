#ifndef VOXEL_OCTREE_INCLUDED
#define VOXEL_OCTREE_INCLUDED


#include "VoxelDensityTypes.hlsl"
#include "VoxelDensityMath.hlsl"


// ============================================================
// DISTANCE SQUARED TO AABB
// ============================================================

float DistanceSquaredToAABB(
    float3 samplePosition,
    float3 boxMin,
    float3 boxMax)
{
    float dx =
        0.0f;

    float dy =
        0.0f;

    float dz =
        0.0f;


    if (samplePosition.x < boxMin.x)
    {
        dx =
            boxMin.x -
            samplePosition.x;
    }
    else if (samplePosition.x > boxMax.x)
    {
        dx =
            samplePosition.x -
            boxMax.x;
    }


    if (samplePosition.y < boxMin.y)
    {
        dy =
            boxMin.y -
            samplePosition.y;
    }
    else if (samplePosition.y > boxMax.y)
    {
        dy =
            samplePosition.y -
            boxMax.y;
    }


    if (samplePosition.z < boxMin.z)
    {
        dz =
            boxMin.z -
            samplePosition.z;
    }
    else if (samplePosition.z > boxMax.z)
    {
        dz =
            samplePosition.z -
            boxMax.z;
    }


    return
        dx * dx +
        dy * dy +
        dz * dz;
}


// ============================================================
// PLANET SHELL INTERSECTION
// ============================================================

bool NodeIntersectsPlanetShell(
    float3 nodeMin,
    float3 nodeMax)
{
    float noiseAmplitude =
        NoiseHeight;


    if (noiseAmplitude < 0.0f)
    {
        noiseAmplitude =
            -noiseAmplitude;
    }


    float padding =
        noiseAmplitude +
        1.0f;


    float innerRadius =
        PlanetRadius -
        padding;


    if (innerRadius < 0.0f)
    {
        innerRadius =
            0.0f;
    }


    float outerRadius =
        PlanetRadius +
        padding;


    // ========================================================
    // CLOSEST POINT
    // ========================================================

    float closestX =
        PlanetCenter.x;

    float closestY =
        PlanetCenter.y;

    float closestZ =
        PlanetCenter.z;


    if (closestX < nodeMin.x)
    {
        closestX =
            nodeMin.x;
    }
    else if (closestX > nodeMax.x)
    {
        closestX =
            nodeMax.x;
    }


    if (closestY < nodeMin.y)
    {
        closestY =
            nodeMin.y;
    }
    else if (closestY > nodeMax.y)
    {
        closestY =
            nodeMax.y;
    }


    if (closestZ < nodeMin.z)
    {
        closestZ =
            nodeMin.z;
    }
    else if (closestZ > nodeMax.z)
    {
        closestZ =
            nodeMax.z;
    }


    float closestDX =
        closestX -
        PlanetCenter.x;

    float closestDY =
        closestY -
        PlanetCenter.y;

    float closestDZ =
        closestZ -
        PlanetCenter.z;


    float closestDistanceSquared =
        closestDX * closestDX +
        closestDY * closestDY +
        closestDZ * closestDZ;


    // ========================================================
    // FARTHEST POINT
    // ========================================================

    float minDX =
        nodeMin.x -
        PlanetCenter.x;

    float maxDX =
        nodeMax.x -
        PlanetCenter.x;


    float minDY =
        nodeMin.y -
        PlanetCenter.y;

    float maxDY =
        nodeMax.y -
        PlanetCenter.y;


    float minDZ =
        nodeMin.z -
        PlanetCenter.z;

    float maxDZ =
        nodeMax.z -
        PlanetCenter.z;


    float squaredMinDX =
        minDX * minDX;

    float squaredMaxDX =
        maxDX * maxDX;


    float squaredMinDY =
        minDY * minDY;

    float squaredMaxDY =
        maxDY * maxDY;


    float squaredMinDZ =
        minDZ * minDZ;

    float squaredMaxDZ =
        maxDZ * maxDZ;


    float farthestX =
        squaredMinDX;

    if (squaredMaxDX > farthestX)
    {
        farthestX =
            squaredMaxDX;
    }


    float farthestY =
        squaredMinDY;

    if (squaredMaxDY > farthestY)
    {
        farthestY =
            squaredMaxDY;
    }


    float farthestZ =
        squaredMinDZ;

    if (squaredMaxDZ > farthestZ)
    {
        farthestZ =
            squaredMaxDZ;
    }


    float farthestDistanceSquared =
        farthestX +
        farthestY +
        farthestZ;


    float innerRadiusSquared =
        innerRadius *
        innerRadius;


    float outerRadiusSquared =
        outerRadius *
        outerRadius;


    if (!IsFiniteFloat(
        closestDistanceSquared))
    {
        return false;
    }


    if (!IsFiniteFloat(
        farthestDistanceSquared))
    {
        return false;
    }


    return
        closestDistanceSquared <= outerRadiusSquared &&
        farthestDistanceSquared >= innerRadiusSquared;
}


// ============================================================
// INITIALIZE PERSISTENT GPU OCTREE
// ============================================================

[numthreads(64, 1, 1)]
void CSInitializeOctree(
    uint3 id : SV_DispatchThreadID)
{
    uint nodeIndex =
        id.x;


    if (MaxOctreeNodes <= 0)
    {
        return;
    }


    if (nodeIndex >=
        (uint) MaxOctreeNodes)
    {
        return;
    }


    uint childBlockCount =
        (uint) ((MaxOctreeNodes - 1) >> 3);


    // ========================================================
    // ROOT
    // ========================================================

    if (nodeIndex == 0u)
    {
        VoxelOctreeNode root;


        root.coord =
            int3(
                0,
                0,
                0
            );


        root.lod =
            RootLod;


        root.canonicalOrigin =
            RootCanonicalOrigin;


        root.parentIndex =
            -1;


        root.firstChildIndex =
            -1;


        root.state =
            OCTREE_NODE_LEAF;


        root.flags =
            OCTREE_FLAG_SURFACE |
            OCTREE_FLAG_ACTIVE |
            OCTREE_FLAG_MESH_DIRTY |
            OCTREE_FLAG_LOD_DIRTY;


        root.neighborLODMask =
            0xFFFu;


        OctreeNodeBuffer[0] =
            root;


        ActiveLeafCountBuffer[0] =
            0u;


        HierarchyChangedCountBuffer[0] =
            1u;


        OctreeFreeNodeCountBuffer[0] =
            childBlockCount;


        return;
    }


    // ========================================================
    // FREE NODE SLOT
    // ========================================================

    VoxelOctreeNode freeNode;


    freeNode.coord =
        int3(
            0,
            0,
            0
        );


    freeNode.lod =
        0;


    freeNode.canonicalOrigin =
        int3(
            0,
            0,
            0
        );


    freeNode.parentIndex =
        -1;


    freeNode.firstChildIndex =
        -1;


    freeNode.state =
        OCTREE_NODE_FREE;


    freeNode.flags =
        0u;


    freeNode.neighborLODMask =
        0xFFFu;


    OctreeNodeBuffer[
        nodeIndex
    ] =
        freeNode;


    uint stackIndex =
        nodeIndex - 1u;


    if (stackIndex < childBlockCount)
    {
        OctreeFreeNodeStack[
            stackIndex
        ] =
            1u +
            stackIndex * 8u;
    }
}


// ============================================================
// SELECT LOD
// ============================================================

[numthreads(64, 1, 1)]
void CSSelectLOD(
    uint3 id : SV_DispatchThreadID)
{
    uint nodeIndex =
        id.x;


    if (MaxOctreeNodes <= 0)
    {
        return;
    }


    if (nodeIndex >=
        (uint) MaxOctreeNodes)
    {
        return;
    }


    VoxelOctreeNode node =
        OctreeNodeBuffer[
            nodeIndex
        ];


    if (node.state ==
        OCTREE_NODE_FREE)
    {
        return;
    }


    if (!HasOctreeFlag(
        node.flags,
        OCTREE_FLAG_SURFACE))
    {
        return;
    }


    float3 nodeMin =
        GetNodeWorldMin(
            node
        );


    float3 nodeMax =
        GetNodeWorldMax(
            node
        );


    float nodeSize =
        GetNodeWorldSize(
            node
        );


    float distanceSquared =
        DistanceSquaredToAABB(
            LodTargetPosition,
            nodeMin,
            nodeMax
        );


    if (!IsFiniteFloat(
        distanceSquared))
    {
        return;
    }


    float splitDistance =
        nodeSize *
        LodSplitDistanceMultiplier;


    float mergeDistance =
        nodeSize *
        LodMergeDistanceMultiplier;


    float splitDistanceSquared =
        splitDistance *
        splitDistance;


    float mergeDistanceSquared =
        mergeDistance *
        mergeDistance;


    // ========================================================
    // LEAF
    // ========================================================

    if (node.state ==
        OCTREE_NODE_LEAF)
    {
        node.flags =
            ClearOctreeFlag(
                node.flags,
                OCTREE_FLAG_SPLIT_REQUEST
            );


        if (node.lod <=
            MinLod)
        {
            OctreeNodeBuffer[
                nodeIndex
            ] =
                node;

            return;
        }


        if (distanceSquared <=
            splitDistanceSquared)
        {
            node.flags =
                SetOctreeFlag(
                    node.flags,
                    OCTREE_FLAG_SPLIT_REQUEST
                );


            node.flags =
                SetOctreeFlag(
                    node.flags,
                    OCTREE_FLAG_LOD_DIRTY
                );


            InterlockedAdd(
                HierarchyChangedCountBuffer[0],
                1u
            );
        }


        OctreeNodeBuffer[
            nodeIndex
        ] =
            node;


        return;
    }


    // ========================================================
    // INTERNAL
    // ========================================================

    if (node.state ==
        OCTREE_NODE_INTERNAL)
    {
        node.flags =
            ClearOctreeFlag(
                node.flags,
                OCTREE_FLAG_MERGE_REQUEST
            );


        if (node.parentIndex < 0)
        {
            OctreeNodeBuffer[
                nodeIndex
            ] =
                node;

            return;
        }


        if (node.firstChildIndex < 0)
        {
            OctreeNodeBuffer[
                nodeIndex
            ] =
                node;

            return;
        }


        bool allChildrenAreLeaves =
            true;


        [unroll]
        for (
            uint mergeCheckOffset = 0u;
            mergeCheckOffset < 8u;
            mergeCheckOffset++
        )
        {
            uint childIndex =
                (uint) node.firstChildIndex +
                mergeCheckOffset;


            if (childIndex >=
                (uint) MaxOctreeNodes)
            {
                allChildrenAreLeaves =
                    false;

                break;
            }


            VoxelOctreeNode child =
                OctreeNodeBuffer[
                    childIndex
                ];


            if (child.state !=
                OCTREE_NODE_LEAF)
            {
                allChildrenAreLeaves =
                    false;

                break;
            }


            if (child.parentIndex !=
                (int) nodeIndex)
            {
                allChildrenAreLeaves =
                    false;

                break;
            }


            if (HasOctreeFlag(
                child.flags,
                OCTREE_FLAG_SPLIT_REQUEST))
            {
                allChildrenAreLeaves =
                    false;

                break;
            }
        }


        if (!allChildrenAreLeaves)
        {
            OctreeNodeBuffer[
                nodeIndex
            ] =
                node;

            return;
        }


        if (distanceSquared >=
            mergeDistanceSquared)
        {
            node.flags =
                SetOctreeFlag(
                    node.flags,
                    OCTREE_FLAG_MERGE_REQUEST
                );


            node.flags =
                SetOctreeFlag(
                    node.flags,
                    OCTREE_FLAG_LOD_DIRTY
                );


            InterlockedAdd(
                HierarchyChangedCountBuffer[0],
                1u
            );
        }


        OctreeNodeBuffer[
            nodeIndex
        ] =
            node;
    }
}


// ============================================================
// BALANCE 2:1 HELPERS
// ============================================================

int BalanceGetNodeCanonicalSpan(
    VoxelOctreeNode node)
{
    int safeLod =
        clamp(
            node.lod,
            0,
            25
        );


    return
        DEFAULT_CHUNK_RESOLUTION <<
        safeLod;
}


// ============================================================
// BALANCE FACE SAMPLE POINT
// ============================================================

int3 BalanceGetFaceSamplePoint(
    VoxelOctreeNode node,
    int faceIndex,
    uint sampleIndex)
{
    int span =
        BalanceGetNodeCanonicalSpan(
            node
        );


    int quarter =
        span >> 2;


    int threeQuarter =
        span -
        quarter;


    int sampleU;
    int sampleV;


    if ((sampleIndex & 1u) == 0u)
    {
        sampleU =
            quarter;
    }
    else
    {
        sampleU =
            threeQuarter;
    }


    if (sampleIndex < 2u)
    {
        sampleV =
            quarter;
    }
    else
    {
        sampleV =
            threeQuarter;
    }


    int3 samplePoint =
        node.canonicalOrigin;


    if (faceIndex == 0)
    {
        samplePoint.x =
            node.canonicalOrigin.x -
            1;


        samplePoint.y +=
            sampleU;


        samplePoint.z +=
            sampleV;


        return samplePoint;
    }


    if (faceIndex == 1)
    {
        samplePoint.x =
            node.canonicalOrigin.x +
            span +
            1;


        samplePoint.y +=
            sampleU;


        samplePoint.z +=
            sampleV;


        return samplePoint;
    }


    if (faceIndex == 2)
    {
        samplePoint.y =
            node.canonicalOrigin.y -
            1;


        samplePoint.x +=
            sampleU;


        samplePoint.z +=
            sampleV;


        return samplePoint;
    }


    if (faceIndex == 3)
    {
        samplePoint.y =
            node.canonicalOrigin.y +
            span +
            1;


        samplePoint.x +=
            sampleU;


        samplePoint.z +=
            sampleV;


        return samplePoint;
    }


    if (faceIndex == 4)
    {
        samplePoint.z =
            node.canonicalOrigin.z -
            1;


        samplePoint.x +=
            sampleU;


        samplePoint.y +=
            sampleV;


        return samplePoint;
    }


    samplePoint.z =
        node.canonicalOrigin.z +
        span +
        1;


    samplePoint.x +=
        sampleU;


    samplePoint.y +=
        sampleV;


    return samplePoint;
}


// ============================================================
// FIND LEAF AT CANONICAL POINT
// ============================================================

int BalanceFindLeafAtCanonicalPoint(
    int3 samplePoint)
{
    VoxelOctreeNode rootNode =
        OctreeNodeBuffer[0];


    int rootSpan =
        BalanceGetNodeCanonicalSpan(
            rootNode
        );


    int3 rootMin =
        rootNode.canonicalOrigin;


    int3 rootMax =
        rootMin +
        int3(
            rootSpan,
            rootSpan,
            rootSpan
        );


    if (samplePoint.x < rootMin.x ||
        samplePoint.x >= rootMax.x ||
        samplePoint.y < rootMin.y ||
        samplePoint.y >= rootMax.y ||
        samplePoint.z < rootMin.z ||
        samplePoint.z >= rootMax.z)
    {
        return -1;
    }


    int currentNodeIndex =
        0;


    for (
        int balanceDepth = 0;
        balanceDepth < 32;
        balanceDepth++
    )
    {
        if (currentNodeIndex < 0 ||
            currentNodeIndex >= MaxOctreeNodes)
        {
            return -1;
        }


        VoxelOctreeNode currentNode =
            OctreeNodeBuffer[
                currentNodeIndex
            ];


        if (currentNode.state ==
            OCTREE_NODE_LEAF)
        {
            return currentNodeIndex;
        }


        if (currentNode.state !=
            OCTREE_NODE_INTERNAL)
        {
            return -1;
        }


        if (currentNode.firstChildIndex < 0)
        {
            return -1;
        }


        int nodeSpan =
            BalanceGetNodeCanonicalSpan(
                currentNode
            );


        int halfSpan =
            nodeSpan >> 1;


        int3 localPoint =
            samplePoint -
            currentNode.canonicalOrigin;


        uint childIndex =
            0u;


        if (localPoint.x >=
            halfSpan)
        {
            childIndex |=
                1u;
        }


        if (localPoint.y >=
            halfSpan)
        {
            childIndex |=
                2u;
        }


        if (localPoint.z >=
            halfSpan)
        {
            childIndex |=
                4u;
        }


        currentNodeIndex =
            currentNode.firstChildIndex +
            (int) childIndex;
    }


    return -1;
}


// ============================================================
// REQUEST SPLIT
// ============================================================

void BalanceRequestSplit(
    int nodeIndex)
{
    if (nodeIndex < 0 ||
        nodeIndex >= MaxOctreeNodes)
    {
        return;
    }


    VoxelOctreeNode targetNode =
        OctreeNodeBuffer[
            nodeIndex
        ];


    if (targetNode.state !=
        OCTREE_NODE_LEAF)
    {
        return;
    }


    if (!HasOctreeFlag(
        targetNode.flags,
        OCTREE_FLAG_SURFACE))
    {
        return;
    }


    if (targetNode.lod <=
        MinLod)
    {
        return;
    }


    uint requestFlags =
        OCTREE_FLAG_SPLIT_REQUEST |
        OCTREE_FLAG_LOD_DIRTY;


    uint previousFlags;


    InterlockedOr(
        OctreeNodeBuffer[nodeIndex].flags,
        requestFlags,
        previousFlags
    );
}


// ============================================================
// 2:1 BALANCE
// ============================================================

[numthreads(64, 1, 1)]
void CSBalanceOctree2To1(
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


    int nodeLod =
        node.lod;


    bool currentSplitRequested =
        HasOctreeFlag(
            node.flags,
            OCTREE_FLAG_SPLIT_REQUEST
        );


    bool tooFineNeighbour =
        false;


    for (
        int balanceFaceIndex = 0;
        balanceFaceIndex < 6;
        balanceFaceIndex++
    )
    {
        for (
            uint balanceSampleIndex = 0u;
            balanceSampleIndex < 4u;
            balanceSampleIndex++
        )
        {
            int3 samplePoint =
                BalanceGetFaceSamplePoint(
                    node,
                    balanceFaceIndex,
                    balanceSampleIndex
                );


            int neighbourIndex =
                BalanceFindLeafAtCanonicalPoint(
                    samplePoint
                );


            if (neighbourIndex < 0 ||
                neighbourIndex == nodeIndex)
            {
                continue;
            }


            VoxelOctreeNode neighbour =
                OctreeNodeBuffer[
                    neighbourIndex
                ];


            if (neighbour.state !=
                OCTREE_NODE_LEAF)
            {
                continue;
            }


            if (!HasOctreeFlag(
                neighbour.flags,
                OCTREE_FLAG_SURFACE))
            {
                continue;
            }


            if (neighbour.lod <
                nodeLod - 1)
            {
                tooFineNeighbour =
                    true;
            }


            if (neighbour.lod >
                nodeLod)
            {
                if (neighbour.lod >
                    nodeLod + 1)
                {
                    BalanceRequestSplit(
                        neighbourIndex
                    );
                }


                if (currentSplitRequested)
                {
                    BalanceRequestSplit(
                        neighbourIndex
                    );
                }
            }
        }
    }


    if (tooFineNeighbour)
    {
        BalanceRequestSplit(
            nodeIndex
        );
    }
}


// ============================================================
// NEIGHBOUR LOD SUMMARY
// ============================================================

uint SetBalanceNeighborFaceState(
    uint mask,
    int faceIndex,
    uint state)
{
    uint shift =
        (uint) (faceIndex * 2);


    uint faceMask =
        3u <<
        shift;


    mask &=
        ~faceMask;


    mask |=
        (state & 3u) <<
        shift;


    return mask;
}


// ============================================================
// BUILD NEIGHBOUR LOD SUMMARY
// ============================================================

[numthreads(64, 1, 1)]
void CSBuildNeighborLOD(
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


    int nodeLod =
        node.lod;


    uint newNeighborMask =
        0xFFFu;


    for (
        int neighborFaceIndex = 0;
        neighborFaceIndex < 6;
        neighborFaceIndex++
    )
    {
        bool foundSurfaceNeighbour =
            false;


        bool foundSameNeighbour =
            false;


        bool foundFinerNeighbour =
            false;


        bool foundCoarserNeighbour =
            false;


        for (
            uint neighborSampleIndex = 0u;
            neighborSampleIndex < 4u;
            neighborSampleIndex++
        )
        {
            int3 samplePoint =
                BalanceGetFaceSamplePoint(
                    node,
                    neighborFaceIndex,
                    neighborSampleIndex
                );


            int neighbourIndex =
                BalanceFindLeafAtCanonicalPoint(
                    samplePoint
                );


            if (neighbourIndex < 0 ||
                neighbourIndex == nodeIndex)
            {
                continue;
            }


            VoxelOctreeNode neighbour =
                OctreeNodeBuffer[
                    neighbourIndex
                ];


            if (neighbour.state !=
                OCTREE_NODE_LEAF)
            {
                continue;
            }


            if (!HasOctreeFlag(
                neighbour.flags,
                OCTREE_FLAG_SURFACE))
            {
                continue;
            }


            foundSurfaceNeighbour =
                true;


            if (neighbour.lod ==
                nodeLod)
            {
                foundSameNeighbour =
                    true;
            }
            else if (neighbour.lod <
                     nodeLod)
            {
                foundFinerNeighbour =
                    true;
            }
            else
            {
                foundCoarserNeighbour =
                    true;
            }
        }


        uint faceState =
            NEIGHBOR_LOD_INVALID;


        if (foundFinerNeighbour)
        {
            faceState =
                NEIGHBOR_LOD_FINER;
        }
        else if (foundCoarserNeighbour)
        {
            faceState =
                NEIGHBOR_LOD_COARSER;
        }
        else if (foundSameNeighbour)
        {
            faceState =
                NEIGHBOR_LOD_SAME;
        }
        else if (foundSurfaceNeighbour)
        {
            faceState =
                NEIGHBOR_LOD_SAME;
        }


        newNeighborMask =
            SetBalanceNeighborFaceState(
                newNeighborMask,
                neighborFaceIndex,
                faceState
            );
    }


    node.neighborLODMask =
        newNeighborMask;


    OctreeNodeBuffer[
        nodeIndex
    ] =
        node;
}


// ============================================================
// EXACT NEIGHBOR TOPOLOGY HELPER
// ============================================================

void SetNeighborTopologyEntry(
    inout VoxelActiveLeafNeighborTopology topology,
    int faceIndex,
    uint quadrant,
    uint neighborNodeIndex)
{
    if (faceIndex == 0)
    {
        if (quadrant == 0u)
        {
            topology.negX.x =
                neighborNodeIndex;

            return;
        }


        if (quadrant == 1u)
        {
            topology.negX.y =
                neighborNodeIndex;

            return;
        }


        if (quadrant == 2u)
        {
            topology.negX.z =
                neighborNodeIndex;

            return;
        }


        topology.negX.w =
            neighborNodeIndex;

        return;
    }


    if (faceIndex == 1)
    {
        if (quadrant == 0u)
        {
            topology.posX.x =
                neighborNodeIndex;

            return;
        }


        if (quadrant == 1u)
        {
            topology.posX.y =
                neighborNodeIndex;

            return;
        }


        if (quadrant == 2u)
        {
            topology.posX.z =
                neighborNodeIndex;

            return;
        }


        topology.posX.w =
            neighborNodeIndex;

        return;
    }


    if (faceIndex == 2)
    {
        if (quadrant == 0u)
        {
            topology.negY.x =
                neighborNodeIndex;

            return;
        }


        if (quadrant == 1u)
        {
            topology.negY.y =
                neighborNodeIndex;

            return;
        }


        if (quadrant == 2u)
        {
            topology.negY.z =
                neighborNodeIndex;

            return;
        }


        topology.negY.w =
            neighborNodeIndex;

        return;
    }


    if (faceIndex == 3)
    {
        if (quadrant == 0u)
        {
            topology.posY.x =
                neighborNodeIndex;

            return;
        }


        if (quadrant == 1u)
        {
            topology.posY.y =
                neighborNodeIndex;

            return;
        }


        if (quadrant == 2u)
        {
            topology.posY.z =
                neighborNodeIndex;

            return;
        }


        topology.posY.w =
            neighborNodeIndex;

        return;
    }


    if (faceIndex == 4)
    {
        if (quadrant == 0u)
        {
            topology.negZ.x =
                neighborNodeIndex;

            return;
        }


        if (quadrant == 1u)
        {
            topology.negZ.y =
                neighborNodeIndex;

            return;
        }


        if (quadrant == 2u)
        {
            topology.negZ.z =
                neighborNodeIndex;

            return;
        }


        topology.negZ.w =
            neighborNodeIndex;

        return;
    }


    if (quadrant == 0u)
    {
        topology.posZ.x =
            neighborNodeIndex;

        return;
    }


    if (quadrant == 1u)
    {
        topology.posZ.y =
            neighborNodeIndex;

        return;
    }


    if (quadrant == 2u)
    {
        topology.posZ.z =
            neighborNodeIndex;

        return;
    }


    topology.posZ.w =
        neighborNodeIndex;
}


// ============================================================
// BUILD EXACT NEIGHBOR TOPOLOGY
// ============================================================

[numthreads(64, 1, 1)]
void CSBuildNeighborTopology(
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


    VoxelActiveLeafNeighborTopology topology;


    topology.negX =
        uint4(
            VOXEL_INVALID_NODE_INDEX,
            VOXEL_INVALID_NODE_INDEX,
            VOXEL_INVALID_NODE_INDEX,
            VOXEL_INVALID_NODE_INDEX
        );


    topology.posX =
        uint4(
            VOXEL_INVALID_NODE_INDEX,
            VOXEL_INVALID_NODE_INDEX,
            VOXEL_INVALID_NODE_INDEX,
            VOXEL_INVALID_NODE_INDEX
        );


    topology.negY =
        uint4(
            VOXEL_INVALID_NODE_INDEX,
            VOXEL_INVALID_NODE_INDEX,
            VOXEL_INVALID_NODE_INDEX,
            VOXEL_INVALID_NODE_INDEX
        );


    topology.posY =
        uint4(
            VOXEL_INVALID_NODE_INDEX,
            VOXEL_INVALID_NODE_INDEX,
            VOXEL_INVALID_NODE_INDEX,
            VOXEL_INVALID_NODE_INDEX
        );


    topology.negZ =
        uint4(
            VOXEL_INVALID_NODE_INDEX,
            VOXEL_INVALID_NODE_INDEX,
            VOXEL_INVALID_NODE_INDEX,
            VOXEL_INVALID_NODE_INDEX
        );


    topology.posZ =
        uint4(
            VOXEL_INVALID_NODE_INDEX,
            VOXEL_INVALID_NODE_INDEX,
            VOXEL_INVALID_NODE_INDEX,
            VOXEL_INVALID_NODE_INDEX
        );


    for (
        int topologyFaceIndex = 0;
        topologyFaceIndex < 6;
        topologyFaceIndex++
    )
    {
        for (
            uint topologyQuadrant = 0u;
            topologyQuadrant < 4u;
            topologyQuadrant++
        )
        {
            int3 samplePoint =
                BalanceGetFaceSamplePoint(
                    node,
                    topologyFaceIndex,
                    topologyQuadrant
                );


            int neighbourIndex =
                BalanceFindLeafAtCanonicalPoint(
                    samplePoint
                );


            uint resolvedNeighbour =
                VOXEL_INVALID_NODE_INDEX;


            if (neighbourIndex >= 0 &&
                neighbourIndex < MaxOctreeNodes &&
                neighbourIndex != nodeIndex)
            {
                VoxelOctreeNode neighbour =
                    OctreeNodeBuffer[
                        neighbourIndex
                    ];


                if (neighbour.state ==
                    OCTREE_NODE_LEAF)
                {
                    if (HasOctreeFlag(
                        neighbour.flags,
                        OCTREE_FLAG_SURFACE))
                    {
                        if (HasOctreeFlag(
                            neighbour.flags,
                            OCTREE_FLAG_ACTIVE))
                        {
                            resolvedNeighbour =
                                (uint) neighbourIndex;
                        }
                    }
                }
            }


            SetNeighborTopologyEntry(
                topology,
                topologyFaceIndex,
                topologyQuadrant,
                resolvedNeighbour
            );
        }
    }


    ActiveLeafNeighborTopologyBuffer[
        nodeIndex
    ] =
        topology;
}


// ============================================================
// APPLY LOD REQUESTS
// ============================================================

[numthreads(64, 1, 1)]
void CSApplyLODRequests(
    uint3 id : SV_DispatchThreadID)
{
    uint nodeIndex =
        id.x;


    if (MaxOctreeNodes <= 0)
    {
        return;
    }


    if (nodeIndex >=
        (uint) MaxOctreeNodes)
    {
        return;
    }


    VoxelOctreeNode node =
        OctreeNodeBuffer[
            nodeIndex
        ];


    if (node.state !=
        OCTREE_NODE_LEAF)
    {
        return;
    }


    if (!HasOctreeFlag(
        node.flags,
        OCTREE_FLAG_SPLIT_REQUEST))
    {
        return;
    }


    if (node.lod <=
        MinLod)
    {
        node.flags =
            ClearOctreeFlag(
                node.flags,
                OCTREE_FLAG_SPLIT_REQUEST
            );


        OctreeNodeBuffer[
            nodeIndex
        ] =
            node;


        return;
    }


    uint observedFreeCount;
    uint originalFreeCount;


    bool acquiredBlock =
        false;


    [loop]
    for (
        int splitAttempt = 0;
        splitAttempt < 32;
        splitAttempt++
    )
    {
        observedFreeCount =
            OctreeFreeNodeCountBuffer[0];


        if (observedFreeCount == 0u)
        {
            break;
        }


        InterlockedCompareExchange(
            OctreeFreeNodeCountBuffer[0],
            observedFreeCount,
            observedFreeCount - 1u,
            originalFreeCount
        );


        if (originalFreeCount ==
            observedFreeCount)
        {
            acquiredBlock =
                true;

            break;
        }
    }


    if (!acquiredBlock)
    {
        return;
    }


    uint freeBlockIndex =
        observedFreeCount - 1u;


    uint firstChildIndex =
        OctreeFreeNodeStack[
            freeBlockIndex
        ];


    int childLod =
        GetChildLod(
            node.lod
        );


    [unroll]
    for (
        uint splitChildOffset = 0u;
        splitChildOffset < 8u;
        splitChildOffset++
    )
    {
        uint childIndex =
            firstChildIndex +
            splitChildOffset;


        VoxelOctreeNode child;


        child.coord =
            GetChildCoordinate(
                node.coord,
                splitChildOffset
            );


        child.lod =
            childLod;


        child.canonicalOrigin =
            GetChildCanonicalOrigin(
                node,
                splitChildOffset
            );


        child.parentIndex =
            (int) nodeIndex;


        child.firstChildIndex =
            -1;


        child.state =
            OCTREE_NODE_LEAF;


        child.flags =
            OCTREE_FLAG_LOD_DIRTY;


        float3 childMin =
            CanonicalLatticeToWorld(
                child.canonicalOrigin
            );


        float childSize =
            GetNodeWorldSize(
                child
            );


        float3 childMax =
            childMin +
            float3(
                childSize,
                childSize,
                childSize
            );


        bool intersectsSurface =
            NodeIntersectsPlanetShell(
                childMin,
                childMax
            );


        if (intersectsSurface)
        {
            child.flags =
                SetOctreeFlag(
                    child.flags,
                    OCTREE_FLAG_SURFACE
                );


            child.flags =
                SetOctreeFlag(
                    child.flags,
                    OCTREE_FLAG_ACTIVE
                );


            child.flags =
                SetOctreeFlag(
                    child.flags,
                    OCTREE_FLAG_MESH_DIRTY
                );
        }


        child.neighborLODMask =
            0xFFFu;


        OctreeNodeBuffer[
            childIndex
        ] =
            child;
    }


    node.firstChildIndex =
        (int) firstChildIndex;


    node.state =
        OCTREE_NODE_INTERNAL;


    node.flags =
        ClearOctreeFlag(
            node.flags,
            OCTREE_FLAG_SPLIT_REQUEST
        );


    node.flags =
        SetOctreeFlag(
            node.flags,
            OCTREE_FLAG_LOD_DIRTY
        );


    node.flags =
        ClearOctreeFlag(
            node.flags,
            OCTREE_FLAG_ACTIVE
        );


    OctreeNodeBuffer[
        nodeIndex
    ] =
        node;


    InterlockedAdd(
        HierarchyChangedCountBuffer[0],
        1u
    );
}


// ============================================================
// APPLY MERGE REQUESTS
// ============================================================

[numthreads(64, 1, 1)]
void CSApplyMergeRequests(
    uint3 id : SV_DispatchThreadID)
{
    uint nodeIndex =
        id.x;


    if (MaxOctreeNodes <= 0)
    {
        return;
    }


    if (nodeIndex >=
        (uint) MaxOctreeNodes)
    {
        return;
    }


    VoxelOctreeNode node =
        OctreeNodeBuffer[
            nodeIndex
        ];


    if (node.state !=
        OCTREE_NODE_INTERNAL)
    {
        return;
    }


    if (!HasOctreeFlag(
        node.flags,
        OCTREE_FLAG_MERGE_REQUEST))
    {
        return;
    }


    if (node.parentIndex < 0)
    {
        node.flags =
            ClearOctreeFlag(
                node.flags,
                OCTREE_FLAG_MERGE_REQUEST
            );


        OctreeNodeBuffer[
            nodeIndex
        ] =
            node;


        return;
    }


    if (node.firstChildIndex < 0)
    {
        return;
    }


    uint firstChildIndex =
        (uint) node.firstChildIndex;


    if (firstChildIndex + 7u >=
        (uint) MaxOctreeNodes)
    {
        return;
    }


    bool canMerge =
        true;


    [unroll]
    for (
        uint mergeCheckOffset = 0u;
        mergeCheckOffset < 8u;
        mergeCheckOffset++
    )
    {
        uint childIndex =
            firstChildIndex +
            mergeCheckOffset;


        VoxelOctreeNode child =
            OctreeNodeBuffer[
                childIndex
            ];


        if (child.state !=
            OCTREE_NODE_LEAF)
        {
            canMerge =
                false;

            break;
        }


        if (child.parentIndex !=
            (int) nodeIndex)
        {
            canMerge =
                false;

            break;
        }


        if (HasOctreeFlag(
            child.flags,
            OCTREE_FLAG_SPLIT_REQUEST))
        {
            canMerge =
                false;

            break;
        }
    }


    if (!canMerge)
    {
        node.flags =
            ClearOctreeFlag(
                node.flags,
                OCTREE_FLAG_MERGE_REQUEST
            );


        OctreeNodeBuffer[
            nodeIndex
        ] =
            node;


        return;
    }


    uint freeStackIndex;
    uint previousFreeCount;


    InterlockedAdd(
        OctreeFreeNodeCountBuffer[0],
        1u,
        previousFreeCount
    );


    freeStackIndex =
        previousFreeCount;


    uint childBlockCount =
        (uint) ((MaxOctreeNodes - 1) >> 3);


    if (freeStackIndex >=
        childBlockCount)
    {
        InterlockedAdd(
            OctreeFreeNodeCountBuffer[0],
            (uint) -1
        );


        return;
    }


    OctreeFreeNodeStack[
        freeStackIndex
    ] =
        firstChildIndex;


    [unroll]
    for (
        uint mergeFreeOffset = 0u;
        mergeFreeOffset < 8u;
        mergeFreeOffset++
    )
    {
        uint childIndex =
            firstChildIndex +
            mergeFreeOffset;


        VoxelOctreeNode freeChild =
            OctreeNodeBuffer[
                childIndex
            ];


        freeChild.state =
            OCTREE_NODE_FREE;


        freeChild.flags =
            0u;


        freeChild.parentIndex =
            -1;


        freeChild.firstChildIndex =
            -1;


        OctreeNodeBuffer[
            childIndex
        ] =
            freeChild;
    }


    node.state =
        OCTREE_NODE_LEAF;


    node.firstChildIndex =
        -1;


    node.flags =
        ClearOctreeFlag(
            node.flags,
            OCTREE_FLAG_MERGE_REQUEST
        );


    node.flags =
        SetOctreeFlag(
            node.flags,
            OCTREE_FLAG_ACTIVE
        );


    node.flags =
        SetOctreeFlag(
            node.flags,
            OCTREE_FLAG_SURFACE
        );


    node.flags =
        SetOctreeFlag(
            node.flags,
            OCTREE_FLAG_MESH_DIRTY
        );


    node.flags =
        SetOctreeFlag(
            node.flags,
            OCTREE_FLAG_LOD_DIRTY
        );


    node.neighborLODMask =
        0xFFFu;


    OctreeNodeBuffer[
        nodeIndex
    ] =
        node;


    InterlockedAdd(
        HierarchyChangedCountBuffer[0],
        1u
    );
}


// ============================================================
// RESET ACTIVE LEAVES
// ============================================================

[numthreads(1, 1, 1)]
void CSResetActiveLeaves(
    uint3 id : SV_DispatchThreadID)
{
    ActiveLeafCountBuffer[0] =
        0u;
}


// ============================================================
// REBUILD ACTIVE LEAF LIST
// ============================================================

[numthreads(64, 1, 1)]
void CSRebuildActiveLeaves(
    uint3 id : SV_DispatchThreadID)
{
    uint nodeIndex =
        id.x;


    if (nodeIndex >=
        (uint) MaxOctreeNodes)
    {
        return;
    }


    VoxelOctreeNode node =
        OctreeNodeBuffer[
            nodeIndex
        ];


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


    uint activeLeafIndex;


    InterlockedAdd(
        ActiveLeafCountBuffer[0],
        1u,
        activeLeafIndex
    );


    if (activeLeafIndex >=
        (uint) MaxActiveLeaves)
    {
        return;
    }


    VoxelActiveLeaf activeLeaf;


    activeLeaf.nodeIndex =
        nodeIndex;


    activeLeaf.lod =
        (uint) node.lod;


    activeLeaf.canonicalOrigin =
        node.canonicalOrigin;


    activeLeaf.neighborLODMask =
        node.neighborLODMask;


    ActiveLeafBuffer[
        activeLeafIndex
    ] =
        activeLeaf;


    // ========================================================
    // ASSIGN COMPACT MESH SLOT
    // ========================================================
    //
    // The slot is the current active-leaf index.
    //
    // It is indexed by octree node index so topology and future
    // mesh generation can resolve:
    //
    //     nodeIndex -> activeLeafIndex
    //
    // without changing VoxelActiveLeaf layout.
    // ========================================================

    ActiveLeafMeshSlotBuffer[
        nodeIndex
    ] =
        activeLeafIndex;
}


// ============================================================
// RESET LOD STATS
// ============================================================

[numthreads(1, 1, 1)]
void CSResetLodStats(
    uint3 id : SV_DispatchThreadID)
{
    ActiveLeafMinLodBuffer[0] =
        0xFFFFFFFFu;


    ActiveLeafMaxLodBuffer[0] =
        0u;
}


// ============================================================
// CALCULATE LOD STATS
// ============================================================

[numthreads(64, 1, 1)]
void CSCalculateLodStats(
    uint3 id : SV_DispatchThreadID)
{
    uint leafIndex =
        id.x;


    uint activeLeafCount =
        ActiveLeafCountBuffer[0];


    if (leafIndex >=
        activeLeafCount)
    {
        return;
    }


    if (leafIndex >=
        (uint) MaxActiveLeaves)
    {
        return;
    }


    VoxelActiveLeaf activeLeaf =
        ActiveLeafBuffer[
            leafIndex
        ];


    uint leafLod =
        activeLeaf.lod;


    InterlockedMin(
        ActiveLeafMinLodBuffer[0],
        leafLod
    );


    InterlockedMax(
        ActiveLeafMaxLodBuffer[0],
        leafLod
    );
}


#endif