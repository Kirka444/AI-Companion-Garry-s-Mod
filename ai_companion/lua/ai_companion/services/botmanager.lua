local BotManager = {}
function BotManager:new(state, data, utils)
	local obj = {
		state = state,
		data = data,
		utils = utils,
		bots = {},
		ownerIndex = {},
		botIndex = {},
		_initialized = false,
		botTickCache = {},
		_tickFrame = 0,
		_cleanupHooksSetup = false,
	}
	setmetatable(obj, self)
	self.__index = self
	return obj
end
function BotManager:GetLocalized(key, ...)
	local locator = AICompanion.GetLocator()
	if locator and locator:has("locale") then
		local locale = locator:get("locale")
		if locale and locale.Get then
			return locale:Get(key, ...)
		end
	end
	return key
end
function BotManager:init()
	if self._initialized then return end
	self:MigrateFromLegacy()
	self:SyncAllBots()
	self:SetupHooks()
	if SERVER and not self._cleanupHooksSetup then
		self._cleanupHooksSetup = true
		self:SetupCleanupHooks()
	end
	self._initialized = true
	if self.utils then
		self.utils.LogInfo("BotManager", self:GetLocalized("log_botmanager_init"), self:GetBotCount())
	end
end
function BotManager:SetupHooks()
	if not SERVER then return end
	local selfRef = self
	hook.Add("PlayerDeath", "gmod.one/ai-companion/remove-dead-bot", function(victim, inflictor, attacker)
		if not IsValid(victim) then return end
		if not victim:IsPlayer() then return end
		if not victim.Nick then return end
		if not selfRef:IsCompanionBot(victim) then return end
		local attackerName = selfRef:GetLocalized("unknown")
		if IsValid(attacker) and attacker.Nick then
			attackerName = attacker:Nick()
		elseif IsValid(attacker) then
			attackerName = attacker:GetClass() or tostring(attacker)
		end
		if selfRef.utils then
			selfRef.utils.LogInfo("BotManager", selfRef:GetLocalized("log_bot_death"),
				victim:Nick(), attackerName)
		end
		timer.Simple(0.1, function()
			if IsValid(victim) and victim.Nick and selfRef.utils and selfRef.utils:IsValid(victim) then
				selfRef:RemoveBot(victim, selfRef:GetLocalized("bot_died"), true)
			end
		end)
	end)
	hook.Add("PlayerDisconnected", "gmod.one/ai-companion/remove-owner-bots", function(ply)
		if not IsValid(ply) then return end
		if ply:IsBot() then return end
		local bot = selfRef:GetBotByOwner(ply)
		if bot and selfRef.utils and selfRef.utils:IsValid(bot) then
			if selfRef.utils then
				selfRef.utils.LogInfo("BotManager", selfRef:GetLocalized("log_owner_disconnect"),
					ply:Nick(), bot:Nick())
			end
			selfRef:RemoveBot(bot, selfRef:GetLocalized("bot_removed"):format(bot:Nick()), false)
		end
	end)
end
function BotManager:GetBotTickCache(bot)
	if not IsValid(bot) then return nil end
	local idx = bot:EntIndex()
	local cached = self.botTickCache[idx]
	local frame = CurTime()
	if cached and cached.frame == frame then
		return cached
	end
	local data = self:GetData(bot)
	if not data then return nil end
	local inVehicle = bot:InVehicle()
	local isPassenger = false
	local isDriver = false
	local vehicle = nil
	if inVehicle then
		vehicle = bot:GetVehicle()
		if vehicle then
			local driver = nil
			-- Direct call without pcall - GetDriver is a standard engine method
			if vehicle.GetDriver then
				driver = vehicle:GetDriver()
			end
			if driver == bot then
				isDriver = true
			else
				isPassenger = true
			end
		end
	end
	-- Получаем Vehicle сервис для GetGlideRoot
	local glideRoot = nil
	if inVehicle and vehicle then
		local locator = AICompanion.GetLocator()
		local vehicleService = locator and locator:get("vehicle")
		if vehicleService and vehicleService.GetGlideRoot then
			glideRoot = vehicleService:GetGlideRoot(vehicle)
		end
	end
	cached = {
		frame       = frame,
		data        = data,
		owner       = data.owner,
		state       = data.state or "idle",
		config      = data.config,
		combat      = data.combat,
		inVehicle   = inVehicle,
		vehicle     = vehicle,
		alive       = bot:Alive(),
		stealth     = data.config and data.config.stealth_mode or false,
		medic       = data.config and data.config.medic_mode or false,
		pacifist    = data.config and data.config.pacifist_mode or false,
		aggressive  = data.config and data.config.aggressive_mode or false,
		defender    = data.config and data.config.defender_mode or false,
		isPassenger = isPassenger,
		isDriver    = isDriver,
		glideRoot   = glideRoot,
	}
	self.botTickCache[idx] = cached
	return cached
