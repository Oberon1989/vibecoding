using UnityEngine;
using UnityEngine.InputSystem;

[RequireComponent(typeof(Rigidbody))]
public class SimplePlayerMovement : MonoBehaviour
{
    [Header("Movement")]
    [SerializeField] private float moveSpeed = 5f;
    [SerializeField] private float verticalSpeed = 10f;

    [Header("Camera")]
    [SerializeField] private float mouseSensitivity = 2f;
    [SerializeField] private Transform cameraTransform;

    [Header("Planet")]
    [SerializeField] private Transform planetCenter;
    [SerializeField] private float planetMass = 5.972e24f;
    [SerializeField] private float surfaceGravity = 9.81f;

    [Header("Player")]
    [SerializeField] private float playerMass = 80f;
    [SerializeField] private float rotationSpeed = 10f;

    [Header("Jump / Fly")]
    [SerializeField] private bool useFly = false;
    [SerializeField] private float jumpForce = 600f;

    [Header("Voxel Editing")]
    [SerializeField] private VoxelGpuHierarchy voxelHierarchy;
    [SerializeField] private VoxelGpuCollider voxelCollider;
    [SerializeField, Min(0.5f)] private float brushRadius = 2.0f;
    [SerializeField, Min(0.01f)] private float brushDensityStrength = 1.5f;
    [SerializeField, Min(0.05f)] private float brushInterval = 0.18f;
    [SerializeField, Min(1.0f)] private float editRayDistance = 1200.0f;

    private Rigidbody rb;

    private float cameraPitch;
    private bool jumpRequested;
    private float nextBrushTime;

    private void Awake()
    {
        rb = GetComponent<Rigidbody>();

        rb.mass = playerMass;
        rb.useGravity = false;

        rb.collisionDetectionMode =
            CollisionDetectionMode.ContinuousDynamic;

        rb.interpolation =
            RigidbodyInterpolation.Interpolate;

        rb.constraints =
            RigidbodyConstraints.FreezeRotation;

        ResolveVoxelEditingReferences();
    }

    private void Update()
    {
        Look();
        HandleVoxelEditing();

        if (!useFly &&
            Keyboard.current != null &&
            Keyboard.current.spaceKey.wasPressedThisFrame)
        {
            jumpRequested = true;
        }
    }

    private void ResolveVoxelEditingReferences()
    {
        if (cameraTransform == null)
            cameraTransform = Camera.main != null
                ? Camera.main.transform
                : null;

        if (voxelHierarchy == null)
        {
            VoxelPlanet planet = FindFirstObjectByType<VoxelPlanet>();
            if (planet != null)
                voxelHierarchy = planet.GpuHierarchy;

            if (voxelHierarchy == null)
                voxelHierarchy = FindFirstObjectByType<VoxelGpuHierarchy>();
        }

        if (voxelCollider == null && voxelHierarchy != null)
            voxelCollider = voxelHierarchy.GetComponent<VoxelGpuCollider>();

        if (voxelCollider == null)
            voxelCollider = FindFirstObjectByType<VoxelGpuCollider>();
    }

    private void HandleVoxelEditing()
    {
        if (Mouse.current == null)
            return;

        bool dig = Mouse.current.leftButton.isPressed;
        bool fill = Mouse.current.rightButton.isPressed;
        if (!dig && !fill)
            return;

        if (Time.unscaledTime < nextBrushTime)
            return;

        nextBrushTime =
            Time.unscaledTime + Mathf.Max(0.05f, brushInterval);

        if (voxelHierarchy == null || voxelCollider == null ||
            !voxelHierarchy.IsInitialized)
        {
            ResolveVoxelEditingReferences();
            if (voxelHierarchy == null || voxelCollider == null ||
                !voxelHierarchy.IsInitialized)
            {
                return;
            }
        }

        Camera editCamera = cameraTransform != null
            ? cameraTransform.GetComponent<Camera>()
            : null;
        if (editCamera == null)
            editCamera = Camera.main;
        if (editCamera == null)
            return;

        Ray ray = editCamera.ViewportPointToRay(
            new Vector3(0.5f, 0.5f, 0.0f)
        );

        if (!voxelCollider.RaycastSurface(
                ray,
                Mathf.Max(1.0f, editRayDistance),
                out RaycastHit hit))
        {
            return;
        }

        float densityDelta = dig
            ? brushDensityStrength
            : -brushDensityStrength;

        voxelHierarchy.AddDensityBrush(
            hit.point,
            Mathf.Max(0.5f, brushRadius),
            densityDelta
        );
    }

