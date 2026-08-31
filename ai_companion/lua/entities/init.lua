ENT.Type = "nextbot"
ENT.Base = "drgbase_nextbot_human"

if not SERVER then return end




local VALID_COMBAT_WEAPONS = {
	["weapon_ar2"] = true,
	["weapon_smg1"] = true,
	["weapon_crossbow"] = true,
	["weapon_shotgun"] = true,
	["weapon_pistol"] = true,
	["weapon_357"] = true,
	["weapon_rpg"] = true
}




local function FindCompanion()
	for _, ent in ipairs(ents.FindByClass("solo_companion_npc")) do
		if IsValid(ent) then return ent end
	end
	return nil
end




concommand.Add("ai_solo_spawn", function(ply)
	if not IsValid(ply) or not ply:IsPlayer() then return end

	if not game.SinglePlayer() then
		ply:ChatPrint("[AI] Компаньон доступен только в одиночной игре!")
		return
	end

	if FindCompanion() then
		ply:ChatPrint("[AI] На карте уже есть компаньон! Используйте ai_solo_replace")
		return
	end

	local npc = ents.Create("solo_companion_npc")
	if not IsValid(npc) then
		ply:ChatPrint("[AI] Ошибка создания NPC!")
		return
	end

	npc:SetPos(ply:GetPos() + ply:GetForward() * 50 + Vector(0, 0, 5))
	npc:Spawn()
	npc:Activate()
	ply:ChatPrint("[AI] Компаньон создан!")
end)




concommand.Add("ai_solo_remove", function(ply)
	if not IsValid(ply) or not ply:IsPlayer() then return end

	local npc = FindCompanion()
	if IsValid(npc) then
		npc:Remove()
		ply:ChatPrint("[AI] Компаньон удалён")
	else
		ply:ChatPrint("[AI] Компаньон не найден!")
	end
end)




concommand.Add("ai_solo_replace", function(ply)
	if not IsValid(ply) or not ply:IsPlayer() then return end

	if not game.SinglePlayer() then
		ply:ChatPrint("[AI] Компаньон доступен только в одиночной игре!")
		return
	end

	
	local old = FindCompanion()
	if IsValid(old) then
		old:Remove()
		ply:ChatPrint("[AI] Старый компаньон удалён")
	end

	
	timer.Simple(0.2, function()
		if not IsValid(ply) then return end

		local npc = ents.Create("solo_companion_npc")
		if not IsValid(npc) then
			ply:ChatPrint("[AI] Ошибка создания NPC!")
			return
		end

		npc:SetPos(ply:GetPos() + ply:GetForward() * 50 + Vector(0, 0, 5))
		npc:Spawn()
		npc:Activate()
		ply:ChatPrint("[AI] Компаньон пересоздан!")
	end)
end)




concommand.Add("ai_solo_teleport", function(ply)
	if not IsValid(ply) or not ply:IsPlayer() then return end

	local npc = FindCompanion()
	if not IsValid(npc) then
		ply:ChatPrint("[AI] Компаньон не найден!")
		return
	end

	
	local tr = util.TraceLine({
		start = ply:EyePos(),
		endpos = ply:EyePos() + ply:GetAimVector() * 300,
		filter = {ply, npc}
	})

	
	if not tr.Hit then
		npc:SetPos(ply:GetPos() + ply:GetForward() * 50 + Vector(0, 0, 5))
		ply:ChatPrint("[AI] Компаньон телепортирован рядом с вами")
		return
	end

	
	if tr.HitNormal.z > 0.7 then
		npc:SetPos(tr.HitPos + Vector(0, 0, 5))
		npc.loco:SetDesiredSpeed(0)
		npc._myTarget = nil
		npc._attackMode = false
		npc._lastKnownPos = nil
		ply:ChatPrint("[AI] Компаньон телепортирован!")
	else
		
		npc:SetPos(ply:GetPos() + ply:GetForward() * 50 + Vector(0, 0, 5))
		ply:ChatPrint("[AI] Нельзя телепортировать на стену/потолок. Компаньон телепортирован рядом с вами.")
	end
end)




concommand.Add("ai_solo_model", function(ply, cmd, args)
	if not IsValid(ply) or not ply:IsPlayer() then return end

	local npc = FindCompanion()
	if not IsValid(npc) then
		ply:ChatPrint("[AI] Компаньон не найден!")
		return
	end

	if #args < 1 then
		ply:ChatPrint("[AI] Использование: ai_solo_model <путь_к_модели>")
		ply:ChatPrint("[AI] Текущая модель: " .. npc:GetModel())
		return
	end

	local model = args[1]
	if npc:SetBotModel(model) then
		npc._customModel = model
		ply:ChatPrint("[AI] Модель установлена: " .. model)
	else
		ply:ChatPrint("[AI] Неверная модель: " .. model)
	end
end)




