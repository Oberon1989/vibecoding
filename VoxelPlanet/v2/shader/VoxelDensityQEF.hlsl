#ifndef VOXEL_DENSITY_QEF_INCLUDED
#define VOXEL_DENSITY_QEF_INCLUDED


#include "VoxelDensityTypes.hlsl"
#include "VoxelDensityMath.hlsl"
#include "VoxelDensityDensity.hlsl"


// ============================================================
// QEF DATA
// ============================================================
//
// Symmetric 3x3 ATA:
//
//     [ ata00 ata01 ata02 ]
// A = [ ata01 ata11 ata12 ]
//     [ ata02 ata12 ata22 ]
//
// Atb:
//
//     [ atb0 ]
// b = [ atb1 ]
//     [ atb2 ]
//
// Constraint points are accumulated in cell-local coordinates.
// Intersection points remain in world space for fallbacks.
// ============================================================

struct QEFData
{
    float ata00;
    float ata01;
    float ata02;

    float ata11;
    float ata12;

    float ata22;

    float atb0;
    float atb1;
    float atb2;

    float3 intersectionSum;
    float3 constraintPointSum;

    uint intersectionCount;
    uint constraintCount;
};


// ============================================================
// RESET QEF
// ============================================================

void ResetQEF(
    out QEFData qef)
{
    qef.ata00 =
        0.0f;

    qef.ata01 =
        0.0f;

    qef.ata02 =
        0.0f;

    qef.ata11 =
        0.0f;

    qef.ata12 =
        0.0f;

    qef.ata22 =
        0.0f;

    qef.atb0 =
        0.0f;

    qef.atb1 =
        0.0f;

    qef.atb2 =
        0.0f;

    qef.intersectionSum =
        0.0f;

    qef.constraintPointSum =
        0.0f;

    qef.intersectionCount =
        0u;

    qef.constraintCount =
        0u;
}


// ============================================================
// ACCUMULATE CONSTRAINT
// ============================================================
//
// p0 / p1:
//     world-space edge endpoints
//
// d0 / d1:
//     density values
//
// cellCenter:
//     world-space center of current DC cell
//
// IMPORTANT:
//     This signature intentionally remains compatible with the
//     existing VoxelDensityMesh.hlsl.
//
// EstimateNormal() in the current density implementation takes
// only the world-space position.
// ============================================================

void AccumulateConstraint(
    inout QEFData qef,
    float3 p0,
    float3 p1,
    float d0,
    float d1,
    float3 cellCenter)
{
    if (!IsFiniteFloat(d0) ||
        !IsFiniteFloat(d1))
    {
        return;
    }


    bool signChange =
        (d0 < 0.0f && d1 >= 0.0f) ||
        (d1 < 0.0f && d0 >= 0.0f);


    if (!signChange)
    {
        return;
    }


    float denominator =
        d0 -
        d1;


    float t =
        0.5f;


    if (abs(denominator) >
        INTERSECTION_EPSILON)
    {
        t =
            d0 /
            denominator;
    }


    t =
        saturate(t);


    float3 intersection =
        lerp(
            p0,
            p1,
            t
        );


    if (!IsFiniteFloat3(
        intersection))
    {
        return;
    }


    // --------------------------------------------------------
    // Current EstimateNormal() uses the density implementation's
    // own finite-difference step.
    // --------------------------------------------------------

    float3 normal =
        EstimateNormal(
            intersection
        );


    if (!IsFiniteFloat3(
        normal))
    {
        return;
    }


    float normalLengthSquared =
        dot(
            normal,
            normal
        );


    if (!IsFiniteFloat(
        normalLengthSquared) ||
        normalLengthSquared <=
            NORMAL_EPSILON)
    {
        return;
    }


    normal =
        normalize(normal);


    float3 localPoint =
        intersection -
        cellCenter;


    if (!IsFiniteFloat3(
        localPoint))
    {
        return;
    }


    float planeOffset =
        dot(
            normal,
            localPoint
        );


    if (!IsFiniteFloat(
        planeOffset))
    {
        return;
    }


    // ========================================================
    // ATA
    // ========================================================

    qef.ata00 +=
        normal.x *
        normal.x;

    qef.ata01 +=
        normal.x *
        normal.y;

    qef.ata02 +=
        normal.x *
        normal.z;

    qef.ata11 +=
        normal.y *
        normal.y;

    qef.ata12 +=
        normal.y *
        normal.z;

    qef.ata22 +=
        normal.z *
        normal.z;


    // ========================================================
    // ATB
    // ========================================================

    qef.atb0 +=
        normal.x *
        planeOffset;

    qef.atb1 +=
        normal.y *
        planeOffset;

    qef.atb2 +=
        normal.z *
        planeOffset;


    // ========================================================
    // FALLBACK ACCUMULATORS
    // ========================================================

    qef.intersectionSum +=
        intersection;


    qef.constraintPointSum +=
        localPoint;


    qef.intersectionCount +=
        1u;


    qef.constraintCount +=
        1u;
}


