local utils = {}

local lbx = require 'luabox'

-- unix utilities

function utils.date(d)
  local f = io.popen(utils.command {
    'date', '-d', d, '+%s', '2>/dev/null' })
  local t = tonumber(f:read())
  f:close()
  if not t then lbx.exceptions.throw('invalid date: %s', d) end
  return t
end

function utils.dirslash(path)
  return path and (path:sub(-1) == '/' and path or path..'/')
end

function utils.readlink(path, mode)
  local f = io.popen(utils.command {
    'readlink', '-n', '-q',
    (mode and ('-'..mode)) or '-f',
    path,
  })
  local res = f:read '*a'
  f:close()
  return res and string.len(res) > 0 and res
end

function utils.mkdirp(path)
  if os.execute(utils.command {'mkdir', '-p', path}) ~= 0 then
    error('cannot mkdir -p '..path)
  end
  return path:sub(-1) == '/' and path or path..'/'
end

function utils.rmrec(path)
  if os.execute(utils.command {'rm', '-r', path}) ~= 0 then
    error('cannot rm -r '..path)
  end
end

local tput_cache = {}

function utils.tput(capname, ...)
  local key = table.concat({capname, ...}, ' ')
  if not tput_cache[key] then
    local f = io.popen('tput '..key)
    local s = f:read '*a'
    f:close()
    tput_cache[key] = s
    return s
  else
    return tput_cache[key]
  end
end

-- temporary files

local tmp_pfx = nil
local tmp_count = 0

function utils.tmpname(sfx)
  if not tmp_pfx then
    local cmd = 'head -c12 /dev/urandom | base64 | tr -d "+/" | head -c6'
    local p = io.popen(cmd)
    tmp_pfx = '/tmp/lbx_'..p:read('*a')
    p:close()
  end

  local fn = tmp_pfx..tmp_count
  tmp_count = tmp_count+1
  if sfx then
    return fn..'_'..sfx
  else
    return fn
  end
end

-- commands

function utils.command(cmd)
  local ss = {}
  for i, a in ipairs(cmd) do
    local x = tostring(a)
    if x:find '[" \\\t\n]' then
      x = x:gsub('\\', '\\\\')
      x = x:gsub('"', '\\"')
      x = '"'..x..'"'
    end
    table.insert(ss, x)
  end
  return table.concat(ss, ' ')
end

return utils
