-- Number, rate, power and duration formatting. All functions return strings or LocalisedStrings.

local format = {}

local SUFFIXES = { "", "k", "M", "G", "T", "P", "E" }

--- 1234 -> "1.23k", 0.5 -> "0.5"
function format.number(n)
  local negative = n < 0
  local abs = math.abs(n)
  local i = 1
  while abs >= 1000 and i < #SUFFIXES do
    abs = abs / 1000
    i = i + 1
  end
  local text
  if i == 1 then
    if abs >= 100 or abs == math.floor(abs) then
      text = string.format("%d", math.floor(abs + 0.5))
    elseif abs >= 10 then
      text = string.format("%.1f", abs)
    else
      text = string.format("%.2f", abs)
    end
  elseif abs >= 100 then
    text = string.format("%d%s", math.floor(abs + 0.5), SUFFIXES[i])
  elseif abs >= 10 then
    text = string.format("%.1f%s", abs, SUFFIXES[i])
  else
    text = string.format("%.2f%s", abs, SUFFIXES[i])
  end
  return negative and ("-" .. text) or text
end

--- Items per second -> "2.5/s", or "3/min" when slower than one per ten seconds (like the vanilla tooltips).
function format.rate(per_second)
  if per_second >= 0.1 or per_second == 0 then
    return { "insight-tooltips.per-second", format.number(per_second) }
  end
  return { "insight-tooltips.per-minute", format.number(per_second * 60) }
end

--- 0.4567 -> "46%"
function format.percent(fraction)
  return string.format("%d%%", math.floor(fraction * 100 + 0.5))
end

--- Seconds -> "3h 12m", "12m 5s" or "45s"
function format.duration(seconds)
  if seconds ~= seconds or seconds == math.huge then
    return { "insight-tooltips.never" }
  end
  seconds = math.floor(seconds + 0.5)
  if seconds >= 1000 * 3600 then
    return { "insight-tooltips.duration-long" }
  end
  local h = math.floor(seconds / 3600)
  local m = math.floor((seconds % 3600) / 60)
  local s = seconds % 60
  if h > 0 then
    return { "insight-tooltips.duration-hm", h, m }
  elseif m > 0 then
    return { "insight-tooltips.duration-ms", m, s }
  end
  return { "insight-tooltips.duration-s", s }
end

--- Rich text icon for an item or fluid, including its quality when it is not normal.
function format.icon(kind, name, quality)
  if quality and quality ~= "normal" then
    return "[" .. kind .. "=" .. name .. ",quality=" .. quality .. "]"
  end
  return "[" .. kind .. "=" .. name .. "]"
end

return format
