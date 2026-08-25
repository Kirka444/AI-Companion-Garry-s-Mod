if AI_COMPANION_STATE_LOADED then return end
AI_COMPANION_STATE_LOADED = true
local registry = debug.getregistry()
local STORAGE_KEY = "__AI_COMPANION_STORAGE_v2"
registry[STORAGE_KEY] = registry[STORAGE_KEY] or {}
local storage = registry[STORAGE_KEY]
local function ProtectStorageTable(tbl, path, depth)
    if type(tbl) ~= "table" then return end
    if depth and depth > 10 then return end
    local existingMt = getmetatable(tbl)
    if existingMt == false then
        return
    end
    if existingMt and existingMt.__metatable == false then
        return
    end
    local mt = {
        __newindex = function(t, k, v)
            local info = debug.getinfo(2)
            local source = info and info.source or ""
            if source and (string.find(source, "ai_companion") or string.find(source, "ai_")) then
                rawset(t, k, v)
                return
            end
            if v == nil then
                rawset(t, k, v)
                return
            end
            ErrorNoHalt(string.format(
                "[AI Companion] ⛔ БЛОКИРОВКА! Попытка изменить %s.%s извне!\nИсточник: %s\n",
                path or "storage", tostring(k), source or "неизвестно"
            ))
        end,
        __metatable = false,
    }
    local ok, err = pcall(setmetatable, tbl, mt)
    if not ok then
        if AI_CONFIG and AI_CONFIG.DEBUG_MODE then
            print(string.format("[AI State] Пропуск защиты %s: %s", path or "?", tostring(err)))
        end
        return
    end
    local nextDepth = (depth or 0) + 1
    for k, v in pairs(tbl) do
        if type(v) == "table" and k ~= "_" then
            ProtectStorageTable(v, (path or "storage") .. "." .. tostring(k), nextDepth)
        end
    end
end
local function createProtectedProxy()
    local proxy = {}
    proxy._is_ai_companion = true
    proxy._version = "2.0.0"
    proxy._timestamp = os.time()
    setmetatable(proxy, {
        __index = function(t, k)
            if k == "_is_ai_companion" or k == "_version" or k == "_timestamp" then
                return rawget(t, k)
            end
            return storage[k]
        end,
        __newindex = function(t, k, v)
            if k == "_is_ai_companion" or k == "_version" or k == "_timestamp" then
                error("[AI Companion] Попытка перезаписать защищённый ключ: " .. k)
                return
            end
            storage[k] = v
        end,
        __metatable = false,
        __pairs = function(t)
            return pairs(storage)
        end,
        __len = function(t)
            return table.Count(storage)
        end
    })
    return proxy
end
if _G.AI_COMPANION and _G.AI_COMPANION._is_ai_companion then
    if _G.AI_COMPANION._version ~= "2.0.0" then
        ErrorNoHalt("[AI Companion] ВНИМАНИЕ! Несовместимая версия!\n")
    end
    local AC = _G.AI_COMPANION
    print("[AI Companion] Используется существующее хранилище (версия " .. AC._version .. ")")
else
    _G.AI_COMPANION = createProtectedProxy()
    print("[AI Companion] Создано новое защищённое хранилище")
end
local AC = _G.AI_COMPANION
local PROTECTED_GLOBALS = {
    "AI_COMPANION",
    "AI_COMPANION_DEF",
    "AI_CONFIG",
    "AI_SETTINGS",
    "AI",
}
do
    local mt = getmetatable(_G) or {}
    local oldNewIndex = mt.__newindex
    local oldIndex = mt.__index
    mt.__newindex = function(t, k, v)
        for _, protected in ipairs(PROTECTED_GLOBALS) do
            if k == protected then
                if v == _G[protected] or v == nil then
                    if oldNewIndex then return oldNewIndex(t, k, v) end
                    rawset(t, k, v)
                    return
                end
                local info = debug.getinfo(2)
                local source = info and info.source or "неизвестно"
                if source and (string.find(source, "ai_companion") or string.find(source, "ai_")) then
                    if oldNewIndex then return oldNewIndex(t, k, v) end
                    rawset(t, k, v)
                    return
                end
                ErrorNoHalt(string.format(
                    "[AI Companion] ⛔ БЛОКИРОВКА! Попытка перезаписать _G.%s!\nИсточник: %s\n",
                    k, source
                ))
                return
            end
        end
        if oldNewIndex then return oldNewIndex(t, k, v) end
        rawset(t, k, v)
    end
    mt.__index = function(t, k)
        for _, protected in ipairs(PROTECTED_GLOBALS) do
            if k == protected then
                if oldIndex then return oldIndex(t, k) end
                return rawget(t, k)
            end
        end
        if oldIndex then return oldIndex(t, k) end
        return rawget(t, k)
    end
    setmetatable(_G, mt)
