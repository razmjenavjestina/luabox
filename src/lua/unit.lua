local unit = {}

local lbx = require 'luabox'
local exc = lbx.exceptions

local units = {}

local unit_env = setmetatable({}, {__index=_G})

local unit_ = {}
local unit_mt = {__index = unit_}

local function unit_install(un)
  if un.installed then return end
  exc.context(function()
    for dep, _ in pairs(un.depends) do
      unit_install(units[dep])
    end
  end, 'installing dependencies of unit %s', un.name)
  exc.context(function()
    un.install_fn(lbx)
  end, 'installing unit %s', un.name)
  un.installed = true
end; unit_.install = unit_install

local unit_paths = {}

do
  local ps = os.getenv 'LUABOX_UNIT_PATH'
  if ps then
    for p in ps:gmatch '[^;]+' do
      table.insert(unit_paths, 1, p)
    end
  end
end

local function find_unit(name)
  for _, templ in ipairs(unit_paths) do
    local path = lbx.utils.readlink(templ:gsub('?', name), 'e')
    if path then return path end
  end
end

local function load_path(path)
  local chunk, err = loadfile(path)
  if not chunk then exc.throw('cannot load unit: %s', err) end
  setfenv(chunk, unit_env)
  local ok, x = exc.pcall(chunk)
  if not ok then return nil, x end

  local depends = {}
  local install_fn

  local valid = type(x) == 'table'
            and type(x.name) == 'string'
            and (not x.depends or type(x.depends) == 'table')
            and (not x.install or type(x.install) == 'function')
  if valid and x.depends then
    for _, n in ipairs(x.depends) do
      if type(n) ~= 'string' then valid = false; break end
      depends[n] = depends[n] or true
    end
    for n, v in pairs(x.depends) do
      if type(n) == 'string' then
        depends[n] = v
      end
    end
  end
  if valid and x.install then
    install_fn = x.install
    setfenv(install_fn, _G)
  end

  if not valid then return nil, 'unit contract violation' end
  return setmetatable({
    name = x.name,
    depends = depends,
    install_fn = install_fn,
  }, unit_mt)
end

local function load_unit(name)
  if units[name] then
    return units[name]
  end
  return exc.context(function()
    local path = find_unit(name)
    if not path then
      local msg = {'cannot find unit, tried paths:'}
      if #unit_paths == '0' then
        table.insert(msg, '(no unit paths defined)')
      else
        for _, templ in ipairs(unit_paths) do
          local s = templ:gsub('?', name)
          table.insert(msg, s)
        end
      end
      exc.throw(table.concat(msg, '\n\t'))
    end
    local un, err = load_path(path)
    if not un then err:rethrow() end
    if un.name ~= name then exc.throw('unit name mismatch: %s', un.name) end
    units[name] = un
    exc.context(function()
      for dep, _ in pairs(un.depends) do
        load_unit(dep)
      end
    end, 'loading dependencies of unit %s', name)
    return un
  end, 'loading unit %s', name)
end; unit.load = load_unit

setmetatable(unit, {__call = function(_, name)
  return load_unit(name)
end})

return unit
