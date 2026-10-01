using UnityEngine;

[DisallowMultipleComponent]
[RequireComponent(typeof(VoxelGpuHierarchy))]
[RequireComponent(typeof(VoxelPlanetGpuRenderer))]
public sealed class VoxelPlanet : MonoBehaviour
{
    [Header("Planet Definition")]
    [SerializeField] private VoxelPlanetDefinition definition;

    [Header("LOD Target")]
    [SerializeField] private Transform lodTarget;

    [Header("Runtime")]
    [SerializeField] private VoxelGpuHierarchy gpuHierarchy;

    private bool running;

    public VoxelPlanetDefinition Definition => definition;

    public Transform LodTarget => lodTarget;

    public VoxelGpuHierarchy GpuHierarchy => gpuHierarchy;

    public Vector3 PlanetCenter =>
        definition != null
            ? definition.PlanetCenter
            : transform.position;

    public float PlanetRadius =>
        definition != null
            ? definition.PlanetRadius
            : 0f;

    private void Reset()
    {
        gpuHierarchy = GetComponent<VoxelGpuHierarchy>();

        if (lodTarget == null && Camera.main != null)
            lodTarget = Camera.main.transform;
    }

    private void Awake()
    {
        if (gpuHierarchy == null)
            gpuHierarchy = GetComponent<VoxelGpuHierarchy>();

        if (lodTarget == null && Camera.main != null)
            lodTarget = Camera.main.transform;

        ValidateReferences();
    }

    private void OnEnable()
    {
        if (!Application.isPlaying)
            return;

        if (definition == null || gpuHierarchy == null)
            return;

        running = gpuHierarchy.Initialize(
            definition,
            ResolveLodTargetPosition());
    }

    private void OnDisable()
    {
        running = false;

        if (gpuHierarchy != null)
            gpuHierarchy.Shutdown();
    }

    private void Update()
    {
        if (!running || gpuHierarchy == null)
            return;

        gpuHierarchy.SetLodTargetPosition(
            ResolveLodTargetPosition());

        gpuHierarchy.Tick();
    }

    private Vector3 ResolveLodTargetPosition()
    {
        if (lodTarget != null)
            return lodTarget.position;

        if (Camera.main != null)
            return Camera.main.transform.position;

        return PlanetCenter;
    }

    private void ValidateReferences()
    {
        if (definition == null)
        {
            Debug.LogError(
                $"[{nameof(VoxelPlanet)}] " +
                "VoxelPlanetDefinition is not assigned.",
                this);
        }

        if (gpuHierarchy == null)
        {
            Debug.LogError(
                $"[{nameof(VoxelPlanet)}] " +
                "VoxelGpuHierarchy is missing.",
                this);
        }
    }

#if UNITY_EDITOR
    private void OnValidate()
    {
        if (gpuHierarchy == null)
            gpuHierarchy = GetComponent<VoxelGpuHierarchy>();
    }
#endif
}
