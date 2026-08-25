if AI_COMPANION_CONFIG_LOADED then return end
AI_COMPANION_CONFIG_LOADED = true
local registry = debug.getregistry()
local storage = registry["__AI_COMPANION_STORAGE_v2"]
if not storage then
    ErrorNoHalt("[AI Config] КРИТИЧЕСКАЯ ОШИБКА: state.lua не загружен!\n")
    ErrorNoHalt("[AI Config] Создаём fallback-хранилище...\n")
    storage = {
        Config = {},
        Settings = {},
        State = {},
    }
    registry["__AI_COMPANION_STORAGE_v2"] = storage
end
local Config = storage.Config
for k, _ in pairs(Config) do
    Config[k] = nil
end
Config.Network = {
    LLM = {
        IP = "127.0.0.1",
        Port = 1234,
        Model = "local-model",
        Timeout = 60,
        MaxTokens = 100,
        Temperature = 0.7,
    },
    TTS = {
        IP = "127.0.0.1",
        Port = 8188,
        Timeout = 120,
    },
}
Config.HTTP = {
    MaxConcurrent = 3,
    DefaultTimeout = 10,
    RetryCount = 3,
    RetryDelay = 1,
}
Config.Cache = {
    LLM = {
        Size = 50,
        TTL = 3600,
    },
    TTS = {
        Size = 100,
        TTL = 7200,
    },
    Prefix = {
        Size = 32,
        TTL = 60,
    },
}
Config.LLM = {
    MaxHistoryPairs = 5,
    MaxTTSConcurrent = 5,
    CheckInterval = 30,
    SoloCooldown = 5,
    GlobalCooldown = 3,
    MaxMessageLength = 300,
}
Config.TTS = {
    MaxConcurrent = 5,
    DefaultVoice = "21m00Tcm4TlvDq8ikWAM",
    DefaultModel = "eleven_monolingual_v1",
    AudioCacheLifetime = 30,
}
Config.Weapons = {
    IDLE = "weapon_physgun",
    COMBAT = "weapon_smg1",
    MELEE = "weapon_crowbar",
    MEDKIT = "weapon_medkit",
    RPG = "weapon_rpg",
    FRAG = "weapon_frag",
}
Config.Navigation = {
    RecalcInterval = 1.0,
    MaxIterations = 1500,
    TeleportDist = 2000,
    LookaheadDist = 56,
    CloseFollowDistSq = 6400,
    DebugOverlayInterval = 1.0,
    UnstuckTime = 0.7,
    UnstuckDuration = 0.45,
    LadderTimeout = 4,
    FastDist = 700,
    MediumDist = 260,
    WalkSlow = 200,
    DirectPathDistSq = 9216,
    WallRepathDelay = 5.0,
    AvoidanceRadius = 64,
    MaxClimbHeight = 40,
    JumpCheckDist = 32,
    NoclipHeightThreshold = 50,      
    NoclipTeleportCheckDist = 500,   
}
Config.Speeds = {
    Walk = 200,
    WalkSlow = 150, 
    Run = 320,
    Stealth = 80,
    Crouch = 90,
    Min = 80,
    Max = 340,
    Melee = 400,
    Combat = 220,
    Flee = 350,
    Dodge = 350,
}
Config.Combat = {
    MeleeDist = 110,
    FragMinDist = 150,
    FragMaxDist = 600,
    RPGRDist = 500,
    IdealDist = 300,
    GrenadeDodgeRadius = 250,
    GrenadeDangerDist = 110,
    CombatForgetRadius = 240000,
    FragCooldown = 5.0,
    RPGCooldown = 0.1,
    AltFireCooldown = 2.0,
    WeaponSwitchDelay = 5,
    HealCooldown = 1.2,
    MedicPostCombatCooldown = 3.0,
    ThreatScanRadius = 1500,
    ThreatScanInterval = 2.0,
    EnemyCacheInterval = 2.0,
    StrafeMinInterval = 0.4,
    StrafeMaxInterval = 2.0,
    StrafeDist = 60,
    CombatStrafeDist = 100,
    HealThresholdOwner = 0.7,
    HealThresholdSelf = 0.5,
    HealRange = 72,
    AimDotThreshold = 0.85,
    MeleeGiveCooldown = 1.0,
    MeleeApproachDist = 30,
    AmmoGiveAmount = 100,
    DefaultClipSize = 30,
    CommandAttackRadius = 2000,
    CombatIdleTimeout = 10.,
}
Config.Spawn = {
    MaxBotsTotal = 10,
    MaxBotsPerPlayer = 1,
    SpawnGraceDuration = 10,
    HealthkitLifetime = 30,
    StageDelays = {0, 0.01, 0.05, 4.0},
    ForceStandIterations = 200,
}
Config.Vehicle = {
    EngineDeadZoneEnter = 120,
    EngineDeadZoneExit = 180,
    EngineStopDelay = 1.5,
    EngineIdleTimeout = 25.0,
    Heli = {
        FollowMaxSpeed = 240,
        FollowApproachDist = 350,
        FollowDeadZone = 100,
        EnemyMaxSpeed = 400,
        EnemyApproachDist = 200,
        HeightDeadZone = 20,
        MaxPitch = 0.28,
        MaxRoll = 0.28,
        DampingFactor = 0.10,
        SoftAltLimit = 200,
        HardAltLimit = 350,
        DownForceMax = 8000,
        UpForceMax = 4000,
        ForceDeadZone = 30,
    },
}
Config.UI = {
    PanelWidth = 800,
    PanelHeight = 600,
    InputFieldWidth = 150,
    ButtonWidth = 85,
    BotStatusHeight = 140,
    MaxNickLength = 32,
    QuickColors = {
        {name = "Стандартный [AI]", r = 255, g = 200, b = 0},
        {name = "Белый", r = 255, g = 255, b = 255},
        {name = "Чёрный", r = 30, g = 30, b = 30},
        {name = "Серый", r = 150, g = 150, b = 150},
        {name = "Красный", r = 255, g = 50, b = 50},
        {name = "Тёмно-красный", r = 180, g = 0, b = 0},
        {name = "Оранжевый", r = 255, g = 150, b = 0},
        {name = "Жёлтый", r = 255, g = 255, b = 0},
        {name = "Лайм", r = 150, g = 255, b = 50},
        {name = "Зелёный", r = 50, g = 255, b = 50},
        {name = "Тёмно-зелёный", r = 0, g = 150, b = 0},
        {name = "Бирюзовый", r = 0, g = 255, b = 255},
        {name = "Голубой", r = 50, g = 200, b = 255},
        {name = "Синий", r = 50, g = 100, b = 255},
        {name = "Тёмно-синий", r = 0, g = 50, b = 180},
        {name = "Фиолетовый", r = 150, g = 50, b = 255},
        {name = "Розовый", r = 255, g = 100, b = 200},
        {name = "Пурпурный", r = 255, g = 0, b = 255},
        {name = "Коричневый", r = 150, g = 100, b = 50},
        {name = "Цвет чата игрока", r = 255, g = 255, b = 178},
        {name = "Админ-красный", r = 255, g = 0, b = 0},
        {name = "Золотой", r = 255, g = 215, b = 0},
        {name = "Серебряный", r = 192, g = 192, b = 192},
    },
}
Config.Chat = {
    MaxMessageLength = 500,
    MaxHistorySize = 100,
    MaxHistoryAge = 3600,
    MaxPrivateMessageLength = 300,
}
Config.RateLimits = {
    CommandCooldown = 5,
    GlobalLLMCooldown = 3,
    MaxRequestsPerSecond = 3,
    MaxRequestsPerMinute = 30,
    MaxRequestsPerHour = 300,
}
Config.Providers = {
    LLM = {
        Default = "openai",
        List = {
            {id = "openai", name = "OpenAI (ChatGPT)", needsKey = true},
            {id = "deepseek", name = "DeepSeek", needsKey = true},
            {id = "anthropic", name = "Anthropic (Claude)", needsKey = true},
            {id = "google", name = "Google Gemini", needsKey = true},
            {id = "grok", name = "Grok (xAI)", needsKey = true},
        },
        Defaults = {
            openai = {model = "gpt-4o-mini", endpoint = "https://api.openai.com/v1/chat/completions"},
            deepseek = {model = "deepseek-chat", endpoint = "https://api.deepseek.com/v1/chat/completions"},
            anthropic = {model = "claude-3-haiku-20240307", endpoint = "https://api.anthropic.com/v1/messages"},
            google = {model = "gemini-1.5-flash", endpoint = "https://generativelanguage.googleapis.com/v1beta/models"},
            grok = {model = "grok-2-1212", endpoint = "https://api.x.ai/v1/chat/completions"},
        },
    },
    TTS = {
        Default = "elevenlabs",
        List = {
            {id = "elevenlabs", name = "ElevenLabs", needsKey = true},
            {id = "google", name = "Google Cloud TTS", needsKey = true},
            {id = "yandex", name = "Yandex SpeechKit (MP3)", needsKey = true, needsFolder = true},
            {id = "vk", name = "VK Cloud Voice (MP3)", needsKey = true},
        },
        Defaults = {
            elevenlabs = {voice = "21m00Tcm4TlvDq8ikWAM", model = "eleven_monolingual_v1"},
            google = {voice = "ru-RU-Wavenet-D", language = "ru-RU"},
            yandex = {voice = "oksana", language = "ru-RU"},
            vk = {voice = "katherine", encoder = "mp3", tempo = 1.0},
        },
    },
}
Config.Commands = {
    AttackRadius = 2000,
}
Config.Appearance = {
    RainbowSpeed = 120,
}
Config.Cleanup = {
    HistoryInterval = 600,
    LLMCleanupInterval = 300,
    OwnershipCleanupInterval = 60,
    CacheCleanupInterval = 300,
}
Config.Magic = {
    HTTP = {
        MaxBodySize = 100000,
        DefaultTimeout = 10,
    },
    Navigation = {
        AreaCacheTime = 0.35,
        MaxPathRetries = 4,
        NavDisabledTime = 3,
        JumpCheckDist = 65,
        MaxWaypointAdvance = 12,
        StairsSkipTime = 1.5,
        StairsMinMoveSq = 225,
        ForceWPSkipTime = 2.5,
        ForceWPSkipMinMove = 100,
        HeightSkipTime = 1.5,
        WaypointAdvanceThreshold = 5,
        StuckDistSq = 36,
        StuckFallZDiff = 40,
        StuckFallXYDist = 200,
        DebugOverlayTime = 0.1,
        DirectPathDistSq = 65536,
        StairsFlatDist = 150,
        StairsHeightDiff = 120,
        NavmeshDistSq = 262144,
        WeaponSwitchTime = 1.0,
        ReplaceDelay = 0.5,
        MinGoalMoveForRepath = 16384,
        StrafeWallClearance = 24,
        RecalcInterval = 1.0,
        MaxIterations = 1500,
        TeleportDist = 2000,
        LookaheadDist = 56,
        CloseFollowDistSq = 6400,
        DebugOverlayInterval = 1.0,
        UnstuckTime = 0.7,
        UnstuckDuration = 0.45,
        LadderTimeout = 4,
        FastDist = 700,
        MediumDist = 260,
        WalkSlow = 200,
        DirectPathMaxDistSq = 160000,
        WallRepathDelay = 5.0,
        AvoidanceRadius = 64,
        MaxClimbHeight = 40,
        NoclipHeightThreshold = 50,
        NoclipTeleportCheckDist = 500,
    },
    Speeds = {
        Walk = 200,
        WalkSlow = 150,
        Run = 320,
        Stealth = 80,
        Crouch = 90,
        Min = 80,
        Max = 340,
        Melee = 400,
        Combat = 220,
        Flee = 350,
        Dodge = 350,
    },
    Combat = {
        MeleeDist = 110,
        FragMinDist = 150,
        FragMaxDist = 600,
        RPGDist = 500,
        IdealDist = 300,
        GrenadeDodgeRadius = 250,
        GrenadeDangerDist = 110,
        CombatForgetRadius = 240000,
        FragCooldown = 5.0,
        RPGCooldown = 0.1,
        AltFireCooldown = 2.0,
        WeaponSwitchDelay = 5,
        HealCooldown = 1.2,
        MedicPostCombatCooldown = 3.0,
        ThreatScanRadius = 1500,
        ThreatScanInterval = 2.0,
        EnemyCacheInterval = 2.0,
        StrafeMinInterval = 0.4,
        StrafeMaxInterval = 2.0,
        StrafeDist = 60,
        CombatStrafeDist = 100,
        HealThresholdOwner = 0.7,
        HealThresholdSelf = 0.5,
        HealRange = 72,
        AimDotThreshold = 0.85,
        MeleeGiveCooldown = 1.0,
        MeleeApproachDist = 30,
        AmmoGiveAmount = 100,
        DefaultClipSize = 30,
        CommandAttackRadius = 2000,
        CombatIdleTimeout = 10.0,
        GrenadeUpdateInterval = 0.3,
        FragThrowAngle = 15,
        SteerMultiplier = 1.35,
        WallSteerMultiplier = 1.5,
        MoveForwardDist = 150,
        MoveBackDist = 110,
        CombatBackDist = 110,
        ExitVehicleDelay = 0.1,
        AmmoCheckInterval = 2.0,
        DodgeSpeed = 350,
        MeleeSpeed = 400,
        CombatSpeed = 220,
        FleeSpeed = 350,
    },
    Vehicle = {
        BulletSpeed = 8000,
        LeadTime = 0.3,
        BulletDamage = 12,
        BulletForce = 50,
        BulletHullSize = 2,
        BulletSpread = 0.02,
        MissileDist = 800,
        MissileChance = 0.3,
        HeliLeadTime = 0.4,
        HeliCircleRadius = 280,
        HeliCircleMultiplier = 0.3,
        HeliCircleHeight = 140,
        HeliFollowHeight = 130,
        HeliFollowDist = 180,
        HeliMinTurnDist = 50,
        HeliMaxYaw = 0.8,
        HeliYawMultiplier = 1.5,
        HeliPitchDivisor = 350,
        HeliRollMultiplier = 0.25,
        HeliRollDivisor = 700,
        HeliPitchYawMultiplier = 0.3,
        HeliHeightMultiplier = 0.0035,
        HeliZMultiplier = 0.005,
        HeliHeightDeadZone = 60,
        HeliUpMinThrottle = 0.65,
        HeliDownMaxThrottle = 0.35,
        HeliMinGroundHeight = 70,
        HeliGroundThrottle = 0.85,
        HeliGroundPitchClamp = 0.12,
        HeliSmoothSpeed = 1.6,
        TankMinAimTime = 1.5,
        TankBulletSpeed = 5000,
        TankAimDotThreshold = 0.92,
        TankAttackHoldTime = 0.15,
        TankAttackReleaseDelay = 0.2,
        EngineStopCooldown = 2.0,
        ObstacleOffsetY = 40,
        ObstacleDistance = 450,
        ObstacleStrafeMultiplier = 0.3,
        FullThrottleDist = 800,
        MidThrottleDist = 500,
        MinThrottle = 0.2,
        ObstacleThrottleMultiplier = 0.8,
        ObstacleMinThrottle = 0.2,
        ReverseDist = 260,
        ReverseThrottle = 0.4,
        SteerThreshold = 0.1,
        VehicleEnterDelay = 0.1,
        VehicleExitDist = 300,
        VehicleSearchRadius = 500,
        HeliFollowMaxSpeed = 240,
        HeliFollowApproachDist = 350,
        HeliFollowDeadZone = 100,
        HeliEnemyMaxSpeed = 400,
        HeliEnemyApproachDist = 200,
        HeliHeightDeadZone = 20,
        HeliMaxPitch = 0.28,
        HeliMaxRoll = 0.28,
        HeliDampingFactor = 0.10,
        HeliSoftAltLimit = 200,
        HeliHardAltLimit = 350,
        HeliDownForceMax = 8000,
        HeliUpForceMax = 4000,
        HeliForceDeadZone = 30,
        EngineDeadZoneEnter = 120,
        EngineDeadZoneExit = 180,
        EngineStopDelay = 1.5,
        EngineIdleTimeout = 25.0,
    },
    Spawn = {
        MaxArmor = 100,
        SpawnArmor = 100,
        ArmorRetryCount = 30,
        ArmorRetryInterval = 0.1,
        ForceStandInterval = 0.05,
        ForceStandIterations = 200,
        FinalStageDelay = 4.00,
        RegisterDelay = 0.1,
        RemoveDelay = 0.5,
        MaxBotsTotal = 10,
        MaxBotsPerPlayer = 1,
        SpawnGraceDuration = 10,
        HealthkitLifetime = 30,
    },
    LLM = {
        MaxHistoryPairs = 5,
        MaxTTSConcurrent = 5,
        CheckInterval = 30,
        SoloCooldown = 5,
        GlobalCooldown = 3,
        MaxMessageLength = 300,
        FallbackHistorySize = 20,
        MinHistorySize = 4,
        TTSRetryInterval = 2.0,
        TTSCheckInterval = 1.0,
        TTSMaxAttempts = 50,
        TTSTimeout = 10,
        SoloCleanupDelay = 0.1,
        PingTimeout = 6,
        MenuUpdateDelay = 0.5,
        ProviderCacheTTL = 60,
    },
    TTS = {
        CacheSize = 50,
        CacheTTL = 300,
        MaxConcurrent = 5,
        DefaultVoice = "21m00Tcm4TlvDq8ikWAM",
        DefaultModel = "eleven_monolingual_v1",
        AudioCacheLifetime = 30,
        MaxTextLength = 500,
        ElevenLabsStability = 0.5,
        ElevenLabsSimilarity = 0.5,
    },
    Misc = {
        RainbowSpeed = 120,
        HistoryInterval = 600,
        LLMCleanupInterval = 300,
        OwnershipCleanupInterval = 60,
        CacheCleanupInterval = 300,
        MigrationDelay = 2,
        SettingsLoadDelay = 1,
        SyncDelay = 0.1,
        CheckDelay = 0.1,
    },
}
function Config.GetLLMURL()
    local ip = (storage.Settings and storage.Settings.llm_ip) or Config.Network.LLM.IP
    local port = (storage.Settings and storage.Settings.llm_port) or Config.Network.LLM.Port
    return string.format("http://%s:%d/v1/chat/completions", ip, port)
