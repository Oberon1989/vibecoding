using UnityEngine;
using UnityEngine.Rendering;

[DisallowMultipleComponent]
[RequireComponent(typeof(VoxelPlanet))]
public class VoxelPlanetGpuRenderer : MonoBehaviour
{
    [Header("Source")]
    [SerializeField] private VoxelPlanet planet;

    [Header("Render")]
    [SerializeField] private Shader renderShader;
    [SerializeField]
    private Color baseColor =
        new Color(0.45f, 0.65f, 0.85f, 1.0f);

    [Header("Procedural Surface")]
    [SerializeField]
    private Color noiseColor =
        new Color(0.16f, 0.28f, 0.36f, 1.0f);

    [SerializeField, Min(1.0f)]
    private float noiseFeatureSize = 250.0f;

    [SerializeField, Range(0.0f, 1.0f)]
    private float noiseStrength = 0.75f;

    [Header("Lighting")]
    [SerializeField] private Light directionalLight;

    [SerializeField] private int renderLayer = 0;

    [Header("Debug Bounds")]
    [SerializeField] private float boundsPadding = 4.0f;

    [Header("Indirect Arguments (VoxelPlanetRenderArgs.compute)")]
    [SerializeField] private ComputeShader renderArgsShader;

    private VoxelGpuHierarchy hierarchy;

    private Material renderMaterial;
    private MaterialPropertyBlock materialProperties;
    private GraphicsBuffer renderArgsBuffer;

    private int buildRenderArgsKernel;

    private Bounds worldBounds;

    private bool initialized;

    private static readonly int VertexBufferId =
        Shader.PropertyToID("_VertexBuffer");

    private static readonly int NormalBufferId =
        Shader.PropertyToID("_NormalBuffer");

    private static readonly int IndexBufferId =
        Shader.PropertyToID("_IndexBuffer");

    private static readonly int BaseColorId =
        Shader.PropertyToID("_BaseColor");

    private static readonly int NoiseColorId =
        Shader.PropertyToID("_NoiseColor");

    private static readonly int PlanetCenterId =
        Shader.PropertyToID("_PlanetCenter");

    private static readonly int NoiseFrequencyId =
        Shader.PropertyToID("_NoiseFrequency");

    private static readonly int NoiseStrengthId =
        Shader.PropertyToID("_NoiseStrength");

    private static readonly int LightDirectionId =
        Shader.PropertyToID("_LightDirection");

    private static readonly int LightColorId =
        Shader.PropertyToID("_LightColor");

    private static readonly int AmbientColorId =
        Shader.PropertyToID("_AmbientColor");

    private void Reset()
    {
        planet =
            GetComponent<VoxelPlanet>();
    }

    private void Awake()
    {
        if (planet == null)
        {
            planet =
                GetComponent<VoxelPlanet>();
        }

        ResolveDirectionalLight();
    }

    private void OnEnable()
    {
        InitializeRenderer();
    }

    private void OnDisable()
    {
        ShutdownRenderer();
    }

    private void OnDestroy()
    {
        ShutdownRenderer();
    }

    private void LateUpdate()
    {
        if (!initialized)
            return;

        if (planet == null)
            return;

        hierarchy =
            planet.GpuHierarchy;

        if (hierarchy == null)
            return;

        if (!hierarchy.IsInitialized)
            return;

        if (hierarchy.IndexBuffer == null ||
            hierarchy.VertexBuffer == null ||
            hierarchy.NormalBuffer == null ||
            hierarchy.IndexCountBuffer == null)
        {
            return;
        }

        UpdateWorldBounds();

        BuildRenderArguments();

        RenderPlanet();
    }

    private void InitializeRenderer()
    {
        if (initialized)
            return;

        if (planet == null)
        {
            Debug.LogError(
                $"[{nameof(VoxelPlanetGpuRenderer)}] " +
                "VoxelPlanet is not assigned.",
                this
            );

            return;
        }

        hierarchy =
            planet.GpuHierarchy;

        if (hierarchy == null)
        {
            Debug.LogError(
                $"[{nameof(VoxelPlanetGpuRenderer)}] " +
                "VoxelGpuHierarchy was not found through VoxelPlanet.",
                this
            );

            return;
        }

        if (renderShader == null)
        {
            Debug.LogError(
                $"[{nameof(VoxelPlanetGpuRenderer)}] " +
                "Render Shader is not assigned.",
                this
            );

            return;
        }

        if (renderArgsShader == null)
        {
            Debug.LogError(
                $"[{nameof(VoxelPlanetGpuRenderer)}] " +
                "Render Args Compute Shader is not assigned. " +
                "Assign VoxelPlanetRenderArgs.compute here; " +
                "VoxelDensityV1.compute belongs on VoxelGpuHierarchy.",
                this
            );

            return;
        }

        if (!renderArgsShader.HasKernel("CSBuildRenderArgs"))
        {
            Debug.LogError(
                $"[{nameof(VoxelPlanetGpuRenderer)}] " +
                $"'{renderArgsShader.name}' has no CSBuildRenderArgs kernel. " +
                "Assign Assets/VoxelPlanet/v2/ComputeShaders/" +
                "VoxelPlanetRenderArgs.compute to Render Args Compute Shader. " +
                "Keep VoxelDensityV1.compute assigned to VoxelGpuHierarchy.",
                this
            );

            return;
        }

        buildRenderArgsKernel =
            renderArgsShader.FindKernel(
                "CSBuildRenderArgs"
            );

        renderMaterial =
            new Material(
                renderShader
            );

        renderMaterial.name =
            $"{gameObject.name}_VoxelPlanetGpuMaterial";

        renderMaterial.enableInstancing = true;

        materialProperties =
            new MaterialPropertyBlock();

        renderArgsBuffer =
            new GraphicsBuffer(
                GraphicsBuffer.Target.IndirectArguments,
                1,
                GraphicsBuffer.IndirectDrawArgs.size
            );

        UpdateWorldBounds();

        initialized = true;
    }

