using UnityEngine;
using System.Collections;

[ExecuteInEditMode]
public class Lighting : MonoBehaviour {

    struct VPL
    {
        public Vector3 color;
        public Vector3 position;
    }

	public enum SplattingMode
	{
		CPU,
		COMPUTE,
		GPU
	};

	public SplattingMode splattingMode = SplattingMode.COMPUTE;

    public Shader lightingShader = null;
    public ComputeShader firstBounceSplattingShader = null;
    public int renderSize = 8;
    public float worldVolumeBoundary = 10.0f;
    public float firstBounceStrength = 1.0f;
	public float ambientMultiplyFactor = 1.0f;
	public Color ambientLightColor = Color.gray;
	public float attenuationFactor = 0.1f;
	public float distanceThreshold = 0.05f;
    
    private Material lightingMaterial = null;

    private Camera[] cameras = null;
    private Camera firstBounceCamera = null;
    
    private VPL[] firstVPLData = null;
    
    private ComputeBuffer firstVPLBuffer = null;

	public Color[] vplColorBuffer = null;
	public Color[] vplPositionBuffer = null;

	public Texture2D vplColorTexture = null;
	public Texture2D vplPositionTexture = null;
    
	// Use this for initialization
	void Awake () {

		RenderSettings.ambientLight = ambientLightColor;

		GetComponent<Camera> ().depthTextureMode = DepthTextureMode.Depth | DepthTextureMode.DepthNormals;

		if (lightingShader != null) {
			
			lightingMaterial = new Material (lightingShader);
			lightingMaterial.SetInt ("_RenderSize", renderSize);
			lightingMaterial.SetFloat ("_WorldVolumeBoundary", worldVolumeBoundary);
			lightingMaterial.SetFloat ("_FirstBounceStrength", firstBounceStrength);
			lightingMaterial.SetColor ("ambientLightColor", RenderSettings.ambientLight);
			lightingMaterial.SetFloat ("ambientMultiplyFactor", ambientMultiplyFactor);
			lightingMaterial.SetFloat ("attenuationFactor", attenuationFactor);
			lightingMaterial.SetFloat ("distanceThreshold", distanceThreshold);
			lightingMaterial.SetFloat ("stepX", 1.0f / renderSize);
			lightingMaterial.SetFloat ("stepY", 1.0f / renderSize);
		
		}

        cameras = Resources.FindObjectsOfTypeAll<Camera>();

        for(int i = 0; i < cameras.Length; ++i)
        {
            if(cameras[i].name.Equals("First Bounce Camera"))
            {
                firstBounceCamera = cameras[i];
                firstBounceCamera.GetComponent<FirstBounce>().Initialize();
            }
        }

		InitializeVPLCompute();
		InitializeVPLCPU();

	}
	
    // Function to initialize the virtual point lights
    void InitializeVPLCompute() {

        firstVPLData = new VPL[renderSize * renderSize];

        for(int i = 0; i < (renderSize * renderSize); ++i)
        {
            firstVPLData[i].color = Vector3.zero;
            firstVPLData[i].position = Vector3.zero;
        }

        firstVPLBuffer = new ComputeBuffer(firstVPLData.Length, 24);
        firstVPLBuffer.SetData(firstVPLData);

    }

	void InitializeVPLCPU() {

		vplColorTexture = new Texture2D (renderSize, renderSize, TextureFormat.RGB24, false);
		vplPositionTexture = new Texture2D (renderSize, renderSize, TextureFormat.RGB24, false);

	}

    // Function to generate the vpl data for the first bounce using the textures
    void GenerateFirstBounceVPL() {

        int kernel = firstBounceSplattingShader.FindKernel("SplattingMain");

        firstBounceSplattingShader.SetTexture(kernel, "_DirectLightingTexture", firstBounceCamera.GetComponent<FirstBounce>().directLightingTexture);
        firstBounceSplattingShader.SetTexture(kernel, "_PositionTexture", firstBounceCamera.GetComponent<FirstBounce>().positionTexture);
        firstBounceSplattingShader.SetBuffer(kernel, "_VPLBuffer", firstVPLBuffer);
        firstBounceSplattingShader.SetFloat("_WorldVolumeBoundary", worldVolumeBoundary);
        firstBounceSplattingShader.SetInt("_RenderSize", renderSize);

        firstBounceSplattingShader.Dispatch(kernel, renderSize, renderSize, 1);

    }

	private void GenerateVPLDataOnCPU() {

		RenderTexture.active = firstBounceCamera.GetComponent<FirstBounce> ().directLightingTexture;
		vplColorTexture.ReadPixels (new Rect (0, 0, renderSize, renderSize), 0, 0);
		vplColorTexture.Apply ();
		RenderTexture.active = null;

		RenderTexture.active = firstBounceCamera.GetComponent<FirstBounce> ().positionTexture;
		vplPositionTexture.ReadPixels (new Rect (0, 0, renderSize, renderSize), 0, 0);
		vplPositionTexture.Apply ();
		RenderTexture.active = null;

		vplColorBuffer = vplColorTexture.GetPixels ();
		vplPositionBuffer = vplPositionTexture.GetPixels ();

	}

	// Use this to add post-processing effects
	void OnRenderImage (RenderTexture source, RenderTexture destination) {

		firstBounceCamera.GetComponent<FirstBounce> ().RenderTextures ();

		lightingMaterial.SetMatrix( "InverseViewMatrix", GetComponent<Camera>().cameraToWorldMatrix);
		lightingMaterial.SetMatrix( "InverseProjectionMatrix", GetComponent<Camera>().projectionMatrix.inverse);

		if (splattingMode == SplattingMode.COMPUTE) {

			lightingMaterial.EnableKeyword ("COMPUTE");
			lightingMaterial.DisableKeyword ("CPU");
			lightingMaterial.DisableKeyword ("GPU");

			GenerateFirstBounceVPL ();

			lightingMaterial.SetBuffer ("_FirstVPLBuffer", firstVPLBuffer);

			Graphics.Blit (source, destination, lightingMaterial);

		} else if (splattingMode == SplattingMode.CPU) {

			lightingMaterial.EnableKeyword ("CPU");
			lightingMaterial.DisableKeyword ("COMPUTE");
			lightingMaterial.DisableKeyword ("GPU");

			GenerateVPLDataOnCPU ();

			lightingMaterial.SetColorArray ("vplColorBuffer", vplColorBuffer);
			lightingMaterial.SetColorArray ("vplPositionBuffer", vplPositionBuffer);

			Graphics.Blit (source, destination, lightingMaterial);

		} else {

			lightingMaterial.EnableKeyword ("GPU");
			lightingMaterial.DisableKeyword ("COMPUTE");
			lightingMaterial.DisableKeyword ("CPU");

			lightingMaterial.SetTexture ("directLightingTexture", firstBounceCamera.GetComponent<FirstBounce>().directLightingTexture);
			lightingMaterial.SetTexture ("positionTexture", firstBounceCamera.GetComponent<FirstBounce>().positionTexture);

			Graphics.Blit (source, destination, lightingMaterial);

		}
        
	}
}