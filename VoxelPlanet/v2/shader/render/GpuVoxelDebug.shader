Shader "Unlit/GpuVoxelDebug"
{
    Properties
    {
        _Color ("Color", Color) =
            (0.3, 0.7, 1.0, 1.0)

        _Ambient ("Ambient", Range(0, 1)) =
            0.20

        _LightStrength ("Light Strength", Range(0, 2)) =
            1.0

        _Brightness ("Brightness", Range(0, 2)) =
            1.0

        _SpecularStrength ("Specular Strength", Range(0, 1)) =
            0.05

        _Smoothness ("Smoothness", Range(0, 1)) =
            0.25

        [Toggle]
        _DebugNormals ("Debug Normals", Float) =
            0
    }


    SubShader
    {
        Tags
        {
            "RenderType" = "Opaque"
            "Queue" = "Geometry"
        }


        Pass
        {
            ZWrite On
            ZTest LEqual

            // Пока оставляем OFF,
            // чтобы видеть обе стороны и
            // диагностировать нормали.
            Cull Back


            HLSLPROGRAM

            #pragma vertex vert
            #pragma fragment frag

            #include "UnityCG.cginc"


            // =================================================
            // BUFFERS
            // =================================================

            StructuredBuffer<float3> VertexBuffer;

            StructuredBuffer<float3> NormalBuffer;


            // =================================================
            // MATERIAL
            // =================================================

            float4 _Color;

            float _Ambient;

            float _LightStrength;

            float _Brightness;

            float _SpecularStrength;

            float _Smoothness;

            float _DebugNormals;


            // =================================================
            // VERTEX OUTPUT
            // =================================================

            struct VertexOutput
            {
                float4 position :
                    SV_POSITION;

                float3 worldPosition :
                    TEXCOORD0;

                float3 normal :
                    TEXCOORD1;

                float3 viewDirection :
                    TEXCOORD2;
            };


            // =================================================
            // VERTEX
            // =================================================

            VertexOutput vert(
                uint vertexID :
                SV_VertexID)
            {
                VertexOutput output;


                // ------------------------------------------------
                // Position
                // ------------------------------------------------

                float3 worldPosition =
                    VertexBuffer[
                        vertexID
                    ];


                // ------------------------------------------------
                // Normal
                // ------------------------------------------------

                float3 normal =
                    NormalBuffer[
                        vertexID
                    ];


                float normalLength =
                    dot(
                        normal,
                        normal
                    );


                if (normalLength < 0.000001f)
                {
                    normal =
                        float3(
                            0.0f,
                            1.0f,
                            0.0f
                        );
                }
                else
                {
                    normal =
                        normalize(
                            normal
                        );
                }


                // ------------------------------------------------
                // Clip position
                // ------------------------------------------------

                output.position =
                    mul(
                        UNITY_MATRIX_VP,
                        float4(
                            worldPosition,
                            1.0f
                        )
                    );


                // ------------------------------------------------
                // World position
                // ------------------------------------------------

                output.worldPosition =
                    worldPosition;


                // ------------------------------------------------
                // Normal
                // ------------------------------------------------

                output.normal =
                    normal;


                // ------------------------------------------------
                // View direction
                // ------------------------------------------------

                output.viewDirection =
                    normalize(
                        _WorldSpaceCameraPos -
                        worldPosition
                    );


                return output;
            }


            // =================================================
            // FRAGMENT
            // =================================================

            float4 frag(
                VertexOutput input
            ) : SV_Target
            {
                float3 normal =
                    normalize(
                        input.normal
                    );


                // =================================================
                // DEBUG NORMALS
                //
                // [-1, +1]
                //        ↓
                // [ 0, +1]
                //
                // X = R
                // Y = G
                // Z = B
                // =================================================

                if (_DebugNormals > 0.5f)
                {
                    float3 normalColor =
                        normal *
                        0.5f +
                        0.5f;


                    return float4(
                        normalColor,
                        1.0f
                    );
                }


                // =================================================
                // MAIN LIGHT
                //
                // _WorldSpaceLightPos0:
                //
                // w = 0 → directional light
                // w = 1 → point light
                // =================================================

                float3 lightDirection;


                if (_WorldSpaceLightPos0.w == 0.0f)
                {
                    lightDirection =
                        normalize(
                            _WorldSpaceLightPos0.xyz
                        );
                }
                else
                {
                    lightDirection =
                        normalize(
                            _WorldSpaceLightPos0.xyz -
                            input.worldPosition
                        );
                }


                // =================================================
                // DIFFUSE
                // =================================================

                float NdotL =
                    saturate(
                        dot(
                            normal,
                            lightDirection
                        )
                    );


                float3 diffuse =
                    _LightStrength *
                    NdotL;


                // =================================================
                // AMBIENT
                // =================================================

                float3 ambient =
                    _Ambient.xxx;


                // =================================================
                // SPECULAR
                // =================================================

                float3 viewDirection =
                    normalize(
                        input.viewDirection
                    );


                float3 halfVector =
                    normalize(
                        lightDirection +
                        viewDirection
                    );


                float specularDot =
                    saturate(
                        dot(
                            normal,
                            halfVector
                        )
                    );


                float specularPower =
                    lerp(
                        8.0f,
                        64.0f,
                        _Smoothness
                    );


                float specular =
                    pow(
                        specularDot,
                        specularPower
                    );


                // =================================================
                // LIGHTING
                // =================================================

                float3 lighting =
                    ambient +
                    diffuse;


                lighting +=
                    specular *
                    _SpecularStrength;


                // =================================================
                // FINAL COLOR
                // =================================================

                float3 finalColor =
                    _Color.rgb *
                    lighting;


                finalColor *=
                    _Brightness;


                return float4(
                    finalColor,
                    _Color.a
                );
            }


            ENDHLSL
        }
    }
}