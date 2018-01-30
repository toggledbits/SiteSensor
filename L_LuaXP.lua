------------------------------------------------------------------------
-- LuaXP is a simple expression evaluator for Lua, based on lexp.js, a
-- lightweight (math) expression parser for JavaScript by the same
-- author.
--
-- Author: Copyright (c) 2016 Patrick Rigney <patrick@toggledbits.com>
-- License: GPL 3.0 (see https://github.com/toggledbits/luaxp/blob/master/LICENSE)
-- Github: https://github.com/toggledbits/luaxp
------------------------------------------------------------------------
module("L_LuaXP", package.seeall)

local string = require("string")
local math = require("math")
local base = _G

local VREF = 'vref'
local FREF = 'fref'
local UNOP = 'unop'
local BINOP = 'binop'

_VERSION = "0.9.3+SiteSensor"
_DEBUG = false

local binops = {
      { op='.', prec=-1 }
    , { op='*', prec=3 }
    , { op='/', prec=3 }
    , { op='%', prec=3 }
    , { op='+', prec=4 }
    , { op='-', prec=4 }
    , { op='<', prec=6 }
    , { op='<=', prec=6 }
    , { op='>', prec=6 }
    , { op='>=', prec=6 }
    , { op='==', prec=7 }
    , { op='<>', prec=7 }
    , { op='!=', prec=7 }
    , { op='~=', prec=7 }
    , { op='&', prec=8 }
    , { op='^', prec=9 }
    , { op='|', prec=10 }
    , { op='=', prec=14 }
}
local MAXPREC = 99 -- value doesn't matter as long as it's >= any used in binops

local charmap = { t = "\t", r = "\r", n = "\n" }

-- Utility functions

function debug(s)
    if (_DEBUG) then print(s) end
end

function dump(t)
    local typ = base.type(t)
    st = "(" .. typ .. ")"
    if (typ == "table") then
        st = st .. "{ "
        local n,v
        local first = true
        for n,v in pairs(t) do
            if (not first) then st = st .. ", " end
            st = st .. n .. "=" .. dump(v)
            first = false
        end
        st = st .. "}"
    else
        st = st .. tostring(t)
    end
    return st
end

local function xp_pow(b, x)
    return math.exp(x * math.log(b))
end

local function xp_select(obj, keyname, keyval)
    local i,v
    for i,v in pairs(obj) do
        if v[keyname] == keyval then
            return v
        end
    end
    return nil
end

local monthNameMap = {}
local function mapLocaleMonth( m )
    local k
    if m == nil then error("Nil month name") end
    local ml = string.lower(tostring(m))
    if ml:match("^%d+$") then
        -- All numeric. Simply return numeric form if valid range.
        k = tonumber(ml) or 0
        if k >=1 and k <= 12 then return k end
    end
    if monthNameMap[ml] ~= nil then -- cached result?
        debug("mapLocaleMonth(" .. ml .. ") cached result=" .. monthNameMap[ml])
        return monthNameMap[ml]
    end
    -- Since we can't get locale information directly in a platform-independent way,
    -- deduce it from live results...
    local d = os.date("*t") -- current time and date
    d.day = 1 -- pinned
    for k = 1,12 do
        d.month = k
        local tt = os.time(d)
        local s = os.date("#%b#%B#", tt):lower()
        if s:find("#"..ml.."#") then
            monthNameMap[ml] = k
            return k 
        end
    end
    return error("Cannot parse month name '" .. m .. "'")
end

local YMD=0
local DMY=1
local MDY=2
local function guessMDDM()
    local d = os.date( "%x", os.time( { year=2001, month=8, day=22, hour=0 } ) )
    local p = { d:match("(%d+)([/-])(%d+)[/-](%d+)") }
    if p[1] == "2001" then return YMD,p[2]
    elseif tonumber(p[1]) == 22 then return DMY,p[2]
    else return MDY,p[2] end
end
    
-- Somewhat simple time parsing. Handles the most common forms of ISO 8601, plus many less regular forms.
-- If mm/dd vs dd/mm is ambiguous, it tries to discern using current locale's rule.
local function xp_parse_time( t )
    if type(t) == "number" then return t end -- if already numeric, assume it's already timestamp
    if t == nil or tostring(t):lower() == "now" then return os.time() end
    t = tostring(t) -- force string
    local now = os.time()
    local nd = os.date("*t", now) -- consistent
    local tt = { year=nd.year, month=nd.month, day=nd.day, hour=0, ['min']=0, sec=0 }
    local offset = 0
    -- Try to match a date. Start with two components.
    local order = nil
    local p = { t:match("^%s*(%d+)([/-])(%d+)(.*)") } -- entirely numeric w/sep
    if p[3] == nil then debug("match 2") p = { t:match("^%s*(%d+)(%-)(%a+)(.*)") } order=DMY end -- number-word (4-Jul)
    if p[3] == nil then debug("match 3") p = { t:match("^%s*(%a+)(%-)(%d+)(.*)") } order=MDY end -- word-number (Jul-4) 
    if p[3] ~= nil then 
        -- Look ahead for third component behind same separator
        debug(string.format("Found p1=%s, p2=%s, sep=%s, rem=%s", p[1], p[2], p[3], p[4]))
        local sep = p[2]
        t = p[4] or ""
        debug(string.format("Scanning for 3rd part from: '%s'", t))
        p[4],p[5] = t:match("^%" .. sep .. "(%d+)(.*)")
        if p[4] == nil then 
            p[4] = tt.year
        else
            t = p[5] or "" -- advance token
        end
        -- We now have three components. Figure out their order.
        p[5]=t p[6]=p[6]or"" debug(string.format("p=%s,%s,%s,%s,%s", unpack(p)))
        local first = tonumber(p[1]) or 0
        if order == nil and first > 31 then
            -- First is year (can't be month or day), assume y/m/d
            tt.year = first
            tt.month = mapLocaleMonth(p[3])
            tt.day = p[4]
        elseif order == nil and first > 12 then
            -- First is day, assume d/m/y
            tt.day = first
            tt.month = mapLocaleMonth(p[3])
            tt.year = p[4]
        else
            -- Guess using locale formatting
            if order == nil then
                debug("Guessing MDY order")
                order = guessMDDM()
            end
            debug("MDY order is " .. order)
            if order == 0 then 
                tt.year = p[1] tt.month = mapLocaleMonth(p[3]) tt.day = p[4]
            elseif order == 1 then
                tt.day = p[1] tt.month = mapLocaleMonth(p[3]) tt.year = p[4]
            else
                tt.month = mapLocaleMonth(p[1]) tt.day = p[3] tt.year = p[4]
            end
        end
        tt.year = tonumber(tt.year)
        if tt.year < 100 then tt.year = tt.year + 2000 end
        debug(string.format("Parsed date year=%s, month=%s, day=%s", tostring(tt.year), tostring(tt.month), tostring(tt.day)))
    else
        -- YYYYMMDD?
        debug("No match to delimited")
        p = { t:match("^%s*(%d%d%d%d)(%d%d)(%d%d)(.*)") }
        if p[3] ~= nil then
            tt.year = p[1]
            tt.month = p[2]
            tt.day = p[3]
            t = p[4] or ""
        else
            debug("check %%c format")
            -- Fri Aug  4 16:18:22 2017
            p = { t:match("^%s*%a+%s+(%a+)%s+(%d+)(.*)") } -- with dow
            if p[2] == nil then p = { t:match("^%s*(%a+)%s+(%d+)(.*)") } end -- without dow
            if p[2] ~= nil then
                debug(string.format("Matches %%c format, 1=%s,2=%s,3=%s", p[1], p[2], p[3]))
                tt.day = p[2]
                tt.month = mapLocaleMonth(p[1])
                t = p[3] or ""
                -- Following time and year?
                p = { t:match("^%s*([%d:]+)%s+(%d%d%d%d)(.*)") }
                if p[1] ~= nil then
                    tt.year = p[2]
                    t = (p[1] or "") .. " " .. (p[3] or "")
                else
                    -- Maybe just year?
                    p = { t:match("^%s*(%d%d%d%d)(.*)") }
                    if p[1] ~= nil then
                        tt.year = p[1]
                        t = p[2] or ""
                    end
                end
            else 
                debug("No luck with any known date format.")
            end
        end
        debug(string.format("Parsed date year=%s, month=%s, day=%s", tostring(tt.year), tostring(tt.month), tostring(tt.day)))
    end
    -- Time? Note: does not support decimal fractions except on seconds component, which is ignored (ISO 8601 allows on any, but must be last component)
    debug(string.format("Scanning for time from: '%s'", t))
    local hasTZ = false
    local sep = nil
    p = { t:match("^%s*T?(%d%d)(%d%d)(.*)") } -- ISO 8601 (Thhmm) without delimiters
    if p[1] == nil then p = { t:match("^%s*T?(%d+):(%d+)(.*)") } end -- with delimiters
    if p[1] ~= nil then
        -- Hour and minute
        tt.hour = p[1]
        tt['min'] = p[2]
        t = p[3] or ""
        -- Seconds?
        p = { t:match("^:?(%d+)(.*)") }
        if p[1] ~= nil then
            tt.sec = p[1]
            t = p[2] or ""
        end
        -- Swallow decimal on last component?
        p = { t:match("^(%.%d+)(.*)") }
        if p[1] ~= nil then
            t = p[2] or ""
        end
        -- AM or PM?
        p = { t:match("^%s*([AaPp])[Mm]?(.*)") }
        if p[1] ~= nil then
            debug("AM/PM is " .. p[1])
            if p[1]:lower() == "p" then tt.hour = tt.hour + 12 end
            t = p[2] or ""
        end
        debug(string.format("Parsed time is %s:%s:%s", tt.hour, tt['min'], tt.sec))
        
        -- Timezone Zulu?
        p = { t:match("^([zZ])(.*)") } -- no whitespace, see comment below.
        if p[1] ~= nil then
            -- Zulu
            offset = 0
            hasTZ = true
            t = p[2] or ""
        end
        -- Handling for zones? UTC, GMT, minimally... what about others... EDT, JST, ...?
        -- Offset +/-HH[mm] (e.g. +02, -0500). Not that the pattern requires the TZ spec 
        -- to follow the time without spaces between, to distinguish TZ from offsets (below).
        p = { t:match("^([+-]%d%d)(.*)") }
        if p[1] ~= nil then
            hasTZ = true
            offset = 60 * tonumber(p[1])
            t = p[2];
            p = { t:match("^:?(%d%d)(.*)") }
            if p[1] ~= nil then
                if offset < 0 then offset = offset - tonumber(p[1])
                else offset = offset + tonumber(p[1]) 
                end
                t = p[2] or ""
            end
        end
    end
    -- Is there an offset? Form is (+/-)DDD:HH:MM:SS. If parts are omitted, the offset
    -- is parsed from smallest to largest, so +05:00 is +5 minutes, -35 is minus 35 seconds.
    local delta = 0
    debug("Checking for offset from '" .. t .. "'")
    p = { t:match("%s*([+-])(%d+)(.*)") }
    if p[2] ~= nil then
        debug("Parsing offset from " .. t .. ", first part is " .. p[2])
        local sign = p[1]
        delta = tonumber(p[2]) or error("Invalid delta spec: " .. t)
        t = p[3] or ""
        local k
        for k = 1,3 do
            debug("Parsing offset from " .. t)
            p = { t:match("%:(%d+)(.*)") }
            if p[1] == nil then break end
            if k == 3 then delta = delta * 24 else delta = delta * 60 end
            delta = delta + tonumber(p[1])
            t = p[2] or ""
        end
        if sign == "-" then delta = -delta end
        debug("Final delta is " .. delta)
    end
    -- There should not be anything left at this point
    if t:match("([^%s])") then
        return error("Unparseable data: " .. t)
    end
    local tm = os.time(tt)
    if hasTZ then
        -- If there's a timezone spec, apply it. Otherwise we assume time was in current (system) TZ
        -- and leave it unmodified.
        local locale_offset = os.time( { year=1970, month=1, day=1, hour=0 } )
        tm = tm - locale_offset -- back to UTC, because conversion assumes current TZ, so undo that.
        tm = tm - ( offset * 60 ) -- apply specified offset
    end
    tm = tm + delta
    return tm -- returns time in UTC
end

-- Date add. First arg is timestamp, then secs, mins, hours, days, months, years
local function xp_date_add( a ) 
    local tm = xp_parse_time( a[1] )
    if a[2] ~= nil then tm = tm + (tonumber(a[2]) or error("Invalid seconds (argument 2) to dateadd()")) end
    if a[3] ~= nil then tm = tm + 60 * (tonumber(a[3]) or error("Invalid minutes (argument 3) to dateadd()")) end
    if a[4] ~= nil then tm = tm + 3600 * (tonumber(a[4]) or error("Invalid hours (argument 4) to dateadd()")) end
    if a[5] ~= nil then tm = tm + 86400 * (tonumber(a[5]) or error("Invalid days (argument 5) to dateadd()")) end
    if a[6] ~= nil or a[7] ~= nil then
        debug("Applying delta months and years to " .. tm)
        local d = os.date("*t", tm)
        d.month = d.month + ( tonumber( a[6] ) or 0 )
        d.year = d.year + ( tonumber( a[7] ) or 0 )
        debug(string.format("Normalizing month,year=%d,%d", d.month, d.year))
        while d.month < 1 do
            d.month = d.month + 12
            d.year = d.year - 1
        end
        while d.month > 12 do
            d.month = d.month - 12
            d.year = d.year + 1
        end
        tm = os.time(d)
    end
    return tm
end

-- Delta between two times. Returns value in seconds.
local function xp_date_diff( d1, d2 )
    return xp_parse_time( d1 ) - xp_parse_time( d2 or os.time() )
end

local nativeFuncs = {
      ['abs']   = { nargs = 1, impl = function( argv ) if argv[1] < 0 then return -argv[1] else return argv[1] end end }
    , ['sgn']   = { nargs = 1, impl = function( argv ) if argv[1] < 0 then return -1 elseif (argv[1] == 0) then return 0 else return 1 end end }
    , ['floor'] = { nargs = 1, impl = function( argv ) return math.floor(argv[1]) end }
    , ['ceil']  = { nargs = 1, impl = function( argv ) return math.ceil(argv[1]) end }
    , ['round'] = { nargs = 1, impl = function( argv ) local n = argv[1] local p = argv[2] or 0 return math.floor( n * pow(10, p) + 0.5 ) / pow(10, p) end }
    , ['cos']   = { nargs = 1, impl = function( argv ) return math.cos(argv[1]) end }
    , ['sin']   = { nargs = 1, impl = function( argv ) return math.sin(argv[1]) end }
    , ['tan']   = { nargs = 1, impl = function( argv ) return math.tan(argv[1]) end }
    , ['log']   = { nargs = 1, impl = function( argv ) return math.log(argv[1]) end }
    , ['exp']   = { nargs = 1, impl = function( argv ) return math.exp(argv[1]) end }
    , ['pow']   = { nargs = 2, impl = function( argv ) return xp_pow(argv[1], argv[2]) end }
    , ['sqrt']  = { nargs = 1, impl = function( argv ) return math.sqrt( argv[1] ) end }
    , ['min']   = { nargs = 2, impl = function( argv ) if argv[1] <= argv[2] then return argv[1] else return argv[2] end end }
    , ['max']   = { nargs = 2, impl = function( argv ) if argv[1] >= argv[2] then return argv[1] else return argv[2] end end }
    , ['len']   = { nargs = 1, impl = function( argv ) return string.len(tostring(argv[1])) end }
    , ['sub']   = { nargs = 2, impl = function( argv ) local st = tostring(argv[1]) local p = argv[2] local l = argv[3] or -1 return string.sub(st, p, l) end }
    , ['find']  = { nargs = 2, impl = function( argv ) local st = tostring(argv[1]) local p = tostring(argv[2]) local i = argv[3] or 1 return string.find(st, p, i) end }
    , ['upper'] = { nargs = 1, impl = function( argv ) return string.upper(tostring(argv[1])) end }
    , ['lower'] =  { nargs = 1, impl = function( argv ) return string.lower(tostring(argv[1])) end }
    , ['tostring'] = { nargs = 1, impl = function( argv ) return tostring(argv[1]) end }
    , ['tonumber'] = { nargs = 1, impl = function( argv ) return tonumber(argv[1], argv[2] or 10) end }
    , ['time']  = { nargs = 0, impl = function( argv ) return xp_parse_time( argv[1] ) end }
    , ['choose'] = { nargs = 2, impl = function( argv ) local ix = argv[1] if ix < 1 or ix > (#argv-2) then return argv[2] else return argv[ix+2] end end }
    , ['select'] = { nargs = 3, impl = function( argv ) return xp_select(argv[1],argv[2],argv[3]) end }
    , ['strftime'] = { nargs = 1, impl = function( argv ) return os.date(unpack(argv)) end }
    , ['dateadd'] = { nargs = 2, impl = function( argv ) return xp_date_add( argv ) end }
    , ['datediff'] = { nargs = 1, impl = function( argv ) return xp_date_diff( argv[1], argv[2] or os.time() ) end }
    , ['format'] = { nargs = 1, impl = function( argv ) return string.format( unpack(argv) ) end }
}

-- Adapted from "BitUtils", Lua-users wiki at http://lua-users.org/wiki/BitUtils; thank you kind stranger(s)...
local bit = {}
bit['nand'] = function(x,y,z)
    z=z or 2^16
    if z<2 then
        return 1-x*y
    else
        return bit.nand((x-x%z)/z,(y-y%z)/z,math.sqrt(z))*z+bit.nand(x%z,y%z,math.sqrt(z))
    end
end
bit["bnot"]=function(y,z) return bit.nand(bit.nand(0,0,z),y,z) end
bit["band"]=function(x,y,z) return bit.nand(bit["bnot"](0,z),bit.nand(x,y,z),z) end
bit["bor"]=function(x,y,z) return bit.nand(bit["bnot"](x,z),bit["bnot"](y,z),z) end
bit["bxor"]=function(x,y,z) return bit["band"](bit.nand(x,y,z),bit["bor"](x,y,z),z) end

-- Forward declarations
local _comp
local scan_token

-- Let's get to work

-- Skips white space, returns index of non-space character or nil
local function skip_white( expr, index )
    debug("skip_white from " .. index .. " in " .. expr)
    local len = string.len(expr)
    local ch
    while (index <= len) do
        ch = string.sub(expr, index, index)
        if ( not (ch == ' ' or ch == '\t') ) then return index end
        index = index + 1
    end
    return index
end

-- Scan a numeric token. Supports fractional and exponent specs in
-- decimal numbers, and binary, octal, and hexadecimal integers.
local function scan_numeric( expr, index )
    debug("scan_numeric from " .. index .. " in " .. expr)
    local len = string.len(expr)
    local start = index
    local ch, i
    local val = 0
    local base = 0
    -- Try to guess the base first
    ch = string.sub(expr, index, index)
    if (ch == '0' and index < len) then
        -- Look to next character
        index = index + 1
        ch = string.sub(expr, index, index)
        if (ch == 'b' or ch == 'B') then
            base = 2
            index = index + 1
        elseif (ch == 'x' or ch == 'X') then
            base = 16
            index = index + 1
        elseif (ch == '.') then
            base = 10 -- going to be a decimal number
        else
            base = 8
        end
    end
    if (base <= 0) then base = 10 end
    -- Now parse the whole part of the number
    while (index <= len) do
        ch = string.sub(expr, index, index)
        if (ch == '.') then break end
        i = string.find("0123456789ABCDEF", string.upper(ch), 1, true)
        if (i == nil) then break end
        if (i > base) then break end
        val = base * val + (i-1)
        index = index + 1
    end
    -- Parse fractional part, if any
    if (ch == '.' and base==10) then
        local ndec = 0
        index = index + 1 -- get past decimal point
        while (index <= len) do
            ch = string.sub(expr, index, index)
            i = string.find("0123456789", ch, 1, true)
            if (i == nil) then break end
            ndec = ndec - 1
            val = val + (i-1) * pow(10, ndec)
            index = index + 1
        end
    end
    -- Parse exponent, if any
    if ( (ch == 'e' or ch == 'E') and base == 10 ) then
        local npow = 0
        index = index + 1 -- get base exponent marker
        while (index <= len) do
            ch = string.sub(expr, index, index)
            i = string.find("0123456789", ch, 1, true)
            if (i == nil) then break end
            npow = npow * 10 + (i-1)
            index = index + 1
        end
        val = val * pow(10,npow)
    end
    -- Return result
    debug("scan_numeric returning index=" .. index .. ", val=" .. val)
    return index, val
end

-- Parse a string. Trivial at the moment and needs escaping of some kind
local function scan_string( expr, index )
    debug("scan_string from " .. index .. " in " .. expr)
    local len = string.len(expr)
    local st = ""
    local i
    local qchar = string.sub(expr, index, index)
    index = index + 1
    while (index <= len) do
        i = string.sub(expr, index, index)
        if (i == '\\' and index < len) then
            index = index + 1
            i = string.sub(expr, index, index)
            if (charmap[i] ~= nil) then i = charmap[i] end
        elseif (i == qchar) then
            -- PHR??? Should we do the double char style of quoting? don''t won''t ??
            index = index + 1
            return index, st
        end
        st = st .. i
        index = index + 1
    end
    return error("Unterminated string at " .. index, 0)
end

-- Parse a function reference. It is treated as a degenerate case of
-- variable reference, i.e. an alphanumeric string followed immediately
-- by an opening parenthesis.
local function scan_fref( expr, index, name )
    debug("scan_fref from " .. index .. " in " .. expr)
    local len = string.len(expr)
    local args = {}
    local parenLevel = 1
    local ch
    local subexp = ""
    while ( true ) do
        if ( index > len ) then return error("Unexpected end of argument list at " .. index, 0) end -- unexpected end of argument list

        ch = string.sub(expr, index, index)
        if (ch == ')') then
            debug("scan_fref: Found a closing paren while at level " .. parenLevel)
            parenLevel = parenLevel - 1
            if (parenLevel == 0) then
                debug("scan_fref: handling end of argument list with subexp=" .. subexp)
                if (string.len(subexp) > 0) then -- PHR??? Need to test out all whitespace strings from the likes of "func( )"
                    table.insert(args, _comp( subexp ) ) -- compile the subexp and put it on the list
                end
                index = index + 1
                debug("scan_fref returning, function is " .. name .. " with " .. table.getn(args) .. " arguments: " .. dump(args))
                return index, { type=FREF, args=args, name=name, pos=index }
            else
                -- It's part of our argument, so just add it to the subexpress string
                subexp = subexp .. ch
                index = index + 1
            end
        elseif ch == "'" or ch == '"' then
            -- Start of string? Swallow it whole and append it to our subexpression
            local qq = ch
            index, ch = scan_string( expr, index )
            subexp = subexp .. qq .. ch .. qq
        elseif (ch == ',' and parenLevel == 1) then -- completed subexpression
            debug("scan_fref: handling argument=" .. subexp)
            if (string.len(subexp) > 0) then
                local r = _comp(subexp)
                if (r == nil) then return error("Subexpression failed to compile at " .. index, 0) end
                table.insert(args, r)
                debug("scan_fref: inserted argument " .. subexp .. " as " .. dump(r))
            end
            index = skip_white( expr, index+1 )
            subexp = ""
            debug("scan_fref: continuing argument scan in " .. expr .. " from " .. index)
        else
            subexp = subexp .. ch
            if (ch == '(') then parenLevel = parenLevel + 1 end
            index = index + 1
        end
    end
end

-- Parse an array reference
local function scan_aref( expr, index, name )
    debug("scan_aref from " .. index .. " in " .. expr)
    local len = string.len(expr)
    local args = {}
    local parenLevel = 1
    local ch
    local subexp = ""
    while ( true ) do
        if ( index > len ) then return error("Unexpected end of array index expression at " .. index, 0) end -- unexpected end of argument list

        ch = string.sub(expr, index, index)
        if (ch == ']') then
            debug("scan_aref: Found a closing bracket, subexp=" .. subexp)
            args = _comp(subexp)
            debug("scan_aref returning, array is " .. name)
            return index+1, { type=VREF, name=name, index=args, pos=index }
        else
            subexp = subexp .. ch
            index = index + 1
        end
    end
end

-- Scan a variable reference; could turn into a function reference
local function scan_vref( expr, index )
    debug("scan_vref from " .. index .. " in " .. expr)
    local len = string.len(expr);
    local ch, k
    local name = ""
    while (index <= len) do
        ch = string.sub(expr, index, index)
        if (ch == '(') then
            return scan_fref(expr, index+1, name)
        elseif (ch == "[") then
            return scan_aref(expr, index+1, name)
        end
        k = string.find("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ_", string.upper(ch), 1, true)
        if (k == nil) then
            break
        elseif (name == "" and k <= 10) then
            return error("Invalid identifier at " .. index, 0) -- Invalid identifier (can't start with digit)
        end

        name = name .. ch
        index = index + 1
    end

    return index, { type=VREF, name=name, pos=index }
end

-- Scan nested expression (called when ( seen while scanning for token)
local function scan_expr( expr, index )
    debug("scan_expr from " .. index .. " in " .. expr)
    local len = string.len(expr)
    local ch, k
    local st = ""
    local parenLevel = 0
    index = index + 1
    while (index <= len) do
        ch = string.sub(expr,index,index)
        if (ch == ')') then
            if (parenLevel == 0) then
                debug("scan_expr parsing subexpression=" .. st)
                local r = _comp( st )
                if (r == nil) then return error("Subexpression failed to parse at " .. index, 0) end
                return index+1, r -- pass as single-element sub-expression
            end
            parenLevel = parenLevel - 1
        elseif (ch == '(') then
            parenLevel = parenLevel + 1
        end
        -- Add character to subexpression string (note drop-throughs from above conditionals)
        st = st .. ch
        index = index + 1
    end
    return index, nil -- Unexpected end of expression/unmatched paren group
end

local function scan_unop( expr, index )
    debug("scan_unop from " .. index .. " in " .. expr)
    local len = string.len(expr)
    local ch, k
    ch = string.sub(expr, index, index)
    if (ch == '-' or ch == '+' or ch == '!' or ch == '#') then
        -- We have a UNOP
        index = index + 1
        local k, r = scan_token( expr, index )
        if (r == nil) then return k, r end
        return k, { r, { type=UNOP, op=ch, pos=index } }
    end
    return index, nil -- Not a UNOP
end

local function scan_binop( expr, index )
    debug("scan_binop from " .. index .. " in " .. expr)
    local len = string.len(expr)
    local matched = false
    index = skip_white(expr, index)
    if (index > len) then return index, nil end

    local op = ""
    local ch
    local k = 0
    local prec
    while (index <= len) do
        ch = string.sub(expr,index,index)
        local st = op .. ch
        local matched = false
        k = k + 1
        for n,f in ipairs(binops) do
            if (string.sub(f.op,1,k) == st) then
                -- matches something
                matched = true
                prec = f.prec
                break;
            end
        end
        if (not matched) then
            -- Didn't match anything. If we matched nothing on the first character, that's an error.
            -- Otherwise, op now contains the name of the longest-matching binop in the catalog.
            if (k == 1) then return error("Invalid operator at " .. st, 0) end
            break
        end

        -- Keep going to find longest matching binop
        op = st
        index = index + 1
    end

    debug("scan_binop succeeds with op="..op)
    return index, { type=BINOP, op=op, prec=prec, pos=index }
end

-- Scan our next token (forward-declared)
function scan_token( expr, index )
    debug("scan_token from " .. index .. " in " .. expr)
    local len = string.len(expr)
    local index = skip_white(expr, index)
    if (index > len) then return index, nil end

    local ch = string.sub(expr,index,index)
    debug("scan_token guessing from " .. ch .. " at " .. index)
    if (ch == '"' or ch=="'") then
        -- String literal
        return scan_string( expr, index )
    elseif (ch == '(') then
        -- Nested expression
        return scan_expr( expr, index )
    elseif (string.find("0123456789", ch, 1, true) ~= nil) then
        -- Numeric token
        return scan_numeric( expr, index )
    end

    -- Check for unary operator
    local k, r
    k, r = scan_unop( expr, index )
    if (r ~= nil) then return k, r end

    -- Variable or function reference?
    k, r = scan_vref( expr, index )
    if (r ~= nil) then return k, r end

    --We've got no idea what we're looking at...
    return error("Invalid token at " .. string.sub(expr,index), 0)
end

local function parse_rpn( lexpr, expr, index, lprec )
    debug("parse_rpn: parsing " .. expr .. " from " .. index .. " prec " .. lprec .. " lhs " .. dump(lexpr))
    local len = string.len(expr)
    local stack = {}
    local binop, rexpr, lop, ilast

    ilast = index
    index,lop = scan_binop( expr, index )
    debug("parse_rpn: outside lookahead is " .. dump(lop))
    while (lop ~= nil and lop.prec <= lprec) do
        -- We're keeping this one
        binop = lop
        debug("parse_rpn: mid at " .. index .. " handling " .. dump(binop))
        -- Fetch right side of expression
        index,rexpr = scan_token( expr, index )
        debug("parse_rpn: mid rexpr is " .. dump(rexpr))
        if (rexpr == nil) then return error("Expected operand at " .. string.sub(expr,ilast), 0) end
        -- Peek at next operator
        ilast = index -- remember where we were
        index,lop = scan_binop( expr, index )
        debug("parse_rpn: mid lookahead is " .. dump(lop))
        while (lop ~= nil and lop.prec < binop.prec) do
            index, rexpr = parse_rpn( rexpr, expr, ilast, lop.prec )
            debug("parse_rpn: inside rexpr is " .. dump(rexpr))
            ilast = index
            index, lop = scan_binop( expr, index )
            debug("parse_rpn: inside lookahead is " .. dump(lop))
        end
        lexpr = { lexpr, rexpr, binop }
    end
    debug("parse_rpn: returning index " .. ilast .. " lhs " .. dump(lexpr))
    return ilast, lexpr
end

-- Completion of forward declaration
function _comp( expr )
    local index = 1
    local lhs

    expr = expr or ""
    expr = tostring(expr)
    debug("_comp: parse " .. expr)

    index,lhs = scan_token( expr, index )
    index,lhs = parse_rpn( lhs, expr, index, MAXPREC )
    return { lhs }
end

local function contextOrFunc( name, ctx )
    -- Name can be a name, expected to be a key within ctx, or func reference (e.g. get(something).
    -- If func, each function argument needs to be parsed out, then the function called.
    if true then
        return ctx[name]
    end
end

local function resolve( name, context )
    if ( context == nil) then return nil end
    debug("resolve: resolved " .. tostring(name))
    local k
    local i = 1
    local m = context
    repeat
        k = string.find(name, '.' , i, true)
        if (k == nil) then
            m = contextOrFunc( string.sub(name,i) )
            break
        else
            m = contextOrFunc( string.sub(name,i,k-1) )
            i = k + 1
        end
    until m == nil
    return m
end

local function check_operand_type(v, allowed, err)
    err = err or "Incompatible operand type"
    local i, t
    local vt = base.type(v)
    if base.type(allowed) == "string" then
        if vt == allowed then return true else error(err) end
    end
    for i,t in ipairs(allowed) do
        if vt == t then return true end
    end
    return error(err)
end

local function cast(v1, v2)
    return v1, v2
end

local function coerce(val, typ)
    local vt = base.type(val)
    debug("coerce: attempt (" .. vt .. ")" .. tostring(val) .. " to (" .. typ .. ")")
    if vt == typ then return val end
    if typ == "boolean" then
        -- Coerce to boolean
        if vt == "number" then return val ~= 0
        elseif vt == "string" then
            if string.lower(val) == "true" then return true
            elseif string.lower(val) == "false" then return false
            else return #val ~= 0 -- empty string is false, all else is true
            end
        end
    elseif typ == "string" then
        if vt == "number" then return tostring(val)
        elseif vt == "boolean" and val then return "true"
        elseif vt == "boolean" and not val then return "false"
        end
    elseif typ == "number" then
        if vt == "boolean" and val then return 1
        elseif vt == "boolean" and not val then return 0
        elseif vt == "string" then
            local n = tonumber(val,10)
            if n ~= nil then return n else error("Conversion of " .. val .. "from string to number failed", 0) end
        end
    end
    error("No conversion for " .. vt .. " to " .. typ)
end

local function isNumeric(val)
    local s = tonumber(val, 10)
    if s == nil then return false
    else return true, s
    end
end

local function _run( ce, ctx, stack )
    if (ce == nil) then error("Invalid input for argument 1", 0) end
    local index = 1
    local stack = {}
    local len = table.getn(ce)
    local v, e
    while (index <= len) do
        e = ce[index]
        debug("_run: next element is " .. dump(e))
        if ( base.type(e) == "number" or base.type(e) == "string" ) then
            debug("_run: " .. base.type(e) .. " value: " .. tostring(e))
            v = e
        elseif (base.type(e) == "table" and e.type == nil) then
            debug("_run: subexpression: " .. dump(e))
            v = _run( e, ctx )
            if (v == nil) then return nil end
        elseif (e.type == BINOP) then
            debug("_run: handling BINOP " .. e.op)
            local v2 = table.remove(stack)
            local v1 = table.remove(stack)
            debug("_run: operands are (" .. base.type(v1) .. ")" .. tostring(v1) .. ", (" .. base.type(v2) .. ")" .. tostring(v2))
            if (e.op == '.') then
                debug("_run: descend to " .. tostring(v2))
                check_operand_type(v1, "table", "Cannot subreference " .. base.type(v1))
                check_operand_type(v2, "string", "Invalid subreference")
                v = v1[v2]
                if v == nil then error("Subreference not found: " .. tostring(v2)) end
            elseif (e.op == '+') then
                -- Special case for +, if either operand is a string, treat as concatenation
                if base.type(v1) == "string" or base.type(v2) == "string" then
                    v = tostring(v1) .. tostring(v2)
                else
                    check_operand_type(v1, "number")
                    check_operand_type(v2, "number")
                    v = v1 + v2
                end
            elseif (e.op == '-') then
                check_operand_type(v1, "number")
                check_operand_type(v2, "number")
                v = v1 - v2
            elseif (e.op == '*') then
                check_operand_type(v1, "number")
                check_operand_type(v2, "number")
                v = v1 * v2
            elseif (e.op == '/') then
                check_operand_type(v1, "number")
                check_operand_type(v2, "number")
                v = v1 / v2
            elseif (e.op == '%') then
                check_operand_type(v1, "number")
                check_operand_type(v2, "number")
                v = v1 % v2
            elseif (e.op == '&') then
                if base.type(v1) == "boolean" or base.type(v2) == "boolean" then
                    v = coerce(v1, "boolean") and coerce(v2, "boolean")
                else
                    check_operand_type(v1, "number")
                    check_operand_type(v2, "number")
                    v = bit.band(v1, v2)
                end
            elseif (e.op == '|') then
                if base.type(v1) == "boolean" or base.type(v2) == "boolean" then
                    v = coerce(v1, "boolean") or coerce(v2, "boolean")
                else
                    check_operand_type(v1, "number")
                    check_operand_type(v2, "number")
                    v = bit.bor(v1, v2)
                end
            elseif (e.op == '^') then
                if base.type(v1) == "boolean" or base.type(v2) == "boolean" then
                    v = coerce(v1, "boolean") or coerce(v2, "boolean")
                else
                    check_operand_type(v1, "number")
                    check_operand_type(v2, "number")
                    v = bit.bxor(v1, v2)
                end
            elseif (e.op == '<') then
                check_operand_type(v1, {"number","string"})
                check_operand_type(v2, {"number","string"})
                v = v1 < v2
            elseif (e.op == '<=') then
                check_operand_type(v1, {"number","string"})
                check_operand_type(v2, {"number","string"})
                v = v1 <= v2
            elseif (e.op == '>') then
                check_operand_type(v1, {"number","string"})
                check_operand_type(v2, {"number","string"})
                v = v1 > v2
            elseif (e.op == '>=') then
                check_operand_type(v1, {"number","string"})
                check_operand_type(v2, {"number","string"})
                v = v1 >= v2
            elseif (e.op == '=' or e.op == '==') then
                if base.type(v1) == "boolean" or base.type(v2) == "boolean" then
                    v = coerce(v1, "boolean") == coerce(v2, "boolean")
                elseif (base.type(v1) == "number" or base.type(v2) == "number") and isNumeric(v1) and isNumeric(v2) then
                    return coerce(v1, "number") == coerce(v2, "number")
                else
                    check_operand_type(v1, "string")
                    check_operand_type(v2, "string")
                    v = v1 == v2
                end
            elseif (e.op == '<>' or e.op == '!=' or e.op == '~=') then
                check_operand_type(v1, {"number","string","boolean"})
                check_operand_type(v2, {"number","string","boolean"})
                if base.type(v1) == "boolean" or base.type(v2) == "boolean" then
                    v = coerce(v1, "boolean") == coerce(v2, "boolean")
                elseif (base.type(v1) == "number" or base.type(v2) == "number") and isNumeric(v1) and isNumeric(v2) then
                    return coerce(v1, "number") ~= coerce(v2, "number")
                else
                    check_operand_type(v1, "string")
                    check_operand_type(v2, "string")
                    v = v1 ~= v2
                end
            else
                error("Bug: binop parsed but not implemented by evaluator, binop=" .. e.op, 0)
            end
        elseif (e.type == UNOP) then
            -- Get the operand
            debug("_run: handling unop, stack has " .. table.getn(stack))
            v = table.remove(stack)
            if (v == nil) then error("Stack underflow in unop eval", 0) end
            if (e.op == '-') then
                v = v * -1
            elseif (e.op == '+') then
                -- noop
            elseif (e.op == '!') then
                if base.type(v) == "boolean" then
                    v = not v
                else
                    if v == 0 then v = 1 else v = 0 end
                end
            elseif e.op == '#' then
                debug("_run: # unop on " .. tostring(v))
                local vt = base.type(v)
                if vt == "string" then
                    v = #v
                elseif vt == "table" then
                    v = table.getn(v)
                elseif v == nil then
                    v = 0
                else
                    v = 1
                end
            else
                error("Bug: unop parsed but not implemented by evaluator, unop=" .. e.op, 0)
            end
        elseif (e.type == FREF) then
            -- Function reference
            debug("_run: Handling function " .. e.name .. " with " .. table.getn(e.args) .. " arguments passed");
            -- Parse our arguments and put each on the stack; push them in reverse so they pop correctly (first to pop is first passed)
            local n, v1, argv
            local argc = table.getn(e.args)
            argv = {}
            for n=1,argc do
                v = e.args[n]
                debug("_run: evaluate function argument " .. n .. ": " .. dump(v))
                v1 = _run(v, ctx)
                if (v1 == nil) then error("Evaluation of arg " .. n .. " to function " .. e.name .. " failed: " .. tostring(msg), 0) end
                debug("_run: adding argument result " .. dump(v1))
                argv[n] = v1
            end
            -- Locate the implementation
            local impl = nil
            if nativeFuncs[e.name] ~= nil then
                debug("_run: func=" .. dump(nativeFuncs[e.name]))
                impl = nativeFuncs[e.name].impl
                if (argc < nativeFuncs[e.name].nargs) then error("Insufficient arguments to " .. e.name .. ", need " .. nativeFuncs[e.name].nargs .. ", got " .. argc, 0) end
            end
            if (impl == nil and ctx['__functions'] ~= nil) then
                impl = ctx['__functions'][e.name]
                debug("_run: context __functions provides implementation")
            end
            if impl == nil then
                debug("_run: context provides deprecated-style implementation")
                impl = ctx[e.name]
            end
            if (impl == nil) then error("Unrecognized function: " .. e.name, 0) end
            if (base.type(impl) ~= "function") then error("Reference is not a function: " .. e.name) end
            -- Run the implementation
            local status
            status, v = pcall(impl, argv)
            debug("_run: finished " .. e.name .. "() call, status=" .. tostring(status) .. ", result=" .. dump(v))
            if (not status) then error("Execution of function " .. e.name .. "() returned an error: " .. tostring(v), 0) end
        elseif (e.type == VREF) then
            debug("_run: handling vref, name=" .. e.name)
            local isLook = false
            if index < len then
                local lookahead = ce[index+1]
                if base.type(lookahead) == 'table' and lookahead.type == BINOP and lookahead.op == '.' then
                    isLook = true
                    v = table.remove(stack)
                    debug("_run: Lookahead found subref through " .. dump(v))
                    if v == nil then error("Can't subreference through nil", 0) end
                    v = v[e.name]
                    if v == nil then error("Subreference doesn't exist", 0) end
                    index = index + 1 -- skip lookahead
                end
            end
            if not isLook then
                -- v = resolve(e.name, ctx)
                v = ctx[e.name]
                if (v == nil) then error("Undefined variable: " .. e.name, 0) end
            end
            -- Apply array index if present
            if (e.index ~= nil) then
                local ix = _run(e.index, ctx)
                debug("_run: vref " .. e.name .. " applying subscript " .. tostring(ix))
                if ix ~= nil then
                    v = v[ix]
                    if v == nil then error("Subscript out of range", 0) end
                else
                    error("Subscript evaluation failed", 0)
                end
            end
        else
            error("Bug: invalid object type in parse tree: " .. tostring(e.type), 0)
        end

        -- Push result to stack, move on in tree
        debug("_run: pushing result to stack: (" .. base.type(v) .. ")" .. tostring(v))
        if (v == 0) then v = 0 end -- Huh? Well... long story. Resolve the inconsistency of -0 in Lua. See issue #4.
        table.insert(stack, v)
        index = index + 1
    end
    debug("_run: finished, stack has " .. table.getn(stack) .. ": " .. dump(stack))
    if (table.getn(stack) > 0) then
        return table.remove(stack)
    end
    return nil
end

-- PUBLIC METHODS

-- Compile the expression (public method)
function compile( expressionString )
    local s,v,n
    s,v,n = pcall(_comp, expressionString)
    if (s) then
        return  { rpn = v, source = expressionString }
    else
        return nil, tostring(v)
    end
end

-- Public method to execute compiled expression. Accepts a context (ctx)
function run( compiledExpression, executionContext )
    executionContext = executionContext or {}
    if (compiledExpression == nil or compiledExpression.rpn == nil or base.type(compiledExpression.rpn) ~= "table") then return nil end
    local status, val = pcall(_run, compiledExpression.rpn, executionContext)
    if (status) then
        return val
    else
        return nil, val
    end
end

function evaluate( expressionString, executionContext )
    local r,m = compile( expressionString )
    if (r == nil) then return r,m end -- return error as we got it
    return run( r, executionContext ) -- and directly return whatever run() wants to return
end

-- Return the error message and approximate location of where a parsing error occurred (if used immediately
-- after compile(); if used after run(), returns evaluation error (location is meaningless).
function getLastError( compiledExpression )
    -- Eventually, return the error message and index within the string of where things went wrong
    return "some future error message", 0
end
