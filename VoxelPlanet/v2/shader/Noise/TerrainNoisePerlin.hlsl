#ifndef TERRAIN_NOISE_PERLIN_INCLUDED
#define TERRAIN_NOISE_PERLIN_INCLUDED

#include "TerrainNoiseCommon.hlsl"


// ============================================================
// GRADIENT DOT
//
// Компактный 3D gradient.
// Использует 12 направлений:
// (±1,±1,0), (±1,0,±1), (0,±1,±1)
//
// Без switch и массивов.
// ============================================================

float TerrainGradientDot3D(
    int x,
    int y,
    int z,
    float dx,
    float dy,
    float dz,
    uint seed)
{
    uint h =
        TerrainHash3D(
            x,
            y,
            z,
            seed
        );

    float sx =
        ((h & 1u) != 0u)
        ? 1.0f
        : -1.0f;

    float sy =
        ((h & 2u) != 0u)
        ? 1.0f
        : -1.0f;

    uint axis =
        (h >> 2) % 3u;


    float result;


    if (axis == 0u)
    {
        // (sx, sy, 0)

        result =
            sx * dx +
            sy * dy;
    }
    else if (axis == 1u)
    {
        // (0, sx, sy)

        result =
            sx * dy +
            sy * dz;
    }
    else
    {
        // (sx, 0, sy)

        result =
            sx * dx +
            sy * dz;
    }


    return result;
}


// ============================================================
// 3D PERLIN
//
// Output roughly around [-1, 1].
// ============================================================

float TerrainNoisePerlin3D(
    float3 position,
    float frequency,
    uint seed)
{
    // --------------------------------------------------------
    // Optional fast path.
    // --------------------------------------------------------

    if (frequency <= 0.0f)
    {
        return 0.0f;
    }


    // --------------------------------------------------------
    // Scale
    // --------------------------------------------------------

    float3 p =
        position *
        frequency;


    // --------------------------------------------------------
    // Integer lattice coordinate
    // --------------------------------------------------------

    int ix =
        (int) floor(p.x);

    int iy =
        (int) floor(p.y);

    int iz =
        (int) floor(p.z);


    // --------------------------------------------------------
    // Local position
    // --------------------------------------------------------

    float fx =
        p.x -
        (float) ix;

    float fy =
        p.y -
        (float) iy;

    float fz =
        p.z -
        (float) iz;


    // --------------------------------------------------------
    // Quintic fade
    // --------------------------------------------------------

    float wx =
        TerrainFade(fx);

    float wy =
        TerrainFade(fy);

    float wz =
        TerrainFade(fz);


    // ========================================================
    // 8 CORNERS
    // ========================================================

    float n000 =
        TerrainGradientDot3D(
            ix,
            iy,
            iz,
            fx,
            fy,
            fz,
            seed
        );


    float n100 =
        TerrainGradientDot3D(
            ix + 1,
            iy,
            iz,
            fx - 1.0f,
            fy,
            fz,
            seed
        );


    float n010 =
        TerrainGradientDot3D(
            ix,
            iy + 1,
            iz,
            fx,
            fy - 1.0f,
            fz,
            seed
        );


    float n110 =
        TerrainGradientDot3D(
            ix + 1,
            iy + 1,
            iz,
            fx - 1.0f,
            fy - 1.0f,
            fz,
            seed
        );


    float n001 =
        TerrainGradientDot3D(
            ix,
            iy,
            iz + 1,
            fx,
            fy,
            fz - 1.0f,
            seed
        );


    float n101 =
        TerrainGradientDot3D(
            ix + 1,
            iy,
            iz + 1,
            fx - 1.0f,
            fy,
            fz - 1.0f,
            seed
        );


    float n011 =
        TerrainGradientDot3D(
            ix,
            iy + 1,
            iz + 1,
            fx,
            fy - 1.0f,
            fz - 1.0f,
            seed
        );


    float n111 =
        TerrainGradientDot3D(
            ix + 1,
            iy + 1,
            iz + 1,
            fx - 1.0f,
            fy - 1.0f,
            fz - 1.0f,
            seed
        );


    // ========================================================
    // X
    // ========================================================

    float nx00 =
        lerp(
            n000,
            n100,
            wx
        );

    float nx10 =
        lerp(
            n010,
            n110,
            wx
        );

    float nx01 =
        lerp(
            n001,
            n101,
            wx
        );

    float nx11 =
        lerp(
            n011,
            n111,
            wx
        );


    // ========================================================
    // Y
    // ========================================================

    float nxy0 =
        lerp(
            nx00,
            nx10,
            wy
        );

    float nxy1 =
        lerp(
            nx01,
            nx11,
            wy
        );


    // ========================================================
    // Z
    // ========================================================

    float result =
        lerp(
            nxy0,
            nxy1,
            wz
        );


    // Scale to convenient terrain range.
    result *= 0.95f;


    return clamp(
        result,
        -1.0f,
        1.0f
    );
}


#endif