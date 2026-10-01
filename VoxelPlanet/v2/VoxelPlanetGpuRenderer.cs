using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;

public enum VoxelCubeFace : byte
{
    PositiveX,
    NegativeX,
    PositiveY,
    NegativeY,
    PositiveZ,
    NegativeZ
}

public struct VoxelPatchKey
{
    public VoxelCubeFace Face;
    public int Lod;
    public int X;
    public int Y;

    public VoxelPatchKey(VoxelCubeFace face, int lod, int x, int y)
    {
        Face = face;
        Lod = lod;
        X = x;
        Y = y;
    }

    public override bool Equals(object obj)
    {
        if (!(obj is VoxelPatchKey)) return false;
        VoxelPatchKey other = (VoxelPatchKey)obj;
        return Face == other.Face && Lod == other.Lod &&
               X == other.X && Y == other.Y;
    }

    public override int GetHashCode()
    {
        unchecked
        {
            int hash = (int)Face;
            hash = hash * 397 ^ Lod;
            hash = hash * 397 ^ X;
            hash = hash * 397 ^ Y;
            return hash;
        }
    }
}

[DisallowMultipleComponent]
public sealed class VoxelPlanetGpuRenderer : MonoBehaviour
{
    [Header("Rendering")]
    [SerializeField] private Shader renderShader;
    [SerializeField] private Color baseColor = new Color(0.34f, 0.50f, 0.28f, 1f);
    [SerializeField] private int renderLayer;
    [SerializeField] private bool castShadows = true;

    private readonly Dictionary<VoxelPatchKey, PatchView> patches =
        new Dictionary<VoxelPatchKey, PatchView>();

    private readonly List<PatchView> collisionCandidates =
        new List<PatchView>(128);

    private Material material;
    private VoxelPlanetDefinition definition;
    private Vector3 planetCenter;
    private Transform patchRoot;

    public IReadOnlyCollection<PatchView> ActivePatches => patches.Values;

    public void Initialize(VoxelPlanetDefinition newDefinition, Transform owner)
    {
        definition = newDefinition;
        planetCenter = definition.PlanetCenter;

        EnsurePatchRoot(owner);
        EnsureMaterial();
        Clear();
    }

    public PatchView CreatePatch(VoxelPatchKey key)
    {
        if (patches.TryGetValue(key, out PatchView existing))
            return existing;

        PatchView view = new PatchView(key);
        view.GameObject.transform.SetParent(patchRoot, false);
        view.GameObject.layer = renderLayer;
        view.Renderer.sharedMaterial = material;
        view.Renderer.shadowCastingMode = castShadows
            ? ShadowCastingMode.On
            : ShadowCastingMode.Off;
        view.Renderer.receiveShadows = true;

        BuildPatchMesh(view);
        patches.Add(key, view);
        return view;
    }

    public void RemovePatch(VoxelPatchKey key)
    {
        PatchView view;
        if (!patches.TryGetValue(key, out view))
            return;

        patches.Remove(key);
        if (view.GameObject != null)
            Destroy(view.GameObject);
    }

    public void SetPatchVisible(VoxelPatchKey key, bool visible)
    {
        PatchView view;
        if (patches.TryGetValue(key, out view))
            view.SetVisible(visible);
    }

    public Vector3 GetPatchCenterDirection(VoxelPatchKey key)
    {
        float u0, u1, v0, v1;
        CubeFaceBounds(key, out u0, out u1, out v0, out v1);
        return CubeToSphere(key.Face, (u0 + u1) * 0.5f, (v0 + v1) * 0.5f);
    }

    public Vector3 GetPatchCenterWorld(VoxelPatchKey key)
    {
        Vector3 direction = GetPatchCenterDirection(key);
        float radius = Mathf.Max(1f, definition.PlanetRadius);
        return planetCenter +
               direction * (radius + definition.SampleHeight(direction));
    }

    public float GetPatchWorldSize(VoxelPatchKey key)
    {
        int divisions = 1 << Mathf.Clamp(key.Lod, 0, 18);
        return Mathf.Max(1f, definition.PlanetRadius * 2f / divisions);
    }

