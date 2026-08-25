if AI_COMPANION_NAMESPACE_LOADED then return end
AI_COMPANION_NAMESPACE_LOADED = true
_G.AI_COMPANION_DEF = _G.AI_COMPANION_DEF or {}
local AI = _G.AI_COMPANION_DEF
AI.Core = AI.Core or {}
AI.Core.StealthMode = false
AI.Core.DefenderMode = false
AI.Core.MedicMode = false
AI.Core.PacifistMode = false
AI.Core.AggressiveMode = false
AI.Core.Disabled = false
AI.Core.Nick = "AI_Companion"
AI.Core.Model = "models/player/urban.mdl"
AI.TTS = AI.TTS or {}
AI.TTS.Enabled = false
AI.TTS.Global = false
AI.TTS.Active = 0
AI.TTS.IP = "127.0.0.1"
AI.TTS.Port = 8188
AI.TTS.Timeout = 120
AI.LLM = AI.LLM or {}
AI.LLM.Enabled = true
AI.LLM.IP = "127.0.0.1"
AI.LLM.Port = 1234
AI.LLM.Model = "local-model"
AI.LLM.Timeout = 60
AI.Weapons = AI.Weapons or {}
AI.Weapons.Combat = "weapon_smg1"
AI.Weapons.Melee = "weapon_crowbar"
AI.Weapons.Idle = "weapon_physgun"
AI.Appearance = AI.Appearance or {}
AI.Appearance.Prefix = AI.Appearance.Prefix or {}
AI.Appearance.Prefix.Text = "[AI]"
AI.Appearance.Prefix.Rainbow = false
AI.Appearance.Prefix.Color = AI.Appearance.Prefix.Color or {}
AI.Appearance.Prefix.Color.R = 255
AI.Appearance.Prefix.Color.G = 200
AI.Appearance.Prefix.Color.B = 0
AI.API = AI.API or {}
AI.Private = AI.Private or {}
AI.Config = AI.Config or {}
local function ProtectTable(tbl, name)
    if not tbl then return end
    local mt = getmetatable(tbl)
    if mt and mt.__metatable == false then
        return 
    end
    local new_mt = {
        __newindex = function(t, k, v)
            if type(k) == "string" and string.sub(k, 1, 1) == "_" then
                rawset(t, k, v)
                return
            end
            local info = debug.getinfo(2)
            local source = info and info.source or ""
            if source and string.find(source, "ai_companion") then
                rawset(t, k, v)
                return
            end
            error(string.format(
                "[AI Companion] Попытка изменить защищённую таблицу '%s.%s' извне!\nИсточник: %s",
                name or "AI_COMPANION_DEF",
                tostring(k),
                source or "неизвестно"
            ))
        end,
        __metatable = false,
    }
    setmetatable(tbl, new_mt)
end
ProtectTable(AI, "AI_COMPANION_DEF")
ProtectTable(AI.Core, "AI_COMPANION_DEF.Core")
ProtectTable(AI.TTS, "AI_COMPANION_DEF.TTS")
ProtectTable(AI.LLM, "AI_COMPANION_DEF.LLM")
ProtectTable(AI.Weapons, "AI_COMPANION_DEF.Weapons")
ProtectTable(AI.Appearance, "AI_COMPANION_DEF.Appearance")
ProtectTable(AI.Appearance.Prefix, "AI_COMPANION_DEF.Appearance.Prefix")
ProtectTable(AI.Appearance.Prefix.Color, "AI_COMPANION_DEF.Appearance.Prefix.Color")
ProtectTable(AI.API, "AI_COMPANION_DEF.API")
ProtectTable(AI.Private, "AI_COMPANION_DEF.Private")
ProtectTable(AI.Config, "AI_COMPANION_DEF.Config")
AI._loaded = true
AI._version = "0.7.0"
print("[AI Companion] ========================================")
print("[AI Companion] Защищённый неймспейс создан")
print("[AI Companion] Версия: " .. AI._version)
print("[AI Companion] ========================================")