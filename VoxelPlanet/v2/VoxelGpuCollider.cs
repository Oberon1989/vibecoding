using UnityEngine;

[DisallowMultipleComponent]
public sealed class VoxelGpuCollider : MonoBehaviour
{
    [Header("References")]
    [SerializeField] private VoxelGpuHierarchy hierarchy;
    [SerializeField] private Transform target;

    [Header("Collision")]
    [SerializeField, Min(0f)] private float collisionRadius = 1200f;
    [SerializeField, Min(1)] private int collisionLeafCount = 32;
    [SerializeField] private bool convex = false;
    [SerializeField] private PhysicMaterial physicMaterial;

    private void Awake()
    {
        ResolveReferences();
    }

    private void OnEnable()
    {
        ResolveReferences();
    }

    private void LateUpdate()
    {
        if (hierarchy == null || !hierarchy.IsInitialized)
        {
            ResolveReferences();
            return;
        }

        if (target == null && Camera.main != null)
            target = Camera.main.transform;

        if (target == null)
            return;

        hierarchy.UpdateCollision(
            target.position,
            collisionRadius,
            collisionLeafCount,
            convex,
            physicMaterial);
    }

    public bool RaycastSurface(
        Ray ray,
        float maxDistance,
        out RaycastHit hit)
    {
        if (hierarchy != null)
            return hierarchy.RaycastSurface(
                ray,
                maxDistance,
                out hit);

        hit = default(RaycastHit);
        return false;
    }

    private void ResolveReferences()
    {
        if (hierarchy == null)
            hierarchy = GetComponent<VoxelGpuHierarchy>();

        if (hierarchy == null)
        {
            VoxelPlanet planet =
                GetComponent<VoxelPlanet>();

            if (planet != null)
                hierarchy = planet.GpuHierarchy;
        }

        if (target == null && Camera.main != null)
            target = Camera.main.transform;
    }

#if UNITY_EDITOR
    private void OnValidate()
    {
        collisionRadius = Mathf.Max(0f, collisionRadius);
        collisionLeafCount = Mathf.Max(1, collisionLeafCount);

        if (hierarchy == null)
            hierarchy = GetComponent<VoxelGpuHierarchy>();
    }
#endif
}
