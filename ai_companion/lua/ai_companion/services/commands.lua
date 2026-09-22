-- Console and chat command processing.

local Commands = {}
function Commands:new(utils, config, state, botmanager, spawn, llm, tts, shared, vehicle)
	local obj = {
		utils = utils,
		config = config,
		state = state,
		botmanager = botmanager,
		spawn = spawn,
		llm = llm,
		tts = tts,
		shared = shared,
		vehicle = vehicle,
		_initialized = false,
		_commandCooldowns = {},
		_globalCooldowns = {},
		_requestCounter = 0,
		_llmRateLimit = {},
		_ttsRateLimit = {},
	}
	setmetatable(obj, self)
	self.__index = self
	return obj
end
function Commands:GetLocalized(key, ...)
	local locator = AICompanion.GetLocator()
	if locator and locator:has("locale") then
		local locale = locator:get("locale")
		if locale and locale.Get then
			return locale:Get(key, ...)
		end
	end
	return key
end
function Commands:init()
	if self._initialized then return end
	if self.utils then
	end
	if SERVER then
		if self.utils then
		end
		self:RegisterCompanionCommands()
		self:SetupCommands()
		self:SetupChatHook()
	end
	self._initialized = true
	if self.utils then
		self.utils.LogInfo("Commands", self:GetLocalized("log_commands_initialized"))
	end
end
function Commands:GetSetting(key, default)
	if self.state then
		local val = self.state:getSetting(key)
		if val ~= nil then return val end
	end
	return default
end
function Commands:GetState(key, default)
	if self.state then
		local val = self.state:getState(key)
		if val ~= nil then return val end
	end
	return default
end
function Commands:FindOwnedBot(ply)
	if not self.utils or not self.utils:IsValid(ply) then return nil, nil end
	if self.botmanager then
		local bot = self.botmanager:GetBotByOwner(ply)
		if self.utils and self.utils:IsValid(bot) then
			local data = self.botmanager:GetData(bot)
			if data and data.owner == ply then
				return bot, bot:EntIndex()
			end
		end
	end
	for _, bot in ipairs(player.GetAll()) do
		if self.utils and self.utils:IsValid(bot) and bot:IsBot() and bot:GetNWBool("IsAICompanion", false) then
			local owner = bot:GetNWEntity("AICompanionOwnerEnt")
			if self.utils and self.utils:IsValid(owner) and owner == ply then
				return bot, bot:EntIndex()
			end
		end
	end
	return nil, nil
end
function Commands:IsBotOwner(bot, ply)
	if not self.utils or not self.utils:IsValid(bot) or not self.utils:IsValid(ply) then return false end
	if self.botmanager then
		local data = self.botmanager:GetData(bot)
		if data and data.owner == ply then
			return true
		end
	end
	local owner = bot:GetNWEntity("AICompanionOwnerEnt")
	return self.utils:IsValid(owner) and owner == ply
end
function Commands:SendSystemMessage(ply, text)
	if not self.utils or not self.utils:IsValid(ply) then return end
	if self.shared then
		self.shared:SendChatMessage(ply, text, Color(255, 0, 0), "AI", ply:Nick(), false)
	end
end
function Commands:CheckCooldown(ply, cmd)
	if not self.utils or not self.utils:IsValid(ply) then return false end
	local key = ply:EntIndex() .. "_" .. cmd
	local last = self._commandCooldowns[key] or 0
	local cooldown = 5
	if self.config and self.config:get("RateLimits") then
		cooldown = self.config:get("RateLimits").CommandCooldown or 5
	end
	if CurTime() - last < cooldown then return false end
	self._commandCooldowns[key] = CurTime()
	return true
end
function Commands:CheckGlobalCooldown(key, duration)
	local last = self._globalCooldowns[key] or 0
	if CurTime() - last < duration then
		return false, math.ceil(duration - (CurTime() - last))
	end
	self._globalCooldowns[key] = CurTime()
	return true, 0
end

function Commands:CheckLLMRateLimit(ply)
	if not self.utils or not self.utils:IsValid(ply) then return false, "Invalid player" end
	local steamID = ply:SteamID64()
	local now = CurTime()
	local limit = self._llmRateLimit[steamID] or { count = 0, resetTime = now + 60 }

	if now > limit.resetTime then
		limit.count = 0
		limit.resetTime = now + 60
	end

	if limit.count >= 10 then
		local wait = math.ceil(limit.resetTime - now)
		return false, "Превышен лимит LLM-запросов. Подождите " .. wait .. " сек."
	end

	limit.count = limit.count + 1
	self._llmRateLimit[steamID] = limit
	return true
end

function Commands:CheckTTSRateLimit(ply)
	if not self.utils or not self.utils:IsValid(ply) then return false, "Invalid player" end
	local steamID = ply:SteamID64()
	local now = CurTime()
	local limit = self._ttsRateLimit[steamID] or { count = 0, resetTime = now + 60 }

	if now > limit.resetTime then
		limit.count = 0
		limit.resetTime = now + 60
	end

	if limit.count >= 5 then
		local wait = math.ceil(limit.resetTime - now)
		return false, "Превышен лимит TTS-запросов. Подождите " .. wait .. " сек."
	end

	limit.count = limit.count + 1
	self._ttsRateLimit[steamID] = limit
	return true