    private void BuildRenderArguments()
    {
        renderArgsShader.SetBuffer(
            buildRenderArgsKernel,
            "IndexCountBuffer",
            hierarchy.IndexCountBuffer
        );

        renderArgsShader.SetBuffer(
            buildRenderArgsKernel,
            "RenderArgsBuffer",
            renderArgsBuffer
        );

        renderArgsShader.Dispatch(
            buildRenderArgsKernel,
            1,
            1,
            1
        );
    }

    private void RenderPlanet()
    {
        materialProperties.Clear();

        materialProperties.SetBuffer(
            VertexBufferId,
            hierarchy.VertexBuffer
        );

        materialProperties.SetBuffer(
            NormalBufferId,
            hierarchy.NormalBuffer
        );

        materialProperties.SetBuffer(
            IndexBufferId,
            hierarchy.IndexBuffer
        );

        materialProperties.SetColor(
            BaseColorId,
            baseColor
        );

        materialProperties.SetColor(
            NoiseColorId,
            noiseColor
        );

        materialProperties.SetVector(
            PlanetCenterId,
            hierarchy.PlanetCenter
        );

        materialProperties.SetFloat(
            NoiseFrequencyId,
            1.0f / Mathf.Max(1.0f, noiseFeatureSize)
        );

        materialProperties.SetFloat(
            NoiseStrengthId,
            noiseStrength
        );

        Light sun = directionalLight;
        Vector3 lightDirection = sun != null
            ? -sun.transform.forward
            : new Vector3(0.4f, 0.8f, 0.3f).normalized;
        Color lightColor = sun != null
            ? sun.color * Mathf.Clamp01(sun.intensity)
            : Color.white;

        materialProperties.SetVector(
            LightDirectionId,
            lightDirection
        );

        materialProperties.SetColor(
            LightColorId,
            lightColor
        );

        materialProperties.SetColor(
            AmbientColorId,
            RenderSettings.ambientLight
        );

        RenderParams renderParams =
            new RenderParams(
                renderMaterial
            );

        renderParams.worldBounds =
            worldBounds;

        renderParams.matProps =
            materialProperties;

        renderParams.layer =
            renderLayer;

        renderParams.shadowCastingMode =
            ShadowCastingMode.Off;

        renderParams.receiveShadows =
            false;

        Graphics.RenderPrimitivesIndirect(
            renderParams,
            MeshTopology.Triangles,
            renderArgsBuffer,
            1,
            0
        );
    }

    private void ResolveDirectionalLight()
    {
        if (directionalLight != null)
            return;

        directionalLight = RenderSettings.sun;
        if (directionalLight != null)
            return;

        Light[] sceneLights =
            FindObjectsByType<Light>(FindObjectsSortMode.None);

        for (int i = 0; i < sceneLights.Length; i++)
        {
            if (sceneLights[i].isActiveAndEnabled &&
                sceneLights[i].type == LightType.Directional)
            {
                directionalLight = sceneLights[i];
                return;
            }
        }
    }

    private void UpdateWorldBounds()
    {
        if (hierarchy != null && hierarchy.IsInitialized)
        {
            float activeRadius = hierarchy.PlanetRadius;
            float activeNoiseHeight = Mathf.Abs(hierarchy.PlanetNoiseHeight);
            float activeDiameter =
                activeRadius * 2.0f +
                activeNoiseHeight * 2.0f +
                boundsPadding;

            worldBounds = new Bounds(
                hierarchy.PlanetCenter,
                Vector3.one * activeDiameter
            );
            return;
        }

        if (planet == null ||
            planet.Definition == null)
        {
            worldBounds =
                new Bounds(
                    transform.position,
                    Vector3.one * 100000.0f
                );

            return;
        }

        Vector3 center =
            planet.Definition.PlanetCenter;

        float radius =
            planet.Definition.PlanetRadius;

        float noiseHeight =
            Mathf.Abs(
                planet.Definition.NoiseHeight
            );

        float diameter =
            radius * 2.0f +
            noiseHeight * 2.0f +
            boundsPadding;

        worldBounds =
            new Bounds(
                center,
                Vector3.one * diameter
            );
    }

    private void ShutdownRenderer()
    {
        initialized = false;

        if (renderArgsBuffer != null)
        {
            renderArgsBuffer.Release();
            renderArgsBuffer = null;
        }

        if (renderMaterial != null)
        {
            if (Application.isPlaying)
            {
                Destroy(renderMaterial);
            }
            else
            {
                DestroyImmediate(renderMaterial);
            }

            renderMaterial = null;
        }

        materialProperties = null;
        hierarchy = null;
    }
}

