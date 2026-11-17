require "WardrobeLoadouts/Cursor"
require "ISUI/ISPanel"
require "ISUI/ISButton"
require "ISUI/ISScrollingListBox"
require "ISUI/ISTextEntryBox"

local WLM = WardrobeLoadouts
local colors = {
    background = { r = 0.09, g = 0.10, b = 0.105, a = 0.98 },
    listBackground = { r = 0.075, g = 0.08, b = 0.08, a = 1 },
    header = { r = 0.14, g = 0.15, b = 0.155, a = 1 },
    sidebar = { r = 0.115, g = 0.12, b = 0.12, a = 1 },
    panel = { r = 0.125, g = 0.135, b = 0.135, a = 1 },
    input = { r = 0.07, g = 0.075, b = 0.075, a = 1 },
    border = { r = 0.31, g = 0.32, b = 0.30, a = 1 },
    text = { r = 0.90, g = 0.88, b = 0.83, a = 1 },
    muted = { r = 0.65, g = 0.64, b = 0.60, a = 1 },
    accent = { r = 0.82, g = 0.60, b = 0.27, a = 1 },
}

local function textWidth(value, font)
    local manager = getTextManager and getTextManager()
    if manager then
        local ok, width = pcall(function() return manager:MeasureStringX(font, value) end)
        if ok and tonumber(width) then return tonumber(width) end
    end
    return #value * 7
end

