require "WardrobeLoadouts/Shared"

local WLM = WardrobeLoadouts
WLM.CarryGuard = WLM.CarryGuard or {}
local Guard = WLM.CarryGuard

function Guard.begin(player, wardrobe)
    local inventory = player:getInventory()
    local token = {
        player = player, inventory = inventory,
        capacity = inventory:getCapacity(), maxWeight = player:getMaxWeight(),
    }
    local weight = inventory:getContentsWeight()
    for _, container in ipairs(WLM.storageContainers(wardrobe)) do weight = weight + container:getContentsWeight() end
    token.limit = math.ceil(math.max(token.capacity, token.maxWeight, weight) + 50)
    inventory:setCapacity(token.limit)
    player:setMaxWeight(token.limit)
    WLM.debugLog(string.format("[WardrobeLoadouts] temporary carry limit=%d previousCapacity=%d previousMaxWeight=%d",
        token.limit, token.capacity, token.maxWeight))
    return token
end

function Guard.keep(token)
    if token and not token.released then token.player:setMaxWeight(token.limit) end
end

function Guard.release(token)
    if not token or token.released then return end
    token.inventory:setCapacity(token.capacity)
    token.player:setMaxWeight(token.maxWeight)
    token.released = true
    WLM.debugLog("[WardrobeLoadouts] restored previous carry limits")
end
