if CLIENT then
    local function GetAIMenu()
        local getLocator = _G.AI_GetLocator
        if not getLocator then return nil end

        local ok, locator = pcall(getLocator)
        if not ok or not locator then return nil end

        if not locator:has("menu") then return nil end

        local ok2, menu = pcall(function()
            return locator:get("menu")
        end)

        if not ok2 then
            ErrorNoHalt("[AI Companion] Ошибка получения меню: " .. tostring(menu) .. "\n")
            return nil
        end

        return menu
    end

    local function GetLocaleString(key, ...)
        local getLocator = _G.AI_GetLocator
        if not getLocator then return key end

        local ok, locator = pcall(getLocator)
        if not ok or not locator then return key end

        if not locator:has("locale") then return key end

        local ok2, locale = pcall(function()
            return locator:get("locale")
        end)

        if not ok2 or not locale then return key end

        return locale:Get(key, ...)
    end

    concommand.Add("ai_companion_menu", function()
        local menu = GetAIMenu()
        if menu and menu.Open then
            menu:Open()
        else
            local errMsg = GetLocaleString("menu_unavailable", "Меню недоступно. Проверь загрузку сервиса 'menu'.")
            ErrorNoHalt("[AI Companion] " .. errMsg .. "\n")
        end
    end)

    hook.Add("PopulateToolMenu", "AICompanion_ToolMenu", function()
        spawnmenu.AddToolMenuOption(
            "Utilities",
            "AI Companion",
            "AICompanionSettings",
            GetLocaleString("AI Companion"),
            "",
            "",
            function(panel)
                panel:ClearControls()

                local btn = panel:Button(GetLocaleString("toolmenu_open", "Открыть меню AI Companion"))
                btn.DoClick = function()
                    RunConsoleCommand("ai_companion_menu")
                end

                panel:Help(GetLocaleString("toolmenu_help", "Открыть меню настроек AI Companion"))
            end
        )
    end)
end
