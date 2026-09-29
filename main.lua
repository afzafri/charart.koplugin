--[[--
Character Art: look up art of a character by highlighting their name.

Highlighting a name in a book and tapping "Character art" searches the book's
wiki for pictures of that character and shows them in an image viewer.

@module koplugin.CharArt
--]]--

local ArtCache = require("artcache")
local ConfirmBox = require("ui/widget/confirmbox")
local Device = require("device")
local Dispatcher = require("dispatcher")
local ImageFetch = require("imagefetch")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local Lookup = require("lookup")
local Trapper = require("ui/trapper")
local UIManager = require("ui/uimanager")
local Viewer = require("viewer")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local WikiResolver = require("wiki_resolver")
local Http = require("http")
local ffiUtil = require("ffi/util")
local logger = require("logger")
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

--- Registers a gesture-bindable action.
-- The highlight menu is not always reachable: a single-word press opens the
-- dictionary by default, and some KOReader distributions replace the menu with
-- one of their own. A bindable action gives readers a way in that does not
-- depend on any of that, and does not override anything.
function CharArt:onDispatcherRegisterActions()
    Dispatcher:registerAction("charart_lookup", {
        category = "none",
        event = "CharArtLookup",
        title = _("Character Art"),
        reader = true,
    })
end

--- Looks up whatever is selected, or asks for a name if nothing is.
function CharArt:onCharArtLookup()
    local highlight = self.ui and self.ui.highlight
    local selected = highlight and highlight.selected_text
    local term = selected and util.cleanupSelectedText(selected.text)
    if term and term ~= "" then
        if highlight then
            highlight:onClose(true)
        end
        self:lookup(term)
    else
        self:askForName()
    end
    return true
end

--- Asks for a character's name, for looking someone up without finding them
-- on the page first.
function CharArt:askForName()
    local dialog
    dialog = InputDialog:new{
        title = _("Character Art"),
        description = _("Whose picture are you looking for?"),
        input = "",
        buttons = {{
            {
                text = _("Cancel"),
                id = "close",
                callback = function()
                    UIManager:close(dialog)
                end,
            },
            {
                text = _("Look up"),
                is_enter_default = true,
                callback = function()
                    local term = dialog:getInputText()
                    UIManager:close(dialog)
                    if term and term ~= "" then
                        self:lookup(term)
                    end
                end,
            },
        }},
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

--- Adds a button to the dictionary popup.
-- Holding a single word opens the dictionary rather than the highlight menu,
-- and that is the gesture people actually use on a name, so the plugin should
-- be reachable from there too. KOReader offers a registration API for this;
-- nothing of the dictionary's own is replaced or overridden.
function CharArt:registerDictButtons()
    local dictionary = self.ui and self.ui.dictionary
    if not (dictionary and dictionary.addToDictButtons) then
        return -- older KOReader without the dictionary button API
    end

    dictionary:addToDictButtons({
        id = "charart_lookup",
        menu_text = _("Character Art"),
        text = _("Character Art"),
        insert_first = true,
        callback = function(dict_popup)
            local term = dict_popup.word
            dict_popup:onClose(true)
            if term and term ~= "" then
                self:lookup(term)
            end
        end,
    })
end

function CharArt:init()
    self:onDispatcherRegisterActions()
    self:registerDictButtons()
    if self.ui and self.ui.highlight and self.document then
        self:addToHighlightDialog()
    end
    if self.ui and self.ui.menu then
        self.ui.menu:registerToMainMenu(self)
    end
    logger.info("CharArt: ready,", #Lookup.sources, "source(s)")
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
            text = _("Character Art"),
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
    local found, kind = WikiResolver.resolve(self.ui.doc_props)
    if found then
        self.ui.doc_settings:saveSetting("charart_wiki", found)
    end
    return found, kind
end

--- Says the wiki could not be reached, rather than pretending we looked.
-- Offering a web search here would be no use: that needs the network too.
function CharArt:showOffline()
    UIManager:show(InfoMessage:new{
        text = _("Could not reach the wiki.\n\nCharacter Art needs a network connection to fetch pictures. Once a picture has been shown it is kept on the device, and looking that character up again works offline."),
    })
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

--- Asks which wiki covers this book, and checks the answer before keeping it.
-- Not prefilled with a guess: we only get here because the guesses failed, and
-- offering a known-bad one under a "Use this" button invites the reader to
-- save it. When they already have a wiki set, that is worth showing, since
-- this is also how it gets corrected.
function CharArt:askForWiki(on_chosen)
    local current = self.document and self.ui.doc_settings:readSetting("charart_wiki")
    local dialog
    dialog = InputDialog:new{
        title = _("Wiki for this book"),
        description = _("Address of a wiki covering this book, or just its Fandom name, like dungeon-crawler-carl."),
        input = current or "",
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
                    if not wiki then
                        return
                    end
                    -- Check it before saving it. A typo kept silently would
                    -- have every later lookup reporting that the character is
                    -- not on the wiki, which sends the reader looking for the
                    -- wrong problem.
                    Trapper:wrap(function()
                        Trapper:info(T(_("Checking %1…"), wiki:gsub("^https?://", "")))
                        local ok, kind = WikiResolver.verify(wiki)
                        Trapper:clear()

                        if ok then
                            UIManager:close(dialog)
                            self.ui.doc_settings:saveSetting("charart_wiki", wiki)
                            on_chosen(wiki)
                        elseif kind == Http.OFFLINE then
                            self:showOffline()
                        else
                            -- Left open so the address can be corrected.
                            UIManager:show(InfoMessage:new{
                                text = T(_("%1 did not answer.\n\nCheck the address, or open the wiki in a browser to see what it is called."),
                                    wiki:gsub("^https?://", "")),
                            })
                        end
                    end)
                end,
            },
        }},
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