end
local STATE_KEY_MAP = {
	companion_nick = "Companion_Nick",
	model_path = "Model_Path",
	combat_weapon = "Combat_Weapon",
	melee_weapon = "Melee_Weapon",
	idle_weapon = "Idle_Weapon",
	stealth_mode = "Stealth_Mode",
	defender_mode = "Defender_Mode",
	medic_mode = "Medic_Mode",
	pacifist_mode = "Pacifist_Mode",
	aggressive_mode = "Aggressive_Mode",
	show_sender_name = "Show_Sender_Name",
}
local MODE_STATE_MAP = {
	Stealth_Mode = "StealthMode",
	Defender_Mode = "DefenderMode",
	Medic_Mode = "MedicMode",
	Pacifist_Mode = "PacifistMode",
	Aggressive_Mode = "AggressiveMode",
}
function Commands:SetBotSetting(ply, key, value)
	if not self.utils or not self.utils:IsValid(ply) or ply:IsBot() then return false end
	local bot, botID = self:FindOwnedBot(ply)
	if not self.utils or not self.utils:IsValid(bot) then
		return false
	end
	if not self:IsBotOwner(bot, ply) then
		return false
	end
	local data = nil
	if self.botmanager then
		data = self.botmanager:GetData(bot)
	end
	if not data then
		local settings = self:GetPlayerSettings(ply) or {}
		if self.spawn and self.spawn.data then
			data = self.spawn.data:InitBotData(bot, ply, settings)
		end
		if not data then
			if self.utils then
				self.utils.LogError("Commands", self:GetLocalized("log_commands_botdata_fail"))
			end
			return false
		end
		if self.botmanager then
			self.botmanager:UpdateData(bot, data)
		end
	end
	if not data.config then
		data.config = {
			combat_weapon = "weapon_smg1",
			melee_weapon = "weapon_crowbar",
			idle_weapon = "weapon_physgun",
			stealth_mode = false,
			defender_mode = false,
			medic_mode = false,
			pacifist_mode = false,
			aggressive_mode = false,
			model_path = "models/player/urban.mdl",
			companion_nick = "AI_Companion",
			show_sender_name = true,
		}
	end
	local cfg = data.config
	local boolVal = tobool(value)
	local applied = false
	local booleanKeys = {
		stealth_mode = true,
		defender_mode = true,
		medic_mode = true,
		pacifist_mode = true,
		aggressive_mode = true,
		show_sender_name = true,
	}
	if booleanKeys[key] then
		cfg[key] = boolVal
		data._nw_cache[key] = boolVal
		applied = true
	elseif key == "combat_weapon" or key == "melee_weapon" or key == "idle_weapon" then
		cfg[key] = tostring(value)
		applied = true
		local wepClass = tostring(value)

		pcall(function()
			if not bot:HasWeapon(wepClass) then
				bot:Give(wepClass)
			end
		end)

		local botState = self.botmanager:GetBotState(bot) or "idle"
		local isCombatState = (botState == "combat" or botState == "attack" or botState == "protecting")

		local shouldSwitch = false
		local weaponToSelect = nil

		if key == "combat_weapon" then
			if isCombatState then
				shouldSwitch = true
				weaponToSelect = wepClass
			end
		elseif key == "idle_weapon" then
			if not isCombatState then
				shouldSwitch = true
				weaponToSelect = wepClass
			end
		elseif key == "melee_weapon" then
			shouldSwitch = true
			weaponToSelect = wepClass
		end

		if shouldSwitch and weaponToSelect then
			bot:SelectWeapon(weaponToSelect)
		end
	elseif key == "model_path" then
		if self.utils and self.utils:IsValidModel(value) then
			cfg.model_path = value
			bot:SetModel(value)
			applied = true
		end
	elseif key == "companion_nick" then
		cfg.companion_nick = value
		-- Ник бота обновится при следующем пересоздании
		-- Здесь только сохраняем в конфиг
		applied = true
	else
		applied = true
	end
	if not applied then
		return false
	end
	local stateKey = STATE_KEY_MAP[key]
	if stateKey and self.state then
		local steamID = ply:SteamID64()
		local valToSave = booleanKeys[key] and boolVal or value
		if self.state:IsGlobalKey(stateKey) then
			self.state:setSetting(stateKey, valToSave)
		else
			self.state:setPlayerSetting(steamID, stateKey, valToSave)
		end
		if booleanKeys[key] and MODE_STATE_MAP[stateKey] then
			self.state:setState(MODE_STATE_MAP[stateKey], boolVal)
		end
		if self.utils then
			self.utils.LogDebug("Commands", self:GetLocalized("log_commands_state_sync"), stateKey, tostring(valToSave))
		end
	end
	if self.botmanager then
		self.botmanager:UpdateData(bot, data)
		self.botmanager:SyncToNWVars(bot)
	end
	return true
end
function Commands:GetPlayerSettings(ply)
	if not self.utils or not self.utils:IsValid(ply) then return nil end
	local settings = {}
	if self.state then
		local rawSettings = self.state:getRaw("Settings") or {}
		for k, v in pairs(rawSettings) do
			settings[k] = v
		end
	end
	return settings
end
function Commands:GetPlayerSettingSafe(ply, key, default)
	if not self.utils or not self.utils:IsValid(ply) then return default end
	local val = self:GetSetting(key, nil)
	if val ~= nil then return val end
	return default
end
function Commands:RegisterCompanionCommand(name, desc, fn, aliases, needsBot)
	self._companionCommands[name] = {
		fn = fn,
		desc = desc,
		needsBot = needsBot ~= false,
	}
	if aliases then
		for _, a in ipairs(aliases) do
			self._companionAliases[a] = name
		end
	end
