-- Insight Tooltips: adds runtime tooltip fields (new in 2.1) to the entity a player is hovering.
-- Fields only exist while somebody hovers the entity, so nothing is computed for the rest of the map
-- and no stale numbers stay behind.

local insights = require("scripts.insights")

local ORDER_BASE = 200 -- after the vanilla tooltip lines (default order is 100)

-- storage.tracked[unit_number] = {
--   entity = LuaEntity,
--   ids = { [key] = field id },
--   viewers = { [player_index or "remote"] = true },
--   history = {}, -- measurements over time, see insights.collect
-- }
-- storage.viewing[player_index] = unit_number

local function init_storage()
  storage.tracked = storage.tracked or {}
  storage.viewing = storage.viewing or {}
end

local function clear_fields(entry)
  local entity = entry.entity
  if entity.valid then
    for _, id in pairs(entry.ids) do
      entity.clear_tooltip_field(id)
    end
  end
  entry.ids = {}
end

local function update(entry)
  local entity = entry.entity
  local lines = insights.collect(entity, entry.history) or {}
  local seen = {}
  for i, line in pairs(lines) do
    entry.ids[line.key] = entity.set_tooltip_field({
      id = entry.ids[line.key],
      name = line.name,
      value = line.value,
      order = ORDER_BASE + i,
    })
    seen[line.key] = true
  end
  for key, id in pairs(entry.ids) do
    if not seen[key] then
      entity.clear_tooltip_field(id)
      entry.ids[key] = nil
    end
  end
end

local function release(unit_number, viewer)
  local entry = storage.tracked[unit_number]
  if not entry then
    return
  end
  entry.viewers[viewer] = nil
  if next(entry.viewers) == nil then
    clear_fields(entry)
    storage.tracked[unit_number] = nil
  end
end

local function watch(entity, viewer)
  local unit_number = entity.unit_number
  local entry = storage.tracked[unit_number]
  if not entry then
    entry = { entity = entity, ids = {}, viewers = {}, history = {} }
    storage.tracked[unit_number] = entry
  end
  entry.viewers[viewer] = true
  update(entry)
end

local function stop_viewing(player_index)
  local unit_number = storage.viewing[player_index]
  if unit_number then
    storage.viewing[player_index] = nil
    release(unit_number, player_index)
  end
end

local function start_viewing(player_index, entity)
  storage.viewing[player_index] = entity.unit_number
  watch(entity, player_index)
end

local function on_selected_entity_changed(event)
  local player = game.get_player(event.player_index)
  stop_viewing(event.player_index)
  local selected = player and player.selected
  if selected and selected.unit_number and insights.collectors[selected.type] then
    start_viewing(event.player_index, selected)
  end
end

local function refresh()
  for unit_number, entry in pairs(storage.tracked) do
    if entry.entity.valid then
      update(entry)
    else
      for viewer in pairs(entry.viewers) do
        if type(viewer) == "number" then
          storage.viewing[viewer] = nil
        end
      end
      storage.tracked[unit_number] = nil
    end
  end
end

local function register_refresh()
  script.on_nth_tick(nil)
  script.on_nth_tick(settings.global["insight-tooltips-update-interval"].value, refresh)
end

local function reset()
  for _, entry in pairs(storage.tracked) do
    clear_fields(entry)
  end
  storage.tracked = {}
  storage.viewing = {}
end

script.on_init(function()
  init_storage()
  register_refresh()
end)

script.on_load(register_refresh)

script.on_configuration_changed(function()
  init_storage()
  reset()
end)

script.on_event(defines.events.on_selected_entity_changed, on_selected_entity_changed)

script.on_event({ defines.events.on_player_left_game, defines.events.on_player_removed }, function(event)
  stop_viewing(event.player_index)
end)

script.on_event(defines.events.on_runtime_mod_setting_changed, function(event)
  if string.sub(event.setting, 1, 17) ~= "insight-tooltips-" then
    return
  end
  register_refresh()
  for _, entry in pairs(storage.tracked) do
    if entry.entity.valid then
      clear_fields(entry)
    end
  end
  refresh()
end)

remote.add_interface("insight-tooltips", {
  --- Returns the tooltip lines this mod shows for an entity, as { key, name, value, raw } tables.
  --- For a watched entity this includes measurements over time (container fill rate).
  collect = function(entity)
    if not (entity and entity.valid) then
      return nil
    end
    local entry = entity.unit_number and storage.tracked[entity.unit_number]
    return insights.collect(entity, entry and entry.history)
  end,
  --- Keeps the tooltip fields on an entity as if it was hovered, until unwatch is called.
  watch = function(entity)
    if entity and entity.valid and entity.unit_number and insights.collectors[entity.type] then
      watch(entity, "remote")
    end
  end,
  unwatch = function(entity)
    if entity and entity.valid and entity.unit_number then
      release(entity.unit_number, "remote")
    end
  end,
  --- Estimated chest-to-chest inserter throughput in items per second.
  inserter_throughput = function(entity)
    if not (entity and entity.valid and entity.type == "inserter") then
      return nil
    end
    return insights.inserter_throughput(entity)
  end,
})
