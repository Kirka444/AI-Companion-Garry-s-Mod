local LLMRemember = {}
local NPC_NAMES = {
	npc_zombie = "зомби",
	npc_fastzombie = "быстрый зомби",
	npc_poisonzombie = "ядовитый зомби",
	npc_zombine = "зомбайн",
	npc_headcrab = "хедкраб",
	npc_headcrab_fast = "быстрый хедкраб",
	npc_headcrab_poison = "ядовитый хедкраб",
	npc_headcrab_black = "ядовитый хедкраб",
	npc_antlion = "антлион",
	npc_antlionguard = "страж антлионов",
	npc_antlion_worker = "антлион-рабочий",
	npc_combine_s = "комбайн-солдат",
	npc_metropolice = "полицейский Альянса",
	npc_manhack = "менхэк",
	npc_rollermine = "роллермина",
	npc_hunter = "охотник",
	npc_strider = "страйдер",
	npc_helicopter = "вертолёт Альянса",
	npc_combinegunship = "ганшип Альянса",
	npc_vortigaunt = "вортигонт",
	npc_citizen = "гражданин",
	npc_refugee = "беженец",
	npc_stalker = "сталкер",
	npc_barnacle = "барнакл",
	npc_turret_floor = "напольная турель",
	npc_turret_ceiling = "потолочная турель",
	npc_sniper = "снайпер",
	npc_alyx = "Аликс",
	npc_barney = "Барни",
	npc_dog = "Дог",
	npc_gman = "G-Man",
	npc_monk = "монах",
	npc_kleiner = "Кляйнер",
	npc_eli = "Илай",
	npc_mossman = "Моссман",
	npc_breen = "Брин",
	npc_fisherman = "рыбак",
	npc_skeleton = "скелет",
	npc_ichthyosaur = "ихтиозавр",
	npc_crow = "ворона",
	npc_pigeon = "голубь",
	npc_seagull = "чайка",
}
function LLMRemember:new(utils, config, state, llm, shared)
	local obj = {
		utils = utils,
		config = config,
		state = state,
		llm = llm,
		shared = shared,
		_initialized = false,
		_savePath = "ai_companion_data/ai_companion_remember.txt",
		_data = {
			enabled = true,
			players = {}
		},
		_dirty = false
	}
	setmetatable(obj, self)
	self.__index = self
	return obj
end
function LLMRemember:GetLocalized(key, ...)
	local locator = AICompanion.GetLocator()
	if locator and locator:has("locale") then
		local locale = locator:get("locale")
		if locale and locale.Get then
			return locale:Get(key, ...)
		end
	end
	return key
end
function LLMRemember:init()
	if self._initialized then return end
	if SERVER then
		if not file.Exists("ai_companion_data", "DATA") then
			file.CreateDir("ai_companion_data")
		end
		self:LoadFromFile()
		self:SetupNetReceivers()
		self:SetupHooks()
		timer.Create("gmod.one/ai-companion/remember-autosave", 60, 0, function()
			if self._dirty then
				self:SaveToFile()
			end
		end)
	end
	self._initialized = true
	if self.utils then
		self.utils.LogInfo("[LLMRemember]", self:GetLocalized("log_remember_init"))
	end
end
function LLMRemember:SanitizeString(str)
	if not str or type(str) ~= "string" then return "" end
	str = string.gsub(str, "\r\n", " ")
	str = string.gsub(str, "\n", " ")
	str = string.gsub(str, "\r", " ")
	str = string.gsub(str, "\t", " ")
	str = string.gsub(str, "%s+", " ")
	str = string.Trim(str)
	if #str > 500 then
		str = string.sub(str, 1, 500)
	end
	return str
end
function LLMRemember:GetSafePlayerName(ply)
	if not ply or not self.utils:IsValid(ply) then return "Unknown" end
	local name = ply:Nick()
	if not name or name == "" then
		name = "Player_" .. ply:EntIndex()
	end
	name = self:SanitizeString(name)
	if #name > 32 then
		name = string.sub(name, 1, 32)
	end
	return name
