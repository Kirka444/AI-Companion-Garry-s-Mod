local Spawn = {}
function Spawn:new(utils, config, state, data, botmanager)
	local obj = {
		utils = utils,
		config = config,
		state = state,
		data = data,
		botmanager = botmanager,
		_initialized = false,
		FALLBACK_WEAPONS = {
			idle = "weapon_physgun",
			combat = "weapon_smg1",
			melee = "weapon_crowbar",
			medkit = "weapon_medkit",
			rpg = "weapon_rpg",
			frag = "weapon_frag"
		},
		AVAILABLE_MODELS = {
			"models/player/combine_soldier.mdl",
			"models/player/alyx.mdl",
			"models/player/barney.mdl",
			"models/player/kleiner.mdl",
			"models/player/mossman.mdl",
			"models/player/p2_chell.mdl",
			"models/player/urban.mdl"
		},
	}
	setmetatable(obj, self)
	self.__index = self
	return obj
end
function Spawn:GetLocalized(key, ...)
	local locator = AICompanion.GetLocator()
	if locator and locator:has("locale") then
		local locale = locator:get("locale")
		if locale and locale.Get then
			return locale:Get(key, ...)
		end
	end
	return key
end
function Spawn:init()
	if self._initialized then return end
	if SERVER then
		self:SetupHooks()
		self:SetupNetMessages()
	end
	self._initialized = true
	if self.utils then
		self.utils.LogInfo("Spawn", self:GetLocalized("log_spawn_init"))
	end
end
function Spawn:SetupNetMessages()
	if not SERVER then return end
	util.AddNetworkString("gmod.one/ai-companion/owner-sync")
	util.AddNetworkString("gmod.one/ai-companion/color-sync")
end
function Spawn:IsValidModelPath(path)
	if not path or path == "" then return false end
	if string.find(path, "%.%.") then return false end
	if string.find(path, "\\") then return false end
	if not string.match(path, "%.mdl$") then return false end
	local ok, exists = pcall(util.IsValidModel, path)
	if not ok then
		ErrorNoHaltWithStack("[Spawn] Ошибка проверки модели " .. tostring(path) .. ": " .. tostring(exists) .. "\n")
		return false
	end
	return exists
end
function Spawn:FindSafeSpawnPos(ply)
	if not self.utils or not self.utils:IsValid(ply) then
		return Vector(0, 0, 100)
	end
	local start = ply:GetPos() + ply:GetForward() * 80
	local tr = util.TraceLine({
		start = start + Vector(0, 0, 100),
		endpos = start - Vector(0, 0, 200),
		filter = ply
	})
	if tr.Hit then
		local ground = tr.HitPos + Vector(0, 0, 5)
		local hull = util.TraceHull({
			start = ground + Vector(0, 0, 36),
			endpos = ground + Vector(0, 0, 36),
			mins = Vector(-16, -16, 0),
			maxs = Vector(16, 16, 72),
			filter = ply
		})
		if not hull.Hit then
			return ground
		end
	end
	return start + Vector(0, 0, 5)
end
function Spawn:ForceStandUp(bot)
	if not self.utils or not self.utils:IsValid(bot) then return end
	bot:RemoveFlags(FL_DUCKING)
	bot:RemoveFlags(FL_ANIMDUCKING)
	bot:ConCommand("-duck")
end
function Spawn:SafeGiveWeapon(bot, wepName, fallback)
	if not self.utils or not self.utils:IsValid(bot) then
		return false, nil
	end
	if not wepName or wepName == "" then
		wepName = fallback
		if not wepName or wepName == "" then
			return false, nil
		end
	end
	if not bot:HasWeapon(wepName) then
		bot:Give(wepName)
	end
	return true, wepName
end
function Spawn:GetWeaponWithFallback(settings, settingKey, fallback)
	local wep = settings and settings[settingKey]
	if wep and wep ~= "" then
		return wep
	end
	return fallback
