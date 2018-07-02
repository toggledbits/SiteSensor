-- -----------------------------------------------------------------------------
-- L_SiteSensor.lua
-- Copyright 2016, 2017 Patrick H. Rigney, All Rights Reserved
-- This file is available under GPL 3.0. See LICENSE in documentation for info.
--
-- TO-DO:
--   TCP direct
--   More types (POST, PUT, etc.) for HTTP(S)
--   XML?
-- -----------------------------------------------------------------------------

module("L_SiteSensor1", package.seeall)

local _PLUGIN_NAME = "SiteSensor"
local _PLUGIN_VERSION = "1.8stable180702"
local _PLUGIN_URL = "http://www.toggledbits.com/sitesensor"
local _CONFIGVERSION = 10900

local MYSID = "urn:toggledbits-com:serviceId:SiteSensor1"
local MYTYPE = "urn:schemas-toggledbits-com:device:SiteSensor:1"
local SSSID = "urn:micasaverde-com:serviceId:SecuritySensor1"
local HASID = "urn:micasaverde-com:serviceId:HaDevice1"

local idata = {} -- per-instance data

local isALTUI = false
local isOpenLuup = false
local debugMode = false

local logCapture = {}
local logMax = 50

local https = require("ssl.https")
local http = require("socket.http")
local ltn12 = require("ltn12")
local dkjson = require('dkjson')
local luaxp = require("L_LuaXP")

local function dump(t)
    if t == nil then return "nil" end
    local sep = ""
    local str = "{ "
    for k,v in pairs(t) do
        local val
        if type(v) == "table" then
            val = dump(v)
        elseif type(v) == "function" then
            val = "(function)"
        elseif type(v) == "string" then
            val = string.format("%q", v)
        else
            val = tostring(v)
        end
        str = str .. sep .. tostring(k) .. "=" .. val
        sep = ", "
    end
    str = str .. " }"
    return str
end

local function L(msg, ...)
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
            end
            return tostring(val)
        end
    )
    luup.log(str, level)
    if type(msg) == "string" then -- don't capture debug
        table.insert( logCapture, os.date("%X") .. ": " .. str )
        if #logCapture > logMax then table.remove( logCapture, 1 ) end
        luup.variable_set( MYSID, "LogCapture", table.concat( logCapture, "|" ), luup.device )
    end
end

local function D(msg, ...)
    if debugMode then
        L( { msg=msg,prefix=_PLUGIN_NAME .. "(debug)::" }, ... )
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

local function parseRefExpr(ex, ctx)
    D("parseRefExpr(%1,ctx)", ex, ctx)
    local cx, err
    cx, err = luaxp.compile(ex,ctx)
    if cx == nil then
        L("Failed to parse expression `%1', %2", ex, err)
        return nil
    end

    local val
    val, err = luaxp.run(cx, ctx)
    if val == nil then
        L("Failed to execute `%1', %2", ex, err)
    end
    return val
end

-- Get numeric variable, or return default value if not set or blank
local function getVarNumeric( name, dflt, dev, serviceId )
    assert( dev ~= nil )
    if serviceId == nil then serviceId = MYSID end
    local s = luup.variable_get(serviceId, name, dev)
    if (s == nil or s == "") then return dflt end
    s = tonumber(s, 10)
    if (s == nil) then return dflt end
    return s
end

local function setMessage(s, dev)
    assert(dev ~= nil)
    assert(idata[dev] ~= nil)
    luup.variable_set(MYSID, "Message", s or "", dev)
end

local function isFailed(dev)
    assert(dev ~= nil)
    assert(idata[dev] ~= nil)
    local failed = getVarNumeric("Failed", 0, dev, MYSID)
    return failed ~= 0
end

local function fail(failState, dev)
    assert(dev ~= nil)
    assert(idata[dev] ~= nil)
    assert(type(failState) == "boolean")
    D("fail(%1,%2)", failState, dev)
    if failState ~= isFailed(dev) then
        local fval = 0
        if failState then fval = 1 end
        luup.variable_set(MYSID, "Failed", fval, dev)
    end
end

local function isArmed(dev)
    assert(dev ~= nil)
    assert(idata[dev] ~= nil)
    local armed = getVarNumeric("Armed", 0, dev, SSSID)
    return armed ~= 0
