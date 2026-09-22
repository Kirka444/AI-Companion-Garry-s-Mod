-- Runtime data storage for companion bots.

local Data = {}
function Data:new(state, config, utils)
	local obj = {
		state = state,
		config = config,
		utils = utils,
		botData = {},
		entIndexToUUID = {},
		_initialized = false,
		_defaultData = nil,
	}
	setmetatable(obj, self)
	self.__index = self
	return obj
end
function Data:GetLocalized(key, ...)
	local locator = AICompanion.GetLocator()
	if locator and locator:has("locale") then
		local locale = locator:get("locale")
		if locale and locale.Get then
			return locale:Get(key, ...)
		end
	end
	return key
end
function Data:init()
	if self._initialized then return end
	self._defaultData = self:CreateDefaultData()
	self._defaultDataMeta = { __index = self._defaultData }
	self._initialized = true
	if self.utils then
		self.utils:LogInfo("Data", self:GetLocalized("log_data_init"))
	end
end
function Data:CreateDefaultData()
	return {
		botID = nil,
		owner = nil,
		creationTime = 0,
		uuid = nil,
		config = {
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
		},
		state = "idle",
		task = "",
		flags = {
			is_in_combat = false,
			is_following = false,
			is_pointing = false,
			is_in_vehicle = false,
			is_sitting = false,
			is_medic_healing = false,
		},
		combat = {
			target = nil,
			target_type = nil,
			triggered_by = nil,
			last_attack_time = 0,
			last_combat_end = 0,
			frag_last_throw = 0,
			rpg_last_fire = 0,
			alt_fire_timer = 0,
			weapon_switch_wait = 0,
			weapon_wait_ticks = 0,
			next_strafe_change = 0,
			strafe_dir = 1,
			last_melee_give = 0,
			last_damage_time = 0,
			heal_cooldown_until = 0,
			medic_post_combat_cooldown = 0,
		},
		navigation = {
			path = nil,
			path_index = 1,
			goal_pos = Vector(0, 0, 0),
			target_key = -1,
			fail_count = 0,
			disabled_until = 0,
			stuck = {
				pos = Vector(0, 0, 0),
				time = 0,
				unstuck_dir = nil,
				unstuck_until = 0,
				pos_history = {},
				no_progress_time = 0,
				wp_stuck_time = 0,
				wp_stuck_pos = Vector(0, 0, 0),
				last_dist_to_goal = nil,
				last_dist_to_wp = nil,
				loop_key = nil,
				loop_count = 0,
				loop_reset = 0,
				teleport_fails = 0,
				in_narrow_passage = false,
			},
			repath = {
				force = false,
				next_force = 0,
				last_wall = 0,
				cooldown = 0,
				last_time = 0,
			},
			door_wait = 0,
			slide_time = 0,
			area_cache = {
				pos = Vector(0, 0, 0),
				area = nil,
				time = 0,
			},
		},
		vehicle = {
			locked_vehicle = nil,
			locked_seat = nil,
			sit_by_command = false,
			is_driver = false,
			was_in_vehicle = false,
			cached_turret = nil,
			cached_weapons = nil,
			path = nil,
			path_time = 0,
			path_index = 1,
			dead_zone_active = false,
			engine_state = "on",
			engine_idle_timer = 0,
		},
		point = {
			pos = nil,
			angle = nil,
		},
		_nw_cache = {
			stealth_mode = false,
			defender_mode = false,
			medic_mode = false,
			pacifist_mode = false,
			aggressive_mode = false,
			state = "idle",
			task = "",
			is_ai_companion = true,
			owner_name = "",
		},
	}
end
function Data:IsCompanionBot(ent)
	if not ent or not ent:IsValid() or not ent:IsPlayer() then
		return false
	end
	if ent:GetNWBool("IsAICompanion", false) == true then return true end
	if ent._aiUUID then return true end
	return false
