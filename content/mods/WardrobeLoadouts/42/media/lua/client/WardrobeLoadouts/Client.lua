require "WardrobeLoadouts/Shared"
require "WardrobeLoadouts/Options"
require "WardrobeLoadouts/CarryGuard"
require "TimedActions/ISInventoryTransferUtil"
require "TimedActions/ISWearClothing"
require "TimedActions/ISUnequipAction"
require "TimedActions/ISEquipWeaponAction"
require "TimedActions/ISDetachItemHotbar"
require "TimedActions/ISWLMRestoreAttachmentsAction"
require "TimedActions/ISWLMFinalizeSwitchAction"
require "TimedActions/ISWLMFinalizeStoreAction"
require "TimedActions/ISWLMFinalizeRecoveryAction"

local WLM = WardrobeLoadouts
WLM.Client = WLM.Client or {}
local Client = WLM.Client

local function beginCarry(player, wardrobe, pending)
    pending.carryToken = WLM.CarryGuard.begin(player, wardrobe)
    Client.carryOperation = pending
end

local function getPlayer(playerNum)
    return getSpecificPlayer(playerNum or 0)
end

local function syncItemState(player, item)
    if type(syncItemFields) == "function" then pcall(syncItemFields, player, item) end
end

local function inventoryItem(player, id)
    return WLM.findItem(player and player:getInventory(), id)
end

local function temporarilyUnfavorite(player, wardrobe, profiles, pending)
    pending.favoriteItems = pending.favoriteItems or {}
    local seen = {}
    for _, profile in ipairs(profiles) do
        for _, id in ipairs(WLM.profileItems(profile)) do
            if not seen[id] then
                seen[id] = true
                local item = inventoryItem(player, id) or WLM.findItem(wardrobe, id)
                local ok, favorite = pcall(function() return item and item:isFavorite() end)
                if ok and favorite then
                    local changed = pcall(function() item:setFavorite(false, true) end)
                    if changed then pending.favoriteItems[id] = item end
                end
            end
        end
    end
end

local function restoreFavorites(pending, player, wardrobe)
    for id, item in pairs(pending and pending.favoriteItems or {}) do
        item = item or inventoryItem(player, id) or WLM.findItem(wardrobe, id)
        if item then pcall(function() item:setFavorite(true, true) end) end
    end
    if pending then pending.favoriteItems = nil end
end

local function sameObjectArgs(left, right)
    return left and right and left.x == right.x and left.y == right.y and left.z == right.z
        and left.objectIndex == right.objectIndex and left.spriteName == right.spriteName
end

local function wornItem(player, id)
    local worn = player and player:getWornItems()
    if not worn then return nil end
    for index = 0, worn:size() - 1 do
        local entry = worn:get(index)
        local item = entry and entry:getItem()
        if item and tonumber(item:getID()) == tonumber(id) then return item end
    end
    return nil
end

local function isKeyRing(item)
    if not item then return false end
    local ok, itemType = pcall(function() return item:getType() end)
    if ok and itemType == "KeyRing" then return true end
    if ItemTag and ItemTag.KEY_RING then
        local tagged, result = pcall(function() return item:hasTag(ItemTag.KEY_RING) end)
        if tagged and result then return true end
    end
    return false
end

local function playerKeyRing(player)
    local inventory = player and player:getInventory()
    local items = inventory and inventory:getItems()
    if not items then return nil end
    for index = 0, items:size() - 1 do
        local item = items:get(index)
        if isKeyRing(item) then return item end
    end
    return nil
end

local function notify(message, isError)
    if HaloTextHelper then
        if isError and HaloTextHelper.addBadText then
            HaloTextHelper.addBadText(getPlayer(Client.playerNum), message)
        elseif HaloTextHelper.addGoodText then
            HaloTextHelper.addGoodText(getPlayer(Client.playerNum), message)
        end
    elseif print then
        print("[WardrobeLoadouts] " .. tostring(message))
    end
end

local function logOperation(operation, success, profile, reason)
    if not WLM.Options.diagnosticsEnabled() then return end
    local keyRingId = profile and profile.keyRing and profile.keyRing.id or "none"
    local keyRingFavorite = "none"
    if profile and profile.keyRing then
        local player = getPlayer(Client.playerNum)
        local item = inventoryItem(player, profile.keyRing.id)
            or WLM.findItem(Client.object and Client.object:getContainer(), profile.keyRing.id)
        local ok, favorite = pcall(function() return item and item:isFavorite() end)
        keyRingFavorite = item and ok and tostring(favorite) or "missing"
    end
    local locationDetail = ""
    if operation == "switch" then
        local player = getPlayer(Client.playerNum)
        local wardrobe = Client.object and Client.object:getContainer()
        local inInventory, inWardrobe, both, missing = 0, 0, 0, 0
        for _, id in ipairs(WLM.profileItems(profile)) do
            local inPlayerInventory = inventoryItem(player, id) ~= nil
            local inStorage = WLM.findItem(wardrobe, id) ~= nil
            if inPlayerInventory then inInventory = inInventory + 1 end
            if inStorage then inWardrobe = inWardrobe + 1 end
            if inPlayerInventory and inStorage then both = both + 1 end
            if not inPlayerInventory and not inStorage then missing = missing + 1 end
        end
        locationDetail = string.format(" location=inventory:%d,wardrobe:%d,both:%d,missing:%d",
            inInventory, inWardrobe, both, missing)
    end
    local detail = reason and (" reason=" .. tostring(reason)) or ""
    WLM.debugLog(string.format("[WardrobeLoadouts] %s %s items=%d keyRing=%s keyRingFavorite=%s%s%s",
        operation, success and "complete" or "failed", #WLM.profileItems(profile),
        tostring(keyRingId), keyRingFavorite, locationDetail, detail))
end

local function profileHasRole(profile, id, role)
    local roles = WLM.profileRoles(profile)
    for _, currentRole in ipairs(roles[tonumber(id)] or {}) do
        if currentRole == role then return true end
    end
    return false
end

local function isWearableBag(item)
    local result = false
    if item then
        pcall(function() result = item:IsInventoryContainer() end)
        if not result then pcall(function() result = instanceof(item, "InventoryContainer") end) end
    end
    return result
end

local function itemBodyLocation(item)
    local ok, bodyLocation = pcall(function() return item:getBodyLocation() end)
    return ok and tostring(bodyLocation) or ""
end

local function isBandageItem(item)
    if not item then return false end
    local ok, bodyLocation = pcall(function() return item:getBodyLocation() end)
    if ok and ItemBodyLocation and bodyLocation == ItemBodyLocation.BANDAGE then return true end
    return WLM.isBandageEntry({
        fullType = tostring(item:getFullType()),
        bodyLocation = ok and tostring(bodyLocation) or "",
    })
end

local function profileWeightDelta(player, wardrobe, active, target)
    local activeIds, targetIds = {}, {}
    for _, id in ipairs(WLM.profileItems(active)) do activeIds[id] = true end
    for _, id in ipairs(WLM.profileItems(target)) do targetIds[id] = true end
    local delta = 0
    for id in pairs(activeIds) do
        if not targetIds[id] then delta = delta + WLM.itemWeight(inventoryItem(player, id)) end
    end
    for id in pairs(targetIds) do
        if not activeIds[id] then
            local item = WLM.findItem(wardrobe, id)
            if item then delta = delta - WLM.itemWeight(item) end
        end
    end
    return delta
end

local function setDuration(action, frames)
    frames = math.max(0, tonumber(frames) or 0)
    if action.Type == "ISDetachItemHotbar" then
        if frames <= 1 then
            action.maxTime = 1
            action.animSpeed = 1.0
        else
            action.maxTime = -1
            action.animSpeed = frames / action:adjustMaxTime(frames)
        end
    else
        action.maxTime = frames
        if action.maxTimeInit ~= nil then action.maxTimeInit = frames end
    end
    return action
end

local function countOperations(player, hotbar, active, target, wardrobe)
    local count = 3
    local targetIds = {}
    for _, id in ipairs(WLM.profileItems(target)) do targetIds[id] = true end
    if WLM.settings().includeAttachments and hotbar then
        for _, item in pairs(hotbar.attachedItems or {}) do
            if item and item:getAttachedSlot() >= 0 then
                count = count + 1
            end
        end
    end
    local worn = player:getWornItems()
    for index = 0, worn:size() - 1 do
        local entry = worn:get(index)
        local item = entry and entry:getItem()
        if item and not isBandageItem(item) and not profileHasRole(target, item:getID(), "worn") then count = count + 1 end
    end
    for _, id in ipairs(WLM.profileItems(active)) do
        if not targetIds[id] and inventoryItem(player, id) then count = count + 1 end
    end
    for _, entry in ipairs(target.worn or {}) do
        if WLM.isBandageEntry(entry) then
            local item = WLM.findItem(wardrobe, entry.id) or inventoryItem(player, entry.id)
            if item and not wornItem(player, entry.id) then
                count = count + 1
                local source = item:getContainer()
                if source and source ~= player:getInventory() then count = count + 1 end
            end
        elseif (WLM.settings().includeBags or entry.isBag ~= true) and not wornItem(player, entry.id) then
            count = count + 1
        end
    end
    for _, id in ipairs(WLM.profileItems(target)) do
        if WLM.findItem(wardrobe, id) then count = count + 1 end
    end
    return math.max(1, count)