// ============================================================
// CHECK LOCAL POSITION AGAINST CURRENT CELL
// ============================================================
//
// IMPORTANT:
//
//     cellStep is the ACTUAL world-space size of the current
//     adaptive DC cell.
//
// We must not use the global Step here.
// ============================================================

bool IsInsideCellLocal(
    float3 localPosition,
    float cellStep)
{
    if (!IsFiniteFloat3(
        localPosition))
    {
        return false;
    }


    float safeCellStep =
        max(
            abs(cellStep),
            BASE_LATTICE_SIZE
        );


    float halfStep =
        safeCellStep *
        0.5f;


    float tolerance =
        max(
            safeCellStep * 0.001f,
            EPSILON
        );


    return
        localPosition.x >=
            -halfStep - tolerance &&
        localPosition.x <=
            halfStep + tolerance &&

        localPosition.y >=
            -halfStep - tolerance &&
        localPosition.y <=
            halfStep + tolerance &&

        localPosition.z >=
            -halfStep - tolerance &&
        localPosition.z <=
            halfStep + tolerance;
}


// ============================================================
// CLAMP LOCAL POSITION TO CURRENT CELL
// ============================================================

float3 ClampIntersectionToCell(
    float3 localPosition,
    float cellStep)
{
    float safeCellStep =
        max(
            abs(cellStep),
            BASE_LATTICE_SIZE
        );


    float halfStep =
        safeCellStep *
        0.5f;


    float3 result =
        localPosition;


    result.x =
        clamp(
            result.x,
            -halfStep,
            halfStep
        );


    result.y =
        clamp(
            result.y,
            -halfStep,
            halfStep
        );


    result.z =
        clamp(
            result.z,
            -halfStep,
            halfStep
        );


    return result;
}


// ============================================================
// SOLVE 3x3 LINEAR SYSTEM
// ============================================================
//
// Explicit augmented rows are used here instead of float3x4.
//
// This avoids Unity/HLSL parser issues while preserving the same
// Gaussian elimination with partial pivoting.
// ============================================================

bool SolveQEF(
    QEFData qef,
    out float3 solution)
{
    solution =
        0.0f;


    // ========================================================
    // AUGMENTED MATRIX
    // ========================================================

    float4 row0 =
        float4(
            qef.ata00,
            qef.ata01,
            qef.ata02,
            qef.atb0
        );


    float4 row1 =
        float4(
            qef.ata01,
            qef.ata11,
            qef.ata12,
            qef.atb1
        );


    float4 row2 =
        float4(
            qef.ata02,
            qef.ata12,
            qef.ata22,
            qef.atb2
        );


    // ========================================================
    // PIVOT COLUMN 0
    // ========================================================

    float pivot0 =
        abs(row0.x);

    int pivotRow0 =
        0;


    float candidate10 =
        abs(row1.x);


    if (candidate10 >
        pivot0)
    {
        pivot0 =
            candidate10;

        pivotRow0 =
            1;
    }


    float candidate20 =
        abs(row2.x);


    if (candidate20 >
        pivot0)
    {
        pivot0 =
            candidate20;

        pivotRow0 =
            2;
    }


    if (!IsFiniteFloat(pivot0) ||
        pivot0 <= EPSILON)
    {
        return false;
    }


    if (pivotRow0 == 1)
    {
        float4 temporary =
            row0;

        row0 =
            row1;

        row1 =
            temporary;
    }
    else if (pivotRow0 == 2)
    {
        float4 temporary =
            row0;

        row0 =
            row2;

        row2 =
            temporary;
    }


    // ========================================================
    // ELIMINATE COLUMN 0
    // ========================================================

    float factor10 =
        row1.x /
        row0.x;


    float factor20 =
        row2.x /
        row0.x;


    if (!IsFiniteFloat(factor10) ||
        !IsFiniteFloat(factor20))
    {
        return false;
    }


    row1 -=
        factor10 *
        row0;


    row2 -=
        factor20 *
        row0;


    // ========================================================
    // PIVOT COLUMN 1
    // ========================================================

    float pivot1 =
        abs(row1.y);

    int pivotRow1 =
        1;


    float candidate21 =
        abs(row2.y);


    if (candidate21 >
        pivot1)
    {
        pivot1 =
            candidate21;

        pivotRow1 =
            2;
    }


    if (!IsFiniteFloat(pivot1) ||
        pivot1 <= EPSILON)
    {
        return false;
    }


    if (pivotRow1 == 2)
    {
        float4 temporary =
            row1;

        row1 =
            row2;

        row2 =
            temporary;
    }


    // ========================================================
    // ELIMINATE COLUMN 1
    // ========================================================

    float factor21 =
        row2.y /
        row1.y;


    if (!IsFiniteFloat(
        factor21))
    {
        return false;
    }


    row2 -=
        factor21 *
        row1;


    // ========================================================
    // FINAL PIVOT
    // ========================================================

    float pivot2 =
        abs(row2.z);


    if (!IsFiniteFloat(
        pivot2) ||
        pivot2 <= EPSILON)
    {
        return false;
    }


    // ========================================================
    // BACK SUBSTITUTION
    // ========================================================

    float x2 =
        row2.w /
        row2.z;


    if (!IsFiniteFloat(x2))
    {
        return false;
    }


    float x1 =
        (
            row1.w -
            row1.z * x2
        ) /
        row1.y;


    if (!IsFiniteFloat(x1))
    {
        return false;
    }


    float x0 =
        (
            row0.w -
            row0.y * x1 -
            row0.z * x2
        ) /
        row0.x;


    if (!IsFiniteFloat(x0))
    {
        return false;
    }


    solution =
        float3(
            x0,
            x1,
            x2
        );


    if (!IsFiniteFloat3(
        solution))
    {
        return false;
    }


    return true;
}


