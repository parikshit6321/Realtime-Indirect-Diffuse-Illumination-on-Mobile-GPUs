using UnityEngine;
using System.Collections;

[ExecuteInEditMode]
public class PositionWriting : MonoBehaviour {

   public Shader normalShader = null;

    public RenderTexture normalTexture = null;
    
    private float worldVolumeBoundary = 10.0f;

    private Light spotLight = null;
    private float spotLightIntensity = 1.0f;

	// Function to initialize position writing
	public void Initialize () {

		worldVolumeBoundary = GameObject.Find("FirstPersonCharacter").GetComponent<Lighting>().worldVolumeBoundary;

		normalTexture = new RenderTexture(Screen.width, Screen.height, 16, RenderTextureFormat.ARGB32);

        spotLight = GameObject.Find("Spotlight").GetComponent<Light>();
        spotLightIntensity = spotLight.intensity;
	}
	
    // Function to deallocate the dynamically allocated resources
    void OnDestroy() {

        normalTexture.Release();

    }

	// Function to render the position texture
	public void RenderTextures () {

        spotLightIntensity = spotLight.intensity;

        GetComponent<Camera>().targetTexture = normalTexture;
        GetComponent<Camera>().RenderWithShader(normalShader, null);

    }
}
