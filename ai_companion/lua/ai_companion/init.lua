local IS_SERVER = SERVER == true
local IS_CLIENT = CLIENT == true
local IS_SOLO = game.SinglePlayer() == true

-- ============================================================
-- ДОБАВЛЯЕМ ВСЕ КЛИЕНТСКИЕ ФАЙЛЫ В AddCSLuaFile (только на сервере)
-- ============================================================
if SERVER then
    -- Ядро
    AddCSLuaFile("ai_companion/services/servicelocator.lua")
    AddCSLuaFile("ai_companion/init.lua")
    AddCSLuaFile("ai_companion/locales/init.lua")
	AddCSLuaFile("ai_companion/locales/languages.lua")
    -- Общие сервисы
    AddCSLuaFile("ai_companion/locales/init.lua")
    AddCSLuaFile("ai_companion/services/utils.lua")
    AddCSLuaFile("ai_companion/services/config.lua")
    AddCSLuaFile("ai_companion/services/logger.lua")
    AddCSLuaFile("ai_companion/services/state.lua")
    AddCSLuaFile("ai_companion/services/shared.lua")
    
    -- Клиентские сервисы
    AddCSLuaFile("ai_companion/services/client.lua")
    AddCSLuaFile("ai_companion/services/menu.lua")
    AddCSLuaFile("ai_companion/services/llm_remember.lua")
end

-- ============================================================
-- ЛОКАТОР
-- ============================================================
local function getOrCreateLocator()
    local registry = debug.getregistry()
    local REGISTRY_KEY = "__AI_COMPANION_LOCATOR_v2"

    local locator = registry[REGISTRY_KEY]
    if locator then
        return locator
    end

    print("[AI Companion] Создаём локатор для", IS_SERVER and "СЕРВЕРА" or "КЛИЕНТА")

    local ServiceLocator = include("ai_companion/services/servicelocator.lua")
    if not ServiceLocator then
        error("[AI Companion] НЕ УДАЛОСЬ ЗАГРУЗИТЬ СЕРВИС-ЛОКАТОР!")
    end

    return ServiceLocator
end

local locator = getOrCreateLocator()

_G.AI_GetLocator = function()
    local reg = debug.getregistry()
    local loc = reg["__AI_COMPANION_LOCATOR_v2"]
    if not loc then
        error("[AI Companion] Локатор не найден на " .. (SERVER and "сервере" or "клиенте") .. "!")
    end
    return loc
end

print("[AI Companion] Регистрация фабрик на", IS_SERVER and "сервере" or "клиенте")

locator:register("locale", function()
    local Locale = include("ai_companion/locales/init.lua")
    if not Locale then error("[AI Companion] Не удалось загрузить locales/init.lua") end
    return Locale:new()
end)

locator:register("utils", function()
    local Utils = include("ai_companion/services/utils.lua")
    if not Utils then error("[AI Companion] Не удалось загрузить utils.lua") end
    return Utils:new()
end)

locator:register("config", function()
    local utils = locator:get("utils")
    local Config = include("ai_companion/services/config.lua")
    if not Config then error("[AI Companion] Не удалось загрузить config.lua") end
    return Config:new(utils)
end)

locator:register("logger", function()
    local utils = locator:get("utils")
    local config = locator:get("config")
    local Logger = include("ai_companion/services/logger.lua")
    if not Logger then error("[AI Companion] Не удалось загрузить logger.lua") end
    return Logger:new(utils, config)
end)

locator:register("state", function()
    local utils = locator:get("utils")
    local config = locator:get("config")
    local State = include("ai_companion/services/state.lua")
    if not State then error("[AI Companion] Не удалось загрузить state.lua") end
    return State:new(utils, config)
end)

locator:register("shared", function()
    local utils = locator:get("utils")
    local config = locator:get("config")
    local state = locator:get("state")
    local Shared = include("ai_companion/services/shared.lua")
    if not Shared then error("[AI Companion] Не удалось загрузить shared.lua") end
    return Shared:new(utils, config, state)
end)

