--[[--
Thin wrapper around socket.http for talking to wiki APIs.

Keeps the timeout handling and error mapping in one place so the sources don't
each grow their own copy of it.
--]]--

local JSON = require("json")
local logger = require("logger")

-- MediaWiki asks API clients to identify themselves, and Fandom is stricter
-- about it than most.
local USER_AGENT = "charart.koplugin (KOReader; +https://github.com/afzafri/charart.koplugin)"

local Http = {
    timeout = 10,   -- seconds to establish the connection
    maxtime = 30,   -- seconds for the whole transfer
}

-- Why a request failed, so callers can tell "the wiki has nothing" apart from
-- "we never reached the wiki". Without this a reader with the wifi off is told
-- their character is not on the wiki, which is a lie.
Http.OFFLINE = "offline"   -- never reached the server
Http.SERVER = "server"     -- reached it, got an error back
Http.CONTENT = "content"   -- reached it, could not make sense of the reply

--- Fetches a URL and returns its body.
-- @string url
-- @treturn string body, or nil plus an error message and one of the kinds above
function Http.get(url)
    local http = require("socket.http")
    local ltn12 = require("ltn12")
    local socket = require("socket")
    local socketutil = require("socketutil")
    local socket_url = require("socket.url")

    local parsed = socket_url.parse(url)
    if not parsed or (parsed.scheme ~= "http" and parsed.scheme ~= "https") then
        return nil, "unsupported URL", Http.CONTENT
    end

    local sink = {}
    socketutil:set_timeout(Http.timeout, Http.maxtime)
    local code, headers, status = socket.skip(1, http.request{
        url = url,
        method = "GET",
        headers = { ["User-Agent"] = USER_AGENT },
        sink = socketutil.table_sink(sink),
    })
    socketutil:reset_timeout()

    if code == socketutil.TIMEOUT_CODE
        or code == socketutil.SSL_HANDSHAKE_CODE
        or code == socketutil.SINK_TIMEOUT_CODE then
        logger.warn("charart: request timed out:", url)
        return nil, "timed out", Http.OFFLINE
    end
    if headers == nil then
        logger.warn("charart: no response:", status or code, url)
        return nil, "could not reach the server", Http.OFFLINE
    end
    if code ~= 200 then
        logger.warn("charart: HTTP", code, url)
        return nil, "HTTP " .. tostring(code), Http.SERVER
    end

    local body = table.concat(sink)
    if body == "" then
        return nil, "empty response", Http.CONTENT
    end
    return body
end

--- Fetches a URL and decodes it as JSON.
-- @string url
-- @treturn table decoded response, or nil plus an error message and its kind
function Http.getJson(url)
    local body, err, kind = Http.get(url)
    if not body then
        return nil, err, kind
    end
    local ok, decoded = pcall(JSON.decode, body)
    if not ok or type(decoded) ~= "table" then
        logger.warn("charart: could not decode JSON from", url)
        return nil, "bad response", Http.CONTENT
    end
    return decoded
end

return Http
