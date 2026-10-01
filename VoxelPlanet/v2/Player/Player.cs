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
    [SerializeField] private VoxelPlanet planet;
    [SerializeField] private Transform planetCenterOverride;
    [SerializeField] private float surfaceGravity = 9.81f;

    [Header("Player")]
    [SerializeField] private float playerMass = 80f;
    [SerializeField] private float rotationSpeed = 10f;

    [Header("Jump / Fly")]
    [SerializeField] private bool useFly = false;
    [SerializeField] private float jumpForce = 600f;

    private Rigidbody rb;
    private float cameraPitch;
    private bool jumpRequested;

    private void Awake()
    {
        rb = GetComponent<Rigidbody>();
        rb.mass = playerMass;
        rb.useGravity = false;
        rb.collisionDetectionMode = CollisionDetectionMode.ContinuousDynamic;
        rb.interpolation = RigidbodyInterpolation.Interpolate;
        rb.constraints = RigidbodyConstraints.FreezeRotation;

        if (cameraTransform == null && Camera.main != null)
            cameraTransform = Camera.main.transform;

        if (planet == null)
            planet = FindFirstObjectByType<VoxelPlanet>();
    }

    private Vector3 PlanetCenter
    {
        get
        {
            if (planetCenterOverride != null)
                return planetCenterOverride.position;

            return planet != null ? planet.PlanetCenter : Vector3.zero;
        }
    }

    private void Update()
    {
        Look();

        if (!useFly && Keyboard.current != null &&
            Keyboard.current.spaceKey.wasPressedThisFrame)
        {
            jumpRequested = true;
        }
    }

    private void FixedUpdate()
    {
        if (!useFly)
            ApplyGravity();

        AlignToPlanet();
        Move();

        if (!useFly)
            Jump();
    }

    private void ApplyGravity()
    {
        Vector3 gravityDirection = (PlanetCenter - rb.position).normalized;
        rb.AddForce(gravityDirection * surfaceGravity, ForceMode.Acceleration);
    }

    private void AlignToPlanet()
    {
        Vector3 up = (rb.position - PlanetCenter).normalized;
        Vector3 forward = Vector3.ProjectOnPlane(transform.forward, up);

        if (forward.sqrMagnitude < 0.001f)
            forward = Vector3.ProjectOnPlane(transform.right, up);

        forward.Normalize();

        Quaternion target = Quaternion.LookRotation(forward, up);
        Quaternion rotation = Quaternion.Slerp(
            rb.rotation,
            target,
            rotationSpeed * Time.fixedDeltaTime);

        rb.MoveRotation(rotation);
    }

    private void Move()
    {
        if (Keyboard.current == null)
            return;

        Vector3 up = (rb.position - PlanetCenter).normalized;
        Vector3 forward = Vector3.ProjectOnPlane(transform.forward, up).normalized;
        Vector3 right = Vector3.Cross(up, forward).normalized;

        Vector2 input = new Vector2(
            GetAxis(Key.D, Key.A),
            GetAxis(Key.W, Key.S));

        Vector3 horizontal = right * input.x + forward * input.y;
        if (horizontal.sqrMagnitude > 1f)
            horizontal.Normalize();

        Vector3 movement = horizontal * moveSpeed;

        if (useFly)
        {
            float vertical = 0f;
            if (Keyboard.current.spaceKey.isPressed) vertical += 1f;
            if (Keyboard.current.leftCtrlKey.isPressed) vertical -= 1f;
            movement += up * vertical * verticalSpeed;
        }

        rb.MovePosition(rb.position + movement * Time.fixedDeltaTime);
    }

    private void Jump()
    {
        if (!jumpRequested)
            return;

        jumpRequested = false;

        Vector3 up = (rb.position - PlanetCenter).normalized;
        rb.AddForce(up * jumpForce, ForceMode.Impulse);
    }

    private float GetAxis(Key positive, Key negative)
    {
        float value = 0f;
        if (Keyboard.current[positive].isPressed) value += 1f;
        if (Keyboard.current[negative].isPressed) value -= 1f;
        return value;
    }

    private void Look()
    {
        if (Mouse.current == null || cameraTransform == null)
            return;

        Vector2 mouseDelta = Mouse.current.delta.ReadValue();
        float mouseX = mouseDelta.x * mouseSensitivity * 0.01f;
        float mouseY = mouseDelta.y * mouseSensitivity * 0.01f;

        transform.Rotate(Vector3.up, mouseX, Space.Self);

        cameraPitch = Mathf.Clamp(cameraPitch - mouseY, -89f, 89f);
        cameraTransform.localRotation = Quaternion.Euler(cameraPitch, 0f, 0f);
    }
}
