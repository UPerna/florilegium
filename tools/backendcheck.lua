-- Core rendering must work without a TeX host; shape oracles use planted
-- baselines and physical reading order, independently of the PDF placement.
package.path="./?.lua;"..package.path
tex,node,token,luatexbase=nil,nil,nil,nil
local M,ink,settings=require("florilegium"),require("ink"),require("layout")
local output,resources={},{}
ink.set_backend({literal=function(s) output[#output+1]=s end,extgs=function(k,v) resources[k]=v end})
M.dimen=function() return 0 end
M.macro=function(k) return (k=="pgf@pt@aa" or k=="pgf@pt@bb") and "1" or "0" end
M.seed(1,7);M.draw("divider",1)
assert(#table.concat(output)>1000 and next(resources),"standalone renderer produced no vector paths/resources")
M.configure("variation","spread");assert(M.seed(2)==M.seed(3) and M.seed(3)~=M.seed(4))
M.configure("variation","fixed");assert(M.seed(1)==M.seed(125))
M.configure("seed","17");assert(M.seed(1)~=M.seed(1,18))
M.configure("color_mode","mono");output={};M.draw("divider",1)
local colors=0
local body=table.concat(output)
assert(not body:find(" rg",1,true) and not body:find(" RG",1,true),"monochrome emitted RGB colors")
for _ in body:gmatch("[%d.]+ [gG] ") do colors=colors+1 end
assert(colors>10)
for _,bad in ipairs({{variation="daily"},{color_mode="gray"},{seed=-1},{seed=1.5},{number_scale=0.1},{page_number="yes"}}) do
  assert(not pcall(settings.resolve,bad),"invalid control accepted")
end
local folio,numeral=require("folio"),require("numeral")
assert(numeral.normalize("xiv")=="XIV" and numeral.width("MMMDCCCLXXXVIII"))
assert(not numeral.width("A-1") and not numeral.width(12))
assert(not folio.layout({number="38",colright=6.4,reserves={{0,0,7,6}}},
  settings.resolve({page_number=true}),{1.3,0.75},{6,0.4,13,1.75}),"blocked page label was partially painted")
local function strokes(mirror,label)
  local g={number=label,pw=21,colright=6.4,mirror=mirror,seed=7}
  local n=assert(folio.layout(g,settings.resolve({page_number=true}),{1.3,0.75},{6,0.4,13,1.75}))
  local paths={}
  local api={leaf_layer=5,event=function() end,disc=function() end,add_stem_points=function() end,
    footpts={{0,1},{21,1}},place=function() end,stem=function(p) paths[#paths+1]=p end}
  folio.draw(n,g,api)
  for _,p in ipairs(paths) do for _,v in ipairs(p) do
    v[1]=(mirror and 21-v[1]-(21-n.x1) or v[1]-n.x0)
  end end
  return paths
end
for _,label in ipairs({"38","127","xiv"}) do
  local a,b=strokes(false,label),strokes(true,label)
  local index=0
  for c in numeral.normalize(label):gmatch(".") do for _,stroke in ipairs(numeral.glyphs[c].strokes) do
    index=index+1
    -- Free-end curls may turn toward the page edge; the letter body must read
    -- identically from left to right on both physical sides.
    local count=#a[index]-(stroke.curl and 28 or 0)
    assert(#a[index]==#b[index])
    for j=1,count do
      assert(math.abs(a[index][j][1]-b[index][j][1])<1e-8 and math.abs(a[index][j][2]-b[index][j][2])<1e-8,
        "page-label body was reversed on a mirrored page")
    end
  end end
end
print("backendcheck: standalone paths, resources, spread/fixed seeds, mono, controls and upright Arabic/Roman bodies passed")
