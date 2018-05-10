using UnityEngine;
using System.Collections;

[ExecuteInEditMode]
public class PrototypeSSR : MonoBehaviour {

    [Header("Prototype SSR Shader")]
    public Shader shader = null;
    
    public enum ReflectionModel
    {
        NORMAL,
        PROTOTYPE
    }

    [Header("Reflection Computation Model")]
    public ReflectionModel reflectionModel = ReflectionModel.PROTOTYPE;

    [Header("Normal SSR Settings")]
    [Tooltip("Downsampling for the reflections texture")]
    public int downsample = 1;
    
    [Tooltip("Thickness for positive ray hits")]
    public float zBiasNormal = 0.1f;

    [Tooltip("Distance the ray travels in each iteration")]
    public float rayTraceStepNormal = 10.0f;

    [Tooltip("Maximum number of iterations to consider for reflection calculations")]
    public int maximumIterationsNormal = 32;

    public enum NumberOfSamples
    {
        LOW,    // 1 sample
        MEDIUM, // 7 samples
        HIGH    // 13 samples
    }

    [Header("Prototype SSR Settings")]
    
    [Tooltip("Controls the number of samples taken from the cone distribution")]
    public NumberOfSamples numberOfSamples = NumberOfSamples.MEDIUM;

    [Tooltip("Downsampling for the length calculation texture")]
    public int lengthDownsample = 1;

    [Tooltip("Downsampling for the reflection calculation texture")]
    public int reflectionsDownsample = 1;
    
    [Tooltip("Fix to remove colors at no hit positions")]
    public float rayLengthCutOff = 0.05f;

    [Tooltip("Offset for sampling pixels along cone's axis")]
    public float coneLengthOffset = 0.1f;

    [Tooltip("Angle of the cone distribution used for sampling")]
    public float coneAngle = 20.0f;
    
    [Tooltip("Factor by which the ray step decreases when a hit is about to be found")]
    public float multiplicativeDecreaseFactor = 0.5f;

    [Tooltip("Factor by which the ray step increases when no hit is about to be found")]
    public float multiplicativeIncreaseFactor = 1.0f;

    [Tooltip("Thickness for positive ray hits")]
    public float zBias = 0.1f;

    [Tooltip("Distance the ray travels in each iteration")]
    public float rayTraceStep = 10.0f;

    [Tooltip("Maximum number of iterations to consider for reflection calculations")]
    public int maximumIterations = 32;

    [Tooltip("Number of blur iterations for length texture")]
    public int lengthBlurIterations = 0;

    [Tooltip("Step of blur for length texture")]
    public float lengthBlurStep = 1.0f;

    [Tooltip("Threshold value for removing edge artifacts in downsampled length texture")]
    public float lengthBlurThreshold = 0.1f;

    [Tooltip("How far to sample for edge filtering")]
    public float filterStep = 1.0f;

    [Tooltip("Minimum color intensity for filtering")]
    public float filterThreshold = 0.1f;

    [Tooltip("Minimum intensity for far away reflections")]
    public float minimumReflectionIntensity = 0.2f;
    
    [Header("General Settings")]

    [Tooltip("Controls the spread of the blur effect")]
    public float blurStep = 1.0f;

    [Tooltip("Number of blur passes")]
    public int blurIterations = 2;

    [Tooltip("Depth till which reflections are calculated")]
    public float depthCutOff = 50.0f;
    
    [Tooltip("Strength of the reflections")]
    public float reflectionStrength = 0.3f;

    [Tooltip("The resolution at which the final image is to be rendered")]
    public Vector2 targetResolution;
    
    private Material material = null;
    
    private int iter = 0;
    private Matrix4x4 inverseProjectionMatrix;

	// Use this for initialization
	void Awake () {

        targetResolution.Set(1920, 1080);

        GetComponent<Camera>().depthTextureMode = DepthTextureMode.Depth | DepthTextureMode.DepthNormals;

        if (shader != null)
            material = new Material(shader);

        Screen.SetResolution((int)targetResolution.x, (int)targetResolution.y, false);
        
	}
    
