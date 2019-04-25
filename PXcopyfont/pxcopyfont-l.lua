--
-- pxcopyfont
--
prog_name = "pxcopyfont"
version = "0.7.1L"
mod_date = "2010/05/05"
--globals
out_files = {}

-------- main

function main()
  kpse.set_program_name(prog_name)
  read_option()
  local vfc, k
  vfc = parse_vf(read_whole(kpse_find(src_main..".vf")))
  if op_info then info_vf(vfc); return end
  if op_zrname then set_names_zrname(vfc) end
  local nb = #vfc[1]; local nb1 = #dst_base
  info(("copy %s --> %s"):format(src_main, dst_main))
  if nb == nb1 then
    info(("source vf has %d base tfm(s)"):format(nb))
  else
    local m = "wrong number of base tfm(s) (must be %d)"
    w_error(m:format(nb), nb1)
    if nb1 > nb then dst_base[nb + 1] = nil end
  end
  write_whole(dst_main..".vf", form_vf(vfc))
  write_whole(dst_main..".tfm", read_whole(kpse_find(src_main..".tfm")))
  for k = 1, #dst_base do
    local sfn = vfc[1][k][2]; local dfn = dst_base[k]
    write_whole(dfn..".tfm", read_whole(kpse_find(sfn..".tfm")))
  end
  if op_dryrun then return end
  write_all()
end

-------- vf parsing
FID_OVER = 999

function parse_vf(vf)
  local fs, pos; local lst = {}
  fs = { vf:byte(1, 3) }
  if not(fs[1] == 0xf7 and fs[2] == 0xca) then return end
  pos = fs[3] + 12; local hd = vf:sub(1, pos - 1)
  while true do
    fs = { vf:byte(pos, pos + 1) }; local fid
    if not(243 <= fs[1] and fs[1] <= 246) then break end
    if fs[1] == 243 then fid = fs[2] else fid = FID_OVER end
    local t = fs[1] - 242 + 13
    local pos2 = pos + t; local fs0 = vf:sub(pos, pos2 - 1)
    fs = { vf:byte(pos2, pos2 + 1) }
    local l = fs[1] + fs[2]; local n = vf:sub(pos2 + 2, pos2 + l + 1)
    pos = pos2 + l + 2; table.insert(lst, { fs0, n, fid })
    if not n:match("^[\33-\126]+$") then
      n = n:gsub("[^\33-\91\93-\126]", xescape)
      error_("bad tfm name recorded in VF", n)
    end
  end
  local ft = vf:sub(pos):gsub("\248+$", "")
  return { lst, hd, ft }
end

function xescape(ch)
  return ("\\x%02x"):format(ch:byte())
end

function info_vf(vfc)
  io.stdout:write(("VF '%s' refers to:\n"):format(src_main))
  local i, ent
  for i, ent in pairs(vfc[1]) do
    io.stdout:write(("%03d:%s\n"):format(ent[3], ent[2]))
  end
end

