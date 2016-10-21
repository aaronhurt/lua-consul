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

-- Execute Consul API commands.
-- Executes calls against the Consul HTTP API and
-- handles the result(s) including JSON decoding.
-- @param self    Module object
-- @param api     The complete API call string
-- @param input   Optional input body to the API request
-- @param method  Optional HTTP method - defaults to GET
-- @return        Result and error or nil
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
    if input then
        if type(input) == "string" then
            request.source = ltn12.source.string(input)
            request.headers["content-length"] = string.len(input)
        else
            -- error out - we only support strings
            return nil, "Invalid non-string input"
        end
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
        return nil, tostring(err)
    end

    -- all okay
    return data, nil
end

-- Create a module object.
-- Creates a module object from scratch or optionally
-- based on another passed object.  The following object
-- members are accepted:
-- dc        Optional datacenter attribute - default nil
-- addr      Optional Consul connection address - defaults to CONSUL_HTTP_ADDR
--           from environment or 127.0.0.1:8500
-- url       Optional url override - defaults to http://<addr>
-- create    Optional http request.create function
-- timeout   Optional http request timeout - defaults to 15 seconds
-- @param o  Optional object settings
-- @return   Module object
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

-- Get a key/value pair.
-- @param key     The key name to retrieve
-- @param decode  Optionally base64 decode values
-- @return        Result and error or nil
function _M:kvGet (key, decode)
    -- build call
    local api = self.kv.api .. "/" .. key

    -- make request
    local data, err = callConsul(self, api)

    -- attempt base64 decoding if asked
    if data and err == nil and decode then
        for _, entry in ipairs(data) do
            if type(entry.Value) == "string" then
                local decoded = base64.decode(entry.Value)
                if decoded then
                    entry.Value = decoded
                end
            end
        end
    end

    -- return result
    return data, err
end

-- List all keys under a prefix.
-- @param prefix  The k/v prefix to list
-- @return        Result and error or nil
function _M:kvKeys (prefix)
    -- build call
    local api = self.kv.api .. "/" .. prefix .. "?keys"

    -- make request
    return callConsul(self, api)
end

-- Write a key/value pair.
-- @param key     The key name to write
-- @param value   The string value to write
-- @return        Result and error or nil
function _M:kvPut (key, value)
    -- build call
    local api = self.kv.api .. "/" .. key

    -- make request
    return callConsul(self, api, value, "PUT")
end

-- Delete a key or prefix.
-- @param key      The key name or prefix to delete
-- @param recurse  Optionally delete all keys under the given prefix
-- @return         Result and error or nil
function _M:kvDelete (key, recurse)
    -- build call
    local api = self.kv.api .. "/" .. key
    if recurse then api = api .. "?recurse" end

    -- make request
    return callConsul(self, api, nil, "DELETE")
end

-- Query health of the given node.
-- @param node  The node to query
-- @return      Result and error or nil
function _M:healthNode (node)
    -- build call
    local api = self.health.api .. "/node/" .. node

    -- make request
    return callConsul(self, api)
end

-- Query checks associated with a service.
-- @param service  The service to query
-- @return         Result and error or nil
function _M:healthChecks (service)
    -- build call
    local api = self.health.api .. "/checks/" .. service

    -- make request
    return callConsul(self, api)
end

-- Query the health of a service.
-- @param service  The service to query
-- @param passing  Optionally only return passing
-- @param tag      Optionally filter to specific tags
-- @return         Result and error or nil
function _M:healthService (service, passing, tag)
    -- build call
    local api = self.health.api .. "/service/" .. service
    if passing then api = api .. "?passing" end
    if tag then api = api .. "?tag=" .. tag end

    -- make request
    return callConsul(self, api)
end

-- Query checks in given state.
-- @param state  The state to query - defaults to any
-- @return       Result and error or nil
function _M:healthState (state)
    -- build call
    local state = state or "any"
    local api = self.health.api .. "/state/" .. state

    -- make request
    return callConsul(self, api)
end

-- List available datacenters.
-- @return         Result and error or nil
function _M:catalogDatacenters ()
    -- build call
    local api = self.catalog.api .. "/datacenters"

    -- make request
    return callConsul(self, api)
end

-- List available nodes.
-- @return         Result and error or nil
function _M:catalogNodes ()
    -- build call
    local api = self.catalog.api .. "/nodes"

    -- make request
    return callConsul(self, api)
end

-- Query a specific node.
-- @param node  The node to query
-- @return      Result and error or nil
function _M:catalogNode (node)
    -- build call
    local api = self.catalog.api .. "/node/" .. node

    -- make request
    return callConsul(self, api)
end

-- List available services.
-- @return         Result and error or nil
function _M:catalogServices ()
    -- build call
    local api = self.catalog.api .. "/services"

    -- make request
    return callConsul(self, api)
end

-- Query a specific service.
-- @param service  The service to query
-- @return         Result and error or nil
function _M:catalogService (service)
    -- build call
    local api = self.catalog.api .. "/service/" .. service

    -- make request
    return callConsul(self, api)
end

-- return module table
return _M