end
function LLMRemember:LoadFromFile()
	if not file.Exists(self._savePath, "DATA") then
		if self.utils then
			self.utils.LogInfo("[LLMRemember]", self:GetLocalized("log_remember_file_missing"))
		end
		self._data = { enabled = true, players = {} }
		self:SaveToFile()
		return
	end
	local json = file.Read(self._savePath, "DATA")
	if not json or json == "" then
		if self.utils then
			self.utils.LogInfo("[LLMRemember]", self:GetLocalized("log_remember_file_empty"))
		end
		self._data = { enabled = true, players = {} }
		return
	end
	local ok, data = pcall(util.JSONToTable, json)
	if not ok then
		ErrorNoHaltWithStack("[LLMRemember] Ошибка парсинга JSON: " .. tostring(data) .. "\n")
		if self.utils then
			self.utils.LogInfo("[LLMRemember]", self:GetLocalized("log_remember_parse_error"), tostring(data))
		end
		self._data = { enabled = true, players = {} }
		return
	end
	if not data or type(data) ~= "table" then
		if self.utils then
			self.utils.LogInfo("[LLMRemember]", self:GetLocalized("log_remember_format_error"))
		end
		self._data = { enabled = true, players = {} }
		return
	end
	self._data = data
	if not self._data.players then
		self._data.players = {}
	end
	if self.utils then
		self.utils.LogInfo("[LLMRemember]", self:GetLocalized("log_remember_loaded"), table.Count(self._data.players))
	end
	if self.state then
		local settings = self.state:getRaw("Settings")
		if settings then
			settings["Memory_Enabled"] = self._data.enabled
		end
	end
