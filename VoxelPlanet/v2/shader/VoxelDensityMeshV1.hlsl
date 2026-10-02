#ifndef VOXEL_DENSITY_MESH_V1_INCLUDED
#define VOXEL_DENSITY_MESH_V1_INCLUDED

// V1 keeps the density/QEF vertex stage but replaces the old face passes.
// Connectivity is generated from sign-changing canonical primal edges.
#include "VoxelDensityMeshCommon.hlsl"
#include "VoxelDensityQEF.hlsl"
#include "VoxelDensityMeshVertices.hlsl"
#include "VoxelDensityMeshFinalize.hlsl"


struct V1EdgePolygon
{
    uint4 vertices;
    uint count;

    uint ownerNode;
    uint ownerSlot;

    uint finestLod;
    uint coarsestLod;

    uint missingVertices;
};


// ============================================================================
// EDGE COUNT
// ============================================================================

uint V1EdgeCountPerAxis(
    uint resolution)
{
    return resolution *
           (resolution + 1u) *
           (resolution + 1u);
}


// ============================================================================
// EDGE GRID DECODE
// ============================================================================

int3 V1DecodeEdgeGrid(
    uint axis,
    uint index,
    uint resolution)
{
    uint side =
        resolution + 1u;

    if (axis == 0u)
    {
        uint x =
            index % resolution;

        uint t =
            index / resolution;

        return int3(
            (int) x,
            (int) (t % side),
            (int) (t / side));
    }

    if (axis == 1u)
    {
        uint y =
            index % resolution;

        uint t =
            index / resolution;

        return int3(
            (int) (t % side),
            (int) y,
            (int) (t / side));
    }

    uint z =
        index % resolution;

    uint t =
        index / resolution;

    return int3(
        (int) (t % side),
        (int) (t / side),
        (int) z);
}


// ============================================================================
// AXIS OFFSET
// ============================================================================

int3 V1CanonicalAxisOffset(
    uint axis,
    int distance)
{
    if (axis == 0u)
        return int3(distance, 0, 0);

    if (axis == 1u)
        return int3(0, distance, 0);

    return int3(0, 0, distance);
}


// ============================================================================
// FIND LEAF AT CANONICAL POINT
// ============================================================================

int V1FindLeafAtCanonicalPoint(
    int3 sampleCoord)
{
    VoxelOctreeNode rootNode =
        OctreeNodeReadBuffer[0];


    int rootLod =
        clamp(
            rootNode.lod,
            0,
            25);


    int rootSpan =
        DEFAULT_CHUNK_RESOLUTION <<
        rootLod;


    int3 rootMin =
        rootNode.canonicalOrigin;


    int3 rootMax =
        rootMin +
        int3(
            rootSpan,
            rootSpan,
            rootSpan);


    if (sampleCoord.x < rootMin.x ||
        sampleCoord.x >= rootMax.x ||
        sampleCoord.y < rootMin.y ||
        sampleCoord.y >= rootMax.y ||
        sampleCoord.z < rootMin.z ||
        sampleCoord.z >= rootMax.z)
    {
        return -1;
    }


    int currentNodeIndex =
        0;


    for (
        int depth = 0;
        depth < 32;
        ++depth)
    {
        if (currentNodeIndex < 0 ||
            currentNodeIndex >= MaxOctreeNodes)
        {
            return -1;
        }


        VoxelOctreeNode currentNode =
            OctreeNodeReadBuffer[
                currentNodeIndex];


        if (currentNode.state ==
            OCTREE_NODE_LEAF)
        {
            return currentNodeIndex;
        }


        if (currentNode.state !=
                OCTREE_NODE_INTERNAL ||
            currentNode.firstChildIndex < 0)
        {
            return -1;
        }


        int nodeLod =
            clamp(
                currentNode.lod,
                0,
                25);


        int halfSpan =
            (DEFAULT_CHUNK_RESOLUTION <<
             nodeLod) >> 1;


        int3 localCoord =
            sampleCoord -
            currentNode.canonicalOrigin;


        uint childOffset =
            0u;


        if (localCoord.x >= halfSpan)
            childOffset |= 1u;

        if (localCoord.y >= halfSpan)
            childOffset |= 2u;

        if (localCoord.z >= halfSpan)
            childOffset |= 4u;


        currentNodeIndex =
            currentNode.firstChildIndex +
            (int) childOffset;
    }


    return -1;
}


