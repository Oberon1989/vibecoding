using UnityEngine;
using UnityEngine.Rendering;
using System.Text;

/// <summary>
/// Drives the V1 compute-shader test and reads back mesh diagnostics.
/// Attach beside VoxelPlanet and VoxelGpuHierarchy. Assign the planet
/// definition and, when desired, the Transform used as the LOD target.
/// </summary>
[DefaultExecutionOrder(-1000)]
[DisallowMultipleComponent]
[RequireComponent(typeof(VoxelPlanet))]
public sealed class VoxelPlanetV1Test : MonoBehaviour
{
    [Header("V1 Planet Inputs")]
    [SerializeField] private VoxelPlanetDefinition planetDefinition;
    [SerializeField] private Transform lodTarget;
    [SerializeField] private bool overridePlanetRadius;
    [SerializeField, Min(0.0f)] private float planetRadius;

    [Header("Diagnostics")]
    [SerializeField, Min(1)] private int reportEveryFrames = 30;
    [SerializeField] private bool reportOnlyMixedLod = true;

    private VoxelGpuHierarchy hierarchy;
    private VoxelPlanet planet;
    private int frame;
    private int generation;
    private int completed;
    private bool pending;
    private bool ownsHierarchy;
    private bool disabledPlanetDriver;
    private bool hasReportedSnapshot;
    private readonly uint[] values = new uint[7];
    private readonly uint[] leafLods = new uint[65536];

    private void Reset()
    {
        hierarchy = GetComponent<VoxelGpuHierarchy>();
        planet = GetComponent<VoxelPlanet>();
        CopyPlanetInputsWhenMissing();
    }

    private void OnValidate()
    {
        if (!overridePlanetRadius && planetDefinition != null)
            planetRadius = planetDefinition.PlanetRadius;
    }

    private void Awake()
    {
        hierarchy = GetComponent<VoxelGpuHierarchy>();
        planet = GetComponent<VoxelPlanet>();
        CopyPlanetInputsWhenMissing();
    }

    private void OnEnable()
    {
        if (!Application.isPlaying)
            return;

        if (hierarchy == null)
            hierarchy = GetComponent<VoxelGpuHierarchy>();
        if (planet == null)
            planet = GetComponent<VoxelPlanet>();

        // VoxelPlanet normally owns this hierarchy. Disable that driver while
        // V1 is active so only this component initializes and ticks it.
        if (planet != null && planet.enabled)
        {
            planet.enabled = false;
            disabledPlanetDriver = true;
        }

        if (hierarchy == null || planetDefinition == null)
        {
            Debug.LogError(
                "[VoxelPlanetV1Test] Assign a VoxelGpuHierarchy and " +
                "VoxelPlanetDefinition before running V1.",
                this
            );
            RestorePlanetDriver();
            return;
        }

        float radius = overridePlanetRadius
            ? planetRadius
            : planetDefinition.PlanetRadius;
        Vector3 center = planetDefinition.PlanetCenter;
        Vector3 targetPosition = ResolveLodTargetPosition(center);

        if (hierarchy.IsInitialized)
            hierarchy.Shutdown();

        if (!hierarchy.Initialize(
                center,
                radius,
                planetDefinition.NoiseSeed,
                planetDefinition.NoiseFrequency,
                planetDefinition.NoiseHeight,
                targetPosition))
        {
            Debug.LogError(
                "[VoxelPlanetV1Test] GPU hierarchy initialization failed. " +
                "Check the V1 compute-shader assignment and planet inputs.",
                this
            );
            RestorePlanetDriver();
            return;
        }

        ownsHierarchy = true;
        hasReportedSnapshot = false;
        Debug.Log(
            $"[VoxelPlanetV1Test] Started " +
            $"PlanetCenter={center} PlanetRadius={radius} " +
            $"LodTarget={(lodTarget != null ? lodTarget.name : "Camera/Center")} " +
            $"LodTargetPos={targetPosition}",
            this
        );
    }

    private void OnDisable()
    {
        generation++;
        pending = false;

        if (ownsHierarchy && hierarchy != null)
        {
            hierarchy.Shutdown();
            ownsHierarchy = false;
        }

        RestorePlanetDriver();
    }

    private void Update()
    {
        if (!ownsHierarchy || hierarchy == null || !hierarchy.IsInitialized)
            return;

        hierarchy.SetLodTargetPosition(
            ResolveLodTargetPosition(planetDefinition.PlanetCenter)
        );
        hierarchy.Tick();

        if (pending || ++frame < Mathf.Max(1, reportEveryFrames))
            return;

        frame = 0;
        RequestSnapshot();
    }

