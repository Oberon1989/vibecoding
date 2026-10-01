using System;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;

[DisallowMultipleComponent]
public class VoxelGpuCollider : MonoBehaviour
{
    [Header("References")]
    [SerializeField] private VoxelGpuHierarchy hierarchy;
    [SerializeField] private Transform target;

    [Header("Collision Streaming")]
    [Tooltip("Only chunks whose bounds are within this distance from Target are eligible for collision. Set to 1000 for a 1 km collision search radius.")]
    [SerializeField] private float collisionRadius = 1000.0f;
    [Tooltip("Maximum number of nearest eligible chunks combined into the collision mesh. Increase only if the local collision patch is too small; larger values cost more CPU time and mesh-cooking memory.")]
    [SerializeField] private int collisionLeafCount = 9;
    [Tooltip("Rebuild the collision patch after the target moves this far.")]
    [SerializeField] private float collisionCellSize = 16.0f;

    [Header("LOD Change Detection")]
    [SerializeField] private int lodCheckIntervalFrames = 15;

    [Header("Vertex Readback")]
    [SerializeField] private int vertexBatchGap = 32;

    [Header("Collider")]
    [SerializeField] private bool convex = false;
    [SerializeField] private PhysicsMaterial physicMaterial;

    private const int ACTIVE_LEAF_UINTS = 6;
    private const int MESH_INFO_UINTS = 7;

    private const int DEFAULT_CHUNK_RESOLUTION = 32;
    private const float BASE_LATTICE_SIZE = 0.5f;

    private MeshCollider meshCollider;
    private GameObject colliderObject;
    private Mesh collisionMesh;

    private bool rebuildRequested;
    private bool rebuildInProgress;
    private bool lodCheckPending;
    private int lodCheckGeneration;
    private bool warnedCollisionLeafLimit;
    private bool hasReportedCollisionRangeState;
    private bool lastTargetWasInCollisionRange;
    private int lastObservedMeshRevision = -1;

    private int currentLeafProcessIndex;

    private uint lastActiveLeafCount;
    private uint lastMeshIndexCount;

    private Vector3 lastBuildTargetPosition;
    private Vector3 rebuildTargetPosition;
    private Vector3Int lastBuildCell;

    private readonly List<CollisionLeaf> selectedLeaves =
        new List<CollisionLeaf>();

    private readonly List<uint> combinedGlobalIndices =
        new List<uint>();

    private readonly HashSet<uint> uniqueGlobalVertexIndices =
        new HashSet<uint>();

    private readonly List<uint> sortedGlobalVertexIndices =
        new List<uint>();

    private readonly Dictionary<uint, int> globalToLocalVertex =
        new Dictionary<uint, int>();

    private struct CollisionLeaf
    {
        public int slot;
        public float distanceSq;

        public uint vertexBase;
        public uint vertexCount;

        public uint indexBase;
        public uint indexCount;
    }

    private void Awake()
    {
        if (hierarchy == null)
        {
            hierarchy = GetComponent<VoxelGpuHierarchy>();
        }

        VoxelPlanet planet =
            GetComponent<VoxelPlanet>();

        if (target == null &&
            planet != null &&
            planet.LodTarget != null)
        {
            target = planet.LodTarget;
        }

        if (target == null && Camera.main != null)
        {
            target = Camera.main.transform;
        }

        CreateColliderObject();

        rebuildRequested = true;
    }

    private void LateUpdate()
    {
        if (hierarchy == null)
        {
            return;
        }

        if (target == null)
        {
            return;
        }

        if (!hierarchy.IsInitialized)
        {
            return;
        }

        if (rebuildInProgress)
        {
            ProcessRebuildStep();
            return;
        }

        if (lastObservedMeshRevision != hierarchy.MeshRevision)
        {
            lastObservedMeshRevision = hierarchy.MeshRevision;
            rebuildRequested = true;
        }

        if (rebuildRequested)
        {
            BeginRebuild();
            return;
        }

        CheckTargetCell();
        CheckLodState();
    }

