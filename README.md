## Synopsis

Fork and rewrite of https://github.com/epicfilemcnulty/lua-consul fixing some obvious ommisions and addition of several missing methods.  The original source seems to be abandoned.

The code has been cleaned up and extensively refactored.  Every function has two returns (data and error).  The data element will be the decoded JSON response from the Consul API and error will always be nil on a successful return.

You can find more information about the basic API structure in the Consul HTTP API documentation.

https://www.consul.io/docs/agent/http.html

### Currently Implemented Calls

```text
consul:new [object]									Make a new module object
consul:kvGet <key>, [decode]						Get a key/value and optionally base64 decode
consul:kvKeys <prefix>								Get a list of keys under a given prefix
consul:kvPut <key>, <value>							Write a key/value to the Consul store
consul:kvDelete <key>, [recurse]					Delete a key and optionally recurse down the prefix
consul:healthNode <node>							Get the health of the given node
consul:healthChecks <service>						Get all health checks associated with a given node
consul:healthService <service>, [passing], [tag]	Return the health of the given service
consul:healthState [state]							Return all checks of the given state (default: any)
consul:catalogDatacenters							Obtain a list of all available datacenters
consul:catalogNodes									Obtain a list of all available nodes
consul:catalogNode <node>							Get information on the given node
consul:catalogServices								Obtain a list of all services in the catalog
consul:catalogService <service>						Obtain information about the given service
```

### Installation

The simplest installation method is to use luarocks:
```
$ luarocks install --server=http://luarocks.org/dev lua-consul
```

### Example Usage

Load the package:
```lua
consul = require("consul")
c = consul:new()
```

Get a list of available datacenters:
```lua
dcs, err = c:catalogDatacenters()
if dcs and err == nil then
	for idx, entry in ipairs(dcs) do
		print(idx, entry)
	end
end
```

Returns:
```
1	dc1
2	dc2
```

Query all passing instances of a service:
```lua
svc, err = c:healthService("testing", true)
if svc and err == nil then
	for idx, entry in ipairs(svc) do
		for k1, v1 in pairs(entry) do
			for k2, v2 in pairs(v1) do 
				print(idx, k1, k2, v2)
			end
		end
	end
end
```

Returns:
```
1	Node	CreateIndex	3030615
1	Node	ModifyIndex	3274460
1	Node	Node	docker1
1	Node	TaggedAddresses	table: 0x7fca68d05780
1	Node	Address	10.20.10.80
1	Checks	1	table: 0x7fca68d064b0
1	Checks	2	table: 0x7fca68d064f0
1	Service	Tags	table: 0x7fca68d06220
1	Service	EnableTagOverride	false
1	Service	ModifyIndex	3274081
1	Service	Service	testing
1	Service	CreateIndex	3274067
1	Service	Port	3002
1	Service	Address	10.20.30.10
1	Service	ID	testing-5d289e964212
2	Node	CreateIndex	3030615
2	Node	ModifyIndex	3274489
2	Node	Node	docker2
2	Node	TaggedAddresses	table: 0x7fca68d06ae0
2	Node	Address	10.20.10.50
2	Checks	1	table: 0x7fca68d07030
2	Checks	2	table: 0x7fca68d07070
2	Service	Tags	table: 0x7fca68d06b20
2	Service	EnableTagOverride	false
2	Service	ModifyIndex	3274044
2	Service	Service	testing
2	Service	CreateIndex	3274028
2	Service	Port	3002
2	Service	Address	10.20.30.70
2	Service	ID	testing-3c10cf042a46
3	Node	CreateIndex	3030615
3	Node	ModifyIndex	3274451
3	Node	Node	docker3
3	Node	TaggedAddresses	table: 0x7fca68d07670
3	Node	Address	10.20.10.60
3	Checks	1	table: 0x7fca68d07c40
3	Checks	2	table: 0x7fca68d07c80
3	Service	Tags	table: 0x7fca68d076b0
3	Service	EnableTagOverride	false
3	Service	ModifyIndex	3274141
3	Service	Service	testing
3	Service	CreateIndex	3274131
3	Service	Port	3002
3	Service	Address	10.20.30.20
3	Service	ID	testing-e09a259bbe2f
```

