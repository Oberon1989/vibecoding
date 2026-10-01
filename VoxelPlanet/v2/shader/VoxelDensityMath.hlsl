#ifndef VOXEL_DENSITY_MATH_INCLUDED
#define VOXEL_DENSITY_MATH_INCLUDED


#include "VoxelDensityTypes.hlsl"


// ============================================================
// CANONICAL BASE LATTICE
// ============================================================
//
// Finest terrain resolution:
//
//     LOD 0 = 0.5 m
//
// Every higher LOD doubles the cell size:
//
//     LOD 0 = 0.5 m
//     LOD 1 = 1.0 m
//     LOD 2 = 2.0 m
//     LOD 3 = 4.0 m
//     ...
//
// All LODs remain aligned to the same canonical lattice.
// ============================================================

static const float BASE_LATTICE_SIZE =
    0.5f;


// ============================================================
// DEFAULT CHUNK RESOLUTION
// ============================================================
//
// Production chunk:
//
//     32 × 32 × 32 cells
//
// The current test shader still receives CellCount from C#.
// Therefore this constant is used only by the future GPU
// hierarchy helpers.
// ============================================================

static const int DEFAULT_CHUNK_RESOLUTION =
    32;


// ============================================================
// FINITE FLOAT CHECKS
// ============================================================
//
// Intentionally no:
//
//     isnan()
//     isinf()
//     asuint()
//
// This keeps the shader compatible with the Unity DX11/DX12
// compilation path we are currently targeting.
//
// NaN:
//
//     value == value
//
// is false.
//
// The large finite range rejects IEEE floating-point infinity.
// ============================================================

bool IsFiniteFloat(
    float value)
{
    return
        value == value &&
        value < 1.0e30f &&
        value > -1.0e30f;
}


bool IsFiniteFloat2(
    float2 value)
{
    return
        IsFiniteFloat(value.x) &&
        IsFiniteFloat(value.y);
}


bool IsFiniteFloat3(
    float3 value)
{
    return
        IsFiniteFloat(value.x) &&
        IsFiniteFloat(value.y) &&
        IsFiniteFloat(value.z);
}


bool IsFiniteFloat4(
    float4 value)
{
    return
        IsFiniteFloat(value.x) &&
        IsFiniteFloat(value.y) &&
        IsFiniteFloat(value.z) &&
        IsFiniteFloat(value.w);
}


// ============================================================
// SAFE NORMALIZE
// ============================================================

float3 SafeNormalize(
    float3 value,
    float3 fallback)
{
    float lengthSquared =
        dot(
            value,
            value
        );


    if (!IsFiniteFloat(lengthSquared) ||
        lengthSquared <= NORMAL_EPSILON)
    {
        return fallback;
    }


    float inverseLength =
        rsqrt(
            lengthSquared
        );


    float3 result =
        value *
        inverseLength;


    if (!IsFiniteFloat3(result))
    {
        return fallback;
    }


    return result;
}


// ============================================================
// CURRENT SINGLE-CHUNK VERTEX INDEX
// ============================================================
//
// Current buffer layout:
//
//     x + CellCount * (y + CellCount * z)
//
// Kept exactly compatible with the existing single-chunk
// renderer.
// ============================================================

uint GetVertexIndex(
    int x,
    int y,
    int z)
{
    return
        (uint) (
            x +
            CellCount *
            (
                y +
                CellCount * z
            )
        );
}


// ============================================================
// CURRENT CELL RESOLUTION
// ============================================================
//
// CellCount = number of samples.
//
// Therefore:
//
//     resolution = CellCount - 1
// ============================================================

int GetCellResolution()
{
    return
        CellCount - 1;
}


// ============================================================
// CURRENT CELL COORDINATE VALIDATION
// ============================================================

bool IsValidCellCoordinate(
    int3 cellCoordinate)
{
    int resolution =
        GetCellResolution();


    return
        cellCoordinate.x >= 0 &&
        cellCoordinate.y >= 0 &&
        cellCoordinate.z >= 0 &&

        cellCoordinate.x < resolution &&
        cellCoordinate.y < resolution &&
        cellCoordinate.z < resolution;
}


// ============================================================
// LOD → CELL SIZE
// ============================================================
//
//     LOD 0 = 0.5 m
//     LOD 1 = 1.0 m
//     LOD 2 = 2.0 m
//     LOD 3 = 4.0 m
//
// A simple multiplication loop is used instead of pow().
// ============================================================