end
local function DeepCopy(src, dst)
    if type(src) ~= "table" then 
        return src 
    end
    dst = dst or {}
    for k, v in pairs(src) do
        if type(v) == "table" then
            dst[k] = DeepCopy(v, {})
        else
            dst[k] = v
        end
    end
    return dst
end
if not storage.State then
    storage.State = {
        TTS_Enabled = false,
        TTS_Global = false,
        LLM_Enabled = true,
        Disabled = false,
        TTS_Active = 0,
        StealthMode = false,
        DefenderMode = false,
        MedicMode = false,
        PacifistMode = false,
        AggressiveMode = false,
    }
end
if not storage.Settings then
    storage.Settings = {
        LLM_IP = "127.0.0.1",
        LLM_Port = 1234,
        LLM_Model = "local-model",
        LLM_Mode = "local",
        LLM_Provider = "openai",
        LLM_API_Key = "",
        LLM_Cloud_Model = "",
        LLM_Endpoint = "",
        LLM_Temperature = 0.7,
        LLM_Max_Tokens = 100,
        LLM_Timeout = 60,
        TTS_IP = "127.0.0.1",
        TTS_Port = 8188,
        TTS_Timeout = 120,
        TTS_Mode = "local",
        TTS_Personal = true,
        TTS_Provider = "elevenlabs",
        TTS_API_Key = "",
        TTS_Voice = "",
        TTS_Language = "",
        TTS_Endpoint = "",
        TTS_Speed = 1.0,
        Yandex_Folder_ID = "",
        Yandex_Voice = "oksana",
        Yandex_Lang = "ru-RU",
        VK_Voice = "katherine",
        VK_Tempo = 1.0,
        Companion_Nick = "AI_Companion",
        Model_Path = "models/player/urban.mdl",
        Combat_Weapon = "weapon_smg1",
        Melee_Weapon = "weapon_crowbar",
        Idle_Weapon = "weapon_physgun",
        Prefix_Text = "[AI]",
        Prefix_Rainbow = false,
        Prefix_Color_R = 255,
        Prefix_Color_G = 200,
        Prefix_Color_B = 0,
        Show_Sender_Name = true,
        Debug_Mode = false,
        Auto_Sync_Global = true,
    }
end
if not _G.AI_SETTINGS then
    _G.AI_SETTINGS = storage.Settings
elseif _G.AI_SETTINGS ~= storage.Settings then
    for k, v in pairs(_G.AI_SETTINGS) do
        storage.Settings[k] = v
    end
    _G.AI_SETTINGS = storage.Settings
end
if not storage.Core then
    storage.Core = {
        Nick = "AI_Companion",
        Model = "models/player/urban.mdl",
        Version = "2.0.0",
        _loaded = true,
        _created = os.time(),
    }
end
if not storage.Config then
    storage.Config = {}
end
if not storage.Config.Network then
    storage.Config.Network = {
        LLM = {
            IP = storage.Settings.LLM_IP,
            Port = storage.Settings.LLM_Port,
            Model = storage.Settings.LLM_Model,
            Timeout = storage.Settings.LLM_Timeout,
            MaxTokens = storage.Settings.LLM_Max_Tokens,
            Temperature = storage.Settings.LLM_Temperature,
        },
        TTS = {
            IP = storage.Settings.TTS_IP,
            Port = storage.Settings.TTS_Port,
            Timeout = storage.Settings.TTS_Timeout,
        }
    }
