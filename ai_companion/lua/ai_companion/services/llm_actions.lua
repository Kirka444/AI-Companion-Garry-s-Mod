
local LLMActions = {}

function LLMActions:new(utils, config, state, llm, commands, spawn, botmanager, shared)
    local obj = {

        utils = utils,
        config = config,
        state = state,
        llm = llm,
        commands = commands,
        spawn = spawn,
        botmanager = botmanager,
        shared = shared,

        _initialized = false,
        _spawnTable = nil,
        _synonyms = nil,
    }
    setmetatable(obj, self)
    self.__index = self
    return obj
end

function LLMActions:init()
    if self._initialized then return end

    self._spawnTable = self:GetSpawnTable()

    self._synonyms = self:BuildSynonyms()

    if self.llm then

        if self.llm.ProcessResponse then
            local originalProcess = self.llm.ProcessResponse
            self.llm.ProcessResponse = function(ply, response)
                local processed = originalProcess(ply, response)
                return self:ProcessResponse(ply, processed)
            end
        else

            self.llm.ProcessResponse = function(ply, response)
                return self:ProcessResponse(ply, response)
            end
        end
    end

    if SERVER then
        self:SetupCommands()
        self:SetupChatHook()
    end

    self._initialized = true
    if self.utils then
        self.utils.LogInfo("LLMActions", "Сервис действий LLM инициализирован")
    end
end

function LLMActions:IsValid(ent)
    return self.utils and self.utils:IsValid(ent)
end

function LLMActions:SafeGetClass(ent)
    if not self:IsValid(ent) then return "invalid" end
    local ok, class = pcall(function() return ent:GetClass() end)
    return (ok and class) or "error"
end

function LLMActions:SafeGetPos(ent)
    if not self:IsValid(ent) then return Vector() end
    local ok, pos = pcall(function() return ent:GetPos() end)
    return (ok and pos) or Vector()
end

function LLMActions:GetSetting(key, default)
    if self.state then
        local val = self.state:getSetting(key)
        if val ~= nil then return val end
    end
    return default
end

function LLMActions:GetState(key, default)
    if self.state then
        local val = self.state:getState(key)
        if val ~= nil then return val end
    end
    return default
end

function LLMActions:SendAIMessage(ply, msg)
    if not self:IsValid(ply) or not SERVER then return end

    local prefixColor = Color(255, 200, 0)
    if self.utils and self.utils.GetPrefixColor then
        prefixColor = self.utils:GetPrefixColor(ply)
    end

    local cleanPrefix = "AI"
    if self.utils and self.utils.GetCleanPrefix then
        cleanPrefix = self.utils:GetCleanPrefix(ply)
    end

    if self.shared then
        self.shared:SendChatMessage(ply, msg, prefixColor, cleanPrefix, ply:Nick(), false)
    end
end

function LLMActions:GetBotManager()
    return self.botmanager
end

function LLMActions:GetCommands()
    return self.commands
end

