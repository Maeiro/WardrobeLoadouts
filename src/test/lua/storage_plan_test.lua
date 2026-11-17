dofile("content/mods/WardrobeLoadouts/42/media/lua/shared/WardrobeLoadouts/Shared.lua")

local WLM = WardrobeLoadouts
local containers
WLM.capacity = function() end
WLM.storageContainers = function() return containers end
local player = { canAccessContainer = function(_, container) return container.accessible ~= false end }

local function compartment(capacity, used, accessible)
    return {
        accessible = accessible,
        getEffectiveCapacity = function() return capacity end,
        getCapacityWeight = function() return used end,
        isItemAllowed = function(_, item) return not item.rejected end,
        hasRoomFor = function(_, _, item) return used + item.weight <= capacity end,
    }
end

local function item(weight, rejected)
    return { weight = weight, rejected = rejected, getUnequippedWeight = function() return weight end }
end

containers = { compartment(32, 0), compartment(31, 0) }
local items = { item(12), item(20), item(15), item(15) }
local plan = assert(WLM.planStorage(nil, player, items))
assert(#plan == 4)
local totals = {}
for _, transfer in ipairs(plan) do
    totals[transfer.destination] = (totals[transfer.destination] or 0) + transfer.item.weight
end
assert(totals[containers[1]] == 30 and totals[containers[2]] == 32
    or totals[containers[1]] == 32 and totals[containers[2]] == 30)
assert(items[1].weight == 12)

containers = { compartment(8, 0), compartment(7, 0) }
assert(#WLM.planStorage(nil, player, { item(7), item(5), item(3) }) == 3)

containers = { compartment(32, 32), compartment(31, 1) }
plan = assert(WLM.planStorage(nil, player, { item(15), item(15) }))
assert(plan[1].destination == containers[2] and plan[2].destination == containers[2])

containers = { compartment(32, 20), compartment(31, 20) }
assert(WLM.planStorage(nil, player, { item(15) }) == nil)
containers = { compartment(32, 0), compartment(31, 0, false) }
assert(WLM.planStorage(nil, player, { item(20), item(20) }) == nil)
assert(WLM.planStorage(nil, player, { item(1, true) }) == nil)
assert(WLM.planStorage(nil, player, { item(40) }) == nil)
assert(#WLM.planStorage(nil, player, {}) == 0)
containers = { compartment(32, 0) }
assert(WLM.planStorage(nil, player, { item(20), item(20) }) == nil)
assert(#WLM.planStorage(nil, player, { item(12.5), item(19.5) }) == 2)
print("PASS: storage planning distributes items and rejects transfers that cannot fit before queuing actions.")