end
function Spawn:SyncBotColors(bot, owner)
	if not self.utils or not self.utils:IsValid(bot) then return end
	if not self.utils:IsValid(owner) then return end
	pcall(function()
		local weaponColor = owner:GetWeaponColor()
		if bot.SetWeaponColor then
			bot:SetWeaponColor(weaponColor)
		end
	end)
	pcall(function()
		local playerColor = owner:GetPlayerColor()
		if bot.SetPlayerColor then
			bot:SetPlayerColor(playerColor)
			bot:SetNWVector("PlayerColor", playerColor)
		end
	end)
	if SERVER then
		net.Start("gmod.one/ai-companion/owner-sync")
		net.WriteEntity(bot)
		net.WriteEntity(owner)
		net.Broadcast()
		net.Start("gmod.one/ai-companion/color-sync")
		net.WriteEntity(bot)
		net.WriteVector(owner:GetWeaponColor() or Vector(1, 1, 1))
		net.Broadcast()
	end
	if self.utils then
		self.utils.LogDebug("Spawn", self:GetLocalized("log_spawn_sync"), bot:Nick(), owner:Nick())
	end
end
function Spawn:GetBotSettingsFromState(owner)
	local settings = {}
	if not self.state then return settings end
	local steamID = owner and owner:IsValid() and owner:SteamID64() or nil
	local function getSetting(key, default)
		local val
		if steamID then
			val = self.state:getPlayerSetting(steamID, key)
		end
		if val == nil then
			val = self.state:getSetting(key)
		end
		if val == nil then
			val = default
		end
		return val
	end
	settings.companion_nick = getSetting("Companion_Nick", "AI_Companion")
	settings.model_path = getSetting("Model_Path", "models/player/urban.mdl")
	settings.combat_weapon = getSetting("Combat_Weapon", "weapon_smg1")
	settings.melee_weapon = getSetting("Melee_Weapon", "weapon_crowbar")
	settings.idle_weapon = getSetting("Idle_Weapon", "weapon_physgun")
	settings.stealth_mode = getSetting("Stealth_Mode", false)
	settings.defender_mode = getSetting("Defender_Mode", false)
	settings.medic_mode = getSetting("Medic_Mode", false)
	settings.pacifist_mode = getSetting("Pacifist_Mode", false)
	settings.aggressive_mode = getSetting("Aggressive_Mode", false)
	settings.show_sender_name = getSetting("Show_Sender_Name", true)
	if self.utils then
		self.utils.LogInfo("Spawn", self:GetLocalized("log_spawn_settings_state"),
			settings.companion_nick or self:GetLocalized("unknown"),
			settings.model_path or self:GetLocalized("unknown"))
	end
	return settings
