-- Execution layer for LLM-driven companion actions.

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
function LLMActions:GetLocalized(key, ...)
	local locator = AICompanion.GetLocator()
	if locator and locator:has("locale") then
		local locale = locator:get("locale")
		if locale and locale.Get then
			return locale:Get(key, ...)
		end
	end
	return key
end
function LLMActions:init()
	if self._initialized then return end
	self._spawnTable = self:GetSpawnTable()
	self._synonyms = self:BuildSynonyms()
	if self.llm then
	end
	if SERVER then
	end
	self._initialized = true
	if self.utils then
		self.utils.LogInfo("LLMActions", self:GetLocalized("log_llm_actions_init"))
	end
end
function LLMActions:IsValid(ent)
	return self.utils and self.utils:IsValid(ent)
end
function LLMActions:SafeGetClass(ent)
	if not self:IsValid(ent) then return "invalid" end
	local ok, class = ent:GetClass()
	return (ok and class) or "error"
end
function LLMActions:SafeGetPos(ent)
	if not self:IsValid(ent) then return Vector() end
	local ok, pos = ent:GetPos()
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

	local steamID = ply:SteamID64()
	local settings = self.state and self.state:getPlayerSettings(steamID) or {}
	local prefixColor = self.utils:GetPrefixColor(ply, settings)
	local cleanPrefix = self.utils:GetCleanPrefix(ply, settings)

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
		car = { class = "prop_vehicle_jeep", type = "vehicle" },
		apc = { class = "prop_vehicle_apc", type = "vehicle" },
		btr = { class = "prop_vehicle_apc", type = "vehicle" },
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
		car = "jeep",
		vehicle = "jeep",
		airboat = "airboat",
		boat = "airboat",
		apc = "apc",
		btr = "apc",
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
function LLMActions:SpawnEntity(ply, keyword)
	if not self:IsValid(ply) then
		return false, self:GetLocalized("error")
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
			return false, self:GetLocalized("log_llm_actions_spawn_unknown"):format(keyword)
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
		ent = self:CreateProp(entry, spawnPos, ply)
	elseif entry.type == "npc" then
		ent = self:CreateNPC(entry, spawnPos, keyword)
	elseif entry.type == "item" or entry.type == "weapon" then
		ent = self:CreateItem(entry, spawnPos, ply)
	elseif entry.type == "vehicle" then
		ent = self:CreateVehicle(entry, spawnPos, ply)
	else
		return false, self:GetLocalized("log_llm_actions_spawn_type_unknown")
	end
	if not self:IsValid(ent) then
		return false, self:GetLocalized("log_llm_actions_spawn_fail")
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
function LLMActions:CreateProp(entry, spawnPos, ply)
	local model = entry.model
	if not model or model == "" then return nil end

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

	local ang = Angle(0, 0, 0)
	if self:IsValid(ply) then
		ang = ply:EyeAngles()
		ang.p = 0
		ang.r = 0
	end
	ent:SetAngles(ang)

	ent:Spawn()
	ent:Activate()

	local phys = ent:GetPhysicsObject()
	if self:IsValid(phys) then
		phys:Wake()
	else
		SafeRemoveEntity(ent)
		return nil
	end

	local tr = util.TraceLine({
		start = ent:GetPos(),
		endpos = ent:GetPos() - Vector(0, 0, 10000),
		filter = { ply, ent },
		mask = MASK_SOLID_BRUSHONLY
	})

	if tr.Hit then
		ent:SetPos(tr.HitPos + Vector(0, 0, 2))
		if self:IsValid(ent:GetPhysicsObject()) then
			ent:GetPhysicsObject():Wake()
		end
	end

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
function LLMActions:CreateVehicle(entry, spawnPos, ply)
	local class = entry.class
	if not class or class == "" then return nil end

	if class == "prop_vehicle_driveable" then
		class = "prop_vehicle_jeep"
	end

	local ent = ents.Create(class)
	if not self:IsValid(ent) then return nil end

	if class == "prop_vehicle_jeep" then
		ent:SetModel("models/buggy.mdl")
		ent:SetKeyValue("vehiclescript", "scripts/vehicles/jeep_test.txt")
	elseif class == "prop_vehicle_airboat" then
		ent:SetModel("models/airboat.mdl")
		ent:SetKeyValue("vehiclescript", "scripts/vehicles/airboat.txt")
	elseif class == "prop_vehicle_prisoner_pod" then
		ent:SetModel("models/vehicles/prisoner_pod_inner.mdl")
		ent:SetKeyValue("vehiclescript", "scripts/vehicles/prisoner_pod.txt")
	elseif class == "prop_vehicle_apc" then
		ent:SetModel("models/combine_apc.mdl")
		ent:SetKeyValue("vehiclescript", "scripts/vehicles/apc.txt")
	else
		if not entry.vehiclescript then
			return nil
		end
		if entry.model then
			ent:SetModel(entry.model)
		end
		ent:SetKeyValue("vehiclescript", entry.vehiclescript)
	end

	ent:SetPos(spawnPos)

	local ang = Angle(0, 0, 0)
	if self:IsValid(ply) then
		ang = ply:EyeAngles()
		ang.p = 0
		ang.r = 0
	end
	ent:SetAngles(ang)

	ent:Spawn()
	ent:Activate()

	local tr = util.TraceLine({
		start = ent:GetPos() + Vector(0, 0, 50),
		endpos = ent:GetPos() - Vector(0, 0, 10000),
		filter = { ply, ent },
		mask = MASK_SOLID_BRUSHONLY
	})

	if tr.Hit then
		ent:SetPos(tr.HitPos + Vector(0, 0, 5))
	end

	return ent