end

local function isTripped(dev)
    assert(dev ~= nil)
    assert(idata[dev] ~= nil)
    local tripped = getVarNumeric("Tripped", 0, dev, SSSID)
    return tripped ~= 0
end

local function trip(tripped, dev)
    assert(dev ~= nil)
    assert(idata[dev] ~= nil)
    assert(type(tripped) == "boolean")
    D("trip(%1,%2)", tripped, dev)
    local newVal
    if tripped ~= isTripped(dev) then
        if tripped then
            D("trip() marking tripped")
            newVal = "1"
            luup.variable_set(SSSID, "LastTrip", os.time(), dev)
        else
            D("trip() marking not tripped")
            newVal = "0"
        end
        luup.variable_set(SSSID, "Tripped", newVal, dev)
        -- LastTrip and ArmedTripped are set as needed by Luup
    end
end

function scheduleNext(dev, delay, stamp)
    D("scheduleNext(%1,%2,%3)", dev, delay, stamp)
    assert(dev ~= nil)
    assert(idata[dev] ~= nil)

    -- Schedule next run. First, get and sanitize our interval if we weren't passed one.
    if delay == nil then
        delay = getVarNumeric("Interval", 1800, dev)
        if isArmed(dev) then
            delay = getVarNumeric("ArmedInterval", delay, dev)
        end
        D("scheduleNext() interval is %1", delay)
        
        -- Now, see if we've missed an interval
        local nextQuery = getVarNumeric("LastQuery", 0, dev) + delay
        local now = os.time()
        local nextDelay = nextQuery - now
        if nextDelay <= 0 then
            -- We missed an interval completely. ??? Maybe we should schedule forward?
            D("scheduleNext() next should have been %1, now %2, we missed it!", nextQuery, now)
            delay = 1
        elseif nextDelay < delay then
            -- Interval coming up sooner than full delay time.
            D("scheduleNext() next coming a little sooner, reducing delay from %1 to %2", delay, nextDelay)
            delay = nextDelay
        end
    end
    
    -- See if we're doing eval ticks (rerunning evals between requests)
    local qtype = luup.variable_get(MYSID, "ResponseType", dev) or "text"
    if qtype == "json" then
        local evalTick = getVarNumeric("EvalInterval", 0, dev)
        if evalTick > 0 and evalTick < delay then
            D("scheduleNext() reducing delay from %1 to %2 for EvalInterval", delay, evalTick)
            delay = evalTick
        end
    end
    
    -- Book it.
    if delay < 1 then delay = 1 end
    L("Next activity in %1 seconds", delay)
    luup.call_delay("siteSensorRunQuery", delay, string.format("%d:%d", stamp, dev))
end

local function b64encode( d )
    local mime = require("mime")
    return mime.b64(d)
end

local function b64decode( d )
    local mime = require("mime")
    return mime.unb64(d)
end

local function urlencode( str )
    if str == nil then return "" end
    str = tostring(str)
    return str:gsub("([^%w._-])", function( c ) if c==" " then return "+" else return string.format("%%%02x", string.byte(c)) end end )
end

local function urldecode( str )
    if str == nil then return "" end
    str = tostring(str)
    str = str:gsub("%+", " ")
    return str:gsub("%%(..)", function( c ) return string.char(tonumber(c,16)) end)
end   

-- Return the current timezone offset adjusted for DST
local function tzoffs()
    local localtime = os.date("*t")
    local epoch = { year=1970, month=1, day=1, hour=0 }
    if localtime.isdst then epoch.isdst = true end
    return os.time( epoch )
end