    private Vector3 ResolveLodTargetPosition(Vector3 planetCenter)
    {
        if (lodTarget != null)
            return lodTarget.position;
        if (Camera.main != null)
            return Camera.main.transform.position;
        return planetCenter;
    }

    private void CopyPlanetInputsWhenMissing()
    {
        if (planet == null)
            planet = GetComponent<VoxelPlanet>();

        if (hierarchy == null)
            hierarchy = GetComponent<VoxelGpuHierarchy>();

        if (planetDefinition == null && planet != null)
            planetDefinition = planet.Definition;

        if (lodTarget == null && planet != null)
            lodTarget = planet.LodTarget;

        if (!overridePlanetRadius && planetDefinition != null)
            planetRadius = planetDefinition.PlanetRadius;
    }

    private void RestorePlanetDriver()
    {
        if (!disabledPlanetDriver || planet == null)
            return;

        disabledPlanetDriver = false;
        planet.enabled = true;
    }

    private void RequestSnapshot()
    {
        GraphicsBuffer[] buffers =
        {
            hierarchy.ActiveLeafCountBuffer,
            hierarchy.ActiveLeafMinLodBuffer,
            hierarchy.ActiveLeafMaxLodBuffer,
            hierarchy.VertexCountBuffer,
            hierarchy.IndexCountBuffer,
            hierarchy.MeshOverflowFlagsBuffer,
            hierarchy.ActiveLeafBuffer
        };

        for (int i = 0; i < buffers.Length; i++)
        {
            if (buffers[i] == null)
            {
                Debug.LogError(
                    $"[VoxelPlanetV1Test] Snapshot buffer {i} is null; " +
                    "mesh diagnostics cannot be read.",
                    this
                );
                return;
            }
        }

        pending = true;
        completed = 0;
        int thisGeneration = ++generation;

        for (int i = 0; i < buffers.Length; i++)
        {
            int valueIndex = i;
            AsyncGPUReadback.Request(
                buffers[i],
                request => OnReadback(thisGeneration, valueIndex, request)
            );
        }
    }

    private void OnReadback(
        int thisGeneration,
        int valueIndex,
        AsyncGPUReadbackRequest request)
    {
        if (thisGeneration != generation || !isActiveAndEnabled)
            return;

        if (request.hasError)
        {
            pending = false;
            Debug.LogError("[VoxelPlanetV1Test] GPU readback failed.", this);
            return;
        }

        var data = request.GetData<uint>();
        if (data.Length == 0)
        {
            pending = false;
            Debug.LogError("[VoxelPlanetV1Test] Readback buffer is empty.", this);
            return;
        }

        if (valueIndex == 6)
        {
            const int wordsPerLeaf = 6;
            int leafCount = Mathf.Min(
                data.Length / wordsPerLeaf,
                leafLods.Length
            );

            for (int leaf = 0; leaf < leafCount; leaf++)
                leafLods[leaf] = data[leaf * wordsPerLeaf + 1];

            values[valueIndex] = 1u;
        }
        else
        {
            values[valueIndex] = data[0];
        }

        completed++;
        if (completed != values.Length)
            return;

        pending = false;
        uint active = values[0];
        uint minLod = values[1];
        uint maxLod = values[2];
        uint vertices = values[3];
        uint indices = values[4];
        uint flags = values[5];
        bool mixedLod = minLod != maxLod;

        // Always emit the first snapshot so a healthy single-LOD result can be
        // distinguished from a renderer that is not drawing. Later snapshots
        // can stay quiet while the single-LOD mesh remains healthy.
        if (reportOnlyMixedLod && !mixedLod && flags == 0u &&
            vertices > 0u && indices > 0u && hasReportedSnapshot)
            return;

        hasReportedSnapshot = true;
        Debug.Log(
            $"[VoxelPlanetV1Test] Active={active} " +
            $"LOD=[{minLod}..{maxLod}] " +
            $"LODCounts={FormatLodHistogram(active)} " +
            $"MeshV={vertices} MeshI={indices} " +
            $"MeshFlags=0x{flags:X8} " +
            $"TrianglesValid={(indices % 3u) == 0u}",
            this
        );
    }

    private string FormatLodHistogram(uint activeLeafCount)
    {
        uint[] counts = new uint[26];
        int count = Mathf.Min((int)activeLeafCount, leafLods.Length);

        for (int leaf = 0; leaf < count; leaf++)
        {
            uint lod = leafLods[leaf];
            if (lod < counts.Length)
                counts[lod]++;
        }

        var result = new StringBuilder("[");
        bool first = true;
        for (int lod = 0; lod < counts.Length; lod++)
        {
            if (counts[lod] == 0u)
                continue;

            if (!first)
                result.Append(", ");

            result.Append(lod).Append(':').Append(counts[lod]);
            first = false;
        }

        return result.Append(']').ToString();
    }
}
