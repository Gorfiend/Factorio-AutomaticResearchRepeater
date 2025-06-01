local flib_technology = require("__flib__.technology")
local flib_gui_templates = require("__flib__.gui-templates")

--- Table for each forces settings
--- @class (exact) ArrStorageData
--- @field players ArrPlayerData[]
--- @field forces ArrForceData[]
--- @field all_techs LuaTechnologyPrototype[] All infinite techs
storage = {}

--- @class (exact) ArrPlayerData
--- @field config_frame LuaGuiElement? main config frame

--- @class (exact) ArrForceData
--- @field enabled boolean Global enable/disable flag. I false, no requeueing will be done.
--- @field techs {string:ArrTechData} Map of tech name to settings for that tech

--- @class (exact) ArrTechData
--- @field requeue boolean Whether to requeue this tech when it finishes
--- @field max_level int Don't requeue when this level is researched or already in the queue

script.on_event(defines.events.on_research_finished, function(event)
    -- Skip researches completed by a script.
    -- This includes the "instant-research" function in editor mode.
    -- Player probably doesn't want this tech to be automatically requeued.
    if event.by_script then return end

    local tech = event.research
    if tech.level >= tech.prototype.max_level then return end -- Reached max level for this tech

    local force = tech.force
    local force_data = storage.forces[force.index]
    if not force_data.enabled then return end -- globally disabled for this force

    local tech_data = get_tech_data(force_data, tech.name)
    if not tech_data.requeue then return end -- this tech disabled for this force

    if tech_data.max_level and tech_data.max_level > 0 then
        -- tech.level is the level that would be researched next, i.e. one greater than the level that just completed
        -- Count how many times this tech already occurs in the queue
        local max_queued_level = tech.level - 1
        for _, queued_tech in ipairs(force.research_queue) do
            if queued_tech.name == tech.name then
                max_queued_level = max_queued_level + 1
            end
        end
        if max_queued_level >= tech_data.max_level then return end -- Researched or have already queued the max level we want
    end

    -- Nothing disabled it, so requeue
    force.add_research(tech)
end)

--- @param force_data ArrForceData
--- @param tech_name string
function get_tech_data(force_data, tech_name)
    if not force_data.techs[tech_name] then
        force_data.techs[tech_name] = {
            requeue = true,
            max_level = 0,
        }
    end
    return force_data.techs[tech_name]
end

---@param parent LuaGuiElement
---@param tech LuaTechnology
---@param force LuaForce
function add_tech_button(parent, tech, force)
    if parent.arr_requeue_tech_button then
        parent.arr_requeue_tech_button.destroy()
    end
    local force_data = storage.forces[force.index]
    local tech_data = get_tech_data(force_data, tech.name)


    --- @type TechnologyResearchState
    local state
    if not tech_data.requeue then
        -- Always show as disabled if this specific tech is set to never requeue
        state = flib_technology.research_state.disabled
    elseif not force_data.enabled then
        -- Show as red if requeue has been disabled globally
        state = flib_technology.research_state.not_available
    elseif tech_data.max_level == 0 then
        -- If no max level set, then show as green
        state = flib_technology.research_state.researched
    elseif tech.level <= tech_data.max_level then
        -- If max level is set and it hasn't been reached yet, show as yellow
        -- tech.level is the level of the next tech available to research
        state = flib_technology.research_state.available
    else
        -- If max level has been set and reached, show as orange
        state = flib_technology.research_state.conditionally_available
    end


    local tech_button = flib_gui_templates.technology_slot(parent, tech, tech.level, state, nil, nil, 1)
    tech_button.name = "arr_requeue_tech_button"
end

--- @param force LuaForce
function refresh_force_guis(force)
    for _, p in pairs(force.players) do
        local player_gui_frame = storage.players[p.index].config_frame
        if player_gui_frame and player_gui_frame.valid then
            player_gui_frame.arr_global_enable_button.state = storage.forces[force.index].enabled
            for _, tech_frame in pairs(player_gui_frame.tech_table_scroll.tech_table.children) do
                local force_tech = force.technologies[tech_frame.name]
                add_tech_button(tech_frame, force_tech, force)
            end
        end
    end
end

function recalc_techs()
    storage.all_techs = {}
    for _, tech in pairs(prototypes.technology) do
        if flib_technology.is_multilevel(tech) then
            table.insert(storage.all_techs, tech)
        end
    end
    table.sort(storage.all_techs, flib_technology.sort_predicate)
end

