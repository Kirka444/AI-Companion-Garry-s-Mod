ENT.Type = "nextbot"
ENT.Base = "drgbase_nextbot_human"

if not CLIENT then
	return
end

local DEFAULT_NAME = "Solo Companion NPC"
local CLASS_NAME = "solo_companion_npc"

print("[SoloNPC][CLIENT] cl_init.lua loaded")

hook.Add("InitPostEntity", "gmod.one/solo-companion/sync-color", function()
	local ply = LocalPlayer()

	if IsValid(ply) then
		local col = ply:GetPlayerColor()

		if col then
			ply:SetNWVector("PlayerColor", col)
			print("[SoloNPC][CLIENT] Player color set in NW:", col.x, col.y, col.z)
		end
	end
end)

hook.Add("PlayerColorChanged", "gmod.one/solo-companion/update-color", function(ply, oldColor, newColor)
	if IsValid(ply) and ply == LocalPlayer() and newColor then
		ply:SetNWVector("PlayerColor", newColor)
		print("[SoloNPC][CLIENT] Player color updated in NW:", newColor.x, newColor.y, newColor.z)
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
			print("[SoloNPC][CLIENT] language.Add updated: " .. CLASS_NAME .. " -> " .. nick)

			ent.PrintName = nick
			print("[SoloNPC][CLIENT] ent.PrintName updated: " .. nick)

			local stored = scripted_ents.GetStored(CLASS_NAME)

			if stored and stored.t then
				stored.t.PrintName = nick
				print("[SoloNPC][CLIENT] scripted_ents.PrintName updated: " .. nick)
			else
				print("[SoloNPC][CLIENT] WARNING: scripted_ents.GetStored returned nil!")
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
				print("[SoloNPC][CLIENT] Replaced cached fields: " .. replaced)
			end

			print("[SoloNPC][CLIENT] Companion name fully updated: " .. nick)
		end
	end
end)

matproxy.Add({
	name = "PlayerWeaponColor",
	init = function(self, mat, values)
		self.ResultTo = values.resultvar or "$selfillumtint"
	end,
	bind = function(self, mat, ent)
		if not IsValid(ent) then
			return
		end

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
	end,
})
