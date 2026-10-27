# GPU Marching Cubes and Transvoxel

`VoxelDensityV1.compute` keeps the octree and 2:1 LOD balancing on the GPU.
It builds regular Marching Cubes cells and Transvoxel transition cells on the
GPU, writes the indirect-render buffers there, and calculates normals from the
density field. The CPU uploads fixed lookup tables and density-edit stamps;
mesh generation does not read density or build vertices on the CPU.

The regular and transition lookup tables come from Eric Lengyel's
[Transvoxel repository](https://github.com/EricLengyel/Transvoxel) and are
distributed under the MIT license in `Transvoxel-LICENSE.txt`. Their arrays
are uploaded once when the hierarchy allocates its GPU buffers.

The CPU copies the resulting mesh data only when building or updating the
physics collider. Rendering continues to consume the GPU vertex and index
buffers directly.