// ============================================================================
// MISSING INCIDENT CELL STAND-IN
//
// A neighbouring leaf only owns a dual vertex where the surface crosses one of
// its own cells. Along an LOD transition the coarser cell that contains a fine
// edge can be empty (the planet shell test keeps those leaves active even when
// the fine surface does not reach the coarse cell corners), so the four cell
// stencil of that edge cannot be completed. Emitting the polygon with fewer
// vertices, or dropping it, is what opened the holes along the transitions.
//
// Instead reuse the nearest cell of the same leaf that does own a vertex. The
// search order is fixed and the vertex hash is only read, so every polygon that
// refers to the same cell resolves the identical stand-in vertex and the poly-
// gon loop around the transition stays closed.
// ============================================================================

static const int V1_STANDIN_SEARCH_RADIUS =
    2;


bool V1TryResolveStandInVertex(
    uint leafSlot,
    int3 cell,
    out uint globalVertex)
{
    globalVertex =
        VOXEL_INVALID_NODE_INDEX;


    [loop]
    for (int radius = 1;
         radius <= V1_STANDIN_SEARCH_RADIUS;
         ++radius)
    {
        [loop]
        for (int dz = -radius;
             dz <= radius;
             ++dz)
        {
            [loop]
            for (int dy = -radius;
                 dy <= radius;
                 ++dy)
            {
                [loop]
                for (int dx = -radius;
                     dx <= radius;
                     ++dx)
                {
                    int shellDistance =
                        max(
                            abs(dx),
                            max(
                                abs(dy),
                                abs(dz)));


                    if (shellDistance !=
                        radius)
                    {
                        continue;
                    }


                    int3 candidate =
                        cell +
                        int3(
                            dx,
                            dy,
                            dz);


                    if (any(candidate < 0) ||
                        any(candidate >= CellCount))
                    {
                        continue;
                    }


                    uint localIndex =
                        GetVertexIndex(
                            candidate.x,
                            candidate.y,
                            candidate.z);


                    if (TryGetLeafVertex(
                            leafSlot,
                            localIndex,
                            globalVertex))
                    {
                        InterlockedOr(
                            MeshOverflowFlagsBuffer[0],
                            MESH_DIAGNOSTIC_TRANSITION_STANDIN_VERTEX);

                        return true;
                    }
                }
            }
        }
    }


    globalVertex =
        VOXEL_INVALID_NODE_INDEX;


    return false;
}


// ============================================================================
// RESOLVE INCIDENT CELL
//
// sampleCoord uses a one-unit canonical offset to classify which cell lies
// on each side of the primal edge. The actual cell size of the found leaf
// is then used below when resolving its local vertex.
// ============================================================================

