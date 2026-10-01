using UnityEngine;

[CreateAssetMenu(
    fileName = "VoxelPlanetDefinition",
    menuName = "Voxel Planet/Planet Definition")]
public sealed class VoxelPlanetDefinition : ScriptableObject
{
    [Header("Planet")]
    [SerializeField] private Vector3 planetCenter = Vector3.zero;
    [SerializeField, Min(1f)] private float planetRadius = 25000f;

    [Header("Terrain")]
    [SerializeField, Min(0f)] private float noiseHeight = 1500f;
    [SerializeField, Min(0.0000001f)] private float noiseFrequency = 0.00008f;
    [SerializeField, Min(1)] private int noiseSeed = 1;
    [SerializeField, Range(1, 8)] private int noiseOctaves = 5;
    [SerializeField, Range(0.1f, 0.9f)] private float noiseGain = 0.5f;
    [SerializeField, Range(1.5f, 3f)] private float noiseLacunarity = 2f;

    [Header("Patch LOD")]
    [SerializeField, Range(4, 64)] private int patchResolution = 16;
    [SerializeField, Range(0, 16)] private int minLod = 0;
    [SerializeField, Range(0, 18)] private int maxLod = 13;
    [SerializeField, Min(0.1f)] private float splitDistanceMultiplier = 1.65f;
    [SerializeField, Min(0.1f)] private float mergeDistanceMultiplier = 2.35f;
    [SerializeField, Min(1)] private int maxPatchCount = 2048;
    [SerializeField, Min(0f)] private float skirtDepth = 32f;

    public Vector3 PlanetCenter => planetCenter;
    public float PlanetRadius => planetRadius;
    public float NoiseHeight => noiseHeight;
    public float NoiseFrequency => noiseFrequency;
    public int NoiseSeed => noiseSeed;
    public int NoiseOctaves => noiseOctaves;
    public float NoiseGain => noiseGain;
    public float NoiseLacunarity => noiseLacunarity;
    public int PatchResolution => patchResolution;
    public int MinLod => minLod;
    public int MaxLod => Mathf.Max(minLod, maxLod);
    public float SplitDistanceMultiplier => splitDistanceMultiplier;
    public float MergeDistanceMultiplier => Mathf.Max(splitDistanceMultiplier + 0.05f, mergeDistanceMultiplier);
    public int MaxPatchCount => maxPatchCount;
    public float SkirtDepth => skirtDepth > 0f ? skirtDepth : Mathf.Max(4f, noiseHeight * 0.5f);

    public float PlanetDiameter => planetRadius * 2f + noiseHeight * 2f;

    public float SampleHeight(Vector3 direction)
    {
        direction.Normalize();

        if (noiseHeight <= 0f || NoiseFrequency <= 0f)
            return 0f;

        Vector3 p = direction * (planetRadius * noiseFrequency);
        float amplitude = 1f;
        float frequency = 1f;
        float value = 0f;
        float amplitudeSum = 0f;

        int octaves = Mathf.Max(1, noiseOctaves);
        for (int octave = 0; octave < octaves; octave++)
        {
            value += SignedValueNoise(p * frequency, noiseSeed + octave * 1013) * amplitude;
            amplitudeSum += amplitude;
            amplitude *= noiseGain;
            frequency *= noiseLacunarity;
        }

        value /= Mathf.Max(0.0001f, amplitudeSum);
        return value * noiseHeight;
    }

    private static float SignedValueNoise(Vector3 p, int seed)
    {
        int x0 = Mathf.FloorToInt(p.x);
        int y0 = Mathf.FloorToInt(p.y);
        int z0 = Mathf.FloorToInt(p.z);

        float tx = p.x - x0;
        float ty = p.y - y0;
        float tz = p.z - z0;

        tx = Fade(tx);
        ty = Fade(ty);
        tz = Fade(tz);

        float c000 = Hash01(x0, y0, z0, seed);
        float c100 = Hash01(x0 + 1, y0, z0, seed);
        float c010 = Hash01(x0, y0 + 1, z0, seed);
        float c110 = Hash01(x0 + 1, y0 + 1, z0, seed);
        float c001 = Hash01(x0, y0, z0 + 1, seed);
        float c101 = Hash01(x0 + 1, y0, z0 + 1, seed);
        float c011 = Hash01(x0, y0 + 1, z0 + 1, seed);
        float c111 = Hash01(x0 + 1, y0 + 1, z0 + 1, seed);

        float x00 = Mathf.Lerp(c000, c100, tx);
        float x10 = Mathf.Lerp(c010, c110, tx);
        float x01 = Mathf.Lerp(c001, c101, tx);
        float x11 = Mathf.Lerp(c011, c111, tx);

        float y0v = Mathf.Lerp(x00, x10, ty);
        float y1v = Mathf.Lerp(x01, x11, ty);

        return Mathf.Lerp(y0v, y1v, tz) * 2f - 1f;
    }

    private static float Fade(float t)
    {
        return t * t * t * (t * (t * 6f - 15f) + 10f);
    }

    private static float Hash01(int x, int y, int z, int seed)
    {
        unchecked
        {
            uint h = (uint)seed;
            h ^= (uint)x * 374761393u;
            h ^= (uint)y * 668265263u;
            h ^= (uint)z * 2147483647u;
            h ^= h >> 13;
            h *= 1274126177u;
            h ^= h >> 16;
            return (h & 0x00FFFFFFu) / 16777215f;
        }
    }

#if UNITY_EDITOR
    private void OnValidate()
    {
        planetRadius = Mathf.Max(1f, planetRadius);
        noiseHeight = Mathf.Max(0f, noiseHeight);
        noiseFrequency = Mathf.Max(0.0000001f, noiseFrequency);
        patchResolution = Mathf.Clamp(patchResolution, 4, 64);
        minLod = Mathf.Clamp(minLod, 0, 16);
        maxLod = Mathf.Clamp(Mathf.Max(minLod, maxLod), minLod, 18);
        splitDistanceMultiplier = Mathf.Max(0.1f, splitDistanceMultiplier);
        mergeDistanceMultiplier = Mathf.Max(splitDistanceMultiplier + 0.05f, mergeDistanceMultiplier);
        maxPatchCount = Mathf.Max(16, maxPatchCount);
        skirtDepth = Mathf.Max(0f, skirtDepth);
    }
#endif
}
