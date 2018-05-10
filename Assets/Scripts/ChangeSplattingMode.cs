using System.Collections;
using System.Collections.Generic;
using UnityEngine;

public class ChangeSplattingMode : MonoBehaviour {
	
	public void ChangeMode () {

		Lighting.SplattingMode currentMode = Camera.main.GetComponent<Lighting> ().splattingMode;

		if (currentMode == Lighting.SplattingMode.COMPUTE) {
			Camera.main.GetComponent<Lighting> ().splattingMode = Lighting.SplattingMode.CPU;
			GameObject.Find ("SplattingModeText").GetComponent<UnityEngine.UI.Text> ().text = "Current Splatting = CPU";
		} else if (currentMode == Lighting.SplattingMode.CPU) {
			Camera.main.GetComponent<Lighting> ().splattingMode = Lighting.SplattingMode.GPU;
			GameObject.Find ("SplattingModeText").GetComponent<UnityEngine.UI.Text> ().text = "Current Splatting = GPU";
		} else {
			Camera.main.GetComponent<Lighting> ().splattingMode = Lighting.SplattingMode.COMPUTE;
			GameObject.Find ("SplattingModeText").GetComponent<UnityEngine.UI.Text> ().text = "Current Splatting = COMPUTE";
		}
	}

}
