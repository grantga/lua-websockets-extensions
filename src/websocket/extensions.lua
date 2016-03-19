------------------------------------------------------------------
--
--  Author: Alexey Melnichuk <alexeymelnichuck@gmail.com>
--
--  Copyright (C) 2016 Alexey Melnichuk <alexeymelnichuck@gmail.com>
--
--  Licensed according to the included 'LICENSE' document
--
--  This file is part of lua-websockets-extensions library.
--
------------------------------------------------------------------

local function class(base)
  local t = base and setmetatable({}, base) or {}
  t.__index = t
  t.__class = t
  t.__base  = base

  function t.new(...)
    local o = setmetatable({}, t)
    if o.__init then
      if t == ... then -- we call as Class:new()
        return o:__init(select(2, ...))
      else             -- we call as Class.new()
        return o:__init(...)
      end
    end
    return o
  end

  return t
end

local function tappend(t, v)
  t[#t+1]=v
  return t
end

------------------------------------------------------------------
local split = {} do
function split.iter(str, sep, plain)
  local b, eol = 0
  return function()
    if b > #str then
      if eol then eol = nil return "" end
      return
    end

    local e, e2 = string.find(str, sep, b, plain)
    if e then
      local s = string.sub(str, b, e-1)
      b = e2 + 1
      if b > #str then eol = true end
      return s
    end

    local s = string.sub(str, b)
    b = #str + 1
    return s
  end
end

function split.first(str, sep, plain)
  local e, e2 = string.find(str, sep, nil, plain)
  if e then
    return string.sub(str, 1, e - 1), string.sub(str, e2 + 1)
  end
  return str
end
end
------------------------------------------------------------------

------------------------------------------------------------------
local encode_header, decode_header 
local decode_header_native, decode_header_lpeg
do

local function happend(t, v)
  if not t then return v end
  if type(t)=='table' then
    return tappend(t, v)
  end
  return {t, v}
end

local function trim(s)
  return string.match(s, "^%s*(.-)%s*$")
end

local function itrim(t)
  for i = 1, #t do t[i] = trim(t[i]) end
  return t
end

local function prequre(...)
  local ok, mod = pcall(require, ...)
  if not ok then return nil, mod, ... end
  return mod, ...
end

local function unquote(s)
  if string.sub(s, 1, 1) == '"' then
    s = string.sub(s, 2, -2)
    s = string.gsub(s, "\\(.)", "%1")
  end
  return s
end

local function enqute(s)
  if string.find(s, '[ ",;]') then
    s = '"' .. string.gsub(s, '"', '\\"') .. '"'
  end
  return s
end

decode_header_native = function (str)
  -- does not support `,` or `;` in values

  if not str then return end

  local res = {}
  for ext in split.iter(str, "%s*,%s*") do
    local name, tail = split.first(ext, '%s*;%s*')
    if #name > 0 then
      local opt  = {}
      if tail then
        for param in split.iter(tail, '%s*;%s*') do
          local k, v = split.first(param, '%s*=%s*')
          opt[k] = happend(opt[k], v and unquote(v) or true)
        end
      end
      res[#res + 1] = {name, opt}
    end
  end

  return res
end

local lpeg = prequre 'lpeg' if lpeg then
  local P, C, Cs, Ct, Cp = lpeg.P, lpeg.C, lpeg.Cs, lpeg.Ct, lpeg.Cp
  local nl          = P('\n')
  local any         = P(1)
  local eos         = P(-1)
  local quot        = '"'

  -- split params
  local unquoted    = (any - (nl + P(quot) + P(',') + eos))^1
  local quoted      = P(quot) * ((P('\\') * P(quot) + (any - P(quot)))^0) * P(quot)
  local field       = Cs( (quoted + unquoted)^0 )
  local params      = Ct(field * ( P(',') * field )^0) * (nl + eos) * Cp()

  -- split options
  local quoted_pair = function (ch) return ch:sub(2) end
  local unquoted    = (any - (nl + P(quot) + P(';') + P('=') + eos))^1
  local quoted      = (P(quot) / '') * (
    (
      P('\\') * any / quoted_pair +
      (any - P(quot))
    )^0
  ) * (P(quot) / '')
  local kv          = unquoted * P'=' * (quoted + unquoted)
  local field       = Cs(kv + unquoted)
  local options     = Ct(field * ( P(';') * field )^0) * (nl + eos) * Cp()

  decode_header_lpeg = function(str)
    if not str then return str end

    local h = params:match(str)
    if not h then return nil end

    local res = {}
    for i = 1, #h do
      local o = options:match(h[i])
      if o then
        itrim(o)
        local name, opt = o[1], {}
        for j = 2, #o do
          local k, v = split.first(o[j], '%s*=%s*')
          opt[k] = happend(opt[k], v or true)
        end
        res[#res + 1] = {name, opt}
      end
    end

    return res
  end
end

decode_header = decode_header_lpeg or decode_header_native

local function encode_header_options(name, options)
  local str = name
  if options then
    for k, v in pairs(options) do
      if v == true then str = str .. '; ' .. k
      elseif type(v) == 'table' then
        for _, v in ipairs(v) do
          if v == true then str = str .. '; ' .. k
          else str = str .. '; ' .. k .. '=' .. enqute(tostring(v)) end
        end
      else str = str .. '; ' .. k .. '=' .. enqute(tostring(v)) end
    end
  end
  return str
end

encode_header = function (t)
  if not t then return end

  local res = {}
  for _, val in ipairs(t) do
    tappend(res, encode_header_options(val[1], val[2]))
  end

  return table.concat(res, ', ')
end

end
------------------------------------------------------------------

local CONTINUATION  = 0

------------------------------------------------------------------
local Error = class() do

local ERRORS = {
  [-1] = "EINVAL";
}

for k, v in pairs(ERRORS) do Error[v] = k end

function Error:__init(no, name, msg, ext, code, reason)
  self._no     = assert(no)
  self._name   = assert(name or ERRORS[no])
  self._msg    = msg    or ''
  self._ext    = ext    or ''
  return self
end

function Error:cat()    return 'WSEXT'    end

function Error:no()     return self._no   end

function Error:name()   return self._name end

function Error:msg()    return self._msg  end

function Error:ext()    return self._ext  end

function Error:__tostring()
  local fmt 
  if self._ext and #self._ext > 0 then
    fmt = "[%s][%s] %s (%d) - %s"
  else
    fmt = "[%s][%s] %s (%d)"
  end
  return string.format(fmt, self:cat(), self:name(), self:msg(), self:no(), self:ext())
end

function Error:__eq(rhs)
  return self._no == rhs._no
end

end
------------------------------------------------------------------

------------------------------------------------------------------
local Extensions = class() do

function Extensions:__init()
  self._by_name     = {}
  self._extensions  = {}
  self._ext_options = {}

  return self
end

function Extensions:reg(ext, opt)
  local name = ext.name

  if not (ext.rsv1 or ext.rsv2 or ext.rsv3) then
    return
  end

  if self._by_name[name] then
    return
  end

  local id = #self._extensions + 1
  self._by_name[name]     = id
  self._extensions[id]    = ext
  self._ext_options[id]   = opt

  return self
end

-- Generate extension negotiation offer
function Extensions:offer()
  local offer, extensions = {}, {}

  for i = 1, #self._extensions do
    local ext = self._extensions[i]
    local extension = ext.client(self._ext_options[i])
    if extension then
      local off = extension:offer()
      if off then
        extensions[ext.name] = extension
        tappend(offer, {extension.name, off})
      end
    end
  end

  self._offered = extensions

  return encode_header(offer)
end

-- Accept extension negotiation response
function Extensions:accept(params_string)
  if not params_string then return end

  assert(self._offered, 'try accept without offer')

  params = decode_header(params_string)
  if not params then
    return nil, Error.new(Error.EINVAL, nil, 'invalid header value', params_string)
  end

  if #params == 0 then return end

  local active, offered = {}, self._offered
  self._offered = nil

  local rsv1, rsv2, rsv3

  for _, param in ipairs(params) do
    local name, options = param[1], param[2]
    local ext = offered[name]

    if not ext then
      return nil, Error.new(Error.EINVAL, nil, 'not offered extensin', name)
    end

    if (rsv1 and ext.rsv1) or (rsv2 and ext.rsv2) or (rsv2 and ext.rsv2) then
      return nil, Error.new(Error.EINVAL, nil, 'more then one extensin with same rsv bit', name)
    end

    local ok, err = ext:accept(options)
    if not ok then return nil, err end

    offered[name] = nil
    tappend(active, ext)
    rsv1 = rsv1 or ext.rsv1
    rsv2 = rsv2 or ext.rsv2
    rsv3 = rsv3 or ext.rsv3
  end

  for name, ext in pairs(offered) do
    --! @todo close ext
  end

  self._active = active

  return self
end

-- Generate extension negotiation response
function Extensions:response(offers_string)
  if not offers_string then return end

  offers = decode_header(offers_string)
  if not offers then
    return nil, Error.new(Error.EINVAL, nil, 'invalid header value', offers_string)
  end

  local params_by_name = {}
  for _, offer in ipairs(offers) do
    local name, params = offer[1], offer[2]
    if self._by_name[name] then
      params_by_name[name] = params_by_name[name] or {}
      tappend(params_by_name[name], params or {})
    end
  end

  local rsv1, rsv2, rsv3

  local active, response = {}, {}
  for _, offer in ipairs(offers) do
    local name = offer[1]
    local params = params_by_name[name]
    if params then
      params_by_name[name] = nil
      local i              = self._by_name[name]
      local ext            = self._extensions[i]
      -- we accept first extensin with same bits
      if not ((rsv1 and ext.rsv1) or (rsv2 and ext.rsv2) or (rsv2 and ext.rsv2)) then
        local extension  = ext.server(self._ext_options[i])
        -- Client can send invalid or unsupported arguments
        -- if client send invalid arguments then server must close connection
        -- if client send unsupported arguments server should just ignore this extension
        local resp, err = extension:response(params)
        if resp then
          tappend(response, {ext.name, resp})
          tappend(active, extension)
          rsv1 = rsv1 or ext.rsv1
          rsv2 = rsv2 or ext.rsv2
          rsv3 = rsv3 or ext.rsv3
        elseif err then
          return nil, err
        end
      end
    end
  end

  if active[1] then
    self._active = active
    return encode_header(response)
  end
end

function Extensions:validate_frame(opcode, rsv1, rsv2, rsv3)
  local m1, m2, m3

  if self._active then
    for i = 1, #self._active do
      local ext = self._active[i]
      if (ext.rsv1 and rsv1) then m1 = true end
      if (ext.rsv2 and rsv2) then m2 = true end
      if (ext.rsv3 and rsv3) then m3 = true end
    end
  end

  return (m1 or not rsv1) and (m2 or not rsv2) and (m3 or not rsv3)
end

function Extensions:encode(msg, opcode, fin, allows)
  local rsv1, rsv2, rsv3 = false, false, false
  if self._active then
    if allows == nil then allows = true end
    for i = 1, #self._active do
      local ext = self._active[i]
      if (allows ~= false) and ( (allows == true) or (allows[ext.name]) ) then
        local err msg, err  = ext:encode(opcode, msg, fin)
        if not msg then return nil, err end
        rsv1 = rsv1 or ext.rsv1
        rsv2 = rsv2 or ext.rsv2
        rsv3 = rsv3 or ext.rsv3
      end
    end
  end
  if opcode == CONTINUATION then return msg end
  return msg, rsv1, rsv2, rsv3
end

function Extensions:decode(msg, opcode, fin, rsv1, rsv2, rsv3)
  if not (rsv1 or rsv2 or rsv3) then return msg end
  for i = #self._active, 1, -1 do
    local ext = self._active[i]
    if (ext.rsv1 and rsv1) or (ext.rsv2 and rsv2) or (ext.rsv3 and rsv3) then
      local err msg, err = ext:decode(opcode, msg, fin)
      if not msg then return nil, err end
    end
  end
  return msg
end

function Extensions:accepted(name)
  if not self._active then return end

  if name then
    for i = 1, #self._active do
      local ext = self._active[i]
      if ext.name == name then return name, i end
    end
    return
  end

  local res = {}
  for i = 1, #self._active do
    local ext = self._active[i]
    tappend(res, ext.name)
  end
  return res
end

end
------------------------------------------------------------------

return {
  new = Extensions.new;

  -- NOT PUBLIC API
  _decode_header        = decode_header;
  _encode_header        = encode_header;
  _decode_header_lpeg   = decode_header_lpeg;
  _decode_header_native = decode_header_native;
}