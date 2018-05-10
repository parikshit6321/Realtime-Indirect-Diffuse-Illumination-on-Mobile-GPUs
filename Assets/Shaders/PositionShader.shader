// Upgrade NOTE: replaced '_Object2World' with 'unity_ObjectToWorld'
// Upgrade NOTE: replaced 'mul(UNITY_MATRIX_MVP,*)' with 'UnityObjectToClipPos(*)'

Shader "Hidden/PositionShader"
{
	Properties
	{
	}
	SubShader
	{
		// World position writing pass
		Pass
		{
			CGPROGRAM
			#pragma vertex vert
			#pragma fragment frag

			#include "UnityCG.cginc"

			uniform int		_WorldVolumeBoundary;

			// Structure representing the input to the vertex shader
			struct appdata
			{
				float4 vertex : POSITION;
			};

			// Structure representing the input to the fragment shader
			struct v2f
			{
				float4 vertex : SV_POSITION;
				float4 worldPos : TEXCOORD1;
			};

			// Vertex shader for the world position writing pass
			v2f vert(appdata v)
			{
				v2f o;
				o.vertex = UnityObjectToClipPos(v.vertex);
				o.worldPos = mul(unity_ObjectToWorld, v.vertex);
				return o;
			}

			// Fragment shader for the world position writing pass
			float4 frag(v2f i) : SV_Target
			{
				float3 position = float3(i.worldPos.x + _WorldVolumeBoundary, i.worldPos.y + _WorldVolumeBoundary, i.worldPos.z + _WorldVolumeBoundary);
				position /= (2.0 * _WorldVolumeBoundary);
				return float4(position, 1.0);
			}

			ENDCG
		}
	}
}