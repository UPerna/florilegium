-- Internal vector renderer: motif seed size RRGGBB file.pdf [color|mono] [canvas cm].
-- The Python exporter supplies the canvas for motifs with long stems/drifting seeds.
local here=arg[0]:match("^(.*)[/\\]") or "."
package.path=here.."/../?.lua;"..package.path
local motif,seed,size,color,path,mode=arg[1],tonumber(arg[2]),tonumber(arg[3]),arg[4],arg[5],arg[6] or "color"
local supported={flower=true,lily=true,leaf=true,leaflet=true,butterfly=true,bee=true,hedera=true,rosette=true,bud=true,seedhead=true,divider=true}
assert(supported[motif] and seed and seed%1==0 and seed>=0 and seed<2^31 and size and size>=0.1 and size<=2,"invalid export parameters")
assert(color and color:match("^%x%x%x%x%x%x$") and path,"expected a six-digit ink and output path")
local M,writer=require("florilegium"),require("pdfwriter").new()
M.ink.set_backend(writer.backend)
M.configure("color_mode",mode)
local rgb={};for i=1,5,2 do rgb[#rgb+1]=tonumber(color:sub(i,i+1),16)/255 end
M.colors(rgb[1],rgb[2],rgb[3],0xB4/255,0x66/255,0x2F/255)
local canvas=tonumber(arg[7]) or 6
assert(canvas>=1 and canvas<=100,"invalid export canvas")
local sp=canvas/2*72.27*65536/2.54
M.dimen=function() return sp end
M.macro=function(name) return (name=="pgf@pt@aa" or name=="pgf@pt@bb") and "1" or "0" end
M.seed(1,seed)
writer:begin();M.draw(motif,size);writer:finish(canvas*M.ink.CM,canvas*M.ink.CM);writer:write(path)
io.write(path,"\n")