end
function Spawn:SpawnNewBot(model, spawnPos, owner, uuid)
	if self.utils then
	end
	if game.SinglePlayer() then
		if self.utils then
		end
		return nil
	end
	if not owner or not owner:IsValid() or not owner:IsPlayer() then
		if self.utils then
			self.utils.LogWarn("Spawn", self:GetLocalized("log_spawn_new_owner_invalid"))
		end
		return nil
	end
	local settings = self:GetBotSettingsFromState(owner)
	if not settings.companion_nick then
		if self.data and self.data.GetBotConfig then
			local data = self.data:GetBotData(owner)
			if data and data.config then
				for k, v in pairs(data.config) do
					if settings[k] == nil then
						settings[k] = v
					end
				end
				if self.utils then
					self.utils.LogInfo("Spawn", self:GetLocalized("log_spawn_new_settings_supplement"))
				end
			end
		end
	end
	local botNick = settings.companion_nick or "AI_Companion"
	local originalNick = botNick
	local suffix = 1
	local function IsNameTaken(name)
		for _, p in ipairs(player.GetAll()) do
			if self.utils and self.utils:IsValid(p) and not p:IsBot() and p:Nick() == name then
				return true
			end
		end
		return false
	end
	while IsNameTaken(botNick) do
		botNick = originalNick .. "_" .. suffix
		suffix = suffix + 1
	end
	if self.utils then
		self.utils.LogInfo("Spawn", self:GetLocalized("log_spawn_new_name"), botNick)
	end
	if self.utils then
	end
	local bot = player.CreateNextBot(botNick)
	if self.utils then
	end
	if not bot then
		if self.utils and self.utils:IsValid(owner) then
			owner:ChatPrint("[AI] " .. self:GetLocalized("bot_create_failed"))
		end
		if self.utils then
			self.utils.LogError("Spawn", self:GetLocalized("log_spawn_new_error"))
		end
		return nil
	end
	timer.Simple(0.1, function()
		if self.utils and self.utils:IsValid(bot) then
			self.utils.LogInfo("Spawn", self:GetLocalized("log_spawn_new_init_ok"), bot:Nick())
		end
	end)
	if self.utils then
		self.utils.LogInfo("Spawn", self:GetLocalized("log_spawn_new_model_call"))
	end
	local modelToUse = settings.model_path
	local modelMissing = not modelToUse or modelToUse == ""
	if modelMissing and model and model ~= "" then
		modelToUse = model
	end
	if not modelToUse or modelToUse == "" then
		modelToUse = "models/player/urban.mdl"
	end
	if self:IsValidModelPath(modelToUse) then
		bot:SetModel(modelToUse)
		if self.utils then
			self.utils.LogInfo("Spawn", self:GetLocalized("log_spawn_new_model_ok"), modelToUse)
		end
	else
		bot:SetModel("models/player/urban.mdl")
		if self.utils then
			self.utils.LogInfo("Spawn", self:GetLocalized("log_spawn_new_model_fallback"))
		end
	end
	if uuid and uuid ~= "" then
		bot._aiUUID = uuid
		if self.utils then
			self.utils.LogInfo("Spawn", self:GetLocalized("log_spawn_new_uuid"), uuid)
		end
	end
	bot._aiUnregisterDone = false
	bot._aiCleanupDone = false
	bot._aiBeingRemoved = false
	bot:SetName(botNick)
	if self.utils then
		self.utils.LogInfo("Spawn", self:GetLocalized("log_spawn_new_name_set"), botNick)
	end
	if spawnPos then
		bot:SetPos(spawnPos)
		if self.utils then
			self.utils.LogInfo("Spawn", self:GetLocalized("log_spawn_new_pos_set"), tostring(spawnPos))
		end
	else
		local safePos = self:FindSafeSpawnPos(owner or bot)
		bot:SetPos(safePos)
		if self.utils then
			self.utils.LogInfo("Spawn", self:GetLocalized("log_spawn_new_pos_calc"), tostring(safePos))
		end
	end
	bot:RemoveFlags(FL_DUCKING)
	bot:RemoveFlags(FL_ANIMDUCKING)
	bot:ConCommand("-duck")
	bot._aiSpawnTime = CurTime()
	local graceDuration = 10
	if self.config and self.config:get("Spawn") then
		graceDuration = self.config:get("Spawn").SpawnGraceDuration or 10
	end
	bot._aiSpawnNoCrouchUntil = CurTime() + graceDuration
	self:SyncBotColors(bot, owner)
	bot:SetNWBool("IsAICompanion", true)
	bot:SetNWEntity("AICompanionOwnerEnt", owner)
	bot:SetNWString("AICompanionOwner", owner:Nick())
	bot:SetNWString("BotState", "following")
	if self.utils then
		self.utils.LogInfo("Spawn", self:GetLocalized("log_spawn_new_nwvars"), bot:Nick())
		self.utils.LogInfo("Spawn", self:GetLocalized("log_spawn_new_success"))
		self.utils.LogInfo("Spawn", "  " .. self:GetLocalized("log_spawn_new_name_out"):format(bot:Nick()))
		self.utils.LogInfo("Spawn", "  " .. self:GetLocalized("log_spawn_new_id"):format(bot:EntIndex()))
		self.utils.LogInfo("Spawn",
			"  " .. self:GetLocalized("log_spawn_new_uuid_out"):format(bot._aiUUID or self:GetLocalized("unknown")))
		self.utils.LogInfo("Spawn", "  " .. self:GetLocalized("log_spawn_new_model_out"):format(modelToUse))
	end
	self:ScheduleWeaponGive(bot, settings)
	return bot
