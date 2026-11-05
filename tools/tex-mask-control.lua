-- Independent mask control: retain actual imported geometry, remove only the L.
local P,Q,V,Parse=require('pattern'),require('pattern_recipe'),require('pattern_render'),require('pattern_parse')
local function read(path)local f=assert(io.open(path,'rb'));local b=f:read('*a');f:close();return b end
local recipe=Q.decode(read(arg[1]..'.recipe'))
local d=P.definition(P.plain(recipe.definition));local x=P.instance(Parse.decode(read(arg[1]..'.instance')),d)
local view=Parse.decode(read(arg[2]..'.view'));local scene=Parse.decode(read(arg[2]..'.scene'))
view=P.plain(P.view(view,x,d));scene=P.plain(P.scene(scene,x,P.view(view,x,d),d))
local keep=P.array();local removed=0
for _,r in ipairs(view.protected_regions)do
  local a=r.bounds
  local vertical=math.abs(a[1]-.7)<1e-7 and math.abs(a[2]-9)<1e-7 and math.abs(a[3]-1.3)<1e-7 and math.abs(a[4]-12)<1e-7
  local horizontal=math.abs(a[1]-1.3)<1e-7 and math.abs(a[2]-9)<1e-7 and math.abs(a[3]-2.5)<1e-7 and math.abs(a[4]-9.6)<1e-7
  if vertical or horizontal then removed=removed+1 else keep[#keep+1]=r end
end
assert(removed==2,'Expected exactly the two measured callout reservations')
view.extensions={diagnostic={operation='remove-two-callout-masks',source_view=view.id,removed_regions=removed}}
view.id=view.id..'/mask-control';view.protected_regions=keep
view=P.view(view,x,d);scene.id=view.id..'/scene';scene.view_ref=view.id
scene.clip={bounds=P.plain(view.crop),protected_regions=P.plain(keep)}
scene=P.scene(scene,x,view,d)
local f=assert(io.open(arg[3],'wb'));f:write(V.pdf(V.plan(scene,x,view,d)));f:close()
print('Mask control retained source instance and every original drawing operation')
