using System.Collections.Generic;
using UnityEngine;

[DisallowMultipleComponent]
public sealed class VoxelGpuHierarchy : MonoBehaviour
{
    [Header("New LOD")]
    [SerializeField, Range(0, 16)] private int minLod = 0;
    [SerializeField, Range(0, 18)] private int maxLod = 13;
    [SerializeField, Min(1)] private int maxPatchCount = 2048;
    [SerializeField, Min(0.1f)] private float splitDistanceMultiplier = 1.65f;
    [SerializeField, Min(0.1f)] private float mergeDistanceMultiplier = 2.35f;
    [SerializeField, Min(0.01f)] private float lodUpdateMovementThreshold = 0.25f;
    [SerializeField] private bool horizonCulling = true;

    [Header("Renderer")]
    [SerializeField] private VoxelPlanetGpuRenderer renderer;

    private readonly List<Node> roots = new List<Node>(6);
    private Vector3 planetCenter;
    private float planetRadius;
    private float planetNoiseHeight;
    private Vector3 targetPosition;
    private Vector3 lastProcessedTarget;
    private bool initialized;
    private int leafCount;

    private sealed class Node
    {
        public readonly VoxelPatchKey Key;
        public VoxelPlanetGpuRenderer.PatchView View;
        public Node[] Children;

        public Node(VoxelPatchKey key)
        {
            Key = key;
        }

        public bool IsSplit => Children != null;
    }

    public bool IsInitialized => initialized;
    public Vector3 PlanetCenter => planetCenter;
    public float PlanetRadius => planetRadius;
    public float PlanetNoiseHeight => planetNoiseHeight;
    public int ActiveLeafCount => leafCount;
    public VoxelPlanetGpuRenderer Renderer => renderer;

    private void Awake()
    {
        if (renderer == null)
            renderer = GetComponent<VoxelPlanetGpuRenderer>();
    }

    public bool Initialize(
        VoxelPlanetDefinition definition,
        Vector3 initialTarget)
    {
        if (initialized)
            return true;

        if (definition == null)
            return false;

        if (renderer == null)
            renderer = GetComponent<VoxelPlanetGpuRenderer>();

        if (renderer == null)
        {
            Debug.LogError(
                $"[{nameof(VoxelGpuHierarchy)}] " +
                "VoxelPlanetGpuRenderer is missing.",
                this);
            return false;
        }

        planetCenter = definition.PlanetCenter;
        planetRadius = definition.PlanetRadius;
        planetNoiseHeight = definition.NoiseHeight;
        targetPosition = initialTarget;

        renderer.Initialize(definition, transform);

        roots.Clear();
        leafCount = 0;

        CreateRoots();
        initialized = true;
        RebuildLodTree(true);
        lastProcessedTarget = targetPosition;

        Debug.Log(
            $"[{nameof(VoxelGpuHierarchy)}] " +
            $"Initialized Radius={planetRadius:F0}, " +
            $"Diameter={definition.PlanetDiameter:F0}, " +
            $"LOD=[{definition.MinLod}..{definition.MaxLod}], " +
            $"PatchResolution={definition.PatchResolution}.",
            this);

        return true;
    }

    public void SetLodTargetPosition(Vector3 position)
    {
        targetPosition = position;
    }

    public void Tick()
    {
        if (!initialized)
            return;

        if ((targetPosition - lastProcessedTarget).sqrMagnitude <
            lodUpdateMovementThreshold * lodUpdateMovementThreshold)
        {
            return;
        }

        RebuildLodTree(false);
        lastProcessedTarget = targetPosition;
    }

    public void Shutdown()
    {
        if (renderer != null)
            renderer.Clear();

        roots.Clear();
        leafCount = 0;
        initialized = false;
    }

    public void UpdateCollision(
        Vector3 target,
        float collisionRadius,
        int maxColliders,
        bool convex,
        PhysicMaterial physicMaterial)
    {
        if (!initialized || renderer == null)
            return;

        renderer.UpdateCollision(
            target,
            collisionRadius,
            maxColliders,
            convex,
            physicMaterial);
    }

    public bool RaycastSurface(
        Ray ray,
        float maxDistance,
        out RaycastHit hit)
    {
        if (renderer != null)
            return renderer.RaycastSurface(ray, maxDistance, out hit);

        hit = default(RaycastHit);
        return false;
    }

    private void CreateRoots()
    {
        VoxelCubeFace[] faces =
        {
            VoxelCubeFace.PositiveX,
            VoxelCubeFace.NegativeX,
            VoxelCubeFace.PositiveY,
            VoxelCubeFace.NegativeY,
            VoxelCubeFace.PositiveZ,
            VoxelCubeFace.NegativeZ
        };

        for (int i = 0; i < faces.Length; i++)
        {
            Node root = CreateNode(
                new VoxelPatchKey(faces[i], 0, 0, 0));

            roots.Add(root);
            leafCount++;
        }
    }

