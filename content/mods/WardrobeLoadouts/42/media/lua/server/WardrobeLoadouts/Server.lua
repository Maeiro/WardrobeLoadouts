require "WardrobeLoadouts/Shared"

if not isServer() then return end

local WLM = WardrobeLoadouts
local LOCK_SECONDS = 90
local slotSwitches = setmetatable({}, { __mode = "k" })

local function send(player, command, args)
    sendServerCommand(player, WLM.ID, command, args or {})
end

local function fail(player, message, messageKey)
    send(player, "error", { message = message, messageKey = messageKey })
end

local function findWardrobe(player, args, allowRemoteAbort)
    local x, y, z = tonumber(args.x), tonumber(args.y), tonumber(args.z)
    if not x or not y or not z then return nil end
    local square = getCell():getGridSquare(x, y, z)
    if not square then return nil end
    local objects = square:getObjects()
    local wantedIndex = tonumber(args.objectIndex)
    local wantedSprite = tostring(args.spriteName or "")
    local exactMatch, fallback, fallbackCount
    fallbackCount = 0, 0
    for index = 0, objects:size() - 1 do
        local object = objects:get(index)
        if WLM.isWardrobe(object) then
            local objectIndex = index
            pcall(function() objectIndex = object:getObjectIndex() end)
            local spriteName = ""
            pcall(function() spriteName = object:getSprite():getName() end)
            if wantedIndex == objectIndex and (wantedSprite == "" or wantedSprite == spriteName) then
                exactMatch = object
                break
            end
            if wantedSprite == "" or wantedSprite == spriteName then
                fallback = object
                fallbackCount = fallbackCount + 1
            end
        end
    end
    local object = exactMatch or (fallbackCount == 1 and fallback)
    if not object then return nil end

    object = WLM.storageObject(object)
    local container = object:getContainer()
    if not allowRemoteAbort then
        if not WLM.canAccessStorage(player, object) then return nil end
    end
    WLM.capacity(container)
    return object
end

local function playerItem(player, id)
    local inventory = player and player:getInventory()
    return WLM.findItem(inventory, id)
end

local function validProfile(profile)
    if type(profile) ~= "table" or type(profile.name) ~= "string" then return false end
    if #profile.name < 1 or #profile.name > 64 then return false end
    if profile.slot ~= nil and (type(profile.slot) ~= "number" or profile.slot < 1 or profile.slot ~= math.floor(profile.slot) or profile.slot > 1000) then return false end
    if type(profile.worn) ~= "table" or type(profile.attached) ~= "table" or type(profile.hands) ~= "table" then return false end
    if #profile.worn > 64 or #profile.attached > 32 then return false end
    for _, entry in ipairs(profile.worn) do
        if type(entry) ~= "table" or not tonumber(entry.id) then return false end
    end
    for _, entry in ipairs(profile.attached) do
        if type(entry) ~= "table" or type(entry.slotType) ~= "string" or not tonumber(entry.slotIndex) or not tonumber(entry.id) then return false end
    end
    for _, entry in pairs(profile.hands) do
        if entry ~= nil and (type(entry) ~= "table" or not tonumber(entry.id)) then return false end
    end
    if profile.keyRing ~= nil and (type(profile.keyRing) ~= "table" or not tonumber(profile.keyRing.id)) then return false end
    for _, id in ipairs(WLM.profileItems(profile)) do
        if id <= 0 or id ~= math.floor(id) then return false end
    end
    return true
end

local function publishState(player, object, data)
    send(player, "state", {
        object = WLM.objectArgs(object),
        data = data or WLM.getData(object, true),
    })
end

local function clearStoredActiveProfile(player, object, data)
    local activeId = WLM.getActiveId(data, player)
    local profile = activeId and data.sets[tostring(activeId)]
    if not profile then return false end
    local wardrobe = object:getContainer()
    for _, id in ipairs(WLM.profileItems(profile)) do
        if not playerItem(player, id) and WLM.findItem(wardrobe, id) then
            WLM.setActiveId(data, player, nil)
            object:transmitModData()
            return true
        end
    end
    return false
end

local function storeCapacityDelta(player, container, profile)
    local delta = 0
    for _, id in ipairs(WLM.profileItems(profile)) do
        if not WLM.findItem(container, id) then delta = delta + WLM.itemWeight(playerItem(player, id)) end
    end
    return delta
end