end
function LLMRemember:SaveToFile()
	if not SERVER then return end
	local json = util.TableToJSON(self._data, false)
	if not json then
		if self.utils then
			self.utils.LogInfo("[LLMRemember]", self:GetLocalized("log_remember_serialize_error"))
		end
		return
	end
	file.Write(self._savePath, json)
	self._dirty = false
	if self.utils then
		self.utils.LogInfo("[LLMRemember]", self:GetLocalized("log_remember_saved"), #json)
	end
end
function LLMRemember:MarkDirty()
	self._dirty = true
end
function LLMRemember:IsEnabled()
	if self.state then
		return self.state:getSetting("Memory_Enabled", true)
	end
	return self._data.enabled
end
function LLMRemember:AddMessage(playerName, role, text)
	if not self:IsEnabled() then return end
	playerName = self:SanitizeString(playerName)
	if playerName == "" then
		playerName = "Unknown"
	end
	if not self._data.players[playerName] then
		self._data.players[playerName] = { messages = {}, events = {} }
	end
	local pData = self._data.players[playerName]
	local sanitizedText = self:SanitizeString(text)
	table.insert(pData.messages, {
		role = role,
		text = sanitizedText,
		time = os.time()
	})
	local playerMsgs = {}
	local botMsgs = {}
	for _, msg in ipairs(pData.messages) do
		if msg.role == "player" then
			table.insert(playerMsgs, msg)
		else
			table.insert(botMsgs, msg)
		end
	end
	while #playerMsgs > 5 do table.remove(playerMsgs, 1) end
	while #botMsgs > 5 do table.remove(botMsgs, 1) end
	pData.messages = {}
	for _, msg in ipairs(playerMsgs) do table.insert(pData.messages, msg) end
	for _, msg in ipairs(botMsgs) do table.insert(pData.messages, msg) end
	self:MarkDirty()
	if self.utils then
		self.utils.LogInfo("[LLMRemember]",
			self:GetLocalized("log_remember_msg_added"),
			playerName,
			role,
			string.sub(sanitizedText, 1, 50))
	end
end
function LLMRemember:AddEvent(playerName, eventType, text)
	if not self:IsEnabled() then return end
	playerName = self:SanitizeString(playerName)
	if playerName == "" then
		playerName = "Unknown"
	end
	if not self._data.players[playerName] then
		self._data.players[playerName] = { messages = {}, events = {} }
	end
	local pData = self._data.players[playerName]
	local sanitizedText = self:SanitizeString(text)
	table.insert(pData.events, {
		type = eventType,
		text = sanitizedText,
		time = os.time()
	})
	while #pData.events > 8 do table.remove(pData.events, 1) end
	self:MarkDirty()
	if self.utils then
		self.utils.LogInfo("[LLMRemember]", self:GetLocalized("log_remember_event_added"), playerName, sanitizedText)
	end
end
function LLMRemember:GetMemoryContext(ply)
	if not self:IsEnabled() then return "" end
	if not self.utils or not self.utils:IsValid(ply) then return "" end
	local playerName = self:GetSafePlayerName(ply)
	local pData = self._data.players[playerName]
	if not pData then return "" end
	local lines = {}
	table.insert(lines, "=== ПАМЯТЬ БОТА ===")
	if pData.messages and #pData.messages > 0 then
		table.insert(lines, "Последние сообщения:")
		for _, msg in ipairs(pData.messages) do
			local roleName = msg.role == "player" and "Игрок" or "Бот"
			table.insert(lines, string.format("[%s] %s", roleName, msg.text or ""))
		end
	end
	if pData.events and #pData.events > 0 then
		table.insert(lines, "Последние события:")
		for _, ev in ipairs(pData.events) do
			table.insert(lines, string.format("- %s", ev.text or ""))
		end
	end
	table.insert(lines, "==================")
	return table.concat(lines, "\n")
end
function LLMRemember:GetNPCName(npc)
	if not IsValid(npc) then return self:GetLocalized("unknown") end
	local class = npc:GetClass() or "unknown"
	local name = NPC_NAMES[class]
	if name then return name end
	if npc.GetName then
		local n = npc:GetName()
		if n and n ~= "" then return self:SanitizeString(n) end
	end
	return class
end
function LLMRemember:SetupHooks()
	hook.Add("PlayerDeath", "gmod.one/ai-companion/record-fatality", function(victim, inflictor, attacker)
		if not self:IsEnabled() then return end
		if not victim or not victim:IsPlayer() then return end
		local attackerName = self:GetLocalized("unknown")
		if IsValid(attacker) then
			if attacker:IsPlayer() then
				attackerName = self:GetSafePlayerName(attacker)
			else
				attackerName = attacker:GetClass() or self:GetLocalized("unknown")
			end
		end
		if victim:IsBot() and victim:GetNWBool("IsAICompanion", false) then
			local owner = victim:GetNWEntity("AICompanionOwnerEnt")
			if IsValid(owner) then
				local ownerName = self:GetSafePlayerName(owner)
				self:AddEvent(ownerName, "companion_death",
					self:GetLocalized("log_remember_companion_death"):format(ownerName, attackerName))
			end
			return
		end
		if victim:IsBot() then return end
		local victimName = self:GetSafePlayerName(victim)
		self:AddEvent(victimName, "death",
			self:GetLocalized("log_remember_player_death"):format(victimName, attackerName))
		if IsValid(attacker) and attacker:IsPlayer() and not attacker:IsBot() and attacker ~= victim then
			local killerName = self:GetSafePlayerName(attacker)
			self:AddEvent(killerName, "kill",
				self:GetLocalized("log_remember_kill"):format(killerName, victimName))
		end
	end)
	hook.Add("OnNPCKilled", "gmod.one/ai-companion/record-hunt", function(npc, attacker, inflictor)
		if not self:IsEnabled() then return end
		if not IsValid(npc) then return end
		local npcName = self:GetNPCName(npc)
		local killer = attacker
		if IsValid(killer) and not killer:IsPlayer() and killer.GetOwner then
			local ownerEnt = killer:GetOwner()
			if IsValid(ownerEnt) and ownerEnt:IsPlayer() then
				killer = ownerEnt
			end
		end
		if not IsValid(killer) or not killer:IsPlayer() then return end
		if killer:IsBot() then
			if killer:GetNWBool("IsAICompanion", false) then
				local owner = killer:GetNWEntity("AICompanionOwnerEnt")
				if IsValid(owner) then
					local ownerName = self:GetSafePlayerName(owner)
					self:AddEvent(ownerName, "npc_kill_companion",
						self:GetLocalized("log_remember_npc_kill_companion"):format(ownerName, npcName))
				end
			end
			return
		end
		local killerName = self:GetSafePlayerName(killer)
		self:AddEvent(killerName, "npc_kill",
			self:GetLocalized("log_remember_npc_kill"):format(killerName, npcName))
	end)
	hook.Add("PlayerInitialSpawn", "gmod.one/ai-companion/remember-join", function(ply)
		if not self:IsEnabled() then return end
		if not ply:IsPlayer() or ply:IsBot() then return end
		local playerName = self:GetSafePlayerName(ply)
		self:AddEvent(playerName, "join",
			self:GetLocalized("log_remember_join"):format(playerName))
	end)
	hook.Add("PlayerDisconnected", "gmod.one/ai-companion/record-departure", function(ply)
		if not self:IsEnabled() then return end
		if not ply:IsPlayer() or ply:IsBot() then return end
		local playerName = self:GetSafePlayerName(ply)
		self:AddEvent(playerName, "leave",
			self:GetLocalized("log_remember_leave"):format(playerName))
	end)
	hook.Add("PlayerSpawn", "gmod.one/ai-companion/record-arrival", function(ply)
		if not self:IsEnabled() then return end
		if not ply:IsPlayer() or ply:IsBot() then return end
		local playerName = self:GetSafePlayerName(ply)
		self:AddEvent(playerName, "spawn",
			self:GetLocalized("log_remember_spawn"):format(playerName, game.GetMap()))
	end)
	hook.Add("PlayerEnteredVehicle", "gmod.one/ai-companion/remember-vehicle", function(ply, veh)
		if not self:IsEnabled() then return end
		if not ply:IsPlayer() or ply:IsBot() then return end
		local playerName = self:GetSafePlayerName(ply)
		local vehName = IsValid(veh)
			and (veh:GetClass() or self:GetLocalized("status_in_vehicle"))
			or self:GetLocalized("status_in_vehicle")
		self:AddEvent(playerName, "vehicle",
			self:GetLocalized("log_remember_vehicle"):format(playerName, vehName))
	end)
end
function LLMRemember:SetupNetReceivers()
	if SERVER then
		util.AddNetworkString("gmod.one/ai-companion/remember-request-log")
		util.AddNetworkString("gmod.one/ai-companion/remember-send-log")
		util.AddNetworkString("gmod.one/ai-companion/remember-clear")
		util.AddNetworkString("gmod.one/ai-companion/remember-toggle")
		net.Receive("gmod.one/ai-companion/remember-request-log", function(len, ply)
			if not ply:IsAdmin() then return end
			local logText = self:GetReadableLog()
			net.Start("gmod.one/ai-companion/remember-send-log")
			net.WriteString(logText)
			net.Send(ply)
		end)
		net.Receive("gmod.one/ai-companion/remember-clear", function(len, ply)
			if not ply:IsAdmin() then return end
			self._data.players = {}
			self:SaveToFile()
			if self.utils then
				self.utils.LogInfo("[LLMRemember]", self:GetLocalized("log_remember_cleared"), ply:Nick())
			end
		end)
		net.Receive("gmod.one/ai-companion/remember-toggle", function(len, ply)
			if not ply:IsAdmin() then return end
			local val = net.ReadBool()
			self._data.enabled = val
			if self.state then
				self.state:setSetting("Memory_Enabled", val)
			end
			self:SaveToFile()
			if self.utils then
				self.utils.LogInfo("[LLMRemember]",
				self:GetLocalized("log_remember_toggle"),
				(val and self:GetLocalized("mode_on") or self:GetLocalized("mode_off")))
			end
		end)
	end
end
function LLMRemember:GetReadableLog()
	local lines = {}
	table.insert(lines, "=== " .. self:GetLocalized("menu_memory") .. " ===")
	table.insert(lines,
		self:GetLocalized("menu_tts_status") .. ": " ..
			(self._data.enabled and self:GetLocalized("mode_on") or self:GetLocalized("mode_off")))
	table.insert(lines, self:GetLocalized("log_remember_players") .. ": " .. table.Count(self._data.players or {}))
	table.insert(lines, "================================\n")
	for playerName, pData in pairs(self._data.players or {}) do
		table.insert(lines, self:GetLocalized("status_name"):format(playerName))
		if pData.events and #pData.events > 0 then
			table.insert(lines, "  " .. self:GetLocalized("log_remember_events") .. ":")
			for _, ev in ipairs(pData.events) do
				local timeStr = ev.time and os.date("%H:%M:%S", ev.time) or "??:??:??"
				table.insert(lines, "    [" .. timeStr .. "] " .. ev.text)
			end
		end
		if pData.messages and #pData.messages > 0 then
			table.insert(lines, "  " .. self:GetLocalized("log_remember_dialogs") .. ":")
			for _, msg in ipairs(pData.messages) do
				local timeStr = msg.time and os.date("%H:%M:%S", msg.time) or "??:??:??"
				local icon = msg.role == "player" and "" or ""
				table.insert(lines, "    [" .. timeStr .. "] " .. icon .. " " .. msg.text)
			end
		end
	end
	if table.Count(self._data.players or {}) == 0 then
		table.insert(lines, "(" .. self:GetLocalized("log_remember_empty") .. ")")
	end
	return table.concat(lines, "\n")
end
function LLMRemember:GetAPI()
	return {
		AddMessage = function(playerName, role, text) return self:AddMessage(playerName, role, text) end,
		AddEvent = function(playerName, eventType, text) return self:AddEvent(playerName, eventType, text) end,
		GetMemoryContext = function(ply) return self:GetMemoryContext(ply) end,
		GetSafePlayerName = function(ply) return self:GetSafePlayerName(ply) end,
		IsEnabled = function() return self:IsEnabled() end,
	}
end
return LLMRemember