bool V1ResolveIncidentCell(
    int3 edgeStart,
    uint axis,
    int sideA,
    int sideB,
    out uint nodeIndex,
    out uint leafSlot,
    out uint globalVertex)
{
    nodeIndex =
        VOXEL_INVALID_NODE_INDEX;

    leafSlot =
        VOXEL_INVALID_NODE_INDEX;

    globalVertex =
        VOXEL_INVALID_NODE_INDEX;


    int3 sampleCoord =
        edgeStart;


    if (axis == 0u)
    {
        sampleCoord.y +=
            sideA < 0
            ? -1
            : 0;

        sampleCoord.z +=
            sideB < 0
            ? -1
            : 0;
    }
    else if (axis == 1u)
    {
        sampleCoord.x +=
            sideA < 0
            ? -1
            : 0;

        sampleCoord.z +=
            sideB < 0
            ? -1
            : 0;
    }
    else
    {
        sampleCoord.x +=
            sideA < 0
            ? -1
            : 0;

        sampleCoord.y +=
            sideB < 0
            ? -1
            : 0;
    }


    int foundNode =
        V1FindLeafAtCanonicalPoint(
            sampleCoord);


    if (foundNode < 0 ||
        foundNode >= MaxOctreeNodes)
    {
        return false;
    }


    nodeIndex =
        (uint) foundNode;


    VoxelOctreeNode node =
        OctreeNodeReadBuffer[
            nodeIndex];


    if (node.state !=
            OCTREE_NODE_LEAF ||
        node.lod < 0 ||
        node.lod > 25)
    {
        return false;
    }


    leafSlot =
        ActiveLeafMeshSlotReadBuffer[
            nodeIndex];


    if (leafSlot >=
        ActiveLeafCountReadBuffer[0])
    {
        return false;
    }


    // CSResetActiveLeaves() only clears the active leaf count, so a node that is
    // no longer an active leaf keeps a stale slot from an earlier frame. Reject
    // it here instead of resolving a vertex from an unrelated leaf.
    if (ActiveLeafReadBuffer[
            leafSlot].nodeIndex !=
        nodeIndex)
    {
        return false;
    }


    int canonicalStep =
        1 << node.lod;


    int3 relative =
        sampleCoord -
        node.canonicalOrigin;


    int3 cell =
        relative /
        canonicalStep;


    if (any(cell < 0) ||
        any(cell >= CellCount))
    {
        return false;
    }


    uint localCell =
        GetVertexIndex(
            cell.x,
            cell.y,
            cell.z);


    if (!TryGetLeafVertex(
            leafSlot,
            localCell,
            globalVertex))
    {
        V1TryResolveStandInVertex(
            leafSlot,
            cell,
            globalVertex);
    }


    return true;
}


// ============================================================================
// UNIQUE VERTEX APPEND
// ============================================================================

void V1AppendUnique(
    inout V1EdgePolygon polygon,
    uint vertex)
{
    if (vertex ==
        VOXEL_INVALID_NODE_INDEX)
    {
        return;
    }


    if (polygon.count > 0u &&
        polygon.vertices.x == vertex)
    {
        return;
    }


    if (polygon.count > 1u &&
        polygon.vertices.y == vertex)
    {
        return;
    }


    if (polygon.count > 2u &&
        polygon.vertices.z == vertex)
    {
        return;
    }


    if (polygon.count > 3u &&
        polygon.vertices.w == vertex)
    {
        return;
    }


    if (polygon.count == 0u)
    {
        polygon.vertices.x =
            vertex;
    }
    else if (polygon.count == 1u)
    {
        polygon.vertices.y =
            vertex;
    }
    else if (polygon.count == 2u)
    {
        polygon.vertices.z =
            vertex;
    }
    else if (polygon.count == 3u)
    {
        polygon.vertices.w =
            vertex;
    }
    else
    {
        return;
    }


    polygon.count++;
}


// ============================================================================
// ACCUMULATE INCIDENT CELL
// ============================================================================

void V1AccumulateIncidentCell(
    int3 edgeStart,
    uint axis,
    int sideA,
    int sideB,
    inout V1EdgePolygon polygon)
{
    uint nodeIndex;
    uint neighborSlot;
    uint vertexIndex;


    if (!V1ResolveIncidentCell(
            edgeStart,
            axis,
            sideA,
            sideB,
            nodeIndex,
            neighborSlot,
            vertexIndex))
    {
        polygon.missingVertices++;
        return;
    }


    uint lod =
        ActiveLeafReadBuffer[
            neighborSlot].lod;


    // Determine owner BEFORE updating finestLod.
    bool takeOwnership =
        polygon.ownerNode ==
        VOXEL_INVALID_NODE_INDEX;


    if (!takeOwnership)
    {
        uint currentOwnerLod =
            ActiveLeafReadBuffer[
                polygon.ownerSlot].lod;


        takeOwnership =
            lod < currentOwnerLod ||
            (
                lod == currentOwnerLod &&
                nodeIndex < polygon.ownerNode
            );
    }


    if (takeOwnership)
    {
        polygon.ownerNode =
            nodeIndex;

        polygon.ownerSlot =
            neighborSlot;
    }


    polygon.finestLod =
        min(
            polygon.finestLod,
            lod);


    polygon.coarsestLod =
        max(
            polygon.coarsestLod,
            lod);


    if (vertexIndex ==
        VOXEL_INVALID_NODE_INDEX)
    {
        polygon.missingVertices++;
    }
    else
    {
        V1AppendUnique(
            polygon,
            vertexIndex);
    }
}


