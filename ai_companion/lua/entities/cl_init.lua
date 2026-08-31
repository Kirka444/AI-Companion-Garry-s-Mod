ENT.Type = "nextbot"
ENT.Base = "drgbase_nextbot_human"
if not CLIENT then return end

local DEFAULT_NAME = "Solo Companion NPC"
local CLASS_NAME = "solo_companion_npc"

print("[SoloNPC][CLIENT] cl_init.lua загружен")




hook.Add("InitPostEntity", "SoloNPC_SyncPlayerColor", function()
	local ply = LocalPlayer()
	if IsValid(ply) then
		local col = ply:GetPlayerColor()
		if col then
			ply:SetNWVector("PlayerColor", col)
			print("[SoloNPC][CLIENT] Цвет игрока установлен в NW:", col.x, col.y, col.z)
		end
	end
end)

hook.Add("PlayerColorChanged", "SoloNPC_UpdatePlayerColor", function(ply, oldColor, newColor)
	if IsValid(ply) and ply == LocalPlayer() and newColor then
		ply:SetNWVector("PlayerColor", newColor)
		print("[SoloNPC][CLIENT] Цвет игрока обновлён в NW:", newColor.x, newColor.y, newColor.z)
	end
end)







function ENT:GetPrintName()
	local nick = self:GetNWString("CustomNick", "")
	if nick ~= "" then
		return nick
	end
	return self.PrintName
end

hook.Add("Think", "SoloNPC_ClientNameSync", function()
	for _, ent in ipairs(ents.FindByClass(CLASS_NAME)) do
		local nick = ent:GetNWString("CustomNick", "")
		if nick ~= "" and nick ~= ent._appliedNick then
			ent._appliedNick = nick

			
			language.Add(CLASS_NAME, nick)
			print("[SoloNPC][CLIENT] language.Add обновлён: " .. CLASS_NAME .. " -> " .. nick)

			
			ent.PrintName = nick
			print("[SoloNPC][CLIENT] ent.PrintName обновлён: " .. nick)

			
			local stored = scripted_ents.GetStored(CLASS_NAME)
			if stored and stored.t then
				stored.t.PrintName = nick
				print("[SoloNPC][CLIENT] scripted_ents.PrintName обновлён: " .. nick)
			else
				print("[SoloNPC][CLIENT] ВНИМАНИЕ: scripted_ents.GetStored вернул nil!")
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
				print("[SoloNPC][CLIENT] Заменено кэшированных полей: " .. replaced)
			end

			print("[SoloNPC][CLIENT] ✓ Имя компаньона полностью обновлено: " .. nick)
		end
	end
end)




matproxy.Add({
	name = "PlayerWeaponColor",
	init = function(self, mat, values)
		self.ResultTo = values.resultvar or "$selfillumtint"
	end,
	bind = function(self, mat, ent)
		if not IsValid(ent) then return end

		
		if ent:IsWeapon() and ent:GetClass() == "weapon_physgun" then
			local owner = ent:GetOwner()
			if IsValid(owner) and owner:GetClass() == "solo_companion_npc" then
				local col = ent:GetNWVector("WeaponColor")
				if col then
					mat:SetVector(self.ResultTo, col)
					return
				end
			end
		end

		
		if ent:IsPlayer() then
			local col = ent:GetWeaponColor()
			if col then
				mat:SetVector(self.ResultTo, col)
				return
			end
		end

		
		local owner = ent:GetOwner()
		if IsValid(owner) and owner:IsPlayer() then
			local col = owner:GetWeaponColor()
			if col then
				mat:SetVector(self.ResultTo, col)
				return
			end
		end
	end
})