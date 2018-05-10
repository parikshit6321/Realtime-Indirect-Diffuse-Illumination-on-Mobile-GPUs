using System.Collections;
using System.Collections.Generic;
using UnityEngine;

public class AngleChanger : MonoBehaviour {

	public float speed = 10.0f;
	public float switchTimer = 5.0f;

	private float factor = 1.0f;
	private float angle = 0.0f;
	private Vector3 tempEulerAngles = Vector3.zero;

	void Start () {

		tempEulerAngles = transform.eulerAngles;
		InvokeRepeating ("ChangeFactorSign", switchTimer, 2.0f * switchTimer);

	}

	void ChangeFactorSign() {
		
		factor *= -1.0f;
	
	}

	// Update is called once per frame
	void Update () {

		angle += (Time.deltaTime * speed * factor);
		tempEulerAngles.y = angle;
		transform.eulerAngles = tempEulerAngles;

	}
}
