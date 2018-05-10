using UnityEngine;
using System.Collections;

[ExecuteInEditMode]
public class SecondBounce : MonoBehaviour
{

    public Shader positionShader = null;
    public Shader normalShader = null;

    public RenderTexture directLightingTexture = null;
    public RenderTexture positionTexture = null;
    public RenderTexture normalTexture = null;
    
    private int renderSize = 8;
    private float worldVolumeBoundary = 10.0f;

    private Light spotLight = null;

    // Function used for initializing the reflective shadow map camera
    public void Initialize()
    {

        renderSize = GameObject.Find("Main Camera").GetComponent<Lighting>().renderSize;
        worldVolumeBoundary = GameObject.Find("Main Camera").GetComponent<Lighting>().worldVolumeBoundary;

        directLightingTexture = new RenderTexture(renderSize, renderSize, 16, RenderTextureFormat.ARGBFloat);
        positionTexture = new RenderTexture(renderSize, renderSize, 16, RenderTextureFormat.ARGBFloat);
        normalTexture = new RenderTexture(renderSize, renderSize, 16, RenderTextureFormat.ARGBFloat);

        spotLight = GameObject.Find("Spotlight").GetComponent<Light>();
        
    }

    // Function used to release the dynamically allocated render textures
    void OnDestroy()
    {

        directLightingTexture.Release();
        positionTexture.Release();
        normalTexture.Release();

    }

    // Function used for rendering the textures
    public void RenderTextures()
    {
        float intensity = spotLight.intensity;

        spotLight.intensity = 0.0f;
        RenderSettings.ambientIntensity = 1.0f;

        GetComponent<Camera>().targetTexture = directLightingTexture;
        GetComponent<Camera>().Render();

        spotLight.intensity = intensity;
        RenderSettings.ambientIntensity = 0.0f;

        Shader.SetGlobalFloat("_WorldVolumeBoundary", worldVolumeBoundary);
        GetComponent<Camera>().targetTexture = positionTexture;
        GetComponent<Camera>().RenderWithShader(positionShader, null);

        GetComponent<Camera>().targetTexture = normalTexture;
        GetComponent<Camera>().RenderWithShader(normalShader, null);

    }
    
}