local function handleBeginStore(player, object, args)
    if player:getVehicle() then
        fail(player, "Exit the vehicle before storing equipment.", "IGUI_WLM_ErrorVehicle")
        return
    end
    local data = WLM.getData(object, true)
    if data.lock and (data.lockUntil or 0) > getTimestamp() then
        fail(player, "This wardrobe is being used by another player.", "IGUI_WLM_ErrorLocked")
        return
    end
    local profile = args.profile
    if not validProfile(profile) then
        fail(player, "The equipment data could not be saved.", "IGUI_WLM_ErrorSave")
        return
    end

    local updateId = args.updateId and tostring(args.updateId) or nil
    if updateId and (not data.sets[updateId] or WLM.getActiveId(data, player) ~= updateId) then
        fail(player, "Only the active loadout can be updated.", "IGUI_WLM_ErrorUpdateActive")
        return
    end
    if not updateId and profile.slot and not WLM.slotAvailable(data, profile.slot) then
        fail(player, "This slot is no longer empty. Refresh the wardrobe.", "IGUI_WLM_ErrorSlotOccupied")
        return
    end
    if not updateId and WLM.countSets(data) >= WLM.settings().maxLoadouts then
        fail(player, "This wardrobe has reached its loadout limit.", "IGUI_WLM_ErrorLimit")
        return
    end

    for _, itemId in ipairs(WLM.profileItems(profile)) do
        if not playerItem(player, itemId) then
            fail(player, "A saved item is no longer in this character's inventory.", "IGUI_WLM_ErrorMissingInventory")
            return
        end
    end
    local container = object:getContainer()
    local usedWeight = 0
    pcall(function() usedWeight = WLM.storageWeight(container) end)
    if usedWeight + storeCapacityDelta(player, container, profile) > WLM.settings().storageCapacity then
        fail(player, "The wardrobe needs more free capacity before storing this equipment.", "IGUI_WLM_ErrorCapacity")
        return
    end

    slotSwitches[object] = nil
    data.lock = player:getOnlineID()
    data.lockUntil = getTimestamp() + LOCK_SECONDS
    object:transmitModData()
    send(player, "storeReady", { updateId = updateId or "", object = WLM.objectArgs(object) })
end

local function handleFinishStore(player, object, args)
    local data = WLM.getData(object, false)
    if not data or data.lock ~= player:getOnlineID() then return end
    local profile = args.profile
    local updateId = args.updateId and tostring(args.updateId) or nil
    local function reject(message, key)
        if WLM.getActiveId(data, player) then
            WLM.setActiveId(data, player, nil)
        end
        data.lock, data.lockUntil = nil, nil
        object:transmitModData()
        fail(player, message, key)
        publishState(player, object, data)
    end
    if not validProfile(profile) then
        reject("The equipment data could not be saved.", "IGUI_WLM_ErrorSave")
        return
    end
    if updateId and (not data.sets[updateId] or WLM.getActiveId(data, player) ~= updateId) then
        reject("Only the active loadout can be updated.", "IGUI_WLM_ErrorUpdateActive")
        return
    end
    if not updateId and profile.slot and not WLM.slotAvailable(data, profile.slot) then
        reject("This slot is no longer empty. Refresh the wardrobe.", "IGUI_WLM_ErrorSlotOccupied")
        return
    end
    if not updateId and WLM.countSets(data) >= WLM.settings().maxLoadouts then
        reject("This wardrobe has reached its loadout limit.", "IGUI_WLM_ErrorLimit")
        return
    end
    for _, id in ipairs(WLM.profileItems(profile)) do
        if not WLM.findItem(object:getContainer(), id) then
            reject("Some items could not be moved into the wardrobe; the loadout was not saved.", "IGUI_WLM_ErrorStoreIncomplete")
            return
        end
    end
    local usedWeight = 0
    pcall(function() usedWeight = WLM.storageWeight(object:getContainer()) end)
    if usedWeight > WLM.settings().storageCapacity then
        reject("The wardrobe is over its configured capacity; the loadout was not saved.", "IGUI_WLM_ErrorCapacity")
        return
    end

    local id = updateId or tostring(data.nextId)
    if not updateId then data.nextId = data.nextId + 1 end
    profile.id = id
    profile.savedAt = getTimestamp()
    local previousActiveId = WLM.getActiveId(data, player)
    if profile.slot and previousActiveId and tostring(previousActiveId) ~= id then
        data.sets[tostring(previousActiveId)] = nil
    end
    data.sets[id] = profile
    WLM.setActiveId(data, player, nil)
    data.lock, data.lockUntil = nil, nil
    object:transmitModData()
    send(player, "storeComplete", { object = WLM.objectArgs(object) })
    publishState(player, object, data)
