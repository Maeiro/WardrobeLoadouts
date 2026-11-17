WardrobeLoadouts = WardrobeLoadouts or {}

local WLM = WardrobeLoadouts

WLM.ID = "WardrobeLoadouts"
WLM.DATA_KEY = "WardrobeLoadouts"
WLM.VERSION = 1

function WLM.debugLog(message)
    if not WLM.Options or not WLM.Options.diagnosticsEnabled or not WLM.Options.diagnosticsEnabled() then return false end
    print(message)
    return true
end

function WLM.text(key, fallback)
    if WLM.Locales and WLM.Options and WLM.Options.languageCode then
        local code = WLM.Options.languageCode()
        if not code and Translator and Translator.getLanguage then
            local ok, language = pcall(function() return Translator.getLanguage():name() end)
            if ok then code = ({ CH = "CN", CHS = "CN", BR = "PTBR" })[language] or language end
        end
        if code and WLM.Locales[code] then return WLM.Locales[code][key] or WLM.Locales.EN[key] or fallback or key end
    end
    if key and getTextOrNull then
        local ok, value = pcall(getTextOrNull, key)
        if ok and value and value ~= key then return value end
    end
    return fallback or key
end

function WLM.settings()
    local options = SandboxVars and SandboxVars.WardrobeLoadouts or {}
    return {
        maxLoadouts = math.max(1, math.min(24, tonumber(options.MaxLoadouts) or 12)),
        switchDuration = math.max(0, math.min(10, tonumber(options.SwitchDuration) or 0)),
        storageCapacity = math.max(50, math.min(100, tonumber(options.StorageCapacity) or 100)),
        includeHands = options.IncludeHands ~= false,
        includeBags = options.IncludeBags ~= false,
        includeAttachments = options.IncludeAttachments ~= false,
        includeKeyRing = options.IncludeKeyRing ~= false,
    }
end

local storageTypes = { wardrobe = true, dresser = true, locker = true, militarylocker = true }

function WLM.isWardrobe(object)
    if not object or not object.getContainer then return false end
    local ok, container = pcall(function() return object:getContainer() end)
    if not ok or not container then return false end
    local okType, containerType = pcall(function() return container:getType() end)
    if okType and storageTypes[containerType] then return true end
    local named, result = pcall(function()
        local props = object:getSprite():getProperties()
        local name = string.lower(tostring(props:get("CustomName") or "") .. " " .. tostring(props:get("GroupName") or ""))
        return name:find("%f[%a]wardrobes?%f[%A]") or name:find("%f[%a]dressers?%f[%A]") or name:find("%f[%a]lockers?%f[%A]")
    end)
    return named and result ~= nil and result ~= false
end

