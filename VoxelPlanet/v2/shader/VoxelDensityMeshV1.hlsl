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


    TryGetLeafVertex(
        leafSlot,
        localCell,
        globalVertex);


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
// POLYGON PROJECTION
//
// Right-handed bases:
//
// X: Y,Z -> +X
// Y: Z,X -> +Y
// Z: X,Y -> +Z
// ============================================================================

float V1PolygonCoordinateU(
    float3 position,
    uint axis)
{
    if (axis == 0u)
        return position.y;

    if (axis == 1u)
        return position.z;

    return position.x;
}


float V1PolygonCoordinateV(
    float3 position,
    uint axis)
{
    if (axis == 0u)
        return position.z;

    if (axis == 1u)
        return position.x;

    return position.y;
}


float V1PolygonAngle(
    uint vertexIndex,
    float3 center,
    uint axis)
{
    float3 position =
        VertexBuffer[
            vertexIndex];


    float2 delta =
        float2(
            V1PolygonCoordinateU(
                position,
                axis) -
            V1PolygonCoordinateU(
                center,
                axis),

            V1PolygonCoordinateV(
                position,
                axis) -
            V1PolygonCoordinateV(
                center,
                axis));


    return atan2(
        delta.y,
        delta.x);
}


// ============================================================================
// SORT POLYGON VERTICES
// ============================================================================

void V1SortPolygonVertices(
    inout V1EdgePolygon polygon,
    uint axis)
{
    if (polygon.count < 3u)
        return;


    float3 center =
        float3(
            0.0f,
            0.0f,
            0.0f);


    if (polygon.vertices.x !=
        VOXEL_INVALID_NODE_INDEX)
    {
        center +=
            VertexBuffer[
                polygon.vertices.x];
    }


    if (polygon.vertices.y !=
        VOXEL_INVALID_NODE_INDEX)
    {
        center +=
            VertexBuffer[
                polygon.vertices.y];
    }


    if (polygon.vertices.z !=
        VOXEL_INVALID_NODE_INDEX)
    {
        center +=
            VertexBuffer[
                polygon.vertices.z];
    }


    if (polygon.count >= 4u &&
        polygon.vertices.w !=
        VOXEL_INVALID_NODE_INDEX)
    {
        center +=
            VertexBuffer[
                polygon.vertices.w];
    }


    center /=
        (float) polygon.count;


    float angle0 =
        V1PolygonAngle(
            polygon.vertices.x,
            center,
            axis);


    float angle1 =
        V1PolygonAngle(
            polygon.vertices.y,
            center,
            axis);


    float angle2 =
        V1PolygonAngle(
            polygon.vertices.z,
            center,
            axis);


    float angle3 =
        0.0f;


    if (polygon.count >= 4u)
    {
        angle3 =
            V1PolygonAngle(
                polygon.vertices.w,
                center,
                axis);
    }


    // ------------------------------------------------------------------------
    // Fixed sorting network.
    // ------------------------------------------------------------------------

    if (angle0 > angle1)
    {
        float tempAngle =
            angle0;

        angle0 =
            angle1;

        angle1 =
            tempAngle;


        uint tempVertex =
            polygon.vertices.x;

        polygon.vertices.x =
            polygon.vertices.y;

        polygon.vertices.y =
            tempVertex;
    }


    if (polygon.count >= 4u &&
        angle2 > angle3)
    {
        float tempAngle =
            angle2;

        angle2 =
            angle3;

        angle3 =
            tempAngle;


        uint tempVertex =
            polygon.vertices.z;

        polygon.vertices.z =
            polygon.vertices.w;

        polygon.vertices.w =
            tempVertex;
    }


    if (angle0 > angle2)
    {
        float tempAngle =
            angle0;

        angle0 =
            angle2;

        angle2 =
            tempAngle;


        uint tempVertex =
            polygon.vertices.x;

        polygon.vertices.x =
            polygon.vertices.z;

        polygon.vertices.z =
            tempVertex;
    }


    if (polygon.count >= 4u &&
        angle1 > angle3)
    {
        float tempAngle =
            angle1;

        angle1 =
            angle3;

        angle3 =
            tempAngle;


        uint tempVertex =
            polygon.vertices.y;

        polygon.vertices.y =
            polygon.vertices.w;

        polygon.vertices.w =
            tempVertex;
    }


    if (angle1 > angle2)
    {
        float tempAngle =
            angle1;

        angle1 =
            angle2;

        angle2 =
            tempAngle;


        uint tempVertex =
            polygon.vertices.y;

        polygon.vertices.y =
            polygon.vertices.z;

        polygon.vertices.z =
            tempVertex;
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


    // An incomplete incident-cell stencil must never be triangulated.
    // Emitting the remaining three vertices can create a long/crossed
    // triangle because they are not a complete edge-cycle.
    if (polygon.missingVertices > 0u)
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


    V1SortPolygonVertices(
        polygon,
        axis);


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