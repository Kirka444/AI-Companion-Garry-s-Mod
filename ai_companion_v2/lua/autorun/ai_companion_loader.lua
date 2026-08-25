if AI_COMPANION_LOADER_LOADED then return end
AI_COMPANION_LOADER_LOADED = true
local LoaderState = {
    loadedModules = {},
    loadErrors = {},
    startTime = SysTime(),
    isSolo = game.SinglePlayer(),
}
local ALL_MODULES = {
    "ai_companion/ai_companion_state.lua",
    "ai_companion/ai_config.lua",
    "ai_companion/ai_companion_utils.lua",
    "ai_companion/ai_companion_data.lua",
    "ai_companion/ai_companion_botmanager.lua",
    "ai_companion/ai_companion_shared.lua",
    "ai_companion/ai_companion_core.lua",
    "ai_companion/ai_companion_settings.lua",
    "ai_companion/ai_companion_spawn.lua",
    "ai_companion/ai_companion_movement.lua",
    "ai_companion/ai_companion_combat.lua",
    "ai_companion/ai_companion_vehicle.lua",
    "ai_companion/ai_companion_commands.lua",
    "ai_companion/ai_companion_llm.lua",
    "ai_companion/ai_companion_tts.lua",
    "ai_companion/ai_companion_llm_actions.lua",
    "ai_companion/ai_companion_client.lua",
    "ai_companion/ai_companion_menu.lua",
    "ai_companion/ai_companion_solo.lua",
    "ai_companion/ai_companion_afk.lua",
}
local SERVER_MODULES = {
    "ai_companion/ai_companion_state.lua",
    "ai_companion/ai_config.lua",
    "ai_companion/ai_companion_utils.lua",
    "ai_companion/ai_companion_data.lua",
    "ai_companion/ai_companion_botmanager.lua",
    "ai_companion/ai_companion_shared.lua",
    "ai_companion/ai_companion_core.lua",
    "ai_companion/ai_companion_settings.lua",
    "ai_companion/ai_companion_spawn.lua",
    "ai_companion/ai_companion_movement.lua",
    "ai_companion/ai_companion_combat.lua",
    "ai_companion/ai_companion_vehicle.lua",
    "ai_companion/ai_companion_commands.lua",
    "ai_companion/ai_companion_llm.lua",
    "ai_companion/ai_companion_tts.lua",
    "ai_companion/ai_companion_llm_actions.lua",
    "ai_companion/ai_companion_afk.lua",
}
local CLIENT_MODULES = {
    "ai_companion/ai_companion_state.lua",
    "ai_companion/ai_config.lua",
    "ai_companion/ai_companion_utils.lua",
    "ai_companion/ai_companion_shared.lua",
    "ai_companion/ai_companion_data.lua",
    "ai_companion/ai_companion_botmanager.lua",
    "ai_companion/ai_companion_core.lua",
    "ai_companion/ai_companion_settings.lua",
    "ai_companion/ai_companion_client.lua",
    "ai_companion/ai_companion_menu.lua",
    "ai_companion/ai_companion_llm.lua",
    "ai_companion/ai_companion_tts.lua",
    "ai_companion/ai_companion_llm_actions.lua",
}
local CLIENT_SEND_MODULES = {
    "ai_companion/ai_companion_state.lua",
    "ai_companion/ai_config.lua",
    "ai_companion/ai_companion_utils.lua",
    "ai_companion/ai_companion_shared.lua",
    "ai_companion/ai_companion_data.lua",
    "ai_companion/ai_companion_botmanager.lua",
    "ai_companion/ai_companion_core.lua",
    "ai_companion/ai_companion_settings.lua",
    "ai_companion/ai_companion_client.lua",
    "ai_companion/ai_companion_menu.lua",
    "ai_companion/ai_companion_llm.lua",
    "ai_companion/ai_companion_tts.lua",
    "ai_companion/ai_companion_llm_actions.lua",
}
local SOLO_MODULES = {
    "ai_companion/ai_companion_state.lua",
    "ai_companion/ai_config.lua",
    "ai_companion/ai_companion_utils.lua",
    "ai_companion/ai_companion_shared.lua",
    "ai_companion/ai_companion_settings.lua",
    "ai_companion/ai_companion_core.lua",
    "ai_companion/ai_companion_llm.lua",
    "ai_companion/ai_companion_tts.lua",
    "ai_companion/ai_companion_llm_actions.lua",
    "ai_companion/ai_companion_client.lua",
    "ai_companion/ai_companion_menu.lua",
    "ai_companion/ai_companion_solo.lua",
}
local function SafeInclude(modulePath)
    local fileKey = string.gsub(modulePath, "[./]", "_")
    local loadedKey = "_AI_LOADED_" .. fileKey
    if _G[loadedKey] then
        return true
    end
    if SERVER then
        if not file.Exists(modulePath, "LUA") then
            LoaderState.loadErrors[modulePath] = "  "
            return false
        end
        local ok, err = pcall(include, modulePath)
        if not ok then
            LoaderState.loadErrors[modulePath] = tostring(err)
            return false
        end
        _G[loadedKey] = true
        LoaderState.loadedModules[modulePath] = true
        return true
    end
    local ok, err = pcall(include, modulePath)
    if ok then
        _G[loadedKey] = true
        LoaderState.loadedModules[modulePath] = true
        return true
    else
        LoaderState.loadErrors[modulePath] = tostring(err)
        return false
    end