// ============================================================================
// BUILD EDGE POLYGON
// ============================================================================

bool V1BuildEdgePolygon(
    uint leafSlot,
    VoxelActiveLeaf leaf,
    uint axis,
    int3 edgeGrid,
    out V1EdgePolygon polygon,
    out float densityA,
    out float densityB)
{
    polygon.vertices =
        uint4(
            VOXEL_INVALID_NODE_INDEX,
            VOXEL_INVALID_NODE_INDEX,
            VOXEL_INVALID_NODE_INDEX,
            VOXEL_INVALID_NODE_INDEX);


    polygon.count =
        0u;


    polygon.ownerNode =
        VOXEL_INVALID_NODE_INDEX;


    polygon.ownerSlot =
        VOXEL_INVALID_NODE_INDEX;


    polygon.finestLod =
        0xFFFFFFFFu;


    polygon.coarsestLod =
        0u;


    polygon.missingVertices =
        0u;


    densityA =
        0.0f;

    densityB =
        0.0f;


    if (leafSlot >=
        ActiveLeafCountReadBuffer[0])
    {
        return false;
    }


    int canonicalStep =
        1 << (int) leaf.lod;


    int3 edgeStart =
        leaf.canonicalOrigin +
        edgeGrid *
        canonicalStep;


    int3 edgeEnd =
        edgeStart +
        V1CanonicalAxisOffset(
            axis,
            canonicalStep);


    float3 worldA =
        (float3) edgeStart *
        BASE_LATTICE_SIZE;


    float3 worldB =
        (float3) edgeEnd *
        BASE_LATTICE_SIZE;


    densityA =
        SampleDensity(
            worldA);


    densityB =
        SampleDensity(
            worldB);


    if (!IsFiniteFloat(densityA) ||
        !IsFiniteFloat(densityB) ||
        !IsSignChange(
            densityA,
            densityB))
    {
        return false;
    }


    // ------------------------------------------------------------------------
    // Four incident cells.
    // ------------------------------------------------------------------------

    if (axis == 0u)
    {
        V1AccumulateIncidentCell(
            edgeStart,
            axis,
            -1,
            -1,
            polygon);

        V1AccumulateIncidentCell(
            edgeStart,
            axis,
             1,
            -1,
            polygon);

        V1AccumulateIncidentCell(
            edgeStart,
            axis,
             1,
             1,
            polygon);

        V1AccumulateIncidentCell(
            edgeStart,
            axis,
            -1,
             1,
            polygon);
    }
    else if (axis == 1u)
    {
        V1AccumulateIncidentCell(
            edgeStart,
            axis,
            -1,
            -1,
            polygon);

        V1AccumulateIncidentCell(
            edgeStart,
            axis,
            -1,
             1,
            polygon);

        V1AccumulateIncidentCell(
            edgeStart,
            axis,
             1,
             1,
            polygon);

        V1AccumulateIncidentCell(
            edgeStart,
            axis,
             1,
            -1,
            polygon);
    }
    else
    {
        V1AccumulateIncidentCell(
            edgeStart,
            axis,
            -1,
            -1,
            polygon);

        V1AccumulateIncidentCell(
            edgeStart,
            axis,
             1,
            -1,
            polygon);

        V1AccumulateIncidentCell(
            edgeStart,
            axis,
             1,
             1,
            polygon);

        V1AccumulateIncidentCell(
            edgeStart,
            axis,
            -1,
             1,
            polygon);
    }


    if (polygon.missingVertices > 0u)
    {
        InterlockedOr(
            MeshOverflowFlagsBuffer[0],
            MESH_DIAGNOSTIC_TRANSITION_MISSING_VERTICES);
    }


    // ------------------------------------------------------------------------
    // Only the owner emits this polygon.
    // ------------------------------------------------------------------------

    if (polygon.ownerNode !=
        leaf.nodeIndex)
    {
        return false;
    }


    if (polygon.finestLod <
        leaf.lod)
    {
        return false;
    }


    if (polygon.count < 3u)
    {
        InterlockedOr(
            MeshOverflowFlagsBuffer[0],
            MESH_DIAGNOSTIC_DROPPED_EDGE_POLYGON);

        return false;
    }


    // The four incident cells are appended above in a fixed topological cycle
    // around the primal edge, so the polygon already has a correct, crack free
    // vertex order. Sorting the vertices by their solved positions can swap two
    // neighbours when a QEF vertex moves inside its cell: the quad becomes a bow
    // tie, the triangle fan then covers the wrong half and leaves a lens shaped
    // hole plus unpaired edges.


    return true;
}