local function substitution( str, enc, dev )
    local subMap = {
          isodatetime = function( e ) return os.date("%Y-%m-%dT%H:%M:%S") end
        , isodate = function( e ) return os.date("%Y-%m-%d") end
        , isotime = function( e ) return os.date("%H:%M:%S") end
          -- tzoffset returns timezone offset in ISO 8601-like format, -0500
        , tzoffset = function( e, d ) local offs = tzoffs() / 60 local mag = math.abs(offs) local sg = offs < 0 local c = '+' if sg then c = '-' end return string.format("%s%02d%02d", c, mag / 60, mag % 60) end 
          -- tzdelta returns timezone offset formatted like -5hours (PHP-compatible date offset)
        , tzrel = function( e, d ) local offs = tzoffs / 60 return string.format("%+dhours", offs / 60) end
        , device = function( e, d ) return d end
        , latitude = function( e ) return luup.latitude end
        , longitude = function( e ) return luup.longitude end
        , city = function( e ) return luup.city end
        , basicauth = function( e, d ) return b64encode( (luup.variable_get( MYSID, "AuthUsername", d) or "") .. ":" .. (luup.variable_get( MYSID, "AuthPassword", d) or "") ) end
        , ['random'] = function( e ) return math.random() end
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
                s = subMap[e]( e, dev )
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
    assert(idata[dev] ~= nil)
    local logRequest = (getVarNumeric("LogRequests", 0, dev) ~= 0) or debugMode
    if method == nil then method = "GET" end

    -- A few other knobs we can turn
    local timeout = getVarNumeric("Timeout", 30, dev) -- ???
    -- local maxlength = getVarNumeric("MaxLength", 262144, dev) -- ???

    local src
    local tHeaders = {}

    -- Perform on-the-fly substitution of request values
    url = substitution( url, urlencode, dev )

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

    -- HTTP or HTTPS?
    local requestor
    if url:lower():find("https:") then
        requestor = https
    else
        requestor = http
    end

    -- Make the request.
    local respBody, httpStatus
    local r = {}
    http.TIMEOUT = timeout -- N.B. http not https, regardless
    if logRequest then
        L("%2 %1, headers=%3", url, method, tHeaders)
    end
    respBody, httpStatus = requestor.request{
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

    if logRequest then
        L("Response HTTP status %1, body=" .. respBody, httpStatus) -- use concat to avoid quoting
    end
    
    -- Handle special errors from socket library
    if tonumber(httpStatus) == nil then
        respBody = httpStatus
        httpStatus = 500
    end

    -- See what happened. Anything 2xx we reduce to 200 (OK).
    if httpStatus >= 200 and httpStatus <= 299 then
        -- Success response with no data, take shortcut.
        return false, respBody, 200
    end
    return true, respBody, httpStatus
end

local function doMatchQuery( dev )
    assert(dev ~= nil)
    assert(idata[dev] ~= nil)
    local method = "GET"
    local logRequest = (getVarNumeric("LogRequests", 0, dev) ~= 0) or debugMode
    local url = luup.variable_get(MYSID, "RequestURL", dev) or ""
    local pattern = luup.variable_get(MYSID, "Pattern", dev) or "^HTTP/1.. 200"
    local timeout = getVarNumeric("Timeout", 30, dev)
    local trigger = luup.variable_get(MYSID, "Trigger", dev) or nil

    local buf = ""
    local cond, httpStatus, httpHeaders
    local matched = false
    local err = false
    local matchValue
    
    -- Clear log capture for new request
    logCapture = {}
    setMessage("Performing query...", dev)

    -- Perform on-the-fly substitution of request values
    url = substitution( url, urlencode, dev )

    -- HTTP or HTTPS?
    local requestor
    if url:lower():find("https:") then
        requestor = https
    else
        requestor = http
    end

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

    D("doMatchQuery() seeking %1 in %2", pattern, url)

    -- We don't use doRequest here because we can stop and close the
    -- connection as soon as we find our pattern string.
    http.TIMEOUT = timeout
    if logRequest then
        L("HTTP %2 %1, headers=%3", url, method, tHeaders)
    end
    cond, httpStatus, httpHeaders = requestor.request {
        method = method,
        url = url,
        headers = tHeaders,
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
    D("doMatchQuery() returned from request(), cond=%1, httpStatus=%2, httpHeaders=%3", cond or "nil", httpStatus, httpHeaders)
    if logRequest then
        L("Response status %1 with matched %2", httpStatus, matched)
    end

    -- Handle special errors from socket library
    if tonumber(httpStatus) == nil then
        respBody = httpStatus
        httpStatus = 500
    end

    if cond == nil or (cond == 1 and httpStatus == 200) then
        if matched then
            setMessage("Valid response; matched!", dev)
        else
            setMessage("Valid response; no match.", dev)
        end
        local lastVal = luup.variable_get(MYSID, "LastMatchValue", dev)
        if (lastVal == nil or lastVal ~= matchValue) then
            luup.variable_set(MYSID, "LastMatchValue", matchValue, dev)
        end
        fail(false, dev)
    else
        setMessage("Invalid response (" .. tostring(httpStatus) .. ")", dev)
        luup.variable_set(MYSID, "LastMatchValue", "", dev)
        fail(true, dev)
        err = true
    end

    -- Set trip state based on result.
    D("doMatchQuery() matched is %1", matched)
    local newTrip
    if trigger == "neg" then
        newTrip = not matched
    elseif trigger == "err" then
        newTrip = err
    else
        newTrip = matched
    end
    trip(newTrip, dev)
    
    -- Clear LastResponse, which is only used for JSON requests
    luup.variable_set( MYSID, "LastResponse", "", dev )
end

local function doEval( dev, ctx )
    local logRequest = (getVarNumeric("LogRequests", 0, dev) ~= 0) or debugMode
    local numErrors = 0
    
    -- Since we got a valid response, indicate not tripped, unless using TripExpression, then that.
    -- Reset state var for (in)valid response?
    setMessage("Retrieving last response...", dev)
    
    if ctx == nil then 
        local lr = luup.variable_get( MYSID, "LastResponse", dev ) or ""
        if lr == "" then    
            L("No prior response to evaluate.")
            setMessage( "Empty or invalid response data.", dev )
            fail( true, dev )
            return
        end
        local pos, err
        ctx, pos, err = dkjson.decode( lr )
        if err then
            L("Unable parse stored prior result. That's... unexpected. %1 at %2", err, pos)
            setMessage( "Invalid JSON in response.", dev )
            fail( true, dev )
            return
        end
        if ctx.status.valid == 0 then
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
    end

    -- Valid response. Let's parse it and set our variables.
    ctx.expr = {}
    for i = 1,8 do
        local r = nil
        local ex = luup.variable_get(MYSID, "Expr" .. tostring(i), dev)
        if not logRequest then D("doEval() Expr%1=%2", i, ex or "nil") end
        if ex ~= nil then
            if string.len(ex) > 0 then
                r = parseRefExpr(ex, ctx)
                if logRequest then L("Eval #%1: %2=(%3)%4", i, ex, type(r), r) end
                D("doEval() parsed value of %1 is %2", ex, tostring(r))
                if r == nil then    
                    numErrors = numErrors + 1
                end
            end
        else
            luup.variable_set(MYSID, "Expr" .. tostring(i), "", dev)
        end

        -- Canonify the result value
        local rv
        if r == nil then
            rv = ""
        elseif type(r) == "boolean" then
            if r then rv = "true" else rv = "false" end
        elseif type(r) == "table" then
            rv = table.concat( r, "," )
        else
            rv = tostring(r)
        end

        -- Add raw result to context (available to subsequent expressions)
        ctx.expr[i] = r -- raw, not canonical
        
        -- Save to device state if changed.
        local oldVal = luup.variable_get(MYSID, "Value" .. tostring(i), dev)
        D("doEval() newval=(%1)%2 canonical %3, oldVal=%4", type(r), r, rv, oldVal)
        if rv ~= oldVal then
            -- Set new value only if changed
            D("doEval() Expr%1 value changed, was %2 now %3", i, oldVal, rv)
            luup.variable_set(MYSID, "Value" .. tostring(i), rv, dev)
        end
    end

    -- Handle the trip expression
    local texp = luup.variable_get(MYSID, "TripExpression", dev)
    local ttype = luup.variable_get(MYSID, "Trigger", dev) or "err"
    if ttype == "expr" then
        D("doEval() parsing TripExpression %1", texp)
        local r = nil
        if texp ~= nil then r = parseRefExpr(texp, ctx) end
        if r == nil then numErrors = numErrors + 1 end
        D("doEval() TripExpression result is %1", r)
        if logRequest then L("Eval trip expression: %1=(%2)%3", texp, type(r), r) end
        if r == nil
            or ( type(r) == "boolean" and r == false )
            or ( type(r) == "number" and r == 0 )
            or ( type(r) == "string" and ( string.len(r) == 0 or r == "0" or r == "false" ) ) -- some magic strings
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
            msg = "Last query succeeded!"
        else
            msg = parseRefExpr(msgExpr, ctx)
            if msg == nil then msg = "?" end
        end
        fail( false, dev )
    end
    setMessage( msg, dev )
end

local function doJSONQuery(dev)
    assert(dev ~= nil)
    assert(idata[dev] ~= nil)
    local logRequest = (getVarNumeric("LogRequests", 0, dev) ~= 0) or debugMode
    local url = luup.variable_get(MYSID, "RequestURL", dev) or ""
    local ttype = luup.variable_get(MYSID, "Trigger", dev) or "err"
    
    -- Clear log capture for new request
    logCapture = {}

    setMessage("Requesting JSON...", dev)
    if logRequest then L("Requesting JSON data") end
    local err,body,httpStatus = doRequest(url, "GET", nil, dev)
    local ctx = { response={}, status={ timestamp=os.time(), valid=0, httpStatus=httpStatus } }
    if body == nil or err then
        -- Error; trip sensor
        D("doJSONQuery() setting tripped and bugging out...")
        fail(true, dev)
        if ttype == "err" then trip(true, dev) end
    else
        D("doJSONQuery() fixing up JSON response for parsing")
        setMessage("Parsing response...", dev)
        -- Fix booleans, which dkjson doesn't seem to understand (gives nil)
        body = string.gsub( body, ": *true *,", ": 1," )
        body = string.gsub( body, ": *false *,", ": 0," )

        -- Process JSON response. First parse response.
        local t, pos, e = dkjson.decode(body)
        if e then
            L("Unable to decode JSON response, %2 (dev %1)", dev, e)
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
            
            -- Save the response
            luup.variable_set( MYSID, "LastResponse", dkjson.encode( ctx ), dev )
        end
    end

    doEval( dev, ctx )
end

local function checkVersion(dev)
    assert(dev ~= nil)
    assert(idata[dev] ~= nil)
    D("checkVersion() branch %1 major %2 minor %3, string %4, openLuup %5", luup.version_branch, luup.version_major, luup.version_minor, luup.version, isOpenLuup)
    if isOpenLuup or ( luup.version_branch == 1 and luup.version_major >= 7 ) then
        return true
    end
    return false
end

local function runOnce(dev)
    assert(dev ~= nil)
    assert(idata[dev] ~= nil)
    local rev = getVarNumeric("Version", 0, dev)
    if (rev == 0) then
        -- Initialize for new installation
        D("runOnce() Performing first-time initialization!")
        luup.variable_set(MYSID, "Message", "", dev)
        luup.variable_set(MYSID, "RequestURL", "", dev)
        luup.variable_set(MYSID, "Interval", "1800", dev)
        luup.variable_set(MYSID, "Timeout", "30", dev)
        luup.variable_set(MYSID, "QueryArmed", "1", dev)
        luup.variable_set(MYSID, "ResponseType", "text", dev)
        luup.variable_set(MYSID, "Trigger", "err", dev)
        luup.variable_set(MYSID, "Failed", "1", dev)
        luup.variable_set(MYSID, "LastQuery", "0", dev)
        luup.variable_set(MYSID, "LastRun", "0", dev)
        luup.variable_set(MYSID, "LogRequests", "0", dev)
        luup.variable_set(MYSID, "EvalInterval", "", dev)

        luup.variable_set(SSSID, "LastTrip", "0", dev)
        luup.variable_set(SSSID, "Armed", "0", dev)
        luup.variable_set(SSSID, "Tripped", "0", dev)
        luup.variable_set(SSSID, "ArmedTripped", "0", dev)
        luup.variable_set(SSSID, "AutoUntrip", "0", dev)
        
        luup.variable_set(HASID, "ModeSetting", "1:;2:;3:;4:", dev )
        
        luup.attr_set( "category_num", 4, dev )
        luup.attr_set( "subcategory_num", "", dev )
        
        luup.variable_set(MYSID, "Version", _CONFIGVERSION, dev)
        return
    end

    if rev < 10400 then
        D("runOnce() Upgrading config to 10400")
        luup.variable_set(MYSID, "EvalInterval", "", dev)
        luup.variable_set(HASID, "ModeSetting", "1:;2:;3:;4:", dev )
    end
    
    if rev < 10700 then
        D("runOnce() Upgrading config to 10700")
        luup.variable_set(SSSID, "AutoUntrip", "0", dev)
    end
    
    if rev < 10701 then
        D("runOnce() Upgrading config to 10701")
        luup.variable_set(MYSID, "MessageExpr", "", dev)
    end
    
    if rev < 10900 then
        D("runOnce() Upgrading config to 10900")
        luup.attr_set( "category_num", 4, dev )
        luup.attr_set( "subcategory_num", "", dev )
    end
    
    -- No matter what happens above, if our versions don't match, force that here/now.
    if (rev ~= _CONFIGVERSION) then
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
    dev = tonumber(dev,10)
    assert(dev ~= nil)
    assert(idata[dev] ~= nil)
    
    stepStamp = tonumber(stepStamp, 10)
    if stepStamp ~= idata[dev].runStamp then
        D("runQuery() stamp mismatch (got %1, expected %2). Newer thread running! I'm out...", stepStamp, idata[dev].runStamp)
        return
    end
    
    -- Are we doing an eval tick, or running a request?
    local qtype = luup.variable_get(MYSID, "ResponseType", dev) or "text"
    local timeNow = os.time()
    luup.variable_set(MYSID, "LastRun", timeNow, dev)
    local last = getVarNumeric( "LastQuery", 0, dev )
    local interval = getVarNumeric( "Interval", 0, dev )
    if isArmed then
        interval = getVarNumeric( "ArmedInterval", interval, dev )
    end
    if timeNow >= ( last + interval ) then

        -- We may only query when armed, so check that.
        local queryArmed = getVarNumeric("QueryArmed", 1, dev)
        if queryArmed == 0 or isArmed(dev) then

            -- Timestamp -- should we not do this if the query fails?
            luup.variable_set(MYSID, "LastQuery", timeNow, dev)

            -- What type of query?
            if qtype == "json" then
                doJSONQuery(dev)
            else
                doMatchQuery(dev)
            end
        else
            -- Disarmed and querying only when armed. No reschedule.
            D("runQuery() disarmed, query disabled; not rescheduling.")
            setMessage("Disarmed; query skipped.", dev)
            idata[dev].runStamp = 0
            return
        end
    elseif qtype == "json" then
        -- Not time, but for JSON we may do an eval if re-eval ticks are enabled.
        local evalTick = getVarNumeric( "EvalInterval", 0, dev )
        if evalTick > 0 then
            L("Performing re-evaluation of prior response")
            doEval( dev ) -- pass no context, doEval will reproduce it
        end
    end

    -- Schedule next run for interval delay.
    scheduleNext(dev, nil, stepStamp)
end

local function forceUpdate(dev)
    D("forceUpdate(%1)", dev)
    assert(dev ~= nil)
    assert(idata[dev] ~= nil)
    luup.variable_set( MYSID, "LastQuery", 0, dev )
    idata[dev].runStamp = os.time()
    scheduleNext(dev, 1, idata[dev].runStamp)
end

function arm(dev)
    D("arm(%1) arming!", dev)
    D("arm() luup.device is %1", luup.device)
    assert(dev ~= nil)
    assert(idata[dev] ~= nil)
    if not isArmed(dev) then
        luup.variable_set(SSSID, "Armed", "1", dev)
        -- Do not set ArmedTripped; Luup semantics
        forceUpdate(dev)
    end
end

function disarm(dev)
    D("disarm(%1) disarming!", dev)
    assert(dev ~= nil)
    assert(idata[dev] ~= nil)
    if isArmed(dev) then
        luup.variable_set(SSSID, "Armed", "0", dev)
    end
    -- Do not set ArmedTripped; Luup semantics
end

function requestLogging( dev, enabled )
    D("requestLogging(%1,%2)", dev, enabled )
    if enabled then
        luup.variable_set( MYSID, "LogRequests", "1", dev )
        L("Request logging enabled. Detailed logging will begin at next request/eval.")
    else
        luup.variable_set( MYSID, "LogRequests", "0", dev )
    end
end

function actionSetDebug( dev, state )
    D("actionSetDebug(%1,%2)", dev, state)
    if state == 1 or state == "1" or state == true or state == "true" then 
        debugMode = true 
        D("actionSetDebug() debug logging enabled")
    end
end

local function getDevice( dev, pdev, v )
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
    local rc,t,httpStatus
    rc,t,httpStatus = luup.inet.wget("http://localhost/port_3480/data_request?id=status&DeviceNum=" .. dev .. "&output_format=json", 15)
    if httpStatus ~= 200 or rc ~= 0 then 
        devinfo['_comment'] = string.format( 'State info could not be retrieved, rc=%d, http=%d', rc, httpStatus )
        return devinfo
    end
    local d = dkjson.decode(t)
    local key = "Device_Num_" .. dev
    if d ~= nil and d[key] ~= nil and d[key].states ~= nil then d = d[key].states else d = nil end
    devinfo.states = d or {}
    return devinfo
end

function requestHandler(lul_request, lul_parameters, lul_outputformat)
    D("requestHandler(%1,%2,%3) luup.device=%4", lul_request, lul_parameters, lul_outputformat, luup.device)
    local action = lul_parameters['action'] or lul_parameters["command"] or ""
    local deviceNum = tonumber( lul_parameters['device'], 10 ) or luup.device
    if action == "debug" then
        local err,msg,job,args = luup.call_action( MYSID, "SetDebug", { debug=1 }, deviceNum )
        return string.format("Device #%s result: %s, %s, %s, %s", tostring(deviceNum), tostring(err), tostring(msg), tostring(job), dump(args))
    end

    if action:sub( 1, 3 ) == "ISS" then
        -- ImperiHome ISS Standard System API, see http://dev.evertygo.com/api/iss#types
        local path = lul_parameters['path'] or action:sub( 4 ) -- Work even if I'home user forgets &path=
        if path == "/system" then
            return dkjson.encode( { id="SiteSensor-" .. luup.pk_accesspoint, apiversion=1 } ), "application/json"
        elseif path == "/rooms" then
            local roomlist = { { id=0, name="No Room" } }
            for rn,rr in pairs( luup.rooms ) do 
                table.insert( roomlist, { id=rn, name=rr } )
            end
            return dkjson.encode( { rooms=roomlist } ), "application/json"
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
            return dkjson.encode( { devices=devices } ), "application/json"
        else
            D("requestHandler: command %1 not implemented, ignored", action)
            return "{}", "application.json"
        end
    end
    
    if action == "status" then
        if dkjson == nil then return "Missing dkjson library", "text/plain" end
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
        return dkjson.encode( st ), "application/json"
    end
    
    return "<html><head><title>" .. _PLUGIN_NAME .. " Request Handler"
        .. "</title></head><body bgcolor='white'>Request format: <tt>http://" .. (luup.attr_get( "ip", 0 ) or "...")
        .. "/port_3480/data_request?id=lr_" .. lul_request 
        .. "&action=</tt><p>Actions: status, debug, ISS"
        .. "<p>Imperihome ISS URL: <tt>...&action=ISS&path=</tt><p>Documentation: <a href='"
        .. _PLUGIN_URL .. "' target='_blank'>" .. _PLUGIN_URL .. "</a></body></html>"
        , "text/html"
end

function init(dev)
    D("init(%1)", dev)
    L("starting plugin version %1 device %2", _PLUGIN_VERSION, dev)
    -- Initialize instance data
    idata[dev] = {}
    
    -- Check for ALTUI and OpenLuup
    for k,v in pairs(luup.devices) do
        if v.device_type == "urn:schemas-upnp-org:device:altui:1" then
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
        elseif v.device_type == "openLuup" then
            D("init() detected openLuup")
            isOpenLuup = true
        end
    end

    -- Make sure we're in the right environment
    if not checkVersion(dev) then
        setMessage("Unsupported firmware", dev)
        L("This plugin is currently supported only in UI7; buh-bye!")
        return false
    end

    -- See if we need any one-time inits
    runOnce(dev)
    
    -- Other inits
    math.randomseed( os.time() )

    -- Schedule next query.
    idata[dev].runStamp = os.time()
    scheduleNext(dev, nil, idata[dev].runStamp)
    
    return true, "OK", _PLUGIN_NAME
end
