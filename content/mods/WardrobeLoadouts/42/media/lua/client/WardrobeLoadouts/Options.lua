require "WardrobeLoadouts/Shared"
require "WardrobeLoadouts/Locales"

local WLM = WardrobeLoadouts
WLM.Options = WLM.Options or {}

local languages = {
    { code = "EN", name = "English" }, { code = "ES", name = "Spanish" },
    { code = "FR", name = "French" }, { code = "DE", name = "German" },
    { code = "IT", name = "Italian" }, { code = "PT", name = "Portuguese (Portugal)" },
    { code = "PTBR", name = "Portuguese (Brazil)" }, { code = "RU", name = "Russian" },
    { code = "CN", name = "Chinese (Simplified)" }, { code = "UA", name = "Ukrainian" },
    { code = "KO", name = "Korean" }, { code = "JP", name = "Japanese" },
    { code = "TR", name = "Turkish" },
}
local options

local function label(key, fallback)
    return WLM.text(key, fallback)
end

local function registerOptions()
    if not PZAPI or not PZAPI.ModOptions then return end
    options = PZAPI.ModOptions:getOptions(WLM.ID)
    if not options then options = PZAPI.ModOptions:create(WLM.ID, label("IGUI_WLM_Title", "Wardrobe Loadouts")) end
    local languageOption = options:getOption("Language")
    if not languageOption then
        languageOption = options:addComboBox("Language", label("IGUI_WLM_Language", "Interface language"))
    end
    local selected = languageOption:getValue()
    languageOption.values = {}
    languageOption:addItem(label("IGUI_WLM_Automatic", "Automatic (game language)"))
    for _, language in ipairs(languages) do
        languageOption:addItem(language.name .. " [" .. language.code .. "]")
    end
    if languageOption.element then
        languageOption.element:clear()
        for _, name in ipairs(languageOption.values) do languageOption.element:addOption(name) end
    end
    languageOption:setValue(math.max(1, math.min(#languageOption.values, tonumber(selected) or 1)))
    local scaleOption = options:getOption("UIScale")
    local scaleLabel = label("IGUI_WLM_UIScale", "Manager scale")
    if not scaleOption then
        options:addSlider("UIScale", scaleLabel, 80, 130, 5, 100)
    else
        scaleOption.name = scaleLabel
    end
    if not options:getOption("DiagnosticLogs") then
        options:addTickBox("DiagnosticLogs", label("IGUI_WLM_DiagnosticLogs", "Diagnostic logs"), false)
    end
    local clientOptions = {
        { id = "IncludeHands", key = "IGUI_WLM_IncludeHands", fallback = "Save and switch hand items" },
        { id = "IncludeBags", key = "IGUI_WLM_IncludeBags", fallback = "Save and switch wearable bags" },
        { id = "IncludeAttachments", key = "IGUI_WLM_IncludeAttachments", fallback = "Save and restore attached items" },
        { id = "IncludeKeyRing", key = "IGUI_WLM_IncludeKeyRing", fallback = "Save and restore the key ring" },
    }
    local sandboxOptions = SandboxVars and SandboxVars.WardrobeLoadouts or {}
    for _, entry in ipairs(clientOptions) do
        if not options:getOption(entry.id) then
            options:addTickBox(entry.id, label(entry.key, entry.fallback), sandboxOptions[entry.id] ~= false)
        end
    end
end

local function preferenceEnabled(id)
    local option = options and options:getOption(id)
    return not option or option:getValue() == true
end

function WLM.Options.preferences()
    return {
        includeHands = preferenceEnabled("IncludeHands"),
        includeBags = preferenceEnabled("IncludeBags"),
        includeAttachments = preferenceEnabled("IncludeAttachments"),
        includeKeyRing = preferenceEnabled("IncludeKeyRing"),
    }
end

function WLM.Options.diagnosticsEnabled()
    local option = options and options:getOption("DiagnosticLogs")
    return option ~= nil and option:getValue() == true
end

function WLM.Options.uiScale()
    if not options or not options.getOption then return 1 end
    local ok, option = pcall(function() return options:getOption("UIScale") end)
    if not ok or not option or not option.getValue then return 1 end
    local valueOk, value = pcall(function() return option:getValue() end)
    if not valueOk then return 1 end
    return math.max(0.8, math.min(1.3, (tonumber(value) or 100) / 100))
end

function WLM.Options.languageCode()
    if not options then return nil end
    local option = options:getOption("Language")
    local index = option and tonumber(option:getValue()) or 1
    return languages[index - 1] and languages[index - 1].code or nil
end

function WLM.Options.adjustScale(step)
    if not options then return false end
    local option = options:getOption("UIScale")
    if not option then return false end
    option:setValue(math.max(80, math.min(130, math.floor(WLM.Options.uiScale() * 100 + 0.5) + step)))
    PZAPI.ModOptions:save()
    return true
end

registerOptions()
if Events and Events.OnGameBoot then Events.OnGameBoot.Add(registerOptions) end