end

local function addAction(player, action, frameBudget)
    if action.Type == "ISInventoryTransferAction" then
        local isValid = action.isValid
        action.isValid = function(self)
            local valid = isValid(self)
            if not valid and WLM.Options.diagnosticsEnabled() then
                local item, source, destination = self.item, self.srcContainer, self.destContainer
                local ok, details = pcall(function()
                    return string.format("item=%s id=%s inSource=%s removable=%s allowed=%s room=%s weight=%.3f used=%.3f capacity=%s",
                        WLM.nameForItem(item), tostring(item:getID()), tostring(source:contains(item)), tostring(source:isRemoveItemAllowed(item)),
                        tostring(destination:isItemAllowed(item)), tostring(destination:hasRoomFor(player, item)),
                        WLM.itemWeight(item), destination:getCapacityWeight(), tostring(destination:getEffectiveCapacity(player)))
                end)
                WLM.debugLog("[WardrobeLoadouts] transfer rejected " .. (ok and details or tostring(details)))
            end
            return valid
        end
    end
    ISTimedActionQueue.add(setDuration(action, frameBudget))
end

local registeredTidyUpAPI

local function registerTidyUpPolicies()
    local tidyUp = P4TidyUpMeister
    if type(tidyUp) ~= "table" or type(tidyUp.registerActionPolicy) ~= "function"
            or registeredTidyUpAPI == tidyUp then return end
    for _, actionType in ipairs({
        "ISWLMRestoreAttachmentsAction",
        "ISWLMFinalizeSwitchAction",
        "ISWLMFinalizeStoreAction",
        "ISWLMFinalizeRecoveryAction",
    }) do
        tidyUp.registerActionPolicy(actionType, { ignore = true })
    end
    registeredTidyUpAPI = tidyUp
    WLM.debugLog("[WardrobeLoadouts] registered Tidy Up Meister policies: wardrobe actions do not trigger automatic returns")
end

function Client.objectArgs(object)
    return WLM.objectArgs(object)
end

function Client.getData()
    if not Client.object then return nil end
    return WLM.getData(Client.object, false)
end

local function firstStoredProfileItem(player, wardrobe, profile, preferences)
    for _, id in ipairs(WLM.profileItems(profile, preferences)) do
        local item = WLM.findItem(wardrobe, id)
        if item then return item end
    end
end

local function firstStoredBandageItem(player, wardrobe, profile)
    for _, entry in ipairs(profile and profile.worn or {}) do
        if WLM.isBandageEntry(entry) then
            local item = WLM.findItem(wardrobe, entry.id)
            if item then return item end
        end
    end
end

local function clearStoredActiveProfile(player, object, data)
    local activeId = WLM.getActiveId(data, player)
    local profile = activeId and data.sets[tostring(activeId)]
    if not profile then return false end
    local wardrobe = object:getContainer()
    local item = firstStoredProfileItem(player, wardrobe, profile, WLM.getActivePreferences(data, player))
    if item then
        local itemName = WLM.nameForItem(item)
        WLM.debugLog(string.format("[WardrobeLoadouts] active loadout cleared: item still in wardrobe name=%s id=%s",
            itemName, tostring(item:getID())))
        WLM.setActiveId(data, player, nil)
        if object.transmitModData then object:transmitModData() end
        Client.showError(WLM.text("IGUI_WLM_ErrorActiveCleared", "The active loadout was cleared because an item is still in the wardrobe.") .. " (" .. itemName .. ")")
        return true
    end
    return false
end

function Client.request()
    if not Client.object then return end
    if isClient() then
        local args = WLM.objectArgs(Client.object)
        if args then sendClientCommand(getPlayer(Client.playerNum), WLM.ID, "request", args) end
    else
        Client.data = WLM.getData(Client.object, true)
        clearStoredActiveProfile(getPlayer(Client.playerNum), Client.object, Client.data)
        if Client.window then Client.window:refresh() end
    end
end

local function captureProfile(player, name)
    local settings = WLM.settings()
    local profile = { name = tostring(name), worn = {}, attached = {}, hands = {} }
    local worn = player:getWornItems()
    for index = 0, worn:size() - 1 do
        local entry = worn:get(index)
        local item = entry and entry:getItem()
        local isBag = isWearableBag(item)
        if item and not isBandageItem(item) and (settings.includeBags or not isBag) then
            profile.worn[#profile.worn + 1] = {
                id = item:getID(), isBag = isBag,
                fullType = tostring(item:getFullType()), bodyLocation = itemBodyLocation(item),
                name = WLM.nameForItem(item),
            }
        end
    end
    if settings.includeHands then
        local primary, secondary = player:getPrimaryHandItem(), player:getSecondaryHandItem()
        if primary then profile.hands.primary = { id = primary:getID(), name = WLM.nameForItem(primary) } end
        if secondary then profile.hands.secondary = { id = secondary:getID(), name = WLM.nameForItem(secondary) } end
    end
    if settings.includeKeyRing then
        local keyRing = playerKeyRing(player)
        if keyRing then
            profile.keyRing = { id = keyRing:getID(), fullType = tostring(keyRing:getFullType()), name = WLM.nameForItem(keyRing) }
        end
    end
    if settings.includeAttachments then
        local hotbar = getPlayerHotbar(player:getPlayerNum())
        local attached = {}
        for _, item in pairs(hotbar and hotbar.attachedItems or {}) do
            if item and item:getAttachedSlot() >= 0 then
                attached[#attached + 1] = {
                    id = item:getID(), slotType = tostring(item:getAttachedSlotType() or ""),
                    slotIndex = item:getAttachedSlot(), attachmentType = tostring(item:getAttachmentType() or ""),
                    model = tostring(item:getAttachedToModel() or ""), name = WLM.nameForItem(item),
                }
            end
        end
        table.sort(attached, function(left, right) return left.slotIndex < right.slotIndex end)
        profile.attached = attached
    end
    return profile
end

Client.captureProfile = captureProfile

local function storageWeightDelta(player, wardrobe, profile)
    local delta = 0
    for _, id in ipairs(WLM.profileItems(profile)) do
        if not WLM.findItem(wardrobe, id) then
            delta = delta + WLM.itemWeight(inventoryItem(player, id))
        end
    end
    return delta
end

