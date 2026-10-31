-- Layout controls for the grown composition. Distances are in page cm.
local M = { SIDE_OVERHANG = 0.25 }
local presets = { full = 1, balanced = 0.6, airy = 0.3 }
local defaults = { density = 1, text_gap = 0.15, spill = true, footer = true, header = true,
  side = "left", style = "classic", focal_count = 3, focal_scale = 1, asymmetry = 1,
  page_number = false, number_scale = 1, variation = "page", seed = false, color_mode = "color" }
M.styles = {
  classic = { density = 1, spill = true, footer = true, header = true, focal_count = 3, focal_scale = 1, asymmetry = 1 },
  quiet = { density = 0.3, spill = false, footer = false, header = false, focal_count = 1, focal_scale = 0.75, asymmetry = 0.45 },
  chapter = { density = 0.6, spill = false, footer = true, header = true, focal_count = 2, focal_scale = 1.2, asymmetry = 1.35 },
}

function M.resolve(options)
  local out = {}
  for k, v in pairs(defaults) do out[k] = v end
  local preset=options and M.styles[options.style]
  if preset then for k,v in pairs(preset) do out[k]=v end end
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
  for _, k in ipairs({ "spill", "footer", "header", "page_number" }) do
    if out[k] == "true" then out[k] = true elseif out[k] == "false" then out[k] = false end
    if type(out[k]) ~= "boolean" then error("florilegium: " .. k .. " must be true or false", 2) end
  end
  if not ({left=true,right=true,outer=true,inner=true})[out.side] then
    error("florilegium: side must be left, right, outer, or inner", 2)
  end
  if not M.styles[out.style] then error("florilegium: style must be classic, quiet, or chapter", 2) end
  if not ({page=true,spread=true,fixed=true})[out.variation] then error("florilegium: variation must be page, spread or fixed",2) end
  if not ({color=true,mono=true})[out.color_mode] then error("florilegium: color-mode must be color or mono",2) end
  if out.seed=="auto" then out.seed=false end
  if out.seed~=false then
    local n=tonumber(out.seed)
    if not n or n%1~=0 or n<0 or n>=2^31 then error("florilegium: seed must be auto or an integer from 0 to 2^31-1",2) end
    out.seed=n
  end
  for k, limits in pairs({ focal_count = {0,3}, focal_scale = {0.5,1.5}, asymmetry = {0,2}, number_scale = {0.5,1.25} }) do
    local n = tonumber(out[k])
    if not n or n ~= n or n < limits[1] or n > limits[2] or (k == "focal_count" and n % 1 ~= 0) then
      error("florilegium: invalid " .. k .. " (expected " .. limits[1] .. " to " .. limits[2] .. ")", 2)
    end
    out[k] = n
  end
  return out
end

return M