    private void CreateColliderObject()
    {
        if (colliderObject != null)
        {
            return;
        }

        colliderObject =
            new GameObject(
                $"{gameObject.name}_Collision"
            );

        colliderObject.hideFlags =
            HideFlags.DontSave;

        colliderObject.layer =
            gameObject.layer;

        colliderObject.transform.SetPositionAndRotation(
            target != null ? target.position : Vector3.zero,
            Quaternion.identity
        );

        colliderObject.transform.localScale =
            Vector3.one;

        meshCollider =
            colliderObject.AddComponent<MeshCollider>();

        meshCollider.convex =
            convex;

        meshCollider.sharedMaterial =
            physicMaterial;
    }

    private void CheckTargetCell()
    {
        Vector3 position =
            target.position;

        Vector3Int currentCell =
            CalculateTargetCell(
                position
            );

        if (currentCell != lastBuildCell)
        {
            rebuildRequested = true;
        }
    }

    private void CheckLodState()
    {
        if (!IsTargetWithinCollisionRadius())
            return;

        if (lodCheckIntervalFrames <= 0)
        {
            return;
        }

        if (Time.frameCount %
            lodCheckIntervalFrames != 0)
        {
            return;
        }

        GraphicsBuffer activeLeafCountBuffer =
            hierarchy.ActiveLeafCountBuffer;

        GraphicsBuffer indexCountBuffer =
            hierarchy.IndexCountBuffer;

        if (activeLeafCountBuffer == null ||
            indexCountBuffer == null)
        {
            return;
        }

        if (lodCheckPending)
            return;

        lodCheckPending = true;
        int generation = ++lodCheckGeneration;

        AsyncGPUReadback.Request(activeLeafCountBuffer, activeRequest =>
        {
            if (generation != lodCheckGeneration)
                return;

            if (!isActiveAndEnabled || activeRequest.hasError)
            {
                lodCheckPending = false;
                return;
            }

            var activeData = activeRequest.GetData<uint>();
            if (activeData.Length == 0)
            {
                lodCheckPending = false;
                return;
            }

            uint activeLeafCount = activeData[0];

            if (hierarchy == null ||
                !hierarchy.IsInitialized)
            {
                lodCheckPending = false;
                return;
            }

            GraphicsBuffer currentIndexCountBuffer =
                hierarchy.IndexCountBuffer;

            if (currentIndexCountBuffer == null)
            {
                lodCheckPending = false;
                return;
            }

            AsyncGPUReadback.Request(currentIndexCountBuffer, indexRequest =>
            {
                if (generation != lodCheckGeneration)
                    return;

                lodCheckPending = false;
                if (!isActiveAndEnabled || indexRequest.hasError)
                    return;

                var indexData = indexRequest.GetData<uint>();
                if (indexData.Length == 0)
                    return;

                uint meshIndexCount = indexData[0];
                if (activeLeafCount != lastActiveLeafCount ||
                    meshIndexCount != lastMeshIndexCount)
                {
                    rebuildRequested = true;
                }
            });
        });
    }

