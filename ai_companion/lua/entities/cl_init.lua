ENT.Type = "nextbot"
ENT.Base = "drgbase_nextbot_human"

if not CLIENT then
	return
end

local DEFAULT_NAME = "Solo Companion NPC"
local CLASS_NAME = "solo_companion_npc"

hook.Add("InitPostEntity", "gmod.one/solo-companion/sync-color", function()
	local ply = LocalPlayer()
	if IsValid(ply) then
		local col = ply:GetPlayerColor()
		if col then
			ply:SetNWVector("PlayerColor", col)
		end
	end
end)

hook.Add("PlayerColorChanged", "gmod.one/solo-companion/update-color", function(ply, oldColor, newColor)
	if IsValid(ply) and ply == LocalPlayer() and newColor then
		ply:SetNWVector("PlayerColor", newColor)
	end
end)

function ENT:GetPrintName()
	local nick = self:GetNWString("CustomNick", "")

	if nick ~= "" then
		return nick
	end

	return self.PrintName
end

hook.Add("Think", "gmod.one/solo-companion/name-sync", function()
	for _, ent in ipairs(ents.FindByClass(CLASS_NAME)) do
		local nick = ent:GetNWString("CustomNick", "")

		if nick ~= "" and nick ~= ent._appliedNick then
			ent._appliedNick = nick

			language.Add(CLASS_NAME, nick)

			ent.PrintName = nick

			local stored = scripted_ents.GetStored(CLASS_NAME)

			if stored and stored.t then
				stored.t.PrintName = nick
			else
			end

			local replaced = 0

			pcall(function()
				for key, value in pairs(ent) do
					if isstring(value) and value == DEFAULT_NAME then
						ent[key] = nick
						replaced = replaced + 1
					end
				end
			end)

			if replaced > 0 then
			end

		end
	end
end)

matproxy.Add({
	name = "PlayerWeaponColor",
	init = function(self, mat, values)
		-- $selfillumtint отвечает за свечение кристалла физгана
		self.ResultTo = values.resultvar or "$selfillumtint"
	end,
	bind = function(self, mat, ent)
		if not IsValid(ent) then return end

		-- === ФИЗГАН БОТА ===
		if ent:IsWeapon() and ent:GetClass() == "weapon_physgun" then
			local owner = ent:GetOwner()

			-- Бот: читаем цвет из NWVector
			if IsValid(owner) and owner:GetClass() == "solo_companion_npc" then
				local col = ent:GetNWVector("BotPhysgunCrystalColor", nil)

				if col then
					mat:SetVector(self.ResultTo, col)
				else
					mat:SetVector(self.ResultTo, Vector(0.007843, 0.972549, 0.298039))
				end

				return
			end

			-- Игрок: используем стандартный GetWeaponColor
			if IsValid(owner) and owner:IsPlayer() then
				local col = owner:GetWeaponColor()

				if col and (col.x ~= 0 or col.y ~= 0 or col.z ~= 0) then
					mat:SetVector(self.ResultTo, col)
				else
					-- Фолбэк на дефолтный зелёный
					mat:SetVector(self.ResultTo, Vector(0.007843, 0.972549, 0.298039))
				end

				return
			end

			-- Физган без владельца (лежит на земле) - дефолтный зелёный
			mat:SetVector(self.ResultTo, Vector(0.007843, 0.972549, 0.298039))
			return
		end

		-- === ОРУЖИЕ ИГРОКА (не физган) ===
		if ent:IsWeapon() then
			local owner = ent:GetOwner()

			if IsValid(owner) and owner:IsPlayer() then
				local col = owner:GetWeaponColor()

				if col and (col.x ~= 0 or col.y ~= 0 or col.z ~= 0) then
					mat:SetVector(self.ResultTo, col)
				end
			end

			return
		end

		-- === ИГРОК ===
		if ent:IsPlayer() then
			local col = ent:GetWeaponColor()

			if col and (col.x ~= 0 or col.y ~= 0 or col.z ~= 0) then
				mat:SetVector(self.ResultTo, col)
			end

			return
		end

		-- === ВЛАДЕЛЕЦ - ИГРОК (прочие энтити) ===
		local owner = ent:GetOwner()

		if IsValid(owner) and owner:IsPlayer() then
			local col = owner:GetWeaponColor()

			if col and (col.x ~= 0 or col.y ~= 0 or col.z ~= 0) then
				mat:SetVector(self.ResultTo, col)
			end
		end
	end,
})
