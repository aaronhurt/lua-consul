-- init packages
local http = require("socket.http")
local ltn12 = require("ltn12")
local cjson = require("cjson")
local base64 = require("base64")

-- base object
Consul = {
    -- read environment
    addr = os.getenv("CONSUL_HTTP_ADDR") or "127.0.0.1:8500",
    -- base api paths
    kvApi = "/v1/kv",
    catalogApi = "/v1/catalog",
    healthApi = "/v1/health"
}

-- build object
function Consul:new (o)
    -- create new if not passed
    o = o or {}
    -- build prototype
    setmetatable(o, self)
    self.__index = self
    -- build url
    o.url = 'http://' .. o.addr
    -- return object
    return o
end

-- get a key/value
function Consul:kvGet (key, decode)
    local api = self.kvApi .. "/" .. key 
    if self.dc then api = api .. "?dc=" .. self.dc end
    self.body, self.status, self.headers = http.request(self.url .. api)
    if self.status == 200 then
        self.data = cjson.decode(self.body)
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
function Consul:kvKeys (prefix)
    local api = self.kvApi .. "/" .. prefix .. "?keys"
    if self.dc then api = api .. "?dc=" .. self.dc end
    self.body, self.status, self.headers = http.request(self.url .. api)
    if self.status == 200 then
        self.data = cjson.decode(self.body)
        return self.data
    else
        return false
    end
end

-- write a key/value
function Consul:kvPut (key, value)
    local body = {}
    local api = self.kvApi .. "/" .. key
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
function Consul:kvDelete (key, recurse)
    local body = {}
    local api = self.kvApi .. "/" .. key
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
function Consul:healthNode (node)
    local api = self.healthApi .. "/node/" .. node
    if self.dc then api = api .. "?dc=" .. self.dc end
    self.body, self.status, self.headers = http.request(self.url .. api)
    if self.status == 200 then
        self.data = cjson.decode(self.body)
        return self.data
    else
        return false
    end
end

-- query checks associated with a service
function Consul:healthChecks(service)
    local api = self.healthApi .. "/checks/" .. service 
    self.body, self.status, self.headers = http.request(self.url .. api)
    if self.status == 200 then
        self.data = cjson.decode(self.body)
        return self.data
    else
        return false
    end
end

-- query the health of a service
function Consul:healthService(service, passing, tag)
    local api = self.healthApi .. "/service/" .. service 
    if tag then api = api .. "?tag=" .. tag end
    if passing then api = api .. "?passing" end
    if self.dc then api = api .. "?dc=" .. self.dc end
    self.body, self.status, self.headers = http.request(self.url .. api)
    if self.status == 200 then
        self.data = cjson.decode(self.body)
        return self.data
    else
        return false
    end
end

-- query checks in given state
function Consul:healthState (state)
    local state = state or "any"
    local api = self.healthApi .. "/state/" .. state
    if self.dc then api = api .. "?dc=" .. self.dc end
    self.body, self.status, self.headers = http.request(self.url .. api)
    if self.status == 200 then
        self.data = cjson.decode(self.body)
        return self.data
    else
        return false
    end
end

-- list available datacenters
function Consul:catalogDatacenters ()
    local api = self.catalogApi .. "/datacenters"
    self.body, self.status, self.headers = http.request(self.url .. api)
    if self.status == 200 then
        self.data = cjson.decode(self.body)
        return self.data
    else
        return false
    end
end

-- list available nodes
function Consul:catalogNodes ()
    local api = self.catalogApi .. "/nodes"
    if self.dc then api = api .. "?dc=" .. self.dc end
    self.body, self.status, self.headers = http.request(self.url .. api)
    if self.status == 200 then
        self.data = cjson.decode(self.body)
        return self.data
    else
        return false
    end
end

-- query a specific node
function Consul:catalogNode (node)
    local api = self.catalogApi .. "/node/" .. node
    if self.dc then api = api .. "?dc=" .. self.dc end
    self.body, self.status, self.headers = http.request(self.url .. api)
    if self.status == 200 then
        self.data = cjson.decode(self.body)
        return self.data
    else
        return false
    end
end

-- list available services
function Consul:catalogServices ()
    local api = self.catalogApi .. "/services"
    if self.dc then api = api .. "?dc=" .. self.dc end
    self.body, self.status, self.headers = http.request(self.url .. api)
    if self.status == 200 then
        self.data = cjson.decode(self.body)
        return self.data
    else
        return false
    end
end

-- query a specific service
function Consul:catalogService (service)
    local api = self.catalogApi .. "/service/" .. service
    if self.dc then api = api .. "?dc=" .. self.dc end
    self.body, self.status, self.headers = http.request(self.url .. api)
    if self.status == 200 then
        self.data = cjson.decode(self.body)
        return self.data
    else
        return false
    end
end