### HAProxy

In addition to the Consul library there is a proof-of-concept HAProxy integration in this repository.

Basic usage from the main directory:
```
$ haproxy -d -f ./src/haproxy.cfg
Note: setting global.maxconn to 2000.
Available polling systems :
     kqueue : pref=300,  test result OK
       poll : pref=200,  test result OK
     select : pref=150,  test result FAILED
Total: 3 (2 usable), will use kqueue.
Using kqueue() as the polling mechanism.
[debug] 093/214104 (21861) : Loading service catalog from 127.0.0.1:8500
[debug] 093/214105 (21861) : Loaded 12 services from catalog

... request from another client ...

00000000:main.accept(0005)=0007 from [127.0.0.1:53642]
00000000:main.clireq[0007:ffffffff]: GET /test/test.php HTTP/1.1
00000000:main.clihdr[0007:ffffffff]: Host: localhost:10001
00000000:main.clihdr[0007:ffffffff]: User-Agent: curl/7.43.0
00000000:main.clihdr[0007:ffffffff]: Accept: */*
[debug] 093/214113 (21861) : checking path /test/test.php for svc: testyTest
[debug] 093/214113 (21861) : checking path /test/test.php for svc: someService
[debug] 093/214113 (21861) : checking path /test/test.php for svc: anotherService
[debug] 093/214113 (21861) : checking path /test/test.php for svc: test
[debug] 093/214113 (21861) : found match - setting addr to 10.27.18.115:8081
[debug] 093/214113 (21861) : set uri: http://10.27.18.115:8081/test/test.php
00000000:dynamic.srvrep[0007:0008]: HTTP/1.1 200 OK
00000000:dynamic.srvhdr[0007:0008]: Server: nginx/1.8.1
00000000:dynamic.srvhdr[0007:0008]: Date: Mon, 04 Apr 2016 02:48:04 GMT
00000000:dynamic.srvhdr[0007:0008]: Content-Type: text/html
00000000:dynamic.srvhdr[0007:0008]: Transfer-Encoding: chunked
00000000:dynamic.srvhdr[0007:0008]: Connection: keep-alive
00000000:dynamic.srvhdr[0007:0008]: X-Powered-By: PHP/5.4.19
00000000:dynamic.srvhdr[0007:0008]: Set-Cookie: PHPSessionID=hha7hd7td3bldcc9gruj8jqf76; path=/
00000000:dynamic.srvhdr[0007:0008]: Expires: Thu, 19 Nov 1981 08:52:00 GMT
00000000:dynamic.srvhdr[0007:0008]: Cache-Control: no-store, no-cache, must-revalidate, post-check=0, pre-check=0
00000000:dynamic.srvhdr[0007:0008]: Pragma: no-cache
00000001:main.clicls[0007:0008]
00000001:main.closed[0007:0008]
```

Testing from another window:
```
$ curl -vvv http://localhost:10001/test/test.php
*   Trying 127.0.0.1...
* Connected to localhost (127.0.0.1) port 10001 (#0)
> GET /cwp/ws.php HTTP/1.1
> Host: localhost:10001
> User-Agent: curl/7.43.0
> Accept: */*
>
< HTTP/1.1 200 OK
< Server: nginx/1.8.1
< Date: Mon, 04 Apr 2016 02:50:23 GMT
< Content-Type: text/html
< Transfer-Encoding: chunked
< X-Powered-By: PHP/5.4.19
< Set-Cookie: PHPSessionID=hha7hd7td3bldcc9gruj8jqf76; path=/
< Expires: Thu, 19 Nov 1981 08:52:00 GMT
< Cache-Control: no-store, no-cache, must-revalidate, post-check=0, pre-check=0
< Pragma: no-cache
<
<!DOCTYPE html>
<html lang="en">
<head>
    <title>TEST</title>
    <meta charset="UTF-8" />
</head>
<body>
    Hello World!
</body>
</html>

* Connection #0 to host localhost left intact
```

### TODO

* Complete additional Consul methods
* Further develop and test the HAProxy integration
