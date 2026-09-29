--[[--
Works out which wiki covers the book being read.

Fandom's own wiki-search endpoint sits behind a bot check, so there is no
lookup service to ask. What we have instead is the book's own metadata, a list
of known books, and the fact that a wiki address is often just the title with
the spaces taken out.
--]]--

local Http = require("http")
local JSON = require("json")

local KNOWN_WIKIS = require("data/wikis")

-- Guessing is only worth a handful of requests before it stops being faster
-- than just asking the reader which wiki to use.
local MAX_PROBES = 8

-- Words that end a series name without narrowing it. Fandom often drops them:
-- "The Kingkiller Chronicle" lives at kingkiller.fandom.com.
local TRAILING_NOISE = {
    ["chronicle"] = true, ["chronicles"] = true, ["series"] = true,
    ["saga"] = true, ["trilogy"] = true, ["cycle"] = true,
    ["novels"] = true, ["books"] = true,
}

local WikiResolver = {}

--- Everything we know about the book, lowercased, as one searchable string.
-- The filename counts. Publishers fill metadata carelessly, and a file called
-- "This Inevitable Ruin Dungeon Crawler Carl Book 7" says which series it
-- belongs to when the metadata inside the book does not.
local function metadataText(props)
    local parts = {}
    for _, key in ipairs({ "title", "series", "authors", "filename" }) do
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

-- A filename is usually the series, the volume and the author run together.
-- Stripping the parts we can recognise sometimes leaves the series behind.
local function namesFromFilename(props)
    local path = props and props.filename
    if type(path) ~= "string" or path == "" then
        return {}
    end
    local base = path:match("([^/]+)$") or path
    base = base:gsub("%.%w+$", ""):gsub("[_%.]", " "):lower()

    local author = type(props.authors) == "string" and props.authors:lower() or nil
    local names = {}
    for segment in (base .. " - "):gmatch("(.-) %- ") do
        local name = segment
        if author and author ~= "" then
            name = name:gsub(author:gsub("%W", "%%%0"), " ")
        end
        name = name:gsub("%f[%a](book|vol|volume|part|no)%f[%A]%s*%d+", " ")
        name = name:gsub("%d+", " ")
        name = name:gsub("[^%w%s]", " "):gsub("%s+", " "):gsub("^%s*(.-)%s*$", "%1")

        -- Anything longer is the title and the series and half the blurb run
        -- together, and guessing at it only spends the probe budget.
        local words = select(2, name:gsub("%S+", "")) 
        if name ~= "" and words > 0 and words <= 4 then
            table.insert(names, name)
        end
    end
    return names
end

--- Fandom addresses a wiki by a slug, and that slug is often the series name
-- with the punctuation removed -- "stormlightarchive", "dungeon-crawler-carl".
-- Series is a better source than title, since a title carries the volume name
-- while the wiki covers the whole series.
--
-- Candidates come back in groups, fullest name first. Shortening a name makes
-- it likelier to collide with something else: "empyrean" is a wiki about a
-- different Empyrean altogether, with more articles than the right one. A
-- shorter guess is therefore only ever used when no fuller one answered.
-- @treturn table list of groups, each a list of slugs
function WikiResolver.slugCandidateGroups(props)
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
    for _, name in ipairs(namesFromFilename(props)) do
        if not seen[name] then
            seen[name] = true
            table.insert(names, name)
        end
    end

    --- Drops trailing words that do not narrow the name down.
    local function withoutNoise(name)
        local words = {}
        for word in name:gmatch("%S+") do
            table.insert(words, word)
        end
        while #words > 1 and TRAILING_NOISE[words[#words]] do
            table.remove(words)
        end
        return table.concat(words, " ")
    end

    local groups, added = {}, {}
    local function addGroup(form)
        if not form or form == "" then return end
        local group = {}
        for _, slug in ipairs({ (form:gsub("%s", "")), (form:gsub("%s", "-")) }) do
            if slug ~= "" and not added[slug] then
                added[slug] = true
                table.insert(group, slug)
            end
        end
        if #group > 0 then
            table.insert(groups, group)
        end
    end

    for _, name in ipairs(names) do
        local trimmed = name:gsub("^the ", "")
        addGroup(name)
        if trimmed ~= name then
            addGroup(trimmed)
        end
        addGroup(withoutNoise(trimmed))
        addGroup(withoutNoise(name))
    end
    return groups
end

