module("L_SiteSensor1", package.seeall)

local _VERSION = "0.1"
local _CONFIGVERSION = 00100

local MYSID = "urn:toggledbits-com:serviceId:SiteSensor1"
local SSSID = "urn:micasaverde-com:serviceId:SecuritySensor1"
local HASID = "urn:micasaverde-com:serviceId:HaDevice1"

local debugMode = true

local function debug(...)
    if debugMode then
        local str = "SiteSensor1:" .. arg[1]
        local ipos = 1
        while true do
            local i, j, n
            i, j, n = string.find(str, "%%(%d+)", ipos)
            if i == nil then break end
            n = tonumber(n, 10)
            if n >= 1 and n < table.getn(arg) then
                if i == 1 then
                    str = tostring(arg[n+1]) .. string.sub(str, j+1)
                else
                    str = string.sub(str, 1, i-1) .. tostring(arg[n+1]) .. string.sub(str, j+1)
                end
            end
            ipos = j + 1
        end
        luup.log(str)
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
    local i, j, r
    i, j, r = string.find(ex, "([^.]+)%.")
    if i == nil then
        -- No dot found, use entire string as next key
        debug("parseRefExpr(): no dot found in %1, using as entire key", ex)
        return ctx[ex]
    else
        -- Dot. If subcontext available, recurse using subcontext and remainder of expression
        debug("parseRefExpr(): found dot in %1, traversing to %2", ex, tostring(r))
        if ctx[r] == nil then
            return nil
        end
        return parseRefExpr(string.sub(ex, j+1), ctx[r])
    end
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

local function isArmed()
    local armed = getVarNumeric("Armed", 0, luup.device, SSSID)
    return armed ~= 0
end

local function isTripped()
    local tripped = getVarNumeric("Tripped", 0, luup.device, SSSID)
    return tripped ~= 0
end

local function trip(tripped)
    local newVal
    if tripped then 
        debug("trip(): marking tripped")
        newVal = "1" 
        luup.variable_set(SSSID, "LastTrip", os.time(), luup.device)
    else 
        debug("trip(): marking not tripped")
        newVal = "0"
    end
    luup.variable_set(SSSID, "Tripped", newVal, luup.device)
    if isArmed() then
        debug("trip(): marked armed-tripped")
        luup.variable_set(SSSID, "ArmedTripped", newVal, luup.device)
    else
        debug("trip(): not armed-tripped")
        luup.variable_set(SSSID, "ArmedTripped", "0", luup.device)
    end
end    

local function runOnce()
    local rev = getVarNumeric("Version", 0)
    if (rev == 0) then
        -- Initialize for new installation
        debug("runOnce(): Performing first-time initialization!")
        luup.variable_set(SSSID, "LastTrip", "0", luup.device)
        luup.variable_set(MYSID, "RequestURL", nil, luup.device)
        luup.variable_set(MYSID, "Interval", "1800", luup.device)
        luup.variable_set(MYSID, "LastQuery", "0", luup.device)
        luup.variable_set(MYSID, "LastRun", "0", luup.device)
        luup.variable_set(MYSID, "QueryArmed", "1", luup.device)
        luup.variable_set(MYSID, "Trigger", "match", luup.device)
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
    debug("scheduleNext(): interval is %1", delay)
    -- Now, see if we've missed an interval
    local nextQuery = getVarNumeric("LastRun", 0) + delay
    local now = os.time()
    local nextDelay = nextQuery - now
    if nextDelay < 0 then
        -- We missed an interval completely
        debug("scheduleNext(): next should have been %1, now %2, we missed it!", nextQuery, now)
        delay = 1
    elseif nextDelay < delay then
        debug("scheduleNext(): next coming a little sooner, reducing delay from %1 to %2", delay, nextDelay)
        delay = nextDelay
    end
    luup.call_delay("runQuery", delay)
    debug("scheduleNext(): scheduled next runQuery() for %1", delay)
end

