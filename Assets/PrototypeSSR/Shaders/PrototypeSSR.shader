// Upgrade NOTE: commented out 'float4x4 _WorldToCamera', a built-in variable
// Upgrade NOTE: replaced 'mul(UNITY_MATRIX_MVP,*)' with 'UnityObjectToClipPos(*)'

Shader "Hidden/PrototypeSSR"
{
	Properties
	{
		_MainTex ("Texture", 2D) = "white" {}
	}

	CGINCLUDE

	#include "UnityCG.cginc"

	// Input textuers
	uniform sampler2D	_MainTex;
	uniform sampler2D	_LengthTexture;
	uniform sampler2D	_SSRTexture;
	uniform sampler2D	_CameraDepthTexture;
	uniform sampler2D	_CameraDepthNormalsTexture;
	
	// Input matrices
	uniform float4x4	_ProjectionMatrix;
	uniform float4x4	_InverseProjectionMatrix;
	// uniform float4x4	_WorldToCamera;
	
	// General input parameters
	uniform float		_ConeAngle;
	uniform float4		_MainTex_TexelSize;
	uniform float4		_CameraDepthTexture_TexelSize;
	uniform half		_BlurStep;
	uniform float		_DepthCutOff;

	// Input parameters for the prototype reflections model
	uniform float		_MultiplicativeDecreaseFactor;
	uniform float		_MultiplicativeIncreaseFactor;
	uniform float4		_ProjectionInfo;
	uniform float		_RayTraceStep;
	uniform float		_ZBias;
	uniform float		_ReflectionStrength;
	uniform float		_RayLengthCutOff;
	uniform float		_ConeLengthOffset;
	uniform float		_LengthBlurThreshold;
	uniform float		_LengthBlurStep;
	uniform float		_FilterStep;
	uniform float		_FilterThreshold;
	uniform float		_MinimumReflectionIntensity;
	uniform int			_MaxIter;

	struct appdata
	{
		float4 vertex : POSITION;
		float2 uv : TEXCOORD0;
	};

	struct v2f_SSR
	{
		float4 pos : SV_POSITION;
		float2 uv : TEXCOORD0;
	};

	struct v2f
	{
		float2 uv : TEXCOORD0;
		float4 vertex : SV_POSITION;
	};

	struct v2f_blur
	{
		float2 uv : TEXCOORD0;
		float4 vertex : SV_POSITION;
		half2 offset1 : TEXCOORD1;
		half2 offset2 : TEXCOORD2;
		half2 offset3 : TEXCOORD3;
	};

	struct v2f_edge_filter
	{
		float2 uv : TEXCOORD0;
		float4 vertex : SV_POSITION;
		half2 offset1 : TEXCOORD1;
		half2 offset2 : TEXCOORD2;
		half2 offset3 : TEXCOORD3;
		half2 offset4 : TEXCOORD4;
	};

	struct v2f_downsample
	{
		float2 uv : TEXCOORD0;
		float4 vertex : SV_POSITION;
		half2 offset1 : TEXCOORD1;
		half2 offset2 : TEXCOORD2;
		half2 offset3 : TEXCOORD3;
		half2 offset4 : TEXCOORD4;
	};

	// Reconstruct the camera-space position from the passed screen-space co-ordinates and linear depth
	inline float3 ReconstructCSPosition(float2 S, float linEyeZ)
	{
		return float3(((S.xy * _MainTex_TexelSize.zw) * _ProjectionInfo.xy + _ProjectionInfo.zw) * linEyeZ, linEyeZ);
	}

	// Convert the view-space position to normalized device co-ordinates
	inline float3 view2ndc(float3 viewVector)
	{
		float4 clipPos = mul(_ProjectionMatrix, float4(viewVector, 1.0));
		return clipPos.xyz / clipPos.w;
	}

	// Convert the view-space position to screen-space position
	inline float3 view2screen(float3 viewVector)
	{
		return float3(view2ndc(viewVector).xy * 0.5 + 0.5, viewVector.z);
	}

	// Vertex shader for horizontal blurring
	v2f_blur vert_horizontal_blur(appdata v)
	{
		half unitX = _MainTex_TexelSize.x * _BlurStep;

		v2f_blur o;

		o.vertex = UnityObjectToClipPos(v.vertex);

		o.uv = v.uv;

		o.offset1 = half2(o.uv.x - unitX, o.uv.y);
		o.offset2 = half2(o.uv.x, o.uv.y);
		o.offset3 = half2(o.uv.x + unitX, o.uv.y);

		return o;
	}

	// Vertex shader for vertical blurring
	v2f_blur vert_vertical_blur(appdata v)
	{
		half unitY = _MainTex_TexelSize.y * _BlurStep;

		v2f_blur o;

		o.vertex = UnityObjectToClipPos(v.vertex);

		o.uv = v.uv;

		o.offset1 = half2(o.uv.x, o.uv.y - unitY);
		o.offset2 = half2(o.uv.x, o.uv.y);
		o.offset3 = half2(o.uv.x, o.uv.y + unitY);

		return o;
	}

	// Vertex shader for horizontal length blurring
	v2f_blur vert_horizontal_length_blur(appdata v)
	{
		half unitX = _MainTex_TexelSize.x * _LengthBlurStep;

		v2f_blur o;

		o.vertex = UnityObjectToClipPos(v.vertex);

		o.uv = v.uv;

		o.offset1 = half2(o.uv.x - unitX, o.uv.y);
		o.offset2 = half2(o.uv.x, o.uv.y);
		o.offset3 = half2(o.uv.x + unitX, o.uv.y);

		return o;
	}

	// Vertex shader for vertical length blurring
	v2f_blur vert_vertical_length_blur(appdata v)
	{
		half unitY = _MainTex_TexelSize.y * _LengthBlurStep;

		v2f_blur o;

		o.vertex = UnityObjectToClipPos(v.vertex);

		o.uv = v.uv;

		o.offset1 = half2(o.uv.x, o.uv.y - unitY);
		o.offset2 = half2(o.uv.x, o.uv.y);
		o.offset3 = half2(o.uv.x, o.uv.y + unitY);

		return o;
	}

	// Fragment shader for blurring the length texture - both horizontally as well as vertically
	float frag_length_blur(v2f_blur i) : SV_TARGET
	{
		float length;

		float length1 = tex2D(_MainTex, i.offset1);
		float length2 = tex2D(_MainTex, i.offset2);
		float length3 = tex2D(_MainTex, i.offset3);

		float difference12 = abs(length1 - length2);
		float difference13 = abs(length1 - length3);

		length = length1;

		if (difference12 < _LengthBlurThreshold)
			length += length2;
		else
			length += length1;

		if (difference13 < _LengthBlurThreshold)
			length += length3;
		else
			length += length1;

		length *= 0.33;

		return length;
	}

	// Fragment shader for blurring the reflection texture - both horizontally as well as vertically
	half4 frag_blur(v2f_blur i) : SV_TARGET
	{
		half4 col;

		col = tex2D(_MainTex, i.offset1);
		col += tex2D(_MainTex, i.offset2);
		col += tex2D(_MainTex, i.offset3);

		col *= 0.33;

		return col;
	}

	// Vertex shader for edge filtering
	v2f_edge_filter vert_edge_filter(appdata v)
	{
		half unitX = _MainTex_TexelSize.x * _FilterStep;
		half unitY = _MainTex_TexelSize.x * _FilterStep;

		v2f_edge_filter o;

		o.vertex = UnityObjectToClipPos(v.vertex);

		o.uv = v.uv;

		o.offset1 = half2(o.uv.x - unitX, o.uv.y + unitY);
		o.offset2 = half2(o.uv.x + unitX, o.uv.y + unitY);
		o.offset3 = half2(o.uv.x - unitX, o.uv.y - unitY);
		o.offset4 = half2(o.uv.x + unitX, o.uv.y - unitY);

		return o;
	}

	// Fragment shader for edge filtering
	half4 frag_edge_filter(v2f_edge_filter i) : SV_TARGET
	{
		half4 col = tex2D(_MainTex, i.uv);

		half4 col1 = tex2D(_MainTex, i.offset1);
		half4 col2 = tex2D(_MainTex, i.offset2);
		half4 col3 = tex2D(_MainTex, i.offset3);
		half4 col4 = tex2D(_MainTex, i.offset4);
		
		if (col1.r < _FilterThreshold && col1.g < _FilterThreshold && col1.b < _FilterThreshold)
			col = half4(0.0, 0.0, 0.0, 1.0);
		else if (col2.r < _FilterThreshold && col2.g < _FilterThreshold && col2.b < _FilterThreshold)
			col = half4(0.0, 0.0, 0.0, 1.0);
		else if (col3.r < _FilterThreshold && col3.g < _FilterThreshold && col3.b < _FilterThreshold)
			col = half4(0.0, 0.0, 0.0, 1.0);
		else if (col4.r < _FilterThreshold && col4.g < _FilterThreshold && col4.b < _FilterThreshold)
			col = half4(0.0, 0.0, 0.0, 1.0);

		return col;
	}

	// Vertex shader for length calculation in the realistic reflections model
	v2f vert_length(appdata v)
	{
		v2f o;
		o.vertex = UnityObjectToClipPos(v.vertex);
		o.uv = v.uv;
		return o;
	}

	// Get the sampled depth at the corresponding point on screen
	inline float sampleDepthD(float2 uv, float2 dx, float2 dy)
	{
		return UNITY_SAMPLE_DEPTH(tex2D(_CameraDepthTexture, uv, dx, dy));
	}

	// Function to calculate length of the reflected ray when it hits a point for an individual pixel
	inline float calculateLength(v2f i, float defaultLength, float3 viewNormal)
	{
		float viewLinearDepth = LinearEyeDepth(tex2D(_CameraDepthTexture, i.uv));

		// Don't calculate reflections for far away points
		if (viewLinearDepth > _DepthCutOff)
			return defaultLength;

		// Get the view-space normal and position vectors at the current sample
		float3 viewPosition = ReconstructCSPosition(i.uv, viewLinearDepth);
		float3 viewPositionNormalized = normalize(viewPosition);

		// Calculate the reflection direction at the current point
		float3 viewReflect = normalize(reflect(viewPositionNormalized, viewNormal));

		float3 viewReflectPosition = viewPosition + viewReflect;

		float3 screenReflectPosition = float3(view2screen(viewReflectPosition).xy, viewReflectPosition.z);
		float3 screenStartPos = float3(i.uv, viewLinearDepth);
		float3 screenReflectOnePixelDelta = screenReflectPosition - screenStartPos;

		screenReflectOnePixelDelta *= min(_CameraDepthTexture_TexelSize.x, _CameraDepthTexture_TexelSize.y) / length(screenReflectOnePixelDelta.xy);

		float2 dx, dy;
		dx = ddx(i.uv);
		dy = ddy(i.uv);

		// Distance the ray traverses each iteration in screen-space
		float3 screenReflectDelta = screenReflectOnePixelDelta * _RayTraceStep;

		float3 screenCurrentPosition = screenStartPos + screenReflectDelta;
		float3 screenPrevPosition = screenStartPos;

		int currSampleNum = 0;
		float currDist = 0.0;
		
		float delta;

		float backMul = 1.0;
		
		// Loop to march the ray in the reflected ray direction
		for(currSampleNum = 0; currSampleNum < _MaxIter; ++currSampleNum)
		{
			// Get the depths at current traced point and the sample point
			float currentTextureEyeDepth = LinearEyeDepth(sampleDepthD(screenCurrentPosition.xy, dx, dy));
			float currentTracedEyeDepth = screenCurrentPosition.z;

			// Calculate the difference between the two depths
			float delta = currentTracedEyeDepth - currentTextureEyeDepth;
			
			// If the ray is behind the current pixel
			if (delta > 0.0)
			{
				// If the ray is just behing the current pixel
				if (delta < _ZBias)
				{
					// Calculate the screen corrected position to get the sampling point
					float2 screenCorrectedPosition = screenPrevPosition.xy + (currentTextureEyeDepth - screenPrevPosition.z) * screenReflectDelta.xy;
					
					// Compute the view-space position for the end-point
					float3 finalPosition = ReconstructCSPosition(screenCorrectedPosition, currentTracedEyeDepth);
					
					// Get the vector from ray origin to ray end
					float3 differenceVector = finalPosition - viewPosition;
					
					// Calculate ray length
					float vectorLength = length(differenceVector);
					
					return vectorLength;
				}
				// If the ray is too far behind the pixel, decrease the linear step of the ray
				// This simulates binary searching by halving the linear step at every iteration
				else
				{
					backMul = _MultiplicativeDecreaseFactor;

					screenReflectDelta *= backMul;
	
					screenCurrentPosition = screenPrevPosition + screenReflectDelta;
				}
			}
			// The ray is currently infront of the pixel, keep on traversing
			else
			{
				screenPrevPosition = screenCurrentPosition;

				screenReflectDelta *= backMul;

				screenCurrentPosition += screenReflectDelta * _MultiplicativeIncreaseFactor;
			}
		}

		return 0.0;
	}

	// Fragment shader for length calculation pass in realistic reflection model
	float frag_length(v2f i) : SV_Target
	{
		float depth;
		float3 normal_spec;
		float4 depthNormal = tex2D(_CameraDepthNormalsTexture, i.uv);
		DecodeDepthNormal(depthNormal, depth, normal_spec);
		float length = calculateLength(i, 0.0, normal_spec);
		return length;
	}

	// Vertex shader for blending pass in realistic reflection model
	v2f vert_realistic_blend(appdata v)
	{
		v2f o;
		o.vertex = UnityObjectToClipPos(v.vertex);
		o.uv = v.uv;
		return o;
	}

	// Fragment shader for blending pass in realistic reflection model
	float4 frag_realistic_blend(v2f i) : SV_Target
	{
		float4 texColor = tex2D(_MainTex, i.uv);
		float3 ssrColor = tex2D(_SSRTexture, i.uv).rgb * _ReflectionStrength * texColor.a;
		float3 finalColor = texColor.rgb + ssrColor.rgb;
		return float4(finalColor, 1.0);
	}

	// Vertex shader for sampling pass of the realistic reflection model
	v2f_SSR vert_SSR(appdata v)
	{
		v2f_SSR o;
		o.pos = UnityObjectToClipPos(v.vertex);
		o.uv = v.uv;
		return o;
	}

	// Fragment shader for sampling pass of the realistic reflection model
	float4 frag_realistic_SSR(v2f_SSR i) : SV_Target
	{
		float4 finalColor = float4(0.0, 0.0, 0.0, 0.0);
		
		// Extract the reflected ray length at the current sample
		float rayLength = tex2D(_LengthTexture, i.uv);
		
		// Fix for points with no ray hit
		if (rayLength > _RayLengthCutOff)
		{
			// Get the depth at the current sample point
			float depth = LinearEyeDepth(tex2D(_CameraDepthTexture, i.uv));

			// Get the view-space normal at the current sample point
			float depthTemp;
			float3 viewNormal;
			float4 depthNormal = tex2D(_CameraDepthNormalsTexture, i.uv);
			DecodeDepthNormal(depthNormal, depthTemp, viewNormal);
			viewNormal = normalize(viewNormal);

			// Get the view-space position at the current sample point
			float3 viewPosition = ReconstructCSPosition(i.uv, depth);
			float3 viewPositionNormalized = normalize(viewPosition);

			// Get the view-space reflection direction at the current sample point
			float3 viewReflect = normalize(reflect(viewPositionNormalized, viewNormal));

			// Get the position of the current sample in view space
			float3 viewSamplePosition = viewPosition + (viewReflect * rayLength);
			float2 screenSamplePosition = view2screen(viewSamplePosition).xy;

#if defined(LOW_SAMPLES)

			finalColor = tex2D(_MainTex, screenSamplePosition);

#endif

#if defined(MEDIUM_SAMPLES)

			// Add the current sample color two times to give more weight to it
			// 1st cone sample
			finalColor = 2.0 * tex2D(_MainTex, screenSamplePosition);

			// Displacement vectors along which the sample points will be computed in a cone distribution
			float3 displacementVectors[4];
			displacementVectors[0] = normalize(cross(viewReflect, float3(0.0, 1.0, 0.0)));
			displacementVectors[1] = -displacementVectors[0];
			displacementVectors[2] = normalize(cross(viewReflect, displacementVectors[0]));
			displacementVectors[3] = -displacementVectors[2];

			// 2nd cone sample
			viewSamplePosition = viewPosition + ((viewReflect + (displacementVectors[0] * _ConeAngle)) * rayLength);
			screenSamplePosition = view2screen(viewSamplePosition).xy;

			finalColor.rgb += tex2D(_MainTex, screenSamplePosition).rgb;
			finalColor.a += 1.0;
			
			// 3rd cone sample
			viewSamplePosition = viewPosition + ((viewReflect + (displacementVectors[1] * _ConeAngle)) * rayLength);
			screenSamplePosition = view2screen(viewSamplePosition).xy;

			finalColor.rgb += tex2D(_MainTex, screenSamplePosition).rgb;
			finalColor.a += 1.0;
		
			// 4th cone sample
			viewSamplePosition = viewPosition + ((viewReflect + (displacementVectors[2] * _ConeAngle)) * rayLength);
			screenSamplePosition = view2screen(viewSamplePosition).xy;

			finalColor.rgb += tex2D(_MainTex, screenSamplePosition).rgb;
			finalColor.a += 1.0;

			// 5th cone sample
			viewSamplePosition = viewPosition + ((viewReflect + (displacementVectors[3] * _ConeAngle)) * rayLength);
			screenSamplePosition = view2screen(viewSamplePosition).xy;

			finalColor.rgb += tex2D(_MainTex, screenSamplePosition).rgb;
			finalColor.a += 1.0;

			// 6th cone sample
			viewSamplePosition = viewPosition + ((rayLength + _ConeLengthOffset) * viewReflect);
			screenSamplePosition = view2screen(viewSamplePosition).xy;

			finalColor.rgb += tex2D(_MainTex, screenSamplePosition).rgb;
			finalColor.a += 1.0;

			// 7th cone sample
			viewSamplePosition = viewPosition + ((rayLength - _ConeLengthOffset) * viewReflect);
			screenSamplePosition = view2screen(viewSamplePosition).xy;

			finalColor.rgb += tex2D(_MainTex, screenSamplePosition).rgb;
			finalColor.a += 1.0;

			// Average out the computed colors
			finalColor /= 8.0;

#endif

#if defined(HIGH_SAMPLES)

			// Add the current sample color two times to give more weight to it
			// 1st cone sample
			finalColor = 4.0 * tex2D(_MainTex, screenSamplePosition);

			// Displacement vectors along which the sample points will be computed in a cone distribution
			float3 displacementVectors[4];
			displacementVectors[0] = normalize(cross(viewReflect, float3(0.0, 1.0, 0.0)));
			displacementVectors[1] = -displacementVectors[0];
			displacementVectors[2] = normalize(cross(viewReflect, displacementVectors[0]));
			displacementVectors[3] = -displacementVectors[2];

			// 2nd cone sample
			viewSamplePosition = viewPosition + ((viewReflect + (displacementVectors[0] * _ConeAngle)) * rayLength);
			screenSamplePosition = view2screen(viewSamplePosition).xy;

			finalColor.rgb += 2.0 * tex2D(_MainTex, screenSamplePosition).rgb;
			finalColor.a += 1.0;

			// 3rd cone sample
			viewSamplePosition = viewPosition + ((viewReflect + (displacementVectors[1] * _ConeAngle)) * rayLength);
			screenSamplePosition = view2screen(viewSamplePosition).xy;

			finalColor.rgb += 2.0 * tex2D(_MainTex, screenSamplePosition).rgb;
			finalColor.a += 1.0;

			// 4th cone sample
			viewSamplePosition = viewPosition + ((viewReflect + (displacementVectors[2] * _ConeAngle)) * rayLength);
			screenSamplePosition = view2screen(viewSamplePosition).xy;

			finalColor.rgb += 2.0 * tex2D(_MainTex, screenSamplePosition).rgb;
			finalColor.a += 1.0;

			// 5th cone sample
			viewSamplePosition = viewPosition + ((viewReflect + (displacementVectors[3] * _ConeAngle)) * rayLength);
			screenSamplePosition = view2screen(viewSamplePosition).xy;

			finalColor.rgb += 2.0 * tex2D(_MainTex, screenSamplePosition).rgb;
			finalColor.a += 1.0;

			// 6th cone sample
			viewSamplePosition = viewPosition + (viewReflect * (rayLength + _ConeLengthOffset));
			screenSamplePosition = view2screen(viewSamplePosition).xy;

			finalColor.rgb += 2.0 * tex2D(_MainTex, screenSamplePosition).rgb;
			finalColor.a += 1.0;

			// 7th cone sample
			viewSamplePosition = viewPosition + (viewReflect * (rayLength - _ConeLengthOffset));
			screenSamplePosition = view2screen(viewSamplePosition).xy;

			finalColor.rgb += 2.0 * tex2D(_MainTex, screenSamplePosition).rgb;
			finalColor.a += 1.0;

			float offset = 2.0 * _ConeLengthOffset;
			float coneLengthOffset = _ConeLengthOffset + offset;

			// 8th cone sample
			viewSamplePosition = viewPosition + ((rayLength + offset) * (viewReflect + (displacementVectors[0] * _ConeAngle)));
			screenSamplePosition = view2screen(viewSamplePosition).xy;

			finalColor.rgb += tex2D(_MainTex, screenSamplePosition).rgb;
			finalColor.a += 1.0;

			// 9th cone sample
			viewSamplePosition = viewPosition + ((rayLength + offset) * (viewReflect + (displacementVectors[1] * _ConeAngle)));
			screenSamplePosition = view2screen(viewSamplePosition).xy;

			finalColor.rgb += tex2D(_MainTex, screenSamplePosition).rgb;
			finalColor.a += 1.0;

			// 10th cone sample
			viewSamplePosition = viewPosition + ((rayLength + offset) * (viewReflect + (displacementVectors[2] * _ConeAngle)));
			screenSamplePosition = view2screen(viewSamplePosition).xy;

			finalColor.rgb += tex2D(_MainTex, screenSamplePosition).rgb;
			finalColor.a += 1.0;

			// 11th cone sample
			viewSamplePosition = viewPosition + ((rayLength + offset) * (viewReflect + (displacementVectors[3] * _ConeAngle)));
			screenSamplePosition = view2screen(viewSamplePosition).xy;

			finalColor.rgb += tex2D(_MainTex, screenSamplePosition).rgb;
			finalColor.a += 1.0;

			// 12th cone sample
			viewSamplePosition = viewPosition + ((rayLength + coneLengthOffset) * viewReflect);
			screenSamplePosition = view2screen(viewSamplePosition).xy;

			finalColor.rgb += tex2D(_MainTex, screenSamplePosition).rgb;
			finalColor.a += 1.0;

			// 13th cone sample
			viewSamplePosition = viewPosition + ((rayLength - coneLengthOffset) * viewReflect);
			screenSamplePosition = view2screen(viewSamplePosition).xy;

			finalColor.rgb += tex2D(_MainTex, screenSamplePosition).rgb;
			finalColor.a += 1.0;

			// Average out the computed colors
			finalColor /= 22.0;

#endif

			// For glossy reflections
			finalColor *= max((1.0 - rayLength), _MinimumReflectionIntensity);

		}
		
		return finalColor;
	}

	// Function to calculate the Screen-space reflections
	inline float4 computeReflections(v2f_SSR i, float3 viewNormal)
	{
		float4 defaultColor = float4(0.0, 0.0, 0.0, 1.0);

		float viewLinearDepth = LinearEyeDepth(tex2D(_CameraDepthTexture, i.uv));

		// Don't calculate reflections for far away points
		if (viewLinearDepth > _DepthCutOff)
			return defaultColor;

		// Get the view-space normal and position vectors at the current sample
		float3 viewPosition = ReconstructCSPosition(i.uv, viewLinearDepth);
		float3 viewPositionNormalized = normalize(viewPosition);

		// Calculate the reflection direction at the current point
		float3 viewReflect = normalize(reflect(viewPositionNormalized, viewNormal));

		float3 viewReflectPosition = viewPosition + viewReflect;

		float3 screenReflectPosition = float3(view2screen(viewReflectPosition).xy, viewReflectPosition.z);
		float3 screenStartPos = float3(i.uv, viewLinearDepth);
		float3 screenReflectOnePixelDelta = screenReflectPosition - screenStartPos;

		screenReflectOnePixelDelta *= min(_CameraDepthTexture_TexelSize.x, _CameraDepthTexture_TexelSize.y) / length(screenReflectOnePixelDelta.xy);

		float2 dx, dy;
		dx = ddx(i.uv);
		dy = ddy(i.uv);

		// Distance the ray traverses each iteration in screen-space
		float3 screenReflectDelta = screenReflectOnePixelDelta * _RayTraceStep;

		float3 screenCurrentPosition = screenStartPos + screenReflectDelta;
		float3 screenPrevPosition = screenStartPos;

		int currSampleNum = 0;
		float currDist = 0.0;

		float delta;

		float backMul = 1.0;

		// Loop to march the ray in the reflected ray direction
		for (currSampleNum = 0; currSampleNum < _MaxIter; ++currSampleNum)
		{
			// Get the depths at current traced point and the sample point
			float currentTextureEyeDepth = LinearEyeDepth(sampleDepthD(screenCurrentPosition.xy, dx, dy));
			float currentTracedEyeDepth = screenCurrentPosition.z;

			// Calculate the difference between the two depths
			float delta = currentTracedEyeDepth - currentTextureEyeDepth;

			// If the ray is behind the current pixel
			if (delta > 0.0)
			{
				// If the ray is just behing the current pixel
				if (delta < _ZBias)
				{
					// Calculate the screen corrected position to get the sampling point
					float2 screenCorrectedPosition = screenPrevPosition.xy + (currentTextureEyeDepth - screenPrevPosition.z) * screenReflectDelta.xy;

					// Calculate reflected color from the corrected screen-space co-ordinates
					float4 reflected = tex2D(_MainTex, screenCorrectedPosition.xy, dx, dy);

					return reflected;
				}
				// If the ray is too far behind the pixel, decrease the linear step of the ray
				// This simulates binary searching by halving the linear step at every iteration
				else
				{
					backMul = 0.5;

					screenReflectDelta *= backMul;

					screenCurrentPosition = screenPrevPosition + screenReflectDelta;
				}
			}
			// The ray is currently infront of the pixel, keep on traversing
			else
			{
				screenPrevPosition = screenCurrentPosition;

				screenReflectDelta *= backMul;

				screenCurrentPosition += screenReflectDelta;
			}
		}

		return defaultColor;
	}

	// Fragment shader for the normal SSR Pass
	float4 frag_normal_SSR(v2f_SSR i) : SV_Target
	{
		float depth;
		float3 normal_spec;
		float4 depthNormal = tex2D(_CameraDepthNormalsTexture, i.uv);
		DecodeDepthNormal(depthNormal, depth, normal_spec);
		float4 ssrColor = computeReflections(i, normal_spec);
		return ssrColor;
	}

	ENDCG

	SubShader
	{
		// No culling or depth
		Cull Off ZWrite Off ZTest Always

		// 0 : Vertical Blur Pass
		Pass
		{
			CGPROGRAM

			#pragma fragmentoption ARB_precision_hint_fastest
			#pragma vertex vert_vertical_blur
			#pragma fragment frag_blur
			#pragma target 3.0

			ENDCG
		}

		// 1 : Horizontal Blur Pass
		Pass
		{
			CGPROGRAM

			#pragma fragmentoption ARB_precision_hint_fastest
			#pragma vertex vert_horizontal_blur
			#pragma fragment frag_blur
			#pragma target 3.0

			ENDCG
		}

		// 2 : Length Evaluation Pass
		Pass
		{
			CGPROGRAM

			#pragma fragmentoption ARB_precision_hint_fastest
			#pragma vertex vert_length
			#pragma fragment frag_length
			#pragma target 3.0

			ENDCG
		}

		// 3 : Realistic SSR Pass
		Pass
		{
			CGPROGRAM

			#pragma multi_compile LOW_SAMPLES MEDIUM_SAMPLES HIGH_SAMPLES
			#pragma fragmentoption ARB_precision_hint_fastest
			#pragma vertex vert_SSR
			#pragma fragment frag_realistic_SSR
			#pragma target 3.0

			ENDCG
		}

		// 4 : Realistic Blend Pass
		Pass
		{
			CGPROGRAM

			#pragma fragmentoption ARB_precision_hint_fastest
			#pragma vertex vert_realistic_blend
			#pragma fragment frag_realistic_blend
			#pragma target 3.0

			ENDCG
		}

		// 5 : Normal SSR Pass
		Pass
		{
			CGPROGRAM

			#pragma fragmentoption ARB_precision_hint_fastest
			#pragma vertex vert_SSR
			#pragma fragment frag_normal_SSR
			#pragma target 3.0

			ENDCG
		}

		// 6 : Vertical Length Blur Pass
		Pass
		{
			CGPROGRAM

			#pragma fragmentoption ARB_precision_hint_fastest
			#pragma vertex vert_vertical_length_blur
			#pragma fragment frag_length_blur
			#pragma target 3.0

			ENDCG
		}

		// 7 : Horizontal Length Blur Pass
		Pass
		{
			CGPROGRAM

			#pragma fragmentoption ARB_precision_hint_fastest
			#pragma vertex vert_horizontal_length_blur
			#pragma fragment frag_length_blur
			#pragma target 3.0

			ENDCG
		}

		// 8 : Edge Filtering Pass
		Pass
		{
			CGPROGRAM

			#pragma fragmentoption ARB_precision_hint_fastest
			#pragma vertex vert_edge_filter
			#pragma fragment frag_edge_filter
			#pragma target 3.0

			ENDCG
		}

	}
}