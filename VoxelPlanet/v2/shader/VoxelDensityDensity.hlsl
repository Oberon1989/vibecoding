#ifndef VOXEL_DENSITY_DENSITY_INCLUDED
#define VOXEL_DENSITY_DENSITY_INCLUDED


#include "VoxelDensityTypes.hlsl"
#include "VoxelDensityMath.hlsl"
#include "Noise/TerrainNoisePerlin.hlsl"


// ============================================================
// SAMPLE DENSITY
// ============================================================
//
// Density convention:
//
//     density < 0  = inside planet
//     density >= 0 = outside planet
//
// Base surface:
//
//     distance(position, PlanetCenter) - PlanetRadius
//
// Terrain:
//
//     density = sphereDensity - noise * NoiseHeight
//
// IMPORTANT:
//
// This function intentionally preserves the original noise API.
// ============================================================

float SampleDensity(
    float3 position)
{
    float sphereDensity =
        distance(
            position,
            PlanetCenter
        )
        -
        PlanetRadius;


    float density = sphereDensity;

    // Keep the no-terrain-noise fast path while still applying runtime edits.
    if (NoiseHeight != 0.0f)
    {
        float3 directionVector = position - PlanetCenter;
        float directionLengthSquared = dot(directionVector, directionVector);

        // The planet center has no defined radial direction.
        float3 direction = directionLengthSquared <= NORMAL_EPSILON
            ? float3(0.0f, 1.0f, 0.0f)
            : directionVector * rsqrt(directionLengthSquared);

        float noiseValue = TerrainNoisePerlin3D(
            direction,
            NoiseFrequency,
            (uint)NoiseSeed
        );

        density -= noiseValue * NoiseHeight;
    }

    // Runtime-only brush stamps modify the analytic density field. The
    // global bounds reject almost all samples while edits are localized.
    if (DensityEditCount > 0 &&
        all(position >= DensityEditBoundsMin) &&
        all(position <= DensityEditBoundsMax))
    {
        [loop]
        for (int editIndex = 0;
             editIndex < DensityEditCount;
             editIndex++)
        {
            DensityEditStamp edit = DensityEditBuffer[editIndex];
            float radius = max(edit.centerRadius.w, 0.5f);
            float3 offset = position - edit.centerRadius.xyz;
            float distanceSquared = dot(offset, offset);

            if (distanceSquared >= radius * radius)
                continue;

            float distanceToCenter = sqrt(distanceSquared);
            float falloff = 1.0f - smoothstep(0.0f, radius, distanceToCenter);
            density += edit.parameters.x * falloff;
        }
    }

    return density;
}


// ============================================================
// ESTIMATE NORMAL
// ============================================================
//
// Central finite difference:
//
//     dx = D(x+h) - D(x-h)
//     dy = D(y+h) - D(y-h)
//     dz = D(z+h) - D(z-h)
//
// The sampling distance follows the original implementation:
//
//     h = max(Step * 0.25, 0.001)
//
// Because Step belongs to the current chunk, the same function
// works for all LOD levels.
// ============================================================

float3 EstimateNormal(
    float3 position)
{
    float h =
        max(
            Step * 0.25f,
            0.001f
        );


    // --------------------------------------------------------
    // X derivative
    // --------------------------------------------------------

    float dx =
        SampleDensity(
            position +
            float3(
                h,
                0.0f,
                0.0f
            )
        )
        -
        SampleDensity(
            position -
            float3(
                h,
                0.0f,
                0.0f
            )
        );


    // --------------------------------------------------------
    // Y derivative
    // --------------------------------------------------------

    float dy =
        SampleDensity(
            position +
            float3(
                0.0f,
                h,
                0.0f
            )
        )
        -
        SampleDensity(
            position -
            float3(
                0.0f,
                h,
                0.0f
            )
        );


    // --------------------------------------------------------
    // Z derivative
    // --------------------------------------------------------

    float dz =
        SampleDensity(
            position +
            float3(
                0.0f,
                0.0f,
                h
            )
        )
        -
        SampleDensity(
            position -
            float3(
                0.0f,
                0.0f,
                h
            )
        );


    float3 gradient =
        float3(
            dx,
            dy,
            dz
        );


    // --------------------------------------------------------
    // Safe normalization.
    // --------------------------------------------------------

    return SafeNormalize(
        gradient,
        float3(
            0.0f,
            1.0f,
            0.0f
        )
    );
}


#endif