end
function Commands:RegisterCompanionCommands()
	self._companionCommands = {}
	self._companionAliases = {}
	local s = self
	self:RegisterCompanionCommand("follow", self:GetLocalized("desc_follow"), function(bot, ply, args, states)
		if s.state then s.state:setState("Disabled", false) end
		if bot:InVehicle() then bot:ExitVehicle() end

		if s.botmanager then
			local data = s.botmanager:GetData(bot)
			if data then
				if data.combat then
					data.combat.target = nil
					data.combat.target_type = nil
					data.combat.triggered_by = nil
					data.combat.target_queue = {}
				end

				if data.navigation then
					data.navigation.path = nil
					data.navigation.path_index = 1
				end

				if data.vehicle then
					data.vehicle.sit_by_command = false
					data.vehicle.locked_vehicle = nil
					data.vehicle.locked_seat = nil
				end

				s.botmanager:UpdateData(bot, data)
			end

			s.botmanager:SetBotState(bot, states.FOLLOW or "following")
			bot:ChatPrint("[AI] " .. self:GetLocalized("msg_following") .. ply:Nick())
		end

		ply:ChatPrint("[AI] " .. self:GetLocalized("msg_companion_following"))
	end, {"следуй", "за мной", "иди"}, true)
	self:RegisterCompanionCommand("stop", self:GetLocalized("desc_stop"), function(bot, ply, args, states)
		if s.state then s.state:setState("Disabled", false) end

		if bot:InVehicle() then
			bot:ExitVehicle()
		end

		if s.botmanager then
			local data = s.botmanager:GetData(bot)
			if data then
				if data.combat then
					data.combat.target = nil
					data.combat.target_type = nil
					data.combat.triggered_by = nil
					data.combat.target_queue = {}
					data.combat.last_attack_time = nil
					data.combat.last_damage_time = nil
				end

				if data.navigation then
					data.navigation.path = nil
					data.navigation.path_index = 1
					data.navigation.goal_pos = Vector(0, 0, 0)
				end

				if data.vehicle then
					data.vehicle.sit_by_command = false
					data.vehicle.locked_vehicle = nil
					data.vehicle.locked_seat = nil
				end

				data.state = states.STOPPED or "stopped"
				s.botmanager:UpdateData(bot, data)
				s.botmanager:SetBotState(bot, states.STOPPED or "stopped")
			end
		end

		bot:SetLocalVelocity(Vector(0, 0, 0))
		bot:ChatPrint("[AI] " .. self:GetLocalized("msg_stopped"))
		ply:ChatPrint("[AI] " .. self:GetLocalized("msg_companion_stopped"))
	end, {"стой", "стоп"}, true)
	self:RegisterCompanionCommand("point", self:GetLocalized("desc_point"), function(bot, ply, args, states)
		if s.state then s.state:setState("Disabled", false) end

		if bot:InVehicle() then bot:ExitVehicle() end

		if s.botmanager then
			local data = s.botmanager:GetData(bot)
			if data then
				data.combat = data.combat or {}
				data.combat.target = nil

				data.point = data.point or {}
				data.point.pos = bot:GetPos()
				data.point.angle = bot:EyeAngles()

				s.botmanager:UpdateData(bot, data)
			end

			s.botmanager:SetBotState(bot, states.POINTING or "pointing")
		end

		bot:SetLocalVelocity(Vector(0, 0, 0))
		bot:ChatPrint("[AI] " .. self:GetLocalized("msg_pointing"))
		ply:ChatPrint("[AI] " .. self:GetLocalized("msg_companion_pointing"))
	end, {"держи позицию", "стой тут", "point"}, true)

	self:RegisterCompanionCommand("sit", self:GetLocalized("desc_sit"), function(bot, ply, args, states)
		s:DoSitCommand(bot, ply, states)
	end, {"сядь", "сиди", "в машину", "садись"}, true)

	self:RegisterCompanionCommand("attack", self:GetLocalized("desc_attack"), function(bot, ply, args, states)
		if not s.botmanager then return end
		local data = s.botmanager:GetData(bot)
		if not data then return end

		local target = nil

		if args[2] then
			local targetName = table.concat(args, " ", 2)
			local lowerName = string.lower(targetName)

			if targetName == "1" or lowerName == "me" or lowerName == "меня" or
			   lowerName == "owner" or lowerName == "хозяин" or lowerName == "владелец" then
				targetName = ply:Nick()
			end

			target = self:FindPlayerByName(targetName)
			if not s.utils:IsValid(target) then
				return
			end
		else
			local radius = 2000
			local botPos = bot:GetPos()
			local bestEnemy = nil
			local bestDist = radius

			for _, ent in ipairs(ents.FindInSphere(botPos, radius)) do
				if s.utils:IsValid(ent) and ent ~= bot then
					if ent:IsPlayer() then
						continue
					end

					local isHostile = false
					if ent:IsNPC() or ent:IsNextBot() then
						isHostile = true
					end

					local locator = AICompanion.GetLocator()
					local combat = locator and locator:get("combat")
					if combat and combat.IsHostileByDefault then
						isHostile = combat:IsHostileByDefault(ent, bot)
						if ent:IsPlayer() then
							isHostile = false
						end
					end

					if isHostile then
						local dist = botPos:Distance(ent:GetPos())
						if dist < bestDist then
							bestDist = dist
							bestEnemy = ent
						end
					end
				end
			end

			target = bestEnemy
		end

		if not s.utils:IsValid(target) then
			if s.utils and s.utils:IsValid(ply) then
				if args[2] then end
			end
			return
		end

		local locator = AICompanion.GetLocator()
		local combat = locator and locator:get("combat")
		if combat and combat.RequestTarget then
			combat:RequestTarget(bot, target, args[2] and "command_llm" or "command", true)
		else
			if not data.combat then data.combat = {} end
			data.combat.target = target
			data.combat.target_type = target:IsPlayer() and "player" or "npc"
			data.combat.triggered_by = "command"
			data.combat.last_attack_time = CurTime()
			s.botmanager:SetBotState(bot, states.COMBAT or "combat")
			s.botmanager:UpdateData(bot, data)
		end

		if s.utils and s.utils:IsValid(ply) then
			local targetName = "Unknown"
			if target:IsPlayer() then
				targetName = target:Nick()
			elseif target.GetClass then
				targetName = target:GetClass()
			elseif target.GetName then
				targetName = target:GetName()
			end
		end
	end, {"атакуй", "в атаку", "attack"}, true)

	self:RegisterCompanionCommand("standup", self:GetLocalized("desc_standup"), function(bot, ply, args, states)
		if s.state then
			s.state:setState("Disabled", false)
		end
		if s.utils:IsValid(bot) then
			if bot:InVehicle() then bot:ExitVehicle() end
			if s.botmanager then
				local data = s.botmanager:GetData(bot)
				if data and data.combat then
					data.combat.target = nil
					s.botmanager:UpdateData(bot, data)
				end
				s.botmanager:SetBotState(bot, states.FOLLOW or "following")
			end
		end
	end, {"встань", "вставай", "stand", "standup"}, true)
	self:RegisterCompanionCommand("status", self:GetLocalized("desc_status"), function(bot, ply)
		local hp = math.Round(bot:Health()) .. "/" .. math.Round(bot:GetMaxHealth())
		local armor = math.Round(bot:Armor())
		local state = s.botmanager:GetBotState(bot) or "idle"
		local inVeh = bot:InVehicle() and self:GetLocalized("status_in_vehicle") or self:GetLocalized("status_on_foot")
		ply:ChatPrint("[AI] " .. self:GetLocalized("msg_status_header"))
		ply:ChatPrint("[AI] " .. self:GetLocalized("msg_status_name") .. bot:Nick())
		ply:ChatPrint("[AI] " .. self:GetLocalized("msg_status_health") .. hp)
		ply:ChatPrint("[AI] " .. self:GetLocalized("msg_status_armor") .. armor)
		ply:ChatPrint("[AI] " .. self:GetLocalized("msg_status_state") .. state)
		ply:ChatPrint("[AI] " .. self:GetLocalized("msg_status_movement") .. inVeh)
	end, {"статус", "инфа", "состояние"}, true)
	self:RegisterCompanionCommand("help", self:GetLocalized("desc_help"), function(bot, ply)
		ply:ChatPrint("[AI] " .. self:GetLocalized("msg_help_header"))
		for _, line in ipairs(s._companionHelp) do
			ply:ChatPrint("[AI] " .. line)
		end
		ply:ChatPrint("[AI] " .. self:GetLocalized("msg_help_ai"))
		ply:ChatPrint("[AI] " .. self:GetLocalized("msg_help_other"))
	end, {"помощь", "помоги", "h", "?"}, false)
	self._companionHelp = {}
	local names = {}
	for name in pairs(self._companionCommands) do
		table.insert(names, name)
	end
	table.sort(names)
	for _, name in ipairs(names) do
		table.insert(self._companionHelp,
			string.format("!companion %-8s - %s", name, self._companionCommands[name].desc))
	end
