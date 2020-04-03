-- -----------------------------------------------------------------------------
-- L_SiteSensor.lua
-- Copyright 2016,2017,2019 Patrick H. Rigney, All Rights Reserved
-- This file is available under GPL 3.0. See LICENSE in documentation for info.
--
-- TO-DO:
--   TCP direct
--   More types (POST, PUT, etc.) for HTTP(S)
--   XML?
-- -----------------------------------------------------------------------------

module("L_SiteSensor1", package.seeall)

local debugMode = false

local _PLUGIN_ID = 8942 -- luacheck: ignore 211
local _PLUGIN_NAME = "SiteSensor"
local _PLUGIN_VERSION = "1.15develop-20094"
local _PLUGIN_URL = "https://www.toggledbits.com/sitesensor"
local _CONFIGVERSION = 20082

local MYSID = "urn:toggledbits-com:serviceId:SiteSensor1"
local MYTYPE = "urn:schemas-toggledbits-com:device:SiteSensor:1"
local SSSID = "urn:micasaverde-com:serviceId:SecuritySensor1"
local HASID = "urn:micasaverde-com:serviceId:HaDevice1"

local pluginDevice
local runStamp = 0
local isALTUI = false
local isOpenLuup = false
local myChildren
local logCapture = {}
local logRequest = false
local logMax = 50

local http = require("socket.http")
local ssl = require "ssl"
local https = require("ssl.https")
local ltn12 = require("ltn12")
local json = require('dkjson')
local luaxp = require("L_LuaXP")

local dfMap = {
	["urn:schemas-micasaverde-com:device:MotionSensor:1"] = {
		name="Security Sensor",
		device_file="D_MotionSensor1.xml",
		service="urn:micasaverde-com:serviceId:SecuritySensor1",
		variable="Tripped",
		datatype="boolean",
		category=4,
		subcategory=0
	},
	["urn:schemas-micasaverde-com:device:TemperatureSensor:1"] = {
		name="Temperature Sensor",
		device_file="D_TemperatureSensor1.xml",
		service="urn:upnp-org:serviceId:TemperatureSensor1",
		variable="CurrentTemperature",
		datatype="number",
		category=17,
		subcategory=0
	},
	["urn:schemas-micasaverde-com:device:HumiditySensor:1"] = {
		name="Humidity Sensor",
		device_file="D_HumiditySensor1.xml",
		service="urn:micasaverde-com:serviceId:HumiditySensor1",
		variable="CurrentLevel",
		datatype="number",
		category=16,
		subcategory=0
	},
	["urn:schemas-micasaverde-com:device:LightSensor:1"] = {
		name="Light Sensor",
		device_file="D_LightSensor1.xml",
		service="urn:micasaverde-com:serviceId:LightSensor1",
		variable="CurrentLevel",
		datatype="number",
		category=18,
		subcategory=0
	},
	["urn:schemas-micasaverde-com:device:GenericSensor:1"] = {
		name="Generic Sensor",
		device_file="D_GenericSensor1.xml",
		service="urn:micasaverde-com:serviceId:GenericSensor1",
		variable="CurrentLevel",
		datatype="number",
		category=12,
		subcategory=0
	},
	["urn:schemas-upnp-org:device:BinaryLight:1"] = {
		name="Virtual Switch",
		device_file="D_BinaryLight1.xml",
		service="urn:upnp-org:serviceId:SwitchPower1",
		variable="Status",
		datatype="boolean",
		category=3,
		subcategory=0
	}
}

local function dump(t)
	if t == nil then return "nil" end
	local sep = ""
	local str = "{ "
	for k,v in pairs(t) do
		local val
		if type(v) == "table" then
			val = dump(v)
		elseif type(v) == "string" then
			val = string.format("%q", v)
		else
			val = tostring(v)
		end
		local b = string.match( k, "^%a%w*$" ) and k or ( '["'..k..'"]' )
		str = str .. sep .. b .. "=" .. val
		sep = ", "
	end
	str = str .. " }"
	return str
end

local function L(msg, ...) -- luacheck: ignore 212
	local str
	local level = 50
	if type(msg) == "table" then
		str = tostring(msg.prefix or _PLUGIN_NAME) .. ": " .. tostring(msg.msg)
		level = msg.level or level
	else
		str = _PLUGIN_NAME .. ": " .. tostring(msg)
	end
	str = string.gsub(str, "%%(%d+)", function( n )
			n = tonumber(n, 10)
			if n < 1 or n > #arg then return "nil" end
			local val = arg[n]
			if type(val) == "table" then
				return dump(val)
			elseif type(val) == "string" then
				return string.format("%q", val)
			elseif type(val) == "number" and math.abs(val-os.time()) <= 86400 then
				return tostring(val) .. "(" .. os.date("%x.%X", val) .. ")"
			end
			return tostring(val)
		end
	)
	luup.log(str, level)
	return str
end

local function D(msg, ...)
	if debugMode then
		L( { msg=msg,prefix=(_PLUGIN_NAME .. "(debug)") }, ... )
	end
end

-- Capture log
local function C(dev, msg, ...)
	assert(type(dev)=="number")
	if logRequest then
		local str = L(msg,...)
		table.insert( logCapture, os.date("%X") .. ": " .. str )
		if #logCapture > 0 and #logCapture > logMax then table.remove( logCapture, 1 ) end
		luup.variable_set( MYSID, "LogCapture", table.concat( logCapture, "|" ), dev )
	else
		if ( luup.variable_get( MYSID, "LogCapture", dev ) or "" ) ~= "" then
			luup.variable_set( MYSID, "LogCapture", "", dev )
		end
	end
end

local function split( str, sep )
	if sep == nil then sep = "," end
	local arr = {}
	if #str == 0 then return arr, 0 end
	local rest = string.gsub( str or "", "([^" .. sep .. "]*)" .. sep, function( m ) table.insert( arr, m ) return "" end )
	table.insert( arr, rest )
	return arr, #arr
end

local function getInstallPath()
	if not installPath then
		installPath = "/etc/cmh-ludl/" -- until we know otherwise
		if isOpenLuup then
			local loader = require "openLuup.loader"
			if loader.find_file then
				installPath = loader.find_file( "L_SiteSensor1.lua" ):gsub( "L_SiteSensor1.lua$", "" )
			else
				installPath = "./" -- punt
			end
		end
	end
	return installPath
end

local function findChild( id )
	if myChildren == nil then
		myChildren = {}
		for k,v in pairs( luup.devices ) do
			if v.device_num_parent == pluginDevice then
				myChildren[ v.id ] = k
			end
		end
	end
	return myChildren[ id ] or false -- force return boolean instead of nil
end

local function parseRefExpr(ex, ctx, dev)
	D("parseRefExpr(%1,ctx)", ex, ctx)
	local cx, err = luaxp.compile(ex,ctx)
	if cx == nil then
		C(dev, "Failed to parse expression `%1', %2", ex, err)
		return nil
	end

	local val
	val, err = luaxp.run(cx, ctx)
	if val == nil then
		C(dev, "Failed to execute `%1', %2", ex, err)
	end
	return val
end

local function initVar( sid, name, dflt, dev )
	dev = dev or pluginDevice
	sid = sid or MYSID
	local currVal = luup.variable_get( sid, name, dev )
	if currVal == nil then
		luup.variable_set( sid, name, tostring(dflt), dev )
		return dflt
	end
	return currVal
end

-- Set variable, only if value has changed.
local function setVar( sid, name, val, dev )
	assert( dev ~= nil and type(dev) == "number", "Invalid set device for "..dump({sid=sid,name=name,val=val,dev=dev}) )
	assert( dev > 0, "Invalid device number "..tostring(dev) )
	assert( sid ~= nil, "SID required for "..tostring(name) )
	val = (val == nil) and "" or tostring(val)
	local s = luup.variable_get( sid, name, dev )
	-- D("setVar(%1,%2,%3,%4) old value %5", sid, name, val, dev, s )
	if s ~= val then
		luup.variable_set( sid, name, val, dev )
	end
	return s