function LLMActions:GetSpawnTable()

    local spawnTable = nil
    if self.config then
        spawnTable = self.config:get("SpawnTable")
    end

    if spawnTable and next(spawnTable) then
        return spawnTable
    end

    return {

        chair = {
            model = "models/props_c17/chair02a.mdl",
            type = "prop",
            fallback = "models/props_c17/furniturechair001a.mdl"
        },
        table = {
            model = "models/props_c17/table01a.mdl",
            type = "prop",
            fallback = "models/props_c17/furnituredesk01a.mdl"
        },
        desk = {
            model = "models/props_c17/furnituredesk01a.mdl",
            type = "prop",
            fallback = "models/props_c17/table01a.mdl"
        },
        crate = {
            model = "models/props_c17/crate01a.mdl",
            type = "prop",
            fallback = "models/props_junk/wood_crate001a.mdl"
        },
        barrel = {
            model = "models/props_c17/barrel01a.mdl",
            type = "prop",
            fallback = "models/props_junk/barrel001a.mdl"
        },
        couch = {
            model = "models/props_c17/couch01a.mdl",
            type = "prop"
        },
        bed = {
            model = "models/props_c17/bed01a.mdl",
            type = "prop"
        },
        lamp = {
            model = "models/props_c17/lamp01a.mdl",
            type = "prop"
        },
        tv = {
            model = "models/props_c17/tv01a.mdl",
            type = "prop"
        },
        monitor = {
            model = "models/props_c17/monitor01a.mdl",
            type = "prop"
        },
        computer = {
            model = "models/props_c17/computer01a.mdl",
            type = "prop"
        },
        sink = {
            model = "models/props_c17/sink01a.mdl",
            type = "prop"
        },
        toilet = {
            model = "models/props_c17/toilet01a.mdl",
            type = "prop"
        },
        bathtub = {
            model = "models/props_c17/bathtub01a.mdl",
            type = "prop"
        },
        fridge = {
            model = "models/props_c17/fridge01a.mdl",
            type = "prop"
        },
        stove = {
            model = "models/props_c17/stove01a.mdl",
            type = "prop"
        },
        microwave = {
            model = "models/props_c17/microwave01a.mdl",
            type = "prop"
        },
        shelf = {
            model = "models/props_c17/shelf01a.mdl",
            type = "prop",
            fallback = "models/props_c17/shelf02a.mdl"
        },
        pallet = {
            model = "models/props_c17/pallet01a.mdl",
            type = "prop"
        },
        crate_metal = {
            model = "models/props_junk/metal_crate001a.mdl",
            type = "prop"
        },
        crate_wood = {
            model = "models/props_junk/wood_crate001a.mdl",
            type = "prop"
        },
        dumpster = {
            model = "models/props_c17/dumpster01a.mdl",
            type = "prop"
        },
        trashcan = {
            model = "models/props_c17/trashcan01a.mdl",
            type = "prop"
        },
        bench = {
            model = "models/props_c17/bench01a.mdl",
            type = "prop"
        },

        zombie = { class = "npc_zombie", type = "npc" },
        zombie_fast = { class = "npc_fastzombie", type = "npc" },
        zombie_poison = { class = "npc_poisonzombie", type = "npc" },
        combine = { class = "npc_combine_s", type = "npc" },
        combine_elite = { class = "npc_combine_elite", type = "npc" },
        citizen = { class = "npc_citizen", type = "npc" },
        dog = { class = "npc_dog", type = "npc" },
        headcrab = { class = "npc_headcrab", type = "npc" },
        headcrab_fast = { class = "npc_headcrab_fast", type = "npc" },
        headcrab_poison = { class = "npc_headcrab_poison", type = "npc" },
        antlion = { class = "npc_antlion", type = "npc" },
        antlion_guard = { class = "npc_antlion_guard", type = "npc" },
        vortigaunt = { class = "npc_vortigaunt", type = "npc" },
        strider = { class = "npc_strider", type = "npc" },
        gunship = { class = "npc_combinegunship", type = "npc" },
        helicopter = { class = "npc_helicopter", type = "npc" },
        manhack = { class = "npc_manhack", type = "npc" },
        rollermine = { class = "npc_rollermine", type = "npc" },

        healthkit = { class = "item_healthkit", type = "item" },
        healthvial = { class = "item_healthvial", type = "item" },
        battery = { class = "item_battery", type = "item" },
        ammo = { class = "item_ammo_smg1", type = "item" },
        ammo_pistol = { class = "item_ammo_pistol", type = "item" },
        ammo_ar2 = { class = "item_ammo_ar2", type = "item" },
        ammo_buckshot = { class = "item_ammo_buckshot", type = "item" },
        ammo_357 = { class = "item_ammo_357", type = "item" },
        ammo_rpg = { class = "item_rpg_round", type = "item" },

        grenade = { class = "weapon_frag", type = "weapon" },
        rpg = { class = "weapon_rpg", type = "weapon" },
        smg1 = { class = "weapon_smg1", type = "weapon" },
        shotgun = { class = "weapon_shotgun", type = "weapon" },
        pistol = { class = "weapon_pistol", type = "weapon" },
        crowbar = { class = "weapon_crowbar", type = "weapon" },
        stunstick = { class = "weapon_stunstick", type = "weapon" },

        jeep = { class = "prop_vehicle_jeep", type = "vehicle" },
        airboat = { class = "prop_vehicle_airboat", type = "vehicle" },
        car = { class = "prop_vehicle_driveable", type = "vehicle" },
    }