end
function Commands:SetupCommands()
	if not SERVER then return end

	local isSolo = game.SinglePlayer()

	concommand.Add("ai_companion_replace", function(ply, cmd, args)
		if isSolo then return end
		if game.SinglePlayer() then
			if self.utils and self.utils:IsValid(ply) then
				ply:ChatPrint("[AI] " .. self:GetLocalized("bot_solo_mode"))
			end
			return
		end
		if not self.utils or not self.utils:IsValid(ply) or not ply:IsPlayer() or ply:IsBot() then return end
		if not self.botmanager or not self.spawn then
			ply:ChatPrint("[AI] " .. self:GetLocalized("msg_services_unloaded"))
			return
		end
		if not self:CheckCooldown(ply, "replace") then
			ply:ChatPrint("[AI] " .. self:GetLocalized("msg_replace_cooldown"))
			return
		end
		local bot = self.botmanager:GetBotByOwner(ply)
		if not self.utils or not self.utils:IsValid(bot) then
			ply:ChatPrint("[AI] " .. self:GetLocalized("msg_no_companion"))
			return
		end
		local model = args[1]
		if not model or model == "" then
			model = self.state and self.state:getPlayerSetting(ply:SteamID64(), "Model_Path", nil) or nil
		end
		if not model or model == "" then
			model = self:GetSetting("Model_Path", "models/player/urban.mdl")
		end
		local oldNick = bot:Nick() or self:GetLocalized("companion_fallback_name")
		self.botmanager:RemoveBot(bot, self:GetLocalized("reason_replace"), true)
		local prefix = self:GetLocalized("msg_companion_prefix")
		local replacingMsg = self:GetLocalized("msg_replacing")
		ply:ChatPrint("[AI] " .. prefix .. oldNick .. replacingMsg)
		timer.Simple(0.6, function()
			if not self.utils or not self.utils:IsValid(ply) then return end
			local newBot = self.spawn:CreateAICompanion(model, nil, ply)
			if newBot and newBot:IsValid() and newBot:IsPlayer() then
				ply:ChatPrint("[AI] " .. self:GetLocalized("msg_companion_replaced"))
				if self.utils then
					self.utils.LogInfo("Commands", self:GetLocalized("log_companion_replaced"), ply:Nick())
				end
			else
				ply:ChatPrint("[AI] " .. self:GetLocalized("msg_companion_replace_fail"))
			end
		end)
	end)
	concommand.Add("ai_companion_teleport", function(ply)
		if isSolo then return end
		if not self.utils or not self.utils:IsValid(ply) or not ply:IsPlayer() or ply:IsBot() then return end
		if not self:CheckCooldown(ply, "teleport") then
			ply:ChatPrint("[AI] " .. self:GetLocalized("msg_teleport_cooldown"))
			return
		end
		local bot = self:FindOwnedBot(ply)
		if not self.utils or not self.utils:IsValid(bot) then
			ply:ChatPrint("[AI] " .. self:GetLocalized("msg_no_companion"))
			return
		end
		if bot:InVehicle() then
			bot:ExitVehicle()
		end
		local basePos = ply:GetPos()
		local aim = ply:GetAimVector()
		aim.z = 0
		if aim:Length() > 0 then aim:Normalize() end
		local right = aim:Angle():Right()
		local candidates = {
			basePos - aim * 80,
			basePos + right * 80,
			basePos - right * 80,
			basePos + aim * 120,
			basePos,
		}
		local mins, maxs = bot:GetHull()
		for _, pos in ipairs(candidates) do
			local checkPos = pos + Vector(0, 0, 2)
			local tr = util.TraceHull({
				start = checkPos,
				endpos = checkPos,
				mins = mins,
				maxs = maxs,
				filter = {bot, ply},
			})
			if not tr.Hit then
				bot:SetPos(checkPos)
				if self.botmanager then
					local data = self.botmanager:GetData(bot)
					if data then
						if data.navigation then
							data.navigation.path = nil
							data.navigation.path_index = 1
							data.navigation.goal_pos = Vector(0, 0, 0)
						end
						if data.combat then
							data.combat.target = nil
						end
						self.botmanager:UpdateData(bot, data)
					end
					local states = (self.state and self.state:GetStates()) or {}
					self.botmanager:SetBotState(bot, states.FOLLOW or "following")
				end
				ply:ChatPrint("[AI] " .. self:GetLocalized("msg_teleport_success"))
				return
			end
		end
		ply:ChatPrint("[AI] " .. self:GetLocalized("msg_teleport_fail"))
	end)
	concommand.Add("ai_companion_stealth", function(ply)
		if isSolo then return end
		if not self.utils or not self.utils:IsValid(ply) or ply:IsBot() then return end
		local current = self:GetPlayerSettingSafe(ply, "stealth_mode", false)
		local newValue = not current
		if self:SetBotSetting(ply, "stealth_mode", newValue) then
			if self.utils and self.utils:IsValid(ply) then
				local stateText = newValue and self:GetLocalized("state_on_caps") or self:GetLocalized("state_off_caps")
		ply:ChatPrint("[AI] " .. self:GetLocalized("msg_stealth_mode") .. stateText)
			end
		end
	end)
	concommand.Add("ai_companion_defender", function(ply)
		if isSolo then return end
		if not self.utils or not self.utils:IsValid(ply) or ply:IsBot() then return end
		local current = self:GetPlayerSettingSafe(ply, "defender_mode", false)
		local newValue = not current
		if self:SetBotSetting(ply, "defender_mode", newValue) then
			if self.utils and self.utils:IsValid(ply) then
				local stateText = newValue and self:GetLocalized("state_on_caps") or self:GetLocalized("state_off_caps")
		ply:ChatPrint("[AI] " .. self:GetLocalized("msg_defender_mode") .. stateText)
			end
		end
	end)
	concommand.Add("ai_companion_medic", function(ply)
		if isSolo then return end
		if not self.utils or not self.utils:IsValid(ply) or ply:IsBot() then return end
		local current = self:GetPlayerSettingSafe(ply, "medic_mode", false)
		local newValue = not current
		if self:SetBotSetting(ply, "medic_mode", newValue) then
			if self.utils and self.utils:IsValid(ply) then
				local stateText = newValue and self:GetLocalized("state_on_caps") or self:GetLocalized("state_off_caps")
		ply:ChatPrint("[AI] " .. self:GetLocalized("msg_medic_mode") .. stateText)
			end
		end
	end)
	concommand.Add("ai_companion_pacifist", function(ply)
		if isSolo then return end
		if not self.utils or not self.utils:IsValid(ply) or ply:IsBot() then return end
		local current = self:GetPlayerSettingSafe(ply, "pacifist_mode", false)
		local newValue = not current
		if self:SetBotSetting(ply, "pacifist_mode", newValue) then
			if self.utils and self.utils:IsValid(ply) then
				local stateText = newValue and self:GetLocalized("state_on_caps") or self:GetLocalized("state_off_caps")
		ply:ChatPrint("[AI] " .. self:GetLocalized("msg_pacifist_mode") .. stateText)
			end
		end
	end)
	concommand.Add("ai_companion_aggressive", function(ply)
		if isSolo then return end
		if not self.utils or not self.utils:IsValid(ply) or ply:IsBot() then return end
		local current = self:GetPlayerSettingSafe(ply, "aggressive_mode", false)
		local newValue = not current
		if self:SetBotSetting(ply, "aggressive_mode", newValue) then
			if self.utils and self.utils:IsValid(ply) then
				local stateText = newValue and self:GetLocalized("state_on_caps") or self:GetLocalized("state_off_caps")
		ply:ChatPrint("[AI] " .. self:GetLocalized("msg_aggressive_mode") .. stateText)
			end
		end
	end)
	concommand.Add("ai_companion_combat_weapon", function(ply, cmd, args)
		if isSolo then return end
		if not self.utils or not self.utils:IsValid(ply) or not ply:IsPlayer() then return end
		if ply:IsBot() then return end
		if #args < 1 then
			if self.utils and self.utils:IsValid(ply) then
				ply:ChatPrint("[AI] " .. self:GetLocalized("msg_usage_combat_weapon"))
			end
			return
		end
		local weapon = args[1]
		if self:SetBotSetting(ply, "combat_weapon", weapon) then
			if self.utils and self.utils:IsValid(ply) then
				ply:ChatPrint("[AI] " .. self:GetLocalized("msg_combat_weapon") .. weapon)
			end
		end
	end)
	concommand.Add("ai_companion_melee_weapon", function(ply, cmd, args)
		if isSolo then return end
		if not self.utils or not self.utils:IsValid(ply) or not ply:IsPlayer() then return end
		if ply:IsBot() then return end
		if #args < 1 then
			if self.utils and self.utils:IsValid(ply) then
				ply:ChatPrint("[AI] " .. self:GetLocalized("msg_usage_melee_weapon"))
			end
			return
		end
		local weapon = args[1]
		if self:SetBotSetting(ply, "melee_weapon", weapon) then
			if self.utils and self.utils:IsValid(ply) then
				ply:ChatPrint("[AI] " .. self:GetLocalized("msg_melee_weapon") .. weapon)
			end
		end
	end)
	concommand.Add("ai_companion_idle_weapon", function(ply, cmd, args)
		if isSolo then return end
		if not self.utils or not self.utils:IsValid(ply) or not ply:IsPlayer() then return end
		if ply:IsBot() then return end
		if #args < 1 then
			if self.utils and self.utils:IsValid(ply) then
				ply:ChatPrint("[AI] " .. self:GetLocalized("msg_usage_idle_weapon"))
			end
			return
		end
		local weapon = args[1]
		if self:SetBotSetting(ply, "idle_weapon", weapon) then
			if self.utils and self.utils:IsValid(ply) then
				ply:ChatPrint("[AI] " .. self:GetLocalized("msg_idle_weapon") .. weapon)
			end
		end
	end)
	concommand.Add("ai_companion_create", function(ply, cmd, args)
		if isSolo then return end
		if game.SinglePlayer() then
			if self.utils and self.utils:IsValid(ply) then
				ply:ChatPrint("[AI] " .. self:GetLocalized("bot_solo_mode"))
			end
			return
		end
		if not self.utils or not self.utils:IsValid(ply) or not ply:IsPlayer() or ply:IsBot() then return end
		if self.botmanager and self.botmanager:HasBot(ply) then
			if self.utils and self.utils:IsValid(ply) then
				ply:ChatPrint("[AI] " .. self:GetLocalized("msg_companion_exists"))
				ply:ChatPrint("[AI] " .. self:GetLocalized("msg_use_remove"))
			end
			return
		end
		if not self.spawn then
			if self.utils and self.utils:IsValid(ply) then
				ply:ChatPrint("[AI] " .. self:GetLocalized("msg_spawn_unloaded"))
			end
			return
		end
		local model = args[1] or "models/player/urban.mdl"
		local bot = self.spawn:CreateAICompanion(model, nil, ply)
		if bot and bot:IsValid() and bot:IsPlayer() then
			if self.utils and self.utils:IsValid(ply) then
				ply:ChatPrint("[AI] " .. self:GetLocalized("msg_companion_created"))
			end
			if self.utils then
				self.utils.LogInfo("Commands", self:GetLocalized("log_bot_created"), ply:Nick())
			end
		else
			if self.utils and self.utils:IsValid(ply) then
				ply:ChatPrint("[AI] " .. self:GetLocalized("msg_companion_create_fail"))
			end
		end
	end)
	concommand.Add("ai_companion_remove", function(ply)
		if isSolo then return end
		if not self.utils or not self.utils:IsValid(ply) or not ply:IsPlayer() or ply:IsBot() then return end
		if not self.botmanager then return end
		local bot = self.botmanager:GetBotByOwner(ply)
		if not self.utils or not self.utils:IsValid(bot) then
			if self.utils and self.utils:IsValid(ply) then
				ply:ChatPrint("[AI] " .. self:GetLocalized("msg_no_companion"))
			end
			return
		end
		local botNick = bot:Nick() or self:GetLocalized("companion_fallback_name")
		if self.botmanager:RemoveBot(bot, self:GetLocalized("reason_removed_by_player"), true) then
			if self.utils and self.utils:IsValid(ply) then
				local prefix = self:GetLocalized("msg_companion_prefix")
				local removedMsg = self:GetLocalized("msg_companion_removed")
				ply:ChatPrint("[AI] " .. prefix .. botNick .. removedMsg)
			end
		else
			if self.utils and self.utils:IsValid(ply) then
				ply:ChatPrint("[AI] " .. self:GetLocalized("msg_companion_remove_fail"))
			end
		end
	end)
	concommand.Add("ai_companion_status", function(ply)
		if isSolo then return end
		if not self.utils or not self.utils:IsValid(ply) or not ply:IsPlayer() or ply:IsBot() then return end
		local bot = self:FindOwnedBot(ply)
		if not self.utils or not self.utils:IsValid(bot) then
			print("[AI] " .. self:GetLocalized("msg_no_companion"))
			return
		end
		local data = self.botmanager:GetData(bot)
		local hp = bot:Health() .. "/" .. bot:GetMaxHealth()
		local armor = bot:Armor()
		local state = data and data.state or "idle"
		local task = data and data.task or bot:GetNWString("CurrentTask", "")
		print("[AI] " .. self:GetLocalized("msg_status_detailed_header"))
		print("[AI] " .. self:GetLocalized("msg_status_name") .. bot:Nick())
		print("[AI] " .. self:GetLocalized("msg_status_health") .. hp)
		print("[AI] " .. self:GetLocalized("msg_status_armor") .. armor)
		print("[AI] " .. self:GetLocalized("msg_status_state") .. state .. " (" .. task .. ")")
		if data and data.config then
			print("[AI] " .. self:GetLocalized("msg_status_modes_stealth") .. tostring(data.config.stealth_mode) ..
				self:GetLocalized("msg_status_modes_defender") .. tostring(data.config.defender_mode) ..
				self:GetLocalized("msg_status_modes_medic") .. tostring(data.config.medic_mode))
		end
	end)
	concommand.Add("ai_reset_settings", function(ply)
		if not self.utils or not self.utils:IsValid(ply) then return end
		local defaultSettings = {
			LLM_IP = "127.0.0.1",
			LLM_Port = 1234,
			LLM_Model = "local-model",
			TTS_IP = "127.0.0.1",
			TTS_Port = 8188,
			TTS_Enabled = false,
			LLM_Enabled = true,
			Debug_Mode = false,
			Stealth_Mode = false,
			Defender_Mode = false,
			Medic_Mode = false,
			Pacifist_Mode = false,
			Aggressive_Mode = false,
			Prefix_Text = "[AI]",
			Prefix_Color_R = 255,
			Prefix_Color_G = 200,
			Prefix_Color_B = 0,
			Prefix_Rainbow = false,
			Model_Path = "models/player/urban.mdl",
			Companion_Nick = "AI_Companion",
			Combat_Weapon = "weapon_smg1",
			Melee_Weapon = "weapon_crowbar",
			Idle_Weapon = "weapon_physgun",
			LLM_Timeout = 60,
			TTS_Timeout = 120,
		}
		if self.state then
			for k, v in pairs(defaultSettings) do
				self.state:setSetting(k, v)
			end
			self.state:setState("TTS_Enabled", defaultSettings.TTS_Enabled)
			self.state:setState("LLM_Enabled", defaultSettings.LLM_Enabled)
		end
		local bot = nil
		if self.botmanager then
			bot = self.botmanager:GetBotByOwner(ply)
		end
		if self.utils and self.utils:IsValid(bot) then
			for k, v in pairs(defaultSettings) do
				self:SetBotSetting(ply, k, v)
			end
		end
		if self.utils and self.utils:IsValid(ply) then
			ply:ChatPrint("[AI] " .. self:GetLocalized("msg_settings_reset"))
		end
	end)
	concommand.Add("ai_auto_sync", function(ply)
		if not self.utils or not self.utils:IsValid(ply) then return end
		if not ply:IsAdmin() then
			ply:ChatPrint("[AI] " .. self:GetLocalized("settings_admin_only"))
			return
		end
		if self.state then
			local current = self.state:getSetting("Auto_Sync_Global", true)
			local newVal = not current
			self.state:setSetting("Auto_Sync_Global", newVal)
			self.state:SaveToFile()
			local state = newVal and self:GetLocalized("state_on_caps") or self:GetLocalized("state_off_caps")
			ply:ChatPrint("[AI] " .. self:GetLocalized("msg_auto_sync") .. state)
			if self.utils then
				self.utils.LogInfo("Commands", self:GetLocalized("log_auto_sync_set"), state, ply:Nick())
			end
			net.Start("gmod.one/ai-companion/global-setting-updated")
			net.WriteString("Auto_Sync_Global")
			net.WriteString(tostring(newVal))
			net.Broadcast()
		else
			ply:ChatPrint("[AI] " .. self:GetLocalized("msg_state_unavailable"))
		end
	end)
	concommand.Add("ai_sync_global", function(ply)
		if not self.utils or not self.utils:IsValid(ply) then return end
		if not ply:IsAdmin() then
			ply:ChatPrint("[AI] " .. self:GetLocalized("settings_admin_only"))
			return
		end
		if self.state then
			self.state:SaveToFile()
			local settings = self.state:getRaw("Settings") or {}
			for key, value in pairs(settings) do
				if self.state:IsGlobalKey(key) then
					self.state:SyncSingleSettingToAll(key, value)
				end
			end
			ply:ChatPrint("[AI] " .. self:GetLocalized("msg_global_synced"))
			if self.utils then
				self.utils.LogInfo("Commands", self:GetLocalized("log_global_synced"), ply:Nick())
			end
		else
			ply:ChatPrint("[AI] " .. self:GetLocalized("msg_state_unavailable"))
		end
	end)
	concommand.Add("ai_debug_mode", function(ply)
		if not self.utils or not self.utils:IsValid(ply) then return end
		if not ply:IsAdmin() then
			ply:ChatPrint("[AI] " .. self:GetLocalized("settings_admin_only"))
			return
		end
		if self.state then
			local current = self.state:getSetting("Debug_Mode", false)
			local newVal = not current
			self.state:setSetting("Debug_Mode", newVal)
			self.state:SaveToFile()
			local state = newVal and self:GetLocalized("state_on_caps") or self:GetLocalized("state_off_caps")
			ply:ChatPrint("[AI] " .. self:GetLocalized("msg_debug_mode") .. state)
			if self.utils then
				self.utils.LogInfo("Commands", self:GetLocalized("log_debug_mode_set"), state, ply:Nick())
			end
			net.Start("gmod.one/ai-companion/debug-mode-updated")
			net.WriteBool(newVal)
			net.Broadcast()
		else
			ply:ChatPrint("[AI] " .. self:GetLocalized("msg_state_unavailable"))
		end
	end)
	concommand.Add("ai_ping_servers", function(ply)
		if not self.utils or not self.utils:IsValid(ply) then return end
		if not ply:IsAdmin() then
			ply:ChatPrint("[AI] " .. self:GetLocalized("msg_admin_only_ping"))
			return
		end
		local llmIP = self:GetSetting("LLM_IP", "127.0.0.1")
		local llmPort = self:GetSetting("LLM_Port", 1234)
		local ttsIP = self:GetSetting("TTS_IP", "127.0.0.1")
		local ttsPort = self:GetSetting("TTS_Port", 8188)
		llmIP = string.gsub(tostring(llmIP), ":%d+$", "")
		ttsIP = string.gsub(tostring(ttsIP), ":%d+$", "")
		local llmUrl = "http://" .. llmIP .. ":" .. llmPort
		local ttsUrl = "http://" .. ttsIP .. ":" .. ttsPort
		local function printBoth(msg)
			print("[AI PING] " .. msg)
			if IsValid(ply) then
				ply:ChatPrint("[AI PING] " .. msg)
			end
		end
		printBoth(self:GetLocalized("msg_ping_llm") .. llmUrl)
		printBoth(self:GetLocalized("msg_ping_tts") .. ttsUrl)
		local llmChecked = false
		local ttsChecked = false
		local checkDone = false
		local function checkBothDone()
			if checkDone then return end
			if llmChecked and ttsChecked then
				checkDone = true
				printBoth(self:GetLocalized("msg_ping_done"))
			end
		end
		HTTP({
			url = llmUrl,
			method = "GET",
			timeout = 3,
			success = function(code, body)
				printBoth(self:GetLocalized("msg_ping_llm_ok") .. code .. ")")
				llmChecked = true
				checkBothDone()
			end,
			failed = function(err)
				printBoth(self:GetLocalized("msg_ping_llm_fail") .. llmIP .. ":" .. llmPort)
				llmChecked = true
				checkBothDone()
			end
		})
		local checkUrl = ttsUrl
		if string.sub(checkUrl, -1) ~= "/" then
			checkUrl = checkUrl .. "/"
		end
		checkUrl = checkUrl .. "system_stats"
		HTTP({
			url = checkUrl,
			method = "GET",
			timeout = 5,
			success = function(code, body)
				if code == 200 then
					printBoth(self:GetLocalized("msg_ping_tts_ok") .. code .. ")")
				else
					printBoth(self:GetLocalized("msg_ping_tts_warn") .. code)
				end
				ttsChecked = true
				checkBothDone()
			end,
			failed = function(err)
				printBoth(self:GetLocalized("msg_ping_tts_fail") .. ttsIP .. ":" .. ttsPort)
				ttsChecked = true
				checkBothDone()
			end
		})
		timer.Simple(6, function()
			if checkDone then return end
			checkDone = true
			if not llmChecked then
				printBoth(self:GetLocalized("msg_ping_llm_timeout"))
			end
			if not ttsChecked then
				printBoth(self:GetLocalized("msg_ping_tts_timeout"))
			end
			printBoth(self:GetLocalized("msg_ping_done"))
		end)
	end)