end
function Spawn:ScheduleWeaponGive(bot, settings)
	if not self.utils or not self.utils:IsValid(bot) then return end
	local weapons = self.FALLBACK_WEAPONS
	local combatWep = self:GetWeaponWithFallback(settings, "combat_weapon", weapons.combat) or "weapon_smg1"
	local meleeWep = self:GetWeaponWithFallback(settings, "melee_weapon", weapons.melee) or "weapon_crowbar"
	local idleWep = self:GetWeaponWithFallback(settings, "idle_weapon", weapons.idle) or "weapon_physgun"
	if not idleWep or idleWep == "" then idleWep = weapons.idle end
	if not combatWep or combatWep == "" then combatWep = weapons.combat end
	if not meleeWep or meleeWep == "" then meleeWep = weapons.melee end
	local botRef = bot
	timer.Simple(0.01, function()
		if not self.utils or not self.utils:IsValid(botRef) then return end
		pcall(function()
			botRef:StripWeapons()
			botRef:Give(idleWep)
			botRef:SelectWeapon(idleWep)
		end)
	end)
	timer.Simple(0.05, function()
		if not self.utils or not self.utils:IsValid(botRef) then return end
		pcall(function()
			self:SafeGiveWeapon(botRef, combatWep, weapons.combat)
			local wep = botRef:GetWeapon(combatWep)
			if self.utils:IsValid(wep) then
				local ammoType = wep:GetPrimaryAmmoType()
				if ammoType and ammoType ~= -1 then
					botRef:GiveAmmo(120, ammoType, true)
				end
				if self.config and self.config:get("INFINITE_AMMO") then
					wep:SetClip1(wep:GetMaxClip1() or 30)
				end
			end
			self:SafeGiveWeapon(botRef, meleeWep, weapons.melee)
			self:SafeGiveWeapon(botRef, "weapon_frag", weapons.frag)
			self:SafeGiveWeapon(botRef, "weapon_rpg", weapons.rpg)
			self:SafeGiveWeapon(botRef, "weapon_medkit", weapons.medkit)
			self:SafeGiveWeapon(botRef, idleWep, weapons.idle)
			botRef:SelectWeapon(idleWep)
		end)
	end)
	local timerName = "AI_ForceStand_" .. botRef:EntIndex()
	if timer.Exists(timerName) then
		timer.Remove(timerName)
	end
	local forceStandIterations = 200
	if self.config and self.config:get("Spawn") then
		forceStandIterations = self.config:get("Spawn").ForceStandIterations or 200
	end
	botRef._aiForceStandUntil = CurTime() + forceStandIterations * 0.05
	for i = 1, 6 do
		timer.Simple(0.15 + i * 0.2, function()
			if not self.utils or not self.utils:IsValid(botRef) then return end
			local botState = botRef:GetNWString("BotState", "idle")
			if botState == "combat" then return end
			local activeWep = botRef:GetActiveWeapon()
			local activeClass = self.utils:IsValid(activeWep) and activeWep:GetClass() or "none"
			if activeClass ~= idleWep then
				if botRef:HasWeapon(idleWep) then
					botRef:SelectWeapon(idleWep)
				end
			end
		end)
	end
end
function Spawn:CreateAICompanion(modelName, spawnPos, owner)
	if self.utils then
	end
	if game.SinglePlayer() then
		if self.utils and self.utils:IsValid(owner) then
			owner:ChatPrint("[AI] " .. self:GetLocalized("bot_solo_mode"))
		end
		return nil
	end
	if not owner or not owner:IsValid() or not owner:IsPlayer() then
		if self.utils then
			self.utils.LogWarn("Spawn", "Попытка создать бота без владельца")
		end
		return nil
	end
	if self.utils then
	end
	local settings = self:GetBotSettingsFromState(owner)
	local uuid = string.format("%08x-%04x-%04x-%04x-%012x",
		bit.band(util.CRC("bot_" .. os.time() .. "_" .. math.random(1, 9999999)), 0xFFFFFFFF),
		math.random(0, 0xFFFF),
		math.random(0, 0xFFFF),
		math.random(0, 0xFFFF),
		math.random(0, 0xFFFFFFFFFFFF))
	if self.utils then
	end
	local bot = self:SpawnNewBot(modelName, spawnPos, owner, uuid)
	if self.utils then
	end
	if not bot then
		if self.utils then
		end
		if self.utils and self.utils:IsValid(owner) then
			owner:ChatPrint("[AI] " .. self:GetLocalized("bot_create_failed"))
		end
		return nil
	end
	if self.utils then
	end
	if self.botmanager then
		if self.utils then
		end
		local success, err = self.botmanager:RegisterExistingBot(bot, owner, settings)
		if success then
			if self.utils then
			end
		else
			if self.utils then
			end
		end
	else
		if self.utils then
		end
	end
	if self.utils then
		self.utils.LogInfo("Spawn", self:GetLocalized("log_spawn_create_bot_created"), bot:Nick())
	end
	if self.utils then
	end
	return bot
end
function Spawn:RemoveAICompanion(bot, reason, skipMessage)
	if not self.utils or not self.utils:IsValid(bot) then
		return false
	end
	if self.botmanager then
		return self.botmanager:RemoveBot(bot, reason or self:GetLocalized("bot_removed"), skipMessage)
	end
	return false
