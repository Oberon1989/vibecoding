# Voxel Planet vNext

This branch is a clean rewrite of the old experimental voxel pipeline.

## Runtime model
Six cube faces form six independent quadtrees. Each patch samples the same deterministic terrain function.

- integer quadtree coordinates
- deterministic continuous terrain sampling
- split/merge LOD hysteresis
- inward skirts to close coarse/fine boundaries without transition lookup tables
- patch-local mesh coordinates for large-world precision

## Terrain
Terrain height uses deterministic 3D value-noise FBM. World position is planet center plus normalized cube-face direction multiplied by radius plus height.

Because neighbouring patches evaluate the same direction function at shared boundary coordinates, same-LOD boundaries use identical surface samples.

## LOD
LOD is selected from target distance and patch world size. A hard active-patch limit prevents unbounded subdivision.

The system does not require a balanced octree for seam safety because the inward skirts close arbitrary neighbouring LOD differences.

## Physics
Only visible patches close to the target receive MeshColliders. The collider manager limits how many nearby patch colliders are active.

## Large worlds
Each patch transform is placed at its own surface centre and the mesh stores small local coordinates. This keeps the mesh coordinate range small for planets up to roughly 500 km diameter.

## Non-goals for this milestone
This rewrite does not reuse the previous VoxelDensity/QEF/transition-topology implementation and does not depend on the deleted ComputeShader pipeline.

The current milestone is stable planetary surface LOD with deterministic terrain and closed seams. True volumetric caves and overhangs can later be implemented as a separate mesh backend without changing the planet-coordinate and quadtree layers.