--- @param event EventData.CustomInputEvent
function toggle_gui(event)
    if not event.player_index then return end
    local player = game.get_player(event.player_index)
    if not player or not player.force then return end

    local player_data = storage.players[player.index]
    if not player_data then
        player_data = {}
        storage.players[player.index] = player_data
    end

    if player_data.config_frame and player_data.config_frame.valid then
        player_data.config_frame.destroy()
        player_data.config_frame = nil
        return
    end

    local force = player.force --[[@as LuaForce]]
    local force_data = storage.forces[force.index]

    player_data.config_frame = player.gui.screen.add({
        type = "frame",
        direction = "vertical",
    })

    local toolbar = player_data.config_frame.add({
        type = "flow"
    })
    toolbar.drag_target = player_data.config_frame

    toolbar.add({
        type = "label",
        caption = { "arr-config-window-title" },
    })


    local drag_handle = toolbar.add({
        type = "empty-widget",
        style = "draggable_space",
    })
    drag_handle.style.horizontally_stretchable = true
    drag_handle.style.height = 24

    toolbar.add({
        type = "sprite-button",
        name = "arr_close_button",
        style = "frame_action_button",
        sprite = "utility/close",
        hovered_sprite = "utility/close_black",
        clicked_sprite = "utility/close_black",
    })

    local global_enable_check = player_data.config_frame.add({
        type = "checkbox",
        name = "arr_global_enable_button",
        state = force_data.enabled,
        caption = { "arr-global-enable" },
        tooltip = { "arr-global-enable-tooltip" },
    })

    player_data.config_frame.add({
        type = "label",
        caption = { "arr-config-window-description" },
    })

    local toggle_all_panel = player_data.config_frame.add({
        type = "flow",
    })

    toggle_all_panel.add({
        type = "button",
        name = "arr_enable_all_button",
        caption = { "arr-enable-all" },
    })

    toggle_all_panel.add({
        type = "button",
        name = "arr_disable_all_button",
        caption = { "arr-disable-all" },
    })

    local tech_table_scroll = player_data.config_frame.add({
        type = "scroll-pane",
        name = "tech_table_scroll",
        vertical_scroll_policy = "auto",
    })
    tech_table_scroll.style.maximal_height = 650

    local tech_table = tech_table_scroll.add({
        type = "table",
        name = "tech_table",
        column_count = 10,
    })

    for _, tech in pairs(storage.all_techs) do
        local tech_data = get_tech_data(force_data, tech.name)
        local tech_panel = tech_table.add({
            type = "frame",
            name = tech.name,
            direction = "vertical",
            style = "inside_shallow_frame",
            tags = {
                tech_name = tech.name,
            },
        })

        local force_tech = force.technologies[tech.name]

        add_tech_button(tech_panel, force_tech, force)

        local label = tech_panel.add({
            type = "label",
            caption = { "arr-max-level" },
            tooltip = { "arr-max-level-tooltip" },
        })
        label.style.left_padding = 4
        label.style.right_padding = 4

        local max_level_field = tech_panel.add({
            type = "textfield",
            name = "arr_max_level_tech_field",
            numeric = true,
        })
        max_level_field.style.width = 72
        if tech_data.max_level > 0 then
            max_level_field.text = tostring(tech_data.max_level)
        end
    end

    player_data.config_frame.auto_center = true
    player.opened = player_data.config_frame
end

--- @param event EventData.on_gui_click
function close_gui(event)
    local player_data = storage.players[event.player_index]
    if player_data.config_frame and player_data.config_frame.valid then
        player_data.config_frame.destroy()
    end
end

--- @param event EventData.on_gui_click
function handle_requeue_button(event)
    local tech_frame = event.element.parent
    if not tech_frame then return end
    local tech_name = tech_frame.tags.tech_name --[[@as string]]

    local player = game.get_player(event.player_index)
    if not player then return end
    local force_data = storage.forces[player.force_index]

    local tech_data = get_tech_data(force_data, tech_name)
    tech_data.requeue = not tech_data.requeue
    local force_tech = player.force.technologies[tech_name]

    for _, p in pairs(player.force.players) do
        player_gui_frame = storage.players[p.index].config_frame
        if player_gui_frame and player_gui_frame.valid then
            local tf = player_gui_frame.tech_table_scroll.tech_table[tech_name]
            tf.arr_requeue_tech_button.destroy()

            add_tech_button(tf, force_tech, player.force --[[@as LuaForce]])
        end
    end
end

