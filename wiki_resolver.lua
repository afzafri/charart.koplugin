--[[--
Works out which wiki covers the book being read.

Fandom's own wiki-search endpoint sits behind a bot check, so there is no
lookup service to ask. What we have instead is the book's own metadata, a list
of known books, and the fact that a wiki address is often just the title with
the spaces taken out.
--]]--

local KNOWN_WIKIS = require("data/wikis")

local WikiResolver = {}

--- Everything we know about the book, lowercased, as one searchable string.
local function metadataText(props)
    local parts = {}
    for _, key in ipairs({ "title", "series", "authors" }) do
        local value = props and props[key]
        if type(value) == "string" and value ~= "" then
            table.insert(parts, value:lower())
        end
    end
    return table.concat(parts, " ")
end

--- Looks the book up in the bundled list of known wikis.
-- @treturn string wiki base URL, or nil
function WikiResolver.fromKnownWikis(props, known)
    local haystack = metadataText(props)
    if haystack == "" then return nil end
    for _, entry in ipairs(known or KNOWN_WIKIS) do
        if haystack:find(entry.match, 1, true) then
            return entry.wiki
        end
    end
    return nil
end

--- Fandom addresses a wiki by a slug, and that slug is often the series name
-- with the punctuation removed -- "stormlightarchive", "dungeon-crawler-carl".
-- Series is a better source than title, since a title carries the volume name
-- while the wiki covers the whole series.
-- @treturn table candidate slugs, most likely first
function WikiResolver.slugCandidates(props)
    local names, seen = {}, {}
    for _, key in ipairs({ "series", "title" }) do
        local value = props and props[key]
        if type(value) == "string" and value ~= "" then
            -- Drop a subtitle or a volume number: "Cradle: Unsouled" is
            -- covered by a wiki about "Cradle".
            local name = value:lower():gsub("[:(#].*$", "")
            name = name:gsub("[^%w%s]", " "):gsub("%s+", " "):gsub("^%s*(.-)%s*$", "%1")
            if name ~= "" and not seen[name] then
                seen[name] = true
                table.insert(names, name)
            end
        end
    end

    -- Tracked separately from the names above: a one-word series like "Cradle"
    -- produces a slug identical to its own name, and sharing the table would
    -- discard it as a duplicate.
    local candidates, added = {}, {}
    local function add(slug)
        if slug ~= "" and not added[slug] then
            added[slug] = true
            table.insert(candidates, slug)
        end
    end
    for _, name in ipairs(names) do
        local trimmed = name:gsub("^the ", "")
        add((name:gsub("%s", "")))
        add((name:gsub("%s", "-")))
        add((trimmed:gsub("%s", "")))
        add((trimmed:gsub("%s", "-")))
    end
    return candidates
end

return WikiResolver
