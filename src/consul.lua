local http   = require("socket.http")
local ltn12  = require("ltn12")
local cjson  = require("cjson.safe")
local base64 = require("base64")

-- module config
local _M = {
    version = "0.01",
    kv      = { api = "/v1/kv" },
    catalog = { api = "/v1/catalog" },
    health  = { api = "/v1/health" },
}

-- interact with consul api
local function callConsul (self, api, input, method)
    -- add datacenter if specified
    if self.dc then api = api .. "?dc=" .. self.dc end

    -- response body
    local output = {}

    -- build request
    local request = {
        url     = self.url .. api,
        method  = method or "GET",
        sink    = ltn12.sink.table(output),
        headers = { accept = "application/json" },
    }

    -- set create option if specified
    if self.create then
        request.create = self.create
    end

    -- set timeout
    http.TIMEOUT = self.timeout

    -- add input if specified and valid
    if input and type(input) == "string" and string.len(input) > 0 then
        request.source = ltn12.source.string(input)
        request.headers["content-length"] = string.len(input)
    end

    -- execute request
    local response, status = http.request(request)

    -- check return
    if not response then
        -- error out
        return nil, "Failed to execute request."
    end

    -- check status
    if not status or status ~= 200 then
        -- error out
        return nil, "Failed to execute request.  Consul returned: " .. status
    end

    -- validate output
    if not output or not output[response] or #output[response] < 0 then
        -- error out
        return nil, "Failed to execute request.  Consul returned empty response."
    end

    -- decode response output
    local decoder = cjson.new()
    local data, err = decoder.decode(output[response])

    -- check return
    if not data or err ~= nil then
        -- error out
        return nil, err
    end

    -- all okay
    return data, nil
end

-- create new object
function _M:new (o)
    local o   = o or {} -- create table if not passed
    o.dc      = o.dc or nil
    o.addr    = o.addr or os.getenv("CONSUL_HTTP_ADDR") or "127.0.0.1:8500"
    o.url     = "http://" .. o.addr
    o.create  = o.create or nil
    o.timeout = o.timeout or 15
    -- set self
    setmetatable(o, self)
    self.__index = self
    -- return table
    return o
end

-- get a key/value
function _M:kvGet (key, decode)
    -- build call
    local api = self.kv.api .. "/" .. key

    -- make request
    local data, err = callConsul(self, api)

    -- check data and error
    if not data or err ~= nil then
        return nil, err
    end

    -- attempt base64 decoding if asked
    if decode then
        for _, entry in ipairs(data) do
            if type(entry.Value) == "string" then
                local decoded = base64.decode(entry.Value)
                if decoded then
                    entry.Value = decoded
                end
            end
        end
    end

    -- return data
    return data, nil
end

-- list all keys under a prefix
function _M:kvKeys (prefix)
    -- build call
    local api = self.kv.api .. "/" .. prefix .. "?keys"

    -- make request
    local data, err = callConsul(self, api)

    -- check data and error
    if not data or err ~= nil then
        return nil, err
    end

    -- return data
    return data, nil
end

-- write a key/value
function _M:kvPut (key, value)
    -- build call
    local api = self.kv.api .. "/" .. key

    -- make request
    local data, err = callConsul(self, api, value, "PUT")

    -- check data and error
    if not data or err ~= nil then
        return nil, err
    end

    -- return data
    return data, nil
end

-- delete a key or prefix
function _M:kvDelete (key, recurse)
    -- build call
    local api = self.kv.api .. "/" .. key
    if recurse then api = api .. "?recurse" end

    -- make request
    local data, err = callConsul(self, api, nil, "DELETE")

    -- check data and error
    if not resp or err then
        return nil, err
    end

    -- return data
    return data, nil
end

-- query health of the given node
function _M:healthNode (node)
    -- build call
    local api = self.health.api .. "/node/" .. node

    -- make request
    local data, err = callConsul(self, api)

    -- check data and error
    if not data or err ~= nil then
        return nil, err
    end

    -- return data
    return data, nil
end

-- query checks associated with a service
function _M:healthChecks (service)
    -- build call
    local api = self.health.api .. "/checks/" .. service

    -- make request
    local data, err = callConsul(self, api)

    -- check data and error
    if not data or err ~= nil then
        return nil, err
    end

    -- return data
    return data, nil
end

-- query the health of a service
function _M:healthService (service, passing, tag)
    -- build call
    local api = self.health.api .. "/service/" .. service
    if passing then api = api .. "?passing" end
    if tag then api = api .. "?tag=" .. tag end

    -- make request
    local data, err = callConsul(self, api)

    -- check data and error
    if not data or err ~= nil then
        return nil, err
    end

    -- return data
    return data, nil
end

-- query checks in given state
function _M:healthState (state)
    -- build call
    local state = state or "any"
    local api = self.health.api .. "/state/" .. state

    -- make request
    local data, err = callConsul(self, api)

    -- check data and error
    if not data or err ~= nil then
        return nil, err
    end

    -- return data
    return data, nil
end

-- list available datacenters
function _M:catalogDatacenters ()
    -- build call
    local api = self.catalog.api .. "/datacenters"

    -- make request
    local data, err = callConsul(self, api)

    -- check data and error
    if not data or err ~= nil then
        return nil, err
    end

    -- return data
    return data, nil
end

-- list available nodes
function _M:catalogNodes ()
    -- build call
    local api = self.catalog.api .. "/nodes"

    -- make request
    local data, err = callConsul(self, api)

    -- check data and error
    if not data or err ~= nil then
        return nil, err
    end

    -- return data
    return data, nil
end

-- query a specific node
function _M:catalogNode (node)
    -- build call
    local api = self.catalog.api .. "/node/" .. node

    -- make request
    local data, err = callConsul(self, api)

    -- check data and error
    if not data or err ~= nil then
        return nil, err
    end

    -- return data
    return data, nil
end

-- list available services
function _M:catalogServices ()
    -- build call
    local api = self.catalog.api .. "/services"

    -- make request
    local data, err = callConsul(self, api)

    -- check data and error
    if not data or err ~= nil then
        return nil, err
    end

    -- return data
    return data, nil
end

-- query a specific service
function _M:catalogService (service)
    -- build call
    local api = self.catalog.api .. "/service/" .. service

    -- make request
    local data, err = callConsul(self, api)

    -- check data and error
    if not data or err ~= nil then
        return nil, err
    end

    -- return data
    return data, nil
end

-- return module table
return _M
