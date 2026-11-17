require "WardrobeLoadouts/Shared"
require "ISUI/ISWorldObjectContextMenu"

local WLM = WardrobeLoadouts

local function open(object, playerNum)
    WLM.Client.open(object, playerNum)
end

local function addAccess(playerNum, context, worldobjects, test)
    if not context or type(worldobjects) ~= "table" then return end
    for _, object in ipairs(worldobjects) do
        if WLM.isWardrobe(object) then
            if test then return ISWorldObjectContextMenu.setTest() end
            local label = WLM.text("IGUI_WLM_Open", "Manage Loadouts")
            if context:getOptionFromName(label) then return end
            local option = context:addOption(label, object, open, playerNum)
            option.iconTexture = ContainerButtonIcons and ContainerButtonIcons.wardrobe
            local player = getSpecificPlayer(playerNum)
            option.notAvailable = not WLM.canAccessStorage(player, object)
            return
        end
    end
end

if WLM.accessHandler then Events.OnFillWorldObjectContextMenu.Remove(WLM.accessHandler) end
WLM.accessHandler = addAccess
Events.OnFillWorldObjectContextMenu.Add(addAccess)