end
function BotManager:GenerateUUID()
	local timePart = string.format("%x", math.floor(SysTime() * 1000000))
	local rand1 = math.random(0, 0xFFFFFFFF)
	local rand2 = math.random(0, 0xFFFFFFFF)
	local rand3 = math.random(0, 0xFFFF)
	local sessionSalt = os.time() .. "_" .. tostring({})
	local uniqueStr = string.format("%s_%x_%x_%x_%s",
		timePart, rand1, rand2, rand3, sessionSalt)
	local crc = util.CRC(uniqueStr)
	return string.format("%08x-%04x-%04x-%04x-%012x",
		bit.band(crc, 0xFFFFFFFF),
		math.random(0, 0xFFFF),
		math.random(0, 0xFFFF),
		math.random(0, 0xFFFF),
		math.random(0, 0xFFFFFFFFFFFF))
end
function BotManager:IsCompanionBot(ent)
	if not ent or not ent:IsValid() or not ent:IsPlayer() then
		return false
	end
	if ent:GetNWBool("IsAICompanion", false) then
		return true
	end
	if ent._aiUUID then
		return true
	end
	if self.botIndex and self.botIndex[ent:EntIndex()] then
		return true
	end
	for uuid, entry in pairs(self.bots or {}) do
		if entry.bot == ent then
			return true
		end
	end
	return false
end
function BotManager:GetUUID(bot)
	if not self.utils or not self.utils:IsValid(bot) then return nil end
	if bot._aiUUID then return bot._aiUUID end
	local uuid = self.botIndex[bot:EntIndex()]
	if uuid and self.bots[uuid] then
		bot._aiUUID = uuid
		return uuid
	end
	for u, entry in pairs(self.bots) do
		if entry.bot == bot then
			bot._aiUUID = u
			self.botIndex[bot:EntIndex()] = u
			return u
		end
	end
	return nil
end
function BotManager:GetData(bot)
	if not bot or not bot:IsValid() or not bot:IsPlayer() then
		return nil
	end
	local uuid = bot._aiUUID
	if uuid and self.bots[uuid] then
		return self.bots[uuid].data
	end
	local entIndex = bot:EntIndex()
	uuid = self.botIndex and self.botIndex[entIndex]
	if uuid and self.bots[uuid] then
		bot._aiUUID = uuid
		return self.bots[uuid].data
	end
	for u, entry in pairs(self.bots or {}) do
		if entry.bot == bot then
			bot._aiUUID = u
			self.botIndex[entIndex] = u
			return entry.data
		end
	end
	return nil
end
function BotManager:GetBotByUUID(uuid)
	if not uuid then return nil end
	local entry = self.bots[uuid]
	if entry and self.utils and self.utils:IsValid(entry.bot) then
		return entry.bot
	end
	return nil
end
function BotManager:GetBotByOwner(owner)
	if not owner or not owner:IsValid() or not owner:IsPlayer() then
		return nil
	end
	local steamID = self:GetSteamID64(owner)
	if not steamID then return nil end
	local uuids = self.ownerIndex[steamID]
	if uuids and #uuids > 0 then
		for _, uuid in ipairs(uuids) do
			if self.bots[uuid] and self.utils:IsValid(self.bots[uuid].bot) then
				return self.bots[uuid].bot
			end
		end
	end
	for u, entry in pairs(self.bots) do
		if entry.data and entry.data.owner == owner then
			if not self.ownerIndex[steamID] then
				self.ownerIndex[steamID] = {}
			end
			table.insert(self.ownerIndex[steamID], u)
			return entry.bot
		end
	end
	return nil
end
function BotManager:GetBotsByOwner(owner)
	if not owner or not owner:IsValid() or not owner:IsPlayer() then
		return {}
	end
	local result = {}
	local steamID = self:GetSteamID64(owner)
	if steamID and self.ownerIndex[steamID] then
		for _, uuid in ipairs(self.ownerIndex[steamID]) do
			if self.bots[uuid] and self.utils:IsValid(self.bots[uuid].bot) then
				table.insert(result, self.bots[uuid].bot)
			end
		end
		return result
	end
	for u, entry in pairs(self.bots) do
		if entry.data and entry.data.owner == owner then
			table.insert(result, entry.bot)
		end
	end
	return result
