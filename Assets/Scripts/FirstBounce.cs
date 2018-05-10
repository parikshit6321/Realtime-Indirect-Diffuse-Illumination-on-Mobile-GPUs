using UnityEngine;
using System.Collections;

[ExecuteInEditMode]
public class FirstBounce : MonoBehaviour
{

    public Shader positionShader = null;
    
    public RenderTexture directLightingTexture = null;
    public RenderTexture positionTexture = null;
  
    private int renderSize = 8;
    private float worldVolumeBoundary = 10.0f;

    private Light spotLight = null;
	private Color ambientLightOriginal = Color.gray;

    // Function used for initializing the reflective shadow map camera
    public void Initialize()
    {

		renderSize = GameObject.Find("FirstPersonCharacter").GetComponent<Lighting>().renderSize;
		worldVolumeBoundary = GameObject.Find("FirstPersonCharacter").GetComponent<Lighting>().worldVolumeBoundary;

		directLightingTexture = new RenderTexture(renderSize, renderSize, 16, RenderTextureFormat.ARGB32);
		positionTexture = new RenderTexture(renderSize, renderSize, 16, RenderTextureFormat.ARGB32);
  
        spotLight = GameObject.Find("Spotlight").GetComponent<Light>();

        GetComponent<Camera>().farClipPlane = spotLight.range;
        GetComponent<Camera>().fieldOfView = spotLight.spotAngle / 2.0f;

		ambientLightOriginal = RenderSettings.ambientLight;

    }

    // Function used to release the dynamically allocated render textures
    void OnDestroy()
    {

        directLightingTexture.Release();
        positionTexture.Release();
  
    }

    // Function used for rendering the textures
    public void RenderTextures()
    {
		
		RenderSettings.ambientLight = Color.white;
		spotLight.enabled = false;
        GetComponent<Camera>().targetTexture = directLightingTexture;
        GetComponent<Camera>().Render();
		spotLight.enabled = true;
		RenderSettings.ambientLight = ambientLightOriginal;

        Shader.SetGlobalFloat("_WorldVolumeBoundary", worldVolumeBoundary);
        GetComponent<Camera>().targetTexture = positionTexture;
        GetComponent<Camera>().RenderWithShader(positionShader, null);

    }

}