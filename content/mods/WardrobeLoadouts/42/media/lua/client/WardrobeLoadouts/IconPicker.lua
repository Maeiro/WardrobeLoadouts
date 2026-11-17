require "WardrobeLoadouts/Shared"
require "ISUI/ISPanel"
require "ISUI/ISButton"
require "ISUI/ISTextEntryBox"
require "ISUI/ISScrollingListBox"

local WLM = WardrobeLoadouts
local Picker = ISPanel:derive("ISWLMIconPicker")
WLM.IconPicker = Picker
local catalogue

local function entries()
    if catalogue then return catalogue end
    catalogue = {}
    local seen = {}
    local items = getAllItems()
    for index = 0, items:size() - 1 do
        local item = items:get(index)
        if not item:getObsolete() and not item:isHidden() then
            local texture = item:getNormalTexture()
            local name = texture and texture:getName()
            if name and name ~= "Question_On" and not seen[name] then
                seen[name] = true
                local label = tostring(item:getDisplayName())
                catalogue[#catalogue + 1] = { icon = name, texture = texture, name = label, search = string.lower(label .. " " .. name) }
            end
        end
    end
    table.sort(catalogue, function(a,b) return a.search < b.search end)
    return catalogue
end

function Picker:filter()
    local query = string.lower(self.search:getText() or "")
    self.list:clear()
    local row = {}
    for _, entry in ipairs(entries()) do
        if query == "" or entry.search:find(query, 1, true) then
            row[#row + 1] = entry
            if #row == self.columns then self.list:addItem("", row); row = {} end
        end
    end
    if #row > 0 then self.list:addItem("", row) end
    self.list:setYScroll(0)
end

function Picker:createChildren()
    local scale = self.parent.uiScale or 1
    self.uiScale = scale
    local width, height = math.min(540 * scale, self.width - 24), math.min(590 * scale, self.height - 24)
    local left, top = (self.width - width) / 2, (self.height - height) / 2
    self.box = { x = left, y = top, width = width, height = height }
    self.search = ISTextEntryBox:new("", left + 14, top + 49, width - 28, 29)
    self.search:initialise()
    self.search:setPlaceholderText(WLM.text("IGUI_WLM_SearchIcons", "Search item icons..."))
    self.search.onTextChange = function(entry) entry.parent:filter() end
    self:addChild(self.search)
    self.list = ISScrollingListBox:new(left + 14, top + 90, width - 28, height - 219)
    self.list:initialise()
    self.list.itemheight = 46
    self.list.backgroundColor = { r = 0.07, g = 0.08, b = 0.08, a = 1 }
    self.columns = math.max(1, math.floor((self.list.width - 17) / 46))
    self.cellWidth = (self.list.width - 17) / self.columns
    self.list.doDrawItem = function(list, y, row)
        local picker = list.parent
        for column, entry in ipairs(row.item) do
            local x = (column - 1) * picker.cellWidth
            if entry.icon == picker.path:getText() then list:drawRect(x + 2, y + 2, picker.cellWidth - 4, row.height - 4, 1, 0.34, 0.29, 0.17) end
            list:drawTextureScaledAspect(entry.texture, x + 7, y + 6, picker.cellWidth - 14, 32, 1, 1, 1, 1)
        end
        return y + row.height
    end
    self.list:setOnMouseDownFunction(self, function(picker, row)
        local column = math.floor(picker.list:getMouseX() / picker.cellWidth) + 1
        local entry = row[column]
        if entry then picker.path:setText(entry.icon) end
    end)
    self.list.updateTooltip = function(list)
        local row = list.items[list.mouseoverselected or -1]
        if row then
            local entry = row.item[math.floor(list:getMouseX() / list.parent.cellWidth) + 1]
            row.tooltip = entry and entry.name
        end
        ISScrollingListBox.updateTooltip(list)
    end
    self:addChild(self.list)
    self.path = ISTextEntryBox:new("", left + 14, top + height - 87, width - 28, 29)
    self.path:initialise()
    self.path.onTextChange = function(entry) entry.parent.error = nil end
    self.path:setPlaceholderText(WLM.text("IGUI_WLM_TexturePath", "Texture name or path (optional)"))
    self:addChild(self.path)
    local buttonWidth = (width - 44) / 3
    local function button(index, label, callback)
        local control = ISButton:new(left + 14 + (index - 1) * (buttonWidth + 8), top + height - 45, buttonWidth, 30, label, self, callback)
        control:initialise()
        self.styleButton(control, index == 3)
        self:addChild(control)
        return control
    end
    button(1, WLM.text("IGUI_WLM_Automatic", "Automatic"), function(picker) picker.path:setText("") end)
    button(2, WLM.text("IGUI_WLM_Cancel", "Cancel"), function(picker) picker:close() end)
    button(3, WLM.text("IGUI_WLM_Confirm", "Confirm"), function(picker)
        local path = (picker.path:getText() or ""):gsub("^%s+", ""):gsub("%s+$", "")
        if WLM.Client.setSlotIcon(picker.slot, path) then picker:close()
        else picker.error = WLM.text("IGUI_WLM_ErrorIcon", "This texture could not be loaded.") end
    end)
end

function Picker:prerender()
    self:drawRect(0, 0, self.width, self.height, 0.75, 0, 0, 0)
    local box = self.box
    self.roundedRect(self, box.x, box.y, box.width, box.height,
        { r = 0.10, g = 0.12, b = 0.12, a = 1 },
        { r = 0.65, g = 0.49, b = 0.24, a = 1 }, 16 * self.uiScale)
    self:drawText(WLM.text("IGUI_WLM_SelectIcon", "Choose a slot icon"), box.x + 14, box.y + 14, 0.90, 0.88, 0.83, 1, UIFont.Medium)
    self:drawText(self.error or WLM.text("IGUI_WLM_TexturePath", "Texture name or path (optional)"), box.x + 14, box.y + box.height - 112, 0.85, 0.71, 0.57, 1, UIFont.Small)
end

function Picker:onMouseDown() return true end
function Picker:onMouseUp() return true end

function Picker:close()
    if self.list.tooltipUI then self.list.tooltipUI:setVisible(false); self.list.tooltipUI:removeFromUIManager() end
    self:setVisible(false)
end

function Picker.show(parent, slot, styleButton, roundedRect)
    if parent.iconDialog then parent.iconDialog:close(); parent:removeChild(parent.iconDialog) end
    local panel = ISPanel.new(Picker, 0, 0, parent.width, parent.height)
    panel.parent, panel.slot, panel.styleButton, panel.roundedRect = parent, slot, styleButton, roundedRect
    panel.background = false
    panel:initialise()
    parent.iconDialog = panel
    parent:addChild(panel)
    local data = WLM.Client.data or WLM.Client.getData()
    panel.path:setText(data and data.slotIcons and data.slotIcons[tostring(slot)] or "")
    panel:filter()
    panel:bringToTop()
end
