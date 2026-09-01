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

--- Recovers a picture's filename from its URL, so an image we only have a link
-- to can still be credited. Covers Wikia's /images/a/ab/Name.jpg layout and
-- plain MediaWiki's /thumb/a/ab/Name.jpg.
function MediaWiki.captionFromUrl(url)
    local name = url:match("/images/%w/%w%w/([^/?]+)")
        or url:match("/thumb/%w/%w%w/([^/?]+)")
    if not name then
        return nil
    end
    name = name:gsub("%%(%x%x)", function(hex)
        return string.char(tonumber(hex, 16))
    end)
    return MediaWiki.captionFromTitle(name)
end

--- The wiki page describing a file, where the upload and whatever the
-- uploader said about it can be seen.
function MediaWiki.filePageUrl(base, file_title)
    return base .. "/wiki/" .. socket_url.escape(file_title:gsub(" ", "_"))
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
-- @treturn string title, plus the article's lead image URL if it has one
function MediaWiki.resolveTitle(base, term, width)
    local response = Http.getJson(apiUrl(base, {
        action = "query",
        generator = "search",
        gsrnamespace = 0,
        gsrsearch = term,
        gsrlimit = 10,
        prop = "pageimages",
        piprop = "thumbnail",
        pithumbsize = width or 200,
        format = "json",
    }))
    local candidates = rankedPages(response)
    if #candidates == 0 then
        return nil
    end

    local needle = term:lower()
    local best, best_score
    for rank, page in ipairs(candidates) do
        local title = page.title:lower()

        -- How closely the title matches what was highlighted. A title that
        -- begins with the name is usually the character's own page, while one
        -- that merely mentions it is usually a group or an event: searching
        -- this wiki for "Katia" offers "Team Katia" before "Katia Grim".
        local score
        if title == needle then
            score = 500
        elseif title:sub(1, #needle) == needle then
            score = 400
        elseif needle:sub(1, #title) == title then
            score = 300
        elseif title:find(needle, 1, true) then
            score = 200
        else
            score = 100
        end

        -- A page with a picture on it is more likely to be about someone than
        -- a page without one.
        if page.thumbnail then
            score = score + 50
        end

        -- Keep the wiki's own ranking as the tie-breaker.
        score = score - rank

        if not best_score or score > best_score then
            best, best_score = page, score
        end
    end
    if not best then
        return nil
    end
    return best.title, best.thumbnail and best.thumbnail.source
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
                file_title = page.title,
                page_url = MediaWiki.filePageUrl(base, page.title),
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
                file_title = page.title,
                page_url = MediaWiki.filePageUrl(base, page.title),
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
                file_title = page.title,
                page_url = MediaWiki.filePageUrl(base, page.title),
            })
        end
    end
    return preferNamedAfter(images, title)
end

--- Reduces a file page's wikitext to a line worth showing.
-- Uploaders write the real credit here -- "Art by @hunnydohandmade, Instagram"
-- -- which beats a filename every time. What surrounds it is category links
-- and templates, so those come out.
local function cleanDescription(text)
    text = text:gsub("%[%[Category:[^%]]*%]%]", "")
    text = text:gsub("==+[^=]*==+", "")
    text = text:gsub("{|.-|}", "")
    text = text:gsub("{{[^}]*}}", "")
    text = text:gsub("%[%[[^%]|]*|([^%]]*)%]%]", "%1")
    text = text:gsub("%[%[([^%]]*)%]%]", "%1")
    text = text:gsub("%[%S+%s+([^%]]*)%]", "%1")
    text = text:gsub("<[^>]->", "")
    text = text:gsub("%'%'+", "")
    text = text:gsub("%s+", " ")
    text = text:gsub("^%s*(.-)%s*$", "%1")

    if text == "" then
        return nil
    end
    if #text > 140 then
        text = text:sub(1, 137) .. "…"
    end
    return text
end

--- Replaces captions with what the uploader wrote about each picture, where
-- they wrote anything. One request covers every picture we are about to show.
function MediaWiki.describe(base, images)
    local titles, by_title = {}, {}
    for _, image in ipairs(images) do
        if image.file_title and not by_title[image.file_title] then
            table.insert(titles, image.file_title)
            by_title[image.file_title] = image
        end
    end
    if #titles == 0 then
        return
    end

    local response = Http.getJson(apiUrl(base, {
        action = "query",
        titles = table.concat(titles, "|"),
        prop = "revisions",
        rvprop = "content",
        rvslots = "main",
        format = "json",
    }))
    local pages = response and response.query and response.query.pages
    if not pages then
        return
    end

    for _, page in pairs(pages) do
        local image = by_title[page.title]
        local revision = page.revisions and page.revisions[1]
        local main = revision and revision.slots and revision.slots.main
        local text = main and main["*"]
        if image and text then
            local description = cleanDescription(text)
            if description then
                image.caption = description
            end
        end
    end
end

--- Runs the whole lookup for one wiki.
-- @param ctx table with term, wiki (base URL), limit and width
-- @treturn table list of { url, caption }, or nil plus an error message
function MediaWiki.search(ctx)
    local title, lead_image = MediaWiki.resolveTitle(ctx.wiki, ctx.term, ctx.width)
    if not title then
        return nil, "not on this wiki"
    end

    local found, seen = {}, {}
    local function collect(images)
        for _, image in ipairs(images) do
            -- Match on the filename rather than the URL: the same picture
            -- arrives with different sizing parameters depending on which
            -- query returned it.
            local key = MediaWiki.captionFromUrl(image.url) or image.url
            if not seen[key] then
                seen[key] = true
                image.title = title
                table.insert(found, image)
                if #found >= ctx.limit then return true end
            end
        end
        return #found >= ctx.limit
    end

    -- The picture at the top of the character's own page first. Editors choose
    -- it to show who the character is, whereas a gallery page is in whatever
    -- order the filenames happen to sort, which is how a crocheted Carl ends
    -- up ahead of a portrait of him.
    if lead_image then
        local lead_name = MediaWiki.captionFromUrl(lead_image)
        collect({{
            url = lead_image,
            caption = lead_name or title,
            file_title = lead_name and ("File:" .. lead_name) or nil,
            page_url = lead_name
                and MediaWiki.filePageUrl(ctx.wiki, "File:" .. lead_name)
                or nil,
        }})
    end

    -- Every way out of the gathering below goes through here, so the
    -- descriptions are never skipped by an early return.
    local function finish()
        if #found == 0 then
            return nil, "no pictures found"
        end
        MediaWiki.describe(ctx.wiki, found)
        return found
    end

    if collect(MediaWiki.galleryImages(ctx.wiki, title, GALLERY_PATTERNS, ctx.limit, ctx.width)) then
        return finish()
    end
    if collect(MediaWiki.fileSearch(ctx.wiki, title, ctx.limit, ctx.width)) then
        return finish()
    end
    collect(MediaWiki.pageImages(ctx.wiki, title, ctx.limit, ctx.width))
    return finish()
end

return MediaWiki
