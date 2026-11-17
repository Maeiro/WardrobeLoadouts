require = function() end
local ticks, serverHandler = {}, nil
Events = {
    OnTick = { Add = function(callback) ticks[#ticks + 1] = callback end },
    OnServerCommand = { Add = function(callback) serverHandler = callback end },
}
dofile("content/mods/WardrobeLoadouts/42/media/lua/shared/WardrobeLoadouts/Shared.lua")
local WLM = WardrobeLoadouts
WLM.Options = { diagnosticsEnabled = function() return false end }
WLM.text = function(_, fallback) return fallback end
local inventory, wardrobe, data = {}, {}, { lock = 1, sets = {} }
local items, worn, queue, messages = {}, {}, {}, {}
local player = {
    getInventory = function() return inventory end,
    getPlayerNum = function() return 0 end,
    getWornItems = function()
        local entries = {}
        for id in pairs(worn) do
            local item = items[id]
            entries[#entries + 1] = { getItem = function() return item end }
        end
        return { size = function() return #entries end, get = function(_, index) return entries[index + 1] end }
    end,
}
function player:getPrimaryHandItem() return self.primary end
function player:getSecondaryHandItem() return self.secondary end
function getSpecificPlayer() return player end
function isClient() return false end
function getTimestamp() return 10 end
WLM.findItem = function(container, id)
    local item = items[tonumber(id)]
    return item and item.container == container and item or nil
end
WLM.getData = function() return data end
WLM.objectArgs = function() return {} end
WLM.nameForItem = function(item) return item.name end
local object = { getContainer = function() return wardrobe end }
ISTimedActionQueue = { queues = { [player] = { queue = queue } }, add = function(action) queue[#queue + 1] = action end }
ISInventoryTransferUtil = { newInventoryTransferAction = function(_, item, source, destination)
    return { Type = "transfer", run = function() if item.container == source then item.container = destination end end }
end }
ISWearClothing = { new = function(_, _, item) return { Type = "wear", run = function() worn[item.id] = true end } end }
ISEquipWeaponAction = { new = function(_, _, item, _, primary, both)
    return { Type = "equip", run = function()
        if primary then player.primary = item else player.secondary = item end
        if both then player.secondary = item end
    end }
end }
ISWLMRestoreAttachmentsAction = { new = function(_, _, entries, _, operation)
    return { Type = "attach", run = function()
        assert(operation)
        for _, entry in ipairs(entries) do items[entry.id].slot = entry.slotIndex; items[entry.id].slotType = entry.slotType end
    end }
end }
ISWLMFinalizeRecoveryAction = { new = function(_, _, pending)
    return { Type = "finalize", run = function() WLM.Client.finishStoreRecovery(pending) end }
end }
dofile("content/mods/WardrobeLoadouts/42/media/lua/client/WardrobeLoadouts/Client.lua")
local Client = WLM.Client
Client.object = object
Client.showError = function(message) messages[#messages + 1] = message end
local function item(id, container)
    local value = { id = id, container = container, name = "item" .. id, slot = -1, favorite = true }
    function value:getID() return self.id end
    function value:getContainer() return self.container end
    function value:isFavorite() return self.favorite end
    function value:setFavorite(value) self.favorite = value end
    function value:getAttachedSlot() return self.slot end
    function value:getAttachedSlotType() return self.slotType end
    items[id] = value
    return value
end
local function pending()
    worn = {}
    local rifle, tool, ring, shirt = item(1, wardrobe), item(2, wardrobe), item(3, inventory), item(4, wardrobe)
    local profile = { worn = { { id = 4, name = "shirt" } }, hands = { primary = { id = 1, name = "rifle" }, secondary = { id = 1, name = "rifle" } },
        attached = { { id = 2, name = "tool", slotIndex = 4, slotType = "Holster" } }, keyRing = { id = 3 } }
    local value = { phase = "actions", object = object, profile = profile,
        recovery = { player = player, profile = profile, items = { { item = rifle }, { item = tool }, { item = ring }, { item = shirt } } } }
    Client.pendingStore = value
    return value
end
local function drain()
    while #queue > 0 do table.remove(queue, 1).run() end
end

local operation = pending()
Client.finishStore(true)
assert(operation.phase == "recovering" and #queue > 0)
local count = #queue
assert(not Client.recoverStore(operation, "duplicate failure"))
assert(#queue == count)
drain()
assert(Client.pendingStore == nil and items[1].container == inventory and items[2].container == inventory)
assert(player.primary == items[1] and player.secondary == items[1])
assert(worn[4] and items[4].container == inventory)
assert(items[2].slot == 4 and items[2].slotType == "Holster")
assert(items[1].favorite and items[2].favorite and items[3].favorite)
assert(data.lock == nil and next(data.sets) == nil)
assert(messages[#messages]:find("previous equipment has been restored", 1, true))

operation = pending()
ticks[1]()
assert(operation.phase == "recovering")
drain()
assert(Client.pendingStore == nil)

operation = pending()
operation.phase = "server"
serverHandler(WLM.ID, "error", { message = "Server rejected save" })
assert(operation.phase == "recovering")
drain()
assert(Client.pendingStore == nil)

operation = pending()
assert(Client.recoverStore(operation, "Failed"))
while #queue > 0 do table.remove(queue) end
ticks[1]()
assert(Client.pendingStore == nil)
assert(messages[#messages]:find("recovery was incomplete", 1, true))

operation = pending()
for _, entry in ipairs(operation.recovery.items) do entry.item.container = wardrobe end
data.nextId = 1
WLM.slotLimit = function() return 12 end
WLM.activeKey = function() return "test" end
Client.finishStore(true)
assert(Client.pendingStore == nil and #queue == 0)
assert(data.sets["1"] == operation.profile)
assert(items[1].container == wardrobe)
print("PASS: partial storage, cancellation and server rejection recover the original items, two-hand equipment, attachment slot and favorites; interrupted recovery reports failure without looping.")