// ============================================================================
// POLYGON INDEX COUNT
// ============================================================================

uint V1PolygonIndexCount(
    V1EdgePolygon polygon)
{
    return polygon.count >= 3u
        ? (polygon.count - 2u) * 3u
        : 0u;
}


// ============================================================================
// COUNT INDICES
// ============================================================================

void CSCountLeafMeshIndicesImpl(
    uint3 groupId,
    uint3 groupThreadId)
{
    uint leafSlot =
        GetLeafSlot(groupId);


    if (!IsActiveLeafSlot(
            leafSlot))
    {
        return;
    }


    VoxelActiveLeaf leaf =
        ActiveLeafReadBuffer[
            leafSlot];


    uint resolution =
        (uint) CellCount;


    if (resolution == 0u)
        return;


    uint perAxis =
        V1EdgeCountPerAxis(
            resolution);


    uint total =
        perAxis * 3u;


    uint count =
        0u;


    for (
        uint edgeIndex = groupThreadId.x;
        edgeIndex < total;
        edgeIndex += LEAF_MESH_THREADS_PER_LEAF)
    {
        uint axis =
            edgeIndex /
            perAxis;


        uint axisIndex =
            edgeIndex -
            axis * perAxis;


        int3 edgeGrid =
            V1DecodeEdgeGrid(
                axis,
                axisIndex,
                resolution);


        V1EdgePolygon polygon;

        float densityA;
        float densityB;


        if (V1BuildEdgePolygon(
                leafSlot,
                leaf,
                axis,
                edgeGrid,
                polygon,
                densityA,
                densityB))
        {
            count +=
                V1PolygonIndexCount(
                    polygon);
        }
    }


    if (count > 0u)
    {
        InterlockedAdd(
            ActiveLeafMeshIndexCounterBuffer[
                leafSlot],
            count);
    }
}


// ============================================================================
// SCAN INDEX OFFSETS
// ============================================================================

void CSScanLeafMeshIndexOffsetsImpl(
    uint3 id : SV_DispatchThreadID)
{
    if (id.x != 0u)
        return;


    uint activeCount =
        min(
            ActiveLeafCountReadBuffer[0],
            (uint) MaxActiveLeaves);


    uint cursor =
        0u;


    uint capacity =
        (uint) MeshIndexArenaCapacity;


    for (
        uint slot = 0u;
        slot < activeCount;
        ++slot)
    {
        VoxelLeafMeshInfo info =
            ActiveLeafMeshInfoBuffer[
                slot];


        uint requested =
            ActiveLeafMeshIndexCounterBuffer[
                slot];


        uint available =
            cursor < capacity
            ? capacity - cursor
            : 0u;


        uint reserved =
            min(
                requested,
                available);


        reserved =
            (reserved / 3u) * 3u;


        info.indexBase =
            cursor;


        info.indexCapacity =
            reserved;


        info.indexCount =
            0u;


        ActiveLeafMeshInfoBuffer[
            slot] =
            info;


        ActiveLeafMeshIndexCounterBuffer[
            slot] =
            0u;


        if (reserved < requested)
        {
            InterlockedOr(
                MeshOverflowFlagsBuffer[0],
                MESH_OVERFLOW_INDEX_ARENA);
        }


        cursor +=
            reserved;
    }


    IndexCountBuffer[0] =
        0u;
}


// ============================================================================
// WRITE POLYGON
// ============================================================================

