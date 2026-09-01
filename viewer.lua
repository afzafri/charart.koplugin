--[[--
Shows the pictures we found.

KOReader's image viewer already pages through a list of images and accepts
functions in place of images, which is exactly what we want: the reader sees
the first picture immediately and the rest are only downloaded if they swipe.

Two things it does not do, which matter here. It shows one caption for the
whole list, so every picture would be credited to whoever drew the first one.
And the only way to reach the next picture is a swipe, which is invisible --
nothing on screen says there are more. So we add a caption that follows the
image, and buttons that say so out loud.
--]]--

local ButtonTable = require("ui/widget/buttontable")
local CenterContainer = require("ui/widget/container/centercontainer")
local Geom = require("ui/geometry")
local ImageFetch = require("imagefetch")
local ImageViewer = require("ui/widget/imageviewer")
local Notification = require("ui/widget/notification")
local UIManager = require("ui/uimanager")
local _ = require("gettext")

local CreditedImageViewer = ImageViewer:extend{
    captions = nil,   -- list, parallel to the image list
    urls = nil,       -- ditto, so a picture can be identified when kept
    pinned_url = nil, -- the picture already kept for this character, if any
}

function CreditedImageViewer:init()
    ImageViewer.init(self)
    if (self._images_list_nb or 1) > 1 then
        self:_addPagingButtons()
    end
end

--- Replaces the button row with one that includes Previous and Next.
-- The viewer builds its buttons privately, so the row is rebuilt rather than
-- appended to. The scale and rotate buttons keep their ids: ImageViewer:update()
-- looks them up by id and relabels them without checking they exist.
function CreditedImageViewer:_addPagingButtons()
    local buttons = {
        {
            {
                text = "◁  " .. _("Previous"),
                callback = function() self:showRelativeImage(-1) end,
            },
            {
                id = "pin",
                text = self:pinLabel(),
                callback = function() self:togglePin() end,
            },
            {
                text = _("Next") .. "  ▷",
                callback = function() self:showRelativeImage(1) end,
            },
        },
        {
            {
                id = "scale",
                text = self._scale_to_fit and _("Original size") or _("Scale"),
                callback = function()
                    self.scale_factor = self._scale_to_fit and 1 or 0
                    self._scale_to_fit = not self._scale_to_fit
                    self._center_x_ratio = 0.5
                    self._center_y_ratio = 0.5
                    self:update()
                end,
            },
            {
                id = "rotate",
                text = self.rotated and _("No rotation") or _("Rotate"),
                callback = function()
                    self.rotated = not self.rotated and true or false
                    self:update()
                end,
            },
            {
                id = "close",
                text = _("Close"),
                callback = function() self:onClose() end,
            },
        },
    }

    self.button_table = ButtonTable:new{
        width = self.width - 2 * self.button_padding,
        buttons = buttons,
        zero_sep = true,
        show_parent = self,
    }
    self.button_container = CenterContainer:new{
        dimen = Geom:new{
            w = self.width,
            h = self.button_table:getSize().h,
        },
        self.button_table,
    }
    self:update()
end

--- Steps through the pictures, wrapping at either end so neither button is
-- ever a dead press.
function CreditedImageViewer:showRelativeImage(step)
    local count = self._images_list_nb or 1
    if count < 2 then return end
    local next_num = ((self._images_list_cur - 1 + step) % count) + 1
    self:switchToImageNum(next_num)
end

--- Whether the picture on screen is the one kept for this character.
function CreditedImageViewer:isPinned()
    return self.pinned_url ~= nil
        and self.urls ~= nil
        and self.pinned_url == self.urls[self._images_list_cur or 1]
end

function CreditedImageViewer:pinLabel()
    return self:isPinned() and _("★ Kept") or _("Keep this")
end

--- Remembers, or forgets, the picture on screen as this character's.
-- Search results shift as a wiki gains art, and the first hit is not always
-- the likeness a reader has in mind, so let them nail one down.
function CreditedImageViewer:togglePin()
    if not self.on_pin then return end

    local current = self._images_list_cur or 1
    if self:isPinned() then
        self.pinned_url = nil
        self.on_pin(nil)
        UIManager:show(Notification:new{ text = _("No longer kept.") })
    else
        self.pinned_url = self.urls and self.urls[current]
        self.on_pin(current)
        UIManager:show(Notification:new{ text = _("Kept. This picture will come up first.") })
    end
    self:refreshPinLabel()
end

function CreditedImageViewer:refreshPinLabel()
    local button = self.button_table and self.button_table:getButtonById("pin")
    if button then
        button:setText(self:pinLabel(), button.width)
    end
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
    -- After the switch, so the label describes the picture now on screen.
    self:refreshPinLabel()
end

local Viewer = {}

--- Displays a list of results.
-- @param title what the reader highlighted, resolved to the wiki's name for it
-- @param results list of { url, caption } as returned by a source
-- @param on_pin called with the index the reader kept, or nil to forget
-- @param pinned_url the picture already kept for this character, if any
function Viewer.show(title, results, on_pin, pinned_url)
    local images, captions, urls = {}, {}, {}
    for index, result in ipairs(results) do
        images[index] = ImageFetch.lazy(result.url)
        captions[index] = result.caption
        urls[index] = result.url
    end
    -- Free the decoded images when the viewer closes.
    images.image_disposable = true

    UIManager:show(CreditedImageViewer:new{
        image = images,
        captions = captions,
        urls = urls,
        pinned_url = pinned_url,
        caption = captions[1],
        on_pin = on_pin,
        title_text = title,
        with_title_bar = true,
        buttons_visible = true,
    })
end

return Viewer
