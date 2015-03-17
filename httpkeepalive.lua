

-- TsT 20121124 0.0.1
local VERSION = "0.0.1"

local _M = {}
_M._VERSION = VERSION

--local socket = require "socket"
local http = require "socket.http"
local ltn12 = require "ltn12"
--local ssl = require "ssl"

local cache = require("lua-httpkeepalive.uglycache")
local cache_get = cache.get
local cache_set = cache.set
local cache_unset = cache.unset

local try = assert(require("socket").try)
--local protect = socket.protect

local setmetatable = setmetatable
local table = require("table")


-- http://w3.impa.br/~diego/software/luasocket/tcp.html#getstats
-- http://w3.impa.br/~diego/software/luasocket/tcp.html#setoption
--[[
client:setoption(option [, value])
server:setoption(option [, value])

Sets options for the TCP object. Options are only needed by low-level or time-critical applications. You should only modify an option if you are sure you need it.

Option is a string with the option name, and value depends on the option being set:

    'keepalive': Setting this option to true enables the periodic transmission of messages on a connected socket. Should the connected party fail to respond to these messages, the connection is considered broken and processes using the socket are notified;
    'linger': Controls the action taken when unsent data are queued on a socket and a close is performed. The value is a table with a boolean entry 'on' and a numeric entry for the time interval 'timeout' in seconds. If the 'on' field is set to true, the system will block the process on the close attempt until it is able to transmit the data or until 'timeout' has passed. If 'on' is false and a close is issued, the system will process the close in a manner that allows the process to continue as quickly as possible. I do not advise you to set this to anything other than zero;
    'reuseaddr': Setting this option indicates that the rules used in validating addresses supplied in a call to bind should allow reuse of local addresses;
    'tcp-nodelay': Setting this option to true disables the Nagle's algorithm for the connection. 
]]--

local function fastsocket(s)
	s:setoption('tcp-nodelay', true)
	-- set the timeout here ? :s:settimeout(...)
end

-- FIXME: we need to keep the idle time not the age because the server does not close a old active socket 
cache.outdated = function(sock)
	local _, _, age = sock:getstats()
	if (age >= _M.ttl) then
		sock:close()
		return true
	end
	return false
end

local function create()
	-- create a new socket
	local t = {c=try(socket.tcp())}

	local idx = function (tbl, key)
		--print("idx: tbl", tbl, "key", key)
		return function (prxy, ...)
			local c = prxy.c
			return c[key](c,...)
		end
	end

	function t:connect(host, port)
		local c = self.c
		local cached = cache_get(host, port)
		if cached then -- a socket already exists
			if c ~= cached then
				if c then
					-- close a existing unused tcp master socket
					c:close()
				end
				--print("cache found", cached)
				self.c = cached
			end
		else -- no socket exists, need to create one
			if not c then
				self.c = try(socket.tcp())
			end
			-- set options here
			if _M.tcpkeepalive then
				c:setoption('keepalive', true)
			end
			if _M.fastsocket then
				_M.fastsocket(c)
			end
			try(c:connect(host, port))
			cache_set(c, host, port)
		end

		return 1 -- return 1 => success
	end
	function t:close(...)
		--print("close call dropped!", self)
		--try(self.c:close())
	end

	return setmetatable(t, {__index = idx})
end

local function postUtil(req, postBody)
	assert(req, "'req' table must be setted")

	local method = req.method
	if method and method ~= "POST" then
		--error("method is not POST")
		return req
	end
	if method == "POST" and not postBody then
		error("POST request without body ?!")
	end

	if postBody then
		local headers = req.headers or {}
		req.headers = headers

		req.source = ltn12.source.string(postBody)
		headers["content-length"] = #postBody
	end

	return req
end

local function setPostRequest(req)
	local req = req or {}
	if not req.method then
		req.method = "POST"
	end
	return req
end

local function setResponseBody(req, response_body)
	assert(req, "'req' table must be setted")
	if response_body then
		req.sink = ltn12.sink.table(response_body)
	end
	return req
end

local function prepareReq(req)
	assert(req, "'req' table must be setted")

	local headers = req.headers or {}
	req.headers = headers
	headers["Connection"] = "Keep-Alive"

	req.create = create
	return req
end

local function filterReturn(r, c, h)
	if r and c == 200 then
--		local h2 = {}
--		for k,v in pairs(h) do
--			print(k, v)
--			h2[#h2+1] = ("[%s] = '%s'"):format(k,tostring(v))
--		end
--		local h = table.concat(h2, " ; ")
		return r, c, h
	end
	return nil
end

local function httpreq(req, response_body, postBody)
	assert(req, "'req' table must be setted")
	assert(req.url, "'url' field missing in 'req' table")

	req = setPostRequest(req)
	req = postUtil(req, postBody)
	req = setResponseBody(req, response_body)
	req = prepareReq(req)

	return filterReturn(http.request(req))
end


_M.httpreq = httpreq
_M.tcpkeepalive = true
_M.fastsocket = fastsocket
_M.ttl = 50 -- seconds

return _M

