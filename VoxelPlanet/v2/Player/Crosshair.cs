using UnityEngine;

public class Crosshair : MonoBehaviour
{
    [SerializeField] private float size = 20f;
    [SerializeField] private float thickness = 2f;
    [SerializeField] private float gap = 4f;

    private void OnGUI()
    {
        float centerX = Screen.width * 0.5f;
        float centerY = Screen.height * 0.5f;

        GUI.Box(
            new Rect(
                centerX - thickness * 0.5f,
                centerY - size * 0.5f,
                thickness,
                size
            ),
            GUIContent.none
        );

        GUI.Box(
            new Rect(
                centerX - size * 0.5f,
                centerY - thickness * 0.5f,
                size,
                thickness
            ),
            GUIContent.none
        );
    }
}