float GetLODCellSize(
    int lod)
{
    if (lod <= 0)
    {
        return
            BASE_LATTICE_SIZE;
    }


    float cellSize =
        BASE_LATTICE_SIZE;


    [loop]
    for (int lodIndex = 0;
         lodIndex < lod;
         lodIndex++)
    {
        cellSize *=
            2.0f;
    }


    return
        cellSize;
}


// ============================================================
// LOD → CANONICAL STRIDE
// ============================================================
//
// Number of finest 0.5 m lattice intervals represented by one
// cell at this LOD.
//
//     LOD 0 = 1
//     LOD 1 = 2
//     LOD 2 = 4
//     LOD 3 = 8
// ============================================================

int GetLODLatticeStride(
    int lod)
{
    if (lod <= 0)
    {
        return 1;
    }


    int stride =
        1;


    [loop]
    for (int lodIndex = 0;
         lodIndex < lod;
         lodIndex++)
    {
        stride *=
            2;
    }


    return
        stride;
}


// ============================================================
// FIXED CHUNK WORLD SIZE
// ============================================================
//
// Production hierarchy uses DEFAULT_CHUNK_RESOLUTION cells.
//
// Current single-chunk test does not use this helper for its
// existing Step/Origin path.
// ============================================================

float GetChunkWorldSize(
    int resolution,
    int lod)
{
    return
        (float) resolution *
        GetLODCellSize(
            lod
        );
}


// ============================================================
// LOCAL CELL MIN
// ============================================================

float3 GetLocalCellMin(
    int3 cellCoordinate,
    float cellSize)
{
    return
        float3(
            cellCoordinate
        )
        *
        cellSize;
}


// ============================================================
// LOCAL CELL CENTER
// ============================================================

float3 GetLocalCellCenter(
    int3 cellCoordinate,
    float cellSize)
{
    return
        (
            float3(
                cellCoordinate
            )
            +
            float3(
                0.5f,
                0.5f,
                0.5f
            )
        )
        *
        cellSize;
}


// ============================================================
// LOCAL CELL MAX
// ============================================================

float3 GetLocalCellMax(
    int3 cellCoordinate,
    float cellSize)
{
    return
        (
            float3(
                cellCoordinate
            )
            +
            float3(
                1.0f,
                1.0f,
                1.0f
            )
        )
        *
        cellSize;
}


// ============================================================
// WORLD CELL MIN
// ============================================================

float3 GetWorldCellMin(
    float3 chunkOrigin,
    int3 cellCoordinate,
    float cellSize)
{
    return
        chunkOrigin +
        GetLocalCellMin(
            cellCoordinate,
            cellSize
        );
}


// ============================================================
// WORLD CELL CENTER
// ============================================================

float3 GetWorldCellCenter(
    float3 chunkOrigin,
    int3 cellCoordinate,
    float cellSize)
{
    return
        chunkOrigin +
        GetLocalCellCenter(
            cellCoordinate,
            cellSize
        );
}


// ============================================================
// WORLD CELL MAX
// ============================================================

float3 GetWorldCellMax(
    float3 chunkOrigin,
    int3 cellCoordinate,
    float cellSize)
{
    return
        chunkOrigin +
        GetLocalCellMax(
            cellCoordinate,
            cellSize
        );
}


// ============================================================
// WORLD → CANONICAL LATTICE
// ============================================================
//
// Converts a world position to an integer coordinate on the
// global 0.5 m lattice.
//
// The coordinate is intended to be used for deterministic
// boundary addressing.
// ============================================================

int3 WorldToCanonicalLattice(
    float3 worldPosition)
{
    float3 latticePosition =
        worldPosition /
        BASE_LATTICE_SIZE;


    return
        int3(
            round(latticePosition.x),
            round(latticePosition.y),
            round(latticePosition.z)
        );
}


// ============================================================
// CANONICAL LATTICE → WORLD
// ============================================================

float3 CanonicalLatticeToWorld(
    int3 canonicalCoordinate)
{
    return
        float3(
            canonicalCoordinate
        )
        *
        BASE_LATTICE_SIZE;
}


// ============================================================
// WORLD → LOD LATTICE
// ============================================================
//
// Returns integer coordinates on the selected LOD lattice.
//
// Since all LODs are multiples of 0.5 m, every LOD remains
// aligned to the same canonical grid.
// ============================================================

int3 WorldToLODLattice(
    float3 worldPosition,
    int lod)
{
    float cellSize =
        GetLODCellSize(
            lod
        );


    float3 latticePosition =
        worldPosition /
        cellSize;


    return
        int3(
            round(latticePosition.x),
            round(latticePosition.y),
            round(latticePosition.z)
        );
}


