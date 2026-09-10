local NavMesh = {}

function NavMesh:new(utils, constants)
	local obj = {
		utils = utils,
		constants = constants,
		AreaCache = {},
		CenterCache = {},
		AttrCache = {},
		PathCache = {},
		PathCacheCount = 0,
	}
	setmetatable(obj, self)
	self.__index = self
	return obj
end

function NavMesh:GetLocalized(key, ...)
	local locator = AICompanion.GetLocator()
	if locator and locator:has("locale") then
		local locale = locator:get("locale")
		if locale and locale.Get then
			return locale:Get(key, ...)
		end
	end
	return key
end

function NavMesh:IsValid(ent)
	return self.utils and self.utils:IsValid(ent)
end

function NavMesh:GetConst()
	return self.constants and self.constants:get() or {}
end

function NavMesh:SafeCall(fn, default, ...)
	local ok, result = pcall(fn, ...)
	if ok then return result end
	return default
end

function NavMesh:GetAreaByID(id)
	local cached = self.AreaCache[id]
	if cached ~= nil then return cached end
	local ok, area = navmesh.GetNavAreaByID(id)
	if not ok then area = nil end
	self.AreaCache[id] = area
	return area
end

function NavMesh:GetAreaID(area)
	if not area then return nil end
	local ok, id = area:GetID()
	return ok and id or nil
end

function NavMesh:GetAreaCenter(area)
	return self:GetAreaCenterCached(area)
end

function NavMesh:GetAreaCenterCached(area)
	if not area then return nil end

	local id = self:GetAreaID(area)
	if not id then return nil end

	self.CenterCache = self.CenterCache or {}

	local now = CurTime()
	local c = self.CenterCache[id]

	if c and now - c.t < 2.0 then
		return c.pos
	end

	local ok, center = area:GetCenter()

	if ok and center and isvector(center) then
		self.CenterCache[id] = {
			t = now,
			pos = center,
		}

		return center
	end

	return nil
end

function NavMesh:GetAreaAttrCached(area)
	self.AttrCache = self.AttrCache or {}

	if not self:IsValid(area) then
		return {
			blocked = true,
			obstacle = false,
			attrs = 0,
		}
	end

	local id = self:GetAreaID(area)

	if not id then
		return {
			blocked = true,
			obstacle = false,
			attrs = 0,
		}
	end

	local now = CurTime()
	local c = self.AttrCache[id]

	if c and now - c.t < 2.0 then
		return c
	end

	local ok, attrs = area:GetAttributes()
	attrs = ok and tonumber(attrs) or 0

	local const = self:GetConst()

	c = {
		t = now,
		attrs = attrs,
		blocked = bit.band(attrs, const.NAV_MESH_BLOCKED) ~= 0,
		obstacle = bit.band(attrs, const.NAV_MESH_AVOID) ~= 0
			or bit.band(attrs, const.NAV_MESH_OBSTACLE_TOP) ~= 0
			or bit.band(attrs, const.NAV_MESH_CLIFF) ~= 0,
	}

	self.AttrCache[id] = c

	return c
end

function NavMesh:GetAreaClosest(area, pos)
	if not area or not pos then return nil end
	local ok, closest = area:GetClosestPointOnArea(pos)
	return ok and closest or nil
end

function NavMesh:GetNearestArea(pos, radius)
	if not navmesh or not navmesh.IsLoaded() then return nil end
	if not pos then return nil end
	local ok, area = navmesh.GetNearestNavArea(pos, radius or 400)
	return ok and self:IsValid(area) and area or nil
end

function NavMesh:GetAreaCorners(area)
	if not area then return nil end
	local ok, corners = {
			area:GetCorner(0),
			area:GetCorner(1),
			area:GetCorner(2),
			area:GetCorner(3)
		}
	if ok and corners and #corners >= 3 then return corners end
	local center = self:GetAreaCenter(area)
	if not center then return nil end
	local ext = 32
	return {
		center + Vector(-ext, -ext, 0),
		center + Vector(ext, -ext, 0),
		center + Vector(ext, ext, 0),
		center + Vector(-ext, ext, 0)
	}
