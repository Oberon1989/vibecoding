# Voxel planet GPU mesher V1

V1 is an experimental alternative mesh-connectivity path. It deliberately
reuses the current GPU octree, LOD selection/balancing, density function, and
QEF cell-vertex stage so that testing isolates how triangles are connected.
It does not move LOD or Dual Contouring work to the CPU.

## Mesh construction

`VoxelDensityMeshV1.hlsl` enumerates canonical primal edges and resolves their
four incident active leaves through the existing GPU octree. A deterministic
finest-leaf owner emits each sign-changing edge polygon. Repeated QEF vertices
from coarse cells are collapsed before the polygon is triangulated. The same
classification routine is used by the count and build passes. The old
per-face and boundary-face mesh writers are replaced for this shader path.

This is an experimental stitching algorithm, not a claim that all transition
cases have been proven. In particular, the mesh diagnostic bit
`MESH_DIAGNOSTIC_TRANSITION_MISSING_VERTICES` (bit 4) means one or more
incident cell vertices could not be resolved for a crossing edge. This is a
warning, not proof that a polygon was omitted: three remaining distinct
vertices can still form a triangle. `MESH_DIAGNOSTIC_DROPPED_EDGE_POLYGON`
(bit 7) is set only when an owned sign-changing edge has fewer than three
distinct incident vertices and is omitted from the generated mesh. The other
bits keep their existing meanings: vertex/index arena overflow, hash failure,
or an index write beyond its reservation.

## Unity test setup

1. Let Unity import `VoxelDensityV1.compute`.
2. Assign that compute shader to the existing `VoxelGpuHierarchy` component.
3. Add `VoxelPlanetV1Test` to the planet GameObject. It reads the planet
   definition and LOD target from the existing `VoxelPlanet`; the radius can
   optionally be overridden in the V1 component.
4. While enabled in Play mode, the V1 component temporarily disables the
   `VoxelPlanet` driver, initializes the hierarchy with the selected center,
   radius, noise settings, and target Transform, then ticks LOD itself. This
   avoids two components trying to own the same GPU hierarchy.
5. Run through the mixed `LOD=[0..1]` state and read the `[VoxelPlanetV1Test]`
   lines in the Unity Console. The startup line prints the radius and target
   Transform/position used by V1.

The component reports active leaves, min/max LOD, vertex/index totals, and mesh
flags using asynchronous GPU readbacks. It does not validate watertightness by
itself; the Scene view remains the visual check.
