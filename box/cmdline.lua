local cmdline = {}

local lbx = require 'box'
local exc = require 'exc'

local function attrs(s, offs)
  offs = offs or 1
  local k = s:find('[^ \t]', offs)
  local x = {}
  while k do
    local q = (s:find('[ \t=]', k + 1) or #s + 1) - 1
    local attr = s:sub(k, q)
    local val
    if s:byte(q + 1) ~= 0x3d then
      val = true
      k = q + 1
    else
      local m, n = s:find('^%b()', q + 2)
      if m then
        val = s:sub(m + 1, n - 1)
        n = n + 1
      else
        n = s:find('[ \t]', q + 2)
        val = s:sub(q + 2, (n or 0) - 1)
      end
      k = n
    end
    x[attr] = val
    k = k and s:find('[^ \t]', k)
  end
  return x
end

local function luaname(s)
  return s:lower():gsub('-', '_')
end

-- argslists

local args_ = {}
local args_mt = {
  __index = function(args, key)
    if type(key) == 'number' then
      local i = args.first + key - 1
      return i <= args.last and args.list[i] or nil
    else return rawget(args_, key) end
  end,
  __len = function(args) -- doesn't work in lua 5.1
    return args.last - args.first + 1
  end,
}
args_.len = args_mt.__len -- workaround for 5.1

local function args_sepby(args, sep)
  local xs = {}
  local k = args.first
  for i = args.first, args.last do
    if args.list[i] == sep then
      table.insert(xs, setmetatable({
        list  = args.list,
        first = k,
        last  = i - 1,
      }, args_mt))
      k = i + 1
    end
  end
  table.insert(xs, setmetatable({
    list  = args.list,
    first = k,
    last  = args.last,
  }, args_mt))
  return xs
end; args_.sepby = args_sepby

local function argslist(as, i, j)
  return setmetatable({
    list  = as,
    first = i or 1,
    last  = j or as and #as,
  }, args_mt)
end; cmdline.argslist = argslist

-- options

local opt_ = {}
local opt_mt = {__index = opt_}

local opt_attrs = {
  name = true,
  var = true,
  repeated = true,
  required = true,
  default = true,
}

local function optspec(s)
  assert(type(s) == 'string')
  local k = s:find('[^ \t]')

  local so = {}
  local lo = {}
  local mv = {}
  local spec = {
    sopts = so,
    lopts = lo,
    metavars = mv,
  }

  while k do
    local q = (s:find('[ \t]', k + 1) or #s + 1) - 1 -- last char
    local len = q - k + 1

    local dash1 = s:byte(k) == 0x2d
    local dash2 = dash1 and s:byte(k+1) == 0x2d

    if dash2 and len == 2 then
      for key, val in pairs(attrs(s, q + 2)) do
        if opt_attrs[key] then spec[key] = val
        else lbx.warn('unknown option attribute: %s', key) end
      end
      break
    elseif dash2 and len > 2 then
      if #mv > 0 then error('options must precede metavars', 0) end
      local o = s:sub(k + 2, q)
      table.insert(lo, o)
    elseif dash1 and len == 2 then
      if #mv > 0 then error('options must precede metavars', 0) end
      table.insert(so, s:sub(k + 1, q))
    elseif not dash1 and len > 1 then
      local v = {}
      local colon = s:find(':', k, true)
      if colon and colon <= q then
        v.name = luaname(s:sub(k, colon - 1))
        v.typ  = s:sub(colon + 1, q)
      else
        v.name = luaname(s:sub(k, q))
        v.typ  = 'string'
      end
      table.insert(mv, v)
    else
      error('invalid option spec: '..s:sub(k, q), 0)
    end

    k = s:find('[^ \t]', q + 2)
  end

  local proto = {}
  for _, o in ipairs(so) do
    table.insert(proto, '-'..o)
  end
  for _, o in ipairs(lo) do
    table.insert(proto, '--'..o)
  end
  for _, v in ipairs(mv) do
    table.insert(proto, v.name)
  end
  proto = table.concat(proto, ' ')
  if spec.repeated then
    proto = proto..' ...'
  end
  spec.proto = proto

  return spec
end

local function option(spec)
  if type(spec) == 'string' then
    spec = optspec(spec)
  end
  assert(type(spec) == 'table')

  local name = spec.name
  if not name then
    if #spec.lopts > 0 then
      name = luaname(spec.lopts[1])
    elseif #spec.sopts == 0 and #spec.metavars == 1 then
      name = luaname(spec.metavars[1].name)
    else
      error('option name missing for: '..spec.proto)
    end
  end

  local sopts, lopts = {}, {} -- sets
  for _, o in ipairs(spec.sopts) do
    sopts[o] = true
  end
  for _, o in ipairs(spec.lopts) do
    lopts[o] = true
  end

  return function(lsch, gsch)
    local opt = setmetatable({
      name = name,
      sopts = sopts,
      lopts = lopts,
      metavars = spec.metavars,
      repeated = spec.repeated,
      required = spec.required,
      doc = spec.doc,
      proto = spec.proto,
    }, opt_mt)

    local typ
    if #spec.metavars == 0 then
      typ = 'boolean'
    elseif #spec.metavars == 1 then
      typ = spec.metavars[1].typ or 'string'
    else
      local r = {}
      for _, v in ipairs(spec.metavars) do
        r[v.name] = v.typ
      end
      typ = lbx.config.record(r)
    end

    local vctor = lbx.config.var {
      typ = typ,
      repeated = spec.repeated,
      required = spec.required,
      default = spec.default,
      doc = spec.doc,
    }
    if spec.var then
      local v = gsch:getvar(spec.var)
      if v then
        if lbx.config.gettype(v.typ) ~= lbx.config.gettype(typ) then
          local m = string.format('variable %s:%s does not match option: %s',
                                  v.name, v.typ, opt.proto)
          error(m, 0)
        end
      else
        v = gsch:add(spec.var, vctor)
      end
      opt.var = v
    else
      opt.var = lsch:add(name, vctor)
    end

    return opt
  end
end; cmdline.option = option

-- commands

local commands = {}

local cmd_ = {}
local cmd_mt = {__index = cmd_}

local function cmd_parse(cmd, args)
end; cmd_.parse = cmd_parse

local function foreach_line(s, fn)
  local k = 1
  while k do
    local n = s:find('\n', k, true)
    fn(s:sub(k, n and n - 1 or -1))
    k = n and n + 1
  end
end

local cmd_attrs = {
  name = true,
  base = true,
  section = true,
}

local function cmdspec(s)
  assert(type(s) == 'string')
  local spec = {}
  local opts = {}

  local before, after = true, false
  local txt, para = {}, false -- para is true if last line was blank
  local opt
  local doc = {}
  local indent

  foreach_line(s, function(ln)
    if ln == '--' then
      after = not (before and not after)
      before = false
      para = true
      if opt then
        opt.doc = doc and table.concat(doc, '\n')
        table.insert(opts, opt)
      end
    else if not (before or after) then
      local offs = ln:find('[^ \t]', 1)
      if not offs then para = true; return end
      if offs == 1 and ln:find('--[ \t]', 1) == 1 then
        for key, val in pairs(attrs(ln, 3)) do
          if cmd_attrs[key] then spec[key] = val
          else lbx.warn('unknown command attribute: %s', key) end
        end
      elseif offs == 1 then
        if opt then
          opt.doc = doc and table.concat(doc, '\n')
          doc = {}
          table.insert(opts, opt)
        end
        exc.context(function()
          opt = optspec(ln)
          if para then table.insert(txt, ''); para = false end
          table.insert(txt, '    '..opt.proto)
        end, 'parsing optspec %q', ln)
      elseif offs > 1 then
        if para then
          table.insert(doc, '')
          table.insert(txt, '')
          para = false
        end
        indent = indent or offs - 1
        local t = ln:sub(math.min(indent + 1, offs))
        table.insert(doc, t)
        table.insert(txt, '\t'..t)
      end
    elseif ln:find('[^ \t]') then
      if para then table.insert(txt, ''); para = false end
      table.insert(txt, ln)
    elseif #txt > 0 then
      para = true
    end; end
  end)

  spec.options = opts
  spec.doc = table.concat(txt, '\n')
  return spec
end

function cmdline.command(spec)
  if type(spec) == 'string' then
    spec = cmdspec(spec)
  end

  local proto = {spec.name or '<anonymous>'}
  do
    local sopts = {}
    local lopts = {}

    for _, ospec in ipairs(spec.options) do
      for _, o in ipairs(ospec.sopts) do
        if sopts[o] then
          error('duplicate short option: -'..o, 2)
        end
        sopts[o] = true
      end
      for _, o in ipairs(ospec.lopts) do
        if lopts[o] then
          error('duplicate long option: -'..o, 2)
        end
        lopts[o] = true
      end
    end
  end

  return function()
    local gsch = lbx.config.schema {
      base = spec.base and lbx.config.getschema(spec.base),
      vars = lbx.config.section {},
    }
    local lsch = spec.section and gsch:add(spec.section, lbx.config.section {})
                 or gsch

    local options = {}
    local popts = {}
    local sopts = {}
    local lopts = {}

    for _, ospec in ipairs(spec.options) do
      exc.context(function()
        local opt = option(ospec)(lsch, gsch)
        table.insert(options, opt)
        local pos = true
        for o, _ in pairs(opt.sopts) do
          sopts[o] = opt; pos = false
        end
        for o, _ in pairs(opt.lopts) do
          lopts[o] = opt; pos = false
        end
        if pos then
          local last = popts[#popts]
          if last and last.repeated then
            exc.throw('only the last positional option can be repeated: %s',
                      last.proto)
          elseif last and last.var.typ == 'subcommand' then
            exc.throw('only the last positional option can be subcommand: %s',
                      last.proto)
          end
          table.insert(popts, opt)
        end
      end, 'adding option %q', ospec.proto)
    end

    local cmd = setmetatable({
      name = spec.name,
      options = options,
      sopts = sopts,
      lopts = lopts,
      popts = popts,
      doc = spec.doc,
      schema = gsch,
    }, cmd_mt)

    return cmd
  end
end

-- parsers

local prsr_ = {}
local prsr_mt = {__index = prsr_}

local function prsr_incr(p, name)
  p.count[name] = (p.count[name] or 0) + 1
end

local function prsr_enter(p, cmd)
  p.cfg = cmd.schema:new(p.cfg)
  p.cmd = cmd
  p.cl  = cmd.cmdline
  for k, v in pairs(p.cl.lopts) do p.lopts[k] = v end
  for k, v in pairs(p.cl.sopts) do p.sopts[k] = v end
  p.next_popt = #p.cl.popts > 0 and 1 or nil
end

local function prsr_subcommand(p, name)
  local cmd = p.cmd.subcommands and p.cmd.subcommands[name]
           or p.cmd.find_subcommand and p.cmd:find_subcommand(name)
  if not cmd then exc.throw('unknown subcommand: %s', name) end
  prsr_enter(p, cmd)
end

local function prsr_feed_bare(p, arg)
  if not p.opt and p.next_popt then
    p.opt = p.cl.popts[p.next_popt]
    if not p.opt.repeated then
      p.next_popt = p.next_popt < #p.cl.popts and p.next_popt + 1 or nil
    end
  end

  if p.opt then
    if #p.opt.metavars == 1 then
      p.cl.schema:set(p.cfg, p.opt.var.name, arg)
      prsr_incr(p, p.opt.var.name)
      if p.opt.var.typ == lbx.config.gettype 'subcommand' then
        prsr_subcommand(p, arg)
      end
      p.opt = nil
    else
      local v = p.opt.metavars[p.next_arg]
      p.val[v.name] = arg
      if p.next_arg < #p.opt.metavars then
        p.next_arg = p.next_arg + 1
      else
        p.cl.schema:set(p.cfg, p.opt.var.name, p.val)
        prsr_incr(p, p.opt.var.name)
        p.opt = nil; p.val = nil; p.next_arg = nil
      end
    end
  else
    exc.throw('unexpected trailing argument: %s', arg)
  end
end; prsr_.feed_bare = prsr_feed_bare

local function prsr_feed_opt(p, opt)
  if #opt.metavars > 0 then
    p.opt = opt
    p.val = {}
    p.next_arg = 1
  else
    p.cl.schema:set(p.cfg, opt.var.name, 'true')
    prsr_incr(p, opt.var.name)
  end
end; prsr_.feed_opt = prsr_feed_opt

local function prsr_feed(p, arg)
  if p.verbatim or p.opt then
    prsr_feed_bare(p, arg)
  elseif arg == '--' then
    p.verbatim = true
  elseif arg:find('^%-%-') then
    local eq = arg:find('=', 3, true)
    local lopt = arg:sub(3, (eq or 0) - 1)
    local opt = p.lopts[lopt]
    if not opt then exc.throw('unknown long option: --%s', lopt) end
    if eq and #opt.metavars ~= 1 then
      exc.throw('invalid use of "--option=value" syntax for: %s', opt.proto)
    end
    prsr_feed_opt(p, opt)
    if eq then
      prsr_feed_bare(p, arg:sub(eq + 1))
    end
  elseif arg:find('^%-.') then
    for k = 2, #arg do
      local sopt = arg:sub(k, k)
      local opt = p.sopts[sopt]
      if not opt then exc.throw('unknown short option: -%s', sopt) end
      local nargs = #opt.metavars
      if nargs > 0 then
        if k < #arg then
          if nargs ~= 1 then
            exc.throw('invalid use of "-ovalue" syntax for: %s', opt.proto)
          end
          prsr_feed_opt(p, opt)
          prsr_feed_bare(p, arg:sub(k + 1))
          break
        else
          prsr_feed_opt(p, opt)
        end
      else
        prsr_feed_opt(p, opt)
      end
    end
  else
    prsr_feed_bare(p, arg)
  end
end; prsr_.feed = prsr_feed

local function prsr_finish(p)
  if p.opt then
    exc.throw('expecting more arguments: %s', p.opt.proto)
  end
  local missing = {}
  for _, opt in ipairs(p.cl.options) do
    if opt.required and (p.count[opt.var.name] or 0) == 0 then
      table.insert(missing, opt.proto)
    end
  end
  if #missing > 0 then
    exc.throw('missing options: %s', table.concat(missing, ', '))
  end
end; prsr_.finish = prsr_finish

local function parser(cmd, cfg)
  local p = setmetatable({
    cfg   = cfg,
    lopts = {},
    sopts = {},
    count = {},
  }, prsr_mt)
  prsr_enter(p, lbx.command.root)
  prsr_enter(p, cmd)
  return p
end; cmdline.parser = parser

return cmdline