    private void BeginRebuild()
    {
        rebuildRequested = false;

        if (!CanUseHierarchyBuffers())
        {
            return;
        }

        Vector3 targetPosition = target.position;
        rebuildTargetPosition = targetPosition;

        bool targetInRange =
            IsTargetWithinCollisionRadius(targetPosition);

        ReportCollisionRangeState(targetPosition, targetInRange);

        if (!targetInRange)
        {
            ClearCollider();
            lastActiveLeafCount = 0u;
            lastMeshIndexCount = 0u;
            SaveBuildPosition(targetPosition);
            return;
        }

        GraphicsBuffer activeLeafBuffer =
            hierarchy.ActiveLeafBuffer;

        GraphicsBuffer meshInfoBuffer =
            hierarchy.ActiveLeafMeshInfoBuffer;

        GraphicsBuffer activeLeafCountBuffer =
            hierarchy.ActiveLeafCountBuffer;

        if (activeLeafBuffer == null ||
            meshInfoBuffer == null ||
            activeLeafCountBuffer == null)
        {
            return;
        }

        uint activeLeafCount =
            ReadSingleUInt(
                activeLeafCountBuffer
            );

        if (activeLeafCount == 0u)
        {
            ClearCollider();

            lastActiveLeafCount = 0u;
            lastMeshIndexCount = 0u;

            SaveBuildPosition();

            return;
        }

        int leafCount =
            Math.Min(
                (int)activeLeafCount,
                activeLeafBuffer.count
            );

        uint[] activeLeafData =
            new uint[
                leafCount *
                ACTIVE_LEAF_UINTS
            ];

        uint[] meshInfoData =
            new uint[
                leafCount *
                MESH_INFO_UINTS
            ];

        activeLeafBuffer.GetData(
            activeLeafData,
            0,
            0,
            activeLeafData.Length
        );

        meshInfoBuffer.GetData(
            meshInfoData,
            0,
            0,
            meshInfoData.Length
        );

        selectedLeaves.Clear();

        float safeCollisionRadius =
            Mathf.Max(0.0f, collisionRadius);

        float collisionRadiusSq =
            safeCollisionRadius * safeCollisionRadius;

        for (int slot = 0;
             slot < leafCount;
             slot++)
        {
            int leafBase =
                slot *
                ACTIVE_LEAF_UINTS;

            int meshBase =
                slot *
                MESH_INFO_UINTS;

            uint nodeIndex =
                meshInfoData[
                    meshBase + 0
                ];

            uint vertexBase =
                meshInfoData[
                    meshBase + 1
                ];

            uint vertexCapacity =
                meshInfoData[
                    meshBase + 2
                ];

            uint vertexCount =
                meshInfoData[
                    meshBase + 3
                ];

            uint indexBase =
                meshInfoData[
                    meshBase + 4
                ];

            uint indexCapacity =
                meshInfoData[
                    meshBase + 5
                ];

            uint indexCount =
                meshInfoData[
                    meshBase + 6
                ];

            if (vertexCount == 0u ||
                indexCount < 3u)
            {
                continue;
            }

            if (vertexCount > vertexCapacity ||
                indexCount > indexCapacity)
            {
                continue;
            }

            uint activeNodeIndex =
                activeLeafData[
                    leafBase + 0
                ];

            if (nodeIndex != activeNodeIndex)
            {
                continue;
            }

            int lod =
                unchecked(
                    (int)activeLeafData[
                        leafBase + 1
                    ]
                );

            Vector3 canonicalOrigin =
                new Vector3(
                    unchecked(
                        (int)activeLeafData[
                            leafBase + 2
                        ]
                    ),
                    unchecked(
                        (int)activeLeafData[
                            leafBase + 3
                        ]
                    ),
                    unchecked(
                        (int)activeLeafData[
                            leafBase + 4
                        ]
                    )
                );

            float leafWorldSize =
                DEFAULT_CHUNK_RESOLUTION *
                BASE_LATTICE_SIZE *
                Mathf.Pow(
                    2.0f,
                    lod
                );

            Vector3 leafMin =
                canonicalOrigin *
                BASE_LATTICE_SIZE;

            Vector3 leafMax =
                leafMin +
                Vector3.one *
                leafWorldSize;

            Vector3 closestPoint =
                new Vector3(
                    Mathf.Clamp(
                        targetPosition.x,
                        leafMin.x,
                        leafMax.x
                    ),
                    Mathf.Clamp(
                        targetPosition.y,
                        leafMin.y,
                        leafMax.y
                    ),
                    Mathf.Clamp(
                        targetPosition.z,
                        leafMin.z,
                        leafMax.z
                    )
                );

            float distanceSq =
                (closestPoint -
                 targetPosition).sqrMagnitude;

            // Never fall back to a remote planet chunk when the target is
            // outside the collision streaming radius.
            if (distanceSq > collisionRadiusSq)
            {
                continue;
            }

            CollisionLeaf leaf =
                new CollisionLeaf
                {
                    slot = slot,
                    distanceSq = distanceSq,
                    vertexBase = vertexBase,
                    vertexCount = vertexCount,
                    indexBase = indexBase,
                    indexCount = indexCount
                };

            selectedLeaves.Add(
                leaf
            );
        }

        selectedLeaves.Sort(
            CompareCollisionLeaves
        );

        int maxCollisionLeaves =
            Mathf.Max(1, collisionLeafCount);

        if (selectedLeaves.Count > maxCollisionLeaves)
        {
            int skippedLeaves =
                selectedLeaves.Count - maxCollisionLeaves;

            selectedLeaves.RemoveRange(
                maxCollisionLeaves,
                skippedLeaves
            );

            if (!warnedCollisionLeafLimit)
            {
                warnedCollisionLeafLimit = true;
                Debug.LogWarning(
                    $"[{nameof(VoxelGpuCollider)}] Collision radius " +
                    $"contains more than {maxCollisionLeaves} eligible " +
                    $"chunks; keeping the nearest {maxCollisionLeaves}. " +
                    "Raise Max Collision Leaves if the local collider " +
                    "patch is too small.",
                    this
                );
            }
        }

        combinedGlobalIndices.Clear();
        uniqueGlobalVertexIndices.Clear();
        sortedGlobalVertexIndices.Clear();
        globalToLocalVertex.Clear();

        currentLeafProcessIndex = 0;

        rebuildInProgress =
            selectedLeaves.Count > 0;

        lastActiveLeafCount =
            activeLeafCount;

        lastMeshIndexCount =
            ReadSingleUInt(
                hierarchy.IndexCountBuffer
            );

        if (!rebuildInProgress)
        {
            ClearCollider();
            SaveBuildPosition();
        }
    }