    // Use this to add image effects
    void OnRenderImage (RenderTexture source, RenderTexture destination) {

        if(reflectionModel == ReflectionModel.PROTOTYPE)
        {
            // Get the relevant render textures for length calculation, reflection calculation and blurring
            RenderTexture lengthTexture = RenderTexture.GetTemporary(source.width / lengthDownsample, source.height / lengthDownsample, 0, RenderTextureFormat.RFloat);
            RenderTexture tempLength = RenderTexture.GetTemporary(source.width / lengthDownsample, source.height / lengthDownsample, 0, RenderTextureFormat.RFloat);
            RenderTexture reflectionsTexture = RenderTexture.GetTemporary(source.width / reflectionsDownsample, source.height / reflectionsDownsample);
            RenderTexture reflectionsTextureFiltered = RenderTexture.GetTemporary(source.width / reflectionsDownsample, source.height / reflectionsDownsample);
            RenderTexture temp = RenderTexture.GetTemporary(source.width / reflectionsDownsample, source.height / reflectionsDownsample);
            
            // Set shader quality to low
            if (numberOfSamples == NumberOfSamples.LOW)
            {
                material.EnableKeyword("LOW_SAMPLES");
                material.DisableKeyword("MEDIUM_SAMPLES");
                material.DisableKeyword("HIGH_SAMPLES");
            }
            // Set shader quality to medium
            else if (numberOfSamples == NumberOfSamples.MEDIUM)
            {
                material.DisableKeyword("LOW_SAMPLES");
                material.EnableKeyword("MEDIUM_SAMPLES");
                material.DisableKeyword("HIGH_SAMPLES");
            }
            // Set shader quality to high
            else
            {
                material.DisableKeyword("LOW_SAMPLES");
                material.DisableKeyword("MEDIUM_SAMPLES");
                material.EnableKeyword("HIGH_SAMPLES");
            }
            
            // Get the camera's current projection matrix
            Matrix4x4 P = this.GetComponent<Camera>().projectionMatrix;

            bool d3d = SystemInfo.graphicsDeviceVersion.IndexOf("Direct3D") > -1;

            if (d3d)
            {
                // Scale and bias from OpenGL -> D3D depth range
                for (int i = 0; i < 4; i++)
                {
                    P[2, i] = P[2, i] * 0.5f + P[3, i] * 0.5f;
                }
            }

            Vector4 projInfo = new Vector4
                ((-2.0f / (Screen.width * this.GetComponent<Camera>().rect.width * P[0])),
                    (-2.0f / (Screen.height * this.GetComponent<Camera>().rect.height * P[5])),
                    ((1.0f - P[2]) / P[0]),
                    ((1.0f + P[6]) / P[5]));

            // Pass all the shader properties relevant to the fake reflections model
            material.SetVector("_ProjectionInfo", projInfo);
            material.SetMatrix("_ProjectionMatrix", P);

            inverseProjectionMatrix = P.inverse;
            material.SetMatrix("_InverseProjectionMatrix", inverseProjectionMatrix);

            // Pass the appropriate shader properties for the realistic reflections model
            material.SetFloat("_ZBias", zBias);
            material.SetFloat("_RayTraceStep", rayTraceStep);
            material.SetFloat("_ReflectionStrength", reflectionStrength);
            material.SetFloat("_RayLengthCutOff", rayLengthCutOff);
            material.SetFloat("_ConeAngle", coneAngle / 90.0f);
            material.SetFloat("_ConeLengthOffset", coneLengthOffset);
            material.SetFloat("_MultiplicativeDecreaseFactor", multiplicativeDecreaseFactor);
            material.SetFloat("_MultiplicativeIncreaseFactor", multiplicativeIncreaseFactor);
            material.SetFloat("_BlurStep", blurStep);
            material.SetFloat("_FilterStep", filterStep);
            material.SetFloat("_FilterThreshold", filterThreshold);
            material.SetFloat("_LengthBlurStep", lengthBlurStep);
            material.SetFloat("_DepthCutOff", depthCutOff);
            material.SetFloat("_LengthBlurThreshold", lengthBlurThreshold);
            material.SetFloat("_MinimumReflectionIntensity", minimumReflectionIntensity);
            material.SetInt("_MaxIter", maximumIterations);

            Graphics.Blit(source, lengthTexture, material, 2);

            // Blur the length texture horizontally and vertically
            for (iter = 0; iter < lengthBlurIterations; ++iter)
            {
                Graphics.Blit(lengthTexture, tempLength, material, 6);
                Graphics.Blit(tempLength, lengthTexture, material, 7);
            }

            // Render the reflections using the length texture
            material.SetTexture("_LengthTexture", lengthTexture);
            Graphics.Blit(source, reflectionsTexture, material, 3);

            // Apply edge filter
            Graphics.Blit(reflectionsTexture, reflectionsTextureFiltered, material, 8);

            // Blur the reflections texture horizontally and vertically
            for (iter = 0; iter < blurIterations; ++iter)
            {
                Graphics.Blit(reflectionsTextureFiltered, temp, material, 0);
                Graphics.Blit(temp, reflectionsTextureFiltered, material, 1);
            }

            // Pass the calculated reflections to the blending pass
            material.SetTexture("_SSRTexture", reflectionsTextureFiltered);

            // Blend the two textures
            Graphics.Blit(source, destination, material, 4);

            // Release the render textures
            RenderTexture.ReleaseTemporary(lengthTexture);
            RenderTexture.ReleaseTemporary(tempLength);
            RenderTexture.ReleaseTemporary(reflectionsTexture);
            RenderTexture.ReleaseTemporary(reflectionsTextureFiltered);
            RenderTexture.ReleaseTemporary(temp);
        }
        else
        {
            // Get the relevant render textures for reflection calculations and blurring
            RenderTexture reflectionsTex = RenderTexture.GetTemporary(source.width / downsample, source.height / downsample);
            RenderTexture blurredTex = RenderTexture.GetTemporary(source.width / downsample, source.height / downsample);

            // Get the camera's current projection matrix
            Matrix4x4 P = this.GetComponent<Camera>().projectionMatrix;

            bool d3d = SystemInfo.graphicsDeviceVersion.IndexOf("Direct3D") > -1;

            if (d3d)
            {
                // Scale and bias from OpenGL -> D3D depth range
                for (int i = 0; i < 4; i++)
                {
                    P[2, i] = P[2, i] * 0.5f + P[3, i] * 0.5f;
                }
            }

            Vector4 projInfo = new Vector4
                ((-2.0f / (Screen.width * this.GetComponent<Camera>().rect.width * P[0])),
                    (-2.0f / (Screen.height * this.GetComponent<Camera>().rect.height * P[5])),
                    ((1.0f - P[2]) / P[0]),
                    ((1.0f + P[6]) / P[5]));

            // Pass all the shader properties relevant to the fake reflections model
            material.SetVector("_ProjectionInfo", projInfo);
            material.SetMatrix("_ProjectionMatrix", P);

            inverseProjectionMatrix = P.inverse;
            material.SetMatrix("_InverseProjectionMatrix", inverseProjectionMatrix);

            // Pass the appropriate shader properties for the realistic reflections model
            material.SetFloat("_ZBias", zBiasNormal);
            material.SetFloat("_RayTraceStep", rayTraceStepNormal);
            material.SetFloat("_ReflectionStrength", reflectionStrength);
            material.SetFloat("_BlurStep", blurStep);
            material.SetFloat("_DepthCutOff", depthCutOff);
            material.SetInt("_MaxIter", maximumIterationsNormal);

            // Render the reflections using normal SSR Algorithm
            Graphics.Blit(source, reflectionsTex, material, 5);

            // Blur the reflections texture horizontally and vertically
            for (iter = 0; iter < blurIterations; ++iter)
            {
                Graphics.Blit(reflectionsTex, blurredTex, material, 0);
                Graphics.Blit(blurredTex, reflectionsTex, material, 1);
            }

            // Pass the calculated reflections into the blending pass
            material.SetTexture("_SSRTexture", reflectionsTex);

            // Blend the two textures
            Graphics.Blit(source, destination, material, 4);

            // Release the render textures
            RenderTexture.ReleaseTemporary(reflectionsTex);
            RenderTexture.ReleaseTemporary(blurredTex);
        }
	}
}