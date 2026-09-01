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

--- Wraps a URL in a function the image viewer can call when it needs the
-- picture. Only the first image is worth downloading up front; the rest are
-- fetched if and when the reader swipes to them.
-- @treturn function returns a BlitBuffer, or nil
function ImageFetch.lazy(url)
    local image, tried
    return function()
        if not tried then
            tried = true
            image = ImageFetch.fetch(url)
        end
        return image
    end
end

return ImageFetch