    public float DistanceToPatch(Vector3 targetPosition, VoxelPatchKey key)
    {
        Vector3 center = GetPatchCenterWorld(key);
        float halfSize = GetPatchWorldSize(key) * 0.55f;
        return Mathf.Max(
            0f,
            Vector3.Distance(targetPosition, center) - halfSize);
    }

    public bool IsPatchVisible(VoxelPatchKey key, Vector3 targetPosition)
    {
        Vector3 toTarget = targetPosition - planetCenter;
        float centerDistance = toTarget.magnitude;

        if (centerDistance <= definition.PlanetRadius * 1.02f)
            return true;

        if (centerDistance < 0.001f)
            return true;

        Vector3 cameraDirection = toTarget / centerDistance;
        Vector3 patchDirection = GetPatchCenterDirection(key);

        float patchSpan = 2f / Mathf.Max(1, 1 << key.Lod);
        float angularHalfSize = Mathf.Min(
            1.35f,
            Mathf.Sqrt(2f) * patchSpan);

        return Vector3.Dot(
            cameraDirection,
            patchDirection) > -Mathf.Sin(angularHalfSize * 1.1f);
    }

    public void UpdateCollision(
        Vector3 targetPosition,
        float collisionRadius,
        int maxColliders,
        bool convex,
        PhysicMaterial physicMaterial)
    {
        collisionCandidates.Clear();
        float radius = Mathf.Max(0f, collisionRadius);

        foreach (PatchView view in patches.Values)
        {
            if (!view.Visible || view.Mesh == null)
            {
                view.SetCollider(false, convex, physicMaterial);
                continue;
            }

            float distance = DistanceToPatch(targetPosition, view.Key);
            if (distance <= radius)
            {
                view.DistanceToTarget = distance;
                collisionCandidates.Add(view);
            }
            else
            {
                view.SetCollider(false, convex, physicMaterial);
            }
        }

        collisionCandidates.Sort(
            (a, b) => a.DistanceToTarget.CompareTo(b.DistanceToTarget));

        int limit = Mathf.Max(1, maxColliders);
        for (int i = 0; i < collisionCandidates.Count; i++)
        {
            collisionCandidates[i].SetCollider(
                i < limit,
                convex,
                physicMaterial);
        }
    }

    public bool RaycastSurface(
        Ray ray,
        float maxDistance,
        out RaycastHit hit)
    {
        bool found = false;
        float bestDistance = maxDistance;
        hit = default(RaycastHit);

        foreach (PatchView view in patches.Values)
        {
            if (!view.Visible || !view.Collider.enabled)
                continue;

            RaycastHit current;
            if (view.Collider.Raycast(ray, out current, maxDistance) &&
                current.distance < bestDistance)
            {
                bestDistance = current.distance;
                hit = current;
                found = true;
            }
        }

        return found;
    }

    public void Clear()
    {
        foreach (PatchView view in patches.Values)
        {
            if (view.GameObject != null)
                Destroy(view.GameObject);
        }

        patches.Clear();
    }

    private void EnsurePatchRoot(Transform owner)
    {
        if (patchRoot != null)
            return;

        GameObject root = new GameObject("PlanetPatches");
        root.transform.SetParent(owner, false);
        patchRoot = root.transform;
    }

    private void EnsureMaterial()
    {
        if (material != null)
            return;

        Shader shader = renderShader;
        if (shader == null)
            shader = Shader.Find("Universal Render Pipeline/Lit");
        if (shader == null)
            shader = Shader.Find("Standard");

        if (shader == null)
        {
            Debug.LogError(
                $"[{nameof(VoxelPlanetGpuRenderer)}] No compatible surface shader found.",
                this);
            return;
        }

        material = new Material(shader);
        material.name = "VoxelPlanetRuntimeMaterial";
        material.enableInstancing = true;

        if (material.HasProperty("_BaseColor"))
            material.SetColor("_BaseColor", baseColor);

        if (material.HasProperty("_Color"))
            material.SetColor("_Color", baseColor);

        if (material.HasProperty("_Cull"))
            material.SetFloat("_Cull", 0f);
    }