concommand.Add("ai_solo_combat_weapon", function(ply, cmd, args)
	if not IsValid(ply) or not ply:IsPlayer() then return end

	local npc = FindCompanion()
	if not IsValid(npc) then
		ply:ChatPrint("[AI] Компаньон не найден!")
		return
	end

	if #args < 1 then
		ply:ChatPrint("[AI] Использование: ai_solo_combat_weapon <оружие>")
		ply:ChatPrint("[AI] Поддерживаемые: weapon_ar2, weapon_smg1, weapon_crossbow, weapon_shotgun, weapon_pistol, weapon_357, weapon_rpg")
		ply:ChatPrint("[AI] Текущее боевое оружие: " .. npc._combatWeaponClass)
		return
	end

	local weapon = args[1]
	if npc:SetCombatWeapon(weapon) then
		ply:ChatPrint("[AI] Боевое оружие установлено: " .. weapon)
	else
		ply:ChatPrint("[AI] Оружие не поддерживается: " .. weapon)
		ply:ChatPrint("[AI] Поддерживаемые: weapon_ar2, weapon_smg1, weapon_crossbow, weapon_shotgun, weapon_pistol, weapon_357, weapon_rpg")
	end
end)




concommand.Add("ai_solo_idle_weapon", function(ply, cmd, args)
	if not IsValid(ply) or not ply:IsPlayer() then return end

	local npc = FindCompanion()
	if not IsValid(npc) then
		ply:ChatPrint("[AI] Компаньон не найден!")
		return
	end

	if #args < 1 then
		ply:ChatPrint("[AI] Использование: ai_solo_idle_weapon <оружие>")
		ply:ChatPrint("[AI] Текущее мирное оружие: " .. npc._idleWeaponClass)
		return
	end

	local weapon = args[1]
	if npc:SetIdleWeapon(weapon) then
		ply:ChatPrint("[AI] Мирное оружие установлено: " .. weapon)
	else
		ply:ChatPrint("[AI] Не удалось установить оружие: " .. weapon)
	end
end)




concommand.Add("ai_solo_heal", function(ply)
	if not IsValid(ply) or not ply:IsPlayer() then return end

	local npc = FindCompanion()
	if not IsValid(npc) then
		ply:ChatPrint("[AI] Компаньон не найден!")
		return
	end

	npc._healEnabled = not npc._healEnabled
	npc:SaveSettings()
	if npc._healEnabled then
		ply:ChatPrint("[AI] Автолечение ВКЛЮЧЕНО")
		ply:ChatPrint("[AI] Порог лечения: " .. math.floor(npc._healThreshold * 100) .. "% ХП")
	else
		ply:ChatPrint("[AI] Автолечение ВЫКЛЮЧЕНО")
		ply:ChatPrint("[AI] Текущее состояние: " .. tostring(npc._healEnabled))
	end
end)




concommand.Add("ai_solo_nick", function(ply, cmd, args)
	if not IsValid(ply) or not ply:IsPlayer() then return end

	local npc = FindCompanion()
	if not IsValid(npc) then
		ply:ChatPrint("[AI] Компаньон не найден!")
		return
	end

	if #args < 1 then
		ply:ChatPrint("[AI] Использование: ai_solo_nick <имя>")
		ply:ChatPrint("[AI] Текущее имя: " .. npc:GetCustomNick())
		return
	end

	local name = table.concat(args, " ")
	npc:SetCustomNick(name)
	ply:ChatPrint("[AI] Имя установлено: " .. name)
end)




concommand.Add("ai_solo_save", function(ply)
	if not IsValid(ply) or not ply:IsPlayer() then return end
	local npc = FindCompanion()
	if not IsValid(npc) then
		ply:ChatPrint("[AI] Компаньон не найден!")
		return
	end
	npc:SaveSettings()
	ply:ChatPrint("[AI] Настройки сохранены в data/ai_companion_data/ai_companion_solo.txt")
end)

concommand.Add("ai_solo_load", function(ply)
	if not IsValid(ply) or not ply:IsPlayer() then return end
	local npc = FindCompanion()
	if not IsValid(npc) then
		ply:ChatPrint("[AI] Компаньон не найден!")
		return
	end
	if npc:LoadSettings() then
		ply:ChatPrint("[AI] Настройки загружены из сохранения!")
	else
		ply:ChatPrint("[AI] Файл сохранения не найден!")
	end
end)