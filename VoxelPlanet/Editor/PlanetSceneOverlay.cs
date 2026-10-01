using UnityEditor;
using UnityEditor.Overlays;
using UnityEngine;
using UnityEngine.UIElements;

namespace VoxelPlanet.Planet.Editor
{
    [Overlay(
        typeof(SceneView),
        "Planet",
        true
    )]
    public class PlanetSceneOverlay : Overlay
    {
       

        public override VisualElement CreatePanelContent()
        {
            VisualElement root =
                new VisualElement();

            root.style.paddingLeft = 8;
            root.style.paddingRight = 8;
            root.style.paddingTop = 8;
            root.style.paddingBottom = 8;

            Label title =
                new Label("Planet");

            title.style.unityFontStyleAndWeight =
                FontStyle.Bold;

            root.Add(title);

            Toggle largeNoise =
                new Toggle("Large Noise");

            Toggle smallNoise =
                new Toggle("Small Noise");

            Button regenerate =
                new Button();

            regenerate.text =
                "Regenerate";

            root.Add(largeNoise);
            root.Add(smallNoise);

            root.Add(
                new VisualElement()
                {
                    style =
                    {
                        height = 6
                    }
                }
            );

            root.Add(regenerate);

            root.RegisterCallback<AttachToPanelEvent>(
                _ =>
                {
                    

                    
                }
            );

            largeNoise.RegisterValueChangedCallback(
                evt =>
                {
                   

                   
                }
            );

            smallNoise.RegisterValueChangedCallback(
                evt =>
                {
                    

                   
                }
            );

            regenerate.clicked +=
                () =>
                {
                  

                  

                    if (!Application.isPlaying)
                    {
                        UnityEngine.Debug.LogWarning(
                            "[PlanetOverlay] Enter Play Mode to regenerate."
                        );

                        return;
                    }

                    

                    UnityEngine.Debug.Log(
                        "[PlanetOverlay] Planet regenerated."
                    );
                };

            return root;
        }

      
    }
}