local function enqueueStore(player, profile, wardrobe, pending)
    if ISTimedActionQueue.queues[player] and #ISTimedActionQueue.queues[player].queue > 0 then
        return false, WLM.text("IGUI_WLM_ErrorBusy", "Finish the current action before storing equipment.")
    end
    local hotbar = getPlayerHotbar(player:getPlayerNum())
    if WLM.settings().includeAttachments and #((profile and profile.attached) or {}) > 0 and not hotbar then
        return false, WLM.text("IGUI_WLM_ErrorHotbar", "The hotbar is not ready yet.")
    end

    local items = {}
    for _, id in ipairs(WLM.profileItems(profile)) do
        if not WLM.findItem(wardrobe, id) then
            local item = inventoryItem(player, id)
            if not item then
                return false, WLM.text("IGUI_WLM_ErrorMissingInventory", "A saved item is no longer in this character's inventory.")
            end
            items[#items + 1] = item
        end
    end
    local transfers = WLM.planStorage(wardrobe, player, items)
    if not transfers then
        return false, WLM.text("IGUI_WLM_ErrorCapacity", "The wardrobe needs more free capacity before storing this equipment.")
    end

    pending.recovery = { profile = captureProfile(player, profile.name), items = {}, player = player }
    for _, item in ipairs(items) do
        pending.recovery.items[#pending.recovery.items + 1] = { item = item }
    end

    beginCarry(player, wardrobe, pending)

    registerTidyUpPolicies()

    temporarilyUnfavorite(player, wardrobe, { profile }, pending)
    local itemIds = WLM.profileItems(profile)
    local attachedToRemove = {}
    if WLM.settings().includeAttachments and hotbar then
        for _, entry in ipairs(profile.attached or {}) do
            local item = inventoryItem(player, entry.id)
            if item and item:getAttachedSlot() >= 0 then attachedToRemove[#attachedToRemove + 1] = item end
        end
    end
    table.sort(attachedToRemove, function(left, right) return left:getAttachedSlot() < right:getAttachedSlot() end)

    local operations = 1 + #itemIds + #attachedToRemove
    for _, entry in ipairs(profile.worn or {}) do
        if wornItem(player, entry.id) then operations = operations + 1 end
    end
    local hands = profile.hands or {}
    if hands.primary and player:getPrimaryHandItem() and tonumber(player:getPrimaryHandItem():getID()) == tonumber(hands.primary.id) then operations = operations + 1 end
    if hands.secondary and player:getSecondaryHandItem() and tonumber(player:getSecondaryHandItem():getID()) == tonumber(hands.secondary.id)
            and (not hands.primary or tonumber(hands.primary.id) ~= tonumber(hands.secondary.id)) then operations = operations + 1 end
    local perAction = math.max(1, math.floor(WLM.settings().switchDuration * 30 / math.max(1, operations)))

    for _, item in ipairs(attachedToRemove) do
        if perAction <= 1 then
            hotbar:removeItem(item, false)
            syncItemState(player, item)
        else
            hotbar:setAttachAnim(item)
            addAction(player, ISDetachItemHotbar:new(player, item), perAction)
        end
    end
    if hotbar and hotbar.AliceWeaponSling_LastSwapItRemovedItem ~= nil then
        hotbar.AliceWeaponSling_LastSwapItRemovedItem = nil
    end

    local queuedUnequip = {}
    local function unequip(item)
        if item and not queuedUnequip[item:getID()] then
            queuedUnequip[item:getID()] = true
            addAction(player, ISUnequipAction:new(player, item, perAction, "place"), perAction)
        end
    end
    for _, transfer in ipairs(transfers) do
        local item = transfer.item
        local source = item:getContainer() or player:getInventory()
        if wornItem(player, item:getID()) or player:getPrimaryHandItem() == item or player:getSecondaryHandItem() == item then
            unequip(item)
        end
        addAction(player, ISInventoryTransferUtil.newInventoryTransferAction(player, item, source, transfer.destination, perAction), perAction)
    end

    ISTimedActionQueue.add(ISWLMFinalizeStoreAction:new(player, true, nil))
    return true
end

function Client.saveProfile(profile, updateId)
    if not Client.object or not profile then return end
    if type(profile.name) ~= "string" or #profile.name > 64 then
        Client.showError(WLM.text("IGUI_WLM_ErrorNameLength", "Loadout names must be 64 bytes or fewer."))
        return false
    end
    if Client.pendingStore or Client.pendingStoreRequest or Client.pendingSwitch or Client.switchPendingRequest then
        Client.showError(WLM.text("IGUI_WLM_ErrorBusy", "Finish the current action before storing equipment."))
        return false
    end
    local args = WLM.objectArgs(Client.object)
    if not args then return end
    args.profile = profile
    args.updateId = updateId and tostring(updateId) or nil
    local player = getPlayer(Client.playerNum)
    local wardrobe = Client.object:getContainer()
    local data = Client.data or WLM.getData(Client.object, true)
    if data.lock and (data.lockUntil or 0) > getTimestamp() and data.lock ~= player:getOnlineID() then
        Client.showError(WLM.text("IGUI_WLM_ErrorLocked", "Another player is using this wardrobe."))
        return false
    end
    if updateId and (not data.sets[tostring(updateId)] or WLM.getActiveId(data, player) ~= tostring(updateId)) then
        Client.showError(WLM.text("IGUI_WLM_ErrorUpdateActive", "Only the active loadout can be updated."))
        return false
    end
    if updateId then
        WLM.preserveUnselectedCategories(profile, data.sets[tostring(updateId)], WLM.clientPreferences())
    end
    if not updateId and profile.slot and not WLM.slotAvailable(data, profile.slot, Client.object:getContainer()) then
        Client.showError(WLM.text("IGUI_WLM_ErrorSlotOccupied", "This slot is no longer empty. Refresh the wardrobe."))
        return false
    end
    if #WLM.profileItems(profile) == 0 then
        Client.showError(WLM.text("IGUI_WLM_ErrorNoEquipment", "There is no equipment to store."))
        return false
    end
    if not updateId and WLM.countSets(data) >= WLM.slotLimit(Client.object:getContainer()) then
        Client.showError(WLM.text("IGUI_WLM_ErrorLimit", "This wardrobe has reached its loadout limit."))
        return false
    end
    for _, id in ipairs(WLM.profileItems(profile)) do
        if not inventoryItem(player, id) then
            Client.showError(WLM.text("IGUI_WLM_ErrorMissingInventory", "A saved item is no longer in this character's inventory."))
            return false
        end
    end
    WLM.capacity(wardrobe)
    if WLM.storageWeight(wardrobe) + storageWeightDelta(player, wardrobe, profile) > WLM.capacityLimit(wardrobe) then
        Client.showError(WLM.text("IGUI_WLM_ErrorCapacity", "The wardrobe needs more free capacity before storing this equipment."))
        return false
    end

    if isClient() then
        Client.storeObjectArgs = WLM.objectArgs(Client.object)
        Client.pendingStore = { profile = profile, updateId = args.updateId, phase = "request", deadline = getTimestamp() + 90, object = Client.object, objectArgs = Client.storeObjectArgs }
        Client.pendingStoreRequest = true
        sendClientCommand(player, WLM.ID, "beginStore", args)
        if Client.window then Client.window:setMessage(WLM.text("IGUI_WLM_Storing", "Storing equipment in wardrobe..."), false); Client.window:refresh() end
        return true
    end
    Client.storeObjectArgs = args
    Client.pendingStore = { profile = profile, updateId = args.updateId, phase = "actions", object = Client.object, objectArgs = WLM.objectArgs(Client.object) }
    local ok, message = enqueueStore(player, profile, wardrobe, Client.pendingStore)
    if not ok then
        Client.pendingStore = nil
        Client.showError(message)
        return false
    end
    data.lock = player:getOnlineID()
    data.lockUntil = getTimestamp() + 90
    Client.data = data
    if Client.window then Client.window:setMessage(WLM.text("IGUI_WLM_Storing", "Storing equipment in wardrobe..."), false); Client.window:refresh() end
    return true
end

function Client.renameProfile(setId, value, slot)
    if not Client.object then return false end
    if Client.pendingStore or Client.pendingStoreRequest or Client.pendingSwitch or Client.switchPendingRequest then return false end
    local name = tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if #name == 0 or #name > 64 then
        Client.showError(WLM.text("IGUI_WLM_ErrorNameLength", "Loadout names must be 1 to 64 bytes long."))
        return false
    end
    local data = Client.data or WLM.getData(Client.object, false)
    local profile = data and data.sets[tostring(setId)]
    slot = tonumber(slot) or (profile and profile.slot)
    local _, slotCount = WLM.slots(data, Client.object:getContainer())
    if not data or not slot or slot < 1 or slot ~= math.floor(slot) or slot > slotCount then return false end
    if data.lock and (data.lockUntil or 0) > getTimestamp() then
        Client.showError(WLM.text("IGUI_WLM_ErrorLocked", "Another player is using this wardrobe."))
        return false
    end
    local args = WLM.objectArgs(Client.object)
    if not args then return false end
    args.setId, args.name, args.slot = setId and tostring(setId), name, slot
    if isClient() then
        sendClientCommand(getPlayer(Client.playerNum), WLM.ID, "rename", args)
    else
        WLM.setSlotName(data, slot, name, Client.object:getContainer())
        if Client.object.transmitModData then Client.object:transmitModData() end
        if Client.window then Client.window:refresh() end
    end
    return true
end

function Client.setSlotIcon(slot, icon)
    if not Client.object or Client.pendingStore or Client.pendingSwitch or Client.pendingStoreRequest or Client.switchPendingRequest then return false end
    local data = Client.data or WLM.getData(Client.object, false)
    slot = tonumber(slot)
    local _, count = WLM.slots(data, Client.object:getContainer())
    if not data or not slot or slot < 1 or slot ~= math.floor(slot) or slot > count then return false end
    if type(icon) ~= "string" or #icon > 250 or icon:find("..", 1, true) or icon:find("[\r\n]") then return false end
    if data.lock and (data.lockUntil or 0) > getTimestamp() then return false end
    if icon ~= "" and not getTexture(icon) then
        Client.showError(WLM.text("IGUI_WLM_ErrorIcon", "This texture could not be loaded."))
        return false
    end
    local args = WLM.objectArgs(Client.object)
    if not args then return false end
    args.slot, args.icon = slot, icon
    if isClient() then sendClientCommand(getPlayer(Client.playerNum), WLM.ID, "icon", args)
    else
        data.slotIcons = data.slotIcons or {}
        data.slotIcons[tostring(slot)] = icon ~= "" and icon or nil
        if Client.object.transmitModData then Client.object:transmitModData() end
        if Client.window then Client.window:refresh() end
    end
    return true
end

function Client.deleteProfile(setId)
    if not Client.object or not setId then return end
    if Client.pendingStore or Client.pendingStoreRequest or Client.pendingSwitch or Client.switchPendingRequest then return end
    local args = WLM.objectArgs(Client.object)
    if not args then return end
    args.setId = tostring(setId)
    if isClient() then
        sendClientCommand(getPlayer(Client.playerNum), WLM.ID, "delete", args)
        return
    end
    local data = WLM.getData(Client.object, false)
    if not data then return end
    if WLM.isSetActive(data, setId) then
        Client.showError(WLM.text("IGUI_WLM_ErrorSetActive", "Save another loadout before deleting the active one."))
        return
    end
    data.sets[tostring(setId)] = nil
    if Client.object.transmitModData then Client.object:transmitModData() end
    if Client.window then Client.window:refresh() end
end

local function targetIsEquipped(player, profile)
    for _, entry in ipairs(profile.worn or {}) do
        if not WLM.isBandageEntry(entry) and (WLM.settings().includeBags or entry.isBag ~= true) and not wornItem(player, entry.id) then
            return false, entry.name or entry.fullType or tostring(entry.id)
        end
    end
    local hands = profile.hands or {}
    if WLM.settings().includeHands then
        if hands.primary and (not player:getPrimaryHandItem() or tonumber(player:getPrimaryHandItem():getID()) ~= tonumber(hands.primary.id)) then
            return false, hands.primary.name or tostring(hands.primary.id)
        end
        if hands.secondary and (not player:getSecondaryHandItem() or tonumber(player:getSecondaryHandItem():getID()) ~= tonumber(hands.secondary.id)) then
            return false, hands.secondary.name or tostring(hands.secondary.id)
        end
    end
    if WLM.settings().includeAttachments then
        for _, entry in ipairs(profile.attached or {}) do
            local item = inventoryItem(player, entry.id)
            local slotIndex = item and tonumber(item:getAttachedSlot())
            if not item or not slotIndex or slotIndex < 0
                    or tostring(item:getAttachedSlotType()) ~= tostring(entry.slotType) then
                return false, entry.name or tostring(entry.id)
            end
        end
    end
    if WLM.settings().includeKeyRing and profile.keyRing then
        local keyRing = inventoryItem(player, profile.keyRing.id)
        if not isKeyRing(keyRing) then return false, profile.keyRing.name or "Key ring" end
    end
    return true
end

local function currentWorn(player)
    local found = {}
    local worn = player:getWornItems()
    for index = 0, worn:size() - 1 do
        local entry = worn:get(index)
        local item = entry and entry:getItem()
        if item then found[#found + 1] = { item = item } end
    end
    return found
end

local function enqueueSwitch(player, active, target, wardrobe, preferences, merge)
    if ISTimedActionQueue.queues[player] and #ISTimedActionQueue.queues[player].queue > 0 then
        return false, WLM.text("IGUI_WLM_ErrorBusy", "Finish the current action before switching loadouts.")
    end
    local hotbar = getPlayerHotbar(player:getPlayerNum())
    if WLM.settings().includeAttachments and not hotbar then return false, WLM.text("IGUI_WLM_ErrorHotbar", "The hotbar is not ready yet.") end

    registerTidyUpPolicies()

    local durationFrames = WLM.settings().switchDuration * 30
    local operations = countOperations(player, hotbar, active, target, wardrobe)
    local perAction = math.max(1, math.floor(durationFrames / operations))
    local pending = {
        targetId = tostring(target.id),
        profile = target,
        activeProfile = active,
        failed = false,
        phase = "equipping",
        perAction = perAction,
        wardrobe = wardrobe,
        object = Client.object,
        preferences = preferences or WLM.clientPreferences(),
        merge = merge == true,
    }
    pending.recovery = { kind = "switch", player = player, profile = captureProfile(player, "previous"), items = {}, returnItems = {} }
    local originalIds = {}
    for _, profile in ipairs({ pending.recovery.profile, active or {} }) do
        for _, id in ipairs(WLM.profileItems(profile)) do
            local item = inventoryItem(player, id)
            if item and not originalIds[id] then
                originalIds[id] = true
                pending.recovery.items[#pending.recovery.items + 1] = { item = item }
            end
        end
    end
    for _, id in ipairs(WLM.profileItems(target)) do
        local item = WLM.findItem(wardrobe, id)
        if item then pending.recovery.returnItems[#pending.recovery.returnItems + 1] = { item = item, container = item:getContainer() } end
    end
    Client.pendingSwitch = pending
    Client.switchWatch = nil
    beginCarry(player, wardrobe, pending)
    if type(print) == "function" then
        WLM.debugLog(string.format("[WardrobeLoadouts] switch begin active=%s target=%s activeItems=%d targetItems=%d",
            active and tostring(active.id) or "none", tostring(target.id),
            #WLM.profileItems(active), #WLM.profileItems(target)))
    end
    local profiles = {}
    if active then profiles[#profiles + 1] = active end
    profiles[#profiles + 1] = target
    temporarilyUnfavorite(player, wardrobe, profiles, pending)

    local attachedToRemove = {}
    if not merge and WLM.settings().includeAttachments and hotbar then
        for _, item in pairs(hotbar.attachedItems or {}) do
            if item and item:getAttachedSlot() >= 0 then
                attachedToRemove[#attachedToRemove + 1] = item
            end
        end
    end
    table.sort(attachedToRemove, function(left, right) return left:getAttachedSlot() < right:getAttachedSlot() end)
    for _, item in ipairs(attachedToRemove) do
        if perAction <= 1 then
            hotbar:removeItem(item, false)
            syncItemState(player, item)
        else
            hotbar:setAttachAnim(item)
            addAction(player, ISDetachItemHotbar:new(player, item), perAction)
        end
    end
    if hotbar and hotbar.AliceWeaponSling_LastSwapItRemovedItem ~= nil then
        hotbar.AliceWeaponSling_LastSwapItRemovedItem = nil
    end

    local currentlyWorn = currentWorn(player)
    for _, entry in ipairs(currentlyWorn) do
        if not merge and not isBandageItem(entry.item) and not (not WLM.settings().includeBags and isWearableBag(entry.item))
                and not profileHasRole(target, entry.item:getID(), "worn") then
            addAction(player, ISUnequipAction:new(player, entry.item, perAction, "place"), perAction)
        end
    end

    local queuedUnequip = {}
    local function unequipHand(item, role)
        if item and not queuedUnequip[item:getID()] and not profileHasRole(target, item:getID(), role) then
            queuedUnequip[item:getID()] = true
            addAction(player, ISUnequipAction:new(player, item, perAction, "place"), perAction)
        end
    end
    if not merge and WLM.settings().includeHands then
        unequipHand(player:getPrimaryHandItem(), "hand:primary")
        unequipHand(player:getSecondaryHandItem(), "hand:secondary")
    end

    local activeIds = {}
    for _, id in ipairs(WLM.profileItems(active)) do activeIds[id] = true end
    local retrieved = {}
    local function retrieve(id)
        if not activeIds[id] and not retrieved[id] then
            retrieved[id] = true
            local item = inventoryItem(player, id) or WLM.findItem(wardrobe, id)
            local source = item and item:getContainer()
            if item and source and source ~= player:getInventory() then
                local action = ISInventoryTransferUtil.newInventoryTransferAction(player, item, source, player:getInventory(), perAction)
                addAction(player, action, perAction)
            end
        end
    end
    for _, entry in ipairs(target.worn or {}) do
        retrieve(entry.id)
        if WLM.isBandageEntry(entry) then
            local item = WLM.findItem(wardrobe, entry.id) or inventoryItem(player, entry.id)
            if item and not wornItem(player, entry.id) then
                addAction(player, ISWearClothing:new(player, item), perAction)
            end
        elseif (WLM.settings().includeBags or entry.isBag ~= true) and not wornItem(player, entry.id) then
            local item = WLM.findItem(wardrobe, entry.id) or inventoryItem(player, entry.id)
            if item then
                local action = ISWearClothing:new(player, item)
                addAction(player, action, perAction)
            end
        end
    end

    local hands = target.hands or {}
    if WLM.settings().includeHands then
        if hands.primary then retrieve(hands.primary.id) end
        if hands.primary and (not player:getPrimaryHandItem() or tonumber(player:getPrimaryHandItem():getID()) ~= tonumber(hands.primary.id)) then
            local item = WLM.findItem(wardrobe, hands.primary.id) or inventoryItem(player, hands.primary.id)
            if item then
                local bothHands = hands.secondary and tonumber(hands.secondary.id) == tonumber(hands.primary.id)
                pcall(function() bothHands = bothHands or item:isRequiresEquippedBothHands() end)
                addAction(player, ISEquipWeaponAction:new(player, item, perAction, true, bothHands), perAction)
            end
        end
        if hands.secondary and (not player:getSecondaryHandItem() or tonumber(player:getSecondaryHandItem():getID()) ~= tonumber(hands.secondary.id))
                and (not hands.primary or tonumber(hands.primary.id) ~= tonumber(hands.secondary.id)) then
            local item = WLM.findItem(wardrobe, hands.secondary.id) or inventoryItem(player, hands.secondary.id)
            retrieve(hands.secondary.id)
            if item then addAction(player, ISEquipWeaponAction:new(player, item, perAction, false, false), perAction) end
        end
    end

    for _, id in ipairs(WLM.profileItems(target)) do retrieve(id) end
    if WLM.settings().includeAttachments then
        addAction(player, ISWLMRestoreAttachmentsAction:new(player, target.attached or {}, perAction), perAction)
    end
    ISTimedActionQueue.add(ISWLMFinalizeSwitchAction:new(player, true, nil))
    return true
end

local function enqueueReplacedItems(player, pending)
    local targetIds = {}
    for _, id in ipairs(WLM.profileItems(pending.profile)) do targetIds[id] = true end
    local items = {}
    for _, id in ipairs(WLM.profileItems(pending.activeProfile)) do
        if not targetIds[id] then
            local item = inventoryItem(player, id)
            if item and not WLM.findItem(pending.wardrobe, id) then items[#items + 1] = item end
        end
    end
    local transfers = WLM.planStorage(pending.wardrobe, player, items)
    if not transfers then return nil end
    local operations = #transfers
    for _, transfer in ipairs(transfers) do
        local item = transfer.item
        local action = ISInventoryTransferUtil.newInventoryTransferAction(
            player, item, item:getContainer() or player:getInventory(), transfer.destination, pending.perAction)
        addAction(player, action, pending.perAction)
    end
    if type(print) == "function" then
        WLM.debugLog(string.format("[WardrobeLoadouts] switch replaced-items queued=%d target=%s",
            operations, tostring(pending.targetId)))
    end
    return operations
end

function Client.beginSwitch(targetId, slotAction, swap, merge)
    merge = merge == true
    if merge then slotAction, swap = true, false end
    if not Client.object then return end
    if Client.switchPendingRequest or Client.pendingSwitch or Client.pendingStoreRequest or Client.pendingStore then return end
    local player = getPlayer(Client.playerNum)
    if not player then return end
    if player:getVehicle() then
        Client.showError(WLM.text("IGUI_WLM_ErrorVehicle", "Exit the vehicle before changing loadouts."))
        return
    end
    local data = Client.data or WLM.getData(Client.object, false)
    local activeId = data and tostring(WLM.getActiveId(data, player) or "") or ""
    local target = data and data.sets[tostring(targetId)]
    local active = activeId ~= "" and data and data.sets[activeId] or nil
    if not target or activeId == tostring(targetId) or (activeId ~= "" and not active) then return end
    if data.lock and (data.lockUntil or 0) > getTimestamp() and data.lock ~= player:getOnlineID() then
        Client.showError(WLM.text("IGUI_WLM_ErrorLocked", "Another player is using this wardrobe."))
        return
    end
    local args = WLM.objectArgs(Client.object)
    if not args then return end
    local preferences = WLM.clientPreferences()
    args.preferences = preferences
    args.activeId = activeId
    args.targetId = tostring(targetId)
    args.merge = merge
    if slotAction and WLM.isSetActive(data, targetId) then
        Client.showError(WLM.text("IGUI_WLM_ErrorSetActive", "This equipment is currently being used by a player."))
        return
    end
    if slotAction then
        local slots = WLM.slots(data, Client.object:getContainer())
        local slot
        for index, entry in pairs(slots) do if entry.id == tostring(targetId) then slot = index; break end end
        active = swap and captureProfile(player, target.name) or { name = target.name, worn = {}, attached = {}, hands = {} }
        local targetIds = {}
        for _, id in ipairs(WLM.profileItems(target)) do targetIds[id] = true end
        for _, entries in ipairs({ active.worn, active.attached }) do
            for index = #entries, 1, -1 do
                if targetIds[tonumber(entries[index].id)] then table.remove(entries, index) end
            end
        end
        for hand, entry in pairs(active.hands) do
            if entry and targetIds[tonumber(entry.id)] then active.hands[hand] = nil end
        end
        if active.keyRing and targetIds[tonumber(active.keyRing.id)] then active.keyRing = nil end
        active.slot = slot
        args.slotAction = true
        args.swapProfile = active
    end
    if isClient() then
        Client.switchPendingRequest = true
        if Client.window then Client.window.applyButton:setEnable(false) end
        sendClientCommand(player, WLM.ID, "beginSwitch", args)
        return
    end
    local container = Client.object:getContainer()
    WLM.capacity(container)
    if active then
        for _, id in ipairs(WLM.profileItems(active)) do
            if not inventoryItem(player, id) then Client.showError(WLM.text("IGUI_WLM_ErrorActiveIncomplete", "The active loadout is incomplete. Update it before switching.")); return end
        end
    end
    for _, id in ipairs(WLM.profileItems(target)) do
        if not inventoryItem(player, id) and not WLM.findItem(container, id) then Client.showError(WLM.text("IGUI_WLM_ErrorMissingPiece", "A piece from the selected loadout is missing.")); return end
    end
    if WLM.storageWeight(container) + profileWeightDelta(player, container, active, target) > WLM.capacityLimit(container) then
        Client.showError(WLM.text("IGUI_WLM_ErrorCapacity", "The wardrobe needs more free capacity for this switch."))
        return
    end
    local ok, message = enqueueSwitch(player, active, target, container, preferences, merge)
    if not ok then Client.showError(message); return end
    Client.switchObjectArgs = args
    Client.pendingSwitch.slotAction = slotAction == true
    if Client.window then Client.window.applyButton:setEnable(false) end
end

function Client.restoreAttachments(player, entries, operation)
    operation = operation or Client.pendingSwitch
    if not operation then return end
    local hotbar = getPlayerHotbar(player:getPlayerNum())
    if not hotbar then operation.failed = true; return end
    hotbar:reloadIcons()
    hotbar.wornItems = nil
    hotbar:refresh()
    local previous = hotbar.availableSlot or {}
    local ordered = not operation.merge and WLM.orderAttachmentSlots(previous, entries)
    if ordered then
        for index, item in pairs(hotbar.attachedItems or {}) do
            for newIndex, slot in ipairs(ordered) do
                if previous[index] == slot then item:setAttachedSlot(newIndex); break end
            end
        end
        hotbar.availableSlot = ordered
        hotbar:reloadIcons()
        hotbar:savePosition()
    end
    local function reportFailure(entry, item, reason)
        if not WLM.Options.diagnosticsEnabled() then return end
        local slots = {}
        for index, slot in pairs(hotbar.availableSlot or {}) do
            slots[#slots + 1] = tostring(index) .. ":" .. tostring(slot.slotType)
        end
        table.sort(slots)
        local itemType = item and item:getAttachmentType() or entry.attachmentType or ""
        WLM.debugLog(string.format("[WardrobeLoadouts] attachment restore failed item=%s id=%s type=%s expectedSlot=%s index=%s reason=%s available=%s",
            tostring(entry.name or "unknown"), tostring(entry.id), tostring(itemType),
            tostring(entry.slotType), tostring(entry.slotIndex), reason, table.concat(slots, ",")))
    end
    for _, entry in ipairs(entries or {}) do
        local item = inventoryItem(player, entry.id)
        local preferred = tonumber(entry.slotIndex)
        local attachmentType = item and item:getAttachmentType()
        if not attachmentType or attachmentType == "" then attachmentType = entry.attachmentType end
        local chosenIndex, chosenSlot
        local function modelFor(slot)
            local attachments = slot and slot.def and slot.def.attachments
            local model = attachments and attachments[attachmentType]
            if model == nil and tostring(attachmentType or "") == tostring(entry.attachmentType or "")
                    and entry.model and entry.model ~= "" and entry.model ~= "null" then
                model = entry.model
            end
            return model
        end
        local function accepts(index, slot)
            return slot and slot.def and slot.def.attachments
                and modelFor(slot) ~= nil and modelFor(slot) ~= "null"
                and tostring(slot.slotType) == tostring(entry.slotType)
        end
        if item and preferred and accepts(preferred, hotbar.availableSlot[preferred]) then
            chosenIndex, chosenSlot = preferred, hotbar.availableSlot[preferred]
        elseif item then
            local indexes = {}
            for index in pairs(hotbar.availableSlot or {}) do indexes[#indexes + 1] = index end
            table.sort(indexes)
            for _, index in ipairs(indexes) do
                local slot = hotbar.availableSlot[index]
                if accepts(index, slot) then chosenIndex, chosenSlot = index, slot; break end
            end
        end
        if item and chosenSlot then
            local model = modelFor(chosenSlot)
            if chosenSlot.name == "Back" and hotbar.replacements and hotbar.replacements[attachmentType] then
                model = hotbar.replacements[attachmentType]
            end
            if model ~= "null" then
                if operation.merge then
                    local replaced = hotbar.attachedItems[chosenIndex]
                    if replaced and replaced ~= item then
                        hotbar:removeItem(replaced, false)
                        syncItemState(player, replaced)
                    end
                    if item:getAttachedSlot() >= 0 and item:getAttachedSlot() ~= chosenIndex then
                        hotbar:removeItem(item, false)
                    end
                end
                hotbar:attachItem(item, model or entry.model, chosenIndex, chosenSlot.def, false)
                syncItemState(player, item)
            else
                operation.failed = true
                reportFailure(entry, item, "unsupportedModel")
            end
        else
            operation.failed = true
            reportFailure(entry, item, item and "slotNotFound" or "itemNotInInventory")
        end
    end
    hotbar:reloadIcons()
    if hotbar.AliceWeaponSling_LastSwapItRemovedItem ~= nil then
        hotbar.AliceWeaponSling_LastSwapItRemovedItem = nil
    end
end

function Client.finishSwitch(success, message)
    local pending = Client.pendingSwitch
    if not pending then return end
    if pending.phase == "server" then return end
    local player = getPlayer(Client.playerNum)
    local equipped, missingItem = targetIsEquipped(player, pending.profile)
    local storedItem = success and firstStoredProfileItem(player, pending.wardrobe, pending.profile) or nil
    local storedBandage = success and firstStoredBandageItem(player, pending.wardrobe, pending.profile) or nil
    if success and pending.phase ~= "committed" and (pending.failed or not equipped or storedItem or storedBandage) then
        success = false
        message = WLM.text("IGUI_WLM_ErrorSwitchIncomplete", "Some equipment could not be restored. The items remain in the wardrobe or inventory.")
        if storedItem or storedBandage then missingItem = WLM.nameForItem(storedItem or storedBandage) end
        if missingItem then message = message .. " (" .. tostring(missingItem) .. ")" end
    end
    if success and pending.phase == "equipping" then
        pending.phase = "storing"
        if enqueueReplacedItems(player, pending) ~= nil then
            ISTimedActionQueue.add(ISWLMFinalizeSwitchAction:new(player, true, nil))
            return
        end
        success = false
        message = WLM.text("IGUI_WLM_ErrorCapacity", "The wardrobe needs more free capacity for this switch.")
    end
    if success and pending.slotAction then
        local targetIds = {}
        for _, id in ipairs(WLM.profileItems(pending.profile)) do targetIds[id] = true end
        for _, id in ipairs(WLM.profileItems(pending.activeProfile)) do
            if not targetIds[id] and not WLM.findItem(pending.wardrobe, id) then
                success = false
                message = WLM.text("IGUI_WLM_ErrorStoreIncomplete", "Some items could not be moved into the wardrobe; the loadout was not saved.")
                local item = inventoryItem(player, id)
                message = message .. " (" .. (item and WLM.nameForItem(item) or tostring(id)) .. ")"
                break
            end
        end
    end
    if not success and Client.recoverSwitch(pending, message) then return end
    if success and isClient() and pending.phase ~= "committed" then
        WLM.CarryGuard.release(pending.carryToken)
        pending.phase = "server"
        local args = Client.switchObjectArgs or WLM.objectArgs(pending.object)
        args.targetId = pending.targetId
        sendClientCommand(player, WLM.ID, "finishSwitch", args)
        return
    end
    restoreFavorites(pending, player, pending.wardrobe)
    logOperation("switch", success, pending.profile, success and nil or message)
    if success and WLM.Options.diagnosticsEnabled() then
        Client.switchWatch = {
            profile = pending.profile,
            wardrobe = pending.wardrobe,
            targetId = pending.targetId,
            nextCheck = getTimestamp() + 1,
            expires = getTimestamp() + 20,
            returned = 0,
            seen = {},
        }
    end
    local targetId = pending.targetId
    WLM.CarryGuard.release(pending.carryToken)
    Client.pendingSwitch = nil
    if isClient() and pending.phase ~= "committed" then
        local args = Client.switchObjectArgs or WLM.objectArgs(Client.object)
        args.targetId = targetId
        sendClientCommand(player, WLM.ID, success and "finishSwitch" or "abortSwitch", args)
    elseif not isClient() then
        local data = WLM.getData(Client.object, false)
        if data then
            data.lock, data.lockUntil = nil, nil
            if success then
                if pending.slotAction then WLM.completeSlotSwitch(data, player, targetId, pending.activeProfile, pending.preferences)
                else WLM.setActiveId(data, player, targetId, pending.preferences) end
            end
        end
        if Client.object and Client.object.transmitModData then Client.object:transmitModData() end
        if Client.window then Client.window:refresh() end
    end
    if success then notify(WLM.text("IGUI_WLM_SwitchComplete", "Loadout equipped.")) else Client.showError(message or WLM.text("IGUI_WLM_ErrorCancelled", "Loadout switch cancelled.")) end
end

local function saveStoredProfile(player, pending)
    local object = pending.object
    local data = WLM.getData(object, true)
    local updateId = pending.updateId and tostring(pending.updateId) or nil
    if updateId and (not data.sets[updateId] or WLM.getActiveId(data, player) ~= updateId) then
        return false, WLM.text("IGUI_WLM_ErrorUpdateActive", "Only the active loadout can be updated.")
    end
    if not updateId and WLM.countSets(data) >= WLM.slotLimit(object:getContainer()) then
        return false, WLM.text("IGUI_WLM_ErrorLimit", "This wardrobe has reached its loadout limit.")
    end
    for _, id in ipairs(WLM.profileItems(pending.profile)) do
        if not WLM.findItem(object:getContainer(), id) then
            return false, WLM.text("IGUI_WLM_ErrorStoreIncomplete", "Some items could not be moved into the wardrobe; the loadout was not saved.")
        end
    end
    if not updateId and pending.profile.slot and not WLM.slotAvailable(data, pending.profile.slot, object:getContainer()) then
        return false, WLM.text("IGUI_WLM_ErrorSlotOccupied", "This slot is no longer empty. Refresh the wardrobe.")
    end
    local id = updateId or tostring(data.nextId)
    if not updateId then data.nextId = data.nextId + 1 end
    pending.profile.id = id
    pending.profile.savedAt = getTimestamp()
    local previousActiveId = WLM.getActiveId(data, player)
    if pending.profile.slot and previousActiveId and tostring(previousActiveId) ~= id then
        data.sets[tostring(previousActiveId)] = nil
    end
    data.sets[id] = pending.profile
    WLM.setActiveId(data, player, nil)
    data.lock, data.lockUntil = nil, nil
    if object.transmitModData then object:transmitModData() end
    if Client.object == object then Client.data = data end
    logOperation("store", true, pending.profile)
    return true
end

function Client.recoverSwitch(pending, message)
    if not pending or pending.phase == "recovering" then return false end
    WLM.debugLog("[WardrobeLoadouts] switch rollback phase=" .. tostring(pending.phase) .. " target=" .. tostring(pending.targetId))
    logOperation("switch", false, pending.profile, message)
    pending.objectArgs = Client.switchObjectArgs or WLM.objectArgs(pending.object)
    Client.pendingSwitch = nil
    Client.pendingStore = pending
    return Client.recoverStore(pending, message)
end

function Client.recoverStore(pending, message)
    if not pending or not pending.recovery or pending.phase == "recovering" then return false end
    local recovery = pending.recovery
    local player, profile = recovery.player, recovery.profile
    if not pending.carryToken or pending.carryToken.released then beginCarry(player, pending.object:getContainer(), pending) end
    pending.phase = "recovering"
    recovery.message = message
    Client.pendingStoreRequest = false
    local wardrobe = pending.object and pending.object:getContainer()
    temporarilyUnfavorite(player, wardrobe, { profile }, pending)
    local hotbar = getPlayerHotbar and getPlayerHotbar(player:getPlayerNum())
    local unequipped = {}
    local function removeIncoming(item)
        if not item or unequipped[item:getID()] then return end
        unequipped[item:getID()] = true
        if hotbar and item:getAttachedSlot() >= 0 then
            hotbar:removeItem(item, false)
            syncItemState(player, item)
        end
        if wornItem(player, item:getID()) or player:getPrimaryHandItem() == item or player:getSecondaryHandItem() == item then
            addAction(player, ISUnequipAction:new(player, item, 1, "place"), 1)
        end
    end
    for _, entry in ipairs(recovery.returnItems or {}) do removeIncoming(entry.item) end
    if recovery.kind == "switch" then
        for _, entry in ipairs(currentWorn(player)) do
            if not isBandageItem(entry.item) and (WLM.settings().includeBags or not isWearableBag(entry.item))
                    and not profileHasRole(profile, entry.item:getID(), "worn") then removeIncoming(entry.item) end
        end
        if WLM.settings().includeHands then
            local hands = profile.hands or {}
            local primary, secondary = player:getPrimaryHandItem(), player:getSecondaryHandItem()
            if primary and (not hands.primary or tonumber(primary:getID()) ~= tonumber(hands.primary.id)) then removeIncoming(primary) end
            if secondary and (not hands.secondary or tonumber(secondary:getID()) ~= tonumber(hands.secondary.id)) then removeIncoming(secondary) end
        end
    end
    local queued = {}
    local function retrieve(id)
        if not id then return end
        if queued[id] then return queued[id] end
        for _, entry in ipairs(recovery.items) do
            if tonumber(entry.item:getID()) == tonumber(id) then
                queued[id] = entry.item
                local source = entry.item:getContainer()
                if source and source ~= player:getInventory() then
                    addAction(player, ISInventoryTransferUtil.newInventoryTransferAction(player, entry.item, source, player:getInventory(), 1), 1)
                end
                return entry.item
            end
        end
    end
    for _, entry in ipairs(profile.worn or {}) do
        local item = retrieve(entry.id)
        if item and not wornItem(player, entry.id) then addAction(player, ISWearClothing:new(player, item), 1) end
    end
    local hands = profile.hands or {}
    local primary = hands.primary and retrieve(hands.primary.id)
    local secondary = hands.secondary and retrieve(hands.secondary.id)
    local bothHands = hands.primary and hands.secondary and tonumber(hands.primary.id) == tonumber(hands.secondary.id)
    if primary then addAction(player, ISEquipWeaponAction:new(player, primary, 1, true, bothHands), 1) end
    if secondary and not bothHands then addAction(player, ISEquipWeaponAction:new(player, secondary, 1, false, false), 1) end
    for _, entry in ipairs(recovery.items) do retrieve(entry.item:getID()) end
    for _, entry in ipairs(recovery.returnItems or {}) do
        local source = entry.item:getContainer()
        if source and source ~= entry.container then
            addAction(player, ISInventoryTransferUtil.newInventoryTransferAction(player, entry.item, source, entry.container, 1), 1)
        end
    end
    addAction(player, ISWLMRestoreAttachmentsAction:new(player, profile.attached or {}, 1, recovery), 1)
    addAction(player, ISWLMFinalizeRecoveryAction:new(player, pending), 1)
    if Client.window then Client.window:setMessage(WLM.text("IGUI_WLM_Recovering", "Storage failed. Restoring your equipment..."), true) end
    return true
end

function Client.finishStoreRecovery(pending, interrupted)
    if Client.pendingStore ~= pending or pending.phase ~= "recovering" then return end
    local recovery = pending.recovery
    local player, profile = recovery.player, recovery.profile
    local missing = {}
    for _, entry in ipairs(recovery.items) do
        if not inventoryItem(player, entry.item:getID()) then missing[#missing + 1] = WLM.nameForItem(entry.item) end
    end
    for _, entry in ipairs(recovery.returnItems or {}) do
        if entry.item:getContainer() ~= entry.container then missing[#missing + 1] = WLM.nameForItem(entry.item) end
    end
    for _, entry in ipairs(profile.worn or {}) do
        if not wornItem(player, entry.id) then missing[#missing + 1] = entry.name end
    end
    for role, entry in pairs(profile.hands or {}) do
        local item
        if role == "primary" then item = player:getPrimaryHandItem() else item = player:getSecondaryHandItem() end
        if not item or tonumber(item:getID()) ~= tonumber(entry.id) then missing[#missing + 1] = entry.name end
    end
    if recovery.kind == "switch" and WLM.settings().includeHands then
        if not profile.hands.primary and player:getPrimaryHandItem() then missing[#missing + 1] = "Primary hand" end
        if not profile.hands.secondary and player:getSecondaryHandItem() then missing[#missing + 1] = "Secondary hand" end
    end
    for _, entry in ipairs(profile.attached or {}) do
        local item = inventoryItem(player, entry.id)
        if not item or tonumber(item:getAttachedSlot()) ~= tonumber(entry.slotIndex)
                or tostring(item:getAttachedSlotType()) ~= tostring(entry.slotType) then
            missing[#missing + 1] = entry.name
            WLM.debugLog(string.format("[WardrobeLoadouts] recovery attachment mismatch item=%s expected=%s:%s actual=%s:%s",
                tostring(entry.name), tostring(entry.slotType), tostring(entry.slotIndex),
                item and tostring(item:getAttachedSlotType()) or "missing", item and tostring(item:getAttachedSlot()) or "missing"))
        end
    end
    restoreFavorites(pending, player, pending.object and pending.object:getContainer())
    WLM.CarryGuard.release(pending.carryToken)
    local args = pending.objectArgs or WLM.objectArgs(pending.object)
    if isClient() then
        if args then sendClientCommand(player, WLM.ID, recovery.kind == "switch" and "abortSwitch" or "abortStore", args) end
    else
        local data = WLM.getData(pending.object, false)
        if data then data.lock, data.lockUntil = nil, nil end
        if pending.object and pending.object.transmitModData then pending.object:transmitModData() end
    end
    Client.pendingStore = nil
    local restored = not interrupted and not recovery.failed and #missing == 0
    local result = restored and WLM.text("IGUI_WLM_RecoveryComplete", "Your previous equipment has been restored.")
        or WLM.text("IGUI_WLM_RecoveryIncomplete", "Equipment recovery was incomplete. Check your inventory and wardrobe.")
    if #missing > 0 then result = result .. " (" .. table.concat(missing, ", ") .. ")" end
    logOperation("recovery", restored, profile, result)
    Client.showError((recovery.message or WLM.text("IGUI_WLM_ErrorStoreCancelled", "Storing equipment was cancelled.")) .. " " .. result)
end

function Client.finishStore(success, message)
    local pending = Client.pendingStore
    if not pending or pending.phase ~= "actions" then return end
    local player = getPlayer(Client.playerNum)
    local wardrobe = pending.object and pending.object:getContainer()
    if success then
        for _, id in ipairs(WLM.profileItems(pending.profile)) do
            if not WLM.findItem(wardrobe, id) then
                success = false
                message = WLM.text("IGUI_WLM_ErrorStoreIncomplete", "Some items could not be moved into the wardrobe; the loadout was not saved.")
                local item = inventoryItem(player, id)
                local name = item and WLM.nameForItem(item) or tostring(id)
                message = message .. " (" .. name .. ")"
                break
            end
        end
    end

    if not success and Client.recoverStore(pending, message) then return end

    local args = pending.objectArgs or WLM.objectArgs(pending.object)
    if isClient() then
        if success then
            restoreFavorites(pending, player, wardrobe)
            WLM.CarryGuard.release(pending.carryToken)
            args.profile = pending.profile
            args.updateId = pending.updateId
            pending.phase = "server"
            pending.deadline = getTimestamp() + 90
            Client.pendingStoreRequest = false
            sendClientCommand(player, WLM.ID, "finishStore", args)
            return
        end
        logOperation("store", false, pending.profile, message)
        pending.phase = "aborting"
        Client.pendingStoreRequest = false
        args.updateId = pending.updateId
        args.restoreActive = true
        sendClientCommand(player, WLM.ID, "abortStore", args)
    else
        if success then
            local saved, saveError = saveStoredProfile(player, pending)
            success = saved
            message = saveError or message
        end
        if not success and Client.recoverStore(pending, message) then return end
        if not success then logOperation("store", false, pending.profile, message) end
        if not success then
            local data = WLM.getData(pending.object, false)
            if data then
                if WLM.getActiveId(data, player) then
                    WLM.setActiveId(data, player, nil)
                end
                data.lock, data.lockUntil = nil, nil
                if Client.object == pending.object then Client.data = data end
            end
            if pending.object and pending.object.transmitModData then pending.object:transmitModData() end
        end
        if Client.window and Client.object == pending.object then Client.window:refresh() end
    end

    restoreFavorites(pending, player, wardrobe)
    WLM.CarryGuard.release(pending.carryToken)
    Client.pendingStore = nil
    if success then
        if Client.window and Client.object == pending.object then Client.window:setMessage(nil, false); Client.window:refresh() end
        notify(WLM.text("IGUI_WLM_SaveComplete", "Loadout stored in wardrobe."))
    else
        Client.showError(message or WLM.text("IGUI_WLM_ErrorStoreIncomplete", "Some items could not be moved into the wardrobe; the loadout was not saved."))
    end
end

function Client.showError(message)
    notify(tostring(message), true)
    if Client.window then
        Client.window:setMessage(tostring(message), true)
        Client.window:refresh()
    end
end

function Client.open(object, playerNum)
    if not WLM.isWardrobe(object) then return end
    object = WLM.storageObject(object)
    Client.object = object
    Client.playerNum = playerNum or 0
    WLM.capacity(object:getContainer())
    if isClient() then Client.data = nil else Client.data = WLM.getData(object, true) end
    Client.lastObject = object
    local uiScale = WLM.Options and WLM.Options.uiScale and WLM.Options.uiScale() or 1
    local window = Client.window
    local hasCurrentControls = window and window.closeButton and window.list and window.saveButton
        and window.updateButton and window.deleteButton and window.mergeButton and window.applyButton and window.saveDialog
        and window.saveDialog.nameEntry and window.saveDialog.cancelButton and window.saveDialog.saveButton
        and window.slotInterface == 6 and window.iconButton and window.scaleUpButton and window.infoButton
        and window.groupLists and window.groupLists.clothes
        and window.groupLists.hands and window.groupLists.attached
    if window and (window.uiScale ~= uiScale or not hasCurrentControls) then
        window:removeFromUIManager()
        Client.window = nil
    end
    if not Client.window then
        require "WardrobeLoadouts/UI"
        Client.window = WLM.UI:new()
        Client.window:initialise()
    end
    Client.window:open()
    Client.request()
end

function Client.openNearby(playerNum)
    local player = getPlayer(playerNum)
    local square = player and player:getSquare()
    if not square then return end
    local best, bestDistance
    for dx = -2, 2 do
        for dy = -2, 2 do
            local candidateSquare = getCell():getGridSquare(square:getX() + dx, square:getY() + dy, square:getZ())
            if candidateSquare then
                local objects = candidateSquare:getObjects()
                for index = 0, objects:size() - 1 do
                    local object = objects:get(index)
                    if WLM.isWardrobe(object) then
                        local distance = dx * dx + dy * dy
                        local canAccess = false
                        pcall(function() canAccess = player:canAccessContainer(object:getContainer()) end)
                        if canAccess and (not bestDistance or distance < bestDistance) then best, bestDistance = object, distance end
                    end
                end
            end
        end
    end
    if best then Client.open(best, playerNum) else Client.showError(WLM.text("IGUI_WLM_ErrorNoWardrobe", "No wardrobe is nearby.")) end
end

local function onServerCommand(module, command, args)
    if module ~= WLM.ID or not args then return end
    if command == "state" then
        if Client.object and args.object then
            local current = WLM.objectArgs(Client.object)
            if current and current.x == args.object.x and current.y == args.object.y and current.z == args.object.z
                    and current.objectIndex == args.object.objectIndex
                    and current.spriteName == args.object.spriteName then
                Client.data = args.data
                if Client.window then Client.window:refresh() end
            end
        end
    elseif command == "error" then
        local pendingStore = Client.pendingStore
        local pendingSwitch = Client.pendingSwitch
        if pendingStore then logOperation("store", false, pendingStore.profile, args.message or args.messageKey) end
        if pendingSwitch then logOperation("switch", false, pendingSwitch.profile, args.message or args.messageKey) end
        if pendingStore and pendingStore.phase == "recovering" then return end
        if pendingStore and Client.recoverStore(pendingStore, WLM.text(args.messageKey, args.message or "The wardrobe request failed.")) then return end
        if pendingSwitch and Client.recoverSwitch(pendingSwitch, WLM.text(args.messageKey, args.message or "The wardrobe request failed.")) then return end
        Client.switchPendingRequest = false
        Client.pendingStoreRequest = false
        Client.pendingStore = nil
        Client.showError(WLM.text(args.messageKey, args.message or "The wardrobe request failed."))
    elseif command == "storeReady" then
        local pending = Client.pendingStore
        Client.pendingStoreRequest = false
        if not pending or pending.phase ~= "request" or not pending.object
                or not sameObjectArgs(pending.objectArgs, WLM.objectArgs(pending.object))
                or not sameObjectArgs(args.object, pending.objectArgs) then
            local abortArgs = pending and pending.objectArgs or args.object
            if abortArgs then sendClientCommand(getPlayer(Client.playerNum), WLM.ID, "abortStore", abortArgs) end
            return
        end
        pending.phase = "actions"
        pending.updateId = args.updateId ~= "" and tostring(args.updateId) or nil
        local wardrobe = pending.object:getContainer()
        local ok, message = enqueueStore(getPlayer(Client.playerNum), pending.profile, wardrobe, pending)
        if not ok then
            pending.phase = "aborting"
            local abortArgs = pending.objectArgs or WLM.objectArgs(pending.object)
            if abortArgs then sendClientCommand(getPlayer(Client.playerNum), WLM.ID, "abortStore", abortArgs) end
            Client.pendingStore = nil
            Client.showError(message)
        end
    elseif command == "storeComplete" then
        local pending = Client.pendingStore
        if not pending or pending.phase ~= "server" or not sameObjectArgs(args.object, pending.objectArgs) then return end
        restoreFavorites(pending, getPlayer(Client.playerNum), pending.object and pending.object:getContainer())
        WLM.CarryGuard.release(pending.carryToken)
        Client.pendingStore = nil
        Client.pendingStoreRequest = false
        logOperation("store", true, pending.profile)
        if Client.window and Client.object == pending.object then Client.window:setMessage(nil, false); Client.window:refresh() end
        notify(WLM.text("IGUI_WLM_SaveComplete", "Loadout stored in wardrobe."))
    elseif command == "switchComplete" then
        local pending = Client.pendingSwitch
        if not pending or pending.phase ~= "server" or not sameObjectArgs(args.object, WLM.objectArgs(pending.object))
                or tostring(args.targetId) ~= pending.targetId then return end
        pending.phase = "committed"
        Client.finishSwitch(true)
    elseif command == "switchReady" then
        Client.switchPendingRequest = false
        local data = Client.data or WLM.getData(Client.object, false)
        local activeId = tostring(args.activeId or "")
        local active = args.slotAction and args.swapProfile or (activeId ~= "" and data and data.sets[activeId] or nil)
        local target = data and data.sets[tostring(args.targetId)]
        local container = Client.object and Client.object:getContainer()
        if (activeId ~= "" and not active) or not target or not container then
            sendClientCommand(getPlayer(Client.playerNum), WLM.ID, "abortSwitch", WLM.objectArgs(Client.object))
            Client.showError(WLM.text("IGUI_WLM_ErrorRefresh", "The wardrobe data changed before the switch could start."))
            return
        end
        Client.switchObjectArgs = WLM.objectArgs(Client.object)
        Client.switchObjectArgs.activeId = tostring(args.activeId)
        Client.switchObjectArgs.targetId = tostring(args.targetId)
        Client.switchObjectArgs.slotAction = args.slotAction
        Client.switchObjectArgs.merge = args.merge == true
        Client.switchObjectArgs.preferences = args.preferences or WLM.clientPreferences()
        local ok, message = enqueueSwitch(getPlayer(Client.playerNum), active, target, container, Client.switchObjectArgs.preferences, args.merge == true)
        if not ok then
            local abortArgs = WLM.objectArgs(Client.object)
            abortArgs.targetId = tostring(args.targetId)
            sendClientCommand(getPlayer(Client.playerNum), WLM.ID, "abortSwitch", abortArgs)
            Client.showError(message)
        else
            Client.pendingSwitch.slotAction = args.slotAction == true
            if Client.window then Client.window.applyButton:setEnable(false) end
        end
    end
end

Events.OnServerCommand.Add(onServerCommand)

local function monitorPendingStore()
    local pending = Client.pendingStore
    if not pending then return end
    if pending.phase == "recovering" then
        local queue = ISTimedActionQueue.queues[pending.recovery.player]
        if not queue or #queue.queue == 0 then Client.finishStoreRecovery(pending, true) end
        return
    end
    if pending.phase ~= "actions" then
        if pending.deadline and getTimestamp() > pending.deadline then
            Client.pendingStore = nil
            Client.pendingStoreRequest = false
            Client.showError(WLM.text("IGUI_WLM_ErrorStoreCancelled", "Storing equipment timed out."))
        end
        return
    end
    local player = getPlayer(Client.playerNum)
    local queue = player and ISTimedActionQueue.queues[player]
    if queue and #queue.queue > 0 then return end
    Client.finishStore(false, WLM.text("IGUI_WLM_ErrorStoreCancelled", "Storing equipment was cancelled."))
end

Events.OnTick.Add(monitorPendingStore)

local function monitorPendingSwitch()
    if not Client.pendingSwitch then return end
    if Client.pendingSwitch.phase == "server" then return end
    local player = getPlayer(Client.playerNum)
    local queue = player and ISTimedActionQueue.queues[player]
    if queue and #queue.queue > 0 then return end
    local equipped, missingItem = targetIsEquipped(player, Client.pendingSwitch.profile)
    if not Client.pendingSwitch.failed and equipped then
        Client.finishSwitch(true)
        return
    end
    local message = WLM.text("IGUI_WLM_ErrorCancelled", "Loadout switch cancelled.")
    if missingItem then message = message .. " (" .. tostring(missingItem) .. ")" end
    Client.finishSwitch(false, message)
end

Events.OnTick.Add(monitorPendingSwitch)

local function monitorCarryLimit()
    local operation = Client.carryOperation
    if not operation then return end
    if (Client.pendingStore == operation or Client.pendingSwitch == operation) and operation.phase ~= "server" then
        WLM.CarryGuard.keep(operation.carryToken)
    else
        WLM.CarryGuard.release(operation.carryToken)
        Client.carryOperation = nil
    end
end

Events.OnTick.Add(monitorCarryLimit)

Events.OnGameStart.Add(function()
    local operation = Client.carryOperation
    if operation then WLM.CarryGuard.release(operation.carryToken) end
    Client.carryOperation = nil
end)

local function actionQueueSummary(player)
    local queue = player and ISTimedActionQueue.queues[player]
    if not queue or type(queue.queue) ~= "table" then return "empty" end
    local descriptions = {}
    for _, action in ipairs(queue.queue) do
        local actionType = tostring(action.Type or "unknown")
        if actionType == "ISInventoryTransferAction" then
            local item = action.item
            local source, destination = action.srcContainer, action.destContainer
            local queued = 0
            for _, entry in pairs(action.queueList or {}) do queued = queued + #(entry.items or {}) end
            descriptions[#descriptions + 1] = string.format("%s(item=%s,from=%s,to=%s,queued=%d)",
                actionType, item and WLM.nameForItem(item) or "unknown",
                source and tostring(source:getType()) or "none",
                destination and tostring(destination:getType()) or "none", queued)
        else
            descriptions[#descriptions + 1] = actionType
        end
    end
    return #descriptions > 0 and table.concat(descriptions, ";") or "empty"
end

local function monitorSuccessfulSwitch()
    if not WLM.Options.diagnosticsEnabled() then Client.switchWatch = nil; return end
    local watch = Client.switchWatch
    if not watch then return end
    local now = getTimestamp()
    if now < watch.nextCheck then return end
    if now > watch.expires then
        WLM.debugLog(string.format("[WardrobeLoadouts] post-switch watch ended target=%s returned=%d",
            tostring(watch.targetId), watch.returned))
        Client.switchWatch = nil
        return
    end
    watch.nextCheck = now + 1
    local player = getPlayer(Client.playerNum)
    for _, id in ipairs(WLM.profileItems(watch.profile)) do
        local item = WLM.findItem(watch.wardrobe, id)
        if item and not watch.seen[id] then
            watch.seen[id] = true
            watch.returned = watch.returned + 1
            if not watch.queueLogged then
                watch.queueLogged = true
                local ok, summary = pcall(actionQueueSummary, player)
                WLM.debugLog("[WardrobeLoadouts] post-switch action-queue=" .. (ok and tostring(summary) or "unavailable"))
            end
            WLM.debugLog(string.format("[WardrobeLoadouts] post-switch item in wardrobe target=%s item=%s id=%s inventoryAlso=%s",
                tostring(watch.targetId), WLM.nameForItem(item), tostring(id),
                tostring(inventoryItem(player, id) ~= nil)))
        end
    end
end

Events.OnTick.Add(monitorSuccessfulSwitch)
