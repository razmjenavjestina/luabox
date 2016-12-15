local exc = {}

local exc_ = {}

local function exc_add_context(e, gerund)
  if e.context then
    table.insert(e.context, 1, gerund)
  else
    e.context = {gerund}
  end
end; exc_.add_context = exc_add_context

local function exc_rethrow(e)
  e.rethrown = true
  error(e, 0)
end; exc_.rethrow = exc_rethrow

local render_defaults = {
  stack = true,
}

local function exc_render_to(e, ss, opts)
  opts = opts or render_defaults
  if e.context then
    for i, gerund in ipairs(e.context) do
      table.insert(ss, i == 1 and 'while ' or '      ')
      table.insert(ss, gerund)
      table.insert(ss, ':\n')
    end
  end
  table.insert(ss, e.message)
  if not e.nostack and opts.stack then
    table.insert(ss, '\nstack trace:')
    for _, fr in ipairs(e.stack) do
      table.insert(ss, '\n\t')
      table.insert(ss, fr)
    end
  end
  if e.triggers then
    for _, e2 in ipairs(e.triggers) do
      table.insert(ss, '\nwhile handling: ')
      exc_render_to(e2, ss, opts)
    end
  end
end; exc_.render_to = exc_render_to

local function exc_render(e, opts)
  local ss = {}
  exc_render_to(e, ss, opts)
  return table.concat(ss)
end; exc_.render = exc_render

local exc_mt = {
  __index = exc_,
  __tostring = exc_render,
}

local function showframe(info)
  local s = info.short_src..':'
  if info.currentline ~= -1 then s = s..info.currentline..':' end
  if info.name then
    s = s..' function '..info.name
  else
    if info.what == 'C' then
      s = s..' '..string.format('%p', info.func)
    elseif info.what == 'main' then
      s = s..' main chunk'
    else
      s = s..' function <anonymous'
      if info.currentline then
        s = s..':'..info.linedefined..'-'..info.lastlinedefined
      end
      s = s..'>'
    end
  end
  return s
end

local function stacktrace(level)
  local fs = {}
  while true do
    level = level+1
    local info = debug.getinfo(level, 'nSlf')
    if not info then break end
    table.insert(fs, info)
  end
  local tr = {}
  local i = 1
  if i <= #fs and fs[i].what == 'C'
              and fs[i].name == 'error' then i = i+1 end
  while i < #fs do
    local j = i
    local show = true
    if j < #fs and fs[j].what == 'C'
               and fs[j].name == 'pcall' then j = j+1 end
    if j < #fs then
      if    fs[j].func == exc.pcall
        or  fs[j].func == exc.try_catch
        or  fs[j].func == exc.try_finally
        or  fs[j].func == exc.exit_on_exception
      then show = false end
    end
    while i <= j do
      if show then table.insert(tr, showframe(fs[i])) end
      i = i+1
    end
  end
  return tr
end

local function mkexc(message, level)
  return setmetatable({
    message = message,
    stack   = stacktrace(level + 1),
  }, exc_mt)
end

function exc.pcall(fn, ...)
  local args = {...}
  return xpcall(function()
    return fn(unpack(args))
  end, function(err)
    if type(err) == 'table' and getmetatable(err) == exc_mt then
      return err
    else
      return mkexc(err, 1)
    end
  end)
end

function exc.try_catch_finally(thunk, handler, finally)
  local ok, err = exc.pcall(thunk)
  if ok then
    if finally then finally() end
    return err -- non-error result
  else
    local ok2, err2 = exc.pcall(handler, err)
    if finally then finally() end
    if ok2 then
      return err2 -- non-error result
    end
    if err2.rethrown then
      err2.rethrown = false
    else
      err2.triggers = err2.triggers or {}
      table.insert(err2.triggers, err)
    end
    error(err2, 0) -- rethrow
  end
end

exc.try_catch = exc.try_catch_finally

function exc.try_finally(thunk, finally)
  return exc.try_catch_finally(thunk, function(e) e:rethrow() end, finally)
end

function exc.context(thunk, ...)
  local gerund = string.format(...)
  return exc.try_catch(thunk, function(e)
    e:add_context(gerund)
    e:rethrow()
  end)
end

function exc.exit_on_exception(thunk)
  exc.try_catch(thunk, function(e)
    io.stderr:write(tostring(e), '\n')
    os.exit(1)
  end)
end

function exc.throw(...)
  local err = mkexc(string.format(...), 2)
  err.nostack = true
  error(err, 0)
end

function exc.assert(x, err, ...)
  if not x then
    if not err then
      err = 'assertion failed'
    elseif type(err) == 'string' and select('#', ...) > 0 then
      err = string.format(err, ...)
    end
    error(mkexc(err, 2), 0)
  end
  return x
end

return exc