function form_vf(vfc)
  local k; local lst = {}
  if op_zero then
    local t = vfc[1][1]
    if t and t[3] ~= 0 then
      if not(op_force or t[3] == 1) then
        w_error("first fontmap id is not 1", t[3])
      end
      local m = "change first fontmap id to zero (from %d)"
      info(m:format(t[3]))
      t[1] = replacesub(t[1], 2, 2, "\0"); t[3] = 0
    end
  end
  for k = 1, #vfc[1] do
    local t = vfc[1][k]; local sfn = t[2]
    local dfn = dst_base[k]
    if not dfn or dfn == "" then dfn = sfn end
    if #dfn >= 256 then error_("tfm name too long", dfn) end
    info(("(%03d) %s --> %s"):format(t[3], sfn, dfn))
    table.insert(lst, t[1].."\0"..string.char(#dfn)..dfn)
  end
  table.insert(lst, 1, vfc[2]); table.insert(lst, vfc[3])
  local tfm = table.concat(lst, "")
  return tfm .. ("\248"):rep(4 - #tfm % 4)
end

-------- make-name

function set_names_zrname(vfc)
  local fam = dst_main; local ent = vfc[1]
  dst_main = new_name_zrname(src_main, fam); local k
  for k = 1, #ent do
    dst_base[k] = new_name_zrname(ent[k][2], fam)
  end
end

function new_name_zrname(name, fam)
  repeat
    if not name:match("^[%w%-_]+$") then break end
    local fs = split("-", name); local j, k; local sfx = ""
    if fs[1] == "r" then k = 1 else k = 0 end
    if not(#fs >= k + #fam) then break end
    if op_zrname == 2 and #fs >= k + 2 then
      sfx = fs[k + 2]:match("([59]?)$")
    end
    for j = 1, #fam do
      fs[k + j] = fam[j]
      if j == 2 then fs[k + j] = fs[k + j] .. sfx end
    end
    return table.concat(fs, "-")
  until false
  error_("name made in unexpected way", name)
end

function new_name_zrtype(name, typ)
  local pfx = ""
  if not name:match("^[%w_]+%-[%w_]+$") then
    error_("bad target family/shape name", name)
  end
  local fs1, fs2 = typ:match("^([59])-([%w_]+)$")
  if fs1 then pfx, typ = fs1, fs2
  elseif not typ:match("^[%w_]+$") then
    error_("bad type name", typ)
  end
  return name..pfx.."-"..typ
end

-------- input/output

function read_whole(fnam)
  local hin = io.open(fnam, "rb")
  if not hin then error_("cannot open file for input", fnam) end
  info("read from", fnam)
  local buf = hin:read("*a"); hin:close()
  return buf
end

function write_whole(fnam, buf)
  out_files[fnam] = buf
end

function write_all()
  local fnam, buf
  for fnam, buf in pairs(out_files) do
    if not op_overwr and file_exists(fnam) then
      info("already exists", fnam)
    else
      local hout = io.open(fnam, "wb")
      if not hout then error_("cannot open file for output", fnam) end
      info("write to", fnam)
      hout:write(buf); hout:close()
    end
  end
end

function file_exists(fnam)
  local hx = io.open(fnam, "r")
  if not hx then return false end
  hx:close(); return true
end

function kpse_find(fnam)
  local out
  if op_kpse then
    local ftype = "tfm"
    if fnam:match("%.vf$") then ftype = "vf" end
    out = kpse.find_file(fnam, ftype)
  else
    if file_exists(fnam) then out = fnam end
  end
  if not out then
    if op_zrtype and op_zrtype:match("z.$") then
      info("source vf not found (it's ok)", fnam); os.exit()
    else
      error_("source vf not found", fnam)
    end
  end
  info("file found by Kpathsearch", fnam)
  return out
end

-------- user interface

function read_option()
  op_verb = false; op_info = false; op_zero = false; op_force = false
  op_overwr = false; op_zrname = false; op_kpse = true
  if #arg == 0 then show_usage() end
  while #arg > 0 and arg[1]:match("^%-") do
    local opt = arg[1]; table.remove(arg, 1)
    if opt == "-h" or opt == "--help" then
      show_usage()
    elseif opt == "-v" or opt == "--verbose" then
      op_verb = true
    elseif opt == "-z" or opt == "--zero" then
      op_zero = true
    elseif opt == "-f" or opt == "--force" then
      op_force = true
    elseif opt == "-o" or opt == "--overwrite" then
      op_overwr = true
    elseif opt == "-Z" or opt == "--zrname" then
      op_zrname = 1
    elseif opt == "-K" or opt == "--no-kpse" then
      op_kpse = nil
    elseif opt == "-D" or opt == "--dry-run" then
      op_dryrun = true; op_verb = true
    elseif opt == "--zrname-x" then
      op_zrname = 2
    elseif opt:match("^%-%-zrtype") then
      local fs = opt:match("^%-%-zrtype[:=]?(.*)")
      if fs == "" then error("argument is missing", opt) end
      op_zrtype = fs
    else
      error_("invalid option", opt)
    end
  end
  src_main, dst_main, dst_base = arg[1], arg[2], { unpack(arg, 3) }
  if not src_main then error_("no argument given") end
  if op_zrtype then
    op_zrname = 2
    src_main = new_name_zrtype(src_main, op_zrtype)
  end
  if dst_main then
    if op_zrname then
      if #dst_base > 0 then error_("wrong number of arguments given") end
      if not dst_main:match("^[%w%-_]+$") then
        error_("bad target family/shape name", dst_main)
      end
      dst_main = split("-", dst_main)
    elseif not op_force and not op_zrname and #dst_base == 0 then
      error_("no base tfm name given")
    end
  else op_info = true
  end
end

function show_usage()
  local msg = [[
This is !PROG_NAME! v!VERSION! <!MOD_DATE!> by 'ZR'.
Usage: !PROG_NAME! [<option>...] <in_font> <out_font> <out_base_tfm>...
       !PROG_NAME! [<option>...] <in_font>           (to show fontmap)
Arguments:
  <in_font>     input virtual font name (without path or extension)
    N.B. Input TFM/VF files are searched by Kpathsearch.
  <out_font>    output virtual font name
  <out_base_tfm>  names of raw TFMs referred by the output virtual font;
                each entry replaces a font mapping in the input font in
                the given order, so the exactly same number of entries
                must be given as font mappings
Options:
  -v --verbose  verbose mode
  -z --zero     change first fontmap id in vf from 1 to 0
  -f --force    ignore non-fatal errors
  -o --overwrite allow to overwrite existing files
  -Z --zrname   ZR-name mode; in this mode, <out_font> is given as family/
                variant name (leading subpart of font name following ZR-
                naming scheme) and <out_base_tfm> list must be empty; all
                output font names will be constructed automatically
  -K --no-kpse  disable Kpathsearch and assume all files stay in current
                directory
  -D --dry-run  turn on -v and do not write resulted files
]];
  msg = msg:gsub("!PROG_NAME!", prog_name)
    :gsub("!MOD_DATE!", mod_date):gsub("!VERSION!", version)
  io.stdout:write(msg); os.exit()
end

function message(...)
  io.stderr:write(table.concat({prog_name, ...}, ": "), "\n")
end
function info(...)
  if (op_verb) then message(...) end
end
function alert(...)
  message("warning", ...)
end
function w_error(...)
  if (op_force) then alert(...) else error_(...) end
end
function error_(...)
  message(...); os.exit(-1)
end

-------- auxiliary functions

function split(pattern, str)
  local pos = 1; local ary = {}
  repeat
    spos, epos = str:find(pattern, pos)
    if spos then
      table.insert(ary, str:sub(pos, spos - 1)); pos = epos + 1
    else
      table.insert(ary, str:sub(pos)); epos = #str
    end
  until epos == #str
  return ary
end

function replacesub(str, spos, epos, repl)
  return str:sub(1, spos - 1)..repl..str:sub(epos + 1)
end

-------- go to main
main()
-- EOF