local function fitText(value, font, maxWidth)
    value = tostring(value or "")
    if maxWidth <= 0 then return "" end
    if textWidth(value, font) <= maxWidth then return value end

    local suffix = "..."
    local result = ""
    local index = 1
    while index <= #value do
        local byte = string.byte(value, index)
        local length = byte < 0x80 and 1 or byte < 0xE0 and 2 or byte < 0xF0 and 3 or 4
        local nextIndex = math.min(#value + 1, index + length)
        local candidate = string.sub(value, 1, nextIndex - 1) .. suffix
        if textWidth(candidate, font) > maxWidth then break end
        result = string.sub(value, 1, nextIndex - 1)
        index = nextIndex
    end
    return result ~= "" and result .. suffix or ""
end

local function itemTexture(entry, ui)
    if not entry or not entry.id then return nil end
    local cache = ui.itemTextureCache or {}
    ui.itemTextureCache = cache
    local key = tostring(entry.id)
    if cache[key] ~= nil then return cache[key] or nil end
    local player = getSpecificPlayer(WLM.Client.playerNum)
    local item = WLM.findItem(player and player:getInventory(), entry.id)
        or WLM.findItem(WLM.Client.object and WLM.Client.object:getContainer(), entry.id)
    if not item then cache[key] = false; return nil end
    local ok, texture = pcall(function() return item:getTex() end)
    cache[key] = ok and texture or false
    return cache[key] or nil
end

local function groupEntries(profile)
    local groups = { clothes = {}, hands = {}, attached = {} }
    if not profile then return groups end

    for _, entry in ipairs(profile.worn or {}) do
        if not WLM.isBandageEntry(entry) and (WLM.settings().includeBags or entry.isBag ~= true) then
            groups.clothes[#groups.clothes + 1] = entry
        end
    end
    if WLM.settings().includeHands then
        groups.hands[#groups.hands + 1] = {
            id = profile.hands and profile.hands.primary and profile.hands.primary.id,
            name = profile.hands and profile.hands.primary and profile.hands.primary.name or WLM.text("IGUI_WLM_None", "Empty"),
            detail = WLM.text("IGUI_WLM_PrimaryShort", "Primary hand"),
        }
        groups.hands[#groups.hands + 1] = {
            id = profile.hands and profile.hands.secondary and profile.hands.secondary.id,
            name = profile.hands and profile.hands.secondary and profile.hands.secondary.name or WLM.text("IGUI_WLM_None", "Empty"),
            detail = WLM.text("IGUI_WLM_SecondaryShort", "Secondary hand"),
        }
    end
    if WLM.settings().includeKeyRing and profile.keyRing then
        local keyRing = {}
        for key, value in pairs(profile.keyRing) do keyRing[key] = value end
        keyRing.detail = WLM.text("IGUI_WLM_KeyRing", "Key ring | inventory")
        groups.hands[#groups.hands + 1] = keyRing
    end
    if WLM.settings().includeAttachments then
        for _, entry in ipairs(profile.attached or {}) do groups.attached[#groups.attached + 1] = entry end
    end
    return groups
end

local function roundCorners()
    if not ISWardrobeLoadoutsUI.roundCornerTextures then
        ISWardrobeLoadoutsUI.roundCornerTextures = {
            tl = getTexture("media/ui/WLM_RoundTL.png"),
            tr = getTexture("media/ui/WLM_RoundTR.png"),
            bl = getTexture("media/ui/WLM_RoundBL.png"),
            br = getTexture("media/ui/WLM_RoundBR.png"),
        }
    end
    return ISWardrobeLoadoutsUI.roundCornerTextures
end

local function drawRoundedFill(self, x, y, width, height, color, radius)
    x, y = math.floor(x + 0.5), math.floor(y + 0.5)
    width, height = math.floor(width + 0.5), math.floor(height + 0.5)
    if width <= 0 or height <= 0 then return end
    radius = math.max(0, math.min(math.floor(radius + 0.5), math.floor(width / 2), math.floor(height / 2)))
    if radius < 1 then
        self:drawRect(x, y, width, height, color.a, color.r, color.g, color.b)
        return
    end
    self:drawRect(x + radius, y, width - radius * 2, height, color.a, color.r, color.g, color.b)
    self:drawRect(x, y + radius, width, height - radius * 2, color.a, color.r, color.g, color.b)
    local corners = roundCorners()
    self:drawTextureScaled(corners.tl, x, y, radius, radius, color.a, color.r, color.g, color.b)
    self:drawTextureScaled(corners.tr, x + width - radius, y, radius, radius, color.a, color.r, color.g, color.b)
    self:drawTextureScaled(corners.bl, x, y + height - radius, radius, radius, color.a, color.r, color.g, color.b)
    self:drawTextureScaled(corners.br, x + width - radius, y + height - radius, radius, radius, color.a, color.r, color.g, color.b)
end

local function drawRoundedRect(self, x, y, width, height, fill, border, radius, borderWidth)
    borderWidth = borderWidth or 1
    if border then drawRoundedFill(self, x, y, width, height, border, radius) end
    local inset = border and borderWidth or 0
    drawRoundedFill(self, x + inset, y + inset, width - inset * 2, height - inset * 2, fill, math.max(0, radius - inset))
end

ISWardrobeLoadoutsUI = ISPanel:derive("ISWardrobeLoadoutsUI")
WLM.UI = ISWardrobeLoadoutsUI

local function text(key, fallback)
    return WLM.text(key, fallback)
end

local function setButtonStyle(button, primary)
    button.backgroundColor = primary and { r = 0.79, g = 0.56, b = 0.24, a = 1 } or { r = 0.19, g = 0.20, b = 0.20, a = 1 }
    button.backgroundColorMouseOver = primary and { r = 0.88, g = 0.65, b = 0.31, a = 1 } or { r = 0.26, g = 0.27, b = 0.26, a = 1 }
    button.backgroundColorPressed = { r = 0.14, g = 0.15, b = 0.15, a = 1 }
    button.borderColor = { r = primary and 0.88 or 0.39, g = primary and 0.68 or 0.40, b = primary and 0.36 or 0.38, a = 1 }
    button.textColor = primary and { r = 0.12, g = 0.11, b = 0.09, a = 1 } or colors.text
    button.textColor2 = button.textColor
    button.prerender = function(self)
        local fill = self.backgroundColor
        if self.pressed then
            fill = self.backgroundColorPressed
        elseif self.mouseOver and self.enable then
            fill = self.backgroundColorMouseOver
        end
        drawRoundedRect(self, 0, 0, self.width, self.height, fill, self.borderColor, 10 * ((self.parent and self.parent.uiScale) or 1))
        if self.updateTooltip then self:updateTooltip() end
    end
end

ISWLMNameDialog = ISPanel:derive("ISWLMNameDialog")

function ISWLMNameDialog:createChildren()
    self.nameEntry = ISTextEntryBox:new("", 0, 0, 100, 30)
    self.nameEntry:initialise()
    self.nameEntry.placeholderText = text("IGUI_WLM_NamePlaceholder", "Name this loadout")
    self.nameEntry.backgroundColor = { r = colors.input.r, g = colors.input.g, b = colors.input.b, a = 0 }
    self.nameEntry.borderColor = { r = colors.border.r, g = colors.border.g, b = colors.border.b, a = 0 }
    self.nameEntry.background = false
    self.nameEntry.drawBorder = false
    self:addChild(self.nameEntry)

    self.cancelButton = ISButton:new(0, 0, 80, 32, text("IGUI_WLM_Cancel", "Cancel"), self, ISWLMNameDialog.cancel)
    self.saveButton = ISButton:new(0, 0, 80, 32, text("IGUI_WLM_Save", "Save"), self, ISWLMNameDialog.confirm)
    self.cancelButton:initialise()
    self.saveButton:initialise()
    setButtonStyle(self.cancelButton, false)
    setButtonStyle(self.saveButton, true)
    self:addChild(self.cancelButton)
    self:addChild(self.saveButton)
end

function ISWLMNameDialog:layout()
    local scale = self.uiScale or 1
    local boxW, boxH = 380 * scale, 200 * scale
    local left = (self.width - boxW) / 2
    local top = (self.height - boxH) / 2
    self.nameEntry:setX(left + 18 * scale)
    self.nameEntry:setY(top + 74 * scale)
    self.nameEntry:setWidth(boxW - 36 * scale)
    self.nameEntry:setHeight(34 * scale)
    self.nameEntry.font = UIFont.Small
    if self.nameEntry.javaObject then self.nameEntry.javaObject:setCentreVertically(true) end
    self.cancelButton:setX(left + boxW - 180 * scale)
    self.cancelButton:setY(top + 142 * scale)
    self.cancelButton:setWidth(76 * scale)
    self.cancelButton:setHeight(32 * scale)
    self.saveButton:setX(left + boxW - 94 * scale)
    self.saveButton:setY(top + 142 * scale)
    self.saveButton:setWidth(76 * scale)
    self.saveButton:setHeight(32 * scale)
end

function ISWLMNameDialog:prerender()
    ISPanel.prerender(self)
    local scale = self.uiScale or 1
    local boxW, boxH = 380 * scale, 200 * scale
    local left = (self.width - boxW) / 2
    local top = (self.height - boxH) / 2
    self:drawRect(0, 0, self.width, self.height, 0.62, 0, 0, 0)
    drawRoundedRect(self, left, top, boxW, boxH, colors.panel, colors.border, 16 * scale)
    drawRoundedRect(self, self.nameEntry.x, self.nameEntry.y, self.nameEntry.width, self.nameEntry.height, colors.input, colors.border, 10 * scale)
    self:drawText(text("IGUI_WLM_RenameTitle", "Rename loadout"), left + 18 * scale, top + 18 * scale, colors.text.r, colors.text.g, colors.text.b, 1, UIFont.Medium)
    self:drawText(text("IGUI_WLM_Name", "Loadout name"), left + 18 * scale, top + 54 * scale, colors.muted.r, colors.muted.g, colors.muted.b, 1, UIFont.Small)
end

function ISWLMNameDialog:confirm()
    if WLM.Client.renameProfile(self.renameId, self.nameEntry:getText(), self.renameSlot) then self:setVisible(false) end
end

function ISWLMNameDialog:cancel()
    self:setVisible(false)
end

function ISWardrobeLoadoutsUI:createChildren()
    self.slotInterface = 6
    self.closeButton = ISButton:new(0, 0, 28, 25, "X", self, ISWardrobeLoadoutsUI.close)
    self.closeButton:initialise()
    setButtonStyle(self.closeButton, false)
    self:addChild(self.closeButton)

    self.list = ISScrollingListBox:new(0, 0, 100, 100)
    self.list:initialise()
    self.list.itemheight = 56
    self.list.background = false
    self.list.drawBorder = false
    self.list.backgroundColor = { r = colors.listBackground.r, g = colors.listBackground.g, b = colors.listBackground.b, a = 0 }
    self.list.borderColor = colors.border
    self.list:setOnMouseDownFunction(self, ISWardrobeLoadoutsUI.onSelectSet)
    self.list:setOnMouseDoubleClick(self, ISWardrobeLoadoutsUI.onDoubleClickSlot)
    self.list.onMouseDoubleClick = function(list, x, y)
        local index = list:rowAt(x, y)
        if index < 1 or index > #list.items then return end
        if not list:isMouseOverScrollBar() then list.selected = index end
        return ISScrollingListBox.onMouseDoubleClick(list, x, y)
    end
    self.list.doDrawItem = ISWardrobeLoadoutsUI.drawSetItem
    self:addChild(self.list)

    self.groupLists = {}
    for _, key in ipairs({ "clothes", "hands", "attached" }) do
        local list = ISScrollingListBox:new(0, 0, 100, 100)
        list:initialise()
        list.background = false
        list.drawBorder = false
        list.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
        list.font = UIFont.Small
        list.wlmOwner = self
        list.wlmGroup = key
        list.doDrawItem = ISWardrobeLoadoutsUI.drawEquipmentItem
        list.updateTooltip = function(owner)
            ISScrollingListBox.updateTooltip(owner)
            if owner.tooltipUI then owner.tooltipUI.maxLineWidth = 420 end
        end
        self.groupLists[key] = list
        self:addChild(list)
    end

    self.saveButton = ISButton:new(0, 0, 100, 30, text("IGUI_WLM_StoreSlot", "Store in slot"), self, ISWardrobeLoadoutsUI.storeSelected)
    self.updateButton = ISButton:new(0, 0, 100, 30, text("IGUI_WLM_Rename", "Rename"), self, ISWardrobeLoadoutsUI.openRenameDialog)
    self.deleteButton = ISButton:new(0, 0, 100, 30, text("IGUI_WLM_TakeSlot", "Take"), self, ISWardrobeLoadoutsUI.takeSelected)
    self.applyButton = ISButton:new(0, 0, 100, 30, text("IGUI_WLM_SwapSlot", "Swap"), self, ISWardrobeLoadoutsUI.applySelected)
    for _, button in ipairs({ self.saveButton, self.updateButton, self.deleteButton, self.applyButton }) do
        button:initialise()
        setButtonStyle(button, button == self.applyButton)
        self:addChild(button)
    end
    self.saveButton:setVisible(false)
    self.saveButton.tooltip = text("IGUI_WLM_StoreTip", "Move your current equipment into the selected empty slot.")
    self.deleteButton.tooltip = text("IGUI_WLM_TakeTip", "Equip this set and empty its slot. Replaced equipment stays in your inventory.")
    self.applyButton.tooltip = text("IGUI_WLM_SwapTip", "Equip this set and store your current equipment in the same slot.")
    self.infoButton = ISButton:new(0, 0, 24, 24, "?", self, ISWardrobeLoadoutsUI.showHelp)
    self.infoButton:initialise()
    setButtonStyle(self.infoButton, false)
    self.infoButton.tooltip = text("IGUI_WLM_FooterNote", "Shared rules: Sandbox Options | Interface scale: Mod Options")
    self:addChild(self.infoButton)

    self.iconButton = ISButton:new(0, 0, 80, 29, text("IGUI_WLM_Icon", "Icon"), self, ISWardrobeLoadoutsUI.openIconPicker)
    self.scaleDownButton = ISButton:new(0, 0, 24, 24, "-", self, ISWardrobeLoadoutsUI.shrink)
    self.scaleUpButton = ISButton:new(0, 0, 24, 24, "+", self, ISWardrobeLoadoutsUI.grow)
    for _, button in ipairs({ self.iconButton, self.scaleDownButton, self.scaleUpButton }) do
        button:initialise()
        setButtonStyle(button, false)
        self:addChild(button)
    end

    self.saveDialog = ISWLMNameDialog:new(0, 0, self.width, self.height)
    self.saveDialog.uiScale = self.uiScale or 1
    self.saveDialog.parent = self
    self.saveDialog:initialise()
    self.saveDialog:setVisible(false)
    self:addChild(self.saveDialog)

    self.message = nil
    self.messageIsError = false
    self:layoutChildren()
    self:refresh()
end

function ISWardrobeLoadoutsUI:initialise()
    ISPanel.initialise(self)
end

local function layoutList(list, x, y, width, height, rowHeight)
    list:setX(x)
    list:setY(y)
    list:setWidth(width)
    list:setHeight(height)
    list.itemheight = rowHeight
    if list.vscroll then
        list.vscroll:setAnchorLeft(true)
        list.vscroll:setAnchorRight(false)
        list.vscroll:setAnchorTop(true)
        list.vscroll:setAnchorBottom(false)
        list.vscroll:setX(width - 17)
        list.vscroll:setY(0)
        list.vscroll:setWidth(17)
        list.vscroll:setHeight(height)
        list.vscroll.background = false
        list.vscroll.borderColor = { r = 0.25, g = 0.26, b = 0.25, a = 0.3 }
        list.vscroll.prerender = function(bar)
            local owner = bar.parent
            if bar:getX() ~= owner:getWidth() - 17 then bar:setX(owner:getWidth() - 17) end
            if bar:getY() ~= 0 then bar:setY(0) end
            if bar:getHeight() ~= owner:getHeight() then bar:setHeight(owner:getHeight()) end
        end
    end
end

function ISWardrobeLoadoutsUI:layoutChildren()
    local scale = self.uiScale or 1
    local pad = 18 * scale
    self.sidebarW = 290 * scale
    self.detailX = self.sidebarW + 20 * scale
    self.detailW = self.width - self.detailX - pad
    self.footerY = self.height - 66 * scale
    self.settingsY = self.footerY + 2 * scale
    local fontHeight = 16
    if getTextManager then
        local ok, height = pcall(function() return getTextManager():getFontHeight(UIFont.Small) end)
        if ok and tonumber(height) then fontHeight = height end
    end
    local buttonSize = math.ceil(math.max(24 * scale, fontHeight + 8))
    local buttonGap = math.ceil(math.max(6, 8 * scale))
    for index, button in ipairs({ self.closeButton, self.infoButton, self.scaleUpButton, self.scaleDownButton }) do
        button:setX(math.floor(self.width - pad - buttonSize - (index - 1) * (buttonSize + buttonGap)))
        button:setY(math.floor(38 * scale - buttonSize / 2 + 0.5))
        button:setWidth(buttonSize)
        button:setHeight(buttonSize)
    end
    self.headerButtonsLeft = self.scaleDownButton.x
    self.iconButton:setWidth(76 * scale)
    self.iconButton:setHeight(29 * scale)
    self.iconButton:setY(91 * scale)
    layoutList(self.list, pad, 117 * scale, self.sidebarW - pad, self.settingsY - 132 * scale, 68 * scale)
    self.saveButton:setX(pad)
    self.saveButton:setY(self.settingsY - 46 * scale)
    self.saveButton:setWidth(self.sidebarW - pad)
    self.saveButton:setHeight(36 * scale)
    local applyW, takeW = 178 * scale, 116 * scale
    self.applyButton:setX(self.width - pad - applyW)
    self.applyButton:setY(self.footerY + 17 * scale)
    self.applyButton:setWidth(applyW)
    self.applyButton:setHeight(34 * scale)
    self.deleteButton:setX(self.applyButton.x - 10 * scale - takeW)
    self.deleteButton:setY(self.applyButton.y)
    self.deleteButton:setWidth(takeW)
    self.deleteButton:setHeight(34 * scale)
    self.updateButton:setX(self.detailX + 120 * scale)
    self.updateButton:setY(91 * scale)
    self.updateButton:setWidth(96 * scale)
    self.updateButton:setHeight(29 * scale)
    local topY = 149 * scale
    local gap = 10 * scale
    local totalH = self.settingsY - topY - 14 * scale
    local rowH = math.max(34 * scale, 34)
    local handRowH = math.max(25 * scale, 25)
    local groups = self.equipmentGroups or { clothes = {}, hands = {}, attached = {} }
    local handsH = 42 * scale + math.max(1, #groups.hands) * handRowH
    local remaining = totalH - handsH - gap * 2
    local clothesWeight = math.max(3, #groups.clothes)
    local attachedWeight = math.max(3, #groups.attached)
    local clothesH = math.max(95 * scale, math.min(remaining - 95 * scale, remaining * clothesWeight / (clothesWeight + attachedWeight)))
    self.groups = {
        clothes = { x = self.detailX, y = topY, w = self.detailW, h = clothesH },
        hands = { x = self.detailX, y = topY + clothesH + gap, w = self.detailW, h = handsH },
        attached = { x = self.detailX, y = topY + clothesH + handsH + gap * 2, w = self.detailW, h = remaining - clothesH },
    }
    for key, box in pairs(self.groups) do
        layoutList(self.groupLists[key], box.x + 8 * scale, box.y + 33 * scale, box.w - 16 * scale, box.h - 39 * scale, key == "hands" and handRowH or rowH)
    end
    if self.saveDialog then
        self.saveDialog.uiScale = scale
        self.saveDialog:setWidth(self.width)
        self.saveDialog:setHeight(self.height)
        self.saveDialog:layout()
    end
end

function ISWardrobeLoadoutsUI:open()
    local preferredScale = WLM.Options and WLM.Options.uiScale and WLM.Options.uiScale() or 1
    local core = getCore()
    local screenW, screenH = core:getScreenWidth(), core:getScreenHeight()
    local scale = math.min(preferredScale, (screenW - 24) / 980, (screenH - 24) / 780)
    self.uiScale = math.max(0.55, scale)
    self:setWidth(math.floor(980 * self.uiScale))
    self:setHeight(math.floor(780 * self.uiScale))
    self:setX((screenW - self.width) / 2)
    self:setY((screenH - self.height) / 2)
    self:addToUIManager()
    self.removed = false
    self:layoutChildren()
    self:setVisible(true)
    self:setForceCursorVisible(true)
    self:refresh()
    WLM.Cursor.sync(true)
end

function ISWardrobeLoadoutsUI:prerender()
    ISPanel.prerender(self)
    local scale = self.uiScale or 1
    drawRoundedRect(self, 0, 0, self.width, self.height, colors.background, colors.border, 18 * scale)
    self:drawRect(18 * scale, 76 * scale, self.width - 36 * scale, 1, 0.5, colors.accent.r, colors.accent.g, colors.accent.b)
    self:drawRect(18 * scale, self.footerY, self.width - 36 * scale, 1, 0.5, colors.accent.r, colors.accent.g, colors.accent.b)
    local groups = self.equipmentGroups or { clothes = {}, hands = {}, attached = {} }
    self:drawGroup(text("IGUI_WLM_Worn", "Clothing and bags"), groups.clothes, self.groups.clothes)
    self:drawGroup(text("IGUI_WLM_HandsEquipment", "Hands and equipment"), groups.hands, self.groups.hands)
    self:drawGroup(text("IGUI_WLM_AttachedTools", "Attached weapons and tools"), groups.attached, self.groups.attached)
end

function ISWardrobeLoadoutsUI:render()
    ISPanel.render(self)
    if (self.saveDialog and self.saveDialog:getIsVisible()) or (self.iconDialog and self.iconDialog:getIsVisible()) then return end
    local scale = self.uiScale or 1
    local data = WLM.Client.data or WLM.Client.getData()
    local profile = data and data.sets and data.sets[tostring(self.selectedId)]
    local player = getSpecificPlayer(WLM.Client.playerNum)
    local active = profile and tostring(profile.id) == tostring(WLM.getActiveId(data, player))
    local reachText = self.inReach and text("IGUI_WLM_Reach", "IN REACH") or text("IGUI_WLM_OutOfReach", "OUT OF REACH")
    local reachX = self.headerButtonsLeft - textWidth(reachText, UIFont.Small) - 12 * scale
    self:drawText(fitText(text("IGUI_WLM_Title", "Wardrobe Loadouts"):upper(), UIFont.Medium, reachX - 36 * scale), 24 * scale, 20 * scale, colors.text.r, colors.text.g, colors.text.b, 1, UIFont.Medium)
    self:drawText(text("IGUI_WLM_ManagerSubtitle", "Manage your equipment sets"), 25 * scale, 46 * scale, colors.muted.r, colors.muted.g, colors.muted.b, 1, UIFont.Small)
    local reachColor = self.inReach and { r = 0.36, g = 0.80, b = 0.46 } or { r = 0.95, g = 0.42, b = 0.35 }
    self:drawText(reachText, reachX, 28 * scale, reachColor.r, reachColor.g, reachColor.b, 1, UIFont.Small)
    self:drawText(text("IGUI_WLM_Sets", "LOADOUTS"), 18 * scale, 94 * scale, colors.muted.r, colors.muted.g, colors.muted.b, 1, UIFont.Small)
    self:drawText(tostring(WLM.countSets(data)) .. " / " .. tostring(WLM.slotLimit(WLM.Client.object:getContainer())), self.sidebarW - 50 * scale, 94 * scale, colors.muted.r, colors.muted.g, colors.muted.b, 1, UIFont.Small)
    local title = WLM.slotName(data, self.selectedSlot or 1)
    local titleWidth = math.max(0, self.updateButton.x - self.detailX - 12 * scale)
    self:drawText(fitText(title, UIFont.Medium, titleWidth), self.detailX, 94 * scale, colors.text.r, colors.text.g, colors.text.b, 1, UIFont.Medium)
    local summary = not data and text("IGUI_WLM_Loading", "Loading wardrobe data...")
        or profile and tostring(#WLM.profileItems(profile)) .. " " .. text("IGUI_WLM_SavedItems", "saved items")
        or text("IGUI_WLM_EmptySlotHint", "Empty slot - store your current equipment here")
    self:drawText(fitText(summary, UIFont.Small, self.detailW - 110 * scale), self.detailX, 124 * scale, colors.muted.r, colors.muted.g, colors.muted.b, 1, UIFont.Small)
    local status = not profile and text("IGUI_WLM_EmptySlot", "EMPTY") or active and text("IGUI_WLM_Active", "ACTIVE") or text("IGUI_WLM_Stored", "STORED")
    self:drawText(fitText(status, UIFont.Small, 110 * scale), self.width - 128 * scale, 93 * scale, colors.accent.r, colors.accent.g, colors.accent.b, 1, UIFont.Small)
    local message = self.message
    local error = self.messageIsError
    if not message and (self.preview and self.preview.missing or 0) > 0 then
        message = string.format(text("IGUI_WLM_MissingCount", "%d missing item(s) - restore them before equipping"), self.preview.missing)
        error = true
    end
    if message then
        local c = error and { r = 0.95, g = 0.42, b = 0.35 } or colors.muted
        self:drawText(fitText(message, UIFont.Small, self.deleteButton.x - 36 * scale), 18 * scale, self.footerY + 24 * scale, c.r, c.g, c.b, 1, UIFont.Small)
    end
end

function ISWardrobeLoadoutsUI:drawGroup(title, entries, box)
    local scale = self.uiScale or 1
    drawRoundedRect(self, box.x, box.y, box.w, box.h, colors.panel, colors.border, 12 * scale)
    local count = 0
    for _, entry in ipairs(entries) do if entry.id then count = count + 1 end end
    self:drawText(title, box.x + 12 * scale, box.y + 9 * scale, colors.text.r, colors.text.g, colors.text.b, 1, UIFont.Small)
    self:drawText(tostring(count), box.x + box.w - 32 * scale, box.y + 9 * scale, colors.muted.r, colors.muted.g, colors.muted.b, 1, UIFont.Small)
    self:drawRect(box.x + 12 * scale, box.y + 29 * scale, box.w - 24 * scale, 1, 1, 0.23, 0.24, 0.23)
    if #entries == 0 then
        self:drawText(text("IGUI_WLM_None", "Empty"), box.x + 14 * scale, box.y + 43 * scale, colors.muted.r, colors.muted.g, colors.muted.b, 1, UIFont.Small)
    end
end

function ISWardrobeLoadoutsUI:drawEquipmentItem(y, row)
    local ui = self.wlmOwner
    local scale = ui.uiScale or 1
    local entry = row.item
    local texture = itemTexture(entry, ui)
    if texture then self:drawTextureScaledAspect(texture, 5 * scale, y + 3 * scale, 23 * scale, 23 * scale, 1, 1, 1, 1) end
    local missing = entry.id and ui.missingIds and ui.missingIds[tonumber(entry.id)]
    local c = missing and { r = 0.95, g = 0.42, b = 0.35 } or entry.id and colors.text or colors.muted
    local width = self.width - 60 * scale - 17
    local name = entry.name or entry.fullType or text("IGUI_WLM_None", "Empty")
    if self.wlmGroup == "hands" and entry.detail then name = entry.detail .. ": " .. name end
    self:drawText(fitText(name, UIFont.Small, width), 36 * scale, y + 1 * scale, c.r, c.g, c.b, 1, UIFont.Small)
    local detail = missing and text("IGUI_WLM_Missing", "MISSING") or entry.detail
    if not detail and entry.slotType then detail = tostring(entry.slotType) .. " | " .. tostring(entry.slotIndex) end
    if not detail and entry.isBag then detail = text("IGUI_WLM_Bag", "BAG") end
    if detail and self.wlmGroup ~= "hands" then self:drawText(fitText(detail, UIFont.Small, width), 36 * scale, y + 15 * scale, colors.muted.r, colors.muted.g, colors.muted.b, 1, UIFont.Small) end
    self:drawRect(36 * scale, y + row.height - 1, math.max(0, width), 1, 0.6, colors.border.r, colors.border.g, colors.border.b)
    return y + row.height
end

function ISWardrobeLoadoutsUI:drawSetItem(y, row)
    local scale = self.target.uiScale or 1
    local id = row.item and row.item.id
    local profile = WLM.Client.data and WLM.Client.data.sets and WLM.Client.data.sets[tostring(id)]
    local empty = not profile
    if empty then profile = { name = WLM.slotName(WLM.Client.data, row.item.slot) } end

    local selected = self.selected == row.index
    local player = getSpecificPlayer(WLM.Client.playerNum)
    local activeId = WLM.getActiveId(WLM.Client.data, player)
    if selected then
        local fill = { r = 0.21, g = 0.20, b = 0.17, a = 1 }
        drawRoundedRect(self, 0, y, self:getWidth() - 17, row.height - 2 * scale, fill, nil, 12 * scale)
        self:drawRect(0, y, 12 * scale, row.height - 2 * scale, 1, fill.r, fill.g, fill.b)
        self:drawRect(0, y, 3 * scale, row.height - 2 * scale, 1, colors.accent.r, colors.accent.g, colors.accent.b)
    elseif self.mouseoverselected == row.index and self:isMouseOver() and not self:isMouseOverScrollBar() then
        drawRoundedRect(self, 0, y, self:getWidth() - 17, row.height - 2 * scale, { r = 0.22, g = 0.23, b = 0.22, a = 1 }, nil, 12 * scale)
    else
        drawRoundedRect(self, 0, y, self:getWidth() - 17, row.height - 2 * scale, { r = 0.15, g = 0.16, b = 0.155, a = 1 }, nil, 12 * scale)
    end
    local entries = groupEntries(empty and nil or profile)
    local icons = {}
    for _, entry in ipairs(entries.attached) do icons[#icons + 1] = entry end
    for _, entry in ipairs(entries.clothes) do icons[#icons + 1] = entry end
    local data = WLM.Client.data
    local customIcon = data and data.slotIcons and data.slotIcons[tostring(row.item.slot)]
    local texture = customIcon and getTexture(customIcon) or icons[1] and itemTexture(icons[1], self.target)
    if texture then self:drawTextureScaledAspect(texture, 10 * scale, y + 17 * scale, 28 * scale, 28 * scale, 1, 1, 1, 1)
    else self:drawText(empty and "+" or tostring(row.item.slot), 18 * scale, y + 23 * scale, colors.accent.r, colors.accent.g, colors.accent.b, 1, UIFont.Small) end
    local contentW = self.width - 72 * scale - 17
    self:drawText(fitText(profile.name, UIFont.Small, contentW), 48 * scale, y + 8 * scale, colors.text.r, colors.text.g, colors.text.b, 1, UIFont.Small)
    local count = #WLM.profileItems(profile)
    local subtitle = empty and text("IGUI_WLM_EmptySlot", "EMPTY") or tostring(count) .. " " .. text("IGUI_WLM_ItemsShort", "items")
    self:drawText(subtitle, 48 * scale, y + 25 * scale, colors.muted.r, colors.muted.g, colors.muted.b, 1, UIFont.Small)
    local names = {}
    for index = 1, math.min(2, #icons) do names[#names + 1] = icons[index].name or icons[index].fullType or "" end
    self:drawText(fitText(table.concat(names, " / "), UIFont.Small, contentW), 48 * scale, y + 44 * scale, colors.muted.r, colors.muted.g, colors.muted.b, 1, UIFont.Small)
    return y + row.height
end

function ISWardrobeLoadoutsUI:refresh()
    if not self.list then return end
    self.itemTextureCache = {}
    self.languageCode = WLM.Options and WLM.Options.languageCode and WLM.Options.languageCode()
    self.updateButton:setTitle(text("IGUI_WLM_Rename", "Rename"))
    self.iconButton:setTitle(text("IGUI_WLM_Icon", "Icon"))
    self.deleteButton:setTitle(text("IGUI_WLM_TakeSlot", "Take"))
    self.saveDialog.cancelButton:setTitle(text("IGUI_WLM_Cancel", "Cancel"))
    self.saveDialog.saveButton:setTitle(text("IGUI_WLM_Confirm", "Confirm"))
    self.saveButton.tooltip = text("IGUI_WLM_StoreTip", "Move your current equipment into the selected empty slot.")
    self.deleteButton.tooltip = text("IGUI_WLM_TakeTip", "Equip this set and empty its slot. Replaced equipment stays in your inventory.")
    self.infoButton.tooltip = text("IGUI_WLM_FooterNote", "Shared rules: Sandbox Options | Interface scale: Mod Options")
    local selectedSlot = self.selectedSlot or 1
    local oldSlotScroll = self.list:getYScroll()
    self.list:clear()
    local data = WLM.Client.data or WLM.Client.getData()
    local player = getSpecificPlayer(WLM.Client.playerNum)
    local activeId = WLM.getActiveId(data, player)
    local slots, count = WLM.slots(data, WLM.Client.object:getContainer())
    for slot = 1, count do
        self.list:addItem("", { slot = slot, id = slots[slot] and slots[slot].id }, WLM.slotName(data, slot))
    end
    self.list:setYScroll(oldSlotScroll)
    self.selectedSlot = math.min(selectedSlot, count)
    self.selectedId = slots[self.selectedSlot] and slots[self.selectedSlot].id
    self.list.selected = self.selectedSlot
    local profile = data and data.sets and data.sets[tostring(self.selectedId)]
    self.equipmentGroups = groupEntries(profile)
    self:layoutChildren()
    self:layoutRenameButton()
    for key, list in pairs(self.groupLists or {}) do
        local oldScroll = self.lastPreviewSlot == self.selectedSlot and list:getYScroll() or 0
        list:clear()
        for _, entry in ipairs(self.equipmentGroups[key]) do
            local tip = tostring(entry.name or entry.fullType or text("IGUI_WLM_None", "Empty"))
            if entry.detail then tip = tip .. " <LINE> " .. entry.detail end
            list:addItem("", entry, tip)
        end
        list:setYScroll(math.max(math.min(0, oldScroll), math.min(0, list.height - list:getScrollHeight())))
    end
    self.lastPreviewSlot = self.selectedSlot
    self:updatePreview()
end

function ISWardrobeLoadoutsUI:updatePreview()
    local data = WLM.Client.data or WLM.Client.getData()
    local player = getSpecificPlayer(WLM.Client.playerNum)
    local wardrobe = WLM.Client.object and WLM.Client.object:getContainer()
    local profile = data and data.sets and data.sets[tostring(self.selectedId)]
    local activeId = WLM.getActiveId(data, player)
    local active = profile and tostring(self.selectedId) == tostring(activeId)
    local current = player and WLM.Client.captureProfile(player, "Preview")
    local targetRoles, currentRoles = WLM.profileRoles(profile), WLM.profileRoles(current)
    local preview = { equip = 0, unequip = 0, retrieve = 0, store = 0, missing = 0 }
    self.missingIds = {}
    for id, roles in pairs(targetRoles) do
        local inventoryItem = WLM.findItem(player and player:getInventory(), id)
        local storedItem = WLM.findItem(wardrobe, id)
        if not inventoryItem and not storedItem then self.missingIds[id] = true; preview.missing = preview.missing + 1 end
        if storedItem then preview.retrieve = preview.retrieve + 1 end
        if (#roles > 1 or roles[1] ~= "keyring") and table.concat(roles, ";") ~= table.concat(currentRoles[id] or {}, ";") then preview.equip = preview.equip + 1 end
    end
    for id, roles in pairs(currentRoles) do
        if not targetRoles[id] then
            preview.store = preview.store + 1
            if #roles > 1 or roles[1] ~= "keyring" then preview.unequip = preview.unequip + 1 end
        end
    end
    self.preview = preview
    local busy = WLM.Client.pendingStore or WLM.Client.pendingStoreRequest or WLM.Client.pendingSwitch or WLM.Client.switchPendingRequest
    local foreignActive = profile and WLM.isSetActive(data, profile.id) and not active
    local canAccess = WLM.canAccessStorage(player, WLM.Client.object)
    self.inReach = canAccess
    local usable = not busy and data ~= nil and canAccess
    self.updateButton:setEnable(usable)
    self.iconButton:setEnable(usable)
    self.applyButton:setTitle(profile and not active and text("IGUI_WLM_SwapLoadout", "Swap loadout") or text("IGUI_WLM_StoreSlot", "Store"))
    self.applyButton:setEnable(usable and not foreignActive and preview.missing == 0 and (profile ~= nil or preview.store > 0))
    self.deleteButton:setEnable(usable and profile ~= nil and not active and not foreignActive and preview.missing == 0)
    self.saveButton:setEnable(usable and (not profile or active) and current ~= nil and #WLM.profileItems(current) > 0)
    if not profile or active then self.applyButton:setEnable(self.saveButton.enable) end
    self.applyButton.tooltip = (not profile or active) and self.saveButton.tooltip or text("IGUI_WLM_SwapTip", "Equip this set and store your current equipment in the same slot.")
    self:layoutRenameButton()
    self.nextPreviewAt = getTimestamp() + 1
end

function ISWardrobeLoadoutsUI:update()
    ISPanel.update(self)
    WLM.Cursor.sync(self:getIsVisible() and not self.removed)
    local languageCode = WLM.Options and WLM.Options.languageCode and WLM.Options.languageCode()
    if self:getIsVisible() and languageCode ~= self.languageCode then self:refresh() end
    if self:getIsVisible() and getTimestamp() >= (self.nextPreviewAt or 0) then self:updatePreview() end
end

function ISWardrobeLoadoutsUI:layoutRenameButton()
    local scale = self.uiScale or 1
    local data = WLM.Client.data or WLM.Client.getData()
    local title = WLM.slotName(data, self.selectedSlot or 1)
    self.updateButton:setWidth(math.max(96 * scale, textWidth(text("IGUI_WLM_Rename", "Rename"), UIFont.Small) + 16 * scale))
    self.iconButton:setWidth(math.max(76 * scale, textWidth(text("IGUI_WLM_Icon", "Icon"), UIFont.Small) + 16 * scale))
    local width = math.min(textWidth(title, UIFont.Medium), self.detailW - self.updateButton.width - self.iconButton.width - 148 * scale)
    self.updateButton:setX(self.detailX + math.max(0, width) + 12 * scale)
    self.iconButton:setX(self.updateButton.x + self.updateButton.width + 8 * scale)
end

function ISWardrobeLoadoutsUI:onDoubleClickSlot(row)
    if not row or (self.saveDialog and self.saveDialog:getIsVisible()) or (self.iconDialog and self.iconDialog:getIsVisible()) then return end
    self.selectedSlot = row.slot
    self:refresh()
    if self.applyButton.enable then self:applySelected() end
end

function ISWardrobeLoadoutsUI:onSelectSet(row)
    self.selectedSlot = row and row.slot or 1
    self.message = nil
    self:refresh()
end

function ISWardrobeLoadoutsUI:storeSelected()
    if not self.saveButton.enable then return end
    local player = getSpecificPlayer(WLM.Client.playerNum)
    local data = WLM.Client.data or WLM.Client.getData()
    local old = self.selectedId and data and data.sets[tostring(self.selectedId)]
    local profile = WLM.Client.captureProfile(player, WLM.slotName(data, self.selectedSlot))
    profile.slot = self.selectedSlot
    WLM.Client.saveProfile(profile, old and self.selectedId or nil)
end

function ISWardrobeLoadoutsUI:takeSelected()
    if self.deleteButton.enable and self.selectedId then WLM.Client.beginSwitch(self.selectedId, true, false) end
end

function ISWardrobeLoadoutsUI:setMessage(message, isError)
    self.message = message
    self.messageIsError = isError
end

function ISWardrobeLoadoutsUI:openRenameDialog()
    if not self.updateButton.enable then return end
    local data = WLM.Client.data or WLM.Client.getData()
    self.saveDialog.renameId = self.selectedId
    self.saveDialog.renameSlot = self.selectedSlot
    self.saveDialog.nameEntry:setText(WLM.slotName(data, self.selectedSlot))
    self.saveDialog:setVisible(true)
    self.saveDialog:bringToTop()
end

function ISWardrobeLoadoutsUI:openIconPicker()
    if not self.iconButton.enable then return end
    require "WardrobeLoadouts/IconPicker"
    WLM.IconPicker.show(self, self.selectedSlot, setButtonStyle, drawRoundedRect)
end

function ISWardrobeLoadoutsUI:shrink()
    if WLM.Options.adjustScale(-5) then self:removeFromUIManager(); self:open() end
end

function ISWardrobeLoadoutsUI:grow()
    if WLM.Options.adjustScale(5) then self:removeFromUIManager(); self:open() end
end

function ISWardrobeLoadoutsUI:showHelp()
    self.infoButton.tooltip = text("IGUI_WLM_FooterNote", "Shared rules: Sandbox Options | Interface scale: Mod Options")
end

function ISWardrobeLoadoutsUI:updateActive()
    local player = getSpecificPlayer(WLM.Client.playerNum)
    local data = WLM.Client.data or WLM.Client.getData()
    local activeId = WLM.getActiveId(data, player)
    local profile = data and data.sets and data.sets[tostring(activeId)]
    if not profile then return end
    WLM.Client.saveProfile(WLM.Client.captureProfile(player, profile.name), activeId)
end

function ISWardrobeLoadoutsUI:applySelected()
    if not self.applyButton.enable then return end
    local player = getSpecificPlayer(WLM.Client.playerNum)
    local activeId = WLM.getActiveId(WLM.Client.data, player)
    if not self.selectedId or tostring(self.selectedId) == tostring(activeId) then self:storeSelected()
    else WLM.Client.beginSwitch(self.selectedId, true, true) end
end

function ISWardrobeLoadoutsUI:deleteSelected()
    if self.selectedId then WLM.Client.deleteProfile(self.selectedId) end
end

function ISWardrobeLoadoutsUI:close()
    if self.iconDialog then self.iconDialog:close() end
    for _, list in ipairs({ self.list, self.groupLists.clothes, self.groupLists.hands, self.groupLists.attached }) do
        if list.tooltipUI then list.tooltipUI:setVisible(false); list.tooltipUI:removeFromUIManager() end
    end
    self:setVisible(false)
    self:setForceCursorVisible(false)
    WLM.Cursor.sync(false)
    self:removeFromUIManager()
    WLM.Client.window = self
end

function ISWardrobeLoadoutsUI:new()
    local scale = WLM.Options and WLM.Options.uiScale and WLM.Options.uiScale() or 1
    local o = ISPanel.new(self, 0, 0, math.floor(980 * scale), math.floor(780 * scale))
    o.uiScale = scale
    o.moveWithMouse = true
    o.background = false
    o.backgroundColor = colors.background
    o.borderColor = colors.border
    o.selectedId = nil
    return o
end
