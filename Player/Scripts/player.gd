extends CharacterBody3D

enum CrouchMode {TOGGLE, HOLD}  # Два режима: переключение и зажатие
@export var crouch_mode: CrouchMode = CrouchMode.HOLD  # Настройка в инспекторе

const WALK_SPEED = 5.0
const SPRINT_SPEED = 6.0
const JUMP_VELOCITY = 4.5
const MOUSE_SENSITIVITY = 0.003
const MAX_LOOK_UP = deg_to_rad(90)
const MAX_LOOK_DOWN = deg_to_rad(-90)
const ACCELERATION = 10.0
const AIR_ACCELERATION = 2.0
const AIR_CONTROL = 0.5
const GRAVITY = 9.8
const CAMERA_BOB_FREQ = 0.5  # Частота качания камеры
const CAMERA_BOB_AMP = 0.05  # Амплитуда качания
const LANDING_SHAKE = 0.3    # Сила тряски при приземлении
const SPRINT_FOV = 75.0      # FOV при ускорении
const BASE_FOV = 70.0        # Обычный FOV
const BOB_INTENSITY_SPEED = 4.0  # Скорость нарастания/уменьшения интенсивности качания

const CROUCH_SPEED = 2.5
const CROUCH_HEIGHT = 1.0  # Высота при приседании
const STAND_HEIGHT = 1.8   # Обычная высота
const CROUCH_TRANSITION_SPEED = 8.0  # Скорость приседания/вставания
const HEAD_CHECK_OFFSET = 0.05  # Небольшой отступ для проверки свободного пространства

const INTERACTION_DISTANCE = 3.0

@onready var head = $head
@onready var camera = $head/Camera3D

var camera_rot_x: float = 0.0
var is_sprinting: bool = false
var current_speed: float = WALK_SPEED
var target_velocity: Vector3 = Vector3.ZERO
var camera_start_pos: Vector3
var bob_time: float = 0.0
var was_on_floor: bool = true
var jump_lerp: float = 1.0
var bob_intensity: float = 0.0  # Интенсивность качания (0-1)

var is_crouching: bool = false
var wants_to_stand: bool = false
var original_collection_shape: CollisionShape3D


func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	camera_start_pos = camera.position  # Запоминаем стартовую позицию камеры
	original_collection_shape = $CollisionShape3D  # Ваша нода коллизии
func _input(event):
	match crouch_mode:
		CrouchMode.TOGGLE:
			if event.is_action_pressed("crouch"):
				toggle_crouch(!is_crouching)
		
		CrouchMode.HOLD:
			if event.is_action_pressed("crouch"):
				toggle_crouch(true)
			elif event.is_action_released("crouch"):
				toggle_crouch(false)
				
	if event is InputEventMouseMotion:
		rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
		camera_rot_x += -event.relative.y * MOUSE_SENSITIVITY
		camera_rot_x = clamp(camera_rot_x, MAX_LOOK_DOWN, MAX_LOOK_UP)
		head.rotation.x = camera_rot_x
		

func _physics_process(delta):
	var is_on_floor_now = is_on_floor()
	if not is_on_floor_now:
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = 0

	# Обработка приземления
	if is_on_floor_now and not was_on_floor:
		apply_landing_shake()
	was_on_floor = is_on_floor_now

	if Input.is_action_just_pressed("ui_accept") and is_on_floor_now:
		velocity.y = JUMP_VELOCITY
		jump_lerp = 0.0

	# Управление скоростью
	is_sprinting = Input.is_action_pressed("Shift")
	current_speed = SPRINT_SPEED if is_sprinting else WALK_SPEED

	# Движение
	var input_dir = Input.get_vector("A", "D", "W", "S")
	var direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	if direction:
		target_velocity.x = direction.x * current_speed
		target_velocity.z = direction.z * current_speed
	else:
		target_velocity.x = 0
		target_velocity.z = 0

	# Плавное изменение скорости
	if is_on_floor_now:
		velocity.x = lerp(velocity.x, target_velocity.x, ACCELERATION * delta)
		velocity.z = lerp(velocity.z, target_velocity.z, ACCELERATION * delta)
	else:
		velocity.x = lerp(velocity.x, target_velocity.x, AIR_ACCELERATION * delta * AIR_CONTROL)
		velocity.z = lerp(velocity.z, target_velocity.z, AIR_ACCELERATION * delta * AIR_CONTROL)

	if wants_to_stand and can_stand():
		is_crouching = false
		wants_to_stand = false
	
	update_crouch(delta)
	update_camera_effects(delta)
	move_and_slide()

