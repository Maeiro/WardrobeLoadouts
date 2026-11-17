require "WardrobeLoadouts/Shared"

local locales = {}
for _, code in ipairs({ "EN", "ES", "FR", "DE", "IT", "PT", "PTBR", "RU", "CN", "UA", "KO", "JP", "TR" }) do
    local prefix = "UI_WLM_Locale_" .. code .. "_"
    locales[code] = setmetatable({}, {
        __index = function(_, key)
            -- Keep format placeholders intact for the callers' Lua string.format.
            if Translator and Translator.getUI then return Translator.getUI():get(prefix .. key) end
            return getTextOrNull and getTextOrNull(prefix .. key) or nil
        end,
    })
end
WardrobeLoadouts.Locales = locales