end
function BotManager:GetAllBots()
	local result = {}
	for u, entry in pairs(self.bots) do
		if self.utils and self.utils:IsValid(entry.bot) then
			table.insert(result, entry.bot)
		end
	end
	return result
end
function BotManager:GetBotCount()
	local count = 0
	for u, entry in pairs(self.bots) do
		if self.utils and self.utils:IsValid(entry.bot) then
			count = count + 1
		end
	end
	return count
end
function BotManager:HasBot(owner)
	if not owner or not owner:IsValid() or not owner:IsPlayer() then
		return false
	end
	return self:GetBotByOwner(owner) ~= nil
end
function BotManager:GetBotCountByOwner(owner)
	if not owner or not owner:IsValid() or not owner:IsPlayer() then
		return 0
	end
	local steamID = self:GetSteamID64(owner)
	if not steamID then return 0 end
	local uuids = self.ownerIndex[steamID]
	if not uuids then return 0 end
	local count = 0
	for _, uuid in ipairs(uuids) do
		if self.bots[uuid] and self.utils:IsValid(self.bots[uuid].bot) then
			count = count + 1
		end
	end
	return count
end
function BotManager:GetSteamID64(ply)
	if not ply or not ply:IsValid() or not ply:IsPlayer() then
		return nil
	end
	return ply:SteamID64()
end
function BotManager:Internal_AddBot(uuid, bot, data)
	if not uuid then
		if self.utils then
		end
		return
	end
	if not bot or not bot:IsValid() then
		if self.utils then
		end
		return
	end
	self.bots[uuid] = { bot = bot, data = data }
	self.botIndex[bot:EntIndex()] = uuid
end
function BotManager:Internal_RemoveBot(uuid)
	local entry = self.bots[uuid]
	if not entry then return end
	if self.utils and self.utils:IsValid(entry.bot) then
		self.botIndex[entry.bot:EntIndex()] = nil
	end
	if entry.data and entry.data.owner and self.utils:IsValid(entry.data.owner) then
		local steamID = self:GetSteamID64(entry.data.owner)
		if steamID and self.ownerIndex[steamID] then
			for i, storedUuid in ipairs(self.ownerIndex[steamID]) do
				if storedUuid == uuid then
					table.remove(self.ownerIndex[steamID], i)
					break
				end
			end
			if #self.ownerIndex[steamID] == 0 then
				self.ownerIndex[steamID] = nil
			end
		end
	end
	self.bots[uuid] = nil
end
function BotManager:CanCreateBot(owner)
	if not owner or not owner:IsValid() or not owner:IsPlayer() then
		return false, self:GetLocalized("error")
	end
	if self:HasBot(owner) then
		return false, self:GetLocalized("bot_already_exists")
	end
	local maxBots = 10
	if self.config and self.config:get("Spawn") then
		maxBots = self.config:get("Spawn").MaxBotsTotal or 10
	end
	if self:GetBotCount() >= maxBots then
		return false, self:GetLocalized("bot_max_reached"):format(maxBots)
	end
	return true, "OK"