end

function LLMActions:BuildSynonyms()
    return {
        chair = "chair",
        table = "table",
        desk = "table",
        crate = "crate",
        box = "crate",
        crate_wood = "crate",
        barrel = "barrel",
        drum = "barrel",
        couch = "couch",
        sofa = "couch",
        bed = "bed",
        lamp = "lamp",
        tv = "tv",
        monitor = "monitor",
        computer = "computer",
        pc = "computer",
        sink = "sink",
        toilet = "toilet",
        bathtub = "bathtub",
        tub = "bathtub",
        fridge = "fridge",
        refrigerator = "fridge",
        stove = "stove",
        oven = "stove",
        microwave = "microwave",
        dumpster = "dumpster",
        trash = "dumpster",
        bench = "bench",
        pallet = "pallet",
        shelf = "shelf",

        zombie = "zombie",
        z = "zombie",
        combine = "combine",
        soldier = "combine",
        citizen = "citizen",
        dog = "dog",

        health = "healthkit",
        medkit = "healthkit",
        healthvial = "healthvial",
        vial = "healthvial",
        battery = "battery",
        bat = "battery",
        ammo = "ammo",
        ammo_smg1 = "ammo",
        ammo_pistol = "ammo_pistol",
        pistol_ammo = "ammo_pistol",
        ammo_ar2 = "ammo_ar2",
        ar2_ammo = "ammo_ar2",
        ammo_buckshot = "ammo_buckshot",
        buckshot = "ammo_buckshot",
        ammo_357 = "ammo_357",
        magnum_ammo = "ammo_357",
        ammo_rpg = "ammo_rpg",
        rpg_ammo = "ammo_rpg",

        grenade = "grenade",
        frag = "grenade",
        rpg = "rpg",
        rocket = "rpg",
        smg1 = "smg1",
        smg = "smg1",
        shotgun = "shotgun",
        pistol = "pistol",
        crowbar = "crowbar",
        stunstick = "stunstick",

        jeep = "jeep",
        car = "car",
        vehicle = "car",
        airboat = "airboat",
        boat = "airboat",
    }
end

function LLMActions:FindPlayerByName(name)
    if not name or name == "" then return nil end

    if name == "1" or string.lower(name) == "me" or string.lower(name) == "меня" then

        return nil
    end

    name = string.lower(name)
    local bestMatch = nil
    local bestScore = 0

    for _, ply in ipairs(player.GetAll()) do
        if self:IsValid(ply) and not ply:IsBot() then
            local nick = string.lower(ply:Nick())
            if nick == name then return ply end
            if string.find(nick, name, 1, true) then
                local score = #name / #nick
                if score > bestScore then
                    bestScore = score
                    bestMatch = ply
                end
            end
        end
    end

    return bestMatch
end