end
function Commands:SetupChatHook()
	if not SERVER then return end

	hook.Remove("PlayerSay", "gmod.one/ai-companion/process-chat")

	local selfRef = self
	hook.Add("PlayerSay", "gmod.one/ai-companion/process-chat", function(ply, text)
		if ply:IsBot() then
			return
		end
		if ply:GetNWBool("IsAICompanion", false) then
			return
		end
		local lowerText = string.lower(text)

		if string.StartWith(lowerText, "!ai ") then
			if not selfRef:CheckCooldown(ply, "ai") then
				selfRef:SendSystemMessage(ply, selfRef:GetLocalized("cmd_cooldown"))
				return ""
			end
			local ok, remaining = selfRef:CheckGlobalCooldown("llm_request", 3)
			if not ok then
				selfRef:SendSystemMessage(ply, selfRef:GetLocalized("cmd_llm_cooldown"))
				return ""
			end
			local okLimit, errLimit = selfRef:CheckLLMRateLimit(ply)
			if not okLimit then
				selfRef:SendSystemMessage(ply, errLimit)
				return ""
			end
			local msg = string.Trim(string.sub(text, 5))
			if msg == "" then
				ply:ChatPrint("[AI] " .. selfRef:GetLocalized("msg_enter_ai_text"))
				return ""
			end
			local maxPrivateLen = 300
			if selfRef.config and selfRef.config:get("Chat") then
				maxPrivateLen = selfRef.config:get("Chat").MaxPrivateMessageLength or 300
			end
			msg = string.sub(msg, 1, maxPrivateLen)
			local llmEnabled = selfRef:GetState("LLM_Enabled", true)
			local llmMode = selfRef:GetSetting("LLM_Mode", "local")
			if llmEnabled == false or llmMode == "disabled" then
				ply:ChatPrint("[AI] " .. selfRef:GetLocalized("msg_llm_disabled"))
				return ""
			end
			if selfRef.llm then
				local steamID = ply:SteamID64()
				local prefixColor = Color(255, 255, 255)
				if selfRef.state then
					local rainbow = selfRef.state:getPlayerSetting(steamID, "Prefix_Rainbow", false)
					if rainbow then
						local hue = (CurTime() * 120) % 360
						prefixColor = HSVToColor(hue, 1, 1)
					else
						prefixColor = Color(
							selfRef.state:getPlayerSetting(steamID, "Prefix_Color_R", 255),
							selfRef.state:getPlayerSetting(steamID, "Prefix_Color_G", 200),
							selfRef.state:getPlayerSetting(steamID, "Prefix_Color_B", 0)
						)
					end
				end

				selfRef.shared:SendChatMessage(ply, msg, prefixColor, ply:Nick(), cleanPrefix, true)
				selfRef.llm:Ask(ply, msg, true)
			end
			return ""
		end

		if string.StartWith(lowerText, "!companion") and not game.SinglePlayer() then
			if not selfRef._companionCommands then
				selfRef:RegisterCompanionCommands()
			end
			local afterCommand = string.sub(text, string.len("!companion") + 1)
			local cmd = string.Trim(afterCommand)
			if cmd == "" then
				ply:ChatPrint("[AI] " .. selfRef:GetLocalized("msg_use_companion_help"))
				return ""
			end
			local args = {}
			for word in string.gmatch(cmd, "[^%s]+") do
				table.insert(args, word)
			end
			local command = string.lower(args[1] or "")
			local entry = selfRef._companionCommands[command]
			if not entry then
				local canonical = selfRef._companionAliases[command]
				if canonical then entry = selfRef._companionCommands[canonical] end
			end
			if not entry then
				return nil
			end
			local bot = nil
			if entry.needsBot then
				bot = selfRef:FindOwnedBot(ply)
				if not selfRef.utils or not selfRef.utils:IsValid(bot) then
					ply:ChatPrint("[AI] " .. selfRef:GetLocalized("msg_no_companion_create"))
					return ""
				end
				if not selfRef:IsBotOwner(bot, ply) then
					ply:ChatPrint("[AI] " .. selfRef:GetLocalized("msg_not_your_companion"))
					return ""
				end
			else
				bot = selfRef:FindOwnedBot(ply)
			end
			local states = selfRef.state and selfRef.state:GetStates() or {}
			local ok, err = pcall(entry.fn, bot, ply, args, states)
			if not ok then
				if selfRef.utils then
					local errorMsg = selfRef:GetLocalized("log_companion_cmd_error")
					selfRef.utils.LogError("Commands", errorMsg, command, tostring(err))
				end
				ply:ChatPrint("[AI] " .. selfRef:GetLocalized("msg_cmd_error"))
			end
			return ""
		end

		if not string.StartWith(lowerText, "!") and not string.StartWith(lowerText, "/") then
			local msg = string.Trim(text)
			if msg == "" then return nil end
			local llmEnabled = selfRef:GetState("LLM_Enabled", true)
			local llmMode = selfRef:GetSetting("LLM_Mode", "local")
			if llmEnabled == false or llmMode == "disabled" then
				return nil
			end
			if not selfRef:CheckCooldown(ply, "ai") then
				selfRef:SendSystemMessage(ply, selfRef:GetLocalized("cmd_cooldown"))
				return nil
			end
			local ok, remaining = selfRef:CheckGlobalCooldown("llm_request", 3)
			if not ok then
				local rateLimitMsg = selfRef:GetLocalized("msg_llm_rate_limit")
				local secondsMsg = selfRef:GetLocalized("msg_seconds")
				selfRef:SendSystemMessage(ply, rateLimitMsg .. remaining .. secondsMsg)
				return nil
			end
			local maxLen = 300
			if selfRef.config and selfRef.config:get("Chat") then
				maxLen = selfRef.config:get("Chat").MaxPrivateMessageLength or 300
			end
			msg = string.sub(msg, 1, maxLen)
			if selfRef.llm then
				selfRef.llm:Ask(ply, msg, false)
			end
			return nil
		end
	end)