end
local ALLOWED_LLM_COMMANDS = {
	follow = true,
	stop = true,
	point = true,
	sit = true,
	standup = true,
	attack = true,
	spawn = true,
}

function LLMActions:ProcessResponse(ply, response)
	if not self:IsValid(ply) then return response end
	if not response or response == "" then return response end

	local hasCommand = string.find(response, "!companion", 1, true)
	if not hasCommand then
		return response
	end

	local processedResponse = response
	local commandsExecuted = false

	processedResponse = string.gsub(processedResponse, "!companion%s*$", "")
	processedResponse = string.gsub(processedResponse, "!companion%s*\r?\n", "\n")

	local pattern = "!companion%s+([%a_]+)%s*(.-)%s*$"
	local executedCount = 0

	for i = 1, 5 do
		local cmdStart, cmdEnd, cmd, arg = string.find(processedResponse, pattern)
		if not cmdStart then break end

		local beforeCmd = string.sub(processedResponse, 1, cmdStart - 1)
		beforeCmd = string.Trim(beforeCmd)

		local lowerCmd = string.lower(cmd)
		if ALLOWED_LLM_COMMANDS[lowerCmd] and executedCount < 1 then
			self:ExecuteCommand(ply, lowerCmd, arg or "")
			commandsExecuted = true
			executedCount = executedCount + 1
		end

		local afterCmd = string.sub(processedResponse, cmdEnd + 1)
		processedResponse = string.Trim(beforeCmd .. " " .. afterCmd)
	end

	processedResponse = string.gsub(processedResponse, "^!companion%s*", "")
	processedResponse = string.gsub(processedResponse, "%s*!companion%s*$", "")
	processedResponse = string.gsub(processedResponse, "%s+", " ")
	processedResponse = string.Trim(processedResponse)

	if commandsExecuted and processedResponse == "" then
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
			local success, result = self:SpawnEntity(ply, args)
			if success and self:IsValid(result) then
				local effect = EffectData()
				effect:SetOrigin(self:SafeGetPos(result) + Vector(0, 0, 30))
				effect:SetScale(1)
				util.Effect("cball_explode", effect)
			else
			end
		else
		end
		return
	end
	if cmd == "help" then
		local helpMsg = self:GetLocalized("cmd_help_title") .. "\n" ..
			self:GetLocalized("cmd_help_follow") .. "\n" ..
			self:GetLocalized("cmd_help_point") .. "\n" ..
			self:GetLocalized("cmd_help_stop") .. "\n" ..
			self:GetLocalized("cmd_help_sit") .. "\n" ..
			self:GetLocalized("cmd_help_standup") .. "\n" ..
			self:GetLocalized("cmd_help_attack") .. "\n" ..
			self:GetLocalized("log_llm_actions_spawn_usage") .. "\n" ..
			self:GetLocalized("cmd_help_status") .. "\n" ..
			self:GetLocalized("cmd_help_help")
		return
	end
	local bot = nil
	if self.commands then
		bot = self.commands:FindOwnedBot(ply)
	end
	if not self:IsValid(bot) and self.botmanager then
		bot = self.botmanager:GetBotByOwner(ply)
	end

	local soloNPC = nil
	if not self:IsValid(bot) then
		for _, ent in ipairs(ents.FindByClass("solo_companion_npc")) do
			if self:IsValid(ent) then
				soloNPC = ent
				break
			end
		end
	end

	if not self:IsValid(bot) and not self:IsValid(soloNPC) then
		return
	end

	if self:IsValid(soloNPC) and not self:IsValid(bot) then
		self:ExecuteSoloNPCCommand(ply, soloNPC, cmd, args)
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
			if bot:InVehicle() then bot:ExitVehicle() end
			if self.botmanager then
				self.botmanager:SetBotState(bot, states.FOLLOW or "following")
				bot:ChatPrint("[AI] " .. self:GetLocalized("bot_following"):format(ply:Nick()))
			end
		end
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
			bot:SetLocalVelocity(Vector(0, 0, 0))
			bot:ChatPrint("[AI] " .. self:GetLocalized("log_llm_actions_stop"))
		end
	elseif cmd == "point" then
		if self.state then
			self.state:setState("Disabled", false)
		end
		if self:IsValid(bot) then
			if bot:InVehicle() then bot:ExitVehicle() end
			local data = self.botmanager:GetData(bot) or {}
			data.point = data.point or {}
			data.point.pos = bot:GetPos()
			data.point.angle = bot:EyeAngles()
			if self.botmanager then
				self.botmanager:UpdateData(bot, data)
				self.botmanager:SetBotState(bot, states.POINTING or "pointing")
			end
			bot:ChatPrint("[AI] " .. self:GetLocalized("log_llm_actions_point"))
		end
	elseif cmd == "sit" then
		if self.state then
			self.state:setState("Disabled", false)
		end
		if self:IsValid(bot) then
			if bot:InVehicle() then bot:ExitVehicle() end
			local seat = self:FindAnyFreeSeat(bot, 500)
			if self:IsValid(seat) then
				local success = bot:EnterVehicle(seat)
				if success and bot:InVehicle() then
					if self.botmanager then
						self.botmanager:SetBotState(bot, states.SITTING or "sitting")
					end
					bot:ChatPrint("[AI] " .. self:GetLocalized("log_llm_actions_sit"))
				else
				end
			else
				if self:IsValid(bot) then
					bot:ChatPrint("[AI] " .. self:GetLocalized("log_llm_actions_sit_no_seat"))
				end
			end
		end
	elseif cmd == "standup" then
		if self.state then
			self.state:setState("Disabled", false)
		end
		if self:IsValid(bot) then
			if bot:InVehicle() then bot:ExitVehicle() end
			if self.botmanager then
				self.botmanager:SetBotState(bot, states.FOLLOW or "following")
			end
			bot:ChatPrint("[AI] " .. self:GetLocalized("log_llm_actions_standup"):format(ply:Nick()))
		end
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
				if self:IsValid(bot) then
					bot:ChatPrint("[AI] " .. self:GetLocalized("log_llm_actions_attack"):format(target:Nick()))
				end
			else
			end
		else
			local nearestEnemy, nearestDist = self:FindNearestEnemy(bot, 2000)
			if self:IsValid(nearestEnemy) then
				local targetType = nearestEnemy:IsPlayer() and "player" or "npc"
				self:SetBotCombatTarget(bot, nearestEnemy, targetType, "command")
				local name = nearestEnemy:IsPlayer() and nearestEnemy:Nick() or self:SafeGetClass(nearestEnemy)
				if self:IsValid(bot) then
					bot:ChatPrint("[AI] " .. self:GetLocalized("log_llm_actions_attack"):format(name))
				end
			else
				if self:IsValid(bot) then
					bot:ChatPrint("[AI] " .. self:GetLocalized("log_llm_actions_no_enemies"))
				end
			end
		end
	elseif cmd == "status" then
		if not self:IsValid(bot) then
			return
		end
		local hp = math.Round(bot:Health()) .. "/" .. math.Round(bot:GetMaxHealth())
		local armor = math.Round(bot:Armor())
		local state = self.botmanager:GetBotState(bot) or "idle"
		local task = bot:GetNWString("CurrentTask", "")
		local inVeh = bot:InVehicle() and self:GetLocalized("status_in_vehicle") or self:GetLocalized("status_on_foot")
		local msg = self:GetLocalized("log_llm_actions_status_fmt"):format(bot:Nick(), hp, armor, state, task, inVeh)
	else
	end