end
function BotManager:CreateBot(owner, model, spawnPos, settings)
	if self.utils then
		self.utils.LogInfo("BotManager", self:GetLocalized("log_create_start"), owner:Nick())
		self.utils.LogInfo("BotManager", "  " .. self:GetLocalized("log_bm_model") .. ": %s", tostring(model))
		self.utils.LogInfo("BotManager", "  " .. self:GetLocalized("log_bm_spawnpos") .. ": %s", tostring(spawnPos))
		self.utils.LogInfo("BotManager", "  " .. self:GetLocalized("log_bm_settings") .. ": %s", tostring(settings))
	end
	if not owner or not owner:IsValid() or not owner:IsPlayer() then
		if self.utils then
			self.utils.LogError("BotManager", self:GetLocalized("log_bm_owner_invalid"))
		end
		return nil, self:GetLocalized("error")
	end
	local can, err = self:CanCreateBot(owner)
	if self.utils then
		self.utils.LogInfo("BotManager", self:GetLocalized("log_create_can"), tostring(can), tostring(err))
	end
	if not can then
		return nil, err
	end
	local uuid = self:GenerateUUID()
	if not uuid then
		if self.utils then
			self.utils.LogError("BotManager", self:GetLocalized("log_bm_uuid_fail"))
		end
		return nil, self:GetLocalized("bot_create_failed")
	end
	if self.utils then
		self.utils.LogInfo("BotManager", self:GetLocalized("log_create_uuid"), uuid)
	end
	if not model and settings and settings.model_path then
		model = settings.model_path
		if self.utils then
			self.utils.LogInfo("BotManager", self:GetLocalized("log_create_model"), model)
		end
	end
	if self.utils then
		self.utils.LogInfo("BotManager", self:GetLocalized("log_create_spawn_call"))
	end
	local locator = AICompanion.GetLocator()
	local spawn = locator:get("spawn")
	local bot = spawn:SpawnNewBot(model, spawnPos, owner, uuid)
	if self.utils then
		self.utils.LogInfo("BotManager", self:GetLocalized("log_create_spawn_ret"), tostring(bot))
		if bot then
			self.utils.LogInfo("BotManager", "  bot:IsValid() = %s", tostring(self.utils:IsValid(bot)))
			self.utils.LogInfo("BotManager", "  bot:Nick() = %s", bot:Nick())
			self.utils.LogInfo("BotManager", "  bot:EntIndex() = %d", bot:EntIndex())
			self.utils.LogInfo("BotManager", "  bot._aiUUID = %s", tostring(bot._aiUUID))
		else
			self.utils.LogInfo("BotManager", "  bot = nil!")
		end
	end
	if not bot then
		if self.utils then
			self.utils.LogError("BotManager", self:GetLocalized("log_bm_spawn_nil"))
		end
		return nil, self:GetLocalized("bot_create_failed")
	end
	if not self.utils or not self.utils:IsValid(bot) then
		if self.utils then
			self.utils.LogError("BotManager", self:GetLocalized("log_bm_spawn_invalid"))
		end
		return nil, self:GetLocalized("bot_create_failed")
	end
	if not bot._aiUUID then
		bot._aiUUID = uuid
		if self.utils then
			self.utils.LogInfo("BotManager", self:GetLocalized("log_bm_uuid_set"))
		end
	end
	if self.utils then
		self.utils.LogInfo("BotManager", self:GetLocalized("log_create_data_init"))
		self.utils.LogInfo("BotManager", "  self.data = %s", tostring(self.data))
	end
	local existingData = self:GetData(bot)
	if existingData then
		if self.utils then
			self.utils.LogInfo("BotManager", self:GetLocalized("log_bm_data_existing"))
		end
		existingData.owner = owner
		existingData.uuid = uuid
		existingData.botID = bot:EntIndex()
		self:Internal_AddBot(uuid, bot, existingData)
		self:SyncToNWVars(bot)
	else
		local data = nil
		if self.data then
			if self.utils then
				self.utils.LogInfo("BotManager", self:GetLocalized("log_create_data_call"))
			end
			data = self.data:InitBotData(bot, owner, settings or {})
			if self.utils then
				self.utils.LogInfo("BotManager", self:GetLocalized("log_create_data_ret"), tostring(data))
			end
		else
			if self.utils then
				self.utils.LogError("BotManager", self:GetLocalized("log_bm_data_nil"))
			end
		end
		if not data then
			if self.utils then
				self.utils.LogError("BotManager", self:GetLocalized("log_bm_data_fail"))
			end
			return nil, self:GetLocalized("bot_create_failed")
		end
		data.owner = owner
		data.uuid = uuid
		data.botID = bot:EntIndex()
		if self.utils then
			self.utils.LogInfo("BotManager", self:GetLocalized("log_create_add"))
		end
		self:Internal_AddBot(uuid, bot, data)
		if self.utils then
			self.utils.LogInfo("BotManager", self:GetLocalized("log_create_sync"))
		end
		self:SyncToNWVars(bot)
		if self.utils then
			self.utils.LogInfo("BotManager", self:GetLocalized("log_create_done"))
		end
	end
	if self.state then
		local states = self.state:GetStates()
		self:SetBotState(bot, states and states.FOLLOW or "following")
		if self.utils then
			self.utils.LogInfo("BotManager", self:GetLocalized("log_create_state"))
		end
	end
	if self.utils then
		self.utils.LogInfo("BotManager", self:GetLocalized("log_create_success"),
			uuid, bot:EntIndex(), owner:Nick())
	end
	return bot, nil