end
function Commands:GetCleanPrefix(ply)
	if not self.utils or not self.utils:IsValid(ply) then return "AI" end
	local prefix = self:GetSetting("Prefix_Text", "[AI]")
	local clean = string.gsub(prefix, "^%[", "")
	clean = string.gsub(clean, "%]$", "")
	clean = string.Trim(clean)
	if clean == "" then clean = "AI" end
	return clean
end
function Commands:DoSitCommand(bot, ply, states)
	if not self.utils or not self.utils:IsValid(bot) then return end

	local vehicleService = self.vehicle
	if not vehicleService then
		local locator = AICompanion.GetLocator()
		if locator then vehicleService = locator:get("vehicle") end
	end
	if not vehicleService then
		bot:ChatPrint("[AI] " .. self:GetLocalized("msg_vehicle_unloaded"))
		return
	end

	if bot:InVehicle() then
		bot:ExitVehicle()
		timer.Simple(0.2, function()
			if not self.utils or not self.utils:IsValid(bot) then return end
			self:DoSitCommand(bot, ply, states)
		end)
		return
	end

	local radius = 500
	local nearestVehicle = vehicleService:FindNearestVehicle(bot, radius)

	if self.utils and self.utils:IsValid(nearestVehicle) then
		if vehicleService.ResolveVehicleRoot then
			nearestVehicle = vehicleService:ResolveVehicleRoot(nearestVehicle)
		else
			nearestVehicle = vehicleService:GetGlideRoot(nearestVehicle) or nearestVehicle
		end
	end

	if not self.utils or not self.utils:IsValid(nearestVehicle) then
		bot:ChatPrint("[AI] " .. self:GetLocalized("msg_no_vehicle"))
		return
	end

	local success = vehicleService:EnterDriverSeat(bot, nearestVehicle)

	if success then
		timer.Simple(0.1, function()
			if not self.utils or not self.utils:IsValid(bot) then return end
			if bot:InVehicle() then
				self.botmanager:SetBotState(bot, states.SITTING or "sitting")
				bot:ChatPrint("[AI] " .. self:GetLocalized("msg_sat_in_vehicle"))
			else
				timer.Simple(0.3, function()
					if not self.utils or not self.utils:IsValid(bot) then return end
					if bot:InVehicle() then return end
					local retry = vehicleService:EnterDriverSeat(bot, nearestVehicle)
					if retry and bot:InVehicle() then
						self.botmanager:SetBotState(bot, states.SITTING or "sitting")
						bot:ChatPrint("[AI] " .. self:GetLocalized("msg_sat_in_vehicle"))
					else
						bot:ChatPrint("[AI] " .. self:GetLocalized("msg_no_vehicle"))
					end
				end)
			end
		end)
	else
		bot:ChatPrint("[AI] " .. self:GetLocalized("msg_no_vehicle"))
	end
