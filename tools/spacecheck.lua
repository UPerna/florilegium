package.path="./?.lua;"..package.path
local space=require("space")
local region={{0,0,6,20}}
local box={{2,7,4,11}}
local clear={{1,1},{1.2,5},{1.1,15}}
assert(space.route(clear,region,box)==clear,"unobstructed curves changed")
assert(space.clearance(box,3,9)<0 and space.clearance(box,1,9)==1)
local points={}
for y=1,18,0.25 do points[#points+1]={3,y} end
assert(not space.path_clear(points,box))
local routed,ok=space.route(points,region,box)
assert(ok and space.path_clear(routed,box,0.20),"a feasible detour crosses the protected box")
assert(routed[1][1]==points[1][1] and routed[#routed][2]==points[#points][2],"routing moved the endpoints")
local again=space.route(points,region,box)
assert(#again==#routed)
for i,p in ipairs(routed) do assert(p[1]==again[i][1] and p[2]==again[i][2],"routing is not deterministic") end
local _,impossible=space.route(points,region,{{-1,7,7,11}})
assert(not impossible,"a full-width obstacle was reported as connected")
print("spacecheck: clearance, detours, determinism and blocked corridors passed")