function LLMActions:SpawnEntity(ply, keyword, customModel)
    if not self:IsValid(ply) then
        return false, "Игрок не валиден"
    end

    local realKeyword = self._synonyms[keyword]
    if realKeyword then
        keyword = realKeyword
    end

    local spawnTable = self:GetSpawnTable()
    local entry = spawnTable[keyword]

    if not entry then
        local found = nil
        local bestScore = 0
        for k, v in pairs(spawnTable) do
            if string.find(k, keyword, 1, true) then
                local score = #keyword / #k
                if score > bestScore then
                    bestScore = score
                    found = v
                end
            end
            if v.class and string.find(v.class, keyword, 1, true) then
                local score = #keyword / #v.class
                if score > bestScore then
                    bestScore = score
                    found = v
                end
            end
        end
        entry = found
        if not entry then
            if customModel and customModel ~= "" then
                entry = { model = customModel, type = "prop" }
            else
                return false, "Неизвестный тип: " .. keyword
            end
        end
    end

    local spawnPos
    local isItem = (entry.type == "item" or entry.type == "weapon")
    local isProp = (entry.type == "prop")
    local isNPC = (entry.type == "npc")
    local isVehicle = (entry.type == "vehicle")

    if isItem then

        spawnPos = ply:GetPos() + Vector(0, 0, 10)
    else

        spawnPos = ply:GetPos() + ply:GetForward() * 150 + Vector(0, 0, 10)
    end

    if isProp or isVehicle or isNPC then
        spawnPos = self:FindSafeSpawnPos(ply, spawnPos)
    end

    if isItem then
        local downTr = util.TraceLine({
            start = spawnPos + Vector(0, 0, 50),
            endpos = spawnPos - Vector(0, 0, 100),
            filter = ply,
            mask = MASK_PLAYERSOLID
        })
        if downTr.Hit then
            spawnPos = downTr.HitPos + Vector(0, 0, 5)
        end
    end

    local ent

    if entry.type == "prop" then
        ent = self:CreateProp(entry, spawnPos, customModel)
    elseif entry.type == "npc" then
        ent = self:CreateNPC(entry, spawnPos, keyword)
    elseif entry.type == "item" or entry.type == "weapon" then
        ent = self:CreateItem(entry, spawnPos, ply)
    elseif entry.type == "vehicle" then
        ent = self:CreateVehicle(entry, spawnPos, keyword)
    else
        return false, "Неизвестный тип объекта"
    end

    if not self:IsValid(ent) then
        return false, "Не удалось создать объект"
    end

    local effect = EffectData()
    effect:SetOrigin(spawnPos)
    effect:SetScale(1)
    util.Effect("Sparks", effect)

    return true, ent
end

function LLMActions:FindSafeSpawnPos(ply, spawnPos)
    local tr = util.TraceHull({
        start = spawnPos + Vector(0, 0, 36),
        endpos = spawnPos + Vector(0, 0, 36),
        mins = Vector(-16, -16, 0),
        maxs = Vector(16, 16, 72),
        filter = ply
    })

    if tr.Hit then

        spawnPos = ply:GetPos() + ply:GetForward() * 100 + Vector(0, 0, 10)

        local tr2 = util.TraceHull({
            start = spawnPos + Vector(0, 0, 36),
            endpos = spawnPos + Vector(0, 0, 36),
            mins = Vector(-16, -16, 0),
            maxs = Vector(16, 16, 72),
            filter = ply
        })

        if tr2.Hit then

            local right = ply:GetRight() * 80
            spawnPos = ply:GetPos() + ply:GetForward() * 100 + right + Vector(0, 0, 10)

            local tr3 = util.TraceHull({
                start = spawnPos + Vector(0, 0, 36),
                endpos = spawnPos + Vector(0, 0, 36),
                mins = Vector(-16, -16, 0),
                maxs = Vector(16, 16, 72),
                filter = ply
            })

            if tr3.Hit then

                spawnPos = ply:GetPos() + Vector(0, 0, 80)
            end
        end
    end

    return spawnPos
end

function LLMActions:CreateProp(entry, spawnPos, customModel)
    local model = entry.model or customModel
    if not model then return nil end

    local modelsToTry = { model }
    if entry.fallback then
        table.insert(modelsToTry, entry.fallback)
    end

    local chosenModel = nil
    for _, mdl in ipairs(modelsToTry) do
        if self.utils and self.utils.IsValidModel(mdl) then
            chosenModel = mdl
            break
        end
    end

    if not chosenModel then
        return nil
    end

    local ent = ents.Create("prop_physics")
    if not self:IsValid(ent) then return nil end

    ent:SetModel(chosenModel)
    ent:SetPos(spawnPos)
    ent:Spawn()
    ent:Activate()

    local phys = ent:GetPhysicsObject()
    if self:IsValid(phys) then phys:Wake() end

    return ent
end

function LLMActions:CreateNPC(entry, spawnPos, keyword)
    local class = entry.class
    if not class then return nil end

    local ent = ents.Create(class)
    if not self:IsValid(ent) then return nil end

    ent:SetPos(spawnPos)
    ent:Spawn()
    ent:Activate()

    if class == "npc_zombie" or class == "npc_combine_s" or class == "npc_antlion" then
        ent:SetKeyValue("spawnflags", "1")
    end
    if class == "npc_citizen" then
        ent:SetKeyValue("spawnflags", "1")
        ent:SetKeyValue("model", "models/alyx.mdl")
    end

    return ent
