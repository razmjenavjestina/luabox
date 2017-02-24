local command = {}

local lbx = require 'box'
local exc = require 'exc'

local hook_ = {}
local hook_mt = {__index = hook_}

local function hook_make()
  return setmetatable({}, hook_mt)
end

local function hook_append(hook, fn)
  table.insert(hook, fn)
end; hook_.append = hook_append

local function hook_prepend(hook, fn)
  table.insert(hook, 1, fn)
end; hook_.prepend = hook_prepend

local function hook_call(hook, ...)
  for _, fn in ipairs(hook) do
    fn(...)
  end
end; hook_.call = hook_call

local cmd_ = {}
local cmd_mt = {__index = cmd_}

local function cmd_run(cmd, args, cfg)
  -- parse args
  local p = lbx.cmdline.parser(cmd, cfg)
  exc.context(function()
    for i = 1, args:len() do
      exc.context(function()
        p:feed(args[i])
      end, 'parsing argument %q', args[i])
      if p.cfg.show_help then return end
    end
    p:finish()
  end, 'parsing command-line arguments')
  local cmd, cfg = p.cmd, p.cfg

  if cfg.show_help then
    io.stderr:write(p.cl.doc, '\n')
    if cmd.subcommands then
      local ns = {}
      for n, _ in pairs(cmd.subcommands) do table.insert(ns, n) end
      table.sort(ns)
      io.stderr:write '\navailable subcommands:\n'
      for _, n in ipairs(ns) do
        io.stderr:write('* ', n, '\n')
      end
    end
    return
  end

  -- run pre-hooks, handler, and post-hooks
  local function run_hook(which, c, sel)
    exc.context(function()
      c[sel]:call(cfg)
    end, 'running %s-hook for %s', which, c.name or '(root)')
  end
  local cs = {}
  do local c = cmd; repeat table.insert(cs, c); c = c.super until not c end
  for k = #cs, 1, -1 do run_hook('pre', cs[k], 'pre_any_hook') end
  if cmd.pre_hook then run_hook('pre', cmd, 'pre_hook') end
  if cmd.handler then cmd.handler(cfg) end
  if cmd.post_hook then run_hook('post', cmd, 'post_hook') end
  for k = 1, #cs do run_hook('post', cs[k], 'post_any_hook') end
  return cfg
end; cmd_.run = cmd_run

local function make(x)
  return setmetatable(x or {}, cmd_mt)
end

local function cmd_after(cmd, fn)
  cmd.post_hook:prepend(fn)
end; cmd_.after = cmd_after

local function cmd_after_any(cmd, fn)
  cmd.post_any_hook:prepend(fn)
end; cmd_.after_any = cmd_after_any

local function cmd_before(cmd, fn)
  cmd.pre_hook:append(fn)
end; cmd_.before = cmd_before

local function cmd_before_any(cmd, fn)
  cmd.pre_any_hook:append(fn)
end; cmd_.before_any = cmd_before_any

local root = make {
  cmdline = (lbx.cmdline.command [[
lualbx global options:

--

-- base=(root)

--debug
    Show debug information.

-v --verbose
    Be verbose.

--help -- var=(show_help)
    Show a usage message.

COMMAND:subcommand

--

]])(),
  schema  = lbx.config.getschema 'root',
  pre_any_hook  = hook_make(),
  post_any_hook = hook_make(),
}; command.root = root

local function split_parent(name)
  local par = root
  local sub

  for seg in string.gmatch(name, '[^ ]+') do
    if sub then
      exc.assert(par.subcommands, 'no subcommands: %s', par.name)
      par = exc.assert(par.subcommands[sub], 'not a subcommand: %s', sub)
    end
    sub = seg
  end

  return par, sub
end

local function define(spec, fn)
  local name, cl, sch

  if type(spec) == 'string' then
    cl   = lbx.cmdline.command(spec)()
    name = exc.assert(cl.name, 'name not specified')
    sch  = cl.schema
    lbx.config.defschema(name, sch)
  else
    name = exc.assert(spec.name, 'name not specified')
    cl   = exc.assert(spec.cmdline, 'cmdline not specified')
    sch  = spec.schema or cl.schema
    fn   = fn or spec.handler
  end

  return exc.context(function()
    local par, sub = split_parent(name)
    local cmd = make {
      name    = name,
      super   = par,
      cmdline = cl,
      schema  = sch,
      handler = fn,
      pre_hook  = hook_make(), pre_any_hook  = hook_make(),
      post_hook = hook_make(), post_any_hook = hook_make(),
    }
    if not cmd.schema.base then
      cmd.schema.base = par.schema
    end
    if not par.subcommands then par.subcommands = {} end
    par.subcommands[sub] = cmd
    return cmd
  end, 'defining command %q', name)
end; command.define = define

local function get(name)
  local par, sub = split_parent(name)
  return exc.assert(par.subcommands[name], 'not a command: %s', name)
end; command.get = get

local function run(...)
  return cmd_run(root, lbx.cmdline.argslist {...})
end; command.run = run

setmetatable(command, {__call = function(_, spec, fn)
  return define(spec, fn)
end})

return command
