--[[--
Turns a picture's URL into something the image viewer can draw.

Wikia hands back WebP even when the URL ends in .jpg, so decoding is left to
RenderImage, which picks the right decoder by sniffing the data rather than
trusting the file extension.
--]]--

local ArtCache = require("artcache")
local Http = require("http")
local RenderImage = require("ui/renderimage")
local logger = require("logger")

-- Size of the stand-in shown when a picture will not download.
local PLACEHOLDER_SIZE = 600

local ImageFetch = {}

--- Downloads and decodes one picture, reusing the copy on disk if we have it.
-- @string url
-- @treturn BlitBuffer the decoded image, or nil plus an error message
function ImageFetch.fetch(url)
    local data = ArtCache.readImage(url)
    if not data then
        local err
        data, err = Http.get(url)
        if not data then
            return nil, err
        end
        ArtCache.writeImage(url, data)
    end

    local ok, image = pcall(RenderImage.renderImageData, RenderImage, data, #data)
    if not ok or not image then
        logger.warn("charart: could not decode image", url)
        return nil, "unreadable image"
    end
    return image
end

--- Downloads a picture into the cache without decoding it.
-- Used to pull the first picture down while the "looking" message is still on
-- screen, so the viewer opens on an image that is already to hand instead of
-- stalling on the network with nothing showing.
-- @treturn boolean whether the picture is now available locally
function ImageFetch.prefetch(url)
    if ArtCache.readImage(url) then
        return true
    end
    local data = Http.get(url)
    if not data then
        return false
    end
    ArtCache.writeImage(url, data)
    return true
end

--- Wraps a URL in a function the image viewer can call when it needs the
-- picture. Only the first image is downloaded up front; the rest are fetched
-- when the reader pages to them.
--
-- Every call decodes afresh, and deliberately so. The viewer owns what this
-- returns and frees it when the reader moves to another picture, so handing
-- back a remembered one would be handing back freed memory -- paging forward
-- and then back again used to take the whole app down. Decoding again is
-- cheap: the bytes are already on disk by then.
-- @treturn function returns a BlitBuffer
function ImageFetch.lazy(url)
    return function()
        local image = ImageFetch.fetch(url)
        if not image then
            -- The viewer raises "cannot render image" if it is handed
            -- nothing, so a picture that failed to download has to come
            -- back as something. A checkerboard reads as "missing".
            image = RenderImage:renderCheckerboard(PLACEHOLDER_SIZE, PLACEHOLDER_SIZE)
        end
        return image
    end
end

return ImageFetch
