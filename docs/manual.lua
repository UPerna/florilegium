-- docs/manual.lua -- the Markdown of docs/*.md and README.md set as LaTeX, for florilegium-doc.tex,
-- the manual that texdoc florilegium opens. The docs stay the one source: this reads the subset of
-- Markdown they are written in (headings, paragraphs, `code`, *emphasis*, **strong**, [links](url),
-- <autolinks>, images as ![alt](src) or <img src alt width> with the italic paragraph after one as
-- its caption, fenced code, pipe tables, lists and block quotes) and sets anything else as text.
-- A link to a file or heading in the manual becomes a link inside it; any other relative link
-- points at the file in the repository, at the release's tag.
--   texlua docs/manual.lua > build/manual.tex     (from the repository's root: the LaTeX, to read)
-- Copyright (c) 2026 Kevin Raymond. MIT License: see LICENSE or florilegium.sty.

local M = {}

M.repo = "https://github.com/kevinraymond/florilegium"

-- What the manual holds, in order. A whole file opens with its # heading as a section; parts of a
-- file go under a title of their own: "" is the file's opening paragraph, any other name its
-- ## section of that name.
M.CHAPTERS = {
  { file = "README.md", title = "Introduction", parts = { "", "Origin", "Quick start" }, initial = 3 },
  { file = "docs/usage.md" },
  { file = "docs/tikz.md" },
  { file = "docs/species.md" },
  { file = "docs/traits.md" },
  { file = "docs/themes.md" },
  { file = "docs/how-it-works.md" },
  { file = "docs/svg-and-web.md" },
  { file = "docs/building.md" },
  { file = "README.md", title = "Credits and license", parts = { "Credits", "License" } },
}

-- the release, from florilegium.sty's \ProvidesPackage: links to the repository go to its tag
function M.release()
  local f = assert(io.open("florilegium.sty", "r"))
  local sty = f:read("a")
  f:close()
  local date, version = sty:match("\\ProvidesPackage{florilegium}%[(%d+/%d+/%d+) v([%d.]+)")
  return assert(version, "florilegium.sty has no version"), date
end

-- LaTeX's special characters, and the three characters Latin Modern Roman lacks
local ESC = {
  ["\\"] = "\\textbackslash{}", ["{"] = "\\{", ["}"] = "\\}", ["$"] = "\\$", ["&"] = "\\&",
  ["#"] = "\\#", ["^"] = "\\textasciicircum{}", ["_"] = "\\_", ["%"] = "\\%", ["~"] = "\\textasciitilde{}",
}
local MATH = { { "π", "\\ensuremath{\\pi}" }, { "−", "\\ensuremath{-}" }, { "→", "\\ensuremath{\\to}" } }

local function esc(s)
  s = s:gsub("[\\{}$&#^_%%~]", ESC)
  for _, m in ipairs(MATH) do s = s:gsub(m[1], m[2]) end
  return s
end

-- a URL as \href and \url take it inside another command's argument
local function urlesc(s) return (s:gsub("[#%%]", "\\%0")) end

-- GitHub's anchor for a heading: lower case, punctuation dropped, spaces as hyphens
local function slug(s)
  return (s:lower():gsub("[^%w%s%-\128-\255]", ""):gsub("%s", "-"))
end

-- dir .. path with "." and ".." resolved: docs/ and ../gallery/x.png give gallery/x.png
local function resolve(dir, path)
  local parts = {}
  for seg in (dir .. path):gmatch("[^/]+") do
    if seg == ".." and #parts > 0 and parts[#parts] ~= ".." then
      table.remove(parts)
    elseif seg ~= "." then
      parts[#parts + 1] = seg
    end
  end
  return table.concat(parts, "/")
end

local function exists(path)
  local f = io.open(path, "rb")
  if f then f:close() end
  return f ~= nil
end

-- labels of the headings the manual holds (filled by book before any text is set)
local labels = {}

local function label(file, anchor)
  return "md:" .. file .. (anchor and anchor ~= "" and ":" .. anchor or "")
end

-- `code`: break opportunities after commas, equals signs, slashes, hyphens, opening parentheses
-- and closing braces, and after a dot before a letter (not inside a number), so that a long
-- file name or key list wraps in a line or a table cell
local function code(s)
  local t = {}
  for k = 1, #s do                -- bytes; UTF-8 passes through unchanged
    local c = s:sub(k, k)
    t[#t + 1] = ESC[c] or c
    if c:match("[,=/%-}(]") or (c == "." and s:sub(k + 1, k + 1):match("%a")) then
      t[#t + 1] = "\\allowbreak{}"
    end
  end
  return "\\texttt{" .. table.concat(t) .. "}"
end

local inline

local function link(text, url, ctx)
  local shown = inline(text, ctx)
  if url:match("^%a+:") then return "\\href{" .. urlesc(url) .. "}{" .. shown .. "}" end
  local path, anchor = url:match("^([^#]*)#?(.*)$")
  path = path == "" and ctx.file or resolve(ctx.dir, path)
  local key = label(path, anchor)
  if labels[key] then return "\\hyperref[" .. key .. "]{" .. shown .. "}" end
  local target = M.repo .. "/blob/" .. M.ref .. "/" .. path .. (anchor ~= "" and "#" .. anchor or "")
  return "\\href{" .. urlesc(target) .. "}{" .. shown .. "}"
end

-- a paragraph's text: code spans first, then links, autolinks, emphasis, and straight double
-- quotes as curly ones
function inline(s, ctx)
  local out, run = {}, {}
  local function flush()
    if #run > 0 then out[#out + 1] = esc(table.concat(run)); run = {} end
  end
  local em, strong = false, false
  local i, n = 1, #s
  while i <= n do
    local c = s:sub(i, i)
    local text, url, j
    if c == "`" then
      j = s:find("`", i + 1, true)
      if j then flush(); out[#out + 1] = code(s:sub(i + 1, j - 1)); i = j + 1; goto continue end
    elseif c == "[" then
      text, url, j = s:match("^%[(.-)%]%(([^%s%)]+)%)()", i)
      if text then flush(); out[#out + 1] = link(text, url, ctx); i = j; goto continue end
    elseif c == "<" then
      url, j = s:match("^<(%a+://[^>%s]+)>()", i)
      if url then flush(); out[#out + 1] = "\\url{" .. urlesc(url) .. "}"; i = j; goto continue end
    elseif c == "*" then
      flush()
      if s:sub(i + 1, i + 1) == "*" then
        strong = not strong
        out[#out + 1] = strong and "\\textbf{" or "}"
        i = i + 2
      else
        em = not em
        out[#out + 1] = em and "\\emph{" or "}"
        i = i + 1
      end
      goto continue
    elseif c == '"' then
      local before = i > 1 and s:sub(i - 1, i - 1) or " "
      run[#run + 1] = before:match("[%s%(%[]") and "“" or "”"
      i = i + 1
      goto continue
    end
    run[#run + 1] = c
    i = i + 1
    ::continue::
  end
  flush()
  assert(not em and not strong, ctx.file .. ": an * that is never closed in: " .. s)
  return table.concat(out)
end

local function image(src, alt, width, ctx)
  local path = resolve(ctx.dir, src)
  if path:match("%.gif$") or not exists(path) then
    local where = "\\href{" .. urlesc(M.repo .. "/blob/" .. M.ref .. "/" .. ctx.file) .. "}"
    local what = path:match("%.gif$") and "{The online documentation} shows " .. esc(alt) .. " as an animation."
      or "{The online documentation} has an image here, " .. esc(alt) .. "."
    return { "\\begin{center}\\small\\emph{" .. where .. what .. "}\\end{center}" }
  end
  -- GitHub sets a width in pixels in a column about 700 wide; images without one fill it
  local w = math.min(1, (tonumber(width) or 700) / 700)
  return {
    "\\begin{center}",
    ("\\includegraphics[width=%.2f\\linewidth,height=0.42\\textheight,keepaspectratio]{%s}"):format(w, path),
    "\\end{center}",
  }
end

local function cells(row)
  row = row:gsub("^%s*|", ""):gsub("|%s*$", "")
  local out, cur, incode = {}, {}, false
  for c in row:gmatch(".") do
    if c == "`" then incode = not incode end
    if c == "|" and not incode then
      out[#out + 1] = table.concat(cur):match("^%s*(.-)%s*$")
      cur = {}
    else
      cur[#cur + 1] = c
    end
  end
  out[#out + 1] = table.concat(cur):match("^%s*(.-)%s*$")
  return out
end

-- a pipe table as a longtable of ragged-right columns, each as wide as its longest cell asks,
-- within limits, so a column of names stays narrow beside a column of sentences
local function tabular(rows, ctx)
  local head, body = cells(rows[1]), {}
  for k = 3, #rows do body[#body + 1] = cells(rows[k]) end
  local n = #head
  local want = {}
  for c = 1, n do
    local most = 0
    for _, r in ipairs({ head, table.unpack(body) }) do
      local plain = (r[c] or ""):gsub("%]%b()", "]"):gsub("[`*%[%]]", "")
      most = math.max(most, utf8.len(plain) or #plain)
    end
    want[c] = math.min(most, 50) + 6
  end
  local total = 0
  for c = 1, n do total = total + want[c] end
  local spec = {}
  for c = 1, n do
    spec[c] = (">{\\raggedright\\arraybackslash}p{\\dimexpr(\\linewidth-%d\\tabcolsep)*%d/1000\\relax}")
      :format(2 * (n - 1), want[c] * 1000 // total)
  end
  local function row(r, bold)
    local t = {}
    for c = 1, n do
      local s = inline(r[c] or "", ctx)
      t[c] = (bold and s ~= "") and "\\textbf{" .. s .. "}" or s
    end
    return table.concat(t, " & ") .. " \\\\"
  end
  local out = { "\\begin{longtable}{@{}" .. table.concat(spec) .. "@{}}", "\\toprule" }
  local empty = true
  for c = 1, n do if head[c] ~= "" then empty = false end end
  if not empty then
    out[#out + 1] = row(head, true)
    out[#out + 1] = "\\midrule"
  end
  out[#out + 1] = "\\endhead"
  for _, r in ipairs(body) do out[#out + 1] = row(r) end
  out[#out + 1] = "\\bottomrule"
  out[#out + 1] = "\\end{longtable}"
  return out
end

local HEADING = { "section", "subsection", "subsubsection", "paragraph" }

-- lines of Markdown -> lines of LaTeX, appended to out
local function blocks(lines, ctx, out)
  local function put(t) for _, l in ipairs(t) do out[#out + 1] = l end end
  local i, after_image = 1, false
  while i <= #lines do
    local line = lines[i]
    local was_image = after_image
    after_image = false
    local level, title = line:match("^(#+)%s+(.*)$")
    local fence = line:match("^```(%w*)")
    if line:match("^%s*$") then
      i = i + 1
      after_image = was_image
    elseif level then
      local cmd = HEADING[math.min(#level + (ctx.shift or 0), #HEADING)]
      local key = #level == 1 and label(ctx.file) or label(ctx.file, slug(title))
      out[#out + 1] = "\\" .. cmd .. "{" .. inline(title, ctx) .. "}\\label{" .. key .. "}"
      i = i + 1
    elseif fence then
      local code_lines = { "\\begin{Verbatim}[fontsize=\\footnotesize,breaklines,frame=leftline,framerule=0.6pt,rulecolor=\\color{ink!30},xleftmargin=6pt,framesep=8pt]" }
      i = i + 1
      while i <= #lines and not lines[i]:match("^```") do
        code_lines[#code_lines + 1] = lines[i]
        i = i + 1
      end
      code_lines[#code_lines + 1] = "\\end{Verbatim}"
      put(code_lines)
      i = i + 1
    elseif line:match("^|") and (lines[i + 1] or ""):match("^|[%s:|%-]+|%s*$") then
      local rows = {}
      while i <= #lines and lines[i]:match("^|") do
        rows[#rows + 1] = lines[i]
        i = i + 1
      end
      put(tabular(rows, ctx))
    elseif line:match("^<img ") then
      put(image(line:match('src="([^"]+)"'), line:match('alt="([^"]*)"') or "", line:match('width="(%d+)"'), ctx))
      after_image = true
      i = i + 1
    elseif line:match("^!%[.-%]%([^%)]+%)%s*$") then
      local alt, src = line:match("^!%[(.-)%]%(([^%)]+)%)")
      put(image(src, alt, nil, ctx))
      after_image = true
      i = i + 1
    elseif line:match("^%- ") or line:match("^%d+%. ") then
      local ordered = line:match("^%d+%. ") ~= nil
      local env = ordered and "enumerate" or "itemize"
      local items, cur = {}, nil
      while i <= #lines do
        local l = lines[i]
        local start = l:match("^%- (.*)$") or l:match("^%d+%. (.*)$")
        if start then
          cur = { start }
          items[#items + 1] = cur
        elseif cur and l:match("^%s+%S") then
          cur[#cur + 1] = l:match("^%s+(.*)$")
        else
          break
        end
        i = i + 1
      end
      out[#out + 1] = "\\begin{" .. env .. "}"
      for _, item in ipairs(items) do out[#out + 1] = "\\item " .. inline(table.concat(item, " "), ctx) end
      out[#out + 1] = "\\end{" .. env .. "}"
    elseif line:match("^>") then
      out[#out + 1] = "\\begin{quote}"
      local para = {}
      while i <= #lines and lines[i]:match("^>") do
        local l = lines[i]:match("^>%s?(.*)$")
        if l == "" then
          if #para > 0 then out[#out + 1] = inline(table.concat(para, " "), ctx) .. "\\par"; para = {} end
        else
          para[#para + 1] = l
        end
        i = i + 1
      end
      if #para > 0 then out[#out + 1] = inline(table.concat(para, " "), ctx) .. "\\par" end
      out[#out + 1] = "\\end{quote}"
    else
      local para = {}
      while i <= #lines and not lines[i]:match("^%s*$") and not lines[i]:match("^#")
          and not lines[i]:match("^```") and not lines[i]:match("^<img ") do
        para[#para + 1] = lines[i]
        i = i + 1
      end
      local text = table.concat(para, " ")
      if was_image and text:match("^%*[^*]") and text:match("[^*]%*$") then
        out[#out + 1] = "{\\small " .. inline(text, ctx) .. "\\par}\\medskip"
      elseif ctx.initial then
        local first, rest = text:match("^(%a)(.*)$")
        out[#out + 1] = "\\florilegiuminitial[" .. ctx.initial .. "]{" .. first .. "}" .. inline(rest, ctx)
        out[#out + 1] = ""
        ctx.initial = nil
      else
        out[#out + 1] = inline(text, ctx)
        out[#out + 1] = ""
      end
    end
  end
end

local function readlines(file)
  local f = assert(io.open(file, "r"))
  local lines = {}
  for l in f:lines() do lines[#lines + 1] = l end
  f:close()
  return lines
end

-- the lines a chapter takes from its file: all of them, or the parts it names
local function select(ch)
  local lines = readlines(ch.file)
  if not ch.parts then return { lines } end
  local chunks = {}
  for _, part in ipairs(ch.parts) do
    local chunk, inside = {}, false
    if part == "" then
      -- the opening paragraph: the first one after the # heading that is plain text
      local k = 1
      while k <= #lines and not lines[k]:match("^# ") do k = k + 1 end
      k = k + 1
      while k <= #lines and not lines[k]:match("^%a") do k = k + 1 end
      while k <= #lines and lines[k]:match("%S") do chunk[#chunk + 1] = lines[k]; k = k + 1 end
    else
      for _, l in ipairs(lines) do
        if l:match("^## ") then inside = (l == "## " .. part) end
        if inside then chunk[#chunk + 1] = l end
      end
    end
    assert(#chunk > 0, ch.file .. " has no part '" .. part .. "'")
    chunks[#chunks + 1] = chunk
  end
  return chunks
end

-- the manual's text, as lines of LaTeX
function M.book(chapters)
  chapters = chapters or M.CHAPTERS
  M.ref = M.ref or "v" .. M.release()
  -- every label first, so that a link may point forward
  labels = {}
  for _, ch in ipairs(chapters) do
    if ch.title and not labels[label(ch.file)] then labels[label(ch.file)] = ch end
    for _, chunk in ipairs(select(ch)) do
      for _, l in ipairs(chunk) do
        local level, title = l:match("^(#+)%s+(.*)$")
        if level then labels[#level == 1 and label(ch.file) or label(ch.file, slug(title))] = true end
      end
    end
  end
  local out = {}
  for _, ch in ipairs(chapters) do
    local ctx = { file = ch.file, dir = ch.file:match("^(.*/)") or "", initial = ch.initial }
    if ch.title then
      -- the first chapter taken from a file carries the file's label
      local key = labels[label(ch.file)] == ch and label(ch.file) or label(ch.file, slug(ch.title))
      out[#out + 1] = "\\section{" .. esc(ch.title) .. "}\\label{" .. key .. "}"
    end
    for _, chunk in ipairs(select(ch)) do blocks(chunk, ctx, out) end
  end
  return out
end

-- run as a script, it writes the manual's LaTeX to standard output
if arg and arg[0] and arg[0]:match("manual%.lua$") then
  io.write(table.concat(M.book(), "\n"), "\n")
end

return M