    private void FixedUpdate()
    {
        if (!useFly)
        {
            ApplyGravity();
        }

        AlignToPlanet();
        Move();

        if (!useFly)
        {
            Jump();
        }
    }

    private void ApplyGravity()
    {
        Vector3 gravityDirection =
            (
                planetCenter.position -
                rb.position
            ).normalized;

        rb.AddForce(
            gravityDirection *
            surfaceGravity,
            ForceMode.Acceleration
        );
    }

    private void AlignToPlanet()
    {
        Vector3 up =
            (
                rb.position -
                planetCenter.position
            ).normalized;

        Vector3 forward =
            Vector3.ProjectOnPlane(
                transform.forward,
                up
            );

        if (forward.sqrMagnitude < 0.001f)
        {
            forward =
                Vector3.ProjectOnPlane(
                    transform.right,
                    up
                );
        }

        forward.Normalize();

        Quaternion targetRotation =
            Quaternion.LookRotation(
                forward,
                up
            );

        Quaternion rotation =
            Quaternion.Slerp(
                rb.rotation,
                targetRotation,
                rotationSpeed *
                Time.fixedDeltaTime
            );

        rb.MoveRotation(
            rotation
        );
    }

    private void Move()
    {
        if (Keyboard.current == null)
            return;

        Vector3 up =
            (
                rb.position -
                planetCenter.position
            ).normalized;

        Vector3 forward =
            Vector3.ProjectOnPlane(
                transform.forward,
                up
            ).normalized;

        Vector3 right =
            Vector3.Cross(
                up,
                forward
            ).normalized;

        Vector2 input =
            new Vector2(
                GetAxis(
                    Key.D,
                    Key.A
                ),
                GetAxis(
                    Key.W,
                    Key.S
                )
            );

        Vector3 horizontalDirection =
            right * input.x +
            forward * input.y;

        if (horizontalDirection.sqrMagnitude > 1f)
        {
            horizontalDirection.Normalize();
        }

        Vector3 movement =
            horizontalDirection *
            moveSpeed;

        movement +=
            MoveVertical(
                up
            );

        rb.MovePosition(
            rb.position +
            movement *
            Time.fixedDeltaTime
        );
    }

    private Vector3 MoveVertical(
        Vector3 up)
    {
        if (!useFly)
            return Vector3.zero;

        float verticalInput = 0f;

        if (Keyboard.current.spaceKey.isPressed)
        {
            verticalInput += 1f;
        }

        if (Keyboard.current.leftCtrlKey.isPressed)
        {
            verticalInput -= 1f;
        }

        return up *
               verticalInput *
               verticalSpeed;
    }

    private void Jump()
    {
        if (!jumpRequested)
            return;

        jumpRequested = false;

        Vector3 up =
            (
                rb.position -
                planetCenter.position
            ).normalized;

        rb.AddForce(
            up *
            jumpForce,
            ForceMode.Impulse
        );
    }

    private float GetAxis(
        Key positive,
        Key negative)
    {
        float value = 0f;

        if (Keyboard.current[positive].isPressed)
        {
            value += 1f;
        }

        if (Keyboard.current[negative].isPressed)
        {
            value -= 1f;
        }

        return value;
    }

    private void Look()
    {
        if (Mouse.current == null)
            return;

        Vector2 mouseDelta =
            Mouse.current.delta.ReadValue();

        float mouseX =
            mouseDelta.x *
            mouseSensitivity *
            0.01f;

        float mouseY =
            mouseDelta.y *
            mouseSensitivity *
            0.01f;

        transform.Rotate(
            Vector3.up,
            mouseX,
            Space.Self
        );

        cameraPitch -= mouseY;

        cameraPitch =
            Mathf.Clamp(
                cameraPitch,
                -89f,
                89f
            );

        cameraTransform.localRotation =
            Quaternion.Euler(
                cameraPitch,
                0f,
                0f
            );
    }
}
