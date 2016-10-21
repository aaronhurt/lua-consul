local consul = require("consul")
local socket = require("socket")
local services = {}
local updated = 0

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

function hostType(host)
  local r = {err = 0, v4 = 1, v6 = 2, string = 3}
  if type(host) ~= "string" then return r.err end

  -- check for format 1.11.111.111 for ipv4
  local chunks = {host:match("(%d+)%.(%d+)%.(%d+)%.(%d+)")}
  if #chunks == 4 then
    for _,v in pairs(chunks) do
      if tonumber(v) > 255 then return r.string end
    end
    return r.v4
  end

  -- check for ipv6 format, should be 8 'chunks' of numbers/letters
  -- without trailing chars
  local chunks = {host:match(("([a-fA-F0-9]*):"):rep(8):gsub(":$","$"))}
  if #chunks == 8 then
    for _,v in pairs(chunks) do
      if #v > 0 and tonumber(v, 16) > 65535 then return r.string end
    end
    return r.v6
  end

  -- non-ip host
  return r.string
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
			string.format("Failed to retrieve service listing: %s", err))
		return
	end

	-- local service info
	local sdata = {}
	local scount = 0

	-- loop through services
	for svc, tags in pairs(data) do
		local match, matched = hasValue(tags, "proxy-root", "proxy-standard", "proxy-unique")
		if match == true then
			-- get service entries
			entries, err = c:healthService(svc, true)
			-- check return
			if entries and err == nil then
				-- service holder
				local temps = {tags = tags, ids = {}, dest = {}, default = false}
				-- set root if applicable
				if matched == "proxy-root" then
					temps.default = true
				end
				-- error toggle
				local ok = true
				-- loop through service entries
				for idx, entry in ipairs(entries) do
					-- set id
					temps.ids[idx] = entry.Service.ID
					-- get host type
					local hType = hostType(entry.Service.Address)
					-- check host type
					if hType == 1 then
						-- populate ipv4 address
						temps.dest[idx] = string.format("%s:%d", entry.Service.Address, entry.Service.Port)
					elseif hType == 2 then
						-- populate ipv6 address
						temps.dest[idx] = string.format("[%s]:%d", entry.Service.Address, entry.Service.Port)
					elseif hType == 3 then
						-- resolve hostname
						local ip, x = socket.dns.toip(entry.Service.Address)
						-- check result
						if ip then
							-- populate ipv4 address
							temps.dest[idx] = string.format("%s:%d", ip, entry.Service.Port)
						else
							-- debugging
							core.log(core.debug,
								string.format("Failed to resolve %s: %s", entry.Service.Address, x))
							-- resolution failed
							ok = false
							break
						end
					else
						-- unknown or invalid service address
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

	-- set update time
	updated = os.time()

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

	-- check last update and refresh if needed
	if (os.time() - updated) > 30 then
		loadServices()
	end

	-- get request path
	local path = txn.sf:path()

	-- init variables
	local uri = nil
	local defaults = {}

	-- attempt to find service by path
	for svc, data in pairs(services) do
		-- debugging
		txn:Debug(string.format("checking path %s for svc: %s ", path, svc))
		-- compare request path with service name
		if string.match(path, string.format("^/%s/", svc)) then
			-- found a match - select random service entry destination and format uri
			uri = string.format("http://%s%s", data.dest[math.random(#data.dest)], path)
			txn:Debug(string.format("found match - set uri to %s", uri))
			break
		end
		-- no match yet - check default root providers
		if data.default == true then
			-- debugging
			for _, d in ipairs(data.dest) do
				txn:Debug(string.format("found default - adding %s", d))
				table.insert(defaults, d)
			end
		end
	end

	-- check uri and set request if present
	if uri ~= nil then
		-- set uri
		txn.http:req_set_uri(uri)
	else
		-- check defaults before bailing
		if #defaults > 0 then
			-- no match but we have defaults - pick one at random
			uri = string.format("http://%s%s", defaults[math.random(#defaults)], path)
			txn:Debug(string.format("no match - set uri to default %s", uri))
			txn.http:req_set_uri(uri)
		end
	end

	-- all done
	core.done()
end

-- register functions
core.register_init(loadServices)
core.register_action("generateRequest", { "http-req" }, generateRequest)