end
function Data:InitBotData(bot, owner, settings)
	if self.utils then
	end
	if not bot or not bot:IsValid() or not bot:IsPlayer() then
		if self.utils then
			self.utils:LogError("Data", self:GetLocalized("log_data_invalid"))
		end
		return nil
	end
	local existingData = self:GetBotData(bot)
	if self.utils then
	end
	if existingData then
		if self.utils and self.utils:IsValid(owner) then
			existingData.owner = owner
			self:SetBotData(bot, existingData)
		end
		return existingData
	end
	local uuid = bot._aiUUID
	if not uuid then
		uuid = string.format("%08x-%04x-%04x-%04x-%012x",
			bit.band(util.CRC("bot_" .. os.time() .. "_" .. math.random(1, 9999999)), 0xFFFFFFFF),
			math.random(0, 0xFFFF),
			math.random(0, 0xFFFF),
			math.random(0, 0xFFFF),
			math.random(0, 0xFFFFFFFFFFFF))
		bot._aiUUID = uuid
	end
	local data = setmetatable({}, self._defaultDataMeta)
	data.botID = bot:EntIndex()
	data.owner = owner
	data.creationTime = CurTime()
	data.uuid = uuid
	if settings then
		local cfg = data.config
		if settings.combat_weapon then cfg.combat_weapon = settings.combat_weapon end
		if settings.melee_weapon then cfg.melee_weapon = settings.melee_weapon end
		if settings.idle_weapon then cfg.idle_weapon = settings.idle_weapon end
		if settings.stealth_mode ~= nil then cfg.stealth_mode = settings.stealth_mode end
		if settings.defender_mode ~= nil then cfg.defender_mode = settings.defender_mode end
		if settings.medic_mode ~= nil then cfg.medic_mode = settings.medic_mode end
		if settings.pacifist_mode ~= nil then cfg.pacifist_mode = settings.pacifist_mode end
		if settings.aggressive_mode ~= nil then cfg.aggressive_mode = settings.aggressive_mode end
		if settings.model_path then cfg.model_path = settings.model_path end
		if settings.companion_nick then cfg.companion_nick = settings.companion_nick end
		if settings.show_sender_name ~= nil then cfg.show_sender_name = settings.show_sender_name end
		data._nw_cache.stealth_mode = cfg.stealth_mode
		data._nw_cache.defender_mode = cfg.defender_mode
		data._nw_cache.medic_mode = cfg.medic_mode
		data._nw_cache.pacifist_mode = cfg.pacifist_mode
		data._nw_cache.aggressive_mode = cfg.aggressive_mode
		if self.utils and self.utils:IsValid(owner) then
			data._nw_cache.owner_name = owner:Nick()
		end
		data._nw_cache.is_ai_companion = true
	end
	self:SetBotData(bot, data)
	return data
end
function Data:GetBotData(bot)
	if not bot or not bot:IsValid() or not bot:IsPlayer() then
		return nil
	end
	if not self:IsCompanionBot(bot) then return nil end
	local entIndex = bot:EntIndex()
	local uuid = self.entIndexToUUID[entIndex]
	if uuid and self.botData[uuid] then
		bot._aiUUID = uuid
		return self.botData[uuid]
	end
	uuid = bot._aiUUID
	if uuid and self.botData[uuid] then
		self.entIndexToUUID[entIndex] = uuid
		return self.botData[uuid]
	end
	for u, data in pairs(self.botData) do
		if data.botID == entIndex then
			bot._aiUUID = u
			self.entIndexToUUID[entIndex] = u
			return data
		end
	end
	return nil
end
function Data:SetBotData(bot, data)
	if self.utils then
	end
	if not self.utils or not self.utils:IsValid(bot) then
		if self.utils then
			self.utils:LogWarn("Data", self:GetLocalized("log_data_set_invalid"))
		end
		return false
	end
	if not self:IsCompanionBot(bot) then
		if self.utils then
			self.utils:LogWarn("Data", self:GetLocalized("log_data_set_not_companion"))
		end
		return false
	end
	local uuid = bot._aiUUID
	if not uuid then
		uuid = self:GenerateUUID()
		bot._aiUUID = uuid
	end
	local entIndex = bot:EntIndex()
	data.botID = entIndex
	self.botData[uuid] = data
	self.entIndexToUUID[entIndex] = uuid
	if self.utils then
	end
	return true
end
function Data:UpdateBotData(bot, newData)
	if not self.utils or not self.utils:IsValid(bot) then return false end
	local data = self:GetBotData(bot)
	if not data then return false end
	for k, v in pairs(newData) do
		if type(v) == "table" and type(data[k]) == "table" then
			for subK, subV in pairs(v) do
				data[k][subK] = subV
			end
		else
			data[k] = v
		end
	end
	self:SetBotData(bot, data)
	return true
end
function Data:RemoveBotData(bot)
	if not self.utils or not self.utils:IsValid(bot) then return false end
	local entIndex = bot:EntIndex()
	local uuid = bot._aiUUID or self.entIndexToUUID[entIndex]
	if uuid then
		self.botData[uuid] = nil
		self.entIndexToUUID[entIndex] = nil
		return true
	end
	for u, data in pairs(self.botData) do
		if data.botID == entIndex then
			self.botData[u] = nil
			self.entIndexToUUID[entIndex] = nil
			return true
		end
	end
	return false
end
function Data:GenerateUUID()
	return string.format("%08x-%04x-%04x-%04x-%012x",
		math.random(0, 0xFFFFFFFF),
		math.random(0, 0xFFFF),
		math.random(0, 0xFFFF),
		math.random(0, 0xFFFF),
		math.random(0, 0xFFFFFFFFFFFF))