end

function Commands:DoSitCommandDelayed(bot, ply, states, vehicleService)
	if not self.utils or not self.utils:IsValid(bot) then return end
	if bot:InVehicle() then
		bot:ExitVehicle()
		timer.Simple(0.1, function()
			if self.utils and self.utils:IsValid(bot) and not bot:InVehicle() then
				self:DoSitCommandDelayed(bot, ply, states, vehicleService)
			end
		end)
		return
	end

	local radius = 500
	local nearestVehicle = vehicleService:FindNearestVehicle(bot, radius)
	if not self.utils or not self.utils:IsValid(nearestVehicle) then
		bot:ChatPrint("[AI] " .. self:GetLocalized("msg_no_vehicle"))
		return
	end

	local success = vehicleService:EnterDriverSeat(bot, nearestVehicle)
	if success then
		self.botmanager:SetBotState(bot, states.SITTING or "sitting")
		bot:ChatPrint("[AI] " .. self:GetLocalized("msg_sat_in_vehicle"))
	else
		bot:ChatPrint("[AI] " .. self:GetLocalized("msg_no_vehicle"))
	end
end
function Commands:FindPlayerByName(name)
	if not name or name == "" then return nil end

	if name == "1" or string.lower(name) == "me" or string.lower(name) == "меня" then
		return nil
	end

	name = string.lower(name)
	local bestMatch = nil
	local bestScore = 0

	for _, ply in ipairs(player.GetAll()) do
		if self.utils and self.utils:IsValid(ply) and not ply:IsBot() then
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
function Commands:IsHostileEntity(ent)
	if not self.utils or not self.utils:IsValid(ent) then return false end
	if not ent:Alive() then return false end
	local class = ent:GetClass()
	if self.state and self.state:IsFriendlyNPC(class) then return false end
	if ent:IsPlayer() and not ent:IsBot() then return true end
	if ent:IsNPC() or ent:IsNextBot() then return true end
	return false
