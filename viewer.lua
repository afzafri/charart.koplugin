--[[--
Shows the pictures we found.

KOReader's image viewer already pages through a list of images and accepts
functions in place of images, which is exactly what we want: the reader sees
the first picture immediately and the rest are only downloaded if they swipe.
What it does not do is give each image its own caption, so we teach it to.
--]]--

local ImageFetch = require("imagefetch")
local ImageViewer = require("ui/widget/imageviewer")
local UIManager = require("ui/uimanager")

--- An image viewer whose caption follows the image being shown, so each
-- picture is credited to whoever drew it.
local CreditedImageViewer = ImageViewer:extend{
    captions = nil, -- list, parallel to the image list
}

--- Reports which picture the reader left open.
-- Swiping to the second or third picture and closing there is a deliberate
-- act, so we treat it as a preference. Closing on the first picture says
-- nothing, since that is where everyone starts.
function CreditedImageViewer:onClose()
    local shown = self._images_list_cur
    if self.on_settled and shown and shown > 1 then
        self.on_settled(shown)
    end
    return ImageViewer.onClose(self)
end

function CreditedImageViewer:switchToImageNum(image_num)
    local caption = self.captions and self.captions[image_num]
    if caption then
        self.caption = caption
        if self.captioned_title_bar then
            -- update() is about to redraw everything anyway
            self.captioned_title_bar:setSubTitle(caption, true)
        end
    end
    ImageViewer.switchToImageNum(self, image_num)
end

local Viewer = {}

--- Displays a list of results.
-- @param title what the reader highlighted, resolved to the wiki's name for it
-- @param results list of { url, caption } as returned by a source
-- @param on_settled called with the index of the picture the reader chose
function Viewer.show(title, results, on_settled)
    local images, captions = {}, {}
    for index, result in ipairs(results) do
        images[index] = ImageFetch.lazy(result.url)
        captions[index] = result.caption
    end
    -- Free the decoded images when the viewer closes.
    images.image_disposable = true

    UIManager:show(CreditedImageViewer:new{
        image = images,
        captions = captions,
        caption = captions[1],
        on_settled = on_settled,
        title_text = title,
        with_title_bar = true,
        buttons_visible = true,
    })
end

return Viewer
