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
        float halfGap = Mathf.Max(0f, gap) * 0.5f;
        float segmentLength = Mathf.Max(0f, size * 0.5f - halfGap);

        GUI.Box(
            new Rect(
                centerX - thickness * 0.5f,
                centerY - halfGap - segmentLength,
                thickness,
                segmentLength
            ),
            GUIContent.none
        );

        GUI.Box(
            new Rect(
                centerX - thickness * 0.5f,
                centerY + halfGap,
                thickness,
                segmentLength
            ),
            GUIContent.none
        );

        GUI.Box(
            new Rect(
                centerX - halfGap - segmentLength,
                centerY - thickness * 0.5f,
                segmentLength,
                thickness
            ),
            GUIContent.none
        );

        GUI.Box(
            new Rect(
                centerX + halfGap,
                centerY - thickness * 0.5f,
                segmentLength,
                thickness
            ),
            GUIContent.none
        );
    }
}
