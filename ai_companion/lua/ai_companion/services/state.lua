
local State = {}

local GLOBAL_KEYS = {

    ["LLM_IP"] = true,
    ["LLM_Port"] = true,
    ["LLM_Model"] = true,
    ["LLM_Mode"] = true,
    ["LLM_Provider"] = true,
    ["LLM_API_Key"] = true,
    ["LLM_Cloud_Model"] = true,
    ["LLM_Endpoint"] = true,
    ["LLM_Temperature"] = true,
    ["LLM_Max_Tokens"] = true,
    ["LLM_Timeout"] = true,

    ["TTS_IP"] = true,
    ["TTS_Port"] = true,
    ["TTS_Mode"] = true,
    ["TTS_Provider"] = true,
    ["TTS_API_Key"] = true,
    ["TTS_Voice"] = true,
    ["TTS_Language"] = true,
    ["TTS_Endpoint"] = true,
    ["TTS_Timeout"] = true,
    ["TTS_Speed"] = true,

    ["Yandex_Folder_ID"] = true,
    ["Yandex_Voice"] = true,
    ["Yandex_Lang"] = true,

    ["VK_Voice"] = true,
    ["VK_Tempo"] = true,

    ["Debug_Mode"] = true,
    ["Auto_Sync_Global"] = true,
    ["Allow_Custom_Prompts"] = true,
    ["Locale"] = true,
    ["TTS_Enabled"] = true,
    ["LLM_Enabled"] = true,
    ["Global_TTS_Enabled"] = true,
    ["Global_LLM_Enabled"] = true,

    ["TTS_Workflow_Enabled"] = true,

	["Memory_Enabled"] = true,
}

function State:new(utils, config)
    local obj = {
        utils = utils,
        config = config,
        storage = {},
        _initialized = false,
        _storageKey = "__AI_COMPANION_STORAGE_v2",
        _savePath = "ai_companion_settings.txt",
        _playerSettingsPath = "ai_companion_player_settings.txt",
        _saveTimer = nil,
        _dirty = false,
        GLOBAL_KEYS = GLOBAL_KEYS,
        _playerSettings = {},
    }
    setmetatable(obj, self)
    self.__index = self
    return obj
end

function State:init()
	self.utils.LogDebug("[State:init] CALLED!")
    if self._initialized then return end

    local registry = debug.getregistry()
    self.storage = registry[self._storageKey] or {}
    registry[self._storageKey] = self.storage

    self:InitState()
    self:InitSettings()
    self:InitCore()
    self:InitConfig()
    self:InitCompanion()
    self:InitPlayers()
    self:InitCache()
    self:InitNetwork()
    self:InitTTS()
    self:InitLLM()
    self:InitWeapons()
    self:InitAppearance()
    self:InitAPI()
    self:InitAFK()
    self:InitPlayerSettings()

    self:LoadFromFile()
    self.utils.LogDebug("[State:init] After LoadFromFile")

    self:LoadPlayerSettingsFromFile()
    self.utils.LogDebug("[State:init] After LoadPlayerSettingsFromFile")
    self.utils.LogDebug("  PlayerSettings count: " .. table.Count(self.storage.PlayerSettings or {}))
    for steamID, settings in pairs(self.storage.PlayerSettings or {}) do
        self.utils.LogDebug("  [" .. tostring(steamID) .. "]: " .. table.Count(settings) .. " settings")
    end
    self.utils.LogDebug("  File exists: " .. tostring(file.Exists(self._playerSettingsPath, "DATA")))
    self.utils.LogDebug("[State:init] PlayerSettings count = " .. table.Count(self.storage.PlayerSettings or {}))

    self:ProtectStorage()

    if SERVER then
        self._saveTimer = timer.Create("AIState_AutoSave", 30, 0, function()
            if self._dirty then
                self:SaveToFile()
                self:SavePlayerSettingsToFile()
                self._dirty = false
            end
        end)
    end

    self._initialized = true
    if self.utils then
        self.utils.LogInfo("State", "Хранилище инициализировано (версия 2.0.0)")
    end
end

