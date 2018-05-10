// Upgrade NOTE: replaced '_Object2World' with 'unity_ObjectToWorld'
// Upgrade NOTE: replaced 'mul(UNITY_MATRIX_MVP,*)' with 'UnityObjectToClipPos(*)'

Shader "Hidden/NormalShader"
{
	Properties
	{
	}
	SubShader
	{
		// World normal writing pass
		Pass
		{
			CGPROGRAM

			#pragma vertex vert
			#pragma fragment frag
			#pragma target 5.0

			#include "UnityCG.cginc"

			// Structure representing the input to the vertex shader
			struct appdata
			{
				float4 vertex : POSITION;
				float3 normal : NORMAL;
			};

			// Structure representing the input to the fragment shader
			struct v2f
			{
				float4 vertex : SV_POSITION;
				float3 worldNormal : NORMAL;
			};

			// Vertex shader for the world normal writing pass
			v2f vert(appdata v)
			{
				v2f o;
				o.vertex = UnityObjectToClipPos(v.vertex);
				o.worldNormal = mul(unity_ObjectToWorld, v.normal);
				return o;
			}

			// Fragment shader for the world normal writing pass
			float4 frag(v2f i) : SV_Target
			{
				float3 normal = (i.worldNormal * 0.5) + 0.5;
				return float4(normal, 1.0);
			}

			ENDCG
		}
	}
}