if IS_SERVER then
    locator:register("data", function()
        local state = locator:get("state")
        local config = locator:get("config")
        local utils = locator:get("utils")
        local Data = include("ai_companion/services/data.lua")
        if not Data then error("[AI Companion] Не удалось загрузить data.lua") end
        return Data:new(state, config, utils)
    end)

    locator:register("botmanager", function()
        local state = locator:get("state")
        local data = locator:get("data")
        local utils = locator:get("utils")
        local BotManager = include("ai_companion/services/botmanager.lua")
        if not BotManager then error("[AI Companion] Не удалось загрузить botmanager.lua") end
        return BotManager:new(state, data, utils)
    end)

    locator:register("spawn", function()
        local utils = locator:get("utils")
        local config = locator:get("config")
        local state = locator:get("state")
        local data = locator:get("data")
        local botmanager = locator:get("botmanager")
        local Spawn = include("ai_companion/services/spawn.lua")
        if not Spawn then error("[AI Companion] Не удалось загрузить spawn.lua") end
        return Spawn:new(utils, config, state, data, botmanager)
    end)

    locator:register("llm", function()
        local utils = locator:get("utils")
        local config = locator:get("config")
        local state = locator:get("state")
        local LLM = include("ai_companion/services/llm.lua")
        if not LLM then error("[AI Companion] Не удалось загрузить llm.lua") end
        return LLM:new(utils, config, state)
    end)

    locator:register("tts", function()
        local utils = locator:get("utils")
        local config = locator:get("config")
        local state = locator:get("state")
        local TTS = include("ai_companion/services/tts.lua")
        if not TTS then error("[AI Companion] Не удалось загрузить tts.lua") end
        return TTS:new(utils, config, state)
    end)

    locator:register("vehicle", function()
        local utils = locator:get("utils")
        local config = locator:get("config")
        local state = locator:get("state")
        local data = locator:get("data")
        local Vehicle = include("ai_companion/services/vehicle.lua")
        if not Vehicle then error("[AI Companion] Не удалось загрузить vehicle.lua") end
        return Vehicle:new(utils, config, state, data)
    end)

    locator:register("commands", function()
        local utils = locator:get("utils")
        local config = locator:get("config")
        local state = locator:get("state")
        local botmanager = locator:get("botmanager")
        local spawn = locator:get("spawn")
        local llm = locator:get("llm")
        local tts = locator:get("tts")
        local shared = locator:get("shared")
        local vehicle = locator:get("vehicle")

        local Commands = include("ai_companion/services/commands.lua")
        if not Commands then error("[AI Companion] Не удалось загрузить commands.lua") end

        return Commands:new(utils, config, state, botmanager, spawn, llm, tts, shared, vehicle)
    end)

    locator:register("llm_actions", function()
        local utils = locator:get("utils")
        local config = locator:get("config")
        local state = locator:get("state")
        local llm = locator:get("llm")
        local commands = locator:get("commands")
        local spawn = locator:get("spawn")
        local botmanager = locator:get("botmanager")
        local shared = locator:get("shared")
        local LLMActions = include("ai_companion/services/llm_actions.lua")
        if not LLMActions then error("[AI Companion] Не удалось загрузить llm_actions.lua") end
        return LLMActions:new(utils, config, state, llm, commands, spawn, botmanager, shared)
    end)

    locator:register("llm_remember", function()
        local utils = locator:get("utils")
        local config = locator:get("config")
        local state = locator:get("state")
        local llm = locator:get("llm")
        local shared = locator:get("shared")
        local LLMRemember = include("ai_companion/services/llm_remember.lua")
        if not LLMRemember then error("[AI Companion] Не удалось загрузить llm_remember.lua") end
        return LLMRemember:new(utils, config, state, llm, shared)
    end)

    locator:register("combat", function()
        local utils = locator:get("utils")
        local config = locator:get("config")
        local state = locator:get("state")
        local data = locator:get("data")
        local botmanager = locator:get("botmanager")
        local shared = locator:get("shared")
        local Combat = include("ai_companion/services/combat.lua")
        if not Combat then error("[AI Companion] Не удалось загрузить combat.lua") end
        return Combat:new(utils, config, state, data, botmanager, shared)
    end)

    locator:register("movement", function()
        local utils = locator:get("utils")
        local config = locator:get("config")
        local state = locator:get("state")
        local data = locator:get("data")
        local botmanager = locator:get("botmanager")
        local Movement = include("ai_companion/services/movement/init.lua")
        if not Movement then error("[AI Companion] Не удалось загрузить movement/init.lua") end
        return Movement:new(utils, config, state, data, botmanager)
    end)

    locator:register("afk", function()
        local utils = locator:get("utils")
        local config = locator:get("config")
        local state = locator:get("state")
        local botmanager = locator:get("botmanager")
        local spawn = locator:get("spawn")
        local commands = locator:get("commands")
        local shared = locator:get("shared")
        local AFK = include("ai_companion/services/afk.lua")
        if not AFK then error("[AI Companion] Не удалось загрузить afk.lua") end
        return AFK:new(utils, config, state, botmanager, spawn, commands, shared)
    end)