end

function Commands:FindEntityByName(name)
	if not name or name == "" then return nil end
	name = string.lower(name)
	for _, ent in ipairs(ents.GetAll()) do
		if self.utils and self.utils:IsValid(ent) then
			if ent:IsPlayer() and not ent:IsBot() then
				if string.lower(ent:Nick()) == name then return ent end
			elseif ent:IsNPC() or ent:IsNextBot() then
				local class = ent:GetClass() or ""
				if string.lower(class) == name then return ent end
			end
		end
	end
	return nil
end

function Commands:FindNearestEnemy(bot, radius)
	if not self.utils or not self.utils:IsValid(bot) then return nil end
	radius = radius or 1500
	local botPos = bot:GetPos()
	local bestEnemy = nil
	local bestDist = radius
	local locator = AICompanion.GetLocator()
	local combat = locator and locator:get("combat")
	for _, ent in ipairs(ents.FindInSphere(botPos, radius)) do
		if self.utils:IsValid(ent) and ent ~= bot then
			local isHostile = false
			if combat and combat.IsHostileByDefault then
				isHostile = combat:IsHostileByDefault(ent, bot)
			else
				if ent:IsPlayer() and not ent:IsBot() then isHostile = true
				elseif ent:IsNPC() or ent:IsNextBot() then isHostile = true end
			end
			if isHostile then
				local dist = botPos:Distance(ent:GetPos())
				if dist < bestDist then
					bestDist = dist
					bestEnemy = ent
				end
			end
		end
	end
	return bestEnemy
end

function Commands:FindNearestNPCEnemy(bot, radius)
	if not self.utils or not self.utils:IsValid(bot) then return nil end
	radius = radius or 1500
	local botPos = bot:GetPos()
	local bestEnemy = nil
	local bestDist = radius
	local locator = AICompanion.GetLocator()
	local combat = locator and locator:get("combat")
	for _, ent in ipairs(ents.FindInSphere(botPos, radius)) do
		if self.utils:IsValid(ent) and ent ~= bot then
			local isHostile = false
			if combat and combat.IsHostileByDefault then
				isHostile = combat:IsHostileByDefault(ent, bot)
			else
				if ent:IsNPC() or ent:IsNextBot() then isHostile = true end
			end
			if isHostile then
				local dist = botPos:Distance(ent:GetPos())
				if dist < bestDist then
					bestDist = dist
					bestEnemy = ent
				end
			end
		end
	end
	return bestEnemy
end

return Commands
