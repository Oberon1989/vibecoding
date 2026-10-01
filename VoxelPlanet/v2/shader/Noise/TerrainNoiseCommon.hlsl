#ifndef TERRAIN_NOISE_COMMON_INCLUDED
#define TERRAIN_NOISE_COMMON_INCLUDED


// ============================================================
// HASH
// ============================================================

uint TerrainHash3D(
    int x,
    int y,
    int z,
    uint seed)
{
    uint h =
        seed;

    h ^=
        (uint) x *
        0x9E3779B9u;

    h ^=
        (uint) y *
        0x85EBCA6Bu;

    h ^=
        (uint) z *
        0xC2B2AE35u;

    h ^=
        h >> 16;

    h *=
        0x7FEB352Du;

    h ^=
        h >> 15;

    h *=
        0x846CA68Bu;

    h ^=
        h >> 16;

    return h;
}


// ============================================================
// PERLIN GRADIENT
// ============================================================

float3 TerrainGradient3D(
    uint hash)
{
    uint h =
        hash % 12u;

    if (h == 0u)
        return float3(1.0f, 1.0f, 0.0f);

    if (h == 1u)
        return float3(-1.0f, 1.0f, 0.0f);

    if (h == 2u)
        return float3(1.0f, -1.0f, 0.0f);

    if (h == 3u)
        return float3(-1.0f, -1.0f, 0.0f);

    if (h == 4u)
        return float3(1.0f, 0.0f, 1.0f);

    if (h == 5u)
        return float3(-1.0f, 0.0f, 1.0f);

    if (h == 6u)
        return float3(1.0f, 0.0f, -1.0f);

    if (h == 7u)
        return float3(-1.0f, 0.0f, -1.0f);

    if (h == 8u)
        return float3(0.0f, 1.0f, 1.0f);

    if (h == 9u)
        return float3(0.0f, -1.0f, 1.0f);

    if (h == 10u)
        return float3(0.0f, 1.0f, -1.0f);

    return float3(0.0f, -1.0f, -1.0f);
}


// ============================================================
// PERLIN FADE
//
// 6t^5 - 15t^4 + 10t^3
// ============================================================

float TerrainFade(
    float t)
{
    return
        t * t * t *
        (
            t *
            (
                t * 6.0f -
                15.0f
            )
            +
            10.0f
        );
}


#endif