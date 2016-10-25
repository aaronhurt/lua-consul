consul = require("consul")
socket = require("socket")

-- consul poll interval
serviceRefreshInterval = 15

-- consul service holder
serviceTable = {}

-- search a table for matching values
function hasValue(tbl, ...)
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
function hostType(host)
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
local function hostPort(svc)
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

	-- yield after catalog lookup
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
		-- debugging
		-- core.log(core.debug,
		-- 	string.format("Fetching health data for %s", svc))
		-- get service health
		entries, err = c:healthService(svc, true)
		-- check return
		if not entries or err ~= nil then
			-- error fetching service
			core.log(core.warning,
				string.format("Failed fetching service health for %s", svc))
			goto skip
		end
		-- yield after health lookup
		core.yield()
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
				data.path = data.path:gsub("-", ".")
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
			end
			-- yield after proccessing each entry
			core.yield()
		end
		-- end of loop
		::skip::
	end

	-- update servive data
	serviceTable = sdata

	-- all done
	core.log(core.info,
		string.format("Loaded %d services from catalog in %0.3f seconds",
		scount, socket.gettime() - stime))
end

-- service update runner
function servicePoller()
	while true do
		core.sleep(serviceRefreshInterval)
		loadServices()
	end
end

-- build proxy request uri
function buildRequest(txn)
	-- get request path
	local requestPath = txn.sf:path()
	local queryString = txn.sf:query()

	-- init variables
	local uri = nil
	local urif = "http://%s%s"
	local defaults = {}

	-- debugging
	txn:Debug(string.format("Attempting to build request for %s", requestPath))

	-- attempt to find service by path
	for servicePath, data in pairs(serviceTable) do
		-- debugging
		-- txn:Debug(string.format("Checking servicePath %s against requestPath %s",
		-- 	servicePath, requestPath))
		-- compare request path with service name
		if requestPath:match(string.format("^/%s/", servicePath:gsub("([^%w])", "%%%1"))) then
			-- found a match - strip request path if needed
			if data[1].strip == true then
				requestPath = requestPath:gsub(string.format("^/%s/", servicePath:gsub("([^%w])", "%%%1")), "/", 1)
			end
			uri = urif:format(data[math.random(#data)].host, requestPath)
			txn:Debug(string.format("Found path match for %s - proxying to %s", data[1].name, uri))
			break
		end
		-- no match - check default root providers
		if data[1].default == true then
			for _, d in ipairs(data) do
				table.insert(defaults, d.host)
			end
		end
	end

	-- check defaults if uri is still nil
	if uri == nil and #defaults > 0 then
		-- no path match - pick a random entry from the default root providers
		uri = urif:format(defaults[math.random(#defaults)], requestPath)
		txn:Debug(string.format("No path match - proxying to default %s", uri))
	end

	-- append query string if needed
	if uri ~= nil and queryString ~= "" then
		uri = uri .. "?" .. queryString
	end

	-- default return - could be nil
	return uri
end

-- handle http proxy request
function httpRequestHandler(txn)
	-- table debugging (needs print_r package)
	--print_r(txn, false, function(msg) io.stdout:write(msg) end)

	-- TODO: This function should gather statistics

	-- build request uri
	local uri = buildRequest(txn)

	-- check request uri
	if uri ~= nil then
		-- set request
		txn.http:req_set_uri(uri)
	else
		-- log warning
		txn:Warning(string.format("Failed to build proxy request for %s", txn.sf:path()))
	end
end

-- handle http proxy response
function httpResponseHandler(txn)
	-- table debugging (needs print_r package)
	--print_r(txn, false, function(msg) io.stdout:write(msg) end)

	-- TODO This function should collect respones statistics
end

-- init service listing
core.register_init(loadServices)

-- register actions
core.register_action("httpRequestHandler", { "http-req" }, httpRequestHandler)
core.register_action("httpResponseHandler", { "http-res" }, httpResponseHandler)

-- start service poller
core.register_task(servicePoller)
