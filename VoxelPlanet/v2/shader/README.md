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

Two rules keep that loop closed:

1. The four incident dual vertices are emitted in the fixed topological cycle
   around the primal edge and are **not** re-sorted. The stencil order is
   already a proper cycle, while ordering the same four vertices by their
   solved angles can swap two neighbours when a QEF vertex moves inside its
   cell. That turned the quad into a bow tie whose triangle fan covers the
   wrong half, leaving a lens shaped opening plus unpaired edges.
2. A coarser transition cell only owns a dual vertex when the surface crosses
   its own cell corners. The octree marks a leaf as `OCTREE_FLAG_SURFACE` from
   an AABB test against the planet shell `[radius - (|noiseHeight| + 1),
   radius + (|noiseHeight| + 1)]`, so an active leaf can be empty and the cell
   that contains a fine edge of an LOD transition can have no vertex. Rather
   than dropping that polygon, the missing incident vertex is replaced by a
   deterministic stand-in: the nearest cell of the same leaf that does own a
   vertex, searched over the fixed Chebyshev shells 1..2. The search is a pure
   function of the cell and the read only vertex hash, so every polygon that
   refers to that cell resolves the identical vertex position and the surface
   stays watertight across the transition.

The resolver also rejects a `nodeIndex -> slot` mapping whose active leaf entry
does not point back at that node, because `CSResetActiveLeaves()` only clears
the active leaf count and a node that stopped being an active leaf would
otherwise resolve a vertex from an unrelated leaf.

These rules were verified offline with a CPU replica of the same octree, vertex
stage and edge polygon rules on a mixed LOD test field: unpaired (crack) edges
went from 17 to 0, bow ties from 1 to 0 and double edges from 12 to 0, and the
same run with rougher terrain reproduces the pattern (6 to 0 cracks).

Diagnostics: `MESH_DIAGNOSTIC_TRANSITION_STANDIN_VERTEX` (bit 8) is set when a
stand-in vertex was used; that is expected along LOD transitions and the mesh
is still closed. `MESH_DIAGNOSTIC_TRANSITION_MISSING_VERTICES` (bit 4) now
means the stand-in search failed too, and `MESH_DIAGNOSTIC_DROPPED_EDGE_POLYGON`
(bit 7) means such an owned sign-changing edge had fewer than three distinct
vertices and was omitted. Those two are the remaining hole cases. The other
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