    private Node CreateNode(VoxelPatchKey key)
    {
        Node node = new Node(key);
        node.View = renderer.CreatePatch(key);
        node.View.SetVisible(false);
        return node;
    }

    private void Split(Node node)
    {
        if (node.IsSplit ||
            node.Key.Lod >= Mathf.Clamp(maxLod, 0, 18) ||
            leafCount + 3 > Mathf.Max(6, maxPatchCount))
        {
            return;
        }

        int lod = node.Key.Lod + 1;
        int baseX = node.Key.X * 2;
        int baseY = node.Key.Y * 2;

        node.Children = new Node[4];

        node.Children[0] = CreateNode(
            new VoxelPatchKey(
                node.Key.Face,
                lod,
                baseX,
                baseY));

        node.Children[1] = CreateNode(
            new VoxelPatchKey(
                node.Key.Face,
                lod,
                baseX + 1,
                baseY));

        node.Children[2] = CreateNode(
            new VoxelPatchKey(
                node.Key.Face,
                lod,
                baseX,
                baseY + 1));

        node.Children[3] = CreateNode(
            new VoxelPatchKey(
                node.Key.Face,
                lod,
                baseX + 1,
                baseY + 1));

        leafCount += 3;
    }

    private void Merge(Node node)
    {
        if (!node.IsSplit)
            return;

        int removedLeaves = 0;

        for (int i = 0; i < node.Children.Length; i++)
        {
            removedLeaves += CountLeaves(node.Children[i]);
            DestroySubtree(node.Children[i]);
        }

        node.Children = null;

        // All descendant leaves are replaced by this single parent leaf.
        leafCount -= Mathf.Max(0, removedLeaves - 1);
    }

    private int CountLeaves(Node node)
    {
        if (!node.IsSplit)
            return 1;

        int count = 0;

        for (int i = 0; i < node.Children.Length; i++)
            count += CountLeaves(node.Children[i]);

        return count;
    }

    private void DestroySubtree(Node node)
    {
        if (node.IsSplit)
        {
            for (int i = 0; i < node.Children.Length; i++)
                DestroySubtree(node.Children[i]);
        }

        renderer.RemovePatch(node.Key);
    }

    private void RebuildLodTree(bool force)
    {
        if (!force &&
            (targetPosition - lastProcessedTarget).sqrMagnitude <
            lodUpdateMovementThreshold * lodUpdateMovementThreshold)
        {
            return;
        }

        for (int i = 0; i < roots.Count; i++)
            RefreshNode(roots[i]);
    }

    private void RefreshNode(Node node)
    {
        bool visible =
            !horizonCulling ||
            renderer.IsPatchVisible(
                node.Key,
                targetPosition);

        if (!visible)
        {
            if (node.IsSplit)
                Merge(node);

            node.View.SetVisible(false);
            node.View.SetCollider(
                false,
                false,
                null);
            return;
        }

        float distance =
            renderer.DistanceToPatch(
                targetPosition,
                node.Key);

        float patchSize =
            renderer.GetPatchWorldSize(node.Key);

        int clampedMax =
            Mathf.Clamp(maxLod, minLod, 18);

        bool mustSplit =
            node.Key.Lod < minLod ||
            (node.Key.Lod < clampedMax &&
             distance < patchSize * splitDistanceMultiplier);

        bool shouldKeepSplit =
            node.Key.Lod < clampedMax &&
            (node.Key.Lod < minLod ||
             distance < patchSize * mergeDistanceMultiplier);

        if (node.IsSplit)
        {
            if (!shouldKeepSplit)
            {
                Merge(node);
                node.View.SetVisible(true);
                return;
            }

            node.View.SetVisible(false);

            for (int i = 0; i < node.Children.Length; i++)
                RefreshNode(node.Children[i]);

            return;
        }

        if (mustSplit)
        {
            int before = leafCount;
            Split(node);

            if (leafCount != before)
            {
                node.View.SetVisible(false);

                for (int i = 0; i < node.Children.Length; i++)
                    RefreshNode(node.Children[i]);

                return;
            }
        }

        node.View.SetVisible(true);
    }

#if UNITY_EDITOR
    private void OnValidate()
    {
        minLod = Mathf.Clamp(minLod, 0, 16);
        maxLod = Mathf.Clamp(Mathf.Max(minLod, maxLod), minLod, 18);
        maxPatchCount = Mathf.Max(6, maxPatchCount);
        splitDistanceMultiplier = Mathf.Max(0.1f, splitDistanceMultiplier);
        mergeDistanceMultiplier =
            Mathf.Max(
                splitDistanceMultiplier + 0.05f,
                mergeDistanceMultiplier);
        lodUpdateMovementThreshold =
            Mathf.Max(0.01f, lodUpdateMovementThreshold);
    }
#endif
}
