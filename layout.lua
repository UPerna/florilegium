-- Layout controls for the grown composition. Distances are in page cm.
local M = { SIDE_OVERHANG = 0.25 }
local presets = { full = 1, balanced = 0.6, airy = 0.3 }
local defaults = { density = 1, text_gap = 0.15, spill = true, footer = true, header = true }

function M.resolve(options)
  local out = {}
  for k, v in pairs(defaults) do out[k] = v end
  for k, v in pairs(options or {}) do
    if defaults[k] == nil then error("florilegium: unknown layout control '" .. tostring(k) .. "'", 2) end
    out[k] = v
  end
  local d = out.density
  d = presets[d] or (type(d) == "number" or type(d) == "string") and tonumber(d)
  if not d or d ~= d or d < 0.2 or d > 1 then
    error("florilegium: density must be full, balanced, airy, or a number from 0.2 to 1", 2)
  end
  out.density = d
  local gap = out.text_gap
  if type(gap) ~= "number" or gap ~= gap or gap < 0 or gap == math.huge then
    error("florilegium: text-gap must be a finite, nonnegative dimension", 2)
  end
  for _, k in ipairs({ "spill", "footer", "header" }) do
    if out[k] == "true" then out[k] = true elseif out[k] == "false" then out[k] = false end
    if type(out[k]) ~= "boolean" then error("florilegium: " .. k .. " must be true or false", 2) end
  end
  return out
end

return M