end
function Config.GetTTSURL()
    local ip = (storage.Settings and storage.Settings.comfyui_ip) or Config.Network.TTS.IP
    local port = (storage.Settings and storage.Settings.comfyui_port) or Config.Network.TTS.Port
    return string.format("http://%s:%d", ip, port)
end
function Config.GetLLMProvider(id)
    for _, p in ipairs(Config.Providers.LLM.List) do
        if p.id == id then return p end
    end
    return nil
end
function Config.GetTTSProvider(id)
    for _, p in ipairs(Config.Providers.TTS.List) do
        if p.id == id then return p end
    end
    return nil
end
function Config.GetLLMProviderDefaults(id)
    return Config.Providers.LLM.Defaults[id] or {}
end
function Config.GetTTSProviderDefaults(id)
    return Config.Providers.TTS.Defaults[id] or {}
end
if _G.AI_CONFIG and getmetatable(_G.AI_CONFIG) then
    print("[AI Config] Прокси AI_CONFIG активен")
else
    _G.AI_CONFIG = setmetatable({}, {
        __index = function(t, k)
            return Config[k]
        end,
        __newindex = function(t, k, v)
            local info = debug.getinfo(2)
            local source = info and info.source or ""
            if source and string.find(source, "ai_companion") then
                Config[k] = v
                return
            end
            ErrorNoHalt("[AI Config] ⛔ БЛОКИРОВКА записи в AI_CONFIG." .. tostring(k) .. "\n")
        end,
        __metatable = false,
    })
    print("[AI Config] Создан прокси AI_CONFIG (state.lua не найден)")
