require = function() end
WardrobeLoadouts = { debugLog = function() end }
local furniture = { getContentsWeight = function() return 62 end }
WardrobeLoadouts.storageContainers = function() return { furniture } end
dofile("content/mods/WardrobeLoadouts/42/media/lua/shared/WardrobeLoadouts/CarryGuard.lua")
local Guard = WardrobeLoadouts.CarryGuard
local inventory = { capacity = 50 }
function inventory:getCapacity() return self.capacity end
function inventory:setCapacity(value) self.capacity = value end
function inventory:getContentsWeight() return 85 end
local player = { maxWeight = 16 }
function player:getInventory() return inventory end
function player:getMaxWeight() return self.maxWeight end
function player:setMaxWeight(value) self.maxWeight = value end
local token = Guard.begin(player, furniture)
assert(inventory.capacity >= 147 and player.maxWeight >= 147)
assert(furniture:getContentsWeight() == 62)
player.maxWeight = 16
Guard.keep(token)
assert(player.maxWeight == token.limit)
Guard.release(token)
assert(inventory.capacity == 50 and player.maxWeight == 16)
player.maxWeight = 18
Guard.release(token)
assert(player.maxWeight == 18)
token = Guard.begin(player, furniture)
Guard.release(token)
assert(player.maxWeight == 18 and inventory.capacity == 50)
print("PASS: temporary carry limits accommodate both outfits, survive the character's recalculation, restore the previous values and release only once.")
