-- popup-click-off.lua — shared click-off dismissal manager for widget popups.
--
-- attach(popup, hide_fn) makes a popup close when the user clicks anywhere
-- outside it. Awesome only sees pointer events on windows it owns or has
-- grabbed, so "outside" needs two hooks:
--   * client windows — rc.lua's click-to-focus binding grabs button 1 in
--     sync+replay mode, so a click into an app emits "button::press" on that
--     client and is still delivered to the app underneath;
--   * the desktop — root-window clicks have no signal in v4.3, so while any
--     attached popup is open, close-only root.buttons() bindings for buttons
--     1/2/3 are appended (rc.lua only binds 4/5 there for tag scrolling) and
--     the original set is restored once the last popup closes.
-- Opening one attached popup also closes every other attached popup, so
-- clicking a different widget's wibar icon swaps popups instead of stacking.
--
-- Known limit: clicks on other wiboxes (the wibar itself, an unattached
-- popup) are not observable from Lua in v4.3 and do not dismiss anything;
-- each widget's own icon click already toggles its popup closed.
--
-- This file is duplicated into every widget repo (same pattern as the
-- awesome-verify skill): edit it in ONE place, bump _VERSION, and re-sync
-- every copy. All copies share one process-wide manager through _G — the
-- first copy loaded wins unless a later-loaded copy has a higher _VERSION.

local awful = require("awful")
local gears = require("gears")

local _VERSION = 1

local existing = _G.__widget_popup_click_off
if existing and existing.version >= _VERSION then
    return existing
end

local mgr = { version = _VERSION }

local open = {} -- popup -> hide_fn, for each attached popup currently shown
local saved_root_buttons = nil

local function close_all(except)
    -- hide_fn flips popup.visible, whose signal handler mutates `open`, so
    -- snapshot the victims before calling any of them
    local victims = {}
    for popup, hide in pairs(open) do
        if popup ~= except then
            victims[#victims + 1] = hide
        end
    end
    for _, hide in ipairs(victims) do
        hide()
    end
end

local function on_client_press()
    close_all()
end

local function watch_outside_clicks()
    if saved_root_buttons then -- already watching; never double-augment
        return
    end
    client.connect_signal("button::press", on_client_press)
    saved_root_buttons = root.buttons()
    root.buttons(gears.table.join(
        saved_root_buttons,
        awful.button({}, 1, function() close_all() end),
        awful.button({}, 2, function() close_all() end),
        awful.button({}, 3, function() close_all() end)
    ))
end

local function unwatch_outside_clicks()
    if not saved_root_buttons then
        return
    end
    client.disconnect_signal("button::press", on_client_press)
    root.buttons(saved_root_buttons)
    saved_root_buttons = nil
end

--- Register a popup for click-off dismissal.
-- @param popup an awful.popup (or any wibox toggled via .visible)
-- @param hide_fn optional closer for outside clicks; defaults to setting
--        popup.visible = false. Pass the widget's own hide function when
--        hiding needs extra teardown (keygrabbers, state resets, ...).
function mgr.attach(popup, hide_fn)
    hide_fn = hide_fn or function()
        popup.visible = false
    end
    popup:connect_signal("property::visible", function()
        if popup.visible then
            -- register before closing the others, so the watcher never
            -- tears down and immediately re-arms mid-swap
            open[popup] = hide_fn
            close_all(popup)
            watch_outside_clicks()
        else
            open[popup] = nil
            if next(open) == nil then
                unwatch_outside_clicks()
            end
        end
    end)
end

_G.__widget_popup_click_off = mgr
return mgr