end

function LLMActions:CreateItem(entry, spawnPos, ply)
    local class = entry.class
    if not class then return nil end

    local ent = ents.Create(class)
    if not self:IsValid(ent) then return nil end

    ent:SetPos(spawnPos)
    ent:Spawn()

    if entry.type == "weapon" and ent:IsWeapon() then
        local ammoType = ent:GetPrimaryAmmoType()
        if ammoType and ammoType ~= -1 then
            ent:SetClip1(ent:GetMaxClip1() or 30)
            ply:GiveAmmo(120, ammoType, true)
        end
    end

    return ent
end

function LLMActions:CreateVehicle(entry, spawnPos, keyword)
    local class = entry.class
    if not class then return nil end

    local ent = ents.Create(class)
    if not self:IsValid(ent) then return nil end

    ent:SetPos(spawnPos)
    ent:Spawn()
    ent:Activate()

    if class == "prop_vehicle_jeep" then
        ent:SetKeyValue("vehiclescript", "scripts/vehicles/jeep_test.txt")
    end
    if class == "prop_vehicle_airboat" then
        ent:SetKeyValue("vehiclescript", "scripts/vehicles/airboat.txt")
    end

    return ent
end

function LLMActions:ProcessResponse(ply, response)
    if not self:IsValid(ply) then return response end
    if not response or response == "" then return response end

    local hasCommand = string.find(response, "!companion", 1, true)
    if not hasCommand then return response end

    local processedResponse = response
    local commandsExecuted = false

    local pattern = "!companion%s+([%a_]+)%s*(.-)%s*$"

    for i = 1, 5 do
        local cmdStart, cmdEnd, cmd, arg = string.find(processedResponse, pattern)
        if not cmdStart then break end

        local beforeCmd = string.sub(processedResponse, 1, cmdStart - 1)
        beforeCmd = string.Trim(beforeCmd)

        self:ExecuteCommand(ply, cmd, arg or "")
        commandsExecuted = true

        local afterCmd = string.sub(processedResponse, cmdEnd + 1)
        processedResponse = string.Trim(beforeCmd .. " " .. afterCmd)
    end

    if commandsExecuted and string.Trim(processedResponse) == "" then
        return ""
    end

    return processedResponse
end