    private void BuildPatchMesh(PatchView view)
    {
        int resolution = Mathf.Clamp(
            definition.PatchResolution,
            4,
            64);

        int stride = resolution + 1;
        int gridVertexCount = stride * stride;

        List<Vector3> vertices =
            new List<Vector3>(gridVertexCount + resolution * 8);

        List<int> triangles =
            new List<int>(
                resolution * resolution * 6 +
                resolution * 4 * 6);

        float u0, u1, v0, v1;
        CubeFaceBounds(view.Key, out u0, out u1, out v0, out v1);

        Vector3 patchCenter = GetPatchCenterWorld(view.Key);
        view.GameObject.transform.position = patchCenter;
        view.GameObject.transform.rotation = Quaternion.identity;

        Vector3[] surfacePositions =
            new Vector3[gridVertexCount];

        for (int y = 0; y <= resolution; y++)
        {
            float v = Mathf.Lerp(
                v0,
                v1,
                (float)y / resolution);

            for (int x = 0; x <= resolution; x++)
            {
                float u = Mathf.Lerp(
                    u0,
                    u1,
                    (float)x / resolution);

                Vector3 direction =
                    CubeToSphere(view.Key.Face, u, v);

                float height =
                    definition.SampleHeight(direction);

                Vector3 world =
                    planetCenter +
                    direction *
                    (definition.PlanetRadius + height);

                Vector3 local = world - patchCenter;
                int index = y * stride + x;
                surfacePositions[index] = local;
                vertices.Add(local);
            }
        }

        bool flip = ShouldFlipWinding(view.Key.Face);

        for (int y = 0; y < resolution; y++)
        {
            for (int x = 0; x < resolution; x++)
            {
                int a = y * stride + x;
                int b = a + 1;
                int c = a + stride;
                int d = c + 1;

                if (!flip)
                {
                    triangles.Add(a);
                    triangles.Add(b);
                    triangles.Add(c);

                    triangles.Add(b);
                    triangles.Add(d);
                    triangles.Add(c);
                }
                else
                {
                    triangles.Add(a);
                    triangles.Add(c);
                    triangles.Add(b);

                    triangles.Add(b);
                    triangles.Add(c);
                    triangles.Add(d);
                }
            }
        }

        float skirtDepth =
            Mathf.Max(
                definition.SkirtDepth,
                GetPatchWorldSize(view.Key) * 0.02f);

        for (int edge = 0; edge < 4; edge++)
        {
            AddSkirt(
                surfacePositions,
                resolution,
                edge,
                skirtDepth,
                vertices,
                triangles);
        }

        view.Mesh.Clear();
        view.Mesh.indexFormat = IndexFormat.UInt32;
        view.Mesh.SetVertices(vertices);
        view.Mesh.SetTriangles(triangles, 0, true);
        view.Mesh.RecalculateNormals();
        view.Mesh.RecalculateBounds();
        view.Mesh.UploadMeshData(false);

        view.Collider.sharedMesh = null;
        view.Collider.sharedMesh = view.Mesh;
        view.SetVisible(true);
        view.SetCollider(false, false, null);
    }

    private static void AddSkirt(
        Vector3[] surfacePositions,
        int resolution,
        int edge,
        float depth,
        List<Vector3> vertices,
        List<int> triangles)
    {
        for (int i = 0; i < resolution; i++)
        {
            int a = GetEdgeIndex(edge, i, resolution);
            int b = GetEdgeIndex(edge, i + 1, resolution);

            Vector3 pa = surfacePositions[a];
            Vector3 pb = surfacePositions[b];

            Vector3 da = pa.normalized;
            Vector3 db = pb.normalized;

            int baseIndex = vertices.Count;

            vertices.Add(pa);
            vertices.Add(pb);
            vertices.Add(pa - da * depth);
            vertices.Add(pb - db * depth);

            triangles.Add(baseIndex + 0);
            triangles.Add(baseIndex + 1);
            triangles.Add(baseIndex + 3);

            triangles.Add(baseIndex + 0);
            triangles.Add(baseIndex + 3);
            triangles.Add(baseIndex + 2);
        }
    }

