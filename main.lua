--[[--
Character Art: look up art of a character by highlighting their name.

Highlighting a name in a book and tapping "Character art" searches the book's
wiki for pictures of that character and shows them in an image viewer.

@module koplugin.CharArt
--]]--

local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local ffiUtil = require("ffi/util")
local util = require("util")
local _ = require("gettext")
local T = ffiUtil.template

local CharArt = WidgetContainer:extend{
    name = "charart",
}

function CharArt:init()
    if self.ui and self.ui.highlight and self.document then
        self:addToHighlightDialog()
    end
    if self.ui and self.ui.menu then
        self.ui.menu:registerToMainMenu(self)
    end
end

--- Returns the text the user selected, cleaned up for searching.
-- Mirrors what ReaderHighlight:saveHighlight() does, so that a selection made
-- with a single long-press behaves the same as one made by dragging.
function CharArt:getSelectedText(highlight)
    highlight:highlightFromHoldPos()
    local selected = highlight.selected_text
    if not (selected and selected.pos0 and selected.pos1) then
        return nil
    end
    local text
    if highlight.ui.rolling then
        local extended = highlight.ui.document:extendXPointersToSentenceSegment(selected.pos0, selected.pos1)
        text = extended and extended.text
    end
    return util.cleanupSelectedText(text or selected.text)
end

function CharArt:addToHighlightDialog()
    -- "12_search" is the last entry in the highlight dialog; sorting is
    -- alphabetical, so "12_character_art" lands just before it.
    self.ui.highlight:addToHighlightDialog("12_character_art", function(this)
        return {
            text = _("Character art"),
            callback = function()
                local term = self:getSelectedText(this)
                this:onClose(true)
                if not term or term == "" then return end
                self:lookup(term)
            end,
        }
    end)
end

function CharArt:lookup(term)
    UIManager:show(InfoMessage:new{
        text = T(_("Looking up art for %1"), term),
    })
end

function CharArt:addToMainMenu(menu_items)
    menu_items.charart = {
        text = _("Character art"),
        sorting_hint = "more_tools",
        sub_item_table = {},
    }
end

return CharArt