function LLMActions:ExecuteCommand(ply, cmd, args)
    if not self:IsValid(ply) then return end
    if not cmd or cmd == "" then return end

    cmd = string.lower(cmd)

    if cmd == "spawn" then
        if args and args ~= "" then
            local success, result = self:SpawnEntity(ply, args, "")
            if success and self:IsValid(result) then
                self:SendAIMessage(ply, "Создан: " .. (result:GetClass() or "объект"))

                local effect = EffectData()
                effect:SetOrigin(self:SafeGetPos(result) + Vector(0, 0, 30))
                effect:SetScale(1)
                util.Effect("cball_explode", effect)
            else
                self:SendAIMessage(ply, "Ошибка: " .. tostring(result))
            end
        else
            self:SendAIMessage(ply, "Использование: !companion spawn <тип> [модель]")
        end
        return
    end

    if cmd == "help" then
        local helpMsg = [[=== ДОСТУПНЫЕ КОМАНДЫ ===
!companion follow   - Следовать за игроком
!companion point    - Держать текущую позицию
!companion stop     - Полная остановка
!companion sit      - Сесть в транспорт
!companion standup  - Выйти и следовать
!companion attack [имя] - Атаковать врага
!companion spawn <тип> [модель] - Создать объект
!companion status   - Статус компаньона
!companion help     - Эта справка]]
        self:SendAIMessage(ply, helpMsg)
        return
    end

    
    
    
    local bot = nil
    if self.commands then
        bot = self.commands:FindOwnedBot(ply)
    end
    if not self:IsValid(bot) and self.botmanager then
        bot = self.botmanager:GetBotByOwner(ply)
    end

    if not self:IsValid(bot) then
        self:SendAIMessage(ply, "У вас нет компаньона! Создайте его через меню или консольную команду ai_companion_create")
        return
    end

    local states = {}
    if self.state then
        states = self.state:GetStates() or {}
    end

    
    if cmd == "follow" then
        if self.state then
            self.state:setState("Disabled", false)
        end
        if self:IsValid(bot) then
            if bot:InVehicle() then pcall(function() bot:ExitVehicle() end) end
            if self.botmanager then
                self.botmanager:SetBotState(bot, states.FOLLOW or "following")
                bot:ChatPrint("[AI] Следую за " .. ply:Nick())
            end
        end
        self:SendAIMessage(ply, "Следую за вами.")

    
    elseif cmd == "stop" then
        if self.state then
            self.state:setState("Disabled", true)
        end
        if self:IsValid(bot) then
            if self.botmanager then
                local data = self.botmanager:GetData(bot)
                if data and data.combat then
                    data.combat.target = nil
                    self.botmanager:UpdateData(bot, data)
                end
                self.botmanager:SetBotState(bot, states.IDLE or "idle")
            end
            pcall(function() bot:SetLocalVelocity(Vector(0, 0, 0)) end)
            bot:ChatPrint("[AI] Остановлен.")
        end
        self:SendAIMessage(ply, "Остановлен.")

    
    elseif cmd == "point" then
        if self.state then
            self.state:setState("Disabled", false)
        end
        if self:IsValid(bot) then
            if bot:InVehicle() then pcall(function() bot:ExitVehicle() end) end
            local data = self.botmanager:GetData(bot) or {}
            data.point = data.point or {}
            data.point.pos = bot:GetPos()
            data.point.angle = bot:EyeAngles()
            if self.botmanager then
                self.botmanager:UpdateData(bot, data)
                self.botmanager:SetBotState(bot, states.POINTING or "pointing")
            end
            bot:ChatPrint("[AI] Держу точку.")
        end
        self:SendAIMessage(ply, "Держу точку.")

    
    elseif cmd == "sit" then
        if self.state then
            self.state:setState("Disabled", false)
        end
        if self:IsValid(bot) then
            if bot:InVehicle() then pcall(function() bot:ExitVehicle() end) end
            local seat = self:FindAnyFreeSeat(bot, 500)
            if self:IsValid(seat) then
                local success = pcall(function() bot:EnterVehicle(seat) end)
                if success and bot:InVehicle() then
                    if self.botmanager then
                        self.botmanager:SetBotState(bot, states.SITTING or "sitting")
                    end
                    bot:ChatPrint("[AI] Сижу.")
                    self:SendAIMessage(ply, "Сижу.")
                else
                    self:SendAIMessage(ply, "Не удалось сесть.")
                end
            else
                self:SendAIMessage(ply, "Поблизости нет свободных мест.")
                if self:IsValid(bot) then
                    bot:ChatPrint("[AI] Поблизости нет свободных мест.")
                end
            end
        end

    
    elseif cmd == "standup" then
        if self.state then
            self.state:setState("Disabled", false)
        end
        if self:IsValid(bot) then
            if bot:InVehicle() then pcall(function() bot:ExitVehicle() end) end
            if self.botmanager then
                self.botmanager:SetBotState(bot, states.FOLLOW or "following")
            end
            bot:ChatPrint("[AI] Вышел и следую за " .. ply:Nick())
        end
        self:SendAIMessage(ply, "Вышел и следую за вами.")

    
    elseif cmd == "attack" then
        if not self:IsValid(bot) then return end
        if args and args ~= "" then
            local targetName = args
            local lowerName = string.lower(targetName)
            
            
            if targetName == "1" or lowerName == "me" or lowerName == "меня" or 
               lowerName == "owner" or lowerName == "хозяин" or lowerName == "владелец" then
                targetName = ply:Nick() 
            end
            
            
            local target = self:FindPlayerByName(targetName)
            
            if self:IsValid(target) then
                
                self:SetBotCombatTarget(bot, target, "player", "command_llm")
                self:SendAIMessage(ply, "Атакую " .. target:Nick())
                if self:IsValid(bot) then
                    bot:ChatPrint("[AI] Атакую " .. target:Nick())
                end
            else
                self:SendAIMessage(ply, "Игрок не найден: " .. targetName)
            end
        else
            
            local nearestEnemy, nearestDist = self:FindNearestEnemy(bot, 2000)
            if self:IsValid(nearestEnemy) then
                local targetType = nearestEnemy:IsPlayer() and "player" or "npc"
                self:SetBotCombatTarget(bot, nearestEnemy, targetType, "command")
                local name = nearestEnemy:IsPlayer() and nearestEnemy:Nick() or self:SafeGetClass(nearestEnemy)
                self:SendAIMessage(ply, "Атакую " .. name)
                if self:IsValid(bot) then
                    bot:ChatPrint("[AI] Атакую " .. name)
                end
            else
                self:SendAIMessage(ply, "Врагов поблизости нет.")
                if self:IsValid(bot) then
                    bot:ChatPrint("[AI] Врагов поблизости нет.")
                end
            end
        end

    
    elseif cmd == "status" then
        if not self:IsValid(bot) then
            self:SendAIMessage(ply, "У вас нет компаньона! Создайте его через меню или консольную команду ai_companion_create")
            return
        end
        local hp = math.Round(bot:Health()) .. "/" .. math.Round(bot:GetMaxHealth())
        local armor = math.Round(bot:Armor())
        local state = self.botmanager:GetBotState(bot) or "idle"
        local task = bot:GetNWString("CurrentTask", "")
        local inVeh = bot:InVehicle() and "в транспорте" or "пешком"
        local msg = string.format(
            "=== Статус ===\nИмя: %s\nЗдоровье: %s\nБроня: %s\nСостояние: %s (%s)\nДвижение: %s",
            bot:Nick(), hp, armor, state, task, inVeh
        )
        self:SendAIMessage(ply, msg)

    
    else
        self:SendAIMessage(ply, "Неизвестная команда: !companion " .. cmd)
        self:SendAIMessage(ply, "Используйте !companion help для справки")
    end
