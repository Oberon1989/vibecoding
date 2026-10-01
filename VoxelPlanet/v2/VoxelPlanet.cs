using UnityEngine;

[DisallowMultipleComponent]
[RequireComponent(typeof(VoxelGpuHierarchy))]
public class VoxelPlanet : MonoBehaviour
{
    [Header("Planet Definition")]
    [SerializeField] private VoxelPlanetDefinition definition;

    [Header("LOD Target")]
    [SerializeField] private Transform lodTarget;

    [Header("GPU Hierarchy")]
    [SerializeField] private VoxelGpuHierarchy gpuHierarchy;

    public VoxelPlanetDefinition Definition =>
        definition;

    public Transform LodTarget =>
        lodTarget;

    public VoxelGpuHierarchy GpuHierarchy =>
        gpuHierarchy;

    public Vector3 PlanetCenter =>
        definition != null
            ? definition.PlanetCenter
            : transform.position;

    public float PlanetRadius =>
        definition != null
            ? definition.PlanetRadius
            : 0.0f;

    private bool running;

    private void Reset()
    {
        gpuHierarchy =
            GetComponent<VoxelGpuHierarchy>();
    }

    private void Awake()
    {
        if (gpuHierarchy == null)
        {
            gpuHierarchy =
                GetComponent<VoxelGpuHierarchy>();
        }

        ValidateReferences();
    }

    private void OnEnable()
    {
        if (!Application.isPlaying)
            return;

        if (definition == null ||
            gpuHierarchy == null)
        {
            return;
        }

        Vector3 initialTargetPosition =
            ResolveLodTargetPosition();

        running =
            gpuHierarchy.Initialize(
                definition.PlanetCenter,
                definition.PlanetRadius,
                definition.NoiseSeed,
                definition.NoiseFrequency,
                definition.NoiseHeight,
                initialTargetPosition
            );
    }

    private void OnDisable()
    {
        running = false;

        if (gpuHierarchy != null)
        {
            gpuHierarchy.Shutdown();
        }
    }

    private void Update()
    {
        if (!running ||
            gpuHierarchy == null ||
            !gpuHierarchy.IsInitialized)
        {
            return;
        }

        gpuHierarchy.SetLodTargetPosition(
            ResolveLodTargetPosition()
        );

        gpuHierarchy.Tick();
    }

    private Vector3 ResolveLodTargetPosition()
    {
        if (lodTarget != null)
        {
            return lodTarget.position;
        }

        if (Camera.main != null)
        {
            return Camera.main.transform.position;
        }

        return PlanetCenter;
    }

    private void ValidateReferences()
    {
        if (definition == null)
        {
            Debug.LogError(
                $"[{nameof(VoxelPlanet)}] " +
                "VoxelPlanetDefinition is not assigned.",
                this
            );
        }

        if (gpuHierarchy == null)
        {
            Debug.LogError(
                $"[{nameof(VoxelPlanet)}] " +
                "VoxelGpuHierarchy is not assigned " +
                "and was not found on this GameObject.",
                this
            );
        }
    }

#if UNITY_EDITOR
    private void OnValidate()
    {
        if (gpuHierarchy == null)
        {
            gpuHierarchy =
                GetComponent<VoxelGpuHierarchy>();
        }
    }
#endif
}

