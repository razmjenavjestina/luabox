local config = {}

local lbx = require 'box'
local exc = require 'exc'

-- variable types

local types = {}

local typ_ = {}
local typ_mt = {__index = typ_}

function typ_.new(typ)
  return typ.default and typ:parse(typ.default) or nil
end

function typ_mt.__tostring(typ)
  return typ.name or '<anonymous>'
end

local function deftype(tname, typ)
  assert(type(tname) == 'string')
  if types[tname] then
    error('redefinition of variable type: '..tname, 2)
  end
  if type(typ) == 'string' then
    local t = types[typ]
    if not t then error('not a variable type: '..typ, 2) end
    types[tname] = t
    return t
  elseif getmetatable(typ) ~= typ_mt then
    error('invalid definition for variable type: '..tname, 2)
  end
  typ.name = tname
  types[tname] = typ
  return typ
end; config.deftype = deftype

local function gettype(typ)
  if type(typ) == 'string' then
    local t = types[typ]
    if not t then error('not a variable type: '..typ, 2) end
    return t
  elseif getmetatable(typ) == typ_mt then
    return typ
  else
    error('invalid argument to lbx.config.gettype', 2)
  end
end; config.gettype = gettype

function config.types()
  return pairs(types)
end

-- enums

local function enum_parse(typ, s)
  if typ.case_insensitive then
    s = string.lower(s)
  end
  local val = typ.values[s]
  if val == nil then
    exc.throw('invalid %s: %s', typ.name, s)
  end
  return val
end

local function enum(spec)
  local x = setmetatable({
    values = {},
    parse = enum_parse,
  }, typ_mt)
  if type(spec) == 'string' then
    x.luatype = 'string'
    for v in spec:gmatch '%a[%w-]*' do
      x.values[v] = v
    end
  elseif type(spec) == 'table' then
    x.luatype = spec.luatype or 'string'
    x.case_insensitive = spec.case_insensitive
    x.default = spec.default
    for _, v in ipairs(spec) do
      if type(v) == 'string' then
        assert(x.luatype == 'string')
        x.values[v] = v
      elseif type(v) == 'table' then
        local y = v.value
        assert(type(y) == x.luatype)
        for _, w in ipairs(v) do
          x.values[w] = y
        end
      else
        error('invalid enum spec', 2)
      end
    end
  else
    error('invalid enum spec', 2)
  end
  return x
end; config.enum = enum

-- records

local function record_parse(typ, t)
  local x = {}
  for name, ftyp in pairs(typ.elems) do
    if not t[name] then exc.throw('record field missing: %s', name) end
    x[name] = t[name] and ftyp:parse(t[name])
  end
  return x
end

local function record(spec)
  local x = setmetatable({
    elems = {},
    parse = record_parse,
  }, typ_mt)
  assert(type(spec) == 'table')
  for name, typ in pairs(spec) do
    x.elems[name] = gettype(typ)
  end
  return x
end; config.record = record

-- standard types

deftype('boolean', enum {
  luatype = 'boolean',
  default = 'false',
  case_insensitive = true,
  {value = true, '1', 'on', 'true', 'yes', 'y'},
  {value = false, '0', 'false', 'no', 'n', 'off'},
})

deftype('integer', setmetatable({
  luatype = 'number',
  parse = function(_, s)
    local n = exc.assert(tonumber(s), 'invalid integer')
    exc.assert(n % 1 == 0, 'not an integer')
    return n
  end,
}, typ_mt))

deftype('number', setmetatable({
  luatype = 'number',
  parse = function(_, s)
    return exc.assert(tonumber(s), 'invalid number')
  end,
}, typ_mt))

deftype('string', setmetatable({
  luatype = 'string',
  parse = function(_, s) return s end,
}, typ_mt))

deftype('subcommand', setmetatable({
  luatype = 'string',
  parse = function(_, s) return s end,
}, typ_mt))

deftype('datetime', setmetatable({
  luatype = 'number',
  parse = function(_, s)
    local t
    if s:sub(1, 1) == '@' then
      t = tonumber(s:sub(2))
    else
      local cmd = string.format('date -d "%s" "%s" 2>/dev/null', s, '+%s')
      local f = io.popen(cmd)
      t = tonumber(f:read '*a')
      f:close()
    end
    exc.assert(type(t) == 'number', 'invalid date: %s', s)
    return t
  end,
}, typ_mt))

