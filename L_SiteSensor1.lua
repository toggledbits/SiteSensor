-- -----------------------------------------------------------------------------
-- L_SiteSensor.lua
-- Copyright 2016, 2017 Patrick H. Rigney, All Rights Reserved
-- This file is available under GPL 3.0. See LICENSE in documentation for info.
--
-- TO-DO:
--   TCP direct
--   Headers and type (GET, PUT, etc.) for HTTP (e.g. Bearer for authentication)
-- -----------------------------------------------------------------------------
module("L_SiteSensor1", package.seeall)

local _VERSION = "0.1"
local _CONFIGVERSION = 00101

local MYSID = "urn:toggledbits-com:serviceId:SiteSensor1"
local SSSID = "urn:micasaverde-com:serviceId:SecuritySensor1"
local HASID = "urn:micasaverde-com:serviceId:HaDevice1"

local debugMode = false
local traceMode = false

local https = require("ssl.https")
local http = require("socket.http")
local ltn12 = require("ltn12")
local dkjson = require('dkjson')
local luaxp = require("L_LuaXP")

local function trace( typ, msg )
    local ts = os.time()
    local r
    local t = {
        ["type"]=typ,
        plugin="SiteSensor",
        pluginVersion=_CONFIGVERSION,
        serial=luup.pk_accesspoint,
        systime=ts,
        sysver=luup.version,
        longitude=luup.longitude,
        latitude=luup.latitude,
        timezone=luup.timezone,
        city=luup.city,
        message=msg
    }

    local tHeaders = {}
    local body = dkjson.encode(t)
    tHeaders["Content-Type"] = "application/json"
    tHeaders["Content-Length"] = string.len(body)

    -- Make the request.
    local respBody, httpStatus, httpHeaders
    http.TIMEOUT = 10
    respBody, httpStatus, httpHeaders = http.request{
        url = "http://www.toggledbits.com/luuptrace/",
        source = ltn12.source.string(body),
        sink = ltn12.sink.table(r),
        method = "POST",
        headers = tHeaders,
        redirect = false
    }
    if httpStatus == 401 or httpStatus == 404 then
        traceMode = false
    end
end

local function L(msg, ...)
    local str
    if type(msg) == "table" then
        str = msg["prefix"] .. msg["msg"]
    else
        str = "SiteSensor: " .. msg
    end
    local ipos = 1
    while true do
        local i, j, n
        i, j, n = string.find(str, "%%(%d+)", ipos)
        if i == nil then break end
        n = tonumber(n, 10)
        if n >= 1 and n <= table.getn(arg) then
            local val = arg[n]
            if type(val) == "table" then
                val = dkjson.encode(val)
            end
            if i == 1 then
                str = tostring(val) .. string.sub(str, j+1)
            else
                str = string.sub(str, 1, i-1) .. tostring(val) .. string.sub(str, j+1)
            end
        end
        ipos = j + 1
    end
    luup.log(str)
    if traceMode then
        pcall( trace, "log", str )
    end
end

local function D(msg, ...)
    if debugMode then
        L({msg=msg,prefix="SiteSensor(debug)::"}, unpack(arg))
    end
end