end
function BotManager:RegisterExistingBot(bot, owner, settings)
	if not bot or not bot:IsValid() or not bot:IsPlayer() then
		return false, self:GetLocalized("error")
	end
	if not owner or not owner:IsValid() or not owner:IsPlayer() then
		return false, self:GetLocalized("error")
	end
	bot:SetNWBool("IsAICompanion", true)
	bot:SetNWEntity("AICompanionOwnerEnt", owner)
	bot:SetNWString("AICompanionOwner", owner:Nick())
	local uuid = bot._aiUUID
	if not uuid then
		uuid = self:GenerateUUID()
		bot._aiUUID = uuid
	end
	if self:GetData(bot) then
		return false, self:GetLocalized("bot_already_exists")
	end
	local data = self.data and self.data:InitBotData(bot, owner, settings or {})
	if not data then
		return false, self:GetLocalized("bot_create_failed")
	end
	data.owner = owner
	data.uuid = uuid
	data.botID = bot:EntIndex()
	self.bots[uuid] = { bot = bot, data = data }
	self.botIndex[bot:EntIndex()] = uuid
	local steamID = owner:SteamID64()
	if steamID then
		if not self.ownerIndex[steamID] then
			self.ownerIndex[steamID] = {}
		end
		table.insert(self.ownerIndex[steamID], uuid)
	end
	self:SyncToNWVars(bot)
	if self.state then
		local states = self.state:GetStates()
		self:SetBotState(bot, states and states.FOLLOW or "following")
	end
	if self.utils then
	end
	return true, nil
end
function BotManager:RemoveBot(bot, reason, skipMessage)
	if not self.utils or not self.utils:IsValid(bot) then return false end
	if not self:IsCompanionBot(bot) then return false end
	if bot._aiUnregistering then return false end
	bot._aiUnregistering = true
	local uuid = bot._aiUUID
	local entry = uuid and self.bots[uuid]
	local owner = entry and entry.data and entry.data.owner
	local botID = bot:EntIndex()
	local name = bot:Nick() or self:GetLocalized("unknown")
	if self.utils then
		self.utils.LogInfo("BotManager",
			self:GetLocalized("log_remove_start"),
			name,
			reason or self:GetLocalized("unknown"))
	end
	self:CleanupBotTimers(bot)
	self:CleanupServiceCaches(bot)
	if uuid then
		self:Internal_RemoveBot(uuid)
	else
		for u, e in pairs(self.bots) do
			if e.bot == bot then
				self:Internal_RemoveBot(u)
				break
			end
		end
	end
	if self.data then
		self.data:RemoveBotData(bot)
	end
	bot:SetNWBool("IsAICompanion", false)
	bot:SetNWEntity("AICompanionOwnerEnt", NULL)
	bot:SetNWString("AICompanionOwner", "")
	bot:SetNWString("BotState", "")
	bot:SetNWString("CurrentTask", "")
	if not skipMessage then
		local msg = self:GetLocalized("bot_removed"):format(name) .. (reason and " (" .. reason .. ")" or "")
		if self.utils then
			self.utils.LogInfo("BotManager", msg)
		end
		if self.utils and self.utils:IsValid(owner) then
			owner:ChatPrint("[AI] " ..
				self:GetLocalized("bot_removed"):format(name) ..
				(reason and " (" .. reason .. ")" or ""))
		end
	end
	local botRef = bot
	botRef._aiBeingRemoved = true
	timer.Simple(0.1, function()
		if not IsValid(botRef) then return end
		local ok, err = pcall(function()
			if botRef.Kick then
				botRef:Kick(reason or self:GetLocalized("bot_removed"):format(name))
			end
		end)
		timer.Simple(0.5, function()
			if IsValid(botRef) then
				pcall(function()
					if botRef.Remove then
						botRef:Remove()
					end
				end)
			end
			timer.Simple(0.5, function()
				if IsValid(botRef) then
					botRef._aiUnregistering = nil
					botRef._aiBeingRemoved = nil
				end
			end)
		end)
	end)
	return true
end
function BotManager:RemoveAllBots(owner, reason)
	if not self.utils or not self.utils:IsValid(owner) then return 0 end
	local bots = self:GetBotsByOwner(owner)
	local count = 0
	for _, bot in ipairs(bots) do
		if self:RemoveBot(bot, reason or self:GetLocalized("bot_removed"):format(bot:Nick()), true) then
			count = count + 1
		end
	end
	return count
end
function BotManager:SetupCleanupHooks()
	local selfRef = self
	hook.Add("EntityRemoved", "gmod.one/ai-companion/cleanup-caches", function(ent)
		if not IsValid(ent) then return end
		if not ent:IsPlayer() then return end
		if not ent:IsBot() then return end
		if not ent:GetNWBool("IsAICompanion", false) then return end
		selfRef:CleanupServiceCaches(ent)
	end)
end