--- @param event EventData.on_gui_checked_state_changed
function handle_global_enable_checkbox(event)
    local player = game.get_player(event.player_index)
    if not player then return end
    local force_data = storage.forces[player.force_index]

    force_data.enabled = not force_data.enabled

    refresh_force_guis(player.force --[[@as LuaForce]])
end

--- @param event EventData.on_gui_click
function enable_all(event, enabled)
    local player = game.get_player(event.player_index)
    if not player then return end
    local force_data = storage.forces[player.force_index]

    for _, tech_data in pairs(force_data.techs) do
        tech_data.requeue = enabled
    end

    refresh_force_guis(player.force --[[@as LuaForce]])
end

--- @param event EventData.on_gui_click
function handle_enable_all_button(event)
    enable_all(event, true)
end

--- @param event EventData.on_gui_click
function handle_disable_all_button(event)
    enable_all(event, false)
end

--- @param event EventData.on_gui_confirmed|EventData.on_gui_text_changed
function handle_max_level_field(event)
    local tech_frame = event.element.parent
    if not tech_frame then return end
    local tech_name = tech_frame.tags.tech_name --[[@as string]]

    local player = game.get_player(event.player_index)
    if not player then return end
    local force_data = storage.forces[player.force_index]

    local new_max = tonumber(event.element.text) or 0

    get_tech_data(force_data, tech_name).max_level = new_max
    local force_tech = player.force.technologies[tech_name]

    for _, p in pairs(player.force.players) do
        player_gui_frame = storage.players[p.index].config_frame
        if player_gui_frame and player_gui_frame.valid then
            local tf = player_gui_frame.tech_table_scroll.tech_table[tech_name]
            if p.index ~= event.player_index then
                -- Don't interrupt the player currently typing
                local field = tf.arr_max_level_tech_field
                field.text = tostring(new_max)
            end

            -- Do always update the button
            add_tech_button(tf, force_tech, player.force --[[@as LuaForce]])
        end
    end
end

script.on_event("open-automatic-research-repeater-settings", toggle_gui)

--- @type table<string, fun(event: EventData)>
handlers = {
    arr_close_button = close_gui,
    arr_requeue_tech_button = handle_requeue_button,
    arr_max_level_tech_field = handle_max_level_field,
    arr_global_enable_button = handle_global_enable_checkbox,
    arr_enable_all_button = handle_enable_all_button,
    arr_disable_all_button = handle_disable_all_button,
}

script.on_event(defines.events.on_gui_click, function(event)
    local handler = handlers[event.element.name]
    if handler then
        handler(event)
    end
end)

script.on_event(defines.events.on_gui_confirmed, function(event)
    local handler = handlers[event.element.name]
    if handler then
        handler(event)
    end
end)

script.on_event(defines.events.on_gui_text_changed, function(event)
    local handler = handlers[event.element.name]
    if handler then
        handler(event)
    end
end)

---@param event EventData.on_gui_closed
script.on_event(defines.events.on_gui_closed, function(event)
    local player_gui_frame = storage.players[event.player_index].config_frame
    if event.element == player_gui_frame then
        if player_gui_frame and player_gui_frame.valid then
            player_gui_frame.destroy()
        end
        storage.players[event.player_index].config_frame = nil
    end
end)

script.on_event(defines.events.on_player_joined_game, function(event)
    local player = game.get_player(event.player_index)
    if not player then return end
    storage.players[event.player_index] = {}
end)

script.on_event(defines.events.on_player_created, function(event)
    storage.players[event.player_index] = {}
end)

script.on_event(defines.events.on_player_removed, function(event)
    storage.players[event.player_index] = nil
end)

script.on_event(defines.events.on_force_created, function(event)
    storage.forces[event.force.index] = {
        enabled = true,
        techs = {},
    }
end)

script.on_event(defines.events.on_forces_merged, function(event)
    storage.forces[event.source_index] = nil
end)

script.on_init(function()
    storage.players = {}
    for _, player in pairs(game.players) do
        storage.players[player.index] = {}
    end
    storage.forces = {}
    for _, force in pairs(game.forces) do
        storage.forces[force.index] = {
            enabled = true,
            techs = {},
        }
    end
    recalc_techs()
end)

script.on_configuration_changed(function(e)
    -- Ensure tech list is correct
    recalc_techs()

    -- Close any open guis
    for _, value in pairs(storage.players) do
        if value.config_frame and value.config_frame.valid then
            value.config_frame.destroy()
            value.config_frame = nil
        end
    end
end)