end
function LLMActions:ExecuteSoloNPCCommand(ply, npc, cmd, args)
	if not self:IsValid(ply) or not self:IsValid(npc) then return end

	if cmd == "follow" then
		npc._aiDisabled = false
		npc:ClearTargetQueue()
		npc._myTarget = nil
		npc._attackMode = false
		npc._lastKnownPos = nil
		if npc:VehicleIsValid() then
			npc:VehicleExit()
		end

	elseif cmd == "stop" then
		npc._aiDisabled = true
		npc:ClearTargetQueue()
		npc._myTarget = nil
		npc._attackMode = false
		npc._lastKnownPos = nil
		npc.loco:SetDesiredSpeed(0)
		ply._lastAttacker = nil
		ply._lastPlayerTarget = nil

	elseif cmd == "attack" then
		if npc:IsPacifistMode() then
			return
		end

		if args and args ~= "" then
			local targetName = args
			local target = self:FindPlayerByName(targetName)
			if self:IsValid(target) then
				npc:RequestTarget(target, "command_llm", true)
			else
				local found = false
				for _, ent in ipairs(ents.FindInSphere(npc:GetPos(), 3000)) do
					if self:IsValid(ent) and ent ~= npc then
						local class = ent:GetClass()
						if string.find(string.lower(class), string.lower(targetName), 1, true) then
							if (ent:IsNPC() or ent:IsNextBot()) and not npc:IsFriendlyEntity(ent) then
								npc:RequestTarget(ent, "command_llm", true)
								found = true
								break
							end
						end
					end
				end
				if not found then
				end
			end
		else
			local myPos = npc:GetPos()
			local bestEnemy = nil
			local bestDist = 2000

			for _, ent in ipairs(ents.FindInSphere(myPos, 2000)) do
				if self:IsValid(ent) and ent ~= npc then
					if (ent:IsNPC() or ent:IsNextBot()) and not npc:IsFriendlyEntity(ent) and npc:IsTargetAlive(ent) then
						local d = myPos:Distance(ent:GetPos())
						if d < bestDist then
							bestDist = d
							bestEnemy = ent
						end
					end
				end
			end

			if self:IsValid(bestEnemy) then
				npc:RequestTarget(bestEnemy, "command", true)
				local name = bestEnemy:IsPlayer() and bestEnemy:Nick() or bestEnemy:GetClass()
			else
			end
		end

	elseif cmd == "sit" then
		if npc:VehicleIsValid() then
			return
		end

		local veh = nil
		if npc.VehicleFindNearest then
			veh = npc:VehicleFindNearest(700)
		end

		if self:IsValid(veh) then
			if npc:VehicleEnter(veh) then
			else
			end
		else
		end

	elseif cmd == "standup" then
		if npc:VehicleIsValid() then
			npc:VehicleExit()
		end

	elseif cmd == "status" then
		local hp = math.Round(npc:Health()) .. "/" .. math.Round(npc:GetMaxHealth())
		local state = "idle"
		if npc:VehicleIsValid() then
			state = "in_vehicle"
		elseif npc._attackMode and self:IsValid(npc._myTarget) then
			state = "combat"
		elseif npc._isHealing then
			state = "healing"
		elseif npc._aiDisabled then
			state = "disabled"
		end

		local modes = {}
		if npc:IsStealthMode() then table.insert(modes, "stealth") end
		if npc:IsPacifistMode() then table.insert(modes, "pacifist") end
		if npc:IsAggressiveMode() then table.insert(modes, "aggressive") end
		if npc:IsDefenderMode() then table.insert(modes, "defender") end
		if npc:IsMedicMode() then table.insert(modes, "medic") end

		local wep = npc:GetActiveWeapon()
		local wepName = self:IsValid(wep) and wep:GetClass() or "none"

		local msg = "=== Companion Status ===\n" ..
			"Name: " .. npc:GetCustomNick() .. "\n" ..
			"HP: " .. hp .. "\n" ..
			"State: " .. state .. "\n" ..
			"Weapon: " .. wepName .. "\n" ..
			"Modes: " .. (#modes > 0 and table.concat(modes, ", ") or "none")

	elseif cmd == "teleport" then
		local pos = ply:GetPos() + ply:GetForward() * 60 + Vector(0, 0, 5)
		npc:SetPos(pos)
		npc._myTarget = nil
		npc._attackMode = false
		npc._lastKnownPos = nil
		if npc.loco then
			npc.loco:SetDesiredSpeed(0)
		end

	elseif cmd == "defender" then
		npc:SetDefenderMode(not npc:IsDefenderMode())
		local state = npc:IsDefenderMode() and "ON" or "OFF"

	elseif cmd == "pacifist" then
		npc:SetPacifistMode(not npc:IsPacifistMode())
		local state = npc:IsPacifistMode() and "ON" or "OFF"

	elseif cmd == "aggressive" then
		npc:SetAggressiveMode(not npc:IsAggressiveMode())
		local state = npc:IsAggressiveMode() and "ON" or "OFF"

	elseif cmd == "stealth" then
		npc:SetStealthMode(not npc:IsStealthMode())
		local state = npc:IsStealthMode() and "ON" or "OFF"

	elseif cmd == "heal" or cmd == "medic" then
		npc._healEnabled = not npc._healEnabled
		npc:SaveSettings()
		local state = npc._healEnabled and "ON" or "OFF"

	elseif cmd == "remove" then
		npc:Remove()

	elseif cmd == "replace" then
		local oldPos = npc:GetPos()
		local saveData = {
			model = npc._customModel,
			nick = npc._customNick,
			combatWeapon = npc._combatWeaponClass,
			idleWeapon = npc._idleWeaponClass,
			healEnabled = npc._healEnabled,
			healThreshold = npc._healThreshold,
			defenderMode = npc._defenderMode,
			stealthMode = npc._stealthMode,
			pacifistMode = npc._pacifistMode,
			aggressiveMode = npc._aggressiveMode,
		}

		npc:Remove()

		timer.Simple(0.2, function()
			local newNpc = ents.Create("solo_companion_npc")
			if self:IsValid(newNpc) then
				newNpc:SetPos(oldPos)
				newNpc:Spawn()
				newNpc:Activate()

				timer.Simple(0.3, function()
					if not self:IsValid(newNpc) then return end
					if saveData.model then newNpc:SetBotModel(saveData.model) end
					if saveData.nick then newNpc:SetCustomNick(saveData.nick) end
					if saveData.combatWeapon then newNpc._combatWeaponClass = saveData.combatWeapon end
					if saveData.idleWeapon then newNpc._idleWeaponClass = saveData.idleWeapon end
					newNpc._healEnabled = saveData.healEnabled
					newNpc._healThreshold = saveData.healThreshold
					newNpc._defenderMode = saveData.defenderMode
					newNpc._stealthMode = saveData.stealthMode
					newNpc._pacifistMode = saveData.pacifistMode
					newNpc._aggressiveMode = saveData.aggressiveMode
				end)
			end
		end)

	else
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
				driver = ent:GetDriver()
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
		if self:IsValid(ent) and ent ~= bot then
			local alive = true
			if ent.Alive then
				local ok, res = pcall(ent.Alive, ent)
				alive = ok and res or false
			end

			if alive and self:IsHostileEntity(ent) then
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
		bot:Give(combatWep)
	end
	bot:SelectWeapon(combatWep)
end
function LLMActions:IsHostileEntity(ent)
	if not self:IsValid(ent) then return false end
	local alive = true
	if ent.Alive then
		local okAlive, res = pcall(ent.Alive, ent)
		alive = okAlive and res or false
	end
	if not alive then return false end
	local okClass, class = ent:GetClass()
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
function LLMActions:IsFriendlyNPC(ent)
	if not self:IsValid(ent) then return false end
	local class = self:SafeGetClass(ent)
	if self.state then
		return self.state:IsFriendlyNPC(class)
	end
	return false
end
function LLMActions:SetupChatHook()
end
function LLMActions:GetAPI()
	return {
		ProcessResponse = function(ply, response) return self:ProcessResponse(ply, response) end,
		SpawnEntity = function(ply, keyword) return self:SpawnEntity(ply, keyword) end,
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