end
if not storage.Config.Cache then
    storage.Config.Cache = {
        TTS = {
            Size = 50,
            TTL = 300,
        },
        LLM = {
            Size = 100,
            TTL = 600,
        }
    }
end
if not storage.Config.LLM then
    storage.Config.LLM = {
        MaxHistoryPairs = 10,
        MaxTTSConcurrent = 3,
    }
end
if not storage.Config.HTTP then
    storage.Config.HTTP = {
        DefaultTimeout = 30,
        RetryCount = 3,
        RetryDelay = 1,
    }
end
if not storage.Config.Chat then
    storage.Config.Chat = {
        MaxMessageLength = 500,
        MaxHistoryAge = 3600,
    }
end
if not storage.Config.Providers then
    storage.Config.Providers = {
        LLM = {
            Default = "openai",
            List = {"local", "openai", "deepseek", "anthropic", "google", "grok"},
            Defaults = {
                openai = {model = "gpt-4o", endpoint = "https://api.openai.com/v1/chat/completions"},
                deepseek = {model = "deepseek-chat", endpoint = "https://api.deepseek.com/v1/chat/completions"},
                anthropic = {model = "claude-3-sonnet-20240229", endpoint = "https://api.anthropic.com/v1/messages"},
                google = {model = "gemini-1.5-flash", endpoint = "https://generativelanguage.googleapis.com/v1beta/models"},
                grok = {model = "grok-2", endpoint = "https://api.x.ai/v1/chat/completions"},
            }
        },
        TTS = {
            Default = "elevenlabs",
            List = {"comfyui", "elevenlabs", "google", "yandex", "vk"},
            Defaults = {
                elevenlabs = {voice = "21m00Tcm4TlvDq8ikWAM", model = "eleven_multilingual_v2"},
                google = {voice = "ru-RU-Standard-A", language = "ru-RU"},
                yandex = {voice = "oksana", language = "ru-RU"},
                vk = {voice = "katherine", encoder = "mp3", tempo = 1.0},
            }
        }
    }
end
if not storage.Players then
    storage.Players = {
        PrefixText = {},
        PrefixColorR = {},
        PrefixColorG = {},
        PrefixColorB = {},
        PrefixRainbow = {},
    }
end
if not storage.Companion then
    storage.Companion = {
        States = {
            IDLE = "idle",
            FOLLOW = "following",
            COMBAT = "combat",
            VEHICLE = "vehicle",
            PROTECT = "protecting",
            PROTECT_VEHICLE = "protecting_vehicle",
            SITTING = "sitting",
            COVER = "cover",
            POINTING = "pointing",
        },
        FriendlyNPCs = {
            ["npc_citizen"] = true,
            ["npc_alyx"] = true,
            ["npc_barney"] = true,
            ["npc_dog"] = true,
            ["npc_magnusson"] = true,
            ["npc_kleiner"] = true,
            ["npc_eli"] = true,
            ["npc_monk"] = true,
            ["npc_vortigaunt"] = true,
            ["npc_fisherman"] = true,
            ["npc_odessa"] = true,
            ["npc_mossman"] = true,
            ["npc_breen"] = true,
        },
    }
    local States = storage.Companion.States
    storage.Companion.ValidTransitions = {
        [States.IDLE] = {
            [States.FOLLOW] = true,
            [States.COMBAT] = true,
            [States.SITTING] = true,
            [States.PROTECT] = true,
            [States.PROTECT_VEHICLE] = true,
            [States.POINTING] = true,
        },
        [States.FOLLOW] = {
            [States.IDLE] = true,
            [States.COMBAT] = true,
            [States.PROTECT] = true,
            [States.PROTECT_VEHICLE] = true,
            [States.VEHICLE] = true,
            [States.SITTING] = true,
            [States.COVER] = true,
            [States.POINTING] = true,
        },
        [States.COMBAT] = {
            [States.IDLE] = true,
            [States.FOLLOW] = true,
            [States.COVER] = true,
            [States.PROTECT] = true,
            [States.PROTECT_VEHICLE] = true,
        },
        [States.COVER] = {
            [States.COMBAT] = true,
            [States.FOLLOW] = true,
            [States.IDLE] = true,
        },
        [States.POINTING] = {
            [States.COMBAT] = true,
            [States.FOLLOW] = true,
            [States.IDLE] = true,
            [States.PROTECT] = true,
            [States.PROTECT_VEHICLE] = true,
        },
        [States.PROTECT] = {
            [States.COMBAT] = true,
            [States.FOLLOW] = true,
            [States.IDLE] = true,
        },
        [States.PROTECT_VEHICLE] = {
            [States.COMBAT] = true,
            [States.FOLLOW] = true,
            [States.IDLE] = true,
        },
        [States.SITTING] = {
            [States.FOLLOW] = true,
            [States.IDLE] = true,
            [States.VEHICLE] = true,
        },
        [States.VEHICLE] = {
            [States.FOLLOW] = true,
            [States.IDLE] = true,
            [States.COMBAT] = true,
            [States.SITTING] = true,
        },
    }