function WLM.storageObjects(object)
    if not object then return {} end
    local ok, parts = pcall(function()
        local sprite, square = object:getSprite(), object:getSquare()
        local grid = sprite and sprite:getSpriteGrid()
        if not grid or not square or grid:getWidth() * grid:getHeight() > 16 then return { object } end
        local originX = square:getX() - grid:getSpriteGridPosX(sprite)
        local originY = square:getY() - grid:getSpriteGridPosY(sprite)
        local found = {}
        for x = 0, grid:getWidth() - 1 do
            for y = 0, grid:getHeight() - 1 do
                local expected = grid:getSprite(x, y)
                if expected then
                    local tile = getCell():getGridSquare(originX + x, originY + y, square:getZ())
                    if not tile then return { object } end
                    local match
                    local objects = tile:getObjects()
                    for index = 0, objects:size() - 1 do
                        local candidate = objects:get(index)
                        if candidate:getSprite() == expected and WLM.isWardrobe(candidate) then match = candidate; break end
                    end
                    if not match then return { object } end
                    found[#found + 1] = match
                end
            end
        end
        return #found > 0 and found or { object }
    end)
    return ok and parts or { object }
end

function WLM.storageObject(object)
    return WLM.storageObjects(object)[1]
end

function WLM.storageContainers(container)
    local ok, object = pcall(function() return container:getParent() end)
    if not ok or not WLM.isWardrobe(object) then return { container } end
    local containers, seen = {}, {}
    for _, part in ipairs(WLM.storageObjects(object)) do
        local countOK, count = pcall(function() return part:getContainerCount() end)
        count = countOK and count or 1
        for index = 0, math.min(count, 8) - 1 do
            local got, current = pcall(function() return part:getContainerByIndex(index) end)
            if not got then current = part:getContainer() end
            if current and not seen[current] then seen[current] = true; containers[#containers + 1] = current end
        end
    end
    return #containers > 0 and containers or { container }
end

function WLM.canAccessStorage(player, object)
    if not player or not object then return false end
    for _, part in ipairs(WLM.storageObjects(object)) do
        local square = part.getSquare and part:getSquare()
        local playerSquare = player.getSquare and player:getSquare()
        local nearby = not square or not playerSquare or (square:getZ() == playerSquare:getZ()
            and math.abs(square:getX() - playerSquare:getX()) <= 2 and math.abs(square:getY() - playerSquare:getY()) <= 2)
        if nearby then
            for _, container in ipairs(WLM.storageContainers(part:getContainer())) do
                local ok, allowed = pcall(function() return player:canAccessContainer(container) end)
                if ok and allowed then return true end
            end
        end
    end
    return false
end

function WLM.destinationContainer(container, player)
    for _, current in ipairs(WLM.storageContainers(container)) do
        local ok, allowed = pcall(function() return player:canAccessContainer(current) end)
        if ok and allowed then return current end
    end
    return container
end

function WLM.storageWeight(container)
    local total = 0
    for _, current in ipairs(WLM.storageContainers(container)) do total = total + current:getCapacityWeight() end
    return total
end

local function mergeStorageData(owner, parts)
    local ownerModData = owner:getModData()
    local data = ownerModData[WLM.DATA_KEY]
    for _, part in ipairs(parts) do
        local other = part ~= owner and part:getModData()[WLM.DATA_KEY]
        if other and other ~= data then
            if not data then
                data = other
                ownerModData[WLM.DATA_KEY] = data
            else
                WLM.slots(data)
                WLM.slots(other)
                local usedSlots = WLM.slots(data)
                data.nextId = tonumber(data.nextId) or 1
                local movedSlots = {}
                local ids = {}
                for id in pairs(other.sets or {}) do ids[#ids + 1] = tostring(id) end
                table.sort(ids, function(a,b) return (tonumber(a) or 0) < (tonumber(b) or 0) end)
                for _, oldId in ipairs(ids) do
                    local profile = other.sets[oldId]
                    local oldSlot = profile.slot
                    movedSlots[tostring(oldSlot)] = true
                    local slot = 1
                    while usedSlots[slot] or data.slotNames[tostring(slot)] or (data.slotIcons and data.slotIcons[tostring(slot)]) do slot = slot + 1 end
                    while data.sets[tostring(data.nextId)] do data.nextId = data.nextId + 1 end
                    local id = tostring(data.nextId)
                    data.nextId = data.nextId + 1
                    profile.id, profile.slot = id, slot
                    data.sets[id] = profile
                    usedSlots[slot] = { id = id, profile = profile }
                    data.slotNames[tostring(slot)] = profile.name
                    data.slotIcons = data.slotIcons or {}
                    data.slotIcons[tostring(slot)] = other.slotIcons and other.slotIcons[tostring(oldSlot)]
                    data.activeByPlayer = data.activeByPlayer or {}
                    for playerKey, activeId in pairs(other.activeByPlayer or {}) do
                        if tostring(activeId) == oldId and not data.activeByPlayer[playerKey] then data.activeByPlayer[playerKey] = id end
                    end
                end
                local metadataSlots = {}
                for slot in pairs(other.slotNames or {}) do metadataSlots[slot] = true end
                for slot in pairs(other.slotIcons or {}) do metadataSlots[slot] = true end
                for oldSlot in pairs(metadataSlots) do
                    if not movedSlots[tostring(oldSlot)] then
                        local slot = tonumber(oldSlot) or 1
                        if usedSlots[slot] or data.slotNames[tostring(slot)] or (data.slotIcons and data.slotIcons[tostring(slot)]) then
                            slot = 1
                            while usedSlots[slot] or data.slotNames[tostring(slot)] or (data.slotIcons and data.slotIcons[tostring(slot)]) do slot = slot + 1 end
                        end
                        data.slotNames[tostring(slot)] = WLM.slotName(other, oldSlot)
                        data.slotIcons = data.slotIcons or {}
                        data.slotIcons[tostring(slot)] = other.slotIcons and other.slotIcons[tostring(oldSlot)]
                    end
                end
            end
            part:getModData()[WLM.DATA_KEY] = nil
            if part.transmitModData then part:transmitModData() end
            if owner.transmitModData then owner:transmitModData() end
        end
    end
end

function WLM.objectArgs(object)
    object = WLM.storageObject(object)
    local square = object and object:getSquare()
    if not square then return nil end
    local objectIndex = -1
    pcall(function() objectIndex = object:getObjectIndex() end)
    local spriteName = ""
    pcall(function() spriteName = object:getSprite():getName() end)
    return {
        x = square:getX(),
        y = square:getY(),
        z = square:getZ(),
        objectIndex = objectIndex,
        spriteName = spriteName,
    }
end

function WLM.getData(object, create)
    if not object then return nil end
    local parts = WLM.storageObjects(object)
    object = parts[1]
    if not isClient or not isClient() then mergeStorageData(object, parts) end
    local modData = object:getModData()
    local data = modData[WLM.DATA_KEY]
    if not data and create then
        data = { version = WLM.VERSION, sets = {}, nextId = 1, activeByPlayer = {} }
        modData[WLM.DATA_KEY] = data
    end
    if data then
        data.sets = type(data.sets) == "table" and data.sets or {}
        data.nextId = tonumber(data.nextId) or 1
        data.slotNames = type(data.slotNames) == "table" and data.slotNames or {}
        data.slotIcons = type(data.slotIcons) == "table" and data.slotIcons or {}
        data.activeByPlayer = type(data.activeByPlayer) == "table" and data.activeByPlayer or {}
        WLM.slots(data)
    end
    return data
end

function WLM.activeKey(player)
    if not player then return "single" end
    local ok, username = pcall(function() return player:getUsername() end)
    if ok and username and tostring(username) ~= "" then return "user:" .. tostring(username) end
    local idOk, id = pcall(function() return player:getOnlineID() end)
    return idOk and tostring(id) or "single"
end

function WLM.getActiveId(data, player)
    if not data then return nil end
    return data.activeByPlayer and data.activeByPlayer[WLM.activeKey(player)]
end

function WLM.setActiveId(data, player, setId)
    if not data then return end
    data.activeByPlayer = type(data.activeByPlayer) == "table" and data.activeByPlayer or {}
    local key = WLM.activeKey(player)
    if setId == nil then data.activeByPlayer[key] = nil else data.activeByPlayer[key] = tostring(setId) end
    data.activeId = data.activeByPlayer[key]
end

function WLM.getSet(data, setId)
    if not data or not data.sets or setId == nil then return nil end
    return data.sets[tostring(setId)]
end

function WLM.isBandageEntry(entry)
    if type(entry) ~= "table" then return false end
    if entry.isBandage == true then return true end
    local fullType = string.lower(tostring(entry.fullType or ""))
    if fullType:match("^[^%.]+%.bandage_") then return true end
    return string.find(string.lower(tostring(entry.bodyLocation or "")), "bandage", 1, true) ~= nil
end

function WLM.profileItems(profile)
    local settings = WLM.settings()
    local found, seen = {}, {}
    local function add(entry)
        local id = type(entry) == "table" and tonumber(entry.id) or nil
        if id and not seen[id] then
            seen[id] = true
            found[#found + 1] = id
        end
    end
    for _, entry in ipairs(profile and profile.worn or {}) do
        if not WLM.isBandageEntry(entry) and (settings.includeBags or entry.isBag ~= true) then add(entry) end
    end
    if settings.includeAttachments then
        for _, entry in ipairs(profile and profile.attached or {}) do add(entry) end
    end
    if settings.includeHands and profile and profile.hands then
        add(profile.hands.primary)
        add(profile.hands.secondary)
    end
    if settings.includeKeyRing then add(profile and profile.keyRing) end
    return found
end

function WLM.profileRoles(profile)
    local settings = WLM.settings()
    local roles = {}
    local function add(entry, role)
        local id = type(entry) == "table" and tonumber(entry.id) or nil
        if id then
            roles[id] = roles[id] or {}
            roles[id][#roles[id] + 1] = role
        end
    end
    for index, entry in ipairs(profile and profile.worn or {}) do
        if not WLM.isBandageEntry(entry) and (settings.includeBags or entry.isBag ~= true) then add(entry, "worn") end
    end
    if settings.includeAttachments then
        for _, entry in ipairs(profile and profile.attached or {}) do
            add(entry, "attached:" .. tostring(entry.slotType or "") .. ":" .. tostring(entry.slotIndex or 0))
        end
    end
    if settings.includeHands and profile and profile.hands then
        add(profile.hands.primary, "hand:primary")
        add(profile.hands.secondary, "hand:secondary")
    end
    if settings.includeKeyRing then add(profile and profile.keyRing, "keyring") end
    for _, itemRoles in pairs(roles) do
        table.sort(itemRoles)
    end
    return roles
end

function WLM.nameForItem(item)
    if not item then return "Unknown item" end
    local ok, name = pcall(function() return item:getDisplayName() end)
    if ok and name and name ~= "" then return tostring(name) end
    return tostring(item:getFullType())
end

function WLM.findItem(container, id)
    if not container or not id then return nil end
    local ok, item = pcall(function() return container:getItemById(tonumber(id)) end)
    if ok and item then return item end
    local visited = {}
    local function search(current)
        if not current or visited[current] then return nil end
        visited[current] = true
        local items = current:getItems()
        if not items then return nil end
        for index = 0, items:size() - 1 do
            local candidate = items:get(index)
            if candidate and tonumber(candidate:getID()) == tonumber(id) then return candidate end
            if candidate and candidate:IsInventoryContainer() then
                local match = search(candidate:getInventory())
                if match then return match end
            end
        end
        return nil
    end
    for _, current in ipairs(WLM.storageContainers(container)) do
        item = search(current)
        if item then return item end
    end
    return nil
end

function WLM.countSets(data)
    local count = 0
    for _ in pairs(data and data.sets or {}) do count = count + 1 end
    return count
end

function WLM.isSetActive(data, setId)
    if not data then return false end
    setId = tostring(setId)
    local hasPlayerEntries = false
    for _, activeId in pairs(data.activeByPlayer or {}) do
        hasPlayerEntries = true
        if tostring(activeId) == setId then return true end
    end
    return not hasPlayerEntries and tostring(data.activeId or "") == setId
end

function WLM.itemWeight(item)
    if not item then return 0 end
    local ok, weight = pcall(function() return item:getUnequippedWeight() end)
    if not ok then ok, weight = pcall(function() return item:getActualWeight() end) end
    return ok and math.max(0, tonumber(weight) or 0) or 0
end

function WLM.capacity(container)
    if not container then return end
    local limit = WLM.settings().storageCapacity
    for _, current in ipairs(WLM.storageContainers(container)) do
        pcall(function() current:setCapacity(limit) end)
    end
end

function WLM.slots(data)
    local slots, pending = {}, {}
    local count = WLM.settings().maxLoadouts
    for id, profile in pairs(data and data.sets or {}) do
        pending[#pending + 1] = { id = tostring(id), profile = profile }
    end
    table.sort(pending, function(a, b) return (tonumber(a.id) or 0) < (tonumber(b.id) or 0) end)
    for _, entry in ipairs(pending) do
        local slot = tonumber(entry.profile.slot)
        if slot and slot >= 1 and slot == math.floor(slot) and not slots[slot] then
            slots[slot] = entry
            count = math.max(count, slot)
            entry.placed = true
        end
    end
    for _, entry in ipairs(pending) do
        if not entry.placed then
            local slot = 1
            while slots[slot] do slot = slot + 1 end
            slots[slot] = entry
            entry.profile.slot = slot
            count = math.max(count, slot)
        end
    end
    if data then
        data.slotNames = type(data.slotNames) == "table" and data.slotNames or {}
        for slot, entry in pairs(slots) do
            local key = tostring(slot)
            if not data.slotNames[key] then data.slotNames[key] = entry.profile.name end
            entry.profile.name = data.slotNames[key]
        end
    end
    local metadataSlots = {}
    for slot in pairs(data and data.slotNames or {}) do metadataSlots[slot] = true end
    for slot in pairs(data and data.slotIcons or {}) do metadataSlots[slot] = true end
    for slot in pairs(metadataSlots) do
        local number = tonumber(slot)
        if number and number >= 1 and number <= 1000 and number == math.floor(number) then count = math.max(count, number) end
    end
    return slots, count
end

function WLM.slotName(data, slot)
    return data and data.slotNames and data.slotNames[tostring(slot)]
        or WLM.text("IGUI_WLM_Slot", "Slot") .. " " .. tostring(slot)
end

function WLM.setSlotName(data, slot, name)
    slot = tonumber(slot)
    if not data or not slot or slot < 1 or slot ~= math.floor(slot) then return false end
    local slots, count = WLM.slots(data)
    if slot > count or type(name) ~= "string" or #name < 1 or #name > 64 then return false end
    data.slotNames[tostring(slot)] = name
    if slots[slot] then slots[slot].profile.name = name end
    return true
end

function WLM.slotAvailable(data, slot)
    slot = tonumber(slot)
    if not slot or slot ~= math.floor(slot) or slot < 1 or slot > WLM.settings().maxLoadouts then return false end
    local slots = WLM.slots(data)
    return slots[slot] == nil
end

function WLM.completeSlotSwitch(data, player, targetId, replacement)
    local activeId = WLM.getActiveId(data, player)
    if activeId and tostring(activeId) ~= tostring(targetId) then data.sets[tostring(activeId)] = nil end
    if replacement and #WLM.profileItems(replacement) > 0 then
        replacement.name = WLM.slotName(data, replacement.slot)
        replacement.id = tostring(targetId)
        replacement.savedAt = getTimestamp()
        data.sets[tostring(targetId)] = replacement
    else
        data.sets[tostring(targetId)] = nil
    end
    WLM.setActiveId(data, player, nil)
end