func update_camera_effects(delta: float):
	# Плавное изменение интенсивности качания
	var velocity_clamped = clamp(velocity.length(), 0.0, SPRINT_SPEED)
	if is_on_floor() and velocity_clamped > 1.0:
		bob_intensity = lerp(bob_intensity, 1.0, delta * BOB_INTENSITY_SPEED)
	else:
		bob_intensity = lerp(bob_intensity, 0.0, delta * BOB_INTENSITY_SPEED)

	# Качание камеры при движении
	if bob_intensity > 0.01:
		bob_time += delta * velocity_clamped * (1.5 if is_sprinting else 1.0)
		var bob_offset = Vector3(
			sin(bob_time * CAMERA_BOB_FREQ) * CAMERA_BOB_AMP * bob_intensity,
			cos(bob_time * CAMERA_BOB_FREQ * 2) * CAMERA_BOB_AMP * 0.7 * bob_intensity,
			0
		)
		camera.position = camera_start_pos + bob_offset
	else:
		camera.position = camera_start_pos

	# Плавное изменение FOV при ускорении
	var target_fov = SPRINT_FOV if is_sprinting else BASE_FOV
	camera.fov = lerp(camera.fov, target_fov, delta * 8.0)

	# Эффект прыжка/падения
	if not is_on_floor():
		jump_lerp = clamp(jump_lerp + delta * 2.0, 0.0, 1.0)
		camera.position.y = camera_start_pos.y - sin(jump_lerp * PI) * 0.2

func apply_landing_shake():
	# Тряска камеры при приземлении
	var shake = LANDING_SHAKE * clamp(velocity.y / -JUMP_VELOCITY, 0.5, 2.0)
	camera.position.y += shake
	camera.position.x += randf_range(-shake, shake) * 0.3
	
func toggle_crouch(should_crouch: bool):
	if should_crouch:
		is_crouching = true
		wants_to_stand = false
	else:
		if can_stand():
			is_crouching = false
			wants_to_stand = false
		else:
			wants_to_stand = true

func can_stand() -> bool:
	var space_state = get_world_3d().direct_space_state
	var radius = 0.4  # Радиус проверки (должен совпадать с радиусом коллизии персонажа)
	var height_offset = STAND_HEIGHT - CROUCH_HEIGHT + HEAD_CHECK_OFFSET
	
	# Создаем форму для проверки
	var shape = SphereShape3D.new()
	shape.radius = radius
	
	# Параметры запроса
	var query = PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D.IDENTITY.translated(
		global_position + Vector3.UP * (CROUCH_HEIGHT + height_offset/2)
	)
	query.collision_mask = collision_mask
	
	# Выполняем проверку
	var collisions = space_state.intersect_shape(query)
	return collisions.is_empty()

func update_crouch(delta: float):
	var target_height = CROUCH_HEIGHT if is_crouching else STAND_HEIGHT
	var current_height = original_collection_shape.shape.height
	
	# Плавное изменение высоты
	if abs(current_height - target_height) > 0.01:
		original_collection_shape.shape.height = lerp(
			current_height,
			target_height,
			CROUCH_TRANSITION_SPEED * delta
		)
	else:
		original_collection_shape.shape.height = target_height
	
	
	# Изменение скорости при приседании
	current_speed = CROUCH_SPEED if is_crouching else (SPRINT_SPEED if is_sprinting else WALK_SPEED)
	