--- The same candidates as a flat list, most specific first.
-- @treturn table candidate slugs
function WikiResolver.slugCandidates(props)
    local flat = {}
    for _, group in ipairs(WikiResolver.slugCandidateGroups(props)) do
        for _, slug in ipairs(group) do
            table.insert(flat, slug)
        end
    end
    return flat
end

--- Asks a wiki whether it is there, and how much is on it.
-- The size matters. Fandom is full of half-abandoned duplicates, and a name
-- can just as easily land on the wiki for a television adaptation as on the
-- one about the books: "wheeloftime" has 760 articles of screencaps, while
-- "thewheeloftime" has 6500 about the novels.
-- @treturn table {name, articles}, or nil plus the kind of failure
function WikiResolver.inspect(base)
    local body, _, kind = Http.get(
        base .. "/api.php?action=query&meta=siteinfo&siprop=statistics|general&format=json")
    if not body then
        return nil, kind
    end
    local ok, decoded = pcall(JSON.decode, body)
    if not ok or type(decoded) ~= "table" then
        return nil, "content"
    end
    local query = decoded.query or {}
    local statistics = query.statistics or {}
    local general = query.general or {}
    -- It answered, so it exists even if it will not say how big it is.
    return {
        url = base,
        name = general.sitename or base:gsub("^https?://", ""),
        articles = tonumber(statistics.articles) or 0,
    }
end

--- Whether a wiki is there at all.
-- @treturn boolean true, or false plus the kind of failure
function WikiResolver.verify(base)
    local info, kind = WikiResolver.inspect(base)
    if info then
        return true
    end
    return false, kind
end

--- Checks whether a Fandom wiki actually exists at a slug.
-- @treturn string wiki base URL, or nil plus the kind of failure
function WikiResolver.probe(slug)
    local base = "https://" .. slug .. ".fandom.com"
    local ok, kind = WikiResolver.verify(base)
    if ok then
        return base
    end
    return nil, kind
end

--- Looks for wikis that might cover this book.
-- Returns everything that answered rather than picking one, because a guessed
-- name can land somewhere plausible but wrong -- "empyrean" is a wiki about a
-- different Empyrean entirely -- and that is a judgement the reader can make
-- in a second by looking at the name.
--
-- Fuller forms of the name are searched first, and within a group the busier
-- wiki leads: "thewheeloftime" covers the novels, "wheeloftime" the television
-- series.
-- @param seeds wikis to offer ahead of any guess: the one already chosen for
--   this book, and whatever the bundled list knows. Guessing from a volume
--   title alone often finds nothing -- "This Inevitable Ruin" is a Dungeon
--   Crawler Carl book -- and dropping the reader into an empty text box while
--   we hold a perfectly good answer is no help at all.
-- @treturn table list of {url, name, articles}, best first, plus the kind of
-- failure when nothing answered
function WikiResolver.findCandidates(props, seeds)
    local found, seen, probes, last_kind = {}, {}, 0, nil

    for _, base in ipairs(seeds or {}) do
        local info, kind = WikiResolver.inspect(base)
        if info then
            local fingerprint = info.name .. "|" .. tostring(info.articles)
            if not seen[fingerprint] then
                seen[fingerprint] = true
                table.insert(found, info)
            end
        else
            last_kind = kind or last_kind
        end
    end

    for _, group in ipairs(WikiResolver.slugCandidateGroups(props)) do
        local in_group = {}
        for _, slug in ipairs(group) do
            if probes >= MAX_PROBES then break end
            probes = probes + 1
            local info, kind = WikiResolver.inspect("https://" .. slug .. ".fandom.com")
            if info then
                -- Fandom answers to several names for one wiki, and those
                -- aliases are identical down to the article count.
                local fingerprint = info.name .. "|" .. tostring(info.articles)
                if not seen[fingerprint] then
                    seen[fingerprint] = true
                    table.insert(in_group, info)
                end
            else
                last_kind = kind or last_kind
            end
        end
        table.sort(in_group, function(a, b) return a.articles > b.articles end)
        for _, info in ipairs(in_group) do
            table.insert(found, info)
        end
    end

    if #found == 0 then
        return found, last_kind
    end
    return found
end

--- The single best guess at this book's wiki: the known list, then searching.
-- @treturn string wiki base URL, or nil plus the kind of failure
function WikiResolver.resolve(props)
    local known = WikiResolver.fromKnownWikis(props)
    if known then
        return known
    end
    local found, kind = WikiResolver.findCandidates(props)
    if found[1] then
        return found[1].url
    end
    return nil, kind
end

return WikiResolver
