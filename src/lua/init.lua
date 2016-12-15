local lbx = {}

-- lazy module loading

setmetatable(lbx, {
  __index = function(t, n)
    local m = require('luabox.'..n)
    t[n] = m
    return m
  end
})

-- explicitly declared global variables

local globals = {}
local undecl_set = {}
local undecl_get = {}

local function declare(name, val)
  rawset(_G, name, val)
  globals[name] = true
end; lbx.declare = declare

local function warn_undeclared(what, name)
  local info = debug.getinfo(3, 'Sl')
  io.stderr:write(info.short_src, ':', tostring(info.currentline), ': ',
                  what, ' undeclared variable: ', name, '\n')
end

setmetatable(_G, {
  __newindex = function (t, n, v)
    if not globals[n] and not undecl_set[n] then
      warn_undeclared('setting', n)
      undecl_set[n] = true
    end
    rawset(t, n, v)
  end,
  __index = function (_, n)
    if not globals[n] and not undecl_get[n] then
      warn_undeclared('getting', n)
      undecl_get[n] = true
    end
    return nil
  end,
})

local old_require = require
declare('require', function(modname)
  globals[modname] = true
  return old_require(modname)
end)

-- "global" functions

function lbx.log(...)
  io.stderr:write(string.format(...), '\n')
end

function lbx.warn(...)
  io.stderr:write('warning: ', string.format(...), '\n')
end

return lbx
