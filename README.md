# lua-websockets-extensions
WebSocket extensions manager

[![Licence](http://img.shields.io/badge/Licence-MIT-brightgreen.svg)](LICENSE)
[![Build Status](https://travis-ci.org/moteus/lua-websockets-extensions.svg?branch=master)](https://travis-ci.org/moteus/lua-websockets-extensions)
[![Coverage Status](https://coveralls.io/repos/github/moteus/lua-websockets-extensions/badge.svg?branch=master)](https://coveralls.io/github/moteus/lua-websockets-extensions?branch=master)

The API is similar to [websocket-extensions](https://github.com/faye/websocket-extensions-node).

``` Lua
extensions = Extensions.new()

-- add extension
extensions:reg(deflate)

-- to update upgrade request 
offer = extension:offer()
ext_header = 'Sec-Websocket-Extensions: ' .. (offer or '')

-- to accept upgrade response
ok, err = extensions:accept(headers['sec-websocket-extensions'])
if not ok then
  if err then
    -- this means there some error in request
    -- e.g. invalid value for option
    -- client should close connection
  else
    -- this means there no 'Sec-Websocket-Extensions' header or it empty
    -- so this connection should not use any extension but it can be estabilished
  end
end

-- to response to upgrade request
response, err = extensions:response(headers['sec-websocket-extensions'])
if response then
  ext_header = 'Sec-Websocket-Extensions: ' .. response
elseif err then
  -- this means there some thing wrong with request
  -- e.g. invalid value for option
  -- server should close connection
end

-- to validate frame
ok = extensions:validate_frame(opcode, rsv1, rsv2, rsv3)
if not ok then
  -- this is invalid frame and connection should be closed
end

-- to decode incoming frame
frame, err = extensions:decode(frame, opcode, fin, rsv1, rsv2, rsv3)
if not frame then
  if err then
    -- this is invalid frame and connection should be closed
  end
end

-- to encode outgoing frame
-- allows - can be true or mask to be able select which extensions use
frame, rsv1, rsv2, rsv3 = extensions:encode(frame, opcode, fin, allows)
```