end

local function handleAbortStore(player, object, args)
    local data = WLM.getData(object, false)
    if not data or data.lock ~= player:getOnlineID() then return end
    if args and args.restoreActive and WLM.getActiveId(data, player) then
        WLM.setActiveId(data, player, nil)
    end
    data.lock, data.lockUntil = nil, nil
    object:transmitModData()
    publishState(player, object, data)
end

local function findItemAnywhere(player, wardrobeContainer, id)
    return WLM.findItem(wardrobeContainer, id) or playerItem(player, id)
end

local function handleBeginSwitch(player, object, args)
    if player:getVehicle() then
        fail(player, "Exit the vehicle before changing loadouts.", "IGUI_WLM_ErrorVehicle")
        return
    end
    local data = WLM.getData(object, false)
    local targetId = tostring(args.targetId or "")
    local activeId = tostring(args.activeId or "")
    local target = data and data.sets[targetId]
    local active = activeId ~= "" and data and data.sets[activeId] or nil
    local storedActiveId = tostring(WLM.getActiveId(data, player) or "")
    if not data or not target or targetId == activeId or storedActiveId ~= activeId or (activeId ~= "" and not active) then
        fail(player, "Save the current equipment and refresh the wardrobe before switching.", "IGUI_WLM_ErrorRefresh")
        return
    end
    if data.lock and (data.lockUntil or 0) > getTimestamp() and data.lock ~= player:getOnlineID() then
        fail(player, "This wardrobe is being used by another player.", "IGUI_WLM_ErrorLocked")
        return
    end
    if args.slotAction and WLM.isSetActive(data, targetId) then
        fail(player, "This equipment is currently being used by a player.", "IGUI_WLM_ErrorSetActive")
        return
    end
    if args.slotAction then
        if not validProfile(args.swapProfile) then
            fail(player, "The equipment data could not be saved.", "IGUI_WLM_ErrorSave")
            return
        end
        active = args.swapProfile
        local slots = WLM.slots(data)
        for slot, entry in pairs(slots) do if entry.id == targetId then active.slot = slot; break end end
    end
    local container = object:getContainer()
    if active then
        for _, id in ipairs(WLM.profileItems(active)) do
            if not playerItem(player, id) then
                fail(player, "The active loadout is incomplete. Update it before switching.", "IGUI_WLM_ErrorActiveIncomplete")
                return
            end
        end
    end
    for _, id in ipairs(WLM.profileItems(target)) do
        if not findItemAnywhere(player, container, id) then
            fail(player, "A piece from the selected loadout is missing.", "IGUI_WLM_ErrorMissingPiece")
            return
        end
    end

    local activeIds, targetIds = {}, {}
    for _, id in ipairs(WLM.profileItems(active)) do activeIds[id] = true end
    for _, id in ipairs(WLM.profileItems(target)) do targetIds[id] = true end
    local capacityDelta = 0
    for id in pairs(activeIds) do
        if not targetIds[id] then capacityDelta = capacityDelta + WLM.itemWeight(playerItem(player, id)) end
    end
    for id in pairs(targetIds) do
        if not activeIds[id] then
            local item = WLM.findItem(container, id)
            if item then capacityDelta = capacityDelta - WLM.itemWeight(item) end
        end
    end
    local usedWeight = 0
    pcall(function() usedWeight = WLM.storageWeight(container) end)
    if usedWeight + capacityDelta > WLM.settings().storageCapacity then
        fail(player, "The wardrobe needs more free capacity for this switch.", "IGUI_WLM_ErrorCapacity")
        return
    end

    data.lock = player:getOnlineID()
    data.lockUntil = getTimestamp() + LOCK_SECONDS
    object:transmitModData()
    slotSwitches[object] = args.slotAction and { player = player, targetId = targetId, profile = active } or nil
    send(player, "switchReady", { targetId = targetId, activeId = activeId,
        slotAction = args.slotAction == true, swapProfile = args.slotAction and active or nil })
end