end
if not storage.Cache then
    storage.Cache = {
        LLM = nil,
        TTS = nil,
        Prefix = nil,
    }
end
if not storage.LLM then
    storage.LLM = {
        Enabled = storage.State.LLM_Enabled,
        IP = storage.Settings.LLM_IP,
        Port = storage.Settings.LLM_Port,
        Model = storage.Settings.LLM_Model,
        Timeout = storage.Settings.LLM_Timeout,
        MaxTokens = storage.Settings.LLM_Max_Tokens,
        Temperature = storage.Settings.LLM_Temperature,
    }
end
if not storage.Network then
    storage.Network = {
        LLM = {
            IP = storage.Settings.LLM_IP,
            Port = storage.Settings.LLM_Port,
            Model = storage.Settings.LLM_Model,
            Timeout = storage.Settings.LLM_Timeout,
            MaxTokens = storage.Settings.LLM_Max_Tokens,
            Temperature = storage.Settings.LLM_Temperature,
        },
        TTS = {
            IP = storage.Settings.TTS_IP,
            Port = storage.Settings.TTS_Port,
            Timeout = storage.Settings.TTS_Timeout,
        }
    }
end
if not storage.TTS then
    storage.TTS = {
        Enabled = storage.State.TTS_Enabled,
        Global = storage.State.TTS_Global,
        Active = 0,
        IP = storage.Settings.TTS_IP,
        Port = storage.Settings.TTS_Port,
        Timeout = storage.Settings.TTS_Timeout,
    }
end
if not storage.Weapons then
    storage.Weapons = {
        Combat = storage.Settings.Combat_Weapon,
        Melee = storage.Settings.Melee_Weapon,
        Idle = storage.Settings.Idle_Weapon,
    }
end
if not storage.Appearance then
    storage.Appearance = {
        Prefix = {
            Text = storage.Settings.Prefix_Text,
            Rainbow = storage.Settings.Prefix_Rainbow,
            Color = {
                R = storage.Settings.Prefix_Color_R,
                G = storage.Settings.Prefix_Color_G,
                B = storage.Settings.Prefix_Color_B,
            }
        }
    }
end
if not storage.API then
    storage.API = {}
end
ProtectStorageTable(storage, "storage")
ProtectStorageTable(storage.Config, "storage.Config")
ProtectStorageTable(storage.Settings, "storage.Settings")
ProtectStorageTable(storage.State, "storage.State")
ProtectStorageTable(storage.Core, "storage.Core")
ProtectStorageTable(storage.Companion, "storage.Companion")
ProtectStorageTable(storage.Players, "storage.Players")
ProtectStorageTable(storage.Cache, "storage.Cache")
ProtectStorageTable(storage.LLM, "storage.LLM")
ProtectStorageTable(storage.Network, "storage.Network")
ProtectStorageTable(storage.TTS, "storage.TTS")
ProtectStorageTable(storage.Weapons, "storage.Weapons")
ProtectStorageTable(storage.Appearance, "storage.Appearance")
ProtectStorageTable(storage.API, "storage.API")
function AC.MergeConfig()
    if _G.AI_CONFIG and type(_G.AI_CONFIG) == "table" then
        if _G.AI_CONFIG ~= storage.Config then
            if next(_G.AI_CONFIG) then
                DeepCopy(_G.AI_CONFIG, storage.Config)
                print("[AI Companion] Конфиг ai_config.lua смержен в хранилище")
                return true
            end
        end
    end
    return false