function BotManager:CleanupServiceCaches(bot)
	if not self.utils or not self.utils:IsValid(bot) then return end
	local idx = bot:EntIndex()
	local locator = AICompanion.GetLocator()
	if not locator then return end

	-- Vehicle
	if locator:has("vehicle") then
		local v = locator:get("vehicle")
		if v then
			if v._tankState then v._tankState[idx] = nil end
			if v._heliWeaponState then v._heliWeaponState[idx] = nil end
			if v._ramState then v._ramState[idx] = nil end
			if v._antiStuck then v._antiStuck[idx] = nil end
			if v._enemyScan then v._enemyScan[idx] = nil end
		end
	end

	-- Combat (кэши на самом боте)
	bot._aiCanSeeCache = nil
	bot._aiMedicWeaponCache = nil
	bot._aiBoneCache = nil
	bot._aiCmd = nil
	bot._aiBotData = nil

	-- Movement
	if locator:has("movement") then
		local m = locator:get("movement")
		if m and m.InvalidateBotCache then
			m:InvalidateBotCache(bot)
		end
	end
end

function BotManager:CleanupBotTimers(bot)
	if not self.utils or not self.utils:IsValid(bot) then return end
	local botID = bot:EntIndex()
	local steamID = bot:SteamID64()
	timer.Remove("AIArmor_" .. botID)
	timer.Remove("AI_TankFire_" .. botID)
	timer.Remove("AI_MedkitSpawn_" .. botID)
	timer.Remove("AI_HeliWeapon_" .. botID)
	timer.Remove("AI_SpawnCleanup_" .. botID)
	timer.Remove("AI_Core_Cleanup_" .. botID)
	timer.Remove("AI_Combat_State_" .. botID)
	timer.Remove("AI_ExitVehicle_" .. botID)
	timer.Remove("AI_Tank_Attack_" .. botID)
	timer.Remove("AI_Heli_Attack_" .. botID)
	timer.Remove("AI_Strafe_Change_" .. botID)
	timer.Remove("AI_Medkit_Check_" .. botID)
	if steamID then
		timer.Remove("tts_timeout_" .. steamID)
		timer.Remove("LLM_timeout_" .. steamID)
		timer.Remove("AI_LLM_Timeout_" .. steamID)
		timer.Remove("AI_TTS_Timeout_" .. steamID)
		timer.Remove("AI_HTTP_Timeout_" .. steamID)
		timer.Remove("AI_Request_Timeout_" .. steamID)
	end
	if bot._aiPendingRequests then
		for _, requestID in ipairs(bot._aiPendingRequests) do
			timer.Remove("LLM_timeout_" .. tostring(requestID))
		end
		bot._aiPendingRequests = nil
	end
	if bot._aiPendingTTS then
		for _, ttsID in ipairs(bot._aiPendingTTS) do
			timer.Remove("TTS_timeout_" .. tostring(ttsID))
		end
		bot._aiPendingTTS = nil
	end
end
function BotManager:Cleanup()
	local removed = 0
	for uuid, entry in pairs(self.bots) do
		local reason = nil
		if not self.utils or not self.utils:IsValid(entry.bot) then
			reason = self:GetLocalized("log_bm_reason_invalid")
		elseif entry.bot:IsBot() and not entry.bot:Alive() then
			reason = self:GetLocalized("bot_died")
		elseif not self:IsCompanionBot(entry.bot) then
			reason = self:GetLocalized("log_bm_reason_not_companion")
		end
		if reason then
			if self.utils then
			end
			self:Internal_RemoveBot(uuid)
			removed = removed + 1
		end
	end
	for _, bot in ipairs(player.GetAll()) do
		if self.utils and self.utils:IsValid(bot) and bot:IsBot() then
			if bot:GetNWBool("IsAICompanion", false) and not bot:Alive() then
				pcall(function() bot:Kick(self:GetLocalized("bot_died")) end)
				removed = removed + 1
			end
		end
	end
	if removed > 0 and self.utils then
		self.utils.LogInfo("BotManager", self:GetLocalized("log_cleanup_dead"), removed)
	end
	return removed
end
function BotManager:SyncToNWVars(bot)
	if not bot or not bot:IsValid() or not bot:IsPlayer() then
		if self.utils then
		end
		return
	end
	if not bot:Alive() or bot._aiBeingRemoved or bot._aiUnregistering then
		if self.utils then
		end
		return
	end
	local data = self:GetData(bot)
	if not data then
		if self.utils then
		end
		return
	end
	bot:SetNWBool("IsAICompanion", true)
	bot:SetNWEntity("AICompanionOwnerEnt", data.owner or NULL)
	bot:SetNWString("AICompanionOwner", data.owner and data.owner:IsValid() and data.owner:Nick() or "")
end
function BotManager:SyncAllBots()
	local bots = self:GetAllBots()
	for _, bot in ipairs(bots) do
		if self.utils and self.utils:IsValid(bot) and bot:Alive() and not bot._aiBeingRemoved then
			self:SyncToNWVars(bot)
		end
	end