local function handleFinishSwitch(player, object, args, aborted)
    local data = WLM.getData(object, false)
    if not data or data.lock ~= player:getOnlineID() then return end
    if not aborted then
        local targetId = tostring(args.targetId or "")
        local target = data.sets[targetId]
        if not target then
            data.lock = nil
            data.lockUntil = nil
            object:transmitModData()
            return
        end
        for _, id in ipairs(WLM.profileItems(target)) do
            if not playerItem(player, id) then
                data.lock = nil
                data.lockUntil = nil
                object:transmitModData()
                fail(player, "The switch did not finish; the previous loadout remains active.", "IGUI_WLM_ErrorSwitchIncomplete")
                return
            end
        end
        local slotSwitch = slotSwitches[object]
        if slotSwitch and slotSwitch.player == player and slotSwitch.targetId == targetId then
            for _, id in ipairs(WLM.profileItems(slotSwitch.profile)) do
                if not WLM.findItem(object:getContainer(), id) then
                    data.lock, data.lockUntil = nil, nil
                    slotSwitches[object] = nil
                    object:transmitModData()
                    fail(player, "Some equipment could not be stored; the slot was not changed.", "IGUI_WLM_ErrorStoreIncomplete")
                    publishState(player, object, data)
                    return
                end
            end
            WLM.completeSlotSwitch(data, player, targetId, slotSwitch.profile)
        else
            WLM.setActiveId(data, player, targetId)
        end
    end
    slotSwitches[object] = nil
    data.lock = nil
    data.lockUntil = nil
    object:transmitModData()
    publishState(player, object, data)
end

local function onClientCommand(module, command, player, args)
    if module ~= WLM.ID or not player or type(args) ~= "table" then return end
    local object = findWardrobe(player, args, command == "abortSwitch" or command == "abortStore")
    if not object then
        if command == "abortSwitch" or command == "abortStore" then return end
        fail(player, "Move closer to the wardrobe and try again.", "IGUI_WLM_ErrorTooFar")
        return
    end
    if command == "request" then
        local data = WLM.getData(object, true)
        clearStoredActiveProfile(player, object, data)
        publishState(player, object, data)
    elseif command == "beginStore" then
        handleBeginStore(player, object, args)
    elseif command == "finishStore" then
        handleFinishStore(player, object, args)
    elseif command == "abortStore" then
        handleAbortStore(player, object, args)
    elseif command == "beginSwitch" then
        handleBeginSwitch(player, object, args)
    elseif command == "finishSwitch" then
        handleFinishSwitch(player, object, args, false)
    elseif command == "abortSwitch" then
        handleFinishSwitch(player, object, args, true)
    elseif command == "icon" then
        local data = WLM.getData(object, false)
        local slot, icon = tonumber(args.slot), args.icon
        local _, count = WLM.slots(data)
        if not data or not slot or slot < 1 or slot ~= math.floor(slot) or slot > count then return end
        if type(icon) ~= "string" or #icon > 250 or icon:find("..", 1, true) or icon:find("[\r\n]") then return end
        if data.lock and (data.lockUntil or 0) > getTimestamp() then return end
        data.slotIcons = data.slotIcons or {}
        data.slotIcons[tostring(slot)] = icon ~= "" and icon or nil
        object:transmitModData()
        publishState(player, object, data)
    elseif command == "rename" then
        local data = WLM.getData(object, false)
        local profile = data and data.sets[tostring(args.setId or "")]
        local name = type(args.name) == "string" and args.name:gsub("^%s+", ""):gsub("%s+$", "") or ""
        local slot = tonumber(args.slot) or (profile and profile.slot)
        local _, slotCount = WLM.slots(data)
        if not data or not slot or slot < 1 or slot ~= math.floor(slot) or slot > slotCount then return end
        if #name == 0 or #name > 64 then
            fail(player, "Loadout names must be 1 to 64 bytes long.", "IGUI_WLM_ErrorNameLength")
            return
        end
        if data.lock and (data.lockUntil or 0) > getTimestamp() then
            fail(player, "This wardrobe is being used by another player.", "IGUI_WLM_ErrorLocked")
            return
        end
        WLM.setSlotName(data, slot, name)
        object:transmitModData()
        publishState(player, object, data)
    elseif command == "delete" then
        local data = WLM.getData(object, false)
        local id = tostring(args.setId or "")
        if not data or not data.sets[id] then return end
        if WLM.isSetActive(data, id) then
            fail(player, "Save another loadout before deleting the active one.", "IGUI_WLM_ErrorSetActive")
            return
        end
        if data.lock and (data.lockUntil or 0) > getTimestamp() then
            fail(player, "This wardrobe is being used by another player.", "IGUI_WLM_ErrorLocked")
            return
        end
        data.sets[id] = nil
        object:transmitModData()
        publishState(player, object, data)
    end
end

Events.OnClientCommand.Add(onClientCommand)