// ============================================================
// LOD LATTICE → WORLD
// ============================================================

float3 LODLatticeToWorld(
    int3 latticeCoordinate,
    int lod)
{
    return
        float3(
            latticeCoordinate
        )
        *
        GetLODCellSize(
            lod
        );
}


// ============================================================
// CHUNK → CANONICAL ORIGIN
// ============================================================
//
// The chunk contains DEFAULT_CHUNK_RESOLUTION cells.
//
// Each cell covers GetLODLatticeStride(lod) base lattice units.
//
// Therefore:
//
//     chunk span =
//         DEFAULT_CHUNK_RESOLUTION * stride
//
// The calculation is integer-only.
// ============================================================

int3 GetChunkCanonicalOrigin(
    int3 chunkCoordinate,
    int resolution,
    int lod)
{
    int stride =
        GetLODLatticeStride(
            lod
        );


    int cellsPerChunkInCanonicalUnits =
        resolution *
        stride;


    return
        chunkCoordinate *
        cellsPerChunkInCanonicalUnits;
}


// ============================================================
// CHUNK → WORLD ORIGIN
// ============================================================

float3 GetChunkWorldOrigin(
    int3 chunkCoordinate,
    int resolution,
    int lod)
{
    int3 canonicalOrigin =
        GetChunkCanonicalOrigin(
            chunkCoordinate,
            resolution,
            lod
        );


    return
        CanonicalLatticeToWorld(
            canonicalOrigin
        );
}


// ============================================================
// CHUNK WORLD SIZE
// ============================================================

float GetChunkSizeFromLOD(
    int resolution,
    int lod)
{
    return
        (float) resolution *
        GetLODCellSize(
            lod
        );
}


// ============================================================
// CHUNK LOCAL SAMPLE → CANONICAL COORDINATE
// ============================================================
//
// localSampleCoordinate:
//
//     0 .. resolution
//
// includes the final boundary sample.
// ============================================================

int3 GetCanonicalSampleCoordinate(
    int3 chunkCoordinate,
    int3 localSampleCoordinate,
    int resolution,
    int lod)
{
    int3 canonicalOrigin =
        GetChunkCanonicalOrigin(
            chunkCoordinate,
            resolution,
            lod
        );


    int stride =
        GetLODLatticeStride(
            lod
        );


    return
        canonicalOrigin +
        localSampleCoordinate *
        stride;
}


// ============================================================
// CANONICAL SAMPLE → WORLD
// ============================================================

float3 GetCanonicalSampleWorldPosition(
    int3 canonicalCoordinate)
{
    return
        CanonicalLatticeToWorld(
            canonicalCoordinate
        );
}


// ============================================================
// OCTREE NODE CELL SIZE
// ============================================================

float GetNodeCellSize(
    VoxelOctreeNode node)
{
    return
        GetLODCellSize(
            node.lod
        );
}


// ============================================================
// OCTREE NODE LATTICE STRIDE
// ============================================================

int GetNodeLatticeStride(
    VoxelOctreeNode node)
{
    return
        GetLODLatticeStride(
            node.lod
        );
}


// ============================================================
// OCTREE NODE WORLD ORIGIN
// ============================================================
//
// canonicalOrigin is authoritative.
//
// World coordinates are reconstructed from the integer canonical
// lattice rather than accumulated floating-point offsets.
// ============================================================

float3 GetNodeWorldOrigin(
    VoxelOctreeNode node)
{
    return
        CanonicalLatticeToWorld(
            node.canonicalOrigin
        );
}


// ============================================================
// OCTREE NODE WORLD SIZE
// ============================================================
//
// VoxelOctreeNode intentionally does NOT store resolution.
//
// The persistent hierarchy uses a fixed chunk resolution:
//
//     DEFAULT_CHUNK_RESOLUTION
//
// Therefore the physical node/chunk size is:
//
//     resolution * cellSize
// ============================================================

float GetNodeWorldSize(
    VoxelOctreeNode node)
{
    return
        (float) DEFAULT_CHUNK_RESOLUTION *
        GetNodeCellSize(
            node
        );
}


// ============================================================
// NODE WORLD MIN
// ============================================================

float3 GetNodeWorldMin(
    VoxelOctreeNode node)
{
    return
        GetNodeWorldOrigin(
            node
        );
}


// ============================================================
// NODE WORLD MAX
// ============================================================

float3 GetNodeWorldMax(
    VoxelOctreeNode node)
{
    float size =
        GetNodeWorldSize(
            node
        );


    return
        GetNodeWorldOrigin(
            node
        )
        +
        float3(
            size,
            size,
            size
        );
}


