//#define TEST_ARENA

using UnityEngine;
using System.Collections;

[ExecuteInEditMode]
//FPS class to calc FPS and show fps, total frame count and time till game start
//this class can be added to camera game object.
public class FPSCounter : MonoBehaviour
{
    // Use this for initialization
    string strFPS = "";
    float nextTime = 0;
    int frames = 0;
    
   	void Start()
    {
        strFPS = "FPS: " + frames.ToString();
        nextTime = Time.realtimeSinceStartup + 1;
        //Application.targetFrameRate = 500;
        Screen.SetResolution(1280, 720, true);
		Debug.Log (SystemInfo.supportsComputeShaders);
    }

    // Update is called once per frame
    void Update()
    {
        frames += 1;
        if (Time.realtimeSinceStartup >= nextTime)
        {
            strFPS = "FPS: " + frames.ToString();
            frames = 0;
            nextTime = Time.realtimeSinceStartup + 1;
        }
    }


    void OnGUI()
    {
        GUI.Label(new Rect(100, 10, 200, 50), strFPS);
    }

}