end
AC.MergeConfig()
_G.AI_COMPANION_DEF = setmetatable({}, {
    __index = function(t, k)
        return AC[k]
    end,
    __newindex = function(t, k, v)
        local info = debug.getinfo(2)
        local source = info and info.source or ""
        if source and (string.find(source, "ai_companion") or string.find(source, "ai_")) then
            AC[k] = v
            return
        end
        ErrorNoHalt("[AI Companion] ⛔ БЛОКИРОВКА записи в AI_COMPANION_DEF." .. tostring(k) .. "\n")
    end,
    __metatable = false,
})
_G.AI_CONFIG = setmetatable({}, {
    __index = function(t, k)
        return storage.Config[k]
    end,
    __newindex = function(t, k, v)
        local info = debug.getinfo(2)
        local source = info and info.source or ""
        if source and (string.find(source, "ai_companion") or string.find(source, "ai_")) then
            storage.Config[k] = v
            return
        end
        ErrorNoHalt("[AI Companion] ⛔ БЛОКИРОВКА записи в AI_CONFIG." .. tostring(k) .. "\n")
    end,
    __metatable = false,
})
_G.AI_SETTINGS = setmetatable({}, {
    __index = function(t, k)
        return storage.Settings[k]
    end,
    __newindex = function(t, k, v)
        local info = debug.getinfo(2)
        local source = info and info.source or ""
        if source and (string.find(source, "ai_companion") or string.find(source, "ai_")) then
            storage.Settings[k] = v
            return
        end
        ErrorNoHalt("[AI Companion] ⛔ БЛОКИРОВКА записи в AI_SETTINGS." .. tostring(k) .. "\n")
    end,
    __metatable = false,
})
_G.AI = setmetatable({}, {
    __index = function(t, k)
        return AC[k]
    end,
    __newindex = function(t, k, v)
        local info = debug.getinfo(2)
        local source = info and info.source or ""
        if source and (string.find(source, "ai_companion") or string.find(source, "ai_")) then
            AC[k] = v
            return
        end
        ErrorNoHalt("[AI Companion] ⛔ БЛОКИРОВКА записи в AI." .. tostring(k) .. "\n")
    end,
    __metatable = false,
})
function AC.GetState(key)
    return storage.State[key]
end
function AC.SetState(key, value)
    storage.State[key] = value
    if key == "TTS_Enabled" then storage.TTS.Enabled = value end
    if key == "TTS_Global" then storage.TTS.Global = value end
    if key == "LLM_Enabled" then storage.LLM.Enabled = value end
end
function AC.GetSetting(key)
    return storage.Settings[key]