void V1WritePolygon(
    uint ownerSlot,
    V1EdgePolygon polygon,
    bool positiveWinding)
{
    uint indexCount =
        V1PolygonIndexCount(
            polygon);


    if (indexCount == 0u)
        return;


    if (!positiveWinding)
    {
        if (polygon.count == 3u)
        {
            uint temp =
                polygon.vertices.y;

            polygon.vertices.y =
                polygon.vertices.z;

            polygon.vertices.z =
                temp;
        }
        else
        {
            uint temp =
                polygon.vertices.y;

            polygon.vertices.y =
                polygon.vertices.w;

            polygon.vertices.w =
                temp;
        }
    }


    uint writeOffset;


    InterlockedAdd(
        ActiveLeafMeshIndexCounterBuffer[
            ownerSlot],
        indexCount,
        writeOffset);


    VoxelLeafMeshInfo info =
        ActiveLeafMeshInfoReadBuffer[
            ownerSlot];


    if (writeOffset + indexCount >
        info.indexCapacity)
    {
        InterlockedOr(
            MeshOverflowFlagsBuffer[0],
            MESH_OVERFLOW_INDEX_WRITE);

        return;
    }


    uint cursor =
        info.indexBase +
        writeOffset;


    if (polygon.count == 3u)
    {
        IndexBuffer[cursor++] =
            polygon.vertices.x;

        IndexBuffer[cursor++] =
            polygon.vertices.y;

        IndexBuffer[cursor++] =
            polygon.vertices.z;
    }
    else if (polygon.count == 4u)
    {
        IndexBuffer[cursor++] =
            polygon.vertices.x;

        IndexBuffer[cursor++] =
            polygon.vertices.y;

        IndexBuffer[cursor++] =
            polygon.vertices.z;


        IndexBuffer[cursor++] =
            polygon.vertices.x;

        IndexBuffer[cursor++] =
            polygon.vertices.z;

        IndexBuffer[cursor++] =
            polygon.vertices.w;
    }
}


// ============================================================================
// BUILD AXIS EDGES
// ============================================================================

void V1BuildAxisEdges(
    uint3 groupId,
    uint3 groupThreadId,
    uint axis)
{
    uint leafSlot =
        GetLeafSlot(groupId);


    if (!IsActiveLeafSlot(
            leafSlot))
    {
        return;
    }


    VoxelActiveLeaf leaf =
        ActiveLeafReadBuffer[
            leafSlot];


    uint resolution =
        (uint) CellCount;


    uint total =
        V1EdgeCountPerAxis(
            resolution);


    for (
        uint edgeIndex = groupThreadId.x;
        edgeIndex < total;
        edgeIndex += LEAF_MESH_THREADS_PER_LEAF)
    {
        int3 edgeGrid =
            V1DecodeEdgeGrid(
                axis,
                edgeIndex,
                resolution);


        V1EdgePolygon polygon;

        float densityA;
        float densityB;


        if (!V1BuildEdgePolygon(
                leafSlot,
                leaf,
                axis,
                edgeGrid,
                polygon,
                densityA,
                densityB))
        {
            continue;
        }


        V1WritePolygon(
            polygon.ownerSlot,
            polygon,
            densityA < densityB);
    }
}


// ============================================================================
// X FACES
// ============================================================================

void CSBuildXFacesImpl(
    uint3 groupId,
    uint3 groupThreadId)
{
    V1BuildAxisEdges(
        groupId,
        groupThreadId,
        0u);
}


// ============================================================================
// Y FACES
// ============================================================================

void CSBuildYFacesImpl(
    uint3 groupId,
    uint3 groupThreadId)
{
    V1BuildAxisEdges(
        groupId,
        groupThreadId,
        1u);
}


// ============================================================================
// Z FACES
// ============================================================================

void CSBuildZFacesImpl(
    uint3 groupId,
    uint3 groupThreadId)
{
    V1BuildAxisEdges(
        groupId,
        groupThreadId,
        2u);
}


// ============================================================================
// LEAF BOUNDARY FACES
// ============================================================================

// All leaf-boundary edges are enumerated by the three axis passes above.
void CSBuildLeafBoundaryFacesImpl(
    uint3 groupId,
    uint3 groupThreadId)
{
}


#endif