--- Moves the picture the reader settled on last time to the front.
-- The wiki may have gained better art since, so the rest of the results are
-- kept and simply follow behind it.
function CharArt:pinnedFirst(wiki, title, results)
    local pinned = ArtCache.pinned(wiki, title)
    if not pinned or not pinned.url then
        return results
    end

    local ordered = { pinned }
    for _, result in ipairs(results) do
        if result.url ~= pinned.url then
            table.insert(ordered, result)
        end
    end
    return ordered
end

function CharArt:lookup(term)
    -- Trapper gives us a "Searching" popup the reader can dismiss, and lets
    -- the network calls below run without freezing the UI.
    Trapper:wrap(function()
        Trapper:info(_("Finding this book's wiki…"))
        local wiki, wiki_err = self:getWiki()
        Trapper:clear()
        if not wiki then
            if wiki_err == Http.OFFLINE then
                -- We never got off the device, so we do not know whether this
                -- book has a wiki. Asking them to name one would be pretending
                -- we had looked.
                self:showOffline()
            else
                -- Ask, then start over once we have an answer.
                self:askForWiki(function()
                    self:lookup(term)
                end)
            end
            return
        end

        -- A character looked up once tends to be looked up again later, so
        -- reuse the earlier answer rather than asking the wiki twice.
        local results, err, kind = ArtCache.recall(wiki, term)
        if not results then
            Trapper:info(T(_("Looking for pictures of %1…"), term))
            results, err, kind = Lookup.run{
                term = term,
                wiki = wiki,
                limit = IMAGE_COUNT,
                width = IMAGE_WIDTH,
            }
            if results then
                ArtCache.remember(wiki, term, results)
            end
        end
        if not results then
            Trapper:clear()
            if kind == Http.OFFLINE then
                self:showOffline()
            else
                self:showNothingFound(term, err)
            end
            return
        end

        local title = results[1].title or term
        local pinned = ArtCache.pinned(wiki, title)
        results = self:pinnedFirst(wiki, title, results)

        -- Downloading the first picture is the slowest part, so keep the
        -- message up until it is here. Otherwise the screen sits unchanged for
        -- a few seconds and it looks like nothing happened. The rest are still
        -- fetched only if the reader swipes to them.
        Trapper:info(T(_("Fetching a picture of %1…"), title))
        ImageFetch.prefetch(results[1].url)
        Trapper:clear()

        Viewer.show(title, results, function(chosen)
            ArtCache.pin(wiki, title, chosen and results[chosen] or nil)
        end, pinned and pinned.url)
    end)
end

function CharArt:addToMainMenu(menu_items)
    menu_items.charart = {
        text = _("Character Art"),
        sorting_hint = "more_tools",
        sub_item_table = {
            {
                -- Also the way to correct a wrong guess, which is why it shows
                -- the wiki currently in use rather than a bare "Change wiki".
                text_func = function()
                    local wiki = self.document and self.ui.doc_settings:readSetting("charart_wiki")
                    if wiki then
                        return T(_("Wiki: %1"), wiki:gsub("^https?://", ""))
                    end
                    return _("Wiki for this book")
                end,
                enabled_func = function()
                    return self.document ~= nil
                end,
                keep_menu_open = true,
                callback = function()
                    self:askForWiki(function() end)
                end,
            },
            {
                text = _("Forget saved pictures"),
                keep_menu_open = true,
                separator = true,
                callback = function()
                    ArtCache.clear()
                    UIManager:show(InfoMessage:new{
                        text = _("Saved pictures cleared."),
                    })
                end,
            },
        },
    }
end

return CharArt