    private void ProcessRebuildStep()
    {
        if (currentLeafProcessIndex >=
            selectedLeaves.Count)
        {
            FinishRebuild();

            rebuildInProgress = false;

            SaveBuildPosition(rebuildTargetPosition);

            return;
        }

        CollisionLeaf leaf =
            selectedLeaves[
                currentLeafProcessIndex
            ];

        ReadLeafIndices(
            leaf
        );

        currentLeafProcessIndex++;
    }

    private void ReadLeafIndices(
        CollisionLeaf leaf
    )
    {
        if (leaf.indexCount < 3u)
        {
            return;
        }

        if (leaf.indexBase >=
            (uint)hierarchy.IndexBuffer.count)
        {
            return;
        }

        uint available =
            (uint)hierarchy.IndexBuffer.count -
            leaf.indexBase;

        uint safeCount =
            Math.Min(
                leaf.indexCount,
                available
            );

        safeCount -=
            safeCount % 3u;

        if (safeCount < 3u)
        {
            return;
        }

        int safeCountInt =
            checked(
                (int)safeCount
            );

        int startIndex =
            checked(
                (int)leaf.indexBase
            );

        uint[] indices =
            new uint[
                safeCountInt
            ];

        hierarchy.IndexBuffer.GetData(
            indices,
            0,
            startIndex,
            safeCountInt
        );

        for (int i = 0;
             i < indices.Length;
             i++)
        {
            uint globalVertexIndex =
                indices[i];

            if (globalVertexIndex >=
                (uint)hierarchy.VertexBuffer.count)
            {
                continue;
            }

            combinedGlobalIndices.Add(
                globalVertexIndex
            );

            uniqueGlobalVertexIndices.Add(
                globalVertexIndex
            );
        }
    }

    private void FinishRebuild()
    {
        if (combinedGlobalIndices.Count < 3)
        {
            ClearCollider();
            return;
        }

        sortedGlobalVertexIndices.AddRange(
            uniqueGlobalVertexIndices
        );

        sortedGlobalVertexIndices.Sort();

        List<Vector3> vertices =
            ReadRequiredVertices();

        if (vertices == null ||
            vertices.Count == 0)
        {
            ClearCollider();
            return;
        }

        List<int> triangles =
            BuildLocalTriangles();

        if (triangles.Count < 3)
        {
            ClearCollider();
            return;
        }

        // The GPU mesh stores world-space planet vertices. Shift this small
        // collision patch around its build target so the MeshCollider uses
        // local coordinates close to zero, improving physics precision.
        for (int i = 0; i < vertices.Count; i++)
            vertices[i] -= rebuildTargetPosition;

        BuildCollisionMesh(
            vertices,
            triangles
        );
    }

