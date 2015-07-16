package = "consul"
 version = "0.1-2"
 source = {
    url = "git://github.com/me/luafruits",
    tag = "v0.1-2",
 }
 description = {
    summary = "Module for working with consul HTTP API",
    detailed = [[
        Lua module to interact with consul (http://consul.io) HTTP API        
    ]],
    homepage = "https://github.com/epicfilemcnulty/lua-consul",
    license = "BSD"
 }
 dependencies = {
    "lua >= 5.1",
    "luasocket >= 2.9",
    "luasec >= 0.5",
    "lua-cjson >= 2.1"
 }
 build = {
    type = "builtin",
    modules = {
       consul = "consul.lua"
    }
 }