end





function LLMActions:FindAnyFreeSeat(bot, radius)
    if not self:IsValid(bot) then return nil end

    radius = radius or 500
    local botPos = self:SafeGetPos(bot)
    local best = nil
    local bestDist = radius * radius

    for _, ent in ipairs(ents.FindInSphere(botPos, radius)) do
        if self:IsValid(ent) then
            local class = self:SafeGetClass(ent)
            if class == "prop_vehicle_jeep" or
               class == "prop_vehicle_airboat" or
               class == "prop_vehicle_driveable" or
               class == "prop_vehicle_prisoner_pod" then
                local driver = nil
                pcall(function() driver = ent:GetDriver() end)
                if not self:IsValid(driver) then
                    local dist = botPos:Distance(self:SafeGetPos(ent))
                    if dist < bestDist then
                        bestDist = dist
                        best = ent
                    end
                end
            end
        end
    end

    return best
end

function LLMActions:FindNearestEnemy(bot, radius)
    if not self:IsValid(bot) then return nil, math.huge end

    local botPos = self:SafeGetPos(bot)
    local nearestEnemy = nil
    local nearestDist = radius or 2000

    for _, ent in ipairs(self.utils.FindInSphere(botPos, nearestDist)) do
        if self:IsValid(ent) and ent:Alive() and ent ~= bot then
            if self:IsHostileEntity(ent) then
                local dist = botPos:Distance(self:SafeGetPos(ent))
                if dist < nearestDist then
                    nearestDist = dist
                    nearestEnemy = ent
                end
            end
        end
    end

    return nearestEnemy, nearestDist
end

function LLMActions:SetBotCombatTarget(bot, target, targetType, triggeredBy)
    if not self:IsValid(bot) or not self:IsValid(target) then return end
    if not self.botmanager then return end

    local data = self.botmanager:GetData(bot) or {}
    if not data.combat then data.combat = {} end

    data.combat.target = target
    data.combat.target_type = targetType or "npc"
    data.combat.triggered_by = triggeredBy or "command"
    data.combat.last_attack_time = CurTime()

    self.botmanager:UpdateData(bot, data)

    
    local states = {}
    if self.state then
        states = self.state:GetStates() or {}
    end
    self.botmanager:SetBotState(bot, states.COMBAT or "combat")

    
    local combatWep = data.config and data.config.combat_weapon or "weapon_smg1"
    if not bot:HasWeapon(combatWep) then
        pcall(function() bot:Give(combatWep) end)
    end
    bot:SelectWeapon(combatWep)
