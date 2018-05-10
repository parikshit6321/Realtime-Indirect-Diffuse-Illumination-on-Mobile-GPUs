using System.Collections;
using System.Collections.Generic;
using UnityEngine;

public class OscillatingInY : MonoBehaviour {

	public float speed = 10.0f;
	private float angle = 0.0f;
	private Vector3 tempPosition = Vector3.zero;

	void Start () {

		tempPosition = transform.position;

	}

	// Update is called once per frame
	void Update () {
		
		angle += Time.deltaTime * speed;
		tempPosition.y = 5.0f + (Mathf.Sin (angle) * 3.0f);
		transform.position = tempPosition;
	
	}
}
