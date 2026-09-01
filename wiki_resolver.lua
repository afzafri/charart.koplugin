--[[--
Works out which wiki covers the book being read.

Fandom's own wiki-search endpoint sits behind a bot check, so there is no
lookup service to ask. What we have instead is the book's own metadata, a list
of known books, and the fact that a wiki address is often just the title with
the spaces taken out.
--]]--

local Http = require("http")

local KNOWN_WIKIS = require("data/wikis")

-- Guessing is only worth a couple of requests before it stops being faster
-- than just asking the reader which wiki to use.
local MAX_PROBES = 4

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

--- Checks whether a Fandom wiki actually exists at a slug.
-- @treturn string wiki base URL, or nil
function WikiResolver.probe(slug)
    local base = "https://" .. slug .. ".fandom.com"
    local body = Http.get(base .. "/api.php?action=query&meta=siteinfo&format=json")
    return body and base or nil
end

--- Finds the wiki for a book: the known list first, then guessing.
-- Returns nil when neither works, which is the caller's cue to ask the reader.
-- @treturn string wiki base URL, or nil
function WikiResolver.resolve(props)
    local known = WikiResolver.fromKnownWikis(props)
    if known then
        return known
    end
    for index, slug in ipairs(WikiResolver.slugCandidates(props)) do
        if index > MAX_PROBES then break end
        local found = WikiResolver.probe(slug)
        if found then
            return found
        end
    end
    return nil
end

return WikiResolver