end

local function getVar( name, dflt, dev, serviceId )
	local s = luup.variable_get(serviceId or MYSID, name, dev or pluginDevice) or ""
	return ( not string.match( s, "^%s*$" ) ) and s or dflt -- this specific test allows nil dflt return
end

-- Get numeric variable, or return default value if not set or blank
local function getVarNumeric( name, dflt, dev, serviceId )
	assert( dev ~= nil )
	local s = luup.variable_get(serviceId or MYSID, name, dev or pluginDevice) or ""
	if s == "" then return dflt end
	return tonumber(s) or dflt
end

local function deleteVar( sid, var, dev )
	if luup.variable_get( sid, var, dev ) ~= nil then
		luup.variable_set( sid, var, nil, dev )
	end
end

local function isEnabled( dev )
	return getVarNumeric( "Enabled", 1, dev, MYSID ) ~= 0
end

local function setMessage(s, dev)
	setVar(MYSID, "Message", s or "", dev or pluginDevice)
end

local function appendMessage(s, dev)
	setMessage((luup.variable_get(MYSID, "Message", dev or pluginDevice))..(s or ""), dev)
end

local function isFailed(dev)
	return getVarNumeric("Failed", 0, dev or pluginDevice, MYSID) ~= 0
end

local function fail(failState, dev)
	assert(type(failState) == "boolean")
	D("fail(%1,%2)", failState, dev)
	if failState ~= isFailed(dev) then
		local fval = failState and 1 or 0
		setVar(MYSID, "Failed", fval, dev or pluginDevice)
	end
	if getVarNumeric( "DeviceErrorOnFailure", 1, dev, SSSID ) ~= 0 then
		luup.set_failure( failState and 1 or 0, dev or pluginDevice )
		for k,v in pairs( luup.devices ) do
			if v.device_num_parent == dev then
				luup.set_failure( failState and 1 or 0, k )
			end
		end
	end
end

local function isArmed(dev)
	return getVarNumeric("Armed", 0, dev, SSSID) ~= 0
end

local function isTripped(dev)
	return getVarNumeric("Tripped", 0, dev, SSSID) ~= 0
end

local function trip(tripped, dev)
	assert(type(tripped) == "boolean")
	D("trip(%1,%2)", tripped, dev)
	local newVal
	if tripped ~= isTripped(dev) then
		if tripped then
			D("trip() marking tripped")
			newVal = "1"
		else
			D("trip() marking not tripped")
			newVal = "0"
		end
		setVar(SSSID, "Tripped", newVal, dev)
		-- LastTrip and ArmedTripped are set as needed by Luup
	end
end

function scheduleNext(dev, delay, stamp)
	D("scheduleNext(%1,%2,%3)", dev, delay, stamp)
	assert(dev ~= nil)

	-- Schedule next run. First, get and sanitize our interval if we weren't passed one.
	if delay == nil then
		delay = getVarNumeric( "Interval", 1800, dev )
		if isArmed( dev ) then
			delay = getVarNumeric( "ArmedInterval", delay, dev )
		end
		D("scheduleNext() interval is %1", delay)
		if delay < 30 then
			L({level=2,msg="WARNING! Request interval of %1 may be shorter than connection timeout, and cause all kinds of problems."}, delay)
		end
	end

	-- When's our next query scheduled?
	local nextQuery = getVarNumeric( "LastQuery", 0, dev ) + delay
	D("scheduleNext() next query at %1", nextQuery)

	-- See if we're doing eval ticks (rerunning evals between requests)
	local qtype = luup.variable_get(MYSID, "ResponseType", dev) or "text"
	if qtype == "json" then
		local evalTick = getVarNumeric( "EvalInterval", 0, dev )
		if evalTick > 0 then
			local whence = getVarNumeric( "LastEval", 0, dev ) + evalTick -- when tick should have happened
			if whence < nextQuery then
				D("scheduleNext() re-eval is earlier than next query; %1 < %2", whence, nextQuery )
				nextQuery = whence
			end
		end
	end

	-- OK. How long until next happens?
	local now = os.time()
	if nextQuery <= now then
		-- We've missed an interval
		L({level=2,msg="Missed interval! Expected to run at %1"}, nextQuery)
		delay = 0 -- immediately!
	else
		local n = nextQuery - now
		if n < delay then 
			D("scheduleNext() scheduling for %1 delay %2 (reduced from %3)", nextQuery, n, delay)
			delay = n 
		end
	end

	-- Book it.
	if delay < 0 then delay = 0 end
	-- appendMessage( "; next at "..os.date("%X",os.time()+delay), dev)
	L("Scheduling next activity in %1 seconds", delay)
	luup.call_delay("siteSensorRunQuery", delay, string.format("%d:%d", stamp, dev))
end

local function b64encode( d )
	local mime = require("mime")
	return mime.b64(d)
end

local function urlencode( str )
	if str == nil then return "" end
	str = tostring(str)
	return str:gsub("([^%w._-])", function( c ) if c==" " then return "+" else return string.format("%%%02x", string.byte(c)) end end )
end

local function urldecode( str )
	if str == nil then return "" end
	return tostring(str):gsub("%+", " "):gsub("%%(..)", function( c ) return string.char(tonumber(c,16)) end)
end

-- Return the current timezone offset adjusted for DST
local function tzoffs()
	local localtime = os.date("*t")
	local epoch = { year=1970, month=1, day=1, hour=0 }
	-- 19084 duplicate exactly what LuaXP does (see 19084 there)
	epoch.isdst = localtime.isdst
	return os.time( epoch )
end

local function substitution( str, enc, dev )
	local subMap = {
		  isodatetime = function( _ ) return os.date("%Y-%m-%dT%H:%M:%S") end
		, isodate = function( _ ) return os.date("%Y-%m-%d") end
		, isotime = function( _ ) return os.date("%H:%M:%S") end
		  -- tzoffset returns timezone offset in ISO 8601-like format, -0500
		, tzoffset = function( _ ) local offs = tzoffs() / 60 local mag = math.abs(offs) local sg = offs < 0 local c = '+' if sg then c = '-' end return string.format("%s%02d%02d", c, mag / 60, mag % 60) end
		  -- tzdelta returns timezone offset formatted like -5hours (PHP-compatible date offset)
		, tzrel = function( _ ) local offs = tzoffs() / 60 return string.format("%+dhours", offs / 60) end
		, device = function( d ) return d end
		, latitude = function( _ ) return luup.latitude end
		, longitude = function( _ ) return luup.longitude end
		, city = function() return luup.city end
		, basicauth = function( d ) return b64encode( (luup.variable_get( MYSID, "AuthUsername", d) or "") .. ":" .. (luup.variable_get( MYSID, "AuthPassword", d) or "") ) end
		, ['random'] = function( _ ) return math.random() end
	}
	if str == nil then return nil end
	str = tostring(str)
	str = str:gsub("(%[[^%]]+%])", function( e )
			e = e:sub( 2, -2 ):lower()
			local f = e:gsub(":.*$", "")
			local s
			if subMap[f] == nil then
				s = "?" .. f .. "?"
			elseif type(subMap[f]) == "function" then
				s = subMap[e]( dev )
			else
				s = subMap[e] or subMap[f] -- more to less specific
			end
			if type(enc) == "function" then s = enc(s, dev) end
			return s
		end ) -- lambda
	return str
end