    private List<Vector3> ReadRequiredVertices()
    {
        int vertexCount =
            sortedGlobalVertexIndices.Count;

        if (vertexCount == 0)
        {
            return null;
        }

        List<Vector3> vertices =
            new List<Vector3>(
                vertexCount
            );

        int rangeStart = 0;

        while (rangeStart <
               sortedGlobalVertexIndices.Count)
        {
            uint firstIndex =
                sortedGlobalVertexIndices[
                    rangeStart
                ];

            int rangeEnd =
                rangeStart;

            while (rangeEnd + 1 <
                   sortedGlobalVertexIndices.Count)
            {
                uint nextIndex =
                    sortedGlobalVertexIndices[
                        rangeEnd + 1
                    ];

                uint currentIndex =
                    sortedGlobalVertexIndices[
                        rangeEnd
                    ];

                uint gap =
                    nextIndex -
                    currentIndex -
                    1u;

                if (gap >
                    (uint)vertexBatchGap)
                {
                    break;
                }

                rangeEnd++;
            }

            uint lastIndex =
                sortedGlobalVertexIndices[
                    rangeEnd
                ];

            uint rangeLength =
                lastIndex -
                firstIndex +
                1u;

            if (firstIndex >=
                (uint)hierarchy.VertexBuffer.count)
            {
                rangeStart =
                    rangeEnd + 1;

                continue;
            }

            uint available =
                (uint)hierarchy.VertexBuffer.count -
                firstIndex;

            rangeLength =
                Math.Min(
                    rangeLength,
                    available
                );

            int rangeLengthInt =
                checked(
                    (int)rangeLength
                );

            int startIndex =
                checked(
                    (int)firstIndex
                );

            Vector3[] rangeData =
                new Vector3[
                    rangeLengthInt
                ];

            hierarchy.VertexBuffer.GetData(
                rangeData,
                0,
                startIndex,
                rangeLengthInt
            );

            for (int i = rangeStart;
                 i <= rangeEnd;
                 i++)
            {
                uint globalIndex =
                    sortedGlobalVertexIndices[i];

                if (globalIndex <
                    firstIndex)
                {
                    continue;
                }

                uint offset =
                    globalIndex -
                    firstIndex;

                if (offset >=
                    (uint)rangeData.Length)
                {
                    continue;
                }

                int localIndex =
                    vertices.Count;

                vertices.Add(
                    rangeData[
                        (int)offset
                    ]
                );

                globalToLocalVertex[
                    globalIndex
                ] =
                    localIndex;
            }

            rangeStart =
                rangeEnd + 1;
        }

        return vertices;
    }

    private List<int> BuildLocalTriangles()
    {
        List<int> triangles =
            new List<int>(
                combinedGlobalIndices.Count
            );

        int count =
            combinedGlobalIndices.Count -
            combinedGlobalIndices.Count % 3;

        for (int i = 0;
             i < count;
             i += 3)
        {
            uint a =
                combinedGlobalIndices[i + 0];

            uint b =
                combinedGlobalIndices[i + 1];

            uint c =
                combinedGlobalIndices[i + 2];

            if (!globalToLocalVertex.TryGetValue(
                    a,
                    out int ia))
            {
                continue;
            }

            if (!globalToLocalVertex.TryGetValue(
                    b,
                    out int ib))
            {
                continue;
            }

            if (!globalToLocalVertex.TryGetValue(
                    c,
                    out int ic))
            {
                continue;
            }

            if (ia == ib ||
                ib == ic ||
                ic == ia)
            {
                continue;
            }

            triangles.Add(ia);
            triangles.Add(ib);
            triangles.Add(ic);
        }

        return triangles;
    }

    private void BuildCollisionMesh(
        List<Vector3> vertices,
        List<int> triangles
    )
    {
        if (collisionMesh == null)
        {
            collisionMesh =
                new Mesh();

            collisionMesh.name =
                $"{gameObject.name}_CollisionMesh";

            collisionMesh.indexFormat =
                IndexFormat.UInt32;
        }

        meshCollider.sharedMesh = null;

        collisionMesh.Clear();

        collisionMesh.indexFormat =
            IndexFormat.UInt32;

        collisionMesh.SetVertices(
            vertices
        );

        collisionMesh.SetTriangles(
            triangles,
            0,
            false
        );

        collisionMesh.RecalculateBounds();

        colliderObject.transform.SetPositionAndRotation(
            rebuildTargetPosition,
            Quaternion.identity
        );

        meshCollider.sharedMesh =
            collisionMesh;
    }

    private void ClearCollider()
    {
        if (meshCollider != null)
        {
            meshCollider.sharedMesh =
                null;
        }

        if (collisionMesh != null)
        {
            collisionMesh.Clear();
        }

        if (colliderObject != null && target != null)
        {
            colliderObject.transform.SetPositionAndRotation(
                target.position,
                Quaternion.identity
            );
        }
    }

    private void SaveBuildPosition()
    {
        if (target == null)
        {
            return;
        }

        SaveBuildPosition(target.position);
    }

    private void SaveBuildPosition(Vector3 position)
    {
        lastBuildTargetPosition = position;

        lastBuildCell =
            CalculateTargetCell(
                position
            );
    }