local duration_units = {
  s = 1,
  m = 60,
  h = 60 * 60,
  d = 60 * 60 * 24,
}

deftype('duration', setmetatable({
  luatype = 'number',
  parse = function(_, s)
    local d = 0
    local j = 1
    while j and j <= #s do
      local k = s:find('[^0-9]', j)
      exc.assert(not j or (j < k), 'invalid duration: %s', s)
      local n = tonumber(s:sub(j, k and k - 1 or nil))
      exc.assert(type(n) == 'number', 'invalid duration: %s', s)
      local u = duration_units[k and s:sub(k, k) or 's']
      exc.assert(type(u) == 'number', 'invalid duration: %s', s)
      d = d + n * u
      j = k and k + 1
    end
    return d
  end,
}, typ_mt))

deftype('filepath', setmetatable({
  luatype = 'string',
  parse = function(_, s) return s end,
}, typ_mt))

deftype('dirpath', setmetatable({
  luatype = 'string',
  parse = function(_, s) return s end,
}, typ_mt))

deftype('path', setmetatable({
  luatype = 'string',
  parse = function(_, s) return s end,
}, typ_mt))

deftype('inputfile', setmetatable({
  luatype = 'string',
  parse = function(_, s) return s end,
}, typ_mt))

deftype('outputfile', setmetatable({
  luatype = 'string',
  parse = function(_, s) return s end,
}, typ_mt))

-- variables

local var_ = {}
local var_mt = {__index = var_}

local function var_new(v, x)
  if x then
    return x
  elseif v.repeated then
    return {}
  else
    return v.default and v.typ:parse(v.default) or v.typ:new()
  end
end; var_.new = var_new

local function var(spec)
  if type(spec) == 'string' then
    spec = {typ = spec}
  end
  local typ = gettype(spec.typ)
  return function(vname)
    assert(type(vname) == 'string')
    return setmetatable({
      name = vname,
      typ = typ,
      repeated = spec.repeated,
      required = spec.required,
      default = spec.default,
      doc = spec.doc,
    }, var_mt)
  end
end; config.var = var

-- sections

local sec_ = {}
local sec_mt = {__index = sec_}

local function sec_add(s, path, f, offs)
  offs = offs or 1
  local dot = string.find(path, '.', offs, true)
  local fst = string.sub(path, offs, (dot or 0) - 1)
  if dot then
    local x = s.elems[fst]
    assert(x == nil or getmetatable(x) == sec_mt)
    if x == nil then
      x = setmetatable({
        name = s.name and s.name..'.'..fst or fst,
        elems = {}
      }, sec_mt)
      s.elems[fst] = x
    end
    return sec_add(x, path, f, dot + 1)
  else
    if s.elems[fst] then
      error('redefining '..fst..' in section '..s.name, 0)
    end
    local name = s.name and s.name..'.'..fst or fst
    local x = assert(f(name))
    local mt = getmetatable(x)
    if mt ~= var_mt and mt ~= sec_mt then
      error('invalid definition for '..name, 0)
    end
    s.elems[fst] = x
    return x
  end
end; sec_.add = sec_add

local function sec_get(s, path, offs)
  offs = offs or 1
  local dot = string.find(path, '.', offs, true)
  local fst = string.sub(path, offs, (dot or 0) - 1)
  local x = s.elems[fst]
  if x and dot then
    assert(getmetatable(x) == sec_mt)
    return sec_get(x, path, dot + 1)
  else
    return x
  end
end; sec_.get = sec_get

local function sec_getvar(s, path, offs)
  local v = sec_get(s, path, offs)
  assert(not v or getmetatable(v) == var_mt)
  return v
end; sec_.getvar = sec_getvar

local function sec_foreach(s, fn, pfx)
  for n, x in pairs(s.elems) do
    if getmetatable(x) == var_mt then
      fn(x, pfx and pfx..n or n)
    elseif getmetatable(x) == sec_mt then
      sec_foreach(x, fn, pfx and pfx..n..'.' or n..'.')
    end
  end
end; sec_.foreach = sec_foreach

local function sec_new(s, t)
  local t = t or {}
  for n, x in pairs(s.elems) do
    local mt = getmetatable(x)
    if mt == sec_mt and x.required then
      t[n] = sec_new(x, t[n])
    elseif mt == var_mt then
      t[n] = var_new(x, t[n])
    end
  end
  return t
