-- SPDX-License-Identifier: GPL-2.0-or-later
--
-- KOReader user patch (installed as patches/2-harness.lua in the throwaway
-- KO_HOME only).  Exposes globals callable over the HTTP inspector:
--   curl http://127.0.0.1:$KO_PORT/koreader/globals/<name>/'<arg>'/...
-- Arguments arrive as strings; helpers coerce them.  Every helper that
-- changes the UI defers the work to the next UI tick so the HTTP reply
-- goes out first and the screen repaints normally.

local Event = require("ui/event")
local Geom = require("ui/geometry")
local UIManager = require("ui/uimanager")
local time = require("ui/time")

local function ui() return require("apps/reader/readerui").instance end
local function later(f) UIManager:nextTick(f); return true end

-- Tap at screen coordinates through the normal gesture path: link taps,
-- footnote popups, page-turn zones and menus all react as to a finger.
function _G.harness_tap(x, y)
    x, y = tonumber(x), tonumber(y)
    return later(function()
        UIManager:sendEvent(Event:new("Gesture", {
            ges = "tap", pos = Geom:new{ x = x, y = y, w = 0, h = 0 }, time = time.now(),
        }))
    end)
end

-- Links on the current page, optionally filtered by a plain substring of
-- the target ("#_doc_fragment_26_ QQA.3.5" for internal ones).  Each entry
-- carries a tap point at the middle of the link's first line.
function _G.harness_links(pattern)
    local out = {}
    for _, l in ipairs(ui().document:getPageLinks() or {}) do
        local target = l.section or l.uri or ""
        if not pattern or pattern == "" or target:find(pattern, 1, true) then
            local seg = l.segments and l.segments[1]
            local tx = seg and math.floor((seg.x0 + seg.x1) / 2) or l.start_x
            local ty = seg and math.floor((seg.y0 + seg.y1) / 2) or l.start_y
            table.insert(out, { target = target, tap_x = tx, tap_y = ty,
                start_x = l.start_x, start_y = l.start_y, end_x = l.end_x, end_y = l.end_y })
        end
    end
    return out
end

-- Page containing an xpointer such as /body/DocFragment[9]; DocFragment[n]
-- is the n-th spine item (cover = 1).
function _G.harness_page(xp) return ui().document:getPageFromXPointer(xp) end

function _G.harness_goto_xp(xp)
    return later(function() ui().rolling:onGotoXPointer(xp) end)
end

-- Walk pages forward from the current one until a link matches; stops on
-- that page.  Returns {page=, links=} or {page=, links={}} after max pages.
function _G.harness_find_link(pattern, max)
    max = tonumber(max) or 50
    local r = ui().rolling
    for _ = 1, max do
        local links = _G.harness_links(pattern)
        if #links > 0 then return { page = ui().document:getCurrentPage(), links = links } end
        r:onGotoViewRel(1)
    end
    UIManager:setDirty("all", "full")
    return { page = ui().document:getCurrentPage(), links = {} }
end

function _G.harness_state()
    local d = ui().document
    local st = ui().styletweak
    local tweaks = {}
    for id in pairs(st.global_tweaks or {}) do if st:isTweakEnabled(id) then tweaks[id] = true end end
    for id, v in pairs(st.doc_tweaks or {}) do tweaks[id] = v and true or nil end
    return {
        page = d:getCurrentPage(), pages = d:getPageCount(), xpointer = d:getXPointer(),
        font_size = ui().document.configurable.font_size,
        hide_nonlinear = ui().rolling.hide_nonlinear_flows,
        footnote_popup = G_reader_settings:isTrue("footnote_link_in_popup"),
        tweaks = tweaks,
        widgets = (function()
            local w = {}
            for _, e in ipairs(UIManager._window_stack) do table.insert(w, e.widget.name or e.widget.title or "?") end
            return w
        end)(),
    }
end

-- Book-level style tweak on/off ("1"/"0"), e.g. footnote-inpage_epub.
-- Re-renders the book; page numbers shift afterwards.
function _G.harness_tweak(id, on)
    on = on == true or on == "1" or on == "true"
    return later(function()
        local st = ui().styletweak
        if st:isTweakEnabled(id) ~= on then st:onToggleStyleTweak(id, nil, true) end
    end)
end

-- Book-level "Hide non-linear fragments" (EPUB aside[epub:type=footnote]
-- bodies are non-linear in KOReader's html5.css).
function _G.harness_hide_nonlinear(on)
    on = on == true or on == "1" or on == "true"
    return later(function()
        if (ui().rolling.hide_nonlinear_flows and true or false) ~= on then ui().rolling:onToggleHideNonlinear() end
    end)
end

function _G.harness_font_size(size)
    return later(function() ui():handleEvent(Event:new("SetFontSize", tonumber(size))) end)
end

-- Global setting, saved immediately (e.g. footnote_link_in_popup true).
function _G.harness_gset(key, value)
    if value == "true" then value = true elseif value == "false" then value = false
    elseif tonumber(value) then value = tonumber(value) end
    G_reader_settings:saveSetting(key, value)
    return G_reader_settings:readSetting(key)
end

-- Close the top-most widget (popup, menu, dialog).
function _G.harness_close()
    return later(function() UIManager:sendEvent(Event:new("Close")) end)
end
