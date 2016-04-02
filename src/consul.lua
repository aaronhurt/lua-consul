local http   = require("socket.http")
local ltn12  = require("ltn12")
local cjson  = require("cjson")
local base64 = require("base64")

-- module config
local _M = {
    version = "0.01",
    kv      = { api = "/v1/kv" },
    catalog = { api = "/v1/catalog" },
    health  = { api = "/v1/health" },
}

-- create new objects
function _M:new (o)
    local o  = o or {} -- create table if not passed
    o.dc     = o.dc or nil
    o.addr   = o.addr or os.getenv("CONSUL_HTTP_ADDR") or "127.0.0.1:8500"
    o.url    = "http://" .. o.addr
    o.cjson  = cjson:new()
    -- set self
    setmetatable(o, self)
    self.__index = self
    -- return table
    return o
end

-- get a key/value
function _M:kvGet (key, decode)
    local api = self.kv.api .. "/" .. key
    if self.dc then api = api .. "?dc=" .. self.dc end
    self.body, self.status, self.headers = http.request(self.url .. api)
    if self.status == 200 then
        self.data = self.cjson.decode(self.body)
        if decode then
            for _, entry in ipairs(self.data) do
                if type(entry.Value) == "string" then
                    entry.Value = base64.decode(entry.Value)
                end
            end
        end
        return self.data
    else
        return false
    end
end

-- list all keys under a prefix
function _M:kvKeys (prefix)
    local api = self.kv.api .. "/" .. prefix .. "?keys"
    if self.dc then api = api .. "?dc=" .. self.dc end
    self.body, self.status, self.headers = http.request(self.url .. api)
    if self.status == 200 then
        self.data = self.cjson.decode(self.body)
        return self.data
    else
        return false
    end
end

-- write a key/value
function _M:kvPut (key, value)
    local body = {}
    local api = self.kv.api .. "/" .. key
    if self.dc then api = api .. "?dc=" .. self.dc end

    local code, status, headers = http.request({
        url = self.url .. api,
        method = "PUT",
        headers = {
            ["Content-Length"] = string.len(value)
        },
        source = ltn12.source.string(value),
        sink = ltn12.sink.table(body)
    })

    if code then
        self.status = status; self.header = headers; self.body = body
        return true
    else
        self.status = ""; self.header = ""; self.body = ""
        return false
    end
end

-- delete a key or prefix
function _M:kvDelete (key, recurse)
    local body = {}
    local api = self.kv.api .. "/" .. key
    if recurse then api = api .. "?recurse" end
    if self.dc then api = api .. "?dc=" .. self.dc end

    local code, status, headers = http.request({
        url = self.url .. api,
        method = "DELETE",
        sink = ltn12.sink.table(body)
    })

    if code then
        self.status = status; self.header = headers; self.body = body
        return true
    else
        self.status = ""; self.header = ""; self.body = ""
        return false
    end
end

-- query health of the given node
function _M:healthNode (node)
    local api = self.health.api .. "/node/" .. node
    if self.dc then api = api .. "?dc=" .. self.dc end
    self.body, self.status, self.headers = http.request(self.url .. api)
    if self.status == 200 then
        self.data = self.cjson.decode(self.body)
        return self.data
    else
        return false
    end
end

-- query checks associated with a service
function _M:healthChecks(service)
    local api = self.health.api .. "/checks/" .. service
    self.body, self.status, self.headers = http.request(self.url .. api)
    if self.status == 200 then
        self.data = self.cjson.decode(self.body)
        return self.data
    else
        return false
    end
end

-- query the health of a service
function _M:healthService(service, passing, tag)
    local api = self.health.api .. "/service/" .. service
    if tag then api = api .. "?tag=" .. tag end
    if passing then api = api .. "?passing" end
    if self.dc then api = api .. "?dc=" .. self.dc end
    self.body, self.status, self.headers = http.request(self.url .. api)
    if self.status == 200 then
        self.data = self.cjson.decode(self.body)
        return self.data
    else
        return false
    end
end

-- query checks in given state
function _M:healthState (state)
    local state = state or "any"
    local api = self.health.api .. "/state/" .. state
    if self.dc then api = api .. "?dc=" .. self.dc end
    self.body, self.status, self.headers = http.request(self.url .. api)
    if self.status == 200 then
        self.data = self.cjson.decode(self.body)
        return self.data
    else
        return false
    end
end

-- list available datacenters
function _M:catalogDatacenters ()
    local api = self.catalog.api .. "/datacenters"
    self.body, self.status, self.headers = http.request(self.url .. api)
    if self.status == 200 then
        self.data = self.cjson.decode(self.body)
        return self.data
    else
        return false
    end
end

-- list available nodes
function _M:catalogNodes ()
    local api = self.catalog.api .. "/nodes"
    if self.dc then api = api .. "?dc=" .. self.dc end
    self.body, self.status, self.headers = http.request(self.url .. api)
    if self.status == 200 then
        self.data = self.cjson.decode(self.body)
        return self.data
    else
        return false
    end
end

-- query a specific node
function _M:catalogNode (node)
    local api = self.catalog.api .. "/node/" .. node
    if self.dc then api = api .. "?dc=" .. self.dc end
    self.body, self.status, self.headers = http.request(self.url .. api)
    if self.status == 200 then
        self.data = self.cjson.decode(self.body)
        return self.data
    else
        return false
    end
end

-- list available services
function _M:catalogServices ()
    local api = self.catalog.api .. "/services"
    if self.dc then api = api .. "?dc=" .. self.dc end
    self.body, self.status, self.headers = http.request(self.url .. api)
    if self.status == 200 then
        self.data = self.cjson.decode(self.body)
        return self.data
    else
        return false
    end
end

-- query a specific service
function _M:catalogService (service)
    local api = self.catalog.api .. "/service/" .. service
    if self.dc then api = api .. "?dc=" .. self.dc end
    self.body, self.status, self.headers = http.request(self.url .. api)
    if self.status == 200 then
        self.data = self.cjson.decode(self.body)
        return self.data
    else
        return false
    end
end

-- return module table
return _M