end
if _G.AI_COMPANION and _G.AI_COMPANION.MergeConfig then
    _G.AI_COMPANION.MergeConfig()
    print("[AI Config] Конфиг смержен с хранилищем")
end
print("[AI Config] Загружен")
concommand.Add("ai_config_check", function(ply)
    if IsValid(ply) and not ply:IsAdmin() then
        ply:ChatPrint("[AI] Только администраторы!")
        return
    end
    print("")
    print("═══════════════════════════════════════════════════════")
    print("        AI CONFIG - ПРОВЕРКА")
    print("═══════════════════════════════════════════════════════")
    print("")
    print("  Config.Network.LLM.IP: " .. tostring(Config.Network.LLM.IP))
    print("  Config.Network.LLM.Port: " .. tostring(Config.Network.LLM.Port))
    print("  Config.Magic.HTTP.MaxBodySize: " .. tostring(Config.Magic.HTTP.MaxBodySize))
    print("  Config.Magic.Combat.MeleeDist: " .. tostring(Config.Magic.Combat.MeleeDist))
    print("")
    print("  AI_CONFIG == Config: " .. tostring(_G.AI_CONFIG == Config))
    print("  AI_CONFIG.Network.LLM.IP: " .. tostring(_G.AI_CONFIG.Network.LLM.IP))
    print("  AI_CONFIG.Magic.Combat.MeleeDist: " .. tostring(_G.AI_CONFIG.Magic.Combat.MeleeDist))
    print("")
    print("  storage.Config == Config: " .. tostring(storage.Config == Config))
    print("  storage.Config.Magic.Combat.MeleeDist: " .. tostring(storage.Config.Magic.Combat.MeleeDist))
    print("═══════════════════════════════════════════════════════")
    print("")
    if IsValid(ply) then
        ply:ChatPrint("[AI] Проверка конфига завершена, результат в консоли")
    end
end)