end
function BotManager:UpdateData(bot, newData)
	if not self.utils or not self.utils:IsValid(bot) then return false end
	if not bot:Alive() then return false end
	local uuid = bot._aiUUID
	if not uuid then
		uuid = self.botIndex[bot:EntIndex()]
	end
	if not uuid or not self.bots[uuid] then return false end
	local oldData = self.bots[uuid].data
	self.bots[uuid].data = newData
	local oldOwner = oldData and oldData.owner
	local newOwner = newData.owner
	if oldOwner ~= newOwner then
		if oldOwner and self.utils:IsValid(oldOwner) then
			local steamID = self:GetSteamID64(oldOwner)
			if steamID and self.ownerIndex[steamID] then
				for i, storedUuid in ipairs(self.ownerIndex[steamID]) do
					if storedUuid == uuid then
						table.remove(self.ownerIndex[steamID], i)
						break
					end
				end
				if #self.ownerIndex[steamID] == 0 then
					self.ownerIndex[steamID] = nil
				end
			end
		end
		if newOwner and self.utils:IsValid(newOwner) then
			local steamID = self:GetSteamID64(newOwner)
			if steamID then
				if not self.ownerIndex[steamID] then
					self.ownerIndex[steamID] = {}
				end
				table.insert(self.ownerIndex[steamID], uuid)
			end
		end
	end
	self:SyncToNWVars(bot)
	return true
end
function BotManager:GetBotState(bot)
	if not self.utils or not self.utils:IsValid(bot) then return "idle" end
	if not bot:Alive() then return "dead" end
	local data = self:GetData(bot)
	if data and data.state then
		return data.state
	end
	return bot:GetNWString("BotState", "idle")
end
function BotManager:SetBotState(bot, newState)
	if not self.utils or not self.utils:IsValid(bot) then return false end
	if not bot:Alive() then return false end
	local data = self:GetData(bot)
	if not data then return false end
	data.state = newState
	data.task = newState
	self:UpdateData(bot, data)
	self:SyncToNWVars(bot)
	return true
end
function BotManager:MigrateFromLegacy()
	local migrated = 0
	local errors = 0
	local registry = debug.getregistry()
	local storage = registry["__AI_COMPANION_STORAGE_v2"]
	if not storage or not storage.Companion then
		return 0, 0
	end
	local oldData = storage.Companion
	local sources = {}
	if oldData.BotData then
		for id, data in pairs(oldData.BotData) do
			local bot = Entity(id)
			if self.utils and self.utils:IsValid(bot) and self:IsCompanionBot(bot) then
				table.insert(sources, { bot = bot, data = data, source = "BotData" })
			end
		end
	end
	if oldData.RegisteredBots then
		for id, bot in pairs(oldData.RegisteredBots) do
			if self.utils and self.utils:IsValid(bot) and self:IsCompanionBot(bot) then
				local data = self:GetData(bot)
				if data then
					table.insert(sources, { bot = bot, data = data, source = "RegisteredBots" })
				end
			end
		end
	end
	if oldData.OwnerToBot then
		for owner, bot in pairs(oldData.OwnerToBot) do
			if self.utils and self.utils:IsValid(bot) and self:IsCompanionBot(bot) and self.utils:IsValid(owner) then
				local data = self:GetData(bot)
				if not data and self.data then
					data = self.data:InitBotData(bot, owner, {})
				end
				if data then
					data.owner = owner
					table.insert(sources, { bot = bot, data = data, source = "OwnerToBot" })
				end
			end
		end
	end
	for _, entry in ipairs(sources) do
		local bot = entry.bot
		local data = entry.data
		local existingUuid = self:GetUUID(bot)
		if existingUuid then
			if data and data.owner and self.utils:IsValid(data.owner) then
				data._nw_cache = data._nw_cache or {}
				data._nw_cache.owner_name = data.owner:Nick()
				data._nw_cache.is_ai_companion = true
			end
			self.bots[existingUuid].data = data
			migrated = migrated + 1
		else
			local uuid = self:GenerateUUID()
			if not uuid then
				errors = errors + 1
			else
				bot._aiUUID = uuid
				if data and not self.utils:IsValid(data.owner) then
					data.owner = bot:GetNWEntity("AICompanionOwnerEnt")
					if self.utils and self.utils:IsValid(data.owner) then
						data._nw_cache = data._nw_cache or {}
						data._nw_cache.owner_name = data.owner:Nick()
					end
				end
				self:Internal_AddBot(uuid, bot, data)
				migrated = migrated + 1
			end
		end
	end
	if migrated > 0 then
		if oldData.BotData then
			for k in pairs(oldData.BotData) do oldData.BotData[k] = nil end
		end
		if oldData.RegisteredBots then
			for k in pairs(oldData.RegisteredBots) do oldData.RegisteredBots[k] = nil end
		end
		if oldData.OwnerToBot then
			for k in pairs(oldData.OwnerToBot) do oldData.OwnerToBot[k] = nil end
		end
		if oldData.BotOwners then
			for k in pairs(oldData.BotOwners) do oldData.BotOwners[k] = nil end
		end
	end
	if migrated > 0 or errors > 0 then
		if self.utils then
			self.utils.LogInfo("BotManager", self:GetLocalized("log_migration_done"), migrated, errors)
		end
	end
	return migrated, errors
