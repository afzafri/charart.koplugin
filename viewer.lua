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
local Device = require("device")
local Geom = require("ui/geometry")
local ImageFetch = require("imagefetch")
local ImageViewer = require("ui/widget/imageviewer")
local TitleBar = require("ui/widget/titlebar")
local Notification = require("ui/widget/notification")
local UIManager = require("ui/uimanager")
local ffiUtil = require("ffi/util")
local _ = require("gettext")
local T = ffiUtil.template

local CreditedImageViewer = ImageViewer:extend{
    captions = nil,   -- list, parallel to the image list
    urls = nil,       -- ditto, so a picture can be identified when kept
    page_urls = nil,  -- ditto, the wiki page each picture came from
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
                id = "source",
                text = _("Source"),
                enabled_func = function()
                    return self.page_urls ~= nil
                        and self.page_urls[self._images_list_cur or 1] ~= nil
                end,
                callback = function() self:openSource() end,
            },
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
    return self:isPinned() and _("★ Default") or _("Set as default")
end

--- Makes the picture on screen this character's default, or clears it.
-- Search results shift as a wiki gains art, and the first hit is not always
-- the likeness a reader has in mind, so let them nail one down.
function CreditedImageViewer:togglePin()
    if not self.on_pin then return end

    local current = self._images_list_cur or 1
    if self:isPinned() then
        self.pinned_url = nil
        self.on_pin(nil)
        UIManager:show(Notification:new{ text = _("No longer the default picture.") })
    else
        self.pinned_url = self.urls and self.urls[current]
        self.on_pin(current)
        UIManager:show(Notification:new{
            text = T(_("Set as %1's default picture."), self.title_text or _("this character")),
        })
    end
    self:refreshPinLabel()
end

function CreditedImageViewer:refreshPinLabel()
    local button = self.button_table and self.button_table:getButtonById("pin")
    if button then
        button:setText(self:pinLabel(), button.width)
    end
end

--- Recaptions the title bar for the picture now showing.
-- The viewer builds its captioned bar with subtitle_multilines set, and
-- TitleBar:setSubTitle quietly does nothing in that case -- it opens with
-- "if self.subtitle_widget and not self.subtitle_multilines". So the bar has
-- to be built again rather than edited.
function CreditedImageViewer:setCaption(caption)
    self.caption = caption
    if not (self.with_title_bar and self.captioned_title_bar) then
        return
    end
    self.captioned_title_bar = TitleBar:new{
        width = self.width,
        align = "left",
        title = self.title_text,
        title_multilines = true,
        subtitle = caption,
        subtitle_multilines = true,
        subtitle_fullwidth = true,
        with_bottom_line = true,
        left_icon = "triangle",
        left_icon_rotation_angle = 180,
        left_icon_tap_callback = function()
            self.caption_visible = not self.caption_visible
            self:update()
        end,
        close_callback = function() self:onClose() end,
        show_parent = self,
    }
end

function CreditedImageViewer:switchToImageNum(image_num)
    local caption = self.captions and self.captions[image_num]
    if caption then
        self:setCaption(caption)
    end
    ImageViewer.switchToImageNum(self, image_num)
    -- After the switch, so both describe the picture now on screen.
    self:refreshPinLabel()
end

--- Opens the wiki page the picture came from, so the reader can see who made
-- it and what the wiki says about it.
function CreditedImageViewer:openSource()
    local page_url = self.page_urls and self.page_urls[self._images_list_cur or 1]
    if page_url and Device:canOpenLink() then
        Device:openLink(page_url)
    end
end

local Viewer = {}

--- Displays a list of results.
-- @param title what the reader highlighted, resolved to the wiki's name for it
-- @param results list of { url, caption } as returned by a source
-- @param on_pin called with the index the reader kept, or nil to forget
-- @param pinned_url the picture already kept for this character, if any
function Viewer.show(title, results, on_pin, pinned_url)
    local images, captions, urls, page_urls = {}, {}, {}, {}
    for index, result in ipairs(results) do
        images[index] = ImageFetch.lazy(result.url)
        captions[index] = result.caption
        urls[index] = result.url
        page_urls[index] = result.page_url
    end
    -- Free the decoded images when the viewer closes.
    images.image_disposable = true

    UIManager:show(CreditedImageViewer:new{
        image = images,
        captions = captions,
        urls = urls,
        page_urls = Device:canOpenLink() and page_urls or nil,
        pinned_url = pinned_url,
        caption = captions[1],
        on_pin = on_pin,
        title_text = title,
        with_title_bar = true,
        buttons_visible = true,
    })
end

return Viewer