// ============================================================
// NODE WORLD CENTER
// ============================================================

float3 GetNodeWorldCenter(
    VoxelOctreeNode node)
{
    float size =
        GetNodeWorldSize(
            node
        );


    return
        GetNodeWorldOrigin(
            node
        )
        +
        float3(
            size * 0.5f,
            size * 0.5f,
            size * 0.5f
        );
}


// ============================================================
// NODE CHILD CANONICAL ORIGIN
// ============================================================
//
// The parent is split into eight children.
//
// Since the hierarchy uses a fixed number of cells per chunk:
//
//     parent span =
//         DEFAULT_CHUNK_RESOLUTION * parent stride
//
// and each child occupies half of that span.
//
// The calculation remains entirely integer-based.
// ============================================================

int3 GetChildCanonicalOrigin(
    VoxelOctreeNode parentNode,
    uint childIndex)
{
    int3 parentOrigin =
        parentNode.canonicalOrigin;


    int parentLatticeSpan =
        DEFAULT_CHUNK_RESOLUTION *
        GetNodeLatticeStride(
            parentNode
        );


    int childLatticeSpan =
    parentLatticeSpan >>
    1;


    int3 childOffset =
        int3(
            (int) (childIndex & 1u),
            (int) ((childIndex >> 1u) & 1u),
            (int) ((childIndex >> 2u) & 1u)
        );


    return
        parentOrigin +
        childOffset *
        childLatticeSpan;
}


// ============================================================
// NODE CHILD WORLD ORIGIN
// ============================================================

float3 GetChildWorldOrigin(
    VoxelOctreeNode parentNode,
    uint childIndex)
{
    return
        CanonicalLatticeToWorld(
            GetChildCanonicalOrigin(
                parentNode,
                childIndex
            )
        );
}


// ============================================================
// NODE CHILD WORLD SIZE
// ============================================================

float GetChildWorldSize(
    VoxelOctreeNode parentNode)
{
    return
        GetNodeWorldSize(
            parentNode
        )
        *
        0.5f;
}


// ============================================================
// NODE SAMPLE → CANONICAL COORDINATE
// ============================================================
//
// localSampleCoordinate:
//
//     0 .. DEFAULT_CHUNK_RESOLUTION
//
// includes the boundary sample.
// ============================================================

int3 GetNodeCanonicalSampleCoordinate(
    VoxelOctreeNode node,
    int3 localSampleCoordinate)
{
    int stride =
        GetNodeLatticeStride(
            node
        );


    return
        node.canonicalOrigin +
        localSampleCoordinate *
        stride;
}


// ============================================================
// NODE SAMPLE → WORLD POSITION
// ============================================================

float3 GetNodeSampleWorldPosition(
    VoxelOctreeNode node,
    int3 localSampleCoordinate)
{
    return
        CanonicalLatticeToWorld(
            GetNodeCanonicalSampleCoordinate(
                node,
                localSampleCoordinate
            )
        );
}


// ============================================================
// NODE CELL MIN
// ============================================================

float3 GetNodeCellMin(
    VoxelOctreeNode node,
    int3 cellCoordinate)
{
    return
        GetNodeWorldOrigin(
            node
        )
        +
        GetLocalCellMin(
            cellCoordinate,
            GetNodeCellSize(
                node
            )
        );
}


// ============================================================
// NODE CELL CENTER
// ============================================================

float3 GetNodeCellCenter(
    VoxelOctreeNode node,
    int3 cellCoordinate)
{
    return
        GetNodeWorldOrigin(
            node
        )
        +
        GetLocalCellCenter(
            cellCoordinate,
            GetNodeCellSize(
                node
            )
        );
}


// ============================================================
// NODE CELL MAX
// ============================================================

float3 GetNodeCellMax(
    VoxelOctreeNode node,
    int3 cellCoordinate)
{
    return
        GetNodeWorldOrigin(
            node
        )
        +
        GetLocalCellMax(
            cellCoordinate,
            GetNodeCellSize(
                node
            )
        );
}

// ============================================================
// SIGN CHANGE
// ============================================================
//
// Returns true when two density samples lie on opposite sides
// of the implicit surface.
//
// Zero is treated as surface/inside consistently with the
// existing topology code.
// ============================================================

bool IsSignChange(
    float densityA,
    float densityB)
{
    bool insideA =
        densityA < 0.0f;

    bool insideB =
        densityB < 0.0f;

    return
        insideA != insideB;
}


#endif