    private bool IsTargetWithinCollisionRadius()
    {
        return target != null &&
               IsTargetWithinCollisionRadius(target.position);
    }

    private bool IsTargetWithinCollisionRadius(Vector3 position)
    {
        return GetDistanceToPlanetShell(position) <=
               Mathf.Max(0.0f, collisionRadius);
    }

    private float GetDistanceToPlanetShell(Vector3 position)
    {
        if (hierarchy == null || !hierarchy.IsInitialized)
            return float.PositiveInfinity;

        float shellRadius =
            Mathf.Max(0.0f, hierarchy.PlanetRadius) +
            Mathf.Abs(hierarchy.PlanetNoiseHeight);

        float distanceFromCenter =
            Vector3.Distance(position, hierarchy.PlanetCenter);

        return Mathf.Max(0.0f, distanceFromCenter - shellRadius);
    }

    private void ReportCollisionRangeState(
        Vector3 position,
        bool isInRange)
    {
        if (hasReportedCollisionRangeState &&
            lastTargetWasInCollisionRange == isInRange)
        {
            return;
        }

        hasReportedCollisionRangeState = true;
        lastTargetWasInCollisionRange = isInRange;
        string rangeState = isInRange ? "within" : "outside";

        Debug.Log(
            $"[{nameof(VoxelGpuCollider)}] Target is " +
            $"{rangeState} collision range. " +
            $"DistanceToSurface={GetDistanceToPlanetShell(position):F1}, " +
            $"CollisionRadius={Mathf.Max(0.0f, collisionRadius):F1}. " +
            (isInRange
                ? "Nearby chunk search is enabled."
                : "Collider mesh is cleared until the target gets closer."),
            this
        );
    }

    private Vector3Int CalculateTargetCell(
        Vector3 position
    )
    {
        return new Vector3Int(
            Mathf.FloorToInt(
                position.x /
                collisionCellSize
            ),
            Mathf.FloorToInt(
                position.y /
                collisionCellSize
            ),
            Mathf.FloorToInt(
                position.z /
                collisionCellSize
            )
        );
    }

    private static int CompareCollisionLeaves(
        CollisionLeaf a,
        CollisionLeaf b
    )
    {
        return a.distanceSq.CompareTo(
            b.distanceSq
        );
    }

    private static uint ReadSingleUInt(
        GraphicsBuffer buffer
    )
    {
        if (buffer == null)
        {
            return 0u;
        }

        uint[] value =
            new uint[1];

        buffer.GetData(
            value,
            0,
            0,
            1
        );

        return value[0];
    }

    private bool CanUseHierarchyBuffers()
    {
        if (hierarchy == null)
        {
            return false;
        }

        if (!hierarchy.IsInitialized)
        {
            return false;
        }

        if (hierarchy.ActiveLeafBuffer == null)
        {
            return false;
        }

        if (hierarchy.ActiveLeafMeshInfoBuffer == null)
        {
            return false;
        }

        if (hierarchy.ActiveLeafCountBuffer == null)
        {
            return false;
        }

        if (hierarchy.VertexBuffer == null)
        {
            return false;
        }

        if (hierarchy.IndexBuffer == null)
        {
            return false;
        }

        return true;
    }

    private void OnDisable()
    {
        rebuildRequested = false;
        rebuildInProgress = false;
        lodCheckPending = false;
        lodCheckGeneration++;

        if (meshCollider != null)
        {
            meshCollider.enabled = false;
        }
    }

    private void OnEnable()
    {
        if (meshCollider != null)
        {
            meshCollider.enabled = true;
        }

        rebuildRequested = true;
    }

    public bool RaycastSurface(
        Ray ray,
        float maxDistance,
        out RaycastHit hit
    )
    {
        if (meshCollider != null &&
            meshCollider.enabled &&
            meshCollider.sharedMesh != null)
        {
            return meshCollider.Raycast(
                ray,
                out hit,
                maxDistance
            );
        }

        hit = default;
        return false;
    }

    private void OnDestroy()
    {
        lodCheckGeneration++;
        lodCheckPending = false;

        if (collisionMesh != null)
        {
            Destroy(
                collisionMesh
            );

            collisionMesh = null;
        }

        if (colliderObject != null)
        {
            Destroy(
                colliderObject
            );

            colliderObject = null;
        }
    }
}
