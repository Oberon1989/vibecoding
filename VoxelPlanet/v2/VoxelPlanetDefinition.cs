using UnityEngine;

[CreateAssetMenu(
    fileName = "VoxelPlanetDefinition",
    menuName = "Voxel Planet/Planet Definition"
)]
public class VoxelPlanetDefinition : ScriptableObject
{
    [Header("Planet")]
    [SerializeField] private Vector3 planetCenter = Vector3.zero;
    [SerializeField] private float planetRadius = 30000.0f;

    [Header("Noise")]
    [SerializeField] private int noiseSeed = 1;
    [SerializeField] private float noiseFrequency = 0.0001f;
    [SerializeField] private float noiseHeight = 0.0f;

    public Vector3 PlanetCenter => planetCenter;

    public float PlanetRadius => planetRadius;

    public int NoiseSeed => noiseSeed;

    public float NoiseFrequency => noiseFrequency;

    public float NoiseHeight => noiseHeight;

    public float PlanetDiameter =>
        planetRadius * 2.0f +
        Mathf.Abs(noiseHeight) * 2.0f;

#if UNITY_EDITOR
    private void OnValidate()
    {
        if (planetRadius < 0.0f)
        {
            planetRadius = 0.0f;
        }

        if (noiseFrequency < 0.0f)
        {
            noiseFrequency = 0.0f;
        }

        if (noiseHeight < 0.0f)
        {
            noiseHeight = Mathf.Abs(noiseHeight);
        }
    }
#endif
}