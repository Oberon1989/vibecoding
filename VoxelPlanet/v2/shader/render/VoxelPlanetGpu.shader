Shader "VoxelPlanet/VoxelPlanetGpu"
{
    Properties
    {
        _BaseColor ("Front Color", Color) = (1, 1, 1, 1)
        _BackColor ("Back Color", Color) = (1, 0, 0, 1)
        _NoiseColor ("Procedural Variation Color", Color) = (0.16, 0.28, 0.36, 1)
        _NoiseFrequency ("Procedural Noise Frequency", Float) = 0.002
        _NoiseStrength ("Procedural Noise Strength", Range(0, 1)) = 0.75
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

            // Render both sides so we can identify back faces.
            Cull Off

            HLSLPROGRAM

            #pragma target 4.5
            #pragma vertex Vert
            #pragma fragment Frag

            #include "UnityCG.cginc"

            #define UNITY_INDIRECT_DRAW_ARGS IndirectDrawArgs
            #include "UnityIndirect.cginc"

            StructuredBuffer<float3> _VertexBuffer;
            StructuredBuffer<uint> _IndexBuffer;

            float4 _BaseColor;
            float4 _BackColor;
            float4 _NoiseColor;
            float3 _PlanetCenter;
            float3 _LightDirection;
            float4 _LightColor;
            float4 _AmbientColor;
            float _NoiseFrequency;
            float _NoiseStrength;

            StructuredBuffer<float3> _NormalBuffer;

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float3 planetPosition : TEXCOORD0;
                float3 normalWS : TEXCOORD1;
            };

            float Hash3(float3 p)
            {
                p = frac(p * 0.1031);
                p += dot(p, p.zyx + 31.32);
                return frac((p.x + p.y) * p.z);
            }

            float ValueNoise3D(float3 p)
            {
                float3 cell = floor(p);
                float3 blend = frac(p);
                blend = blend * blend * (3.0 - 2.0 * blend);

                float n000 = Hash3(cell + float3(0, 0, 0));
                float n100 = Hash3(cell + float3(1, 0, 0));
                float n010 = Hash3(cell + float3(0, 1, 0));
                float n110 = Hash3(cell + float3(1, 1, 0));
                float n001 = Hash3(cell + float3(0, 0, 1));
                float n101 = Hash3(cell + float3(1, 0, 1));
                float n011 = Hash3(cell + float3(0, 1, 1));
                float n111 = Hash3(cell + float3(1, 1, 1));

                float n00 = lerp(n000, n100, blend.x);
                float n10 = lerp(n010, n110, blend.x);
                float n01 = lerp(n001, n101, blend.x);
                float n11 = lerp(n011, n111, blend.x);
                return lerp(lerp(n00, n10, blend.y),
                            lerp(n01, n11, blend.y), blend.z);
            }

            float FractalNoise3D(float3 p)
            {
                float broad = ValueNoise3D(p);
                float medium = ValueNoise3D(
                    p * 2.0 + float3(17.1, 9.2, 3.7)
                );
                float fine = ValueNoise3D(
                    p * 4.0 + float3(5.3, 21.7, 13.4)
                );

                return broad * 0.56 + medium * 0.29 + fine * 0.15;
            }

            Varyings Vert(
                uint svVertexID : SV_VertexID,
                uint svInstanceID : SV_InstanceID
            )
            {
                InitIndirectDrawArgs(0);

                Varyings output;

                uint drawIndex =
                    GetIndirectVertexID(
                        svVertexID
                    );

                uint vertexIndex =
                    _IndexBuffer[
                        drawIndex
                    ];

                float3 positionWS =
                    _VertexBuffer[
                        vertexIndex
                    ];

                output.planetPosition = positionWS - _PlanetCenter;
                output.normalWS = _NormalBuffer[vertexIndex];

                output.positionCS =
                    mul(
                        UNITY_MATRIX_VP,
                        float4(
                            positionWS,
                            1.0
                        )
                    );

                return output;
            }

            float4 Frag(
                Varyings input,
                bool isFrontFace : SV_IsFrontFace
            ) : SV_Target
            {
                if (!isFrontFace)
                {
                    return _BackColor;
                }

                float noise = FractalNoise3D(
                    input.planetPosition * _NoiseFrequency
                );
                float region = smoothstep(0.39, 0.61, noise);
                float3 patternedColor = lerp(
                    _BaseColor.rgb * 0.22,
                    _NoiseColor.rgb,
                    region
                );
                float3 albedo = lerp(
                    _BaseColor.rgb,
                    patternedColor,
                    saturate(_NoiseStrength)
                );

                float3 normal = normalize(input.normalWS);
                float diffuse = saturate(
                    dot(normal, normalize(_LightDirection))
                );
                float3 lighting =
                    0.16 +
                    _AmbientColor.rgb * 0.45 +
                    _LightColor.rgb * (0.12 + 0.88 * diffuse);
                float3 finalColor = albedo * lighting;

                return float4(finalColor, _BaseColor.a);
            }

            ENDHLSL
        }
    }
}
