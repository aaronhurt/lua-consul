local consul = require("consul")
local socket = require("socket")

-- time between service updates
local serviceLifetime = 30

-- internal variable definitions
local serviceTable = {}
local lastUpdate = 0

-- search a table for matching values
local function hasValue(tbl, ...)
	local args = {...}
	for _, arg in ipairs(args) do
		for _, val in pairs(tbl) do
			if (arg and arg == val) then
				return true, arg
			end
		end
	end
	return false, nil
end

-- determine the host type of the passed string
local function hostType(host)
	local r = {err = 0, v4 = 1, v6 = 2, string = 3}
	if type(host) ~= "string" then
		return r.err
	end

	-- check for format 1.11.111.111 for ipv4
	local chunks = {host:match("(%d+)%.(%d+)%.(%d+)%.(%d+)")}
	if #chunks == 4 then
		for _, v in pairs(chunks) do
			if tonumber(v) > 255 then
				return r.string
			end
		end
		return r.v4
	end

	-- check for ipv6 format, should be 8 'chunks' of numbers/letters
	-- without trailing chars
	local chunks = {host:match(("([a-fA-F0-9]*):"):rep(8):gsub(":$","$"))}
	if #chunks == 8 then
		for _, v in pairs(chunks) do
			if #v > 0 and tonumber(v, 16) > 65535 then
				return r.string
			end
		end
		return r.v6
	end

	-- non-ip host
	return r.string
end

-- build service address
function hostPort(svc)
	-- get host/address type
	local hType = hostType(svc.Address)
	-- check host type
	if hType == 1 then
		--ipv4 address
		 return string.format("%s:%d", svc.Address, svc.Port), nil
	elseif hType == 2 then
		-- ipv6 address
		return string.format("[%s]:%d", svc.Address, svc.Port), nil
	elseif hType == 3 then
		-- resolve hostname
		local ip, x = socket.dns.toip(svc.Address)
		-- check result
		if ip then
			-- reset service address
			svc.Address = ip
			-- recurse back into this function
			return hostPort(svc)
		else
			-- error out
			return "", string.format("Failed to resolve address %s for %s: %s",
				svc.Address, svc.Service, x)
		end
	end
	-- default return -- we shouldn't get here
	return "", string.format("Failed to build uri for %s (address: %s port: %s)",
		svc.Service, svc.Address, svc.Port)
end

-- load service definitions from consul
function loadServices()
	-- init load timer
	local stime = socket.gettime()

	-- init consul
	local c = consul:new()

	-- debugging
	core.log(core.info,
		string.format("Loading service catalog from %s", c.addr))

	-- get service catalog
	local data, err = c:catalogServices()

	-- check return
	if not data or err ~= nil then
		-- log the error
		core.log(core.err,
			string.format("Failed to retrieve service listing: %s", err))
		return
	end

	-- hand back control before processing
	core.yield()

	-- local service info
	local sdata = {}
	local scount = 0

	-- loop through services
	for svc, tags in pairs(data) do
		local match, matched = hasValue(tags, "proxy-root", "proxy-unique", "proxy-standard")
		if match ~= true then
			-- debugging
			-- core.log(core.debug,
			-- 	string.format("Skipping service %s - no matching proxy tags", svc))
			goto skip
		end
		-- get service health
		entries, err = c:healthService(svc, true)
		-- check return
		if not entries or err ~= nil then
			-- error fetching service
			core.log(core.warning,
				string.format("Failed fetching service health for %s", svc))
			goto skip
		end
		-- loop through service entries
		for _, entry in ipairs(entries) do
			-- init specific service data table
			local data = {
				name = entry.Service.Service,
				default = false,
				unique = false,
				host = nil,
				path = entry.Service.Service,
				strip = true
			}
			-- toggle default if needed
			if matched == "proxy-root" then
				data.default = true
			end
			-- change service name to id for unique services
			if matched == "proxy-unique" then
				data.unique = true
				data.path = entry.Service.ID
			end
			-- rewrite path if needed
			if hasValue(tags, "proxy-dash2dots") == true then
				data.path = string.gsub(data.path, "-", ".")
			end
			-- toggle strip if needed
			if hasValue(tags, "proxy-nostrip") == true then
				data.strip = false
			end
			-- get host and port notation
			data.host, err = hostPort(entry.Service)
			-- add service to list
			if data.host and err == nil then
				-- init table
				if not sdata[data.path] then
					sdata[data.path] = {}
				end
				-- insert current values
				table.insert(sdata[data.path], {
					name = data.name,
					default = data.default,
					unique = data.unique,
					host = data.host,
					path = data.path,
					strip = data.strip
				})
				-- increase count
				scount = scount + 1
				-- process services in chunks
				if scount % 5 == 0 then
					core.yield()
				end
			end
		end
		-- end of loop
		::skip::
	end

	-- set update time
	lastUpdate = os.time()

	-- replace service data
	serviceTable = sdata

	-- all done
	core.log(core.info,
		string.format("Loaded %d services from catalog in %0.3f seconds",
		scount, socket.gettime() - stime))

	-- release control
	core.done()
end

-- build proxy request uri
function buildRequest(txn)
	-- get request path
	local requestPath = txn.sf:path()

	-- init variables
	local uri = nil
	local defaults = {}

	-- debugging
	txn:Debug(string.format("Attempting to build request for %s", requestPath))

	-- attempt to find service by path
	for servicePath, data in pairs(serviceTable) do
		-- compare request path with service name
		if string.match(requestPath, string.format("^/%s/", servicePath)) then
			-- found a match - strip request path if needed
			if data[1].strip == true then
				requestPath = string.gsub(requestPath, string.format("/%s/", servicePath), "/", 1)
			end
			uri = string.format("http://%s%s", data[math.random(#data)].host, requestPath)
			txn:Debug(string.format("Found path match for %s - proxying to %s", data[1].name, uri))
			return uri
		end
		-- no match - check default root providers
		if data[1].default == true then
			for _, d in ipairs(data) do
				table.insert(defaults, d.host)
			end
		end
	end

	-- check defaults before bailing
	if #defaults > 0 then
		-- no path match - pick a random entry from the default root providers
		uri = string.format("http://%s%s", defaults[math.random(#defaults)], requestPath)
		txn:Debug(string.format("No path match - proxying to default %s", uri))
		return uri
	end

	-- default return - no match
	return nil
end

-- handle http proxy request
function httpRequestHandler(txn)
	-- check services
	if not serviceTable then
		-- error out
		txn:Warning("Missing service definition - aborting request")
		-- release control
		core.done()
		return
	end

	-- check last update and refresh if needed
	if (os.time() - lastUpdate) > serviceLifetime then
		core.register_task(loadServices)
	end

	-- build request uri
	local uri = buildRequest(txn)

	-- check request uri
	if uri ~= nil then
		-- set request
		txn.http:req_set_uri(uri)
	else
		-- log warning
		txn:Warning("Failed to build proxy request for %s", txn.sf:path())
	end

	-- release control
	core.done()
end

-- register functions
core.register_init(loadServices)
core.register_action("httpRequestHandler", { "http-req" }, httpRequestHandler)
