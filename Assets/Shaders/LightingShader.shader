// Upgrade NOTE: replaced 'mul(UNITY_MATRIX_MVP,*)' with 'UnityObjectToClipPos(*)'

Shader "Hidden/LightingShader"
{
	Properties
	{
		_MainTex ("Texture", 2D) = "white" {}
	}

	CGINCLUDE

	#include "UnityCG.cginc"

	// Structure representing a virtual point light
	struct VPL
	{
		float3 color;
		float3 position;
	};

#ifdef COMPUTE
	uniform StructuredBuffer<VPL>	_FirstVPLBuffer;
#endif

#ifdef CPU
	uniform half4					vplColorBuffer[16];
	uniform half4					vplPositionBuffer[16];
#endif

#ifdef GPU
	uniform sampler2D				directLightingTexture;
	uniform sampler2D				positionTexture;
#endif

	uniform sampler2D				_CameraDepthTexture;
	uniform sampler2D				_CameraDepthNormalsTexture;
	uniform sampler2D				_MainTex;
	uniform sampler2D				_IndirectTexture;

	uniform half4x4					InverseProjectionMatrix;
	uniform half4x4					InverseViewMatrix;

	uniform float3					_CameraPosition;
	uniform half3					ambientLightColor;

	uniform half					_WorldVolumeBoundary;
	uniform half					_FirstBounceStrength;
	uniform half					ambientMultiplyFactor;
	uniform half					attenuationFactor;
	uniform half					distanceThreshold;
	uniform half					stepX;
	uniform half					stepY;
	uniform half					_RenderSize;

	// Structure representing input to the vertex shader
	struct appdata
	{
		float4 vertex : POSITION;
		half2 uv : TEXCOORD0;
	};

	// Structure representing input to the fragment shader
	struct v2f_indirect
	{
		half2 uv : TEXCOORD0;
		float4 vertex : SV_POSITION;
		half4 cameraRay : TEXCOORD1;
	};

	// Vertex shader for the lighting pass
	v2f_indirect vert_lighting(appdata v)
	{
		v2f_indirect o;
		o.vertex = UnityObjectToClipPos(v.vertex);
		o.uv = v.uv;

		//transform clip pos to view space
		half4 clipPos = half4( v.uv * 2.0 - 1.0, 1.0, 1.0);
		half4 cameraRay = mul(InverseProjectionMatrix, clipPos);
		o.cameraRay = cameraRay / cameraRay.w;

		return o;
	}

	inline float3 DecodePosition(float3 inputPosition) {

		float3 decodedPosition = inputPosition;
		decodedPosition *= (2.0 * _WorldVolumeBoundary);
		decodedPosition -= _WorldVolumeBoundary;
		return decodedPosition;

	}

	inline half GetLuminance(half3 pixelColor) {

		half luminance = ((pixelColor.r + pixelColor.g + pixelColor.b) * 0.33f);
		return luminance;

	}

	// Fragment shader for the lighting pass
	half4 frag_lighting(v2f_indirect i) : SV_Target
	{
		half3 accumulatedColor = half3(0.0, 0.0, 0.0);
		half3 firstBounceColor = half3(0.0, 0.0, 0.0);

		// PIXEL POSITION
		float depth = SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, i.uv);
		float lindepth = Linear01Depth (depth);
		float4 viewPos = float4(i.cameraRay.xyz * lindepth,1);
		float3 pixelPosition = mul(InverseViewMatrix, viewPos).xyz;

		// PIXEL COLOR
		half3 pixelColor = tex2D(_MainTex, i.uv);
		half3 amplifiedColor = pixelColor * ambientMultiplyFactor;

		// PIXEL NORMAL
		half depthValue;
		half3 viewSpaceNormal;
		DecodeDepthNormal(tex2D(_CameraDepthNormalsTexture, i.uv), depthValue, viewSpaceNormal);
		viewSpaceNormal = normalize(viewSpaceNormal);
		half3 pixelNormal = mul((half3x3)InverseViewMatrix, viewSpaceNormal);

		// Now, traverse through the vpl buffer and calculate lighting due to all the virtual point lights
		half numberOfVPL = (_RenderSize * _RenderSize);
		
		float3 lightPosition = float3(0.0, 0.0, 0.0);
		half3 lightColor = half3(0.0, 0.0, 0.0);

#ifdef GPU
		// Compute first bounce lighting
		for (half i1 = 0.0f; i1 < _RenderSize; i1 += 1.0f)
		{
			for (half j1 = 0.0f; j1 < _RenderSize; j1 += 1.0f) {

				lightPosition = DecodePosition(tex2D(positionTexture, half2((stepX * i1), (stepY * j1))));
				lightColor = tex2D(directLightingTexture, half2((stepX * i1), (stepY * j1)));

				half3 surfaceToLight = lightPosition - pixelPosition;
				half distanceSquared = dot(surfaceToLight, surfaceToLight);

				half mask = saturate(distanceSquared - distanceThreshold);
				
				half attenuationPointLight = 1.0f + (attenuationFactor * distanceSquared);
				surfaceToLight = normalize(surfaceToLight);

				half brightness = dot(pixelNormal, surfaceToLight) / attenuationPointLight;
				brightness = clamp(brightness, 0.0f, 1.0f);

				firstBounceColor += (mask * (brightness * (lightColor * amplifiedColor)));

			}

		}
#endif

#ifdef COMPUTE
		// Compute first bounce lighting
		for (half i1 = 0.0f; i1 < numberOfVPL; i1 += 1.0f)
		{

			lightPosition = _FirstVPLBuffer[i1].position;
			lightColor = _FirstVPLBuffer[i1].color;

			half3 surfaceToLight = lightPosition - pixelPosition;
			half distanceSquared = dot(surfaceToLight, surfaceToLight);

			half mask = saturate(distanceSquared - distanceThreshold);
			
			half attenuationPointLight = 1.0f + (attenuationFactor * distanceSquared);
			surfaceToLight = normalize(surfaceToLight);

			half brightness = dot(pixelNormal, surfaceToLight) / attenuationPointLight;
			brightness = clamp(brightness, 0, 1);

			firstBounceColor += (mask * (brightness * (lightColor * amplifiedColor)));

		}
#endif

#ifdef CPU
		// Compute first bounce lighting
		for (half i1 = 0.0f; i1 < numberOfVPL; i1 += 1.0f)
		{

			lightPosition = DecodePosition(vplPositionBuffer[i1].rgb);
			lightColor = vplColorBuffer[i1].rgb;

			half3 surfaceToLight = lightPosition - pixelPosition;
			half distanceSquared = dot(surfaceToLight, surfaceToLight);

			half mask = saturate(distanceSquared - distanceThreshold);
			
			half attenuationPointLight = 1.0f + (attenuationFactor * distanceSquared);
			surfaceToLight = normalize(surfaceToLight);

			half brightness = dot(pixelNormal, surfaceToLight) / attenuationPointLight;
			brightness = clamp(brightness, 0, 1);

			firstBounceColor += (mask * (brightness * (lightColor * amplifiedColor)));

		}
#endif

		accumulatedColor = (firstBounceColor * _FirstBounceStrength) / (float)(numberOfVPL);

		half3 finalColor = pixelColor + accumulatedColor;
		return half4(finalColor, 1.0);
	}

	ENDCG

	SubShader
	{
		// No culling or depth
		Cull Off ZWrite Off ZTest Always

		Pass
		{
			CGPROGRAM
			#pragma vertex vert_lighting
			#pragma fragment frag_lighting
			#pragma multi_compile COMPUTE CPU GPU
			#pragma target 5.0
			ENDCG
		}

	}
}