-- Take a string and split it around sep, returning table (indexed) of substrings
-- For example abc,def,ghi becomes t[1]=abc, t[2]=def, t[3]=ghi
-- Returns: table of values, count of values (integer ge 0)
local function split(s, sep)
    local t = {}
    local n = 0
    if (#s == 0) then return t,n end -- empty string returns nothing
    local i,j
    local k = 1
    repeat
        i, j = string.find(s, sep or "%s*,%s*", k)
        if (i == nil) then
            table.insert(t, string.sub(s, k, -1))
            n = n + 1
            break
        else
            table.insert(t, string.sub(s, k, i-1))
            n = n + 1
            k = j + 1
        end
    until k > string.len(s)
    return t, n
end

local function parseRefExpr(ex, ctx)
    D("parseRefExpr(%1,ctx)", ex, ctx)
    local cx, err
    cx, err = luaxp.compile(ex)
    if cx == nil then
        L("parseRefExpr() failed to parse expression `%1', %2", ex, err)
        return nil
    end

    local val
    val, err = luaxp.run(cx, ctx)
    if val == nil then
        L("parseRefExpr() failed to execute `%1', %2", ex, err)
    end
    return val
end

local function checkVersion()
    if ( luup.version_branch == 1 and luup.version_major == 7 ) then
        return true
    end
    return false
end

-- Get numeric variable, or return default value if not set or blank
local function getVarNumeric( name, dflt, dev, serviceId )
    if dev == nil then dev = luup.device end
    if serviceId == nil then serviceId = MYSID end
    local s = luup.variable_get(serviceId, name, dev)
    if (s == nil or s == "") then return dflt end
    s = tonumber(s, 10)
    if (s == nil) then return dflt end
    return s
end

local function setMessage(s)
    luup.variable_set(MYSID, "Message", s or "", luup.device)
end

local function isFailed()
    local failed = getVarNumeric("Failed", 0, luup.device, MYSID)
    return failed ~= 0
end

local function fail(failState)
    assert(type(failState) == "boolean")
    D("fail(%1)", failState)
    if failState ~= isFailed() then
        local fval = 0
        if failState then fval = 1 end
        luup.variable_set(MYSID, "Failed", fval, luup.device)
    end
end

local function isArmed()
    local armed = getVarNumeric("Armed", 0, luup.device, SSSID)
    return armed ~= 0
end

local function isTripped()
    local tripped = getVarNumeric("Tripped", 0, luup.device, SSSID)
    return tripped ~= 0
end

local function trip(tripped)
    assert(type(tripped) == "boolean")
    D("trip(%1)", tripped)
    local newVal
    if tripped ~= isTripped() then
        if tripped then
            D("trip() marking tripped")
            newVal = "1"
            luup.variable_set(SSSID, "LastTrip", os.time(), luup.device)
        else
            D("trip() marking not tripped")
            newVal = "0"
        end
        luup.variable_set(SSSID, "Tripped", newVal, luup.device)
        if isArmed() then
            D("trip() marked armed-tripped")
            luup.variable_set(SSSID, "ArmedTripped", newVal, luup.device)
        else
            D("trip() not armed-tripped")
            luup.variable_set(SSSID, "ArmedTripped", "0", luup.device)
        end
    end
end

local function runOnce()
    local rev = getVarNumeric("Version", 0)
    if (rev == 0) then
        -- Initialize for new installation
        D("runOnce() Performing first-time initialization!")
        luup.variable_set(MYSID, "Message", "", luup.device)
        luup.variable_set(MYSID, "RequestURL", "", luup.device)
        luup.variable_set(MYSID, "Interval", "1800", luup.device)
        luup.variable_set(MYSID, "Timeout", "50", luup.device)
        luup.variable_set(MYSID, "QueryArmed", "1", luup.device)
        luup.variable_set(MYSID, "ResponseType", "text", luup.device)
        luup.variable_set(MYSID, "Trigger", "err", luup.device)
        luup.variable_set(MYSID, "Failed", "1", luup.device)
        luup.variable_set(MYSID, "LastQuery", "0", luup.device)
        luup.variable_set(MYSID, "LastRun", "0", luup.device)
        luup.variable_set(SSSID, "LastTrip", "0", luup.device)
        luup.variable_set(SSSID, "Armed", "0", luup.device)
        luup.variable_set(SSSID, "Tripped", "0", luup.device)
        luup.variable_set(SSSID, "ArmedTripped", "0", luup.device)
    end

    -- No matter what happens above, if our versions don't match, force that here/now.
    if (rev ~= _CONFIGVERSION) then
        luup.variable_set(MYSID, "Version", _CONFIGVERSION, luup.device)
    end
end

function scheduleNext()
    -- First, get and sanitize our interval
    local delay = getVarNumeric("Interval", 1800)
    if isArmed() then
        delay = getVarNumeric("ArmedInterval", delay)
    end
    if delay < 1 then delay = 60 end
    D("scheduleNext() interval is %1", delay)
    -- Now, see if we've missed an interval
    local nextQuery = getVarNumeric("LastRun", 0) + delay
    local now = os.time()
    local nextDelay = nextQuery - now
    if nextDelay < 0 then
        -- We missed an interval completely
        D("scheduleNext() next should have been %1, now %2, we missed it!", nextQuery, now)
        delay = 1
    elseif nextDelay < delay then
        D("scheduleNext() next coming a little sooner, reducing delay from %1 to %2", delay, nextDelay)
        delay = nextDelay
    end
    luup.call_delay("runQuery", delay)
    D("scheduleNext() scheduled next runQuery() for %1", delay)
end

local function doRequest(url, method, body)
    if method == nil then method = "GET" end

    -- A few other knobs we can turn
    local timeout = getVarNumeric("Timeout", 60) -- ???
    -- local maxlength = getVarNumeric("MaxLength", 262144) -- ???

    local src
    local tHeaders = {}

    -- Build post/put data
    if type(body) == "table" then
        body = dkjson.encode(body)
        tHeaders["Content-Type"] = "application/json"
    end
    if body ~= nil then
        tHeaders["Content-Length"] = string.len(body)
        src = ltn12.source.string(body)
    else
        src = nil
    end

    -- HTTP or HTTPS?
    local requestor
    if url:lower():find("https:") then
        requestor = https
    else
        requestor = http
    end

    -- Make the request.
    local respBody, httpStatus, httpHeaders
    local r = {}
    http.TIMEOUT = timeout -- N.B. http not https, regardless
    D("doRequest() %1 %2, headers=%3", method, url, tHeaders)
    respBody, httpStatus, httpHeaders = requestor.request{
        url = url,
        source = src,
        sink = ltn12.sink.table(r),
        method = method,
        headers = tHeaders,
        redirect = false
    }
    D("doRequest() request returned httpStatus=%1, respBody=%2", httpStatus, respBody)

    -- Since we're using the table sink, concatenate chunks to single string.
    respBody = table.concat(r)

    -- See what happened. Anything 2xx we reduce to 200 (OK).
    if httpStatus >= 200 and httpStatus <= 299 then
        -- Success response with no data, take shortcut.
        return false, respBody, 200
    end
    return true, respBody, httpStatus
end

local function doMatchQuery( type )
    local url = luup.variable_get(MYSID, "RequestURL", luup.device) or ""
    local pattern = luup.variable_get(MYSID, "Pattern", luup.device) or "^HTTP/1.. 200"
    local timeout = getVarNumeric("Timeout", 60)
    local trigger = luup.variable_get(MYSID, "Trigger", luup.device) or nil

    local buf = ""
    local cond, httpStatus, httpHeaders
    local matched = false
    local err = false
    local matchValue
    local requestor = http

    -- HTTP or HTTPS?
    local requestor
    if url:lower():find("https:") then
        requestor = https
    else
        requestor = http
    end

    D("doMatchQuery() seeking %1 in %2", pattern, url)

    http.TIMEOUT = timeout
    setMessage("Requesting...")
    cond, httpStatus, httpHeaders = requestor.request {
        url = url,
        redirect = false,
        sink = function(chunk, source_err)
            if chunk == nil then
                -- no more data to process
                D("doMatchQuery() chunk is nil")
                if source_err then
                    return nil, "Source error"
                else
                    return true
                end
            elseif chunk == "" then
                return true
            else
                buf = buf .. chunk
                local l = string.len(buf)
                D("doMatchQuery() valid chunk, buf now contains %1", l)
                if l > 2048 then
                    buf = string.sub(buf, l-2048+1)
                end
                local s,e,p
                s, e, p = string.find(buf, pattern)
                if s ~= nil then
                    -- LastMatchValue will get the first capture if there is one, otherwise whatever matched
                    if p == nil then
                        matchValue = string.sub(buf, s, e)
                    else
                        matchValue = p
                    end
                    matched = true
                    return nil, "Matched" -- early exit, fake valid response
                end
                return true
            end
        end
    }
    --[[ Notes
        Interesting semantics to the return values here. If the pattern is matched before the body response has been
        completely processed, our sink returns nil (because hey, work is done at that point), but it causes request()
        to return "cond=nil,httpStatus=Matched pattern" (or whatever the sink returned). If no match occurs, the full
        body is read (because the sink keeps looking for the pattern and doesn't find it), but in that case, request()
        returns the expected/documented "cond=1,httpStatus=200" response.
    ]]
    D("doMatchQuery() returned from request(), cond=%1, httpStatus=%2, httpHeaders=%3", cond, httpStatus, httpHeaders)
    if cond == nil or (cond == 1 and httpStatus == 200) then
        if matched then
            setMessage("Valid response; matched!")
        else
            setMessage("Valid response; no match.")
        end
        local lastVal = luup.variable_get(MYSID, "LastMatchValue", luup.device)
        if (lastVal == nil or lastVal ~= matchValue) then
            luup.variable_set(MYSID, "LastMatchValue", matchValue, luup.device)
        end
    else
        setMessage("Invalid response (" .. tostring(httpStatus) .. ")")
        err = true
    end

    -- Set trip state based on result.
    D("doMatchQuery() matched is %1", matched)
    local tripState = isTripped()
    local newTrip
    if trigger == "neg" then
        newTrip = not matched
    elseif trigger == "err" then
        newTrip = err
    else
        newTrip = matched
    end
    trip(newTrip)
end

local function doJSONQuery(url)
    local url = luup.variable_get(MYSID, "RequestURL", luup.device) or ""
    local timeout = getVarNumeric("Timeout", 60)
    local maxlength = getVarNumeric("MaxLength", 262144)
    local body, httpStatus, httpHeaders
    local err = false
    local texp = luup.variable_get(MYSID, "TripExpression", luup.device)
    local ttype = luup.variable_get(MYSID, "Trigger", luup.device) or "err"
    
    setMessage("Requesting JSON...")
    err,body,httpStatus = doRequest(url)
    D("doJSONQuery() request returned httpStatus=%1, body=%2", httpStatus, body)
    local ctx = { response={}, status={ timestamp=os.time(), valid=0, httpStatus=httpStatus } }
    if body == nil or err then
        -- Error; trip sensor
        D("doJSONQuery() setting tripped and bugging out...")
        fail(true)
        if ttype == "err" then trip(true) end
    else
        D("doJSONQuery() fixing up JSON response for parsing")
        setMessage("Parsing response...")
        -- Fix booleans, which dkjson doesn't seem to understand (gives nil)
        body = string.gsub( body, ": *true *,", ": 1," )
        body = string.gsub( body, ": *false *,", ": 0," )

        -- Process JSON response. First parse response.
        local t, pos, err
        t, pos, err = dkjson.decode(body)
        if err then
            L("Unable to decode JSON response, %2 (dev %1)", luup.device, err)
            -- If TripExpression isn't used, trip follows status
            fail(true)
            if ttype == "err" then trip(true) end
            -- Set state var for invalid response?
            setMessage("Invalid response")
            ctx.status.jsonStatus = err
        else 
            D("doJSONQuery() parsed response")
            -- Encapsulate the response
            ctx.status.valid = 1
            ctx.status.jsonStatus = "OK"
            ctx.response = t
            fail(false)
        end
    end

--[[ PHR??? IDEA: When we get to using luaxp, have TripCondition expression that trips if true, untrips if false.
                  This allows the JSON response to control the tripped state. Can luaxp return true/false bool?
            IDEA: When luaxp, function to find an element in a hash array in the data, e.g. find(devices, 170) would
                  return the context for the device status/info. This may imply that luaxp needs to be upgraded to be
                  able to return tables as function value.
            IDEA: Have device status display show "Last Result:" label for message, and "Next Query" time/date.
]]


    -- Since we got a valid response, indicate not tripped, unless using TripExpression, then that.
    -- Reset state var for (in)valid response?
    setMessage("Processing response...")
    if ttype == "expr" then
        D("doJSONQuery() parsing TripExpression %1", texp)
        local r = nil
        if texp ~= nil then r = parseRefExpr(texp, ctx) end
        D("doJSONQuery() TripExpression result is %1", r)
        if r == nil
            or (type(r) == "boolean" and r == false)
            or (type(r) == "number" and r == 0)
            or (type(r) == "string" and string.len(r) == 0)
        then
            -- Trip expression is logically (for us) false
            trip(false)
        else    
            -- Trip expression is not logically false (i.e. true)
            trip(true)
        end
    else
        -- No trip expression; trip state follows query success
        D("doJSONQuery() resetting tripped state")
        trip(ctx.status.valid == 0)
    end

    -- Valid response. Let's parse it and set our variables.
    local i
    for i = 1,8 do
        local r = nil
        local ex = luup.variable_get(MYSID, "Expr" .. tostring(i), luup.device)
        D("doJSONQuery() Expr%1=%2", i, ex or "nil")
        if ex ~= nil and string.len(ex) > 0 then
            D("doJSONQuery() parsing %1 to value", ex)
            r = parseRefExpr(ex, ctx)
            D("doJSONQuery() parsed value of %1 is %2", ex, tostring(r))
        else
            luup.variable_set(MYSID, "Expr" .. tostring(i), "", luup.device)
        end
        
        -- Canonify the result value
        if r == nil then 
            r = ""
        elseif type(r) == "boolean" then
            if r then r = "1" else r = "0" end
        else
            r = tostring(r)
        end

        -- Save if changed.
        local oldVal = luup.variable_get(MYSID, "Value" .. tostring(i), luup.device)
        D("doJSONQuery() newval=%1, oldVal=%2", r, oldVal)
        if r ~= oldVal then
            -- Set new value only if changed
            D("doJSONQuery() Expr%1 value changed, was %2 now %3", i, oldVal, r)
            luup.variable_set(MYSID, "Value" .. tostring(i), tostring(r), luup.device)
        end
    end

    local msg
    if ctx.status.valid == 0 then
        msg = "Last query failed, "
        if ctx.status.httpStatus ~= 200 then
            msg = msg .. "HTTP status " .. tostring(ctx.status.httpStatus)
        else
            msg = msg .. "JSON error " .. ctx.status.jsonStatus
        end
    else
        msg = "Last query succeeded!"
    end
    setMessage( msg )
end

function runQuery()
    -- We may only query when armed, so check that.
    local queryArmed = getVarNumeric("QueryArmed", 1)
    if queryArmed == 0 or isArmed() then
        local type = luup.variable_get(MYSID, "ResponseType", luup.device) or "text"

        -- What type of query?
        if type == "json" then
            doJSONQuery()
        else
            doMatchQuery()
        end

        -- Timestamp
        luup.variable_set(MYSID, "LastQuery", os.time(), luup.device)
    else
        setMessage("Disarmed; query skipped.")
    end

    -- Run next interval
    luup.variable_set(MYSID, "LastRun", os.time(), luup.device)
    scheduleNext()
end

function arm(dev)
    D("arm() arming!")
    luup.variable_set(SSSID, "Armed", "1", luup.device)
    if isTripped() then
        luup.variable_set(SSSID, "ArmedTripped", "1", luup.device)
    end
end

function disarm(dev)
    D("disarm() disarming!")
    luup.variable_set(SSSID, "Armed", "0", luup.device)
    luup.variable_set(SSSID, "ArmedTripped", "0", luup.device)
end

function init(dev)
    -- Make sure we're in the right environment
    if not checkVersion() then
        L("This plugin is currently supported only in UI7; buh-bye!")
        return false
    end

    -- See if we need any one-time inits
    runOnce()

    -- Schedule next query
    setMessage("")
    scheduleNext()
end
