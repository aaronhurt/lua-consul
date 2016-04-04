local consul = require("consul")
local socket = require("socket")
local services = {}

-- search a table for matching values
local function hasValue(tbl, v1, v2, v3)
	for key, val in pairs(tbl) do
		if (v1 and v1 == val) then
			return true
		end
		if (v2 and v2 == val) then
			return true
		end
		if (v3 and v3 == val) then
			return true
		end
	end
	return false
end

-- load services
local function loadServices ()
	-- init consul
	local c = consul:new()

	-- debugging
	core.log(core.debug,
		string.format("Loading service catalog from %s", c.addr))

	-- get service catalog
	local data, err = c:catalogServices()

	-- check return
	if not data or err ~= nil then
		-- error out
		core.log(core.alert,
			string.format("Failed to init service listing: %s", err))
		return
	end

	-- local service info
	local sdata = {}
	local scount = 0

	-- loop through services
	for svc, tags in pairs(data) do
		if hasValue(tags, "proxy-root", "proxy-standard", "proxy-unique") then
			-- get service entries
			entries, err = c:catalogService(svc)
			-- check return
			if entries and err == nil then
				-- service holder
				local temps = {}
				temps["tags"] = tags
				temps["ids"] = {}
				temps["addrs"] = {}
				-- error toggle
				local ok = true
				-- loop through service entries
				for idx, entry in ipairs(entries) do
					-- set id
					temps["ids"][idx] = entry.ServiceID
					-- resolve address
					local ip, _ = socket.dns.toip(entry.ServiceAddress)
					-- check result
					if ip then
						-- populate address
						temps["addrs"][idx] = string.format("%s:%d", ip, entry.ServicePort)
					else
						ok = false
						break
					end
				end
				-- add service if all entries okay
				if ok == true then
					-- increase count
					scount = scount + 1
					-- add to service data
					sdata[svc] = temps
				end
			end
		end
	end

	-- export service data
	services = sdata

	-- all done
	core.log(core.debug,
		string.format("Loaded %d services from catalog", scount))

end

-- generate a valid proxy request
function generateRequest (txn)
	-- check services
	if not services then
		-- error out
		txn:Warning("Missing service list")
		return
	end

	-- get request path
	local path = txn.sf:path()

	-- init service address
	local addr = ""

	-- find service by path
	for svc, data in pairs(services) do
		txn:Debug(string.format("checking path %s for svc: %s ", path, svc))
		if string.match(path, string.format("^/%s/", svc)) then
			addr = data["addrs"][1]
			txn:Debug(string.format("found match - setting addr to %s", addr))
			break
		end
	end

	-- check addr
	if addr ~= "" then
		-- build uri
		local uri = string.format("http://%s%s", addr, path)
		-- debugging
		txn:Debug(string.format("set uri: %s", uri))
		-- set uri
		txn.http:req_set_uri(uri)
	end

	-- all done
	core.done()
end

-- register functions
core.register_init(loadServices)
core.register_action("generateRequest", { "http-req" }, generateRequest)
