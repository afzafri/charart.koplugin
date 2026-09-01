--[[--
Finds pictures by asking each source in turn until one answers.

A source is a file in sources/ that returns a table with an id, a priority and
a search function. Dropping a new file in there is enough to register it --
there is no list to add yourself to.

Sources have to be loaded here, at require time. KOReader puts the plugin's own
directory on package.path only while the plugin is being loaded and takes it
back off afterwards, so a source required later, from inside a callback, would
not be found.
--]]--

local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")

local Lookup = {}

--- The directory this file lives in, which is also the plugin's root.
local function pluginRoot()
    return debug.getinfo(1, "S").source:match("^@(.*)/[^/]+$")
end

--- Loads every source, most preferred first.
local function loadSources()
    local sources = {}
    local dir = pluginRoot() .. "/sources"

    -- lfs.dir hands back an iterator and the directory handle it walks; the
    -- loop needs both.
    local ok, iterator, dir_handle = pcall(lfs.dir, dir)
    if not ok then
        logger.warn("charart: no sources directory at", dir)
        return sources
    end

    for entry in iterator, dir_handle do
        local name = entry:match("^(.+)%.lua$")
        if name then
            local loaded, source = pcall(require, "sources/" .. name)
            if loaded and type(source) == "table" and type(source.search) == "function" then
                table.insert(sources, source)
            else
                logger.warn("charart: skipping unusable source", entry)
            end
        end
    end

    table.sort(sources, function(a, b)
        return (a.priority or 100) < (b.priority or 100)
    end)
    return sources
end

Lookup.sources = loadSources()

--- Asks each source for pictures of ctx.term, stopping at the first that has
-- any.
-- @treturn table results, or nil plus a message explaining the last failure
function Lookup.run(ctx)
    local last_error = "no sources available"
    for _, source in ipairs(Lookup.sources) do
        local results, err = source.search(ctx)
        if results and #results > 0 then
            return results
        end
        last_error = err or last_error
        logger.dbg("charart:", source.id, "found nothing:", last_error)
    end
    return nil, last_error
end

return Lookup
