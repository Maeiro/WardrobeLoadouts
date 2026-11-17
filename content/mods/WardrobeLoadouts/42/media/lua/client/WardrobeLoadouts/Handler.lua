require "ISUI/LootWindow/ISLootWindowObjectControlHandler"

local WLM = WardrobeLoadouts

ISLootWindowObjectControlHandler_WardrobeLoadouts = ISLootWindowObjectControlHandler:derive("ISLootWindowObjectControlHandler_WardrobeLoadouts")
local Handler = ISLootWindowObjectControlHandler_WardrobeLoadouts
Handler.Type = "WardrobeLoadouts"

function Handler:shouldBeVisible()
    return WLM.isWardrobe(self.object)
end

function Handler:getControl()
    self.control = self:getButtonControl(WLM.text("IGUI_WLM_Open", "Gerenciar conjuntos"))
    return self.control
end

function Handler:handleJoypadContextMenu(context)
    local option = self:addJoypadContextMenuOption(context, WLM.text("IGUI_WLM_Open", "Gerenciar conjuntos"))
    option.iconTexture = ContainerButtonIcons and ContainerButtonIcons.wardrobe
end

function Handler:perform()
    WLM.Client.open(self.object, self.playerNum)
end

function Handler:new()
    local o = ISLootWindowObjectControlHandler.new(self)
    o.altColor = true
    return o
end

local function addHandler()
    if ISLootWindowContainerControls and ISLootWindowContainerControls.AddHandler then
        ISLootWindowContainerControls.AddHandler(Handler, true)
    end
end

addHandler()
if Events and Events.OnGameStart then Events.OnGameStart.Add(addHandler) end
