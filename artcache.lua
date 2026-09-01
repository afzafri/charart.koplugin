--[[--
Remembers what we found, and the pictures themselves.

Readers look the same character up more than once -- someone reappears after
two hundred pages and you have forgotten who they are. The second lookup should
be instant, and should work with the wifi off.

Named artcache rather than cache because KOReader has a module of its own by
that name, and a plugin's own directory comes first on the module path while it
is loading.
--]]--

local DataStorage = require("datastorage")
local LuaSettings = require("luasettings")
local lfs = require("libs/libkoreader-lfs")
local md5 = require("ffi/sha2").md5
local util = require("util")

-- Old results are worth keeping, but not forever: wikis gain better art, and
-- a picture that has been deleted upstream should stop being served eventually.
local MAX_AGE = 60 * 60 * 24 * 30 -- a month, in seconds
local MAX_IMAGES = 200

local ArtCache = {}

local image_dir = DataStorage:getDataDir() .. "/cache/charart"
local results = LuaSettings:open(DataStorage:getSettingsDir() .. "/charart_results.lua")

local function key(wiki, term)
    return md5(wiki .. "|" .. term:lower())
end

--- Returns the results of an earlier lookup, if we still have them.
-- @treturn table results, or nil
function ArtCache.recall(wiki, term)
    local entry = results:readSetting(key(wiki, term))
    if not entry then
        return nil
    end
    if os.time() - (entry.at or 0) > MAX_AGE then
        return nil
    end
    return entry.results
end

--- Stores the results of a lookup.
function ArtCache.remember(wiki, term, found)
    results:saveSetting(key(wiki, term), { at = os.time(), results = found })
    results:flush()
end

--- Remembers the picture a reader settled on for a character.
-- Kept against the wiki and the character rather than the book, so a choice
-- made in the first volume still holds in the sixth.
function ArtCache.pin(wiki, title, result)
    results:saveSetting("pin:" .. key(wiki, title), result)
    results:flush()
end

--- The picture a reader settled on for a character, if there is one.
-- @treturn table result, or nil
function ArtCache.pinned(wiki, title)
    return results:readSetting("pin:" .. key(wiki, title))
end

--- Where a picture is kept on disk.
function ArtCache.imagePath(url)
    return image_dir .. "/" .. md5(url)
end

--- Reads a picture we downloaded before.
-- @treturn string image data, or nil
function ArtCache.readImage(url)
    local file = io.open(ArtCache.imagePath(url), "rb")
    if not file then
        return nil
    end
    local data = file:read("*a")
    file:close()
    return data ~= "" and data or nil
end

--- Keeps a picture for next time. Failing to write is not worth reporting:
-- the reader has the image on screen either way.
function ArtCache.writeImage(url, data)
    util.makePath(image_dir)
    local file = io.open(ArtCache.imagePath(url), "wb")
    if not file then
        return
    end
    file:write(data)
    file:close()
    ArtCache.prune()
end

--- Drops the oldest pictures once there are too many of them.
function ArtCache.prune()
    local files = {}
    local ok, iterator, handle = pcall(lfs.dir, image_dir)
    if not ok then return end
    for entry in iterator, handle do
        local path = image_dir .. "/" .. entry
        if lfs.attributes(path, "mode") == "file" then
            table.insert(files, { path = path, at = lfs.attributes(path, "modification") or 0 })
        end
    end
    if #files <= MAX_IMAGES then
        return
    end
    table.sort(files, function(a, b) return a.at < b.at end)
    for index = 1, #files - MAX_IMAGES do
        os.remove(files[index].path)
    end
end

--- Forgets everything, for when a reader wants to start over.
function ArtCache.clear()
    util.removePath(image_dir)
    results.data = {}
    results:flush()
end

return ArtCache