end
local function LoadModuleList(modules, label)
    if not modules or #modules == 0 then
        return 0, 0
    end
    local loaded = 0
    local errors = 0
    for _, file in ipairs(modules) do
        if SafeInclude(file) then
            loaded = loaded + 1
        else
            errors = errors + 1
        end
    end
    return loaded, errors
end
local function LoadLocalization()
    if not _L then
        local locales = {
            "ai_companion/locales/init.lua",
            "ai_companion/locales/ru.lua",
            "ai_companion/locales/en.lua",
        }
        for _, localeFile in ipairs(locales) do
            if SERVER then
                if file.Exists(localeFile, "LUA") then
                    pcall(include, localeFile)
                end
            else
                pcall(include, localeFile)
            end
        end
    end
    if _L and not _G.L then
        _G.L = _L
    end
end
local function CheckAllModulesLoaded()
    local allLoaded = true
    local missing = {}
    for _, file in ipairs(ALL_MODULES) do
        local fileKey = string.gsub(file, "[./]", "_")
        if not _G["_AI_LOADED_" .. fileKey] then
            allLoaded = false
            table.insert(missing, file)
        end
    end
    return allLoaded, missing
end
local function GetModuleStatus(file)
    local fileKey = string.gsub(file, "[./]", "_")
    local isLoaded = _G["_AI_LOADED_" .. fileKey] or false
    local error = LoaderState.loadErrors[file]
    return {
        loaded = isLoaded,
        error = error,
        file = file,
    }
