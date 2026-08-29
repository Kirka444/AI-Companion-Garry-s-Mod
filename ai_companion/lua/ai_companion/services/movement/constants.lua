
local Constants = {}

function Constants:new(config)
    local obj = {
        config = config,
        _cached = nil,
    }
    setmetatable(obj, self)
    self.__index = self
    return obj
end

function Constants:get()
    if self._cached then return self._cached end

    local magic = self.config and self.config:get("Magic") or {}
    local nav = magic.Navigation or {}
    local speeds = magic.Speeds or {}
    local combat = magic.Combat or {}

    self._cached = {

        NAV_MESH_INVALID = 0,
        NAV_MESH_CROUCH = 1,
        NAV_MESH_JUMP = 2,
        NAV_MESH_PRECISE = 4,
        NAV_MESH_NO_JUMP = 8,
        NAV_MESH_STOP = 16,
        NAV_MESH_RUN = 32,
        NAV_MESH_WALK = 64,
        NAV_MESH_AVOID = 128,
        NAV_MESH_TRANSIENT = 256,
        NAV_MESH_BLOCKED = 512,
        NAV_MESH_HAS_ELEVATOR = 1024,
        NAV_MESH_FUNC_COST = 2048,
        NAV_MESH_OBSTACLE_TOP = 16384,
        NAV_MESH_CLIFF = 32768,

        closeFollowDistSq = nav.CloseFollowDistSq or 22500,

        directPathDistSq = nav.DirectPathDistSq or 10000,
        directPathMaxDistSq = nav.DirectPathMaxDistSq or 62500,
        directPathMinDist = nav.DirectPathMinDist or 100,

        directCheckInterval = nav.DirectCheckInterval or 0.5,

        directNavMinDist = nav.DirectNavMinDist or 500,
        directNavMaxDist = nav.DirectNavMaxDist or 3000,
        directNavSpeed = nav.DirectNavSpeed or 300,
        directNavCheckInterval = nav.DirectNavCheckInterval or 5.0,
        directNavTeleportThreshold = nav.DirectNavTeleportThreshold or 4000,
        directNavObstacleCheckDist = nav.DirectNavObstacleCheckDist or 150,
        directNavWallSlideDist = nav.DirectNavWallSlideDist or 80,
        directNavTurnSpeed = nav.DirectNavTurnSpeed or 2.0,

        areaCacheTime = nav.AreaCacheTime or 0.35,
        maxPathRetries = nav.MaxPathRetries or 4,
        navDisabledTime = nav.NavDisabledTime or 3,
        recalcInterval = nav.RecalcInterval or 1.0,
        maxIterations = nav.MaxIterations or 1500,
        teleportDist = nav.TeleportDist or 2000,
        lookaheadDist = nav.LookaheadDist or 56,
        debugOverlayInterval = nav.DebugOverlayInterval or 1.0,
        unstuckTime = nav.UnstuckTime or 0.7,
        unstuckDuration = nav.UnstuckDuration or 0.45,
        ladderTimeout = nav.LadderTimeout or 4,
        fastDist = nav.FastDist or 700,
        mediumDist = nav.MediumDist or 260,
        walkSlow = nav.WalkSlow or 200,
        wallRepathDelay = nav.WallRepathDelay or 5.0,
        avoidanceRadius = nav.AvoidanceRadius or 64,
        maxClimbHeight = nav.MaxClimbHeight or 40,
        jumpCheckDist = nav.JumpCheckDist or 32,
        noclipHeightThreshold = nav.NoclipHeightThreshold or 50,
        noclipTeleportCheckDist = nav.NoclipTeleportCheckDist or 500,
        minGoalMoveForRepath = nav.MinGoalMoveForRepath or 16384,
        strafeWallClearance = nav.StrafeWallClearance or 24,

        maxWaypointAdvance = nav.MaxWaypointAdvance or 12,
        waypointRadius = 48,
        waypointAdvanceThreshold = 5,

        stairsSkipTime = nav.StairsSkipTime or 1.5,
        stairsMinMoveSq = nav.StairsMinMoveSq or 225,
        stairsFlatDist = nav.StairsFlatDist or 150,
        stairsHeightDiff = nav.StairsHeightDiff or 120,
        stairsHeightThreshold = 40,
        stairsZDiffThreshold = 30,
        stairsAdjacentThreshold = 2,

        stuckDistSq = nav.StuckDistSq or 36,
        stuckFallZDiff = nav.StuckFallZDiff or 40,
        stuckFallXYDist = nav.StuckFallXYDist or 200,
        stuckHistoryTime = 2.5,
        stuckMaxHistory = 3,
        standStillThreshold = 8,
        standStillTimeThreshold = 1.5,
        standStillSpeedThreshold = 20,

        doorOffsets = {20, 40, 60},
        doorOpenDelay = 0.7,
        doorMaxTries = 3,
        doorOpenAttemptDelay = 0.15,

        wallSlideDistance = 50,
        wallSlideCheckDistance = 35,
        wallSlideHeight = 20,
        obstacleCheckDistance = 40,
        obstacleMinDistance = 64,
        obstacleAvoidFactor = 0.85,
        obstacleMoveFactor = 0.65,

        teleportFailLimit = 3,
        teleportFallbackTimeout = 2.0,
        teleportSearchRadius = 1500,
        teleportMaxDistSq = 90000,

        repathCooldown = 0.3,
        repathCooldownLarge = 3.0,
        repathCooldownMedium = 1.5,

        navAreaSearchRadius = 600,
        navAreaCacheDistSq = 4096,
        navAreaZThreshold = 60,
        navAreaSmartOffsets = {0, -10, -20, 10, 20, -30, 30, -50, 50, -80, 80},
        debugOverlayTime = 0.1,

        jumpHeightMin = 8,
        jumpHeightMax = 45,
        jumpFlatDist = 100,
        jumpZThreshold = 15,
        jumpCheckHeight = 72,

        crouchCheckHeight = 52,
        crouchCheckDist = 30,

        speedMin = speeds.Min or 80,
        speedMax = speeds.Max or 400,
        walkSpeed = speeds.Walk or 200,
        runSpeed = speeds.Run or 320,
        stealthSpeed = speeds.Stealth or 80,
        crouchSpeed = speeds.Crouch or 90,
        meleeSpeed = speeds.Melee or 400,
        combatSpeed = speeds.Combat or 220,
        fleeSpeed = speeds.Flee or 350,
        dodgeSpeed = speeds.Dodge or 350,

        weaponSwitchTime = 1.0,

        replaceDelay = 0.5,
        forceWPSkipTime = 2.5,
        forceWPSkipMinMove = 100,
        heightSkipTime = 1.5,
    }

    return self._cached
end

return Constants