local function doMatchQuery()
    local url = luup.variable_get(MYSID, "RequestURL", luup.device) or ""
    local pattern = luup.variable_get(MYSID, "Pattern", luup.device) or "^HTTP/1.. 200"
    local timeout = getVarNumeric("Timeout", 60)
    local trigger = luup.variable_get(MYSID, "Trigger", luup.device) or nil

    local http = require("socket.http")
    local buf = ""
    local cond, httpStatus, httpHeaders
    local matched = false
    local err = false
    local matchValue
    http.TIMEOUT = timeout
    setMessage("Requesting...")
    cond, httpStatus, httpHeaders = http.request {
        url = url,
        redirect = false,
        sink = function(chunk, source_err)
            if chunk == nil then
                -- no more data to process
                debug("doMatchQuery(): chunk is nil")
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
                debug("doMatchQuery(): valid chunk, buf now contains %1", l)
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
    debug("doMatchQuery(): returned from request(), cond=%1, httpStatus=%2, httpHeaders=%3", cond, httpStatus, httpHeaders)
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

    debug("doMatchQuery(): seeking %1 in %2", pattern, url)
    -- Set trip state based on result.
    debug("doMatchQuery(): matched is %1", matched)
    local tripState = isTripped()
    local newTrip
    if trigger == "neg" then
        newTrip = not matched
    elseif trigger == "err" then
        newTrip = err
    else
        newTrip = matched
    end
    if newTrip and not tripState then
        trip(true)
    elseif tripState and not newTrip then
        trip(false)
    end
end

local function doJSONQuery(url)
    local url = luup.variable_get(MYSID, "RequestURL", luup.device) or ""
    local timeout = getVarNumeric("Timeout", 60)
    local maxlength = getVarNumeric("MaxLength", 262144)

    local http = require("socket.http")
    local body, httpStatus, httpHeaders
    local err = false
    http.TIMEOUT = timeout
    setMessage("Requesting JSON...")
    body, httpStatus, httpHeaders = http.request(url)
    debug("doJSONQuery(): request returned httpStatus=%1, body=%2", httpStatus, body)
    if body == nil or httpStatus ~= 200 then
        -- Error; trip sensor
        if not isTripped() then
            trip(true)
        end
        return
    end
    
    -- Process JSON response. First parse response.
    local json = require("dkjson")
    local t, pos, err
    t, pos, err = json.decode(body)
    if err then
        luup.log("SiteSensor(" .. luup.device .. "): unable to decode JSON response, " .. err)
        if not isTripped() then
            trip(true)
        end
        setMessage("Invalid response")
        return
    end
    
    local ix,iv
    local nn = 0
    for ix,iv in pairs(t) do
        debug("doJSONQuery(): data %1=%2", ix, tostring(iv))
        nn = nn + 1
    end
    debug("doJSONQuery(): %1 root keys", nn)

--[[ PHR??? IDEA: When we get to using luaxp, have TripCondition expression that trips if true, untrips if false.
                  This allows the JSON response to control the tripped state. Can luaxp return true/false bool?
            IDEA: When luaxp, function to find an element in a hash array in the data, e.g. find(devices, 170) would
                  return the context for the device status/info. This may imply that luaxp needs to be upgraded to be
                  able to return tables as function value.
            IDEA: Have device status display show "Last Result:" label for message, and "Next Query" time/date.
]]
                  
    -- Since we got a valid response, indicate not tripped.
    if isTripped() then
        trip(false)
    end
    
    -- Valid response. Let's parse it and set our variables.
    local i
    for i =1,8,1 do
        local r = nil
        local ex = luup.variable_get(MYSID, "Expr" .. tostring(i), luup.device)
        if ex ~= nil and #ex then
            debug("doJSONQuery(): parsing %1 to value", ex)
            r = parseRefExpr(ex, t)
            debug("doJSONQuery(): parsed value of %1 is %2", ex, tostring(r))
        end
        if r == nil then r = "" end
        if r ~= luup.variable_get(MYSID, "Value" .. tostring(i), luup.device) then
            -- Set new value only if changed
            luup.variable_set(MYSID, "Value" .. tostring(i), r, luup.device)
        end
    end
    
    setMessage("Valid response")
end

function runQuery()
    -- We may only query when armed, so check that.
    local queryArmed = getVarNumeric("QueryArmed", 1)
    if queryArmed == 0 or isArmed() then
        local type = luup.variable_get(MYSID, "Type", luup.device) or "pattern"
        
        -- What type of query?
        if type == "pattern" then
            doMatchQuery()
        elseif type == "json" then
            doJSONQuery()
        end

        -- Timestamp
        luup.variable_set(MYSID, "LastQuery", os.time(), luup.device)
    end
        
    -- Run next interval
    luup.variable_set(MYSID, "LastRun", os.time(), luup.device)
    scheduleNext()
end

function arm(dev)
    debug("arm(): arming!")
    luup.variable_set(SSSID, "Armed", "1", luup.device)
    if isTripped() then
        luup.variable_set(SSSID, "ArmedTripped", "1", luup.device)
    end
end

function disarm(dev)
    debug("disarm(): disarming!")
    luup.variable_set(SSSID, "Armed", "0", luup.device)
    luup.variable_set(SSSID, "ArmedTripped", "0", luup.device)
end

function init(dev)
    -- Make sure we're in the right environment
    if not checkVersion() then
        luup.log("SiteSensor: This plugin is currently supported only in UI7; buh-bye!")
        return false
    end

    -- See if we need any one-time inits
    runOnce()

    -- Schedule next query
    setMessage("")
    scheduleNext()
end

--[[ Other stuff we don't need now...

local function parseURL(url)
    local t = {}
    local s, e
    -- http://xyzzy.example.com:8080/therestofit?abc&def
    local s, e, p, q, r = string.find(url, "^([^:]+)://([^/]+)")
    debug("parseURL(): url=%1, s=%2, e=%3, p=%4", url, s, e, p)
    if s ~=nil and s > 0 then
        t['proto'] = p
        t['host'] = q
        t['path'] = string.sub(url, e+1)
        if t['path'] == "" then t['path'] = '/' end
        s, e, p = string.find(t['host'], ":(%d+)$")
        if (s ~= nil) then
            t['host'] = string.sub(t['host'], 1, s-1)
            t['port'] = p
        else
            t['port'] = nil
        end
        debug("parseURL(): url=%1, proto=%2, host=%3, port=%4, path=%5", url, t['proto'], t['host'], t['port'], t['path'])
        return t
    else
        debug("parseURL(): failed to parse %1", url)
        return false
    end
end

function oldRunQuery()
    local url = luup.variable_get(MYSID, "RequestURL", luup.device) or ""
    local pattern = luup.variable_get(MYSID, "Pattern", luup.device) or "^HTTP/1.. 200"
    local tripState = isTripped()
    local timeout = 60
    local matched = false
    local valid = true
    
    -- Parse the URL to its components
    local parts = parseURL(url)
    if parts['proto'] == 'http' then
        if parts['port'] == nil or #parts['port'] == 0 then parts['port'] = 80 end
        if parts['path'] == nil or #parts['path'] == 0 then parts['path'] = "/" end
    elseif parts['proto'] == 'telnet' then
        if parts['port'] == nil or #parts['port'] == 0 then parts['port'] = 23 end
        parts['proto'] = 'socket'
    elseif parts['proto'] == 'socket' then
        if parts['port'] == nil or #parts['port'] == 0 then valid = false end
    else
        valid = false
    end
    
    -- If we have a valid request, make it
    if valid then
        -- Open socket
        local maxBuf = 255
        local h, buf
        local exhausted = os.time() + timeout
        buf = ""
        io.open(h, parts['host'], parts['port'])
        io.intercept(h)
        if parts['proto'] == 'http' then
            io.write("GET " .. parts['path'] .. " HTTP/1.0\r\nHost: " .. parts['host'] .. "\r\n\r\n")
        end
        -- Read and try to match reply to pattern
        while os.time() < exhausted do
            local b = io.read(1,h)
            buf = buf .. b
            debug("runQuery(): read %1, now have %2", b, buf)
            
            if string.find(buf, pattern) then
                -- Match!
                debug("runQuery(): that matches %1!", pattern)
                matched = true
                break
            end
            
            -- Don't let the buffer string get too large
            local l = string.len(buf)
            if l > maxbuf then
                buf = string.sub(buf, l-maxbuf+1)
            end

            luup.sleep(100) -- short rest
        end
    else
        debug("runQuery(): parseURL() says %1 is invalid, nothing more I can do... buh-bye!", url)
        luup.set_failure(1, luup.device)
        -- N.B. exit without scheduling next interval
        return 
    end
    
    -- Set trip state based on result.
    debug("runQuery(): matched is %1", matched)
    if matched then
        if not tripState then
            trip(true)
        end
    else
        -- No match, or no data at all
        if tripState then
            trip(false)
        end
    end
    luup.variable_set(MYSID, "LastQuery", os.time(), luup.device)
    
    -- Run next interval
    scheduleNext()
end

]]