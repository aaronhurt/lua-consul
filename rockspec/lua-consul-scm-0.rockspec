package = "lua-consul"
 version = "scm-0"
 source = {
    url = "https://github.com/leprechau/lua-consul/archive/master.zip",
    dir = "lua-consul-master",
 }
 description = {
    summary = "Module for interacting with the Consul HTTP API",
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