end; sec_.new = sec_new

local function sec_set(s, cfg, path, val, offs)
  offs = offs or 1
  local dot = string.find(path, '.', offs, true)
  local fst = string.sub(path, offs, (dot or 0) - 1)
  if dot then
    local s2 = s.elems[fst]
    assert(s2 and getmetatable(s2) == sec_mt)
    if not cfg[fst] then
      cfg[fst] = s2:new()
    end
    return sec_set(s2, cfg[fst], path, val, dot + 1)
  else
    local v = s.elems[fst]
    assert(v and getmetatable(v) == var_mt)
    local val = v.typ:parse(val)
    if v.repeated then
      if not cfg[fst] then
        cfg[fst] = {val}
      else
        table.insert(cfg[fst], val)
      end
    else
      cfg[fst] = val
    end
    return val
  end
end; sec_.set = sec_set

local function section(spec)
  local fs = {}
  for k, f in pairs(spec) do
    assert(type(k) == 'string')
    if k:byte(1) == 95 then
      assert(type(f) == 'function')
      fs[k:sub(2)] = f
    end
  end
  return function(sname)
    local s = setmetatable({
      name = sname,
      required = spec.required,
      elems = {}
    }, sec_mt)
    for n, f in pairs(fs) do
      local name = sname and sname..'.'..n or n
      local x = assert(f(name))
      local mt = getmetatable(x)
      if mt ~= var_mt and mt ~= sec_mt then
        error('invalid definition: '..name, 0)
      end
      s.elems[n] = x
    end
    return s
  end
end; config.section = section

-- schemas

local schemas = {}

local sch_ = {}
local sch_mt = {__index = sch_}

local function sch_add(c, path, f)
  return sec_add(c.vars, path, f)
end; sch_.add = sch_add

local function sch_get(c, path)
  local x = sec_get(c.vars, path)
  return x or (c.base and sch_get(c.base, path))
end; sch_.get = sch_get

local function sch_getvar(c, path)
  local v = sch_get(c, path)
  assert(not v or getmetatable(v) == var_mt)
  return v
end; sch_.getvar = sch_getvar

local function sch_foreach(c, fn)
  sec_foreach(c.vars, fn)
end; sch_.foreach = sch_foreach

local function sch_new(c, t)
  return sec_new(c.vars, c.base and sch_new(c.base, t) or t)
end; sch_.new = sch_new

local function sch_set(c, cfg, path, val)
  repeat
    if sec_getvar(c.vars, path) then
      return exc.context(function()
        return sec_set(c.vars, cfg, path, val)
      end, 'setting configuration variable %q', path)
    end
    c = c.base
  until not c
  exc.throw('no such configuration variable: %s', path)
end; sch_.set = sch_set

local function defschema(cname, sch)
  assert(type(cname) == 'string')
  if schemas[cname] then
    error('redefinition of schema: '..cname, 2)
  end
  if type(sch) == 'string' then
    local c = schemas[sch]
    if not c then error('not a schema: '..sch, 2) end
    schemas[cname] = c
    return c
  elseif getmetatable(sch) ~= sch_mt then
    error('invalid definition for schema: '..cname, 2)
  end
  sch.name = cname
  schemas[cname] = sch
  return sch
end; config.defschema = defschema

local function getschema(sch)
  if type(sch) == 'string' then
    local c = schemas[sch]
    if not c then error('not a schema: '..sch, 2) end
    return c
  elseif getmetatable(sch) == sch_mt then
    return sch
  else
    error('invalid argument to lbx.config.getschema', 2)
  end
end; config.getschema = getschema

local function schema(spec)
  assert(type(spec) == 'table')
  local sch = setmetatable({
    base = getschema(spec.base or 'root')
  }, sch_mt)

  if spec.vars then
    assert(type(spec.vars) == 'function')
    local vars = spec.vars()
    assert(type(vars) == 'table' and getmetatable(vars) == sec_mt)
    vars.required = true
    sch.vars = vars
  else
    sch.vars = (section {required = true})()
  end

  return sch
end; config.schema = schema

-- root schema

do
  local vars = section {
    _verbose    = var 'boolean',
    _show_help  = var 'boolean',
  }
  schemas.root = setmetatable({
    name = 'root',
    vars = vars(),
  }, sch_mt)
end

return config