end
function AC.SetSetting(key, value)
    storage.Settings[key] = value
    if key == "TTS_IP" then storage.TTS.IP = value; storage.Network.TTS.IP = value end
    if key == "TTS_Port" then storage.TTS.Port = value; storage.Network.TTS.Port = value end
    if key == "TTS_Timeout" then storage.TTS.Timeout = value; storage.Network.TTS.Timeout = value end
    if key == "LLM_IP" then storage.LLM.IP = value; storage.Network.LLM.IP = value end
    if key == "LLM_Port" then storage.LLM.Port = value; storage.Network.LLM.Port = value end
    if key == "LLM_Model" then storage.LLM.Model = value; storage.Network.LLM.Model = value end
    if key == "LLM_Timeout" then storage.LLM.Timeout = value; storage.Network.LLM.Timeout = value end
    if key == "LLM_Max_Tokens" then storage.LLM.MaxTokens = value; storage.Network.LLM.MaxTokens = value end
    if key == "LLM_Temperature" then storage.LLM.Temperature = value; storage.Network.LLM.Temperature = value end
    if key == "Combat_Weapon" then storage.Weapons.Combat = value end
    if key == "Melee_Weapon" then storage.Weapons.Melee = value end
    if key == "Idle_Weapon" then storage.Weapons.Idle = value end
    if key == "Prefix_Text" then storage.Appearance.Prefix.Text = value end
    if key == "Prefix_Rainbow" then storage.Appearance.Prefix.Rainbow = value end
    if key == "Prefix_Color_R" then storage.Appearance.Prefix.Color.R = value end
    if key == "Prefix_Color_G" then storage.Appearance.Prefix.Color.G = value end
    if key == "Prefix_Color_B" then storage.Appearance.Prefix.Color.B = value end
end
function AC.GetConfig(key)
    return storage.Config[key]
end
function AC.SetConfig(key, value)
    storage.Config[key] = value
end
function AC.Diagnostic()
    print("")
    print("═══════════════════════════════════════════════════════")
    print("        AI COMPANION - ДИАГНОСТИКА")
    print("═══════════════════════════════════════════════════════")
    print("  Хранилище: registry[" .. STORAGE_KEY .. "]")
    print("  Версия: " .. storage.Core.Version)
    print("  Создано: " .. os.date("%Y-%m-%d %H:%M:%S", storage.Core._created or 0))
    print("")
    print("  Состояний: " .. table.Count(storage.State))
    print("  Настроек: " .. table.Count(storage.Settings))
    print("  Конфиг: " .. table.Count(storage.Config))
    print("  Кэш: " .. table.Count(storage.Cache))
    print("  Network: " .. table.Count(storage.Network))
    print("")
    print("  Защита _G.AI_COMPANION: АКТИВНА")
    print("  Данные в registry: " .. (registry[STORAGE_KEY] and "ЕСТЬ" or "НЕТ"))
    print("═══════════════════════════════════════════════════════")
    print("")
end
function _G.GetCompanion(ply)
    return BotManager and BotManager:GetBotByOwner(ply) or nil
end
function _G.HasCompanion(ply)
    return IsValid(_G.GetCompanion(ply))
end
function _G.GetAllCompanions()
    return BotManager and BotManager:GetAllBots() or {}
end
function _G.GetAllBots()
    return _G.GetAllCompanions()
end
function _G.GetBotData(bot)
    return BotManager and BotManager:GetData(bot) or nil
end
function _G.SetBotState(bot, state)
    if BotManager then
        local data = BotManager:GetData(bot)
        if data then
            data.state = state
            BotManager:UpdateData(bot, data)
            BotManager:SyncToNWVars(bot)
            return true
        end
    end
    return false
end
function _G.GetBotState(bot)
    if BotManager then
        local data = BotManager:GetData(bot)
        if data then return data.state or "idle" end
    end
    return bot:GetNWString("BotState", "idle")
end
function _G.AskLLM(ply, message, isPrivate)
    if AC.LLM and AC.LLM.Ask then
        AC.LLM.Ask(ply, message, isPrivate)
    end
end
print("")
print("═══════════════════════════════════════════════════════")
print("        AI COMPANION - ЗАЩИЩЁННОЕ ХРАНИЛИЩЕ v2")
print("═══════════════════════════════════════════════════════")
print("  Таблица: _G.AI_COMPANION")
print("  Хранилище: registry[" .. STORAGE_KEY .. "]")
print("  Версия: " .. storage.Core.Version)
print("  Состояний: " .. table.Count(storage.State))
print("  Настроек: " .. table.Count(storage.Settings))
print("  Network: " .. table.Count(storage.Network))
print("  Cache: " .. table.Count(storage.Cache))
print("  Защита глобалов: АКТИВНА")
print("  Защита storage: АКТИВНА")
print("═══════════════════════════════════════════════════════")
print("")