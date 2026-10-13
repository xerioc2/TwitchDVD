obs = obslua

local source_name = ""
local camera_width = 480
local camera_height = 270
local speed = 220
local spin_speed = 0
local enabled = true

local x = 0
local y = 0
local angle = 0
local direction_x = 1
local direction_y = 1
local active_scene_name = nil
local active_source_name = nil
local needs_reset = true
local force_top_left = false
local stopped_by_restore = false
local original_transforms = {}

local TICK_MS = 16
-- Some OBS builds do not export these enum names to Lua. These values are part
-- of the stable libobs API: centered alignment (0) and stretch bounds (1).
local ALIGN_CENTER = 0
local BOUNDS_STRETCH = obs.OBS_BOUNDS_STRETCH or 1

local function clamp(value, minimum, maximum)
    if value < minimum then return minimum end
    if value > maximum then return maximum end
    return value
end

local function current_scene_item()
    local scene_source = obs.obs_frontend_get_current_scene()
    if scene_source == nil then return nil, nil, nil end

    local scene = obs.obs_scene_from_source(scene_source)
    local item = nil
    if scene ~= nil and source_name ~= "" then
        item = obs.obs_scene_find_source(scene, source_name)
    end

    return item, scene_source, obs.obs_source_get_name(scene_source)
end

local function transform_key(scene_name)
    return scene_name .. "\0" .. source_name
end

local function remember_original_transform(item, scene_name)
    local key = transform_key(scene_name)
    if original_transforms[key] ~= nil then return end

    local position = obs.vec2()
    local scale = obs.vec2()
    local bounds = obs.vec2()
    obs.obs_sceneitem_get_pos(item, position)
    obs.obs_sceneitem_get_scale(item, scale)
    obs.obs_sceneitem_get_bounds(item, bounds)

    original_transforms[key] = {
        position_x = position.x,
        position_y = position.y,
        scale_x = scale.x,
        scale_y = scale.y,
        rotation = obs.obs_sceneitem_get_rot(item),
        alignment = obs.obs_sceneitem_get_alignment(item),
        bounds_type = obs.obs_sceneitem_get_bounds_type(item),
        bounds_alignment = obs.obs_sceneitem_get_bounds_alignment(item),
        bounds_x = bounds.x,
        bounds_y = bounds.y
    }
end

local function restore_transform(item, transform)
    local position = obs.vec2()
    position.x = transform.position_x
    position.y = transform.position_y

    local scale = obs.vec2()
    scale.x = transform.scale_x
    scale.y = transform.scale_y

    local bounds = obs.vec2()
    bounds.x = transform.bounds_x
    bounds.y = transform.bounds_y

    obs.obs_sceneitem_set_pos(item, position)
    obs.obs_sceneitem_set_rot(item, transform.rotation)
    obs.obs_sceneitem_set_scale(item, scale)
    obs.obs_sceneitem_set_alignment(item, transform.alignment)
    obs.obs_sceneitem_set_bounds_type(item, transform.bounds_type)
    obs.obs_sceneitem_set_bounds_alignment(item, transform.bounds_alignment)
    obs.obs_sceneitem_set_bounds(item, bounds)
end

local function fit_source(item)
    local bounds = obs.vec2()
    bounds.x = camera_width
    bounds.y = camera_height
    obs.obs_sceneitem_set_bounds_type(item, BOUNDS_STRETCH)
    obs.obs_sceneitem_set_bounds(item, bounds)
    obs.obs_sceneitem_set_alignment(item, ALIGN_CENTER)
    obs.obs_sceneitem_set_bounds_alignment(item, ALIGN_CENTER)
end

local function rotated_half_size()
    local radians = math.rad(angle)
    local cosine = math.abs(math.cos(radians))
    local sine = math.abs(math.sin(radians))
    local half_width = (camera_width * cosine + camera_height * sine) / 2
    local half_height = (camera_width * sine + camera_height * cosine) / 2
    return half_width, half_height
end

local function reset_from_item(item, scene_name, canvas_width, canvas_height)
    remember_original_transform(item, scene_name)
    fit_source(item)

    if force_top_left then
        x = 0
        y = 0
        force_top_left = false
    else
        local position = obs.vec2()
        obs.obs_sceneitem_get_pos(item, position)
        x = clamp(position.x, 0, math.max(0, canvas_width - camera_width))
        y = clamp(position.y, 0, math.max(0, canvas_height - camera_height))
    end

    angle = obs.obs_sceneitem_get_rot(item)

    local half_width, half_height = rotated_half_size()
    if x >= canvas_width - half_width then direction_x = -1 else direction_x = 1 end
    if y >= canvas_height - half_height then direction_y = -1 else direction_y = 1 end
    needs_reset = false
end

