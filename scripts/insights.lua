-- Computes the tooltip lines for a single entity. Only information the vanilla 2.1 tooltip does not
-- already show is added. Each collector appends { key, name, value, raw } entries; control.lua turns them
-- into runtime tooltip fields. `raw` is the underlying number (per second, seconds, ...) for other mods and tests.

local format = require("scripts.format")

local insights = {}

local TWO_PI = 2 * math.pi
local FLOW_WINDOW = 600 -- ticks of container history used for the fill rate

local function add(out, key, value, raw)
  out[#out + 1] = { key = key, name = { "insight-tooltips." .. key }, value = value, raw = raw }
end

--- Expected amount of a recipe/mining product per craft, including productivity.
local function amount_with_productivity(product, productivity)
  local amount = product.amount or ((product.amount_min + product.amount_max) / 2)
  local probability = product.independent_probability or product.probability or 1
  local shared = product.shared_probability
  if shared then
    probability = probability * (shared.max - shared.min)
  end
  local base = amount * probability
  local ignored = (product.ignored_by_productivity or 0) * probability
  local extra = product.extra_count_fraction or 0
  return base + math.max(base - ignored, 0) * productivity + extra * (1 + productivity)
end

-----------------------------------------------------------------------------------------------------------------------
-- Mining drills: output including speed and productivity bonuses, and when the field runs out.

local function collect_drill(entity, out)
  local prototype = entity.prototype
  local categories = prototype.resource_categories or {}
  local resources = entity.surface.find_entities_filtered({ area = entity.mining_area, type = "resource" })
  local total, infinite, first = 0, false, nil
  for _, resource in pairs(resources) do
    local resource_prototype = resource.prototype
    if categories[resource_prototype.resource_category] then
      first = first or resource
      if resource_prototype.infinite_resource then
        infinite = true
      else
        total = total + resource.amount
      end
    end
  end
  if not first or infinite then
    return
  end

  local target = entity.mining_target or first
  local mineable = target.prototype.mineable_properties
  local cycles = prototype.mining_speed * (1 + entity.speed_bonus) / mineable.mining_time
  local product = mineable.products and mineable.products[1]
  if product then
    local rate = cycles * amount_with_productivity(product, entity.productivity_bonus)
    add(out, "drill-output", { "", format.icon(product.type, product.name), " ", format.rate(rate) }, rate)
  end

  -- the vanilla tooltip already shows the resources left ("Expected resources"), so only the time is added
  local drain = (prototype.resource_drain_rate_percent or 100) / 100 * entity.quality.mining_drill_resource_drain_multiplier
  local consumed_per_second = cycles * drain
  if consumed_per_second > 0 then
    local seconds = total / consumed_per_second
    add(out, "depletes-in", { "insight-tooltips.depletes-in-value", format.duration(seconds) }, seconds)
  end
end

-----------------------------------------------------------------------------------------------------------------------
-- Inserters: throughput (vanilla only shows the rotation speed in degrees).

--- Estimated chest-to-chest throughput in items per second, and the hand size.
function insights.inserter_throughput(entity)
  local prototype = entity.prototype
  local quality = entity.quality
  local rotation_speed = prototype.get_inserter_rotation_speed(quality) -- revolutions per tick
  local extension_speed = prototype.get_inserter_extension_speed(quality) -- tiles per tick
  local position = entity.position
  local pickup, drop = entity.pickup_position, entity.drop_position
  local px, py = pickup.x - position.x, pickup.y - position.y
  local dx, dy = drop.x - position.x, drop.y - position.y

  local angle = math.abs(math.atan2(py, px) - math.atan2(dy, dx))
  if angle > math.pi then
    angle = TWO_PI - angle
  end
  local rotation_ticks = (angle / TWO_PI) / rotation_speed
  local extension_ticks = math.abs(math.sqrt(px * px + py * py) - math.sqrt(dx * dx + dy * dy)) / extension_speed
  -- Measured in 2.1: a swing takes ceil(t) - 1 ticks, because the hand picks up or drops on the tick it arrives
  -- (burner 76, inserter 70, long-handed 48, fast/bulk/stack 24 ticks per round trip).
  local one_way = math.max(math.ceil(math.max(rotation_ticks, extension_ticks) - 1e-6) - 1, 1)
  local hand = math.max(entity.inserter_target_pickup_count, 1)
  return hand * 60 / (2 * one_way), hand
end

local function collect_inserter(entity, out)
  local rate, hand = insights.inserter_throughput(entity)
  add(out, "inserter-throughput", { "insight-tooltips.inserter-throughput-value", format.rate(rate), hand }, rate)
end

-----------------------------------------------------------------------------------------------------------------------
-- Crafting machines: vanilla shows the recipe rates including productivity, but not how close the next
-- bonus craft is.

local function collect_crafter(entity, out)
  local recipe = entity.get_recipe()
  if not recipe or entity.productivity_bonus <= 0 or recipe.prototype.maximum_productivity <= 0 then
    return
  end
  add(out, "bonus-progress", format.percent(entity.bonus_progress), entity.bonus_progress)
end

-----------------------------------------------------------------------------------------------------------------------
-- Containers and wagons: fill rate measured while the entity is hovered, and when it will be full or empty.

local CONTAINER_INVENTORY = {
  ["container"] = defines.inventory.chest,
  ["logistic-container"] = defines.inventory.chest,
  ["cargo-wagon"] = defines.inventory.cargo_wagon,
}

local function collect_container(entity, out, history)
  local inventory = entity.get_inventory(CONTAINER_INVENTORY[entity.type])
  if not inventory then
    return
  end
  local count = inventory.get_item_count()
  add(out, "item-count", format.number(count), count)
  if not history then
    return
  end

  local samples = history.samples or {}
  history.samples = samples
  samples[#samples + 1] = { tick = game.tick, count = count }
  while #samples > 2 and game.tick - samples[1].tick > FLOW_WINDOW do
    table.remove(samples, 1)
  end
  local first = samples[1]
  local span = (game.tick - first.tick) / 60
  if span < 1 then
    add(out, "flow", { "insight-tooltips.measuring" })
    return
  end
  local rate = (count - first.count) / span
  if math.abs(rate) < 0.01 then
    add(out, "flow", { "insight-tooltips.flow-steady" }, 0)
  elseif rate > 0 then
    -- room for more of the most common item, which is what is usually flowing in
    local most
    for _, stack in pairs(inventory.get_contents()) do
      if not most or stack.count > most.count then
        most = stack
      end
    end
    local room = most and inventory.get_insertable_count({ name = most.name, quality = most.quality }) or 0
    add(out, "flow", { "insight-tooltips.flow-filling", format.rate(rate), format.duration(room / rate) }, rate)
  else
    add(out, "flow", { "insight-tooltips.flow-emptying", format.rate(-rate), format.duration(count / -rate) }, rate)
  end
end

-----------------------------------------------------------------------------------------------------------------------
-- Electric poles: vanilla shows the network; the time until the accumulators are full or empty is added.

--- Summary of an electric network's last update, in watts and joules. Shared with tests.
function insights.network_summary(network)
  local flow = network.flow_last_tick
  return {
    satisfaction = flow.consumption_satisfaction,
    consumption = (flow.primary_demand * flow.primary_demand_usage + flow.secondary_demand * flow.secondary_demand_usage) * 60,
    capacity = flow.maximum_production * 60,
    accumulator_energy = flow.accumulator_energy,
    accumulator_capacity = flow.accumulator_capacity,
    accumulator_in = flow.tertiary_demand * flow.tertiary_demand_usage * 60,
    accumulator_out = flow.tertiary_output * flow.tertiary_output_usage * 60,
  }
end

local function collect_pole(entity, out)
  local sub_network = entity.electric_network
  if not (sub_network and sub_network.valid) then
    return
  end
  local summary = insights.network_summary(sub_network.parent_network)
  if summary.accumulator_capacity <= 0 then
    return
  end
  if summary.accumulator_out > 0 and summary.accumulator_energy > 0 then
    local seconds = summary.accumulator_energy / summary.accumulator_out
    add(out, "accumulators", { "insight-tooltips.accumulators-draining", format.duration(seconds) }, -seconds)
  elseif summary.accumulator_in > 0 then
    local seconds = (summary.accumulator_capacity - summary.accumulator_energy) / summary.accumulator_in
    add(out, "accumulators", { "insight-tooltips.accumulators-charging", format.duration(seconds) }, seconds)
  end
end

-----------------------------------------------------------------------------------------------------------------------

insights.collectors = {
  ["mining-drill"] = { setting = "insight-tooltips-drills", collect = collect_drill },
  ["inserter"] = { setting = "insight-tooltips-inserters", collect = collect_inserter },
  ["assembling-machine"] = { setting = "insight-tooltips-crafters", collect = collect_crafter },
  ["furnace"] = { setting = "insight-tooltips-crafters", collect = collect_crafter },
  ["rocket-silo"] = { setting = "insight-tooltips-crafters", collect = collect_crafter },
  ["container"] = { setting = "insight-tooltips-containers", collect = collect_container },
  ["logistic-container"] = { setting = "insight-tooltips-containers", collect = collect_container },
  ["cargo-wagon"] = { setting = "insight-tooltips-containers", collect = collect_container },
  ["electric-pole"] = { setting = "insight-tooltips-poles", collect = collect_pole },
}

--- Returns the tooltip lines for an entity, or nil if this mod has nothing to say about it.
--- history is a table kept per watched entity, used for measurements over time (container fill rate).
function insights.collect(entity, history)
  local collector = insights.collectors[entity.type]
  if not collector or not settings.global[collector.setting].value then
    return nil
  end
  local out = {}
  collector.collect(entity, out, history)
  return out
end

return insights