end

function LLMActions:IsHostileEntity(ent)
    if not self:IsValid(ent) then return false end

    local okAlive, alive = pcall(function() return ent:Alive() end)
    if okAlive and not alive then return false end

    local okClass, class = pcall(function() return ent:GetClass() end)
    if not okClass then return false end

    
    if self.state and self.state:IsFriendlyNPC(class) then
        return false
    end

    
    if self.utils and self.utils.IsBotSafe(ent) then
        if ent:GetNWBool("IsAICompanion", false) then
            return false
        end
        return true
    end

    
    if self.utils and self.utils.IsPlayerSafe(ent) then
        return true
    end

    
    if ent.IsNPC and ent:IsNPC() then
        if not self:IsFriendlyNPC(ent) then
            return true
        end
    end

    if ent.IsNextBot and ent:IsNextBot() then
        if not self:IsFriendlyNPC(ent) then
            return true
        end
    end

    
    if string.find(string.lower(class), "npc") and not string.find(class, "friendly") then
        return true
    end

    return false
end





function LLMActions:SetupChatHook()
    if not SERVER then return end

    hook.Add("PlayerSay", "AICompanion_LLMActions", function(ply, text)
        if not self:IsValid(ply) then return end
        if ply:IsBot() then return end

        
        if string.StartWith(string.lower(text), "!companion") then
            local afterCommand = string.sub(text, string.len("!companion") + 1)
            local cmd = string.Trim(afterCommand)

            if cmd == "" then
                self:SendAIMessage(ply, "Используйте !companion help для справки")
                return ""
            end

            local args = {}
            for word in string.gmatch(cmd, "[^%s]+") do
                table.insert(args, word)
            end
            local command = args[1]
            local arg = args[2] or ""

            
            self:ExecuteCommand(ply, command, arg)
            return ""
        end

        
        return nil
    end)
end





function LLMActions:SetupCommands()
    if not SERVER then return end

    concommand.Add("ai_llm_actions_test", function(ply, cmd, args)
        if not self:IsValid(ply) then return end
        if not ply:IsAdmin() then
            ply:ChatPrint("[AI] Только администраторы!")
            return
        end

        local action = args[1] or ""
        local arg = args[2] or ""

        if action == "spawn" and arg ~= "" then
            local success, result = self:SpawnEntity(ply, arg, "")
            if success and self:IsValid(result) then
                ply:ChatPrint("[AI] Создан: " .. (result:GetClass() or "объект"))
            else
                ply:ChatPrint("[AI] Ошибка: " .. tostring(result))
            end
        elseif action == "attack" then
            local target = self:FindPlayerByName(arg)
            if self:IsValid(target) then
                ply:ChatPrint("[AI] Найден игрок: " .. target:Nick())
            else
                ply:ChatPrint("[AI] Игрок не найден: " .. arg)
            end
        else
            ply:ChatPrint("[AI] Использование: ai_llm_actions_test <spawn|attack> [аргумент]")
        end
    end)
end





function LLMActions:GetAPI()
    return {
        ProcessResponse = function(ply, response) return self:ProcessResponse(ply, response) end,
        SpawnEntity = function(ply, keyword, customModel) return self:SpawnEntity(ply, keyword, customModel) end,
        ExecuteCommand = function(ply, cmd, args) return self:ExecuteCommand(ply, cmd, args) end,
        FindPlayerByName = function(name) return self:FindPlayerByName(name) end,
        SendAIMessage = function(ply, msg) return self:SendAIMessage(ply, msg) end,
        FindNearestEnemy = function(bot, radius) return self:FindNearestEnemy(bot, radius) end,
        IsHostileEntity = function(ent) return self:IsHostileEntity(ent) end,
        SetBotCombatTarget = function(bot, target, targetType, triggeredBy)
            return self:SetBotCombatTarget(bot, target, targetType, triggeredBy)
        end,
        GetSpawnTable = function() return self:GetSpawnTable() end,
    }
end














return LLMActions