function State:IsGlobalKey(key)
    local result = self.GLOBAL_KEYS[key] == true
    return result
end

function State:InitState()
    if not self.storage.State then
        self.storage.State = {
            TTS_Enabled = false,
            LLM_Enabled = true,
            Disabled = false,
            StealthMode = false,
            DefenderMode = false,
            MedicMode = false,
            PacifistMode = false,
            AggressiveMode = false,
        }
    end
end

function State:InitSettings()
    if not self.storage.Settings then
        self.storage.Settings = {

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
            Stealth_Mode = false,
            Defender_Mode = false,
            Medic_Mode = false,
            Pacifist_Mode = false,
            Aggressive_Mode = false,

            TTS_Enabled = false,
            LLM_Enabled = true,

            TTS_Workflow_Enabled = false,

			Memory_Enabled = true,
        }
    end
end

function State:InitPlayerSettings()
    if not self.storage.PlayerSettings then
        self.storage.PlayerSettings = {}
    end
end

function State:InitPlayers()
    if not self.storage.Players then
        self.storage.Players = {
            PrefixText = {},
            PrefixColorR = {},
            PrefixColorG = {},
            PrefixColorB = {},
            PrefixRainbow = {},
        }
    end
end

function State:InitCore()
    if not self.storage.Core then
        self.storage.Core = {
            Nick = "AI_Companion",
            Model = "models/player/urban.mdl",
            Version = "2.0.0",
            _loaded = true,
            _created = os.time(),
        }
    end
end