local function move_camera()
    if not enabled or stopped_by_restore or source_name == "" then return end

    local item, scene_source, scene_name = current_scene_item()
    if scene_source == nil then return end

    if item == nil then
        obs.obs_source_release(scene_source)
        return
    end

    local video_info = obs.obs_video_info()
    if not obs.obs_get_video_info(video_info) then
        obs.obs_source_release(scene_source)
        return
    end

    local canvas_width = video_info.base_width
    local canvas_height = video_info.base_height
    if needs_reset or active_scene_name ~= scene_name or active_source_name ~= source_name then
        active_scene_name = scene_name
        active_source_name = source_name
        reset_from_item(item, scene_name, canvas_width, canvas_height)
    end

    local distance = speed * (TICK_MS / 1000)
    x = x + distance * direction_x
    y = y + distance * direction_y
    angle = (angle + spin_speed * (TICK_MS / 1000)) % 360

    local half_width, half_height = rotated_half_size()
    local min_x = math.min(half_width, canvas_width / 2)
    local max_x = math.max(min_x, canvas_width - half_width)
    local min_y = math.min(half_height, canvas_height / 2)
    local max_y = math.max(min_y, canvas_height - half_height)

    if x <= min_x then
        x = min_x
        direction_x = 1
    elseif x >= max_x then
        x = max_x
        direction_x = -1
    end

    if y <= min_y then
        y = min_y
        direction_y = 1
    elseif y >= max_y then
        y = max_y
        direction_y = -1
    end

    local position = obs.vec2()
    position.x = x
    position.y = y
    obs.obs_sceneitem_set_pos(item, position)
    obs.obs_sceneitem_set_rot(item, angle)
    obs.obs_source_release(scene_source)
end

local function reset_position(props, property)
    x = 0
    y = 0
    direction_x = 1
    direction_y = 1
    force_top_left = true
    needs_reset = true
    stopped_by_restore = false
    return true
end

local function restore_camera(props, property)
    local item, scene_source, scene_name = current_scene_item()
    if scene_source == nil then return false end

    local transform = original_transforms[transform_key(scene_name)]
    if item ~= nil and transform ~= nil then
        restore_transform(item, transform)
    elseif item ~= nil then
        -- If the script was reloaded, its earlier snapshot no longer exists.
        -- Still provide a useful normal, stationary camera state.
        obs.obs_sceneitem_set_rot(item, 0)
    end

    stopped_by_restore = true
    needs_reset = true
    obs.obs_source_release(scene_source)
    return true
end

function script_description()
    return [[
<h2>DVD Camera Bounce</h2>
Moves an existing OBS source around the full canvas like a classic DVD screensaver.
Choose your camera source, set its size, movement speed, and optional spin speed,
then enable the animation.
]]
end

function script_defaults(settings)
    obs.obs_data_set_default_int(settings, "camera_width", 480)
    obs.obs_data_set_default_int(settings, "camera_height", 270)
    obs.obs_data_set_default_int(settings, "speed", 220)
    obs.obs_data_set_default_int(settings, "spin_speed", 0)
    obs.obs_data_set_default_bool(settings, "enabled", true)
end

function script_properties()
    local props = obs.obs_properties_create()
    local source_list = obs.obs_properties_add_list(
        props,
        "source_name",
        "Camera source",
        obs.OBS_COMBO_TYPE_LIST,
        obs.OBS_COMBO_FORMAT_STRING
    )

    obs.obs_property_list_add_string(source_list, "Select a source...", "")
    local sources = obs.obs_enum_sources()
    if sources ~= nil then
        for _, source in ipairs(sources) do
            local width = obs.obs_source_get_width(source)
            local height = obs.obs_source_get_height(source)
            if width > 0 and height > 0 then
                local name = obs.obs_source_get_name(source)
                obs.obs_property_list_add_string(source_list, name, name)
            end
        end
        obs.source_list_release(sources)
    end

    obs.obs_properties_add_int_slider(props, "camera_width", "Camera width (px)", 32, 3840, 1)
    obs.obs_properties_add_int_slider(props, "camera_height", "Camera height (px)", 32, 2160, 1)
    obs.obs_properties_add_int_slider(props, "speed", "Movement speed (px/sec)", 20, 1200, 10)
    obs.obs_properties_add_int_slider(props, "spin_speed", "Spin speed (degrees/sec)", -720, 720, 5)
    obs.obs_properties_add_bool(props, "enabled", "Enable bouncing")
    obs.obs_properties_add_button(props, "reset_position", "Reset to top-left", reset_position)
    obs.obs_properties_add_button(props, "restore_camera", "Restore original camera & stop", restore_camera)
    return props
end

function script_update(settings)
    source_name = obs.obs_data_get_string(settings, "source_name")
    camera_width = obs.obs_data_get_int(settings, "camera_width")
    camera_height = obs.obs_data_get_int(settings, "camera_height")
    speed = obs.obs_data_get_int(settings, "speed")
    spin_speed = obs.obs_data_get_int(settings, "spin_speed")
    enabled = obs.obs_data_get_bool(settings, "enabled")
    stopped_by_restore = false
    needs_reset = true
end

function script_load(settings)
    obs.timer_add(move_camera, TICK_MS)
end

function script_unload()
    obs.timer_remove(move_camera)
end
