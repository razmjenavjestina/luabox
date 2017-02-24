#!/usr/bin/env luajit

local lbx = require 'box'
local exc = lbx.exceptions

local prog = arg[0]:match '[^/]+$'
local args = {unpack(arg)}; arg = nil
if prog == 'box' or prog == 'box.lua' then prog = nil
else table.insert(args, 1, prog) end
args = lbx.cmdline.argslist(args)

exc.exit_on_exception(function()
  local root = lbx.command.root
  function root:find_subcommand(name)
    lbx.unit(name):install()
    return self.subcommands[name]
  end
  root:before_any(function(cfg)
    if cfg.debug then
      --local f = io.popen('jq -C . >&2', 'w')
      --local rj = require 'rapidjson'
      --f:write(rj.encode(cfg))
      --f:close()
      -- TODO(frane): something more generic
      print(cfg) -- :)
    end
  end)
  root:run(args)
end)