function State:InitConfig()
    if not self.storage.Config then
        self.storage.Config = {}
    end
    if not self.storage.Config.Network then
        self.storage.Config.Network = {
            LLM = {
                IP = self.storage.Settings.LLM_IP,
                Port = self.storage.Settings.LLM_Port,
                Model = self.storage.Settings.LLM_Model,
                Timeout = self.storage.Settings.LLM_Timeout,
                MaxTokens = self.storage.Settings.LLM_Max_Tokens,
                Temperature = self.storage.Settings.LLM_Temperature,
            },
            TTS = {
                IP = self.storage.Settings.TTS_IP,
                Port = self.storage.Settings.TTS_Port,
                Timeout = self.storage.Settings.TTS_Timeout,
            }
        }
    end
    if not self.storage.Config.Cache then
        self.storage.Config.Cache = {
            TTS = { Size = 50, TTL = 300 },
            LLM = { Size = 100, TTL = 600 },
        }
    end
    if not self.storage.Config.LLM then
        self.storage.Config.LLM = { MaxHistoryPairs = 10, MaxTTSConcurrent = 3 }
    end
    if not self.storage.Config.HTTP then
        self.storage.Config.HTTP = { DefaultTimeout = 30, RetryCount = 3, RetryDelay = 1 }
    end
    if not self.storage.Config.Chat then
        self.storage.Config.Chat = { MaxMessageLength = 500, MaxHistoryAge = 3600 }
    end
    if not self.storage.Config.Providers then
        self.storage.Config.Providers = {
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
end

function State:InitCompanion()
    if not self.storage.Companion then
        self.storage.Companion = {
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
        local States = self.storage.Companion.States
        self.storage.Companion.ValidTransitions = {
            [States.IDLE] = {
                [States.FOLLOW] = true, [States.COMBAT] = true, [States.SITTING] = true,
                [States.PROTECT] = true, [States.PROTECT_VEHICLE] = true, [States.POINTING] = true,
            },
            [States.FOLLOW] = {
                [States.IDLE] = true, [States.COMBAT] = true, [States.PROTECT] = true,
                [States.PROTECT_VEHICLE] = true, [States.VEHICLE] = true, [States.SITTING] = true,
                [States.COVER] = true, [States.POINTING] = true,
            },
            [States.COMBAT] = {
                [States.IDLE] = true, [States.FOLLOW] = true, [States.COVER] = true,
                [States.PROTECT] = true, [States.PROTECT_VEHICLE] = true,
            },
            [States.COVER] = { [States.COMBAT] = true, [States.FOLLOW] = true, [States.IDLE] = true },
            [States.POINTING] = {
                [States.COMBAT] = true, [States.FOLLOW] = true, [States.IDLE] = true,
                [States.PROTECT] = true, [States.PROTECT_VEHICLE] = true,
            },
            [States.PROTECT] = { [States.COMBAT] = true, [States.FOLLOW] = true, [States.IDLE] = true },
            [States.PROTECT_VEHICLE] = { [States.COMBAT] = true, [States.FOLLOW] = true, [States.IDLE] = true },
            [States.SITTING] = { [States.FOLLOW] = true, [States.IDLE] = true, [States.VEHICLE] = true },
            [States.VEHICLE] = {
                [States.FOLLOW] = true, [States.IDLE] = true, [States.COMBAT] = true, [States.SITTING] = true,
            },
        }
    end
end

function State:InitCache()
    if not self.storage.Cache then
        self.storage.Cache = { LLM = nil, TTS = nil, Prefix = nil }
    end
end

function State:InitNetwork()
    if not self.storage.Network then
        self.storage.Network = {
            LLM = {
                IP = self.storage.Settings.LLM_IP,
                Port = self.storage.Settings.LLM_Port,
                Model = self.storage.Settings.LLM_Model,
                Timeout = self.storage.Settings.LLM_Timeout,
                MaxTokens = self.storage.Settings.LLM_Max_Tokens,
                Temperature = self.storage.Settings.LLM_Temperature,
            },
            TTS = {
                IP = self.storage.Settings.TTS_IP,
                Port = self.storage.Settings.TTS_Port,
                Timeout = self.storage.Settings.TTS_Timeout,
            }
        }
    end
end

function State:InitTTS()
    if not self.storage.TTS then
        self.storage.TTS = {
            Enabled = self.storage.State.TTS_Enabled,
            Global = false,
            Active = 0,
            IP = self.storage.Settings.TTS_IP,
            Port = self.storage.Settings.TTS_Port,
            Timeout = self.storage.Settings.TTS_Timeout,
        }
    end
end

function State:InitLLM()
    if not self.storage.LLM then
        self.storage.LLM = {
            Enabled = self.storage.State.LLM_Enabled,
            IP = self.storage.Settings.LLM_IP,
            Port = self.storage.Settings.LLM_Port,
            Model = self.storage.Settings.LLM_Model,
            Timeout = self.storage.Settings.LLM_Timeout,
            MaxTokens = self.storage.Settings.LLM_Max_Tokens,
            Temperature = self.storage.Settings.LLM_Temperature,
        }
    end
end

function State:InitWeapons()
    if not self.storage.Weapons then
        self.storage.Weapons = {
            Combat = self.storage.Settings.Combat_Weapon,
            Melee = self.storage.Settings.Melee_Weapon,
            Idle = self.storage.Settings.Idle_Weapon,
        }
    end
end

function State:InitAppearance()
    if not self.storage.Appearance then
        self.storage.Appearance = {
            Prefix = {
                Text = self.storage.Settings.Prefix_Text,
                Rainbow = self.storage.Settings.Prefix_Rainbow,
                Color = {
                    R = self.storage.Settings.Prefix_Color_R,
                    G = self.storage.Settings.Prefix_Color_G,
                    B = self.storage.Settings.Prefix_Color_B,
                }
            }
        }
    end
end

function State:InitAPI()
    if not self.storage.API then
        self.storage.API = {}
    end
end

function State:InitAFK()
    if not self.storage.AFK then
        self.storage.AFK = {
            Enabled = true,
            InactivityTimeout = 60,
            CheckInterval = 10,
            ActionInterval = { min = 50, max = 60 },
            ActionWeights = {
                sit = 25, wait = 5, fight_zombie = 20, fight_zombine = 10,
                fight_poisonzombie = 8, fight_fastzombie = 8, fight_antlion = 10,
                fight_combine = 10, fight_metropolice = 8, dance = 15, point = 10,
            },
            ZombieLifetime = 15,
            DanceDuration = 5,
            SpawnDistance = {
                default = 150, npc_combine_s = 150, npc_metropolice = 150,
                npc_zombine = 150, npc_poisonzombie = 150, npc_fastzombie = 150,
                npc_zombie = 150,
            },
            ChairHeight = 18,
        }
    end
end

function State:GetSavePath()
    return self._savePath
end

function State:SaveToFile()
    local path = self:GetSavePath()
    if not self.storage.Settings or not self.storage.State then
        if self.utils then
            self.utils.LogError("State", "Ошибка сохранения: отсутствуют основные таблицы")
        end
        return false
    end

    local data = {
        Settings = self.storage.Settings,
        State = self.storage.State,
        Config = self.storage.Config,
        Network = self.storage.Network,
        TTS = self.storage.TTS,
        LLM = self.storage.LLM,
        Weapons = self.storage.Weapons,
        Appearance = self.storage.Appearance,
        Companion = self.storage.Companion,
        Players = self.storage.Players,
        Core = self.storage.Core,
        version = "2.0.0",
        saved_at = os.time(),
    }

    local json = util.TableToJSON(data)
    if json then
        file.Write(path, json)
        if self.utils then
            self.utils.LogInfo("State", "Настройки сохранены в %s", path)
        end
        self._dirty = false
        return true
    end

    if self.utils then
        self.utils.LogError("State", "Не удалось сохранить настройки в %s", path)
    end
    return false
end
function State:LoadFromFileSafe()
    local path = self:GetSavePath()
    if not file.Exists(path, "DATA") then
        if self.utils then
            self.utils.LogInfo("State", "Файл настроек не найден (%s)", path)
        end
        return false
    end

    local backupPath = path .. ".bak"
    if file.Exists(path, "DATA") then
        local content = file.Read(path, "DATA")
        if content and content ~= "" then
            file.Write(backupPath, content)
            if self.utils then
                self.utils.LogDebug("State", "Создана резервная копия: %s", backupPath)
            end
        end
    end

    local json = file.Read(path, "DATA")
    if not json or json == "" then
        if self.utils then
            self.utils.LogWarn("State", "Файл настроек пуст (%s)", path)
        end
        return false
    end

    local ok, data = pcall(util.JSONToTable, json)
    if not ok or not data then
        if self.utils then
            self.utils.LogError("State", "Ошибка парсинга файла настроек: %s", path)
            self.utils.LogError("State", "Попытка восстановить из резервной копии...")
        end

        if file.Exists(backupPath, "DATA") then
            local backupJson = file.Read(backupPath, "DATA")
            if backupJson and backupJson ~= "" then
                local ok2, data2 = pcall(util.JSONToTable, backupJson)
                if ok2 and data2 then
                    data = data2
                    if self.utils then
                        self.utils.LogInfo("State", "✅ Восстановлено из резервной копии")
                    end
                end
            end
        end

        if not data then
            if self.utils then
                self.utils.LogError("State", "❌ Не удалось восстановить настройки")
            end
            return false
        end
    end

    local required = {"Settings", "State", "Config"}
    local valid = true
    for _, key in ipairs(required) do
        if not data[key] or type(data[key]) ~= "table" then
            if self.utils then
                self.utils.LogWarn("State", "Отсутствует обязательное поле: %s", key)
            end
            valid = false
        end
    end

    if not valid then
        if self.utils then
            self.utils.LogError("State", "❌ Файл настроек повреждён, используем дефолтные значения")
        end
        return false
    end

    local structures = {
        "Settings", "State", "Config", "Network", "TTS", "LLM",
        "Weapons", "Appearance", "Companion", "Players", "Core"
    }

    for _, structName in ipairs(structures) do
        if data[structName] and type(data[structName]) == "table" then
            if not self.storage[structName] then
                self.storage[structName] = {}
            end
            for k, v in pairs(data[structName]) do
                self.storage[structName][k] = v
            end
            if self.utils then
                self.utils.LogDebug("State", "Загружена структура: %s", structName)
            end
        end
    end

    if self.utils then
        self.utils.LogInfo("State", "Настройки загружены из %s", path)
    end
    self._dirty = false
    return true
end
function State:LoadFromFile()
    return self:LoadFromFileSafe()
end

function State:SavePlayerSettingsToFile()
    if not SERVER then return false end

    local path = self._playerSettingsPath
    local data = {}

    for steamID, settings in pairs(self.storage.PlayerSettings or {}) do
        data[tostring(steamID)] = settings
    end

    local arrayFormat = {}
    for steamID, settings in pairs(data) do
        table.insert(arrayFormat, {
            id = steamID,
            settings = settings
        })
    end

    local json = util.TableToJSON(arrayFormat)
    if json then
        file.Write(path, json)
        if self.utils then
            self.utils.LogInfo("State", "Персональные настройки сохранены в %s (%d игроков)", path, #arrayFormat)
        end
        return true
    end

    return false
end

function State:LoadPlayerSettingsSafe()
    if not SERVER then return false end

    local path = self._playerSettingsPath
    if not file.Exists(path, "DATA") then
        if self.utils then
            self.utils.LogInfo("State", "Файл персональных настроек не найден (%s)", path)
        end
        return false
    end

    local backupPath = path .. ".bak"
    if file.Exists(path, "DATA") then
        local content = file.Read(path, "DATA")
        if content and content ~= "" then
            file.Write(backupPath, content)
        end
    end

    local json = file.Read(path, "DATA")
    if not json or json == "" then
        return false
    end

    local ok, data = pcall(util.JSONToTable, json)
    if not ok or not data then
        if self.utils then
            self.utils.LogError("State", "Ошибка парсинга персональных настроек")
        end

        if file.Exists(backupPath, "DATA") then
            local backupJson = file.Read(backupPath, "DATA")
            if backupJson and backupJson ~= "" then
                local ok2, data2 = pcall(util.JSONToTable, backupJson)
                if ok2 and data2 then
                    data = data2
                    if self.utils then
                        self.utils.LogInfo("State", "✅ Персональные настройки восстановлены из резерва")
                    end
                end
            end
        end

        if not data then
            return false
        end
    end

    self.storage.PlayerSettings = {}

    if #data > 0 then
        for _, entry in ipairs(data) do
            if entry.id and entry.settings then
                self.storage.PlayerSettings[tostring(entry.id)] = entry.settings
            end
        end
    else
        for steamID, settings in pairs(data) do
            self.storage.PlayerSettings[tostring(steamID)] = settings
        end
    end

    if self.utils then
        self.utils.LogInfo("State", "Персональные настройки загружены: %d игроков", table.Count(self.storage.PlayerSettings))
    end

    return true
end

function State:LoadPlayerSettingsFromFile()
    return self:LoadPlayerSettingsSafe()
end

function State:MarkDirty()
    self._dirty = true
end

function State:getState(key)
    if not self.storage.State then self:InitState() end
    return self.storage.State[key]
end

function State:setState(key, value)
    if not self.storage.State then self:InitState() end
    self.storage.State[key] = value
    self:MarkDirty()

    if CLIENT then
        net.Start("AICompanion_SetGlobalSetting")
        net.WriteString(key)
        net.WriteString(tostring(value))
        net.SendToServer()
    end
end

function State:getSetting(key)
    if not self.storage.Settings then self:InitSettings() end
    return self.storage.Settings[key]
end

function State:setSetting(key, value)
    if not self.storage.Settings then self:InitSettings() end
    self.storage.Settings[key] = value
    self:MarkDirty()
    if SERVER and self:IsGlobalKey(key) then
        local autoSync = self:getSetting("Auto_Sync_Global")
        if autoSync == nil or autoSync == true then
            self:SyncSingleSettingToAll(key, value)
        end
    end

end

function State:getPlayerSetting(steamID, key, default)
    steamID = tostring(steamID or "")
    if steamID == "" then

        return default
    end

    if CLIENT then
        if self._playerSettings and self._playerSettings[steamID] then
            local val = self._playerSettings[steamID][key]
            if val ~= nil then return val end
        end
        return default
    end

    local playerData = self.storage.PlayerSettings and self.storage.PlayerSettings[steamID]
    if playerData then
        local val = playerData[key]
        if val ~= nil then return val end
    end
    return default
end

function State:setPlayerSetting(steamID, key, value)
	steamID = tostring(steamID or "")
	if steamID == "" then
		self.utils.LogDebug("[State:setPlayerSetting] ❌ steamID пустой!")
		return
	end

	if value == "true" then value = true
	elseif value == "false" then value = false
	end

	local current = self:getPlayerSetting(steamID, key, nil)

	if current == "true" then current = true
	elseif current == "false" then current = false
	end

	if current == value and current ~= nil then
		return
	end

	self.utils.LogDebug("[State:setPlayerSetting] 📝 " .. key .. " = " .. tostring(value) .. " для " .. steamID)

	if SERVER then
		if not self.storage.PlayerSettings[steamID] then
			self.storage.PlayerSettings[steamID] = {}
			self.utils.LogDebug("[State:setPlayerSetting] 📁 Создана запись для " .. steamID)
		end
		self.storage.PlayerSettings[steamID][key] = value
		self:MarkDirty()

		local ply = player.GetBySteamID64(steamID)
		if IsValid(ply) then
			local locator = _G.AI_GetLocator()
			if locator and locator:has("shared") then
				locator:get("shared"):SyncPlayerSettingsToClient(ply)
			end
		end
	end

	if CLIENT then
		if not self._playerSettings[steamID] then
			self._playerSettings[steamID] = {}
		end
		self._playerSettings[steamID][key] = value
		self.utils.LogDebug("[State:setPlayerSetting] 💾 Кэш клиента обновлён: " .. key .. " = " .. tostring(value))
	end
end

function State:getPlayerSettings(steamID)
    steamID = tostring(steamID or "")
    if CLIENT then
        return self._playerSettings[steamID] or {}
    end
    return self.storage.PlayerSettings[steamID] or {}
end

function State:setPlayerSettings(steamID, settings)
    steamID = tostring(steamID or "")
    if steamID == "" or type(settings) ~= "table" then return end
    if CLIENT then
        if not self._playerSettings then self._playerSettings = {} end
        self._playerSettings[steamID] = settings
        return
    end
    self.storage.PlayerSettings[steamID] = settings
    self:MarkDirty()
    self:SavePlayerSettingsToFile()
end

function State:getConfig(key)
    return self.storage.Config[key]
end

function State:setConfig(key, value)
    self.storage.Config[key] = value
    self:MarkDirty()
end

function State:getStorage()
    return self.storage
end

function State:getRaw(key)
    return self.storage[key]
end

function State:setRaw(key, value)
    self.storage[key] = value
    self:MarkDirty()
end

function State:SyncSingleSettingToAll(key, value)
    if not SERVER then return end

    net.Start("AI_GlobalSettingUpdated")
    net.WriteString(key)
    net.WriteString(tostring(value))
    net.Broadcast()

    if self.utils then
        self.utils.LogDebug("State", "Глобальная настройка синхронизирована: %s = %s", key, tostring(value))
    end
end

function State:SyncPlayerSettingsToClient(ply)
    if not SERVER or not self.utils or not self.utils:IsValid(ply) then return end

    local steamID = ply:SteamID64()
    local settings = self:getPlayerSettings(steamID)

    net.Start("AI_PlayerSettings_Sync")
    net.WriteString(util.TableToJSON(settings))
    net.Send(ply)
end

function State:GetVersion()
    return self.storage.Core.Version
end

function State:GetCreated()
    return self.storage.Core._created
end

function State:IsValidTransition(fromState, toState)
    local transitions = self.storage.Companion.ValidTransitions
    if not transitions[fromState] then return false end
    return transitions[fromState][toState] == true
end

function State:GetStates()
    return self.storage.Companion.States
end

function State:IsFriendlyNPC(class)
    return self.storage.Companion.FriendlyNPCs[class] == true
end

function State:GetPlayerPrefix(steamID)
    steamID = tostring(steamID or "")
    return self.storage.Players.PrefixText[steamID]
end

function State:SetPlayerPrefix(steamID, prefix)
    steamID = tostring(steamID or "")
    self.storage.Players.PrefixText[steamID] = prefix
    self:MarkDirty()
end

function State:GetPlayerPrefixColor(steamID)
    steamID = tostring(steamID or "")
    return {
        R = self.storage.Players.PrefixColorR[steamID] or 255,
        G = self.storage.Players.PrefixColorG[steamID] or 200,
        B = self.storage.Players.PrefixColorB[steamID] or 0,
    }
end

function State:SetPlayerPrefixColor(steamID, r, g, b)
    steamID = tostring(steamID or "")
    self.storage.Players.PrefixColorR[steamID] = r
    self.storage.Players.PrefixColorG[steamID] = g
    self.storage.Players.PrefixColorB[steamID] = b
    self:MarkDirty()
end

function State:GetPlayerPrefixRainbow(steamID)
    steamID = tostring(steamID or "")
    return self.storage.Players.PrefixRainbow[steamID] or false
end

function State:SetPlayerPrefixRainbow(steamID, value)
    steamID = tostring(steamID or "")
    self.storage.Players.PrefixRainbow[steamID] = value
    self:MarkDirty()
end

function State:ProtectStorage()
    self:ProtectTable(self.storage, "storage")
    self:ProtectTable(self.storage.Config, "storage.Config")
    self:ProtectTable(self.storage.Settings, "storage.Settings")
    self:ProtectTable(self.storage.State, "storage.State")
    self:ProtectTable(self.storage.Core, "storage.Core")
    self:ProtectTable(self.storage.Companion, "storage.Companion")
    self:ProtectTable(self.storage.Players, "storage.Players")
    self:ProtectTable(self.storage.Cache, "storage.Cache")
    self:ProtectTable(self.storage.LLM, "storage.LLM")
    self:ProtectTable(self.storage.Network, "storage.Network")
    self:ProtectTable(self.storage.TTS, "storage.TTS")
    self:ProtectTable(self.storage.Weapons, "storage.Weapons")
    self:ProtectTable(self.storage.Appearance, "storage.Appearance")
    self:ProtectTable(self.storage.API, "storage.API")
    self:ProtectTable(self.storage.AFK, "storage.AFK")

end

function State:ProtectTable(tbl, path, depth)
    if type(tbl) ~= "table" then return end
    if depth and depth > 10 then return end

    if not self._allowedSources then
        self._allowedSources = {}
        for i = 2, 10 do
            local info = debug.getinfo(i)
            if info and info.source then
                self._allowedSources[info.source] = true
            end
        end
    end

    local existingMt = getmetatable(tbl)
    if existingMt == false then return end
    if existingMt and existingMt.__metatable == false then return end

    local mt = {
        __newindex = function(t, k, v)
            local info = debug.getinfo(2)
            local source = info and info.source or ""
            if self._allowedSources[source] then
                rawset(t, k, v)
                return
            end
            if source and (string.find(source, "ai_companion") or string.find(source, "ai_")) then
                rawset(t, k, v)
                return
            end
            if v == nil then
                rawset(t, k, v)
                return
            end
            if self.utils then
                self.utils.LogError("State", "⛔ БЛОКИРОВКА! Попытка изменить %s.%s извне! Источник: %s",
                    path or "storage", tostring(k), source or "неизвестно")
            end
        end,
        __metatable = false,
    }

    local ok, err = pcall(setmetatable, tbl, mt)
    if not ok then
        if self.config and self.config:get("DEBUG_MODE") then
            if self.utils then
                self.utils.LogDebug("State", "Пропуск защиты %s: %s", path or "?", tostring(err))
            end
        end
        return
    end

    local nextDepth = (depth or 0) + 1
    for k, v in pairs(tbl) do
        if type(v) == "table" and k ~= "_" then
            self:ProtectTable(v, (path or "storage") .. "." .. tostring(k), nextDepth)
        end
    end
end

function State:Diagnostic()
    self.utils:LogDebug("")
    self.utils:LogDebug("═══════════════════════════════════════════════════════")
    self.utils:LogDebug("        AI COMPANION - ДИАГНОСТИКА ХРАНИЛИЩА")
    self.utils:LogDebug("═══════════════════════════════════════════════════════")
    self.utils:LogDebug("  Ключ: " .. self._storageKey)
    self.utils:LogDebug("  Версия: " .. self:GetVersion())
    self.utils:LogDebug("  Создано: " .. os.date("%Y-%m-%d %H:%M:%S", self:GetCreated() or 0))
    self.utils:LogDebug("")
    self.utils:LogDebug("  Состояний: " .. table.Count(self.storage.State))
    self.utils:LogDebug("  Настроек: " .. table.Count(self.storage.Settings))
    self.utils:LogDebug("  Персональных: " .. table.Count(self.storage.PlayerSettings))
    self.utils:LogDebug("  Конфиг: " .. table.Count(self.storage.Config))
    self.utils:LogDebug("  Кэш: " .. table.Count(self.storage.Cache))
    self.utils:LogDebug("  Network: " .. table.Count(self.storage.Network))
    self.utils:LogDebug("")
    self.utils:LogDebug("  Файл сохранения: " .. self._savePath)
    self.utils:LogDebug("  Файл существует: " .. tostring(file.Exists(self._savePath, "DATA")))
    self.utils:LogDebug("  Файл персональных: " .. self._playerSettingsPath)
    self.utils:LogDebug("  Файл персональных существует: " .. tostring(file.Exists(self._playerSettingsPath, "DATA")))

    self.utils:LogDebug("  Dirty (нужно сохранить): " .. tostring(self._dirty))
    self.utils:LogDebug("")
    self.utils:LogDebug("  Защита storage: АКТИВНА")
    self.utils:LogDebug("  Данные в registry: " .. (debug.getregistry()[self._storageKey] and "ЕСТЬ" or "НЕТ"))
    self.utils:LogDebug("═══════════════════════════════════════════════════════")
    self.utils:LogDebug("")
end

if SERVER then
    concommand.Add("ai_state_diagnostic", function(ply)
        if IsValid(ply) and not ply:IsAdmin() then
            ply:ChatPrint("[AI] Только администраторы!")
            return
        end
        local locator = _G.AI_GetLocator()
        if locator and locator:has("state") then
            locator:get("state"):Diagnostic()
        else
            self.utils.LogDebug("[AI] State не найден!")
        end
        if IsValid(ply) then
            ply:ChatPrint("[AI] Диагностика выведена в консоль")
        end
    end)

    concommand.Add("ai_state_save", function(ply)
        if IsValid(ply) and not ply:IsAdmin() then
            ply:ChatPrint("[AI] Только администраторы!")
            return
        end
        local locator = _G.AI_GetLocator()
        if locator and locator:has("state") then
            local state = locator:get("state")
            state:SaveToFile()
            state:SavePlayerSettingsToFile()
            if IsValid(ply) then
                ply:ChatPrint("[AI] Настройки сохранены в файл")
            end
        end
    end)

    concommand.Add("ai_state_load", function(ply)
        if IsValid(ply) and not ply:IsAdmin() then
            ply:ChatPrint("[AI] Только администраторы!")
            return
        end
        local locator = _G.AI_GetLocator()
        if locator and locator:has("state") then
            local state = locator:get("state")
            state:LoadFromFile()
            state:LoadPlayerSettingsFromFile()
            if IsValid(ply) then
                ply:ChatPrint("[AI] Настройки загружены из файла")
            end
        end
    end)
end
function State:SyncToAllClients()
    if not SERVER then return end
    
    local settings = self.storage.Settings or {}
    local state = self.storage.State or {}
    
    
    for key, value in pairs(settings) do
        if self:IsGlobalKey(key) then
            self:SyncSingleSettingToAll(key, value)
        end
    end
    
    
    for key, value in pairs(state) do
        if key ~= "Disabled" then
            net.Start("AI_GlobalSettingUpdated")
            net.WriteString(key)
            net.WriteString(tostring(value))
            net.Broadcast()
        end
    end
    
    if self.utils then
        self.utils.LogInfo("State", "Глобальные настройки синхронизированы со всеми клиентами")
    end
end
return State