end
function Spawn:SetupHooks()
	if not SERVER then return end
	hook.Add("CalcMainActivity", "gmod.one/ai-companion/anim-fix", function(ply, velocity)
		if not self.utils or not self.utils:IsValid(ply) then return end
		if not ply:IsBot() then return end
		local isCompanion = ply:GetNWBool("IsAICompanion", false)
		if not isCompanion then return end
		local cmd = ply:GetCurrentCommand()
		if cmd and (cmd:GetForwardMove() ~= 0 or cmd:GetSideMove() ~= 0) then
			return
		end
		local speed = velocity:Length2D()
		if speed > 200 then
			return ACT_MP_RUN, -1
		elseif speed > 10 then
			return ACT_MP_WALK, -1
		else
			return ACT_MP_STAND_IDLE, -1
		end
	end)
	hook.Add("PlayerInitialSpawn", "gmod.one/ai-companion/register-bot", function(ply)
		if not self.utils or not self.utils:IsValid(ply) then return end
		if not ply:IsBot() then return end
		local isCompanion = ply:GetNWBool("IsAICompanion", false)
		if not isCompanion and self.botmanager then
			local data = self.botmanager:GetData(ply)
			if data then
				ply:SetNWBool("IsAICompanion", true)
				ply:SetNWEntity("AICompanionOwnerEnt", data.owner)
				ply:SetNWString("AICompanionOwner", data.owner and data.owner:Nick() or "")
				isCompanion = true
				if self.utils then
				end
			end
		end
		if isCompanion then
			if self.botmanager and not self.botmanager:GetData(ply) then
				local owner = ply:GetNWEntity("AICompanionOwnerEnt")
				if self.utils and self.utils:IsValid(owner) then
					local settings = self:GetBotSettingsFromState(owner)
					if self.data then
						local data = self.data:InitBotData(ply, owner, settings)
						if data and self.botmanager then
							self.botmanager:UpdateData(ply, data)
						end
					end
				end
			end
			local graceDuration = 10
			if self.config and self.config:get("Spawn") then
				graceDuration = self.config:get("Spawn").SpawnGraceDuration or 10
			end
			ply._aiSpawnNoCrouchUntil = CurTime() + graceDuration
			ply:RemoveFlags(FL_DUCKING)
			ply:RemoveFlags(FL_ANIMDUCKING)
			ply:ConCommand("-duck")
		end
	end)
	hook.Add("PlayerInitialSpawn", "gmod.one/ai-companion/armor-fix", function(ply)
		if not self.utils or not self.utils:IsValid(ply) then return end
		if not ply:IsBot() then return end
		local botID = ply:EntIndex()
		timer.Simple(0.5, function()
			if not self.utils or not self.utils:IsValid(ply) then return end
			local isCompanion = ply:GetNWBool("IsAICompanion", false)
			local hasOwner = false
			if self.botmanager then
				local data = self.botmanager:GetData(ply)
				if data and self.utils and self.utils:IsValid(data.owner) then
					hasOwner = true
				end
			end
			if not isCompanion and not hasOwner then return end
			local maxArmor = 100
			if self.config and self.config:get("Spawn") then
				maxArmor = self.config:get("Spawn").MaxArmor or 100
			end
			ply:SetMaxArmor(maxArmor)
			ply:SetArmor(maxArmor)
			local tname = "AIArmor_" .. botID
			timer.Create(tname, 0.1, 30, function()
				if not self.utils or not self.utils:IsValid(ply) then
					timer.Remove(tname)
					return
				end
				if ply:Armor() < maxArmor then
					ply:SetArmor(maxArmor)
				else
					timer.Remove(tname)
				end
			end)
		end)
	end)
	hook.Add("PlayerDisconnected", "gmod.one/ai-companion/remove-owner-bots", function(ply)
		if not self.utils or not self.utils:IsValid(ply) then return end
		if ply:IsBot() then return end
		if self.botmanager then
			local bot = self.botmanager:GetBotByOwner(ply)
			if bot and self.utils:IsValid(bot) then
				if self.utils then
					self.utils.LogInfo("Spawn", self:GetLocalized("log_spawn_owner_disconnect"), ply:Nick(), bot:Nick())
				end
				self.botmanager:RemoveBot(bot, self:GetLocalized("reason_removed_by_player"), false)
			end
		end
	end)
end
return Spawn