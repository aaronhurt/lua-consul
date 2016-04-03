package = "consul"
 version = "0.2-0"
 source = {
    url = "",
    dir = "",
    tag = "",
 }
 description = {
    summary = "Module for working with consul HTTP API",
    detailed = [[
        Lua module to interact with consul (http://consul.io) HTTP API
    ]],
    homepage = "https://github.com/leprechau/lua-consul",
    license = "BSD"
 }
 dependencies = {
    "lua >= 5.1",
    "luasocket >= 2.9",
    "lua-cjson >= 2.1",
    "lbase64 >= 20120807-3"
 }
 build = {
    type = "builtin",
    modules = {
       consul = "src/consul.lua"
    }
 }
