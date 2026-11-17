require "WardrobeLoadouts/Shared"

local WLM = WardrobeLoadouts
local Cursor = {}
WLM.Cursor = Cursor
local lastFunction, lastState, nextSignal
local reportedStatus

local function report(status, message)
    if reportedStatus == status then return end
    if WLM.debugLog("[WardrobeLoadouts Cursor] " .. message) then reportedStatus = status end
end

function Cursor.sync(visible)
    local addons = Viewpoint and Viewpoint.Addons
    local addon = addons and addons["maeiro.wardrobe-cursor"]
    local bridge = addon and addon.WardrobeCursor
    local fn = bridge and bridge.setOpen
    if type(fn) ~= "function" then
        lastFunction, lastState, nextSignal = nil, nil, nil
        if visible then report("unavailable", "Cursor export unavailable. Restart after first install, then activate Wardrobe Loadouts Cursor in Viewpoint > Advanced > Addons.") end
        return
    end
    local now = getTimestampMs()
    if fn ~= lastFunction or visible ~= lastState or (visible and now >= (nextSignal or 0)) then
        local ok, accepted = pcall(fn, visible == true)
        lastFunction, lastState = fn, visible
        nextSignal = now + (ok and accepted and 500 or 1000)
        if visible then
            if ok and accepted then
                report("ready", "Cursor claim active while the wardrobe is open.")
            else
                report("unavailable", "Cursor addon unavailable: " .. tostring(accepted) .. ". Check its card in Viewpoint > Advanced > Addons.")
            end
        end
    end
end

local function updateCursor()
    local window = WLM.Client and WLM.Client.window
    Cursor.sync(window ~= nil and not window.removed and window:getIsVisible())
end

if Events and Events.OnPreUIDraw then
    if WLM.cursorHandler then Events.OnPreUIDraw.Remove(WLM.cursorHandler) end
    WLM.cursorHandler = updateCursor
    Events.OnPreUIDraw.Add(updateCursor)
end