end
function BotManager:GetStats()
	local stats = {
		totalBots = self:GetBotCount(),
		totalOwners = 0,
		botsPerOwner = {},
		uuidCount = table.Count(self.bots),
		indexCount = table.Count(self.botIndex),
	}
	for steamID, uuids in pairs(self.ownerIndex) do
		stats.totalOwners = stats.totalOwners + 1
		stats.botsPerOwner[steamID] = #uuids
	end
	return stats
end
function BotManager:DebugPrint()
	if not self.utils then return end
	local count = 0
	for uuid, entry in pairs(self.bots) do
		if self.utils and self.utils:IsValid(entry.bot) then
			count = count + 1
			local bot = entry.bot
			local data = entry.data
			local owner = data and data.owner
			if data and data.combat and data.combat.target then
			end
		else
		end
	end
end
if SERVER then
	concommand.Add("ai_companion_botmanager_debug", function(ply)
		local locator = AICompanion.GetLocator()
		local bm = locator and locator:has("botmanager") and locator:get("botmanager")
		local locale = bm and function(key, ...) return bm:GetLocalized(key, ...) end or function(key) return key end
		if IsValid(ply) and not ply:IsAdmin() then
			ply:ChatPrint("[AI] " .. locale("settings_admin_only"))
			return
		end
		if bm then
			-- print гарантированно работает даже если LogDebug недоступен
			print("[AI] ========== BOT MANAGER DEBUG ==========")
			print("[AI] Total bots: " .. bm:GetBotCount())
			print("[AI] Total owners: " .. table.Count(bm.ownerIndex or {}))
			for uuid, entry in pairs(bm.bots or {}) do
				local bot = entry.bot
				local data = entry.data
				local owner = data and data.owner
				local ownerName = (IsValid(owner) and owner.Nick) and owner:Nick() or "none"
				local botName = (IsValid(bot) and bot.Nick) and bot:Nick() or "INVALID"
				local botState = data and data.state or "?"
				print("[AI]   [" .. uuid .. "] " .. botName .. " | Owner: " .. ownerName .. " | State: " .. botState)
			end
			print("[AI] ========== END DEBUG ==========")
			-- Также вызываем оригинальный DebugPrint для детального вывода
			bm:DebugPrint()
		else
			print("[AI] BotManager not found!")
		end
		if IsValid(ply) then
			ply:ChatPrint("[AI] " .. locale("status_console"))
		end
	end)
	concommand.Add("ai_botmanager_cleanup", function(ply)
		local locator = AICompanion.GetLocator()
		local bm = locator and locator:has("botmanager") and locator:get("botmanager")
		-- Исправлено: вызываем через bm:, а не как "голую" функцию
		local locale = bm and function(key, ...) return bm:GetLocalized(key, ...) end or function(key) return key end
		if IsValid(ply) and not ply:IsAdmin() then
			ply:ChatPrint("[AI] " .. locale("settings_admin_only"))
			return
		end
		if bm then
			local removed = bm:Cleanup()
			if bm.utils then
				bm.utils.LogInfo("BotManager", locale("log_cleanup_dead"), removed)
			end
			if IsValid(ply) then
				ply:ChatPrint("[AI] " .. locale("log_cleanup_dead"):format(removed))
			end
		else
			if bm and bm.utils then
				bm.utils:LogDebug("[AI] BotManager не найден!")
			end
		end
	end)
end
function BotManager:GetOwner(bot)
	if not self.utils or not self.utils:IsValid(bot) then return nil end
	if not self:IsCompanionBot(bot) then return nil end
	local data = self:GetData(bot)
	if data and self.utils:IsValid(data.owner) then
		return data.owner
	end
	local owner = bot:GetNWEntity("AICompanionOwnerEnt")
	if self.utils:IsValid(owner) then
		return owner
	end
	return nil
end
return BotManager