local function doRequest(url, method, body, dev)
	assert(dev ~= nil)
	if method == nil then method = "GET" end

	-- A few other knobs we can turn
	local timeout = getVarNumeric("Timeout", 30, dev) -- ???

	local src
	local tHeaders = {}

	-- Perform on-the-fly substitution of request values
	url = substitution( url, urlencode, dev )

	-- Build post/put data
	if type(body) == "table" then
		body = json.encode(body)
		tHeaders["Content-Type"] = "application/json"
	elseif ( body or "" ) ~= "" then
		tHeaders["Content-Type"] =  "application/x-www-form-urlencoded"
	end
	if body ~= nil then
		tHeaders["Content-Length"] = string.len(body)
		src = ltn12.source.string(body)
	else
		src = nil
	end

	local moreHeaders = luup.variable_get(MYSID, "Headers", dev) or ""
	if string.len(moreHeaders) > 0 then
		local h = split(moreHeaders, "|")
		for _,hh in ipairs(h) do
			local nh = split(hh, ":")
			if #nh == 2 then
				tHeaders[nh[1]] = substitution( urldecode( nh[2] ), nil, dev ):gsub("^%s+",""):gsub("%s+$","")
			end
		end
	end

	--[[
		Decide where query response storage will be. In order to reduce wear on flash, we try to
		store the query on /tmp. Failing that, we'll store in on flash if we must.
	--]]
	local maxresp = getVarNumeric( "MaxResponseSize", 65536, dev, MYSID )
	local fn = luup.variable_get( MYSID, "qf", dev ) or ""
	if fn == "" or fn == "0" then
		local evalint = getVarNumeric( "EvalInterval", 0, dev, MYSID )
		local ff = "Q_SiteSensor_" .. tostring( dev ) .. ".txt"
		if evalint == 0 and maxresp <= 262144 then
			-- If not recurring evals and max < 256K, use /tmp for storage (a ramfs on Vera, volatile)
			fn = "/tmp/" .. ff
			os.remove( getInstallPath() .. ff )
			os.remove( getInstallPath() .. ff .. ".lzo" )
			-- Link in the install path makes it fetchable from Apps > Develop apps > Luup files
			-- 20090: link doesn't work -- Luup files doesn't list symlinked files. :/
			-- os.execute( "ln -s '"..fn..".lzo' '" .. getInstallPath() .. ff .. ".lzo'" )
		else
			-- Use flash/"real" storage
			os.remove( "/tmp/" .. ff )
			os.remove( "/tmp/" .. ff .. ".lzo" )
			fn = getInstallPath() .. ff
		end
		luup.variable_set( MYSID, "qf", fn, dev )
	end
	os.remove( fn )
	if not isOpenLuup then os.remove( fn..".lzo" ) end
	D("doRequest() setting up response file %1 for max response length %1", fn, maxresp)
	local respBody, httpStatus
	if getVarNumeric( "UseCurl", 0, dev, MYSID ) ~= 0 then
		-- Use curl
		local req = string.format( "curl -m %d -o '%s'", timeout, fn )
		for k,v in pairs( tHeaders or {} ) do
			req = req .. " -H '" .. k .. ": " .. v .. "'"
		end
		local s = luup.variable_get( MYSID, "CurlOptions", dev ) or ""
		if s ~= "" then req = req .. " " .. s end
		req = req .. " '" .. url .. "'"
		C(dev, req)
		local fst, ferr = os.execute( req )
		if fst ~= 0 then
			C(dev, "Request failed, %1", ferr)
			L({level=1,msg="Curl request failed, %1 %2: %3"}, fst, ferr, req)
			httpStatus = 500
		else
			httpStatus = 200
		end
	else
		-- Use http module
		local f, ferr = io.open( fn, "w" )
		if not f then
			C(dev, "Can't open %1: %2", fn, ferr)
			L({level=1,msg="Failed to open %1: %2"}, fn, ferr)
			httpStatus = 500
		else
			local req = {
				url = url,
				source = src,
				sink = ltn12.sink.file( f ),
				method = method,
				headers = tHeaders,
				redirect = false
			}

			-- HTTP or HTTPS?
			local requestor
			if url:lower():find("https:") then
				requestor = https
				req.verify = getVar( "SSLVerify", "none", dev, MYSID )
				req.protocol = getVar( "SSLProtocol", ( ssl._VERSION or "0.5" ):find("^0%.[45]") and "tlsv1" or "any", dev, MYSID )
				req.mode = getVar( "SSLMode", "client", dev, MYSID )
				local s = split( getVar( "SSLOptions", nil, dev, MYSID ) or "" )
				if #s > 0 then req.options = s end
				req.cafile = getVar( "CAFile", nil, dev, MYSID )
				C(dev, "Set up for HTTPS (%4) request, verify=%1, protocol=%2, options=%3",
					req.verify, req.protocol, req.options, ssl._VERSION)
			else
				requestor = http
			end

			-- Make the request.
			http.TIMEOUT = timeout -- N.B. http not https, regardless
			C(dev, "%2 %1, headers=%3", url, method, tHeaders)
			local rh, st
			respBody, httpStatus, rh, st = requestor.request( req )
			D("doRequest() request returned httpStatus=%1, respBody=%2, respHeaders=%3, status=%4", httpStatus, respBody, rh, st)

			pcall( io.close, f ) -- make sure we're closed

			-- Handle special errors from socket library
			httpStatus = tonumber( httpStatus ) or 500
		end
	end

	-- Read response from temporary file; truncate to limit
	if httpStatus >= 200 and httpStatus <= 299 then
		D("doRequest() reading response file %1", fn)
		local f, err = io.open( fn, "r" )
		if not f then
			C(dev, "Can't read response file "..fn..": "..tostring(err))
			respBody = ""
			httpStatus = 500
		else
			respBody = f:read( maxresp )
			local n = f:seek( "end" )
			D("doRequest() read %1 bytes of %2; limit %3", #respBody, n, maxresp)
			if n > maxresp then
				C(dev, "WARNING: Response was truncated to limit of %1 bytes; %2 total bytes received in %3", maxresp, n, fn)
			else
				C(dev, "Response is %1 bytes in %2", #respBody, fn)
			end
			f:close()
			-- On Vera, compress the file so it's fetchable from Apps > Develop apps > Luup files
			if not isOpenLuup then
				if os.execute( "pluto-lzo c '"..fn.."' '"..fn..".lzo'" ) then
					os.remove( fn )
				end
			end
		end
	else
		respBody = httpStatus
		os.remove( fn )
	end

	-- See what happened. Anything 2xx we reduce to 200 (OK).
	if httpStatus >= 200 and httpStatus <= 299 then
		-- Success
		return false, respBody, 200
	end
	-- Error response
	return true, respBody, httpStatus
end

local function doMatchQuery( dev )
	assert(dev ~= nil)

	setMessage("Performing query...", dev)

	local method = "GET"
	local url = (luup.variable_get(MYSID, "RequestURL", dev) or ""):gsub( "^%s+", "" ):gsub( "%s+$", "" )
	local pattern = luup.variable_get(MYSID, "Pattern", dev) or "^HTTP/1.. 200"
	local timeout = getVarNumeric("Timeout", 30, dev)
	local trigger = luup.variable_get(MYSID, "Trigger", dev) or nil

	-- Clear log capture for new request
	logRequest = (getVarNumeric("LogRequests", 0, dev) ~= 0) or debugMode
	logCapture = {}

	-- Perform on-the-fly substitution of request values
	url = substitution( url, urlencode, dev )

	local tHeaders = {}
	local moreHeaders = luup.variable_get(MYSID, "Headers", dev) or ""
	if string.len(moreHeaders) > 0 then
		local h = split(moreHeaders, "|")
		for _,hh in ipairs(h) do
			local nh = split(hh, ":")
			if #nh == 2 then
				tHeaders[nh[1]] = substitution( urldecode( nh[2] ), nil, dev )
			end
		end
	end

	-- Set up the request table
	local matched = false
	local err = true -- guilty until proven innocent
	local matchValue
	local buf = ""
	local req =  {
		method = method,
		url = url,
		headers = tHeaders,
		redirect = false,
		sink = function(chunk, source_err)
			if chunk == nil then
				-- no more data to process
				D("doMatchQuery() chunk is nil")
				if source_err then
					err = true
					return nil, "Source error: "..tostring(source_err)
				else
					return true
				end
			elseif chunk == "" then
				err = false
				return true
			else
				err = false
				buf = buf .. chunk
				D("doMatchQuery() valid chunk, buf now contains %1", #buf)
				if trigger ~= "err" then
					local s, e, p = string.find(buf, pattern)
					if s then
						-- LastMatchValue will get the first capture if there is one, otherwise whatever matched
						if p == nil then
							matchValue = string.sub(buf, s, e)
						else
							matchValue = p
						end
						matched = true -- upvalue!
						return nil, "Matched" -- early exit, fake valid response
					end
				end
				-- Trim buffer to last 2048 bytes
				if #buf > 2048 then
					buf = string.sub(buf, #buf-2048+1)
				end
				return true
			end
		end
	}

	-- HTTP or HTTPS?
	local requestor
	if url:lower():find("^https:") then
		requestor = https
		req.verify = getVar( "SSLVerify", "none", dev, MYSID )
		req.protocol = getVar( "SSLProtocol", ( ssl._VERSION or "0.5" ):match("^0%.[45]") and "tlsv1" or "any", dev, MYSID )
		req.mode = getVar( "SSLMode", "client", dev, MYSID )
		local s = split( getVar( "SSLOptions", nil, dev, MYSID ) or "" )
		if #s > 0 then req.options = s end
		req.cafile = getVar( "CAFile", nil, dev, MYSID )
		C(dev, "Set up for HTTPS (%4) request, verify=%1, protocol=%2, options=%3",
			req.verify, req.protocol, req.options, ssl._VERSION)
	else
		requestor = http
	end

	D("doMatchQuery() seeking %1 in %2", pattern, url)

	-- We don't use doRequest here because we can stop and close the
	-- connection as soon as we find our pattern string.
	http.TIMEOUT = timeout
	C(dev, "HTTP %2 %1, headers=%3", url, method, tHeaders)

	D("doMatchQuery() sending req=%1", req)
	local cond, httpStatus, httpHeaders = requestor.request(req)
	--[[ Notes
		Interesting semantics to the return values here. If the pattern is matched before the body response has been
		completely processed, our sink returns nil (because hey, work is done at that point), but it causes request()
		to return "cond=nil,httpStatus=Matched pattern" (or whatever the sink returned). If no match occurs, the full
		body is read (because the sink keeps looking for the pattern and doesn't find it), but in that case, request()
		returns the expected/documented "cond=1,httpStatus=200" response.
	--]]
	D("doMatchQuery() returned from request(), matched=%1, err=%2, cond=%3, httpStatus=%4, httpHeaders=%5",
		matched, err, tostring(cond), httpStatus, httpHeaders)
	if err or ( cond==nil and httpStatus==nil) then
		C(dev, "Request failed: %1", httpStatus or "connection failure")
		setMessage("Request error: " .. ( httpStatus or "connection failure" ), dev)
		setVar(MYSID, "LastMatchValue", "", dev)
		fail(true, dev)
	else
		C(dev, "Request succeeded, %2 match: %1", httpStatus or "OK", matched and "with" or "no" )
		setMessage( "Valid response; " .. ( matched and "matched!" or "no match." ), dev )
		local lastVal = luup.variable_get(MYSID, "LastMatchValue", dev)
		if lastVal == nil or lastVal ~= matchValue then
			setVar(MYSID, "LastMatchValue", matchValue, dev)
		end
		fail(false, dev)
	end

	-- Set trip state based on result.
	D("doMatchQuery() matched is %1", matched)
	local newTrip
	if trigger == "match" then
		newTrip = matched
	elseif trigger == "neg" then
		newTrip = not matched
	else -- "err" is default now
		newTrip = err
	end
	trip(newTrip, dev)

	-- Clear JSON request fields
	local numexp = getVarNumeric( "NumExp", 8, dev, MYSID )
	for k=1,numexp do
		setVar(MYSID, "Value" .. tostring(k), "", dev)
	end
end

-- Find device by number, name or UDN
local function finddevice( dev, tdev )
	local vn
	if type(dev) == "number" then
		if dev == -1 then return tdev end
		return dev
	elseif type(dev) == "string" then
		if dev == "" then return tdev end
		dev = string.lower( dev )
		if dev:sub(1,5) == "uuid:" then
			for n,d in pairs( luup.devices ) do
				if string.lower( d.udn ) == dev then
					return n
				end
			end
		else
			for n,d in pairs( luup.devices ) do
				if string.lower( d.description ) == dev then
					return n
				end
			end
		end
		vn = tonumber( dev )
	end
	return vn
end


local function doEval( dev, ctx )
	logRequest = (getVarNumeric("LogRequests", 0, dev) ~= 0) or debugMode
	local numErrors = 0

	-- Since we got a valid response, indicate not tripped, unless using TripExpression, then that.
	-- Reset state var for (in)valid response?
	setMessage("Retrieving last response...", dev)

	if ctx == nil then
		local maxresp = getVarNumeric( "MaxResponseSize", 65536, dev, MYSID )
		local isPipe = false
		local fn = luup.variable_get( MYSID, "qf", dev ) or ( getInstallPath() .. "Q_SiteSensor_" .. tostring(dev) .. ".txt" )
		local f, ferr = io.open( fn, "r" )
		if not ( f or isOpenLuup ) then
			f = io.popen( "pluto-lzo d '" .. fn .. ".lzo' /proc/self/fd/1" )
			isPipe = f ~= nil
			L("opened LZO file %1", f)
		end
		-- Tricky. If we opened a pipe, it will be open even if command fails, so we won't know
		-- until we read that the pipe is broken.
		local lr
		if f then
			lr = f:read( maxresp )
		end
		if not ( f and lr ) then
			luup.variable_set( MYSID, "LastQuery", 0, dev ) -- force update
			L({level=2,msg="doEval() failed to open %1: %2"}, fn, ferr)
			C(dev, "No prior response stored to re-evaluate.")
			setMessage( "Empty or invalid response data.", dev )
			fail( true, dev )
			return
		end
		local n
		if isPipe then
			-- Can't seek on a pipe; read to EOF for length
			n = #lr -- actual length may be smaller than maxresp
			repeat
				local t = f:read(2048)
				if t then n = n + #t end
			until not t
		else
			n = f:seek( "end" )
		end
		f:close()
		if n > maxresp then
			C(dev, "WARNING: Response truncated to %1 bytes; %2 bytes actually received", maxresp, n)
		else
			C(dev, "Reloaded %1 bytes from previous response", #lr)
		end
		local data, pos, err = json.decode( lr, 1, luaxp.NULL )
		ctx = { response=data, status={ valid=1, jsonStatus="OK", httpStatus=200 } }
		if err then
			ctx.status.valid = 0
			ctx.jsonStatus = string.format("%s, at %s", tostring(err), tostring(pos))
		else
			C(dev, "Re-evaluating previously received response")
		end
	end

	-- Valid response?
	if ( ctx.status.valid or 0 ) == 0 then
		local msg = "Last query failed, "
		if ctx.status.httpStatus ~= 200 then
			msg = msg .. "HTTP status " .. tostring(ctx.status.httpStatus)
		else
			msg = msg .. "JSON error " .. ctx.status.jsonStatus
		end
		setMessage( msg, dev )
		fail( true, dev )
		return
	end

	ctx.__functions = ctx.__functions or {}
	ctx.__lvars = ctx.__lvars or {}
	ctx.__functions.finddevice = function( args )
		local selector, trouble = unpack( args )
		D("findDevice(%1) selector=%2", args, selector)
		return finddevice( selector, dev ) or ( trouble and luaxp.evalerror( "Device not found" ) or luaxp.NULL )
	end
	ctx.__functions.getstate = function( args )
		local selector, svc, var, trouble = unpack( args )
		local vn = finddevice( selector, dev )
		D("getstate(%1), selector=%2, svc=%3, var=%4, vn(dev)=%5", args, selector, svc, var, vn)
		if vn == luaxp.NULL or vn == nil or luup.devices[vn] == nil then
			-- default behavior for getstate() is error (legacy, diff from finddevice)
			return trouble and luaxp.evalerror( "Device not found" ) or luaxp.NULL
		end
		-- Get and return value
		return luup.variable_get( svc, var, vn ) or luaxp.NULL
	end

	-- Valid response. Let's parse it and set our variables.
	local numexp = getVarNumeric( "NumExp", 8, dev, MYSID )
	ctx.__lvars.expr = {}
	for i = 1,numexp do
		local r = nil
		local ex = luup.variable_get(MYSID, "Expr" .. tostring(i), dev) or ""
		if not logRequest then D("doEval() Expr%1=%2", i, ex or "nil") end
		if ex ~= "" then
			r = parseRefExpr(ex, ctx, dev)
			if luaxp.isNull( r ) then
				C(dev, "Eval #%1: %2=null", i, ex)
			else
				C(dev, "Eval #%1: %2=("..type(r)..")%3", i, ex, r)
			end
			D("doEval() parsed value of %1 is %2", ex, tostring(r))
			if r == nil then
				numErrors = numErrors + 1
			end
			-- Add raw result to context (available to subsequent expressions)
			ctx.__lvars.expr[i] = r -- raw, not canonical
		else
			setVar(MYSID, "Expr" .. tostring(i), "", dev)
		end

		-- Canonify the result value
		local rv
		if r == nil or luaxp.isNull( r ) then
			rv = ""
		elseif type(r) == "boolean" then
			if r then rv = "true" else rv = "false" end
		elseif type(r) == "table" then
			rv = table.concat( r, "," )
		else
			rv = tostring(r)
		end

		-- Save to device state if changed.
		local oldVal = luup.variable_get(MYSID, "Value" .. tostring(i), dev)
		D("doEval() newval=(%1)%2 canonical %3, oldVal=%4", type(r), r, rv, oldVal)
		if rv ~= oldVal or debugMode then
			-- Set new value only if changed
			D("doEval() Expr%1 value changed, was %2 now %3", i, oldVal, rv)
			setVar(MYSID, "Value" .. tostring(i), rv, dev)

			-- Save to child if exists.
			local dv = findChild( string.format( "ch%d", i ) )
			if dv and luup.devices[dv] then
				local df = dfMap[ luup.devices[dv].device_type ]
				if df then
					-- Note: re-using rv -- convert to sensor form value
					if df.datatype == "boolean" then
						if type(r) == "boolean" then rv = r and "1" or "0"
						elseif type(r) == "number" then rv = (r~=0) and "1" or "0"
						elseif type(r) == "string" then
							rv = ( #r > 0 and r ~= "false" and r ~= "0" ) and "1" or "0"
						else
							rv = r ~= nil
						end
						D("doEval() converting %1(%2) to sensor boolean value %3", r, type(r), rv)
					elseif type(r) == "table" then
						rv = table.concat( r, ", " )
					else
						rv = tostring(r)
					end
					D("doEval() converted %1(%2) to sensor %4 value %3", r, type(r), rv, df.datatype)
					D("doEval() setting child %1 (#%2) %3/%4=%5", i, dv, df.service, df.variable, rv)
					setVar( df.service or MYSID, df.variable or "CurrentLevel", rv, dv )
				else
					L({level=2,msg="Can't store value for expr %1 to child, no dfMap entry for %2"}, i, luup.devices[dv].device_type)
				end
			end
		end
	end

	-- Handle the trip expression
	local ttype = luup.variable_get(MYSID, "Trigger", dev) or "err"
	if ttype == "expr" then
		local texp = luup.variable_get(MYSID, "TripExpression", dev)
		if texp == "" then texp = nil end
		D("doEval() parsing TripExpression %1", texp)
		local r = parseRefExpr(texp or "null", ctx, dev)
		if r == nil then numErrors = numErrors + 1 end
		D("doEval() TripExpression result is %1", r)
		if luaxp.isNull(r) then
			C(dev, "Eval trip expression: %1=null", texp)
		else
			C(dev, "Eval trip expression: %1=(%2)%3", texp, type(r), r)
		end
		if r == nil or luaxp.isNull(r)
			or ( type(r) == "boolean" and r == false )
			or ( type(r) == "number" and r == 0 )
			or ( type(r) == "string" and ( string.len(r) == 0 or r == "0" or r:lower() == "false" ) ) -- some magic strings
		then
			-- Trip expression is logically (for us) false
			trip(false, dev)
		else
			-- Trip expression is not logically false (i.e. true)
			trip(true, dev)
		end
	else
		-- No trip expression; trip state follows query success
		D("doEval() resetting tripped state")
		trip(ctx.status.valid == 0, dev)
	end

	local msg
	if numErrors > 0 then
		msg = string.format("Query OK, but %d expressions failed", numErrors)
		fail( true, dev )
	else
		local msgExpr = luup.variable_get(MYSID, "MessageExpr", dev) or ""
		if msgExpr == "" then
			msg = "Last query OK"
		else
			msg = parseRefExpr(msgExpr, ctx, dev)
			if msg == nil then msg = "?" end
		end
		fail( false, dev )
	end
	setMessage( msg, dev )
end

local function doJSONQuery(dev)
	assert(dev ~= nil)
	local url = luup.variable_get(MYSID, "RequestURL", dev) or ""
	local ttype = luup.variable_get(MYSID, "Trigger", dev) or "err"

	-- Clear log capture for new request
	logRequest = (getVarNumeric("LogRequests", 0, dev) ~= 0) or debugMode
	logCapture = {}

	setMessage("Requesting JSON...", dev)
	C(dev, "Requesting JSON data")
	local err,body,httpStatus = doRequest(url, "GET", nil, dev)
	local ctx = { status={ timestamp=os.time(), valid=0, httpStatus=httpStatus } }
	if body == nil or err then
		-- Error; trip sensor
		ctx.status.jsonStatus = "No data"
		C(dev, "Request returned no data, status %1", httpStatus)
		D("doJSONQuery() setting tripped and bugging out...")
		fail(true, dev)
		if ttype == "err" then trip(true, dev) end
	else
		if #body >= 65536 then
			C(dev, "WARNING: the response from this site is quite large! (%1 bytes)", #body)
		end
		D("doJSONQuery() fixing up JSON response (%1 bytes) for parsing", #body)
		setMessage("Parsing response...", dev)
		-- Fix booleans, which json doesn't seem to understand (gives nil)
		-- ??? This does not seem to be issue any more? 2020-04-03
		body = string.gsub( body, ": *true *,", ": 1," )
		body = string.gsub( body, ": *false *,", ": 0," )

		-- Process JSON response. First parse response.
		local t, _, e = json.decode(body, 1, luaxp.NULL)
		if e then
			C(dev, "Unable to decode JSON response, %2 (dev %1)", dev, e)
			-- If TripExpression isn't used, trip follows status
			fail(true, dev)
			if ttype == "err" then trip(true, dev) end
			-- Set state var for invalid response?
			setMessage("Invalid response", dev)
			ctx.status.jsonStatus = e
		else
			D("doJSONQuery() parsed response")
			-- Encapsulate the response
			ctx.status.valid = 1
			ctx.status.jsonStatus = "OK"
			ctx.response = t
			fail(false, dev)
		end
	end

	doEval( dev, ctx )
end

local function checkVersion(dev)
	assert(dev ~= nil)
	D("checkVersion() branch %1 major %2 minor %3, string %4, openLuup %5", luup.version_branch, luup.version_major, luup.version_minor, luup.version, isOpenLuup)
	if isOpenLuup or ( luup.version_branch == 1 and luup.version_major >= 7 ) then
		return true
	end
	return false
end

local function runOnce(dev)
	assert(dev ~= nil)
	local rev = getVarNumeric("Version", 0, dev)
	if rev == 0 then
		-- Initialize for new instance
		D("runOnce() Performing first-time initialization!")
		setVar(HASID, "ModeSetting", "1:;2:;3:;4:", dev )
		luup.attr_set( "category_num", 4, dev )
		luup.attr_set( "subcategory_num", 0, dev )
	end

	initVar(MYSID, "Enabled", 1, dev)
	initVar(MYSID, "NumExp", 8, dev)
	initVar(MYSID, "DebugMode", 0, dev)
	initVar(MYSID, "Message", "", dev)
	initVar(MYSID, "RequestURL", "", dev)
	initVar(MYSID, "Interval", "1800", dev)
	initVar(MYSID, "Timeout", "30", dev)
	initVar(MYSID, "QueryArmed", "1", dev)
	initVar(MYSID, "ResponseType", "text", dev)
	initVar(MYSID, "Trigger", "err", dev)
	initVar(MYSID, "Failed", "1", dev)
	initVar(MYSID, "LastQuery", "0", dev)
	initVar(MYSID, "LastRun", "0", dev)
	initVar(MYSID, "LogRequests", "0", dev)
	initVar(MYSID, "EvalInterval", "", dev)
	initVar(MYSID, "MessageExpr", "", dev)
	initVar(MYSID, "SSLVerify", "", dev)
	initVar(MYSID, "SSLProtocol", "", dev)
	initVar(MYSID, "SSLOptions", "", dev)
	initVar(MYSID, "UseCurl", "0", dev)
	initVar(MYSID, "CurlOptions", "", dev)
	initVar(MYSID, "CAFile", "", dev)
	initVar( MYSID, "DeviceErrorOnFailure", 1, dev )
	initVar( MYSID, "MaxResponseSize", "", dev )

	initVar(SSSID, "Armed", "0", dev)
	initVar(SSSID, "Tripped", "0", dev)
	initVar(SSSID, "AutoUntrip", "0", dev)

	-- No matter what happens above, if our versions don't match, force that here/now.
	if rev < _CONFIGVERSION then
		deleteVar( MYSID, "RawResponse", dev )
		deleteVar( MYSID, "LastResponse", dev )
		deleteVar( MYSID, "LastResponseLimit", dev )

		luup.variable_set(MYSID, "Version", _CONFIGVERSION, dev)
	end
end

-- runQuery is the call_delay callback. It takes one argument (exactly), which we
-- format as "stamp:devno"
function runQuery(p)
	D("runQuery(%1)", p)
	-- D("runQuery() hackity hack... scheduler.current_device is %1", _G.package.loaded['openLuup.scheduler'].current_device())
	local stepStamp,dev

	stepStamp,dev = string.match(p, "(%d+):(%d+)")
	dev = tonumber(dev) or error "Invalid device number"

	stepStamp = tonumber(stepStamp)
	if stepStamp ~= runStamp then
		D("runQuery() stamp mismatch (got %1, expected %2). Newer thread running! I'm out...", stepStamp, runStamp)
		return
	end

	if not isEnabled( dev ) then
		L("Query skipped; disabled.")
		setMessage( "Disabled" )
		return -- without rescheduling
	end

	if getVarNumeric( "QueryArmed", 1, dev ) ~= 0 and not isArmed( dev ) then
		L("Query skipped; configured to query only when armed")
		setMessage("Disarmed; query skipped.", dev)
		setVar( SSSID, "Tripped", "0", dev )
		runStamp = runStamp + 1
		return -- without rescheduling
	end

	-- Are we doing an eval tick, or running a request?
	local timeNow = os.time()
	luup.variable_set(MYSID, "LastRun", timeNow, dev)
	local last = getVarNumeric( "LastQuery", 0, dev )
	local interval = getVarNumeric( "Interval", 0, dev )
	if isArmed then
		interval = getVarNumeric( "ArmedInterval", interval, dev )
	end
	local qtype = luup.variable_get(MYSID, "ResponseType", dev) or "text"
	if timeNow >= ( last + interval ) then
		-- Mark time, always, even if the query fails.
		luup.variable_set( MYSID, "LastQuery", timeNow, dev )
		luup.variable_set( MYSID, "LastEval", timeNow, dev )

		-- What type of query?
		if qtype == "json" then
			doJSONQuery(dev)
		else
			doMatchQuery(dev)
		end
	elseif qtype == "json" then
		-- Not time, but for JSON we may do an eval if re-eval ticks are enabled.
		local evalTick = getVarNumeric( "EvalInterval", 0, dev )
		if evalTick > 0 then
			L("Performing re-evaluation of prior response")
			luup.variable_set( MYSID, "LastEval", timeNow, dev )
			doEval( dev ) -- pass no context, doEval will reproduce it
		end
	end

	-- Schedule next run for interval delay.
	scheduleNext(dev, nil, stepStamp)
end

local function forceUpdate(dev)
	D("forceUpdate(%1)", dev)
	assert(dev ~= nil)
	luup.variable_set( MYSID, "LastQuery", 0, dev )
	runStamp = runStamp + 1
	scheduleNext(dev, 1, runStamp)
end

function arm(dev)
	D("arm(%1) arming!", dev)
	assert(dev ~= nil)
	if not isArmed(dev) then
		setVar(SSSID, "Armed", "1", dev)
		-- Do not set ArmedTripped; Luup semantics
		forceUpdate(dev)
	end
end

function disarm(dev)
	D("disarm(%1) disarming!", dev)
	assert(dev ~= nil)
	if isArmed(dev) then
		setVar(SSSID, "Armed", "0", dev)
	end
	if getVarNumeric( "QueryArmed", 1, dev ) ~= 0 then
		setVar(SSSID, "Tripped", "0", dev)
		setMessage( "Disarmed; query skipped." )
	end
	-- Do not set ArmedTripped; Luup semantics
end

function requestLogging( dev, enabled )
	D("requestLogging(%1,%2)", dev, enabled )
	if enabled then
		setVar( MYSID, "LogRequests", "1", dev )
		L("Request logging enabled. Detailed logging will begin at next request/eval.")
	else
		setVar( MYSID, "LogRequests", "0", dev )
	end
end

function actionSetEnabled( dev, newVal )
	D("actionSetEnabled(%1,%2)", dev, newVal)
	newVal = tonumber( newVal ) or 1
	local enabled = newVal ~= 0
	if enabled ~= isEnabled( dev ) then
		-- Change
		luup.variable_set( MYSID, "Enabled", enabled and "1" or "0", dev )
		if enabled then forceUpdate( dev ) end
	end
	return true
end

function actionDoRequest( dev )
	L("Request by action")
	forceUpdate( dev )
end

function actionSetDebug( dev, state )
	D("actionSetDebug(%1,%2)", dev, state)
	if state == 1 or state == "1" or state == true or state == "true" then
		debugMode = true
		D("actionSetDebug() debug logging enabled")
	end
end

local function getDevice( dev, pdev, v ) -- luacheck: ignore 212
	if v == nil then v = luup.devices[dev] end
	local devinfo = {
		  devNum=dev
		, ['type']=v.device_type
		, description=v.description or ""
		, room=v.room_num or 0
		, udn=v.udn or ""
		, id=v.id
		, ['device_json'] = luup.attr_get( "device_json", dev )
		, ['impl_file'] = luup.attr_get( "impl_file", dev )
		, ['device_file'] = luup.attr_get( "device_file", dev )
		, manufacturer = luup.attr_get( "manufacturer", dev ) or ""
		, model = luup.attr_get( "model", dev ) or ""
	}
	local req = string.format( "http://localhost%s/data_request?id=status&DeviceNum=%d&output_format=json",
		isOpenLuup and ":3480" or "/port_3480", dev )
	local rc,t,httpStatus = luup.inet.wget( req, 15 )
	if httpStatus ~= 200 or rc ~= 0 then
		devinfo['_comment'] = string.format( 'State info could not be retrieved, rc=%d, http=%d', rc, httpStatus )
		return devinfo
	end
	local d = json.decode(t)
	local key = "Device_Num_" .. dev
	if d ~= nil and d[key] ~= nil and d[key].states ~= nil then d = d[key].states else d = nil end
	devinfo.states = d or {}
	return devinfo
end

function init(dev)
	D("init(%1)", dev)
	L("starting version %1 device %2 (#%3)", _PLUGIN_VERSION, luup.devices[dev].description, dev)

	-- Initialize instance data
	pluginDevice = dev
	runStamp = 0
	isOpenLuup = false
	isALTUI = false
	logCapture = {}
	myChildren = {}
	if getVarNumeric( "DebugMode", 0, dev, MYSID ) ~= 0 then
		debugMode = true
		D("init() debug enabled by DebugMode state variable")
	end

	-- Check for ALTUI and OpenLuup; find children.
	for k,v in pairs(luup.devices) do
		if v.device_type == "urn:schemas-upnp-org:device:altui:1" and v.device_num_parent == 0 then
			D("init() detected ALTUI at %1", k)
			isALTUI = true
			local rc,rs,jj,ra = luup.call_action("urn:upnp-org:serviceId:altui1", "RegisterPlugin",
				{
					newDeviceType=MYTYPE,
					newScriptFile="J_SiteSensor1_ALTUI.js",
					newDeviceDrawFunc="SiteSensor_ALTUI.DeviceDraw",
					newFavoriteFunc="SiteSensor_ALTUI.Favorite"
				}, k )
			D("init() ALTUI's RegisterPlugin action returned resultCode=%1, resultString=%2, job=%3, returnArguments=%4", rc,rs,jj,ra)
		elseif v.device_type == "openLuup" and v.device_num_parent == 0 then
			D("init() detected openLuup")
			isOpenLuup = true

		elseif v.device_num_parent == dev then
			D("init() found child %1", v.id)
			myChildren[ v.id ] = k
		end
	end

	-- Make sure we're in the right environment
	if not checkVersion(dev) then
		setMessage("Unsupported firmware", dev)
		L("This plugin is currently supported only in UI7; buh-bye!")
		luup.set_failure( 1, dev )
		return false, "Unsupported firmware", _PLUGIN_NAME
	end

	-- See if we need any one-time inits
	runOnce(dev)

	-- Other inits
	math.randomseed( os.time() )

	-- Check that any child devices have been created.
	D("init() assessing children...")
	local numchild = getVarNumeric( "NumExp", 8, dev, MYSID )
	local ptr = luup.chdev.start( dev )
	local changed = false
	for ix=1,numchild do
		local childid = string.format( "ch%d", ix )
		local childtype = luup.variable_get( MYSID, "Child" .. tostring(ix), dev ) or ""
		D("init() child id %1 should be type %2", childid, childtype)
		if childtype ~= "" then
			-- We should have a child.
			local devnum = myChildren[ childid ]
			D("init() child id %1 found devnum %2 luup.device=%3", childid, devnum, luup.devices[devnum])
			if devnum then
				local v = luup.devices[ devnum ]
				-- We do. Right type?
				if v.device_type == childtype then
					-- Yes. Append (existing)
					local df = dfMap[ v.device_type ]
					if df then
						luup.chdev.append( dev, ptr, v.id, v.description, v.device_type,
							luup.attr_get( 'device_file', devnum ) or "", "", "", false )
						local s = getVarNumeric( "Version", 0, devnum, MYSID )
						if s == 0 then
							-- First-time init for child
							L("Performing first-time inits for %1", childid)
							luup.attr_set( "category_num", df.category, devnum )
							luup.attr_set( "subcategory_num", df.subcategory or 0, devnum )
							luup.attr_set( "room", luup.devices[dev].room_num or 0, devnum )
							luup.variable_set( MYSID, "Version", _CONFIGVERSION, devnum )
						end
						-- Copy current value to child for display
						local cv = luup.variable_get( MYSID, "Value"..tostring(ix), dev ) or ""
						setVar( df.service, df.variable, cv, devnum )
					else
						L({level=1,msg="Missing dfMap entry for %1; child for expr %2 will be removed."}, v.device_type, ix)
						changed = true
					end
				else
					L("Child for expr %1 type changed from %2 to %3, removing child; this will cause a Luup reload.",
						ix, v.device_type, childtype)
					changed = true
				end
			else
				-- Missing child. Append.
				local df = dfMap[ childtype ]
				if df then
					local desc = " " .. tostring(ix)
					desc = luup.attr_get( "name", dev ):sub(1, 20-#desc) .. desc
					local vv = { ",room=" .. ( luup.devices[dev].room_num or 0 ) }
					if df.category then table.insert( vv, ",category_num=" .. df.category ) end
					if df.subcategory then table.insert( vv, ",subcategory_num=" .. df.subcategory ) end
					luup.chdev.append( dev, ptr, childid, desc, "", df.device_file, "", "", false )
					L("Creating new child device for expr %1; this will cause a Luup reload.", ix)
					changed = true
				else
					L({level=1,msg="Missing dfMap entry for %1"}, childtype)
				end
			end
		else
			-- Child where we don't need one?
			if myChildren[childid] then
				L("Child for expr %1 no longer needed, removing; this will cause a Luup reload.", ix)
				changed = true
			end
		end
	end
	if changed then
		L({level=2,msg="Child device devices; this will cause a Luup reload now."})
	end
	luup.chdev.sync( dev, ptr )

	-- If sensor is query armed, and not armed, clear tripped explicitly.
	runStamp = 1
	if not isEnabled( dev ) then
		setVar( SSSID, "Tripped", "0", dev )
		setMessage( "Disabled" );
	elseif getVarNumeric( "QueryArmed", 1, dev ) ~= 0 and not isArmed( dev ) then
		setVar( SSSID, "Tripped", "0", dev )
		setMessage( "Disarmed; query skipped." );
	else
		scheduleNext(dev, nil, runStamp)
	end

	luup.set_failure( 0, dev )
	return true, "OK", _PLUGIN_NAME
end

function requestHandler(lul_request, lul_parameters, lul_outputformat)
	D("requestHandler(%1,%2,%3) luup.device=%4", lul_request, lul_parameters, lul_outputformat, luup.device)
	local action = lul_parameters['action'] or lul_parameters["command"] or ""
	local deviceNum = tonumber( lul_parameters['device'], 10 ) or pluginDevice
	if action == "debug" then
		local err,msg,job,args = luup.call_action( MYSID, "SetDebug", { debug=1 }, deviceNum )
		return string.format("Device #%s result: %s, %s, %s, %s", tostring(deviceNum), tostring(err), tostring(msg), tostring(job), dump(args))
	end

	if action:sub( 1, 3 ) == "ISS" then
		-- ImperiHome ISS Standard System API, see http://dev.evertygo.com/api/iss#types
		local path = lul_parameters['path'] or action:sub( 4 ) -- Work even if I'home user forgets &path=
		if path == "/system" then
			return json.encode( { id="SiteSensor-" .. luup.pk_accesspoint, apiversion=1 } ), "application/json"
		elseif path == "/rooms" then
			local roomlist = { { id=0, name="No Room" } }
			for rn,rr in pairs( luup.rooms ) do
				table.insert( roomlist, { id=rn, name=rr } )
			end
			return json.encode( { rooms=roomlist } ), "application/json"
		elseif path == "/devices" then
			local devices = {}
			for lnum,ldev in pairs( luup.devices ) do
				if ldev.device_type == MYTYPE then
					local dev = { id=tostring(lnum),
						name=ldev.description or ("#" .. lnum),
						["type"]="DevDoor",
						params={
							{ key="armable", value="1" },
							{ key="ackable", value="0" },
							{ key="Armed", value=luup.variable_get( SSSID, "Armed", lnum) or "0" },
							{ key="Tripped", value=luup.variable_get( SSSID, "Tripped", lnum ) or "0" },
							{ key="lasttrip", value=luup.variable_get( SSSID, "LastTrip", lnum ) or "0" }
						}
					}
					if (ldev.room_num or 0) ~= 0 then dev.room = tostring(ldev.room_num) end
					table.insert( devices, dev )

					-- Make a device for each formula that stores a value (if any). Skip empties.
					for k = 1,8 do
						local frm = luup.variable_get( MYSID, "Expr" .. k, lnum ) or ""
						if frm ~= "" then
							dev = { id=string.format("%d-%d", lnum, k),
								name=(ldev.description or ("#" .. lnum)) .. "-" .. k,
								["type"]="DevGenericSensor",
								defaultIcon=nil,
								params={
									{ key="Value", value=luup.variable_get(MYSID, "Value" .. k, lnum) or "" }
								}
							}
							if (ldev.room_num or 0) ~= 0 then dev.room = tostring(ldev.room_num) end
							table.insert( devices, dev )
						end
					end
				end
			end
			return json.encode( { devices=devices } ), "application/json"
		else
			D("requestHandler: command %1 not implemented, ignored", action)
			return "{}", "application.json"
		end
	end

	if action == "status" then
		if json == nil then return "Missing json library", "text/plain" end
		local st = {
			name=_PLUGIN_NAME,
			version=_PLUGIN_VERSION,
			configversion=_CONFIGVERSION,
			author="Patrick H. Rigney (rigpapa)",
			url=_PLUGIN_URL,
			['type']=MYTYPE,
			responder=luup.device,
			timestamp=os.time(),
			system = {
				version=luup.version,
				isOpenLuup=isOpenLuup,
				isALTUI=isALTUI,
				units=luup.attr_get( "TemperatureFormat", 0 ),
			},
			devices={}
		}
		st.luaxp_version = luaxp._VERSION or "?"
		for k,v in pairs( luup.devices ) do
			if v.device_type == MYTYPE then
				local devinfo = getDevice( k, luup.device, v ) or {}
				table.insert( st.devices, devinfo )
			end
		end
		return json.encode( st ), "application/json"

	elseif action == "getvtypes" then
		local r = {}
		if isOpenLuup then
			-- For openLuup, only show device types for resources that are installed
			local loader = require "openLuup.loader"
			if loader.find_file ~= nil then
				for k,v in pairs( dfMap ) do
					if loader.find_file( v.device_file ) then
						r[k] = v
					end
				end
			else
				L{level=1,msg="PLEASE UPGRADE YOUR OPENLUUP TO 181122 OR HIGHER FOR FULL SUPPORT OF SITESENSOR VIRTUAL DEVICES"}
			end
		else
			r = dfMap
		end
		return json.encode( r ), "application/json"

	elseif action == "recipe" then
		local recipe = { name=luup.devices[deviceNum].description, version=os.time(), config={} }
		recipe.signature = [["']]
		for _,v in ipairs( { "RequestURL", "Interval", "Timeout", "QueryArmed", "ResponseType", "Trigger", "NumExp", "TripExpression" } ) do
			local val = luup.variable_get( MYSID, v, deviceNum ) or ""
			recipe.config[v] = val
		end
		for ix=1,(tonumber(recipe.config.NumExp) or 8) do
			recipe.config['Expr'..ix] = luup.variable_get( MYSID, "Expr"..ix, deviceNum ) or ""
			local child = luup.variable_get( MYSID, "Child"..ix, deviceNum ) or ""
			if child ~= "" then recipe.config['Child'..ix] = child end
		end
		r = [[<h2>Current Config</h2><pre>]]
		r = r .. json.encode(recipe, { indent=true })
		r = r .. [[</pre><p>You can copy-paste the above, but be careful not to paste it into Word or other text editors or tools that would alter the quotes or content. A plain-text editor is the best tool. <b>Be sure to remove any auth keys or other private data before posting publicly!</b></p><h2>Load New Recipe</h2><form method="post" action="data_request"><input type="hidden" name="id" value="lr_SiteSensor"><input type="hidden" name="action" value="loadrecipe"><input type="hidden" name="device" value="]] .. deviceNum .. [["><label>Recipe:<textarea name="rdata" wrap="soft" rows="4" cols="80"></textarea></label><br/>Loading the recipe will overwrite this SiteSensor's current configuration. OK/ready? <input type="submit" name="submit" value="Load Recipe"></form>]]
		return r, "text/html"

	elseif action == "loadrecipe" then
		local recipe = lul_parameters.rdata or ""
		local pos,ends = recipe:find( "=== BEGIN SITESENSOR RECIPE ===%s+" )
		if pos then
			recipe = recipe:sub( ends + 1 ):gsub( "=== END SITESENSOR RECIPE ===.*", "" )
			local mime = require "mime"
			recipe = mime.unb64( recipe )
			if not recipe then return "ERROR\nInvalid recipe: can't decode/invalid block format", "text/plain" end
		else
			if not recipe:find( [[signature:%s*"%\"'"]] ) then
				return "ERROR\nInvalid recipe: quote corruption", "text/html"
			end
		end
		local data,err = json.decode( recipe )
		if not data then return "ERROR\nInvalid recipe: "..err, "text/plain" end
		if not data.config then return "ERROR\nInvalid recipe: no config", "text/plain" end
		for k,v in pairs( data.config ) do
			luup.variable_set( MYSID, k, v, deviceNum )
		end
		return "OK\nRecipe " .. tostring(data.name) .. " loaded.\n"..recipe, "text/plain"

	elseif action == "qdiag" and not isOpenLuup then
		local qd = getInstallPath() .. "qdiag-" .. deviceNum .. ".tmp.lzo"
		os.remove( qd )
		local fn = luup.variable_get( MYSID, "qf", deviceNum ) or "/notexists"
		if os.execute( "cp '" .. fn .. ".lzo' '" .. qd .. "'" ) == 0 then
			return "OK\n" .. qd .. " updated; download it now from Apps > Develop apps > Luup files", "text/plain"
		else
			return "ERROR\n" .. fn .. " could not be copied to " .. qd, "text/plain"
		end

	elseif action == "alive" then
		return '{"status":true}', "application/json"

	end

	return "<html><head><title>" .. _PLUGIN_NAME .. " Request Handler"
		.. "</title></head><body bgcolor='white'>Request format: <tt>http://" .. (luup.attr_get( "ip", 0 ) or "...")
		.. "/port_3480/data_request?id=lr_" .. lul_request
		.. "&action=</tt><p>Actions: status, debug, ISS"
		.. "<p>Imperihome ISS URL: <tt>...&action=ISS&path=</tt><p>Documentation: <a href='"
		.. _PLUGIN_URL .. "' target='_blank'>" .. _PLUGIN_URL .. "</a></body></html>"
		, "text/html"
end
