-- Deterministic obstacle clearance and visibility-graph routing, in page cm.
local M = {}
local sqrt, min, max, ceil = math.sqrt, math.min, math.max, math.ceil
function M.clearance(rects, x, y)
  local best = math.huge
  for _, r in ipairs(rects) do
    local dx, dy = max(r[1]-x, 0, x-r[3]), max(r[2]-y, 0, y-r[4])
    local d = sqrt(dx*dx+dy*dy)
    if dx == 0 and dy == 0 then d = -min(x-r[1],r[3]-x,y-r[2],r[4]-y) end
    best = min(best,d)
  end
  return best
end
local function crosses(a,b,r,pad)
  local lo, hi = 0, 1
  for axis=1,2 do
    local d=b[axis]-a[axis]
    local mn,mx=r[axis]-pad,r[axis+2]+pad
    if math.abs(d)<1e-12 then if a[axis]<mn or a[axis]>mx then return false end
    else
      local u,v=(mn-a[axis])/d,(mx-a[axis])/d
      if u>v then u,v=v,u end
      lo,hi=max(lo,u),min(hi,v)
      if lo>hi then return false end
    end
  end
  return true
end
function M.path_clear(pts, exclusions, pad)
  for i=2,#pts do for _,r in ipairs(exclusions) do
    if crosses(pts[i-1],pts[i],r,pad or 0) then return false end
  end end
  return true
end
local function detour(pts, regions, exclusions, pad)
  pad=pad or 0.25
  if #exclusions==0 or M.path_clear(pts,exclusions,pad) then return pts,true end
  local nodes={pts[1],pts[#pts]}
  for _,r in ipairs(exclusions) do
    local p=pad+0.03
    for _,v in ipairs({{r[1]-p,r[2]-p},{r[1]-p,r[4]+p},{r[3]+p,r[2]-p},{r[3]+p,r[4]+p}}) do nodes[#nodes+1]=v end
  end
  local function within(p)
    for _,r in ipairs(regions) do if p[1]>=r[1] and p[1]<=r[3] and p[2]>=r[2] and p[2]<=r[4] then return true end end
    return false
  end
  local function edge(a,b)
    if not M.path_clear({a,b},exclusions,pad) then return nil end
    local length=sqrt((b[1]-a[1])^2+(b[2]-a[2])^2)
    local n=max(1,ceil(length/0.15))
    for k=0,n do local t=k/n if not within({a[1]+t*(b[1]-a[1]),a[2]+t*(b[2]-a[2])}) then return nil end end
    return length
  end
  local costs,previous,seen={[1]=0},{},{}
  for _=1,#nodes do
    local best,u=math.huge,nil
    for k=1,#nodes do if not seen[k] and (costs[k] or math.huge)<best then best,u=costs[k],k end end
    if not u then break end
    if u==2 then
      local order={2};while order[1]~=1 do table.insert(order,1,previous[order[1]]) end
      local out={};for _,k in ipairs(order) do out[#out+1]=nodes[k] end
      return out,true
    end
    seen[u]=true
    for v=1,#nodes do if not seen[v] then
      local d=edge(nodes[u],nodes[v])
      if d and best+d<(costs[v] or math.huge) then costs[v],previous[v]=best+d,u end
    end end
  end
  -- A box may block the entire column. The final PDF clip still protects it.
  return pts,false
end
function M.route(pts,regions,exclusions,pad)
  pad=pad or 0.5
  if #exclusions==0 or M.path_clear(pts,exclusions,pad) then return pts,true end
  local out={pts[1]};local i=1
  while i<#pts do
    if M.path_clear({pts[i],pts[i+1]},exclusions,pad) then out[#out+1]=pts[i+1];i=i+1
    else
      local j=i+1
      while j<#pts and M.clearance(exclusions,pts[j][1],pts[j][2])<=pad do j=j+1 end
      local segment,ok=detour({pts[i],pts[j]},regions,exclusions,pad)
      if not ok then return pts,false end
      for k=2,#segment do out[#out+1]=segment[k] end
      i=j
    end
  end
  local rounded={out[1]}
  local function line_to(b)
    local a=rounded[#rounded];local n=max(1,ceil(sqrt((b[1]-a[1])^2+(b[2]-a[2])^2)/0.15))
    for j=1,n do local t=j/n rounded[#rounded+1]={a[1]+t*(b[1]-a[1]),a[2]+t*(b[2]-a[2])} end
  end
  for k=2,#out-1 do
    local a,b,c=out[k-1],out[k],out[k+1]
    local u,v=sqrt((a[1]-b[1])^2+(a[2]-b[2])^2),sqrt((c[1]-b[1])^2+(c[2]-b[2])^2)
    if u>1e-9 and v>1e-9 then
      local r=min(0.6,u*0.4,v*0.4)
      local entry={b[1]+r*(a[1]-b[1])/u,b[2]+r*(a[2]-b[2])/u}
      local exit={b[1]+r*(c[1]-b[1])/v,b[2]+r*(c[2]-b[2])/v}
      line_to(entry)
      for j=1,8 do local t=j/8;rounded[#rounded+1]={(1-t)^2*entry[1]+2*t*(1-t)*b[1]+t*t*exit[1],(1-t)^2*entry[2]+2*t*(1-t)*b[2]+t*t*exit[2]} end
    end
  end
  line_to(out[#out])
  if M.path_clear(rounded,exclusions,0.20) then return rounded,true end
  return out,true
end
return M
