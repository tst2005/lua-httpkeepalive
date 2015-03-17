local _M = {}

local setmetatable = setmetatable
local table = table
local table_concat = assert(table.concat)

local __cache = {}

local function debuglog(...)
	local handler = _M.debug
	if handler then
		handler(...)
	end
end

local function hashthis(...)
        local t = {}
        for k,v in pairs({...}) do
                t[#t+1] = tostring(v)
        end
        return table_concat(t, ":")
end

local function cache_unset(...)
	local hash = hashthis(...)
	__cache[hash] = nil
end                                                                                                                                                                                              

local function cache_raw_get(...)
	local hash = hashthis(...)
	return __cache[hash]
end

local function cache_get(...)
	local cached = cache_raw_get(...)
	if cached then
		if not _M.outdated or not _M.outdated(cached) then
			return cached
		end
		--cached:close()
		cache_unset(...)
	end
	return nil
end



local function cache_set(sock, ...)
	local hash = hashthis(...)
	if __cache[hash] then
		if __cache[hash] ~= sock then
			debuglog("DEBUG: HMMM socket cache already exists", __cache[hash], sock)
			__cache[hash]:close() -- catch error
			__cache[hash] = sock
		else
			debuglog("DEBUG: overwrite socket cache by it self ?!")
		end
	else
		__cache[hash] = sock
	end
end

_M.get = cache_get
_M.set = cache_set
_M.unset = cache_unset

_M.outdated = nil
_M.debug = nil

return _M