end
if SERVER then
    for _, file in ipairs(CLIENT_SEND_MODULES) do
        AddCSLuaFile(file)
    end
    LoadLocalization()
    if game.SinglePlayer() then
        local loaded, errors = LoadModuleList(SOLO_MODULES, "-")
        LoaderState.isSolo = true
        LoaderState.phase = "solo"
        LoaderState.complete = (errors == 0)
        return
    end
    local loaded, errors = LoadModuleList(SERVER_MODULES, "")
    LoaderState.isSolo = false
    LoaderState.phase = "server"
    LoaderState.complete = (errors == 0)
    concommand.Add("ai_modules_status", function(ply)
        if IsValid(ply) and not ply:IsAdmin() then
            ply:ChatPrint("[AI]  !")
            return
        end
        print("")
        print("")
        print("        AI COMPANION -  ")
        print("")
        print("")
        print("  : " .. (LoaderState.isSolo and "" or ""))
        print("  : " .. (LoaderState.phase or ""))
        print("   : " .. string.format("%.2f", SysTime() - LoaderState.startTime) .. "")
        print("")
        print(string.rep("", 60))
        print("")
        local loaded = 0
        local missing = 0
        local errors = 0
        for _, file in ipairs(ALL_MODULES) do
            local status = GetModuleStatus(file)
            if status.loaded then
                loaded = loaded + 1
                print("  " .. file)
            else
                missing = missing + 1
                if status.error then
                    errors = errors + 1
                    print("  " .. file .. " (: " .. status.error .. ")")
                else
                    print("  " .. file .. " ( )")
                end
            end
        end
        print("")
        print(string.rep("", 60))
        print(string.format("  : %d", loaded))
        print(string.format("  : %d", missing))
        if errors > 0 then
            print(string.format("   : %d", errors))
        end
        print("")
        print("")
        if IsValid(ply) then
            ply:ChatPrint("[AI]     ")
        end
    end)
    concommand.Add("ai_check_modules", function(ply)
        if IsValid(ply) and not ply:IsAdmin() then
            ply:ChatPrint("[AI]  !")
            return
        end
        local allLoaded, missing = CheckAllModulesLoaded()
        if allLoaded then
            if IsValid(ply) then
                ply:ChatPrint("[AI]   !")
            end
        else
            if IsValid(ply) then
                ply:ChatPrint("[AI]  : " .. #missing .. " (. )")
            end
        end
    end)
    concommand.Add("ai_reload_module", function(ply, cmd, args)
        if not IsValid(ply) or not ply:IsAdmin() then
            if IsValid(ply) then
                ply:ChatPrint("[AI]  !")
            end
            return
        end
        if #args < 1 then
            ply:ChatPrint("[AI] : ai_reload_module <_>")
            return
        end
        local fileName = args[1]
        if not string.find(fileName, "%.lua$") then
            fileName = fileName .. ".lua"
        end
        if not string.find(fileName, "^ai_companion/") then
            fileName = "ai_companion/" .. fileName
        end
        if SERVER and not file.Exists(fileName, "LUA") then
            ply:ChatPrint("[AI]   : " .. fileName)
            return
        end
        local fileKey = string.gsub(fileName, "[./]", "_")
        local loadedKey = "_AI_LOADED_" .. fileKey
        _G[loadedKey] = nil
        LoaderState.loadedModules[fileName] = nil
        LoaderState.loadErrors[fileName] = nil
        if SafeInclude(fileName) then
            ply:ChatPrint("[AI]  : " .. fileName)
        else
            ply:ChatPrint("[AI]   : " .. fileName)
        end
    end)
end
if SERVER == false then
    LoadLocalization()
    if game.SinglePlayer() then
        local loaded, errors = LoadModuleList(SOLO_MODULES, "- ()")
        LoaderState.isSolo = true
        LoaderState.phase = "solo_client"
        LoaderState.complete = (errors == 0)
        return
    end
    local loaded, errors = LoadModuleList(CLIENT_MODULES, "")
    LoaderState.isSolo = false
    LoaderState.phase = "client"
    LoaderState.complete = (errors == 0)
end
_G.AI_LOADER = {
    isSolo = LoaderState.isSolo,
    phase = LoaderState.phase,
    complete = LoaderState.complete,
    startTime = LoaderState.startTime,
    allModules = ALL_MODULES,
    serverModules = SERVER_MODULES,
    clientModules = CLIENT_MODULES,
    soloModules = SOLO_MODULES,
    getStatus = GetModuleStatus,
    checkAllLoaded = CheckAllModulesLoaded,
    getLoadedModules = function() return table.Copy(LoaderState.loadedModules) end,
    getErrors = function() return table.Copy(LoaderState.loadErrors) end,
}
if not _G.AI_LOADED_MODULES then
    _G.AI_LOADED_MODULES = LoaderState.loadedModules
end
if not _G.AI_LOAD_ERRORS then
    _G.AI_LOAD_ERRORS = LoaderState.loadErrors
end
if not _G.AI_CheckAllModulesLoaded then
    _G.AI_CheckAllModulesLoaded = CheckAllModulesLoaded
end