// ============================================================
// SOLVE CELL VERTEX
// ============================================================
//
// cellCenter:
//     world-space center of current DC cell
//
// cellMin / cellMax:
//     world-space bounds of current DC cell
//
// cellStep:
//     ACTUAL world-space size of current DC cell
//
// This cellStep is the critical adaptive-LOD correction.
// ============================================================

float3 SolveCellVertex(
    QEFData qef,
    float3 cellCenter,
    float3 cellMin,
    float3 cellMax,
    float cellStep)
{
    float3 localSolution =
        0.0f;


    // ========================================================
    // PRIMARY QEF SOLUTION
    // ========================================================

    bool solved =
        false;


    if (qef.constraintCount >= 1u)
    {
        solved =
            SolveQEF(
                qef,
                localSolution
            );
    }


    if (solved &&
        IsInsideCellLocal(
            localSolution,
            cellStep))
    {
        float3 worldSolution =
            cellCenter +
            localSolution;


        if (IsFiniteFloat3(
            worldSolution))
        {
            return clamp(
                worldSolution,
                cellMin,
                cellMax
            );
        }
    }


    // ========================================================
    // FALLBACK 1:
    // AVERAGE CONSTRAINT POINT
    // ========================================================

    if (qef.constraintCount > 0u)
    {
        float inverseCount =
            1.0f /
            (float) qef.constraintCount;


        float3 averageConstraintLocal =
            qef.constraintPointSum *
            inverseCount;


        if (IsFiniteFloat3(
            averageConstraintLocal))
        {
            if (IsInsideCellLocal(
                averageConstraintLocal,
                cellStep))
            {
                float3 worldAverageConstraint =
                    cellCenter +
                    averageConstraintLocal;


                if (IsFiniteFloat3(
                    worldAverageConstraint))
                {
                    return clamp(
                        worldAverageConstraint,
                        cellMin,
                        cellMax
                    );
                }
            }
        }
    }


    // ========================================================
    // FALLBACK 2:
    // AVERAGE EDGE INTERSECTIONS
    // ========================================================

    if (qef.intersectionCount > 0u)
    {
        float inverseCount =
            1.0f /
            (float) qef.intersectionCount;


        float3 averageIntersection =
            qef.intersectionSum *
            inverseCount;


        if (IsFiniteFloat3(
            averageIntersection))
        {
            float3 averageLocal =
                averageIntersection -
                cellCenter;


            averageLocal =
                ClampIntersectionToCell(
                    averageLocal,
                    cellStep
                );


            float3 worldAverage =
                cellCenter +
                averageLocal;


            if (IsFiniteFloat3(
                worldAverage))
            {
                return clamp(
                    worldAverage,
                    cellMin,
                    cellMax
                );
            }
        }
    }


    // ========================================================
    // FINAL FALLBACK:
    // CELL CENTER
    // ========================================================

    float3 center =
        cellCenter;


    if (!IsFiniteFloat3(
        center))
    {
        center =
            0.5f *
            (
                cellMin +
                cellMax
            );
    }


    return clamp(
        center,
        cellMin,
        cellMax
    );
}


#endif