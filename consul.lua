--[[
        Module for working with consul HTTP API.

    Variables: 

        consul.url - this one is built upon initialisation, 
                     based on the environment variables CONSUL_DOMAIN and CONSUL_PORT,
                     or, if there are none, on the defaults '8500' and 'consul'
        consul.domain - built upon init, based on the envrionment vars CONSUL_DOMAIN or default 'consul' 

        consul.body - response body after performing an API request. Although consul provides responses in json,
                      in lua terms it's just a string. We use cjson.decode to convert json string into a lua table, 
                      and cjson.encode to convert a lua table into a string with proper json. 

        consul.status - response status after the request (number)
        consul.headers - response headers after the request

    Functions:

        consul:get( key, [raw] ) - 
        consul:get_keys( prefix ) -
        consul:put( key, value ) - 
        consul:delete( key ) - 

        consul:health_service( service, [tag] ) -
        consul:health_state( state ) -                                                                                                                    ]]--

local http = require("socket.http")
local url = require("socket.url")
local ltn12 = require("ltn12")
local cjson = require("cjson")
local utils = require("utils")

local consul = {}

consul.domain = os.getenv("CONSUL_DOMAIN") or "consul"

if consul.url = os.getenv("CONSUL_URL") then
    local parsed_url = url.parse(consul.url)
    consul.port = parsed.url.port
    consul.scheme = parsed.url.scheme
else
    consul.port = os.getenv("CONSUL_PORT") or "8500"
    consul.scheme = "http"
    consul.url = consul.scheme .. '://consul.service.' .. consul.domain .. ':' .. consul.port
end

if consul.scheme == "https" then local http = require("ssl.https") end

consul.get = function( self, key, raw )

    local api = "/v1/kv/" .. key 
    if raw then api = api .. "?raw" end
    self.body, self.status, self.headers = http.request( consul.url .. api)
    return self.body

end

consul.get_keys = function ( self, prefix )

    local api = "/v1/kv/" .. prefix .. "?keys"
    self.body, self.status, self.headers = http.request( consul.url .. api ) 

end

consul.put = function (self, key, value )

    local body = {}
    local api = "/v1/kv/" .. key
    
    local code, status, headers = http.request({ url = consul.url .. api, method = "PUT",
                   headers = { ["Content-Length"] = string.len(value) }, source = ltn12.source.string(value),
                   sink = ltn12.sink.table(body)
                 })

    if code then 
        self.status = status; self.header = headers; self.body = body 
    else
        return false
    end

end

consul.delete = function (self, key)

    local body = {}
    local api = "/v1/kv/" .. key
    local code, status, headers = http.request({ url = consul.url .. api, method = "DELETE", sink = ltn12.sink.table(body) })
    if code then 
        self.status = status; self.header = headers; self.body = body 
    else
        return false
    end

end

consul.health_service = function( self, service, tag )

    local api = "/v1/health/service/" .. service 
    if tag then api = api .. "?tag=" .. tag end

    self.body, self.status, self.headers = http.request( consul.url .. api)

end

consul.health_state = function( self, state )

    local state = state or "any"
    local api = "/v1/health/state/" .. state 
    self.body, self.status, self.headers = http.request( consul.url .. api) 

end

consul.report = function( self )                                                                                                                                  

    print ("STATUS = " .. self.status)
    print ("----HEADERS-----")
    utils:dprint(self.headers)
    print ("----HEADERS-----")
    utils:dprint(self.body)

end

return consul