end

function NavMesh:GetAreaAttributes(area)
	if not self:IsValid(area) then return 0 end
	local ok, attrs = area:GetAttributes()
	return ok and tonumber(attrs) or 0
end

function NavMesh:IsAreaBlocked(area)
	return self:GetAreaAttrCached(area).blocked
end

function NavMesh:IsAreaObstacle(area)
	return self:GetAreaAttrCached(area).obstacle
end

function NavMesh:IsAreaStairs(area)
	if not self:IsValid(area) then return false end
	local const = self:GetConst()

	local okAttr, attrs = area:GetAttributes()
	if okAttr and attrs then
		if bit.band(attrs, const.NAV_MESH_NO_JUMP) ~= 0 then
			local okAdj, adj = area:GetAdjacentAreas()
			if okAdj and adj and #adj >= 2 then
				local zs = {}
				for _, a in ipairs(adj) do
					local c = self:GetAreaCenter(a)
					if c then table.insert(zs, c.z) end
				end
				if #zs >= 2 then
					table.sort(zs)
					if math.abs(zs[#zs] - zs[1]) > const.stairsZDiffThreshold then
						return true
					end
				end
			end
		end
	end

	local okAdj, adj = area:GetAdjacentAreas()
	if okAdj and adj and #adj == const.stairsAdjacentThreshold then
		local c1 = self:GetAreaCenter(adj[1])
		local c2 = self:GetAreaCenter(adj[2])
		if c1 and c2 and math.abs(c1.z - c2.z) > const.stairsHeightThreshold then
			return true
		end
	end
	return false
end

function NavMesh:CanEnterArea(fromArea, toArea)
	if not self:IsValid(fromArea) or not self:IsValid(toArea) then return false end
	if self:IsAreaBlocked(toArea) then return false end
	if self:IsAreaObstacle(toArea) then
		local fromZ = self:GetAreaCenter(fromArea)
		local toZ = self:GetAreaCenter(toArea)
		if fromZ and toZ then
			if toZ.z > fromZ.z + 20 then return false end
		end
	end
	return true
end

function NavMesh:GetAreaEntryPoint(toArea, fromArea)
	if not self:IsValid(toArea) or not self:IsValid(fromArea) then return nil end
	local fromCenter = self:GetAreaCenter(fromArea)
	if not fromCenter then return nil end
	local ok, corners = pcall(function()
		return {
			toArea:GetCorner(0),
			toArea:GetCorner(1),
			toArea:GetCorner(2),
			toArea:GetCorner(3)
		}
	end)
	local bestPoint = nil
	local bestDist = math.huge
	if ok and corners then
		for _, c in ipairs(corners) do
			local d = c:DistToSqr(fromCenter)
			if d < bestDist then
				bestDist = d
				bestPoint = c
			end
		end
	end
	if not bestPoint then
		bestPoint = self:GetAreaCenter(toArea)
	end
	return bestPoint
end

function NavMesh:GetAreaExitPoint(fromArea, toArea)
	return self:GetAreaEntryPoint(fromArea, toArea)
end

function NavMesh:GetStairsWaypoints(stairsArea, fromArea, toArea)
	if not self:IsValid(stairsArea) then return nil end
	local fromCenter = self:GetAreaCenter(fromArea)
	local toCenter = self:GetAreaCenter(toArea)
	if not fromCenter or not toCenter then return nil end
	local entry = self:GetAreaEntryPoint(stairsArea, fromArea)
	local exit = self:GetAreaExitPoint(stairsArea, toArea)
	if not entry or not exit then return nil end
	local stairsCenter = self:GetAreaCenter(stairsArea)
	local mid = (entry + exit) * 0.5
	if stairsCenter then mid.z = stairsCenter.z end
	return {
		{ pos = entry, type = "stairs_entry", radius = 24 },
		{ pos = mid,   type = "stairs_mid",   radius = 32 },
		{ pos = exit,  type = "stairs_exit",  radius = 24 }
	}
end

function NavMesh:HeapPush(heap, item)
	heap[#heap + 1] = item
	local i = #heap
	while i > 1 do
		local p = math.floor(i / 2)
		if heap[p].f <= heap[i].f then break end
		heap[p], heap[i] = heap[i], heap[p]
		i = p
	end
end

function NavMesh:HeapPop(heap)
	local top = heap[1]
	local last = heap[#heap]
	heap[#heap] = nil
	if #heap > 0 then
		heap[1] = last
		local i = 1
		while true do
			local l = i * 2
			local r = l + 1
			local best = i
			if l <= #heap and heap[l].f < heap[best].f then best = l end
			if r <= #heap and heap[r].f < heap[best].f then best = r end
			if best == i then break end
			heap[i], heap[best] = heap[best], heap[i]
			i = best
		end
	end
	return top
end

function NavMesh:ReconstructPath(came, id)
	local steps = {}
	while id do
		local c = came[id]
		local area = self:GetAreaByID(id)
		if area then table.insert(steps, { area = area }) end
		id = c and c.pid
	end
	local reversed = {}
	for i = #steps, 1, -1 do
		table.insert(reversed, steps[i])
	end
	return reversed
end

function NavMesh:GetPathCache(key)
	self.PathCache = self.PathCache or {}

	local p = self.PathCache[key]

	if p and CurTime() < p.exp then
		return p.steps
	end

	return nil
end

function NavMesh:SetPathCache(key, steps)
	self.PathCache = self.PathCache or {}
	self.PathCacheCount = self.PathCacheCount or 0

	if self.PathCacheCount > 256 then
		self.PathCache = {}
		self.PathCacheCount = 0
	end

	if not self.PathCache[key] then
		self.PathCacheCount = self.PathCacheCount + 1
	end

	self.PathCache[key] = {
		steps = steps,
		exp = CurTime() + 3.0,
	}
end

function NavMesh:FindPath(startArea, goalArea, allowObstacles)
	if not startArea or not goalArea then return nil end
	local const = self:GetConst()
	local sid = self:GetAreaID(startArea)
	local gid = self:GetAreaID(goalArea)
	if not sid or not gid then return nil end
	if self:IsAreaBlocked(startArea) then return nil end

	local cacheKey = sid .. ">" .. gid .. ">" .. (allowObstacles and 1 or 0)
	local cachedPath = self:GetPathCache(cacheKey)
	if cachedPath then
		return cachedPath
	end

	if self:IsAreaBlocked(goalArea) then
		local goalCenter = self:GetAreaCenter(goalArea)
		if not goalCenter then return nil end

		local oldGoal = goalArea
		local radii = {
			const.navAreaSearchRadius or 400,
			800,
			1200
		}

		for _, r in ipairs(radii) do
			local alt = self:GetNearestAreaSmart(goalCenter, r)

			if alt and alt ~= oldGoal and not self:IsAreaBlocked(alt) then
				goalArea = alt
				gid = self:GetAreaID(alt)
				break
			end
		end

		if goalArea == oldGoal or not gid then
			return nil
		end
	end
	local startCenter = self:GetAreaCenter(startArea)
	local goalCenter = self:GetAreaCenter(goalArea)
	if not startCenter or not goalCenter then return nil end
	if sid == gid then
		return { { area = startArea } }
	end
	local open = {}
	local gScore = { [sid] = 0 }
	local came = {}
	local closed = {}
	self:HeapPush(open, { id = sid, g = 0, f = startCenter:Distance(goalCenter) })
	local iter = 0
	while #open > 0 and iter < const.maxIterations do
		iter = iter + 1
		local cur = self:HeapPop(open)
		local cid = cur.id
		if closed[cid] then
		elseif cid == gid then
			local result = self:ReconstructPath(came, cid)
			self:SetPathCache(cacheKey, result)
			return result
		else
			closed[cid] = true
			local area = self:GetAreaByID(cid)
			local center = area and self:GetAreaCenter(area)
			if area and self:IsAreaBlocked(area) then
			elseif area and center then
				local okAdj2, adj2 = area:GetAdjacentAreas()
				if okAdj2 and adj2 then
					for _, nb in ipairs(adj2) do
						if self:IsValid(nb) then
							local nid = self:GetAreaID(nb)
							if nid and not closed[nid] then
								if self:IsAreaBlocked(nb) then
								elseif (not allowObstacles) and self:IsAreaObstacle(nb) and nid ~= gid then
								elseif not self:CanEnterArea(area, nb) then
								else
									local ncenter = self:GetAreaCenter(nb)
									if ncenter then
										local baseCost = center:Distance(ncenter)
										local zPenalty = math.abs(center.z - ncenter.z) * 0.5
										local ng = (gScore[cid] or 0) + baseCost + zPenalty
										if self:IsAreaObstacle(nb) then ng = ng + 3000 end
										if self:IsAreaStairs(nb) then ng = ng + 100 end
										if not gScore[nid] or ng < gScore[nid] then
											gScore[nid] = ng
											came[nid] = { pid = cid }
											self:HeapPush(open, {
												id = nid,
												g = ng,
												f = ng + ncenter:Distance(goalCenter)
											})
										end
									end
								end
							end
						end
					end
				end
			end
		end
	end
	return nil
end

function NavMesh:GetNearestAreaSmart(pos, radius)
	if not navmesh or not navmesh.IsLoaded() then return nil end
	if not pos then return nil end
	local const = self:GetConst()
	local offsets = const.navAreaSmartOffsets
	local bestArea = nil
	local bestScore = math.huge
	for _, zOffset in ipairs(offsets) do
		local searchPos = pos + Vector(0, 0, zOffset)
		local ok, area = navmesh.GetNearestNavArea(searchPos, radius or const.navAreaSearchRadius)
		if ok and self:IsValid(area) then
			local center = self:GetAreaCenter(area)
			if center then
				local dist = pos:Distance(center)
				local zDiff = math.abs(pos.z - center.z)
				local score = dist + zDiff * 2
				if score < bestScore then
					bestScore = score
					bestArea = area
				end
			end
		end
	end
	return bestArea
end

function NavMesh:GetNearestAreaCached(pos, radius, st)
	if not pos then return nil end
	local const = self:GetConst()

	if not st.area_cache then
		st.area_cache = {
			pos = Vector(0, 0, 0),
			area = nil,
			time = 0,
		}
	end

	local cache = st.area_cache
	if cache.area and self:IsValid(cache.area)
		and CurTime() - cache.time < const.areaCacheTime
		and pos:DistToSqr(cache.pos) < const.navAreaCacheDistSq then
		local center = self:GetAreaCenter(cache.area)
		if center and math.abs(center.z - pos.z) < const.navAreaZThreshold then
			return cache.area
		end
	end
	local area = self:GetNearestAreaSmart(pos, radius or const.navAreaSearchRadius)
	cache.pos = Vector(pos)
	cache.area = area
	cache.time = CurTime()
	return area
end

function NavMesh:CanWalkDirect(from, to, filter)
	if not from or not to then return false end
	if from:DistToSqr(to) <= 1 then return true end
	local tr = util.TraceHull({
		start = from + Vector(0, 0, 36),
		endpos = to + Vector(0, 0, 36),
		mins = Vector(-14, -14, 0),
		maxs = Vector(14, 14, 48),
		filter = filter,
		mask = MASK_PLAYERSOLID
	})
	return not tr.Hit and not tr.StartSolid
end

return NavMesh