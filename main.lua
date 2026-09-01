--[[--
Character Art: look up art of a character by highlighting their name.

Highlighting a name in a book and tapping "Character art" searches the book's
wiki for pictures of that character and shows them in an image viewer.

@module koplugin.CharArt
--]]--

local ConfirmBox = require("ui/widget/confirmbox")
local Device = require("device")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local Lookup = require("lookup")
local Trapper = require("ui/trapper")
local UIManager = require("ui/uimanager")
local Viewer = require("viewer")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local WikiResolver = require("wiki_resolver")
local ffiUtil = require("ffi/util")
local socket_url = require("socket.url")
local util = require("util")
local _ = require("gettext")
local T = ffiUtil.template

-- How many pictures to gather, and how wide to ask the wiki to serve them.
local IMAGE_COUNT = 3
local IMAGE_WIDTH = 800

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

--- The wiki to search for this book, remembered per book once we know it.
function CharArt:getWiki()
    local saved = self.ui.doc_settings:readSetting("charart_wiki")
    if saved then
        return saved
    end
    local found = WikiResolver.resolve(self.ui.doc_props)
    if found then
        self.ui.doc_settings:saveSetting("charart_wiki", found)
    end
    return found
end

--- Tells the reader we came up empty, and offers the web as a last resort.
-- Plenty of books have no wiki at all, and on a device that can open a browser
-- handing the search over is more use than an apology.
function CharArt:showNothingFound(term, err)
    local message = T(_("No picture found for %1."), term)
    if err then
        message = message .. "\n\n" .. err
    end

    if not Device:canOpenLink() then
        UIManager:show(InfoMessage:new{ text = message })
        return
    end

    local book = self.ui.doc_props and (self.ui.doc_props.series or self.ui.doc_props.title) or ""
    local query = socket_url.escape(book .. " " .. term .. " art")
    UIManager:show(ConfirmBox:new{
        text = message,
        ok_text = _("Search the web"),
        ok_callback = function()
            Device:openLink("https://duckduckgo.com/?iax=images&ia=images&q=" .. query)
        end,
    })
end

--- Asks which wiki covers this book, prefilled with our best guess.
function CharArt:askForWiki(on_chosen)
    local guess = WikiResolver.slugCandidates(self.ui.doc_props)[1] or ""
    local dialog
    dialog = InputDialog:new{
        title = _("Wiki for this book"),
        description = _("The address of a wiki covering this book, or just its Fandom name."),
        input = guess,
        buttons = {{
            {
                text = _("Cancel"),
                id = "close",
                callback = function()
                    UIManager:close(dialog)
                end,
            },
            {
                text = _("Use this"),
                is_enter_default = true,
                callback = function()
                    local wiki = WikiResolver.normalize(dialog:getInputText())
                    UIManager:close(dialog)
                    if wiki then
                        self.ui.doc_settings:saveSetting("charart_wiki", wiki)
                        on_chosen(wiki)
                    end
                end,
            },
        }},
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

function CharArt:lookup(term)
    -- Trapper gives us a "Searching" popup the reader can dismiss, and lets
    -- the network calls below run without freezing the UI.
    Trapper:wrap(function()
        Trapper:info(_("Finding this book's wiki…"))
        local wiki = self:getWiki()
        Trapper:clear()
        if not wiki then
            -- Ask, then start over once we have an answer.
            self:askForWiki(function()
                self:lookup(term)
            end)
            return
        end

        Trapper:info(T(_("Looking for pictures of %1…"), term))
        local results, err = Lookup.run{
            term = term,
            wiki = wiki,
            limit = IMAGE_COUNT,
            width = IMAGE_WIDTH,
        }
        Trapper:clear()

        if not results then
            self:showNothingFound(term, err)
            return
        end
        Viewer.show(results[1].title or term, results)
    end)
end

function CharArt:addToMainMenu(menu_items)
    menu_items.charart = {
        text = _("Character art"),
        sorting_hint = "more_tools",
        sub_item_table = {},
    }
end

return CharArt
