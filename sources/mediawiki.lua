--[[--
Looks for character art on MediaWiki sites: Fandom wikis and independent ones
like tolkiengateway.net or awoiaf.westeros.org, which all speak the same API.

The lookup runs in two phases. Searching the file namespace for whatever the
reader highlighted works well for a bare name, but falls apart on the longer
forms people actually highlight -- "Princess Donut the Queen Anne Chonk" turns
up book covers. So we first resolve the selection to an article title, which
article search is good at even when the selection is long or misremembered,
and only then go looking for pictures of that title.
--]]--

local Http = require("http")
local socket_url = require("socket.url")

local GALLERY_PATTERNS = require("data/gallery_patterns")

local MediaWiki = {
    id = "mediawiki",
    priority = 10,
}

--- Builds an api.php URL from a table of query parameters.
local function apiUrl(base, params)
    local parts = {}
    for key, value in pairs(params) do
        table.insert(parts, key .. "=" .. socket_url.escape(tostring(value)))
    end
    return base .. "/api.php?" .. table.concat(parts, "&")
end

--- MediaWiki returns generator results in a hash keyed by page id, with the
-- search rank in each page's "index". Sort by it so rank 1 comes back first.
local function rankedPages(response)
    local pages = response and response.query and response.query.pages
    if not pages then return {} end
    local ordered = {}
    for _, page in pairs(pages) do
        table.insert(ordered, page)
    end
    table.sort(ordered, function(a, b)
        return (a.index or math.huge) < (b.index or math.huge)
    end)
    return ordered
end

--- Turns "File:Carl by Kippin21.jpg" into "Carl by Kippin21".
-- Wiki uploaders habitually name files after the subject and the artist, which
-- makes the filename the most reliable credit we have.
function MediaWiki.captionFromTitle(title)
    local caption = title:gsub("^File:", ""):gsub("%.%w+$", ""):gsub("_", " ")
    return (caption:gsub("^%s*(.-)%s*$", "%1"))
end

--- Phase one: resolve the highlighted text to an article title.
-- Search relevance alone is not enough. Asking this wiki for "Wei Shi Lindon"
-- ranks "Wei Clan" above the article actually called "Wei Shi Lindon", because
-- the clan page mentions the words more often. So we look at several results
-- and prefer one whose title matches what was highlighted, falling back to the
-- wiki's own ranking when nothing matches by name.
-- @treturn string title, or nil if the wiki has nothing matching
function MediaWiki.resolveTitle(base, term)
    local response = Http.getJson(apiUrl(base, {
        action = "query",
        generator = "search",
        gsrnamespace = 0,
        gsrsearch = term,
        gsrlimit = 5,
        format = "json",
    }))
    local candidates = rankedPages(response)
    if #candidates == 0 then
        return nil
    end

    local needle = term:lower()
    for _, page in ipairs(candidates) do
        if page.title:lower() == needle then
            return page.title
        end
    end
    for _, page in ipairs(candidates) do
        local title = page.title:lower()
        if title:find(needle, 1, true) or needle:find(title, 1, true) then
            return page.title
        end
    end
    return candidates[1].title
end

--- Puts pictures whose filename mentions the subject first.
-- A gallery page lists its images alphabetically, which for Carl's gallery
-- means "Bare Knuckles by Content Office" outranks "Carl-anime-style". The
-- uploader naming a file after a character is a decent signal that it shows
-- them, and sorting on it costs no extra requests.
local function preferNamedAfter(images, title)
    local needle = title:lower()
    local named, rest = {}, {}
    for _, image in ipairs(images) do
        if image.caption:lower():find(needle, 1, true) then
            table.insert(named, image)
        else
            table.insert(rest, image)
        end
    end
    for _, image in ipairs(rest) do
        table.insert(named, image)
    end
    return named
end

--- Phase two: search the file namespace for pictures of a resolved title.
-- @treturn table list of { url, caption }
function MediaWiki.fileSearch(base, title, limit, width)
    local response = Http.getJson(apiUrl(base, {
        action = "query",
        generator = "search",
        gsrnamespace = 6,
        gsrsearch = title,
        gsrlimit = limit,
        prop = "imageinfo",
        iiprop = "url",
        iiurlwidth = width,
        format = "json",
    }))
    local images = {}
    for _, page in ipairs(rankedPages(response)) do
        local info = page.imageinfo and page.imageinfo[1]
        local url = info and (info.thumburl or info.url)
        if url then
            table.insert(images, {
                url = url,
                caption = MediaWiki.captionFromTitle(page.title),
            })
        end
    end
    return preferNamedAfter(images, title)
end

--- Every image used on an article, as a fallback when the file namespace is
-- thin. Ordered as they appear on the page, so the lead image comes first.
-- @treturn table list of { url, caption }
function MediaWiki.pageImages(base, title, limit, width)
    local response = Http.getJson(apiUrl(base, {
        action = "query",
        titles = title,
        generator = "images",
        gimlimit = limit,
        prop = "imageinfo",
        iiprop = "url",
        iiurlwidth = width,
        format = "json",
    }))
    local images = {}
    for _, page in ipairs(rankedPages(response)) do
        local info = page.imageinfo and page.imageinfo[1]
        local url = info and (info.thumburl or info.url)
        if url then
            table.insert(images, {
                url = url,
                caption = MediaWiki.captionFromTitle(page.title),
            })
        end
    end
    return images
end

--- Images from a subject's gallery page, if the wiki keeps one.
-- All the candidate page names go into a single request; the ones that do not
-- exist come back empty rather than as an error, so trying several is cheap.
-- @treturn table list of { url, caption }
function MediaWiki.galleryImages(base, title, patterns, limit, width)
    local titles = {}
    for _, pattern in ipairs(patterns) do
        table.insert(titles, (pattern:gsub("{name}", title)))
    end

    local response = Http.getJson(apiUrl(base, {
        action = "query",
        titles = table.concat(titles, "|"),
        generator = "images",
        gimlimit = limit,
        prop = "imageinfo",
        iiprop = "url",
        iiurlwidth = width,
        format = "json",
    }))
    local images = {}
    for _, page in ipairs(rankedPages(response)) do
        local info = page.imageinfo and page.imageinfo[1]
        local url = info and (info.thumburl or info.url)
        if url then
            table.insert(images, {
                url = url,
                caption = MediaWiki.captionFromTitle(page.title),
            })
        end
    end
    return preferNamedAfter(images, title)
end

--- Runs the whole lookup for one wiki.
-- @param ctx table with term, wiki (base URL), limit and width
-- @treturn table list of { url, caption }, or nil plus an error message
function MediaWiki.search(ctx)
    local title = MediaWiki.resolveTitle(ctx.wiki, ctx.term)
    if not title then
        return nil, "not on this wiki"
    end

    local found, seen = {}, {}
    local function collect(images)
        for _, image in ipairs(images) do
            if not seen[image.url] then
                seen[image.url] = true
                image.title = title
                table.insert(found, image)
                if #found >= ctx.limit then return true end
            end
        end
        return #found >= ctx.limit
    end

    if collect(MediaWiki.galleryImages(ctx.wiki, title, GALLERY_PATTERNS, ctx.limit, ctx.width)) then
        return found
    end
    if collect(MediaWiki.fileSearch(ctx.wiki, title, ctx.limit, ctx.width)) then
        return found
    end
    collect(MediaWiki.pageImages(ctx.wiki, title, ctx.limit, ctx.width))

    if #found == 0 then
        return nil, "no pictures found"
    end
    return found
end

return MediaWiki