    private static int GetEdgeIndex(
        int edge,
        int i,
        int resolution)
    {
        int stride = resolution + 1;

        switch (edge)
        {
            case 0:
                return i;
            case 1:
                return resolution + i * stride;
            case 2:
                return resolution * stride + i;
            default:
                return i * stride;
        }
    }

    private static bool ShouldFlipWinding(VoxelCubeFace face)
    {
        Vector3 p0 = CubeToSphere(face, -0.02f, -0.02f);
        Vector3 p1 = CubeToSphere(face, 0.02f, -0.02f);
        Vector3 p2 = CubeToSphere(face, -0.02f, 0.02f);

        Vector3 normal = Vector3.Cross(p1 - p0, p2 - p0);
        Vector3 center = CubeToSphere(face, 0f, 0f);

        return Vector3.Dot(normal, center) < 0f;
    }

    public static Vector3 CubeToSphere(
        VoxelCubeFace face,
        float u,
        float v)
    {
        Vector3 cube;

        switch (face)
        {
            case VoxelCubeFace.PositiveX:
                cube = new Vector3(1f, v, -u);
                break;
            case VoxelCubeFace.NegativeX:
                cube = new Vector3(-1f, v, u);
                break;
            case VoxelCubeFace.PositiveY:
                cube = new Vector3(u, 1f, -v);
                break;
            case VoxelCubeFace.NegativeY:
                cube = new Vector3(u, -1f, v);
                break;
            case VoxelCubeFace.PositiveZ:
                cube = new Vector3(u, v, 1f);
                break;
            default:
                cube = new Vector3(-u, v, -1f);
                break;
        }

        return cube.normalized;
    }

    private static void CubeFaceBounds(
        VoxelPatchKey key,
        out float u0,
        out float u1,
        out float v0,
        out float v1)
    {
        int divisions = 1 << Mathf.Clamp(
            key.Lod,
            0,
            18);

        u0 = -1f + 2f * key.X / divisions;
        u1 = -1f + 2f * (key.X + 1) / divisions;
        v0 = -1f + 2f * key.Y / divisions;
        v1 = -1f + 2f * (key.Y + 1) / divisions;
    }

    public sealed class PatchView
    {
        public readonly VoxelPatchKey Key;
        public readonly GameObject GameObject;
        public readonly MeshFilter Filter;
        public readonly MeshRenderer Renderer;
        public readonly MeshCollider Collider;
        public readonly Mesh Mesh;

        public float DistanceToTarget;

        private bool colliderConfigured;
        private bool colliderConvex;
        private PhysicMaterial colliderMaterial;

        public bool Visible =>
            GameObject != null &&
            GameObject.activeSelf;

        public PatchView(VoxelPatchKey key)
        {
            Key = key;

            GameObject = new GameObject(
                $"Patch_{key.Face}_{key.Lod}_{key.X}_{key.Y}");

            Filter = GameObject.AddComponent<MeshFilter>();
            Renderer = GameObject.AddComponent<MeshRenderer>();
            Collider = GameObject.AddComponent<MeshCollider>();

            Mesh = new Mesh
            {
                name = GameObject.name + "_Mesh",
                indexFormat = IndexFormat.UInt32
            };

            Mesh.MarkDynamic();
            Filter.sharedMesh = Mesh;
            Collider.enabled = false;
        }

        public void SetVisible(bool visible)
        {
            if (GameObject != null)
                GameObject.SetActive(visible);
        }

        public void SetCollider(
            bool enabled,
            bool convex,
            PhysicMaterial physicMaterial)
        {
            if (Collider == null)
                return;

            if (!enabled)
            {
                Collider.enabled = false;
                return;
            }

            if (!colliderConfigured ||
                Collider.sharedMesh != Mesh ||
                colliderConvex != convex ||
                colliderMaterial != physicMaterial)
            {
                Collider.convex = convex;
                Collider.sharedMaterial = physicMaterial;
                Collider.sharedMesh = Mesh;
                colliderConfigured = true;
                colliderConvex = convex;
                colliderMaterial = physicMaterial;
            }

            Collider.enabled = true;
        }
    }
}