end

if IS_CLIENT then

    locator:register("botmanager", function()
        return {
            GetBotByOwner = function() return nil end,
            GetAllBots = function() return {} end,
            GetBotCount = function() return 0 end,
            HasBot = function() return false end,
            GetData = function() return nil end,
            GetUUID = function() return nil end,
            IsCompanionBot = function(ent)
                return IsValid(ent) and ent:IsPlayer() and ent:GetNWBool("IsAICompanion", false)
            end,
            GetBotState = function() return "idle" end,
        }
    end)

    locator:register("client", function()
        local utils = locator:get("utils")
        local config = locator:get("config")
        local state = locator:get("state")
        local shared = locator:get("shared")
        local Client = include("ai_companion/services/client.lua")
        if not Client then error("[AI Companion] Не удалось загрузить client.lua") end
        return Client:new(utils, config, state, shared)
    end)

    locator:register("llm_remember", function()
        local utils = locator:get("utils")
        local config = locator:get("config")
        local state = locator:get("state")
        local shared = locator:get("shared")
        local LLMRemember = include("ai_companion/services/llm_remember.lua")
        if not LLMRemember then error("[AI Companion] Не удалось загрузить llm_remember.lua") end
        return LLMRemember:new(utils, config, state, nil, shared)
    end)

    locator:register("menu", function()
        local utils = locator:get("utils")
        local config = locator:get("config")
        local state = locator:get("state")
        local client = locator:get("client")
        local shared = locator:get("shared")
        local botmanager = locator:get("botmanager")
        local locale = locator:get("locale")

        local Menu = include("ai_companion/services/menu.lua")
        if not Menu then error("[AI Companion] Не удалось загрузить menu.lua") end
        return Menu:new(utils, config, state, client, shared, botmanager, locale)
    end)
end

print("[AI Companion] 🔥 Агрессивная загрузка ВСЕХ сервисов...")

local allServices = {
    "locale", "utils", "config", "state", "shared",
    "data", "botmanager", "spawn", "llm", "logger", "tts", "vehicle", "commands",
    "llm_actions", "llm_remember", "combat", "movement", "afk",
    "client", "menu",
}

for _, name in ipairs(allServices) do
    if locator:has(name) then
        local factory = locator.factories[name]
        if factory then
            print("  📦 Фабрика для " .. name .. " найдена")

            local ok, svc = pcall(function()
                return factory.fn(locator, unpack(factory.args or {}))
            end)

            if ok and svc then
                print("  ✅ " .. name .. " — загружен (тип: " .. type(svc) .. ")")
                locator.services[name] = svc
                locator.factories[name] = nil
            else
                print("  ❌ " .. name .. " — ОШИБКА: " .. tostring(svc))
                print("     Трассировка:", debug.traceback())
            end
        else
            print("  ⚠️ " .. name .. " — нет фабрики")
        end
    end
end

print("[AI Companion] Инициализация сервисов...")

for _, name in ipairs(allServices) do
    local svc = locator.services[name]
    if svc and type(svc.init) == "function" and not svc._initialized then
        local ok, err = pcall(svc.init, svc, locator)
        if not ok then
            error("[AI Companion] Failed to init '" .. name .. "': " .. tostring(err))
        end
    end
end

if IS_CLIENT then
    timer.Simple(0.2, function()
        hook.Run("PopulateToolMenu")
    end)
end

_G.AI_GetLocale = function()
    local loc = _G.AI_GetLocator()
    if loc and loc:has("locale") then
        return loc:get("locale")
    end
    error("[AI Companion] Локализация не найдена в локаторе!")
end

if IS_CLIENT then
    concommand.Add("ai_companion_menu", function()
        local loc = _G.AI_GetLocator()
        if loc then
            local menu = loc:get("menu")
            if menu and menu.Open then
                menu:Open()
            end
        end
    end)
end

local locale = _G.AI_GetLocale()
print("[AI Companion] Загрузка завершена на", IS_SERVER and "сервере" or "клиенте")
print("  Режим:", IS_SOLO and "SOLO" or (IS_SERVER and "СЕРВЕР" or "КЛИЕНТ"))
print("  Локатор:", tostring(debug.getregistry()["__AI_COMPANION_LOCATOR_v2"] and "✅ АКТИВЕН" or "❌ НЕ НАЙДЕН"))
print("  Язык:", locale:GetLang())
print("  Режим загрузки: 🔥 АГРЕССИВНЫЙ (для тестирования)")

return locator
