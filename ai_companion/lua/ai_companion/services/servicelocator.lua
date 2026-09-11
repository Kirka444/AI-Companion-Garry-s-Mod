local ServiceLocator = {}
ServiceLocator.__index = ServiceLocator
function ServiceLocator:new()
	local obj = {
		services = {},
		factories = {},
		_is_ai_locator = true,
		_lazy = false,
	}
	setmetatable(obj, self)
	return obj
end
function ServiceLocator:setLazy(enabled)
	self._lazy = enabled == true
	return self
end
function ServiceLocator:isLazy()
	return self._lazy == true
end
function ServiceLocator:register(name, instanceOrFactory, ...)
	if type(instanceOrFactory) ~= "function" then
		self.services[name] = instanceOrFactory
		return self
	end
	self.factories[name] = {
		fn = instanceOrFactory,
		args = {...}
	}
	return self
end
function ServiceLocator:get(name)
	local cached = self.services[name]
	if cached ~= nil then
		return cached
	end
	local factory = self.factories[name]
	if not factory then
		error("[AI Companion] Service not found: " .. tostring(name))
	end
	local instance = factory.fn(self, unpack(factory.args))
	self.services[name] = instance
	self.factories[name] = nil
	if not self._lazy and type(instance.init) == "function" then
		local ok, err = pcall(instance.init, instance, self)
		if not ok then
			error("[AI Companion] Failed to init '" .. name .. "': " .. tostring(err))
		end
	end
	return instance
end
function ServiceLocator:has(name)
	return self.services[name] ~= nil or self.factories[name] ~= nil
end
function ServiceLocator:initAll()
	for name, svc in pairs(self.services) do
		if type(svc.init) == "function" then
			local ok, err = pcall(svc.init, svc, self)
			if not ok then
				error("[AI Companion] Failed to init '" .. name .. "': " .. tostring(err))
			end
		end
	end
end
local REGISTRY_KEY = "__AI_COMPANION_LOCATOR_v2"
local registry = debug.getregistry()
if registry[REGISTRY_KEY] then
	if not registry[REGISTRY_KEY]._is_ai_locator then
		ErrorNoHaltWithStack("[AI Companion] Registry key '" .. REGISTRY_KEY .. "' already taken by another addon!\n")
		return registry[REGISTRY_KEY]
	end
	return registry[REGISTRY_KEY]
end
local locator = ServiceLocator:new()
registry[REGISTRY_KEY] = locator

-- Защита глобала AICompanion от перезаписи
_G.AICompanion = _G.AICompanion or {}

local aiCompanionMt = {
	__newindex = function(t, k, v)
		if k == "GetLocator" and rawget(t, k) ~= nil then
			ErrorNoHaltWithStack("[AI Companion] ⛔ Попытка перезаписи AICompanion.GetLocator!\n")
			return
		end
		if k == "GetLocale" and rawget(t, k) ~= nil then
			ErrorNoHaltWithStack("[AI Companion] ⛔ Попытка перезаписи AICompanion.GetLocale!\n")
			return
		end
		rawset(t, k, v)
	end,
	__metatable = false
}

if getmetatable(_G.AICompanion) ~= false then
	setmetatable(_G.AICompanion, aiCompanionMt)
end

return locator