end
function Data:GetAllBotData()
	local result = {}
	for uuid, data in pairs(self.botData) do
		local bot = Entity(data.botID)
		if self.utils and self.utils:IsValid(bot) then
			result[uuid] = {
				bot = bot,
				data = data,
				uuid = uuid,
			}
		end
	end
	return result
end
function Data:GetBotCount()
	local count = 0
	for uuid, data in pairs(self.botData) do
		local bot = Entity(data.botID)
		if self.utils and self.utils:IsValid(bot) then
			count = count + 1
		end
	end
	return count
end
function Data:GetBotConfig(bot)
	local data = self:GetBotData(bot)
	return data and data.config or nil
end
function Data:GetBotCombatWeapon(bot)
	local data = self:GetBotData(bot)
	return data and data.config.combat_weapon or "weapon_smg1"
end
function Data:GetBotMeleeWeapon(bot)
	local data = self:GetBotData(bot)
	return data and data.config.melee_weapon or "weapon_crowbar"
end
function Data:GetBotIdleWeapon(bot)
	local data = self:GetBotData(bot)
	return data and data.config.idle_weapon or "weapon_physgun"
end
function Data:GetBotStealthMode(bot)
	local data = self:GetBotData(bot)
	return data and data.config.stealth_mode or false
end
function Data:GetBotDefenderMode(bot)
	local data = self:GetBotData(bot)
	return data and data.config.defender_mode or false
end
function Data:GetBotMedicMode(bot)
	local data = self:GetBotData(bot)
	return data and data.config.medic_mode or false
end
function Data:GetBotPacifistMode(bot)
	local data = self:GetBotData(bot)
	return data and data.config.pacifist_mode or false
end
function Data:GetBotAggressiveMode(bot)
	local data = self:GetBotData(bot)
	return data and data.config.aggressive_mode or false
end
function Data:GetBotState(bot)
	local data = self:GetBotData(bot)
	return data and data.state or "idle"
end
function Data:SetBotState(bot, state)
	local data = self:GetBotData(bot)
	if not data then return false end
	data.state = state
	data.task = state
	self:SetBotData(bot, data)
	return true
end
function Data:DebugPrint()
	print("")
	print("═══════════════════════════════════════════════════════")
	print("        AI COMPANION - " .. self:GetLocalized("log_data_init"))
	print("═══════════════════════════════════════════════════════")
	print("")
	local allData = self:GetAllBotData()
	if next(allData) == nil then
		print("  " .. self:GetLocalized("msg_no_active_bots"))
		print("")
		return
	end
	for uuid, entry in pairs(allData) do
		local bot = entry.bot
		local data = entry.data
		local owner = data and data.owner
		print("  БОТ " ..
			data.botID ..
			": " ..
			(self.utils and self.utils:IsValid(bot) and bot:Nick() or self:GetLocalized("unknown")))
		print("    UUID: " .. uuid)
		print("    " ..
			self:GetLocalized("status_name"):format(
				self.utils and self.utils:IsValid(owner) and owner:Nick() or self:GetLocalized("msg_no_owner")
			))
		print("    " ..
			self:GetLocalized("status_state"):format(data and data.state or "idle",
				data and data.task or ""))
		print("    " ..
			self:GetLocalized("mode_stealth"):format(tostring(data and data.config.stealth_mode or false)) ..
			" " ..
			self:GetLocalized("mode_defender"):format(tostring(data and data.config.defender_mode or false)) ..
			" " ..
			self:GetLocalized("mode_medic"):format(tostring(data and data.config.medic_mode or false)))
		if data and data.combat and self.utils and self.utils:IsValid(data.combat.target) then
			print("    " ..
			self:GetLocalized("bot_attacking"):format(tostring(data.combat.target:Nick() or data.combat.target:GetClass())))
		end
		print("")
	end
	print("  " .. self:GetLocalized("total_models"):format(self:GetBotCount()))
	print("═══════════════════════════════════════════════════════")
	print("")
end
if SERVER then
	concommand.Add("ai_companion_data_debug", function(ply)
		local locator = AICompanion.GetLocator()
		if not locator or not locator:has("data") then
			print("[AI] " .. self:GetLocalized("error") .. ": Data " .. self:GetLocalized("log_client_error"))
			return
		end
		local data = locator:get("data")
		if data.utils and data.utils:IsValid(ply) and not ply:IsAdmin() then
			ply:ChatPrint("[AI] " .. data:GetLocalized("settings_admin_only"))
			return
		end
		data:DebugPrint()
		if data.utils and data.utils:IsValid(ply) then
			ply:ChatPrint("[AI] " .. data:GetLocalized("status_console"))
		end
	end)
end
return Data
