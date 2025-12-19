-- BeeRescue_Server_WithDailyQuest.lua
-- BeeRescue Server dengan integrasi Daily Quest
-- ? FIXED: Hanya gunakan BindableEvent (tidak double trigger)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")

-- ===== CONFIG =====
local CONFIG = {
	START_PROMPT_NAME = "BeeRescuePrompt",
	SUMMIT_ZONE_NAME  = "BeeRescueSummitZone",

	COOLDOWN_SEC      = 10,
	MIN_RUN_SEC       = 12,
	MAX_RUN_SEC       = 1800,
	TOUCH_DEBOUNCE    = 1.0,

	SAVE_DATASTORE    = true,
	DATASTORE_NAME    = "BeeRescuePoints_v2",
	ORDERED_LB_NAME   = "BeeRescuePoints_v2_LB",

	LOAD_RETRY_TIMES  = 2,
	LOAD_RETRY_WAIT   = 1.5,
	SAVE_RETRY_TIMES  = 2,
	SAVE_RETRY_WAIT   = 0.8,
	AUTO_SAVE_INTERVAL = 300,
	SAVE_STAGGER_DELAY = 0.3,
}

local store = CONFIG.SAVE_DATASTORE and DataStoreService:GetDataStore(CONFIG.DATASTORE_NAME) or nil
local orderedLB = CONFIG.SAVE_DATASTORE and DataStoreService:GetOrderedDataStore(CONFIG.ORDERED_LB_NAME) or nil

-- ===== DAILY QUEST INTEGRATION =====
-- ? FIXED: Hanya gunakan BindableEvent, JANGAN panggil _G.DailyQuestAPI juga
local DailyQuestBindable = nil

task.spawn(function()
	DailyQuestBindable = ReplicatedStorage:WaitForChild("DailyQuest_BeeRescued", 30)
	if DailyQuestBindable then
		print("[BeeRescue] ? Connected to Daily Quest system!")
	else
		warn("[BeeRescue] Daily Quest bindable not found")
	end
end)

local function notifyDailyQuest(plr: Player)
	-- ? HANYA gunakan BindableEvent
	-- JANGAN panggil _G.DailyQuestAPI.OnBeeRescued karena itu akan double trigger
	if DailyQuestBindable then
		DailyQuestBindable:Fire(plr)
	end
end
-- ===== END DAILY QUEST INTEGRATION =====

-- ===== REMOTE EVENTS =====
local function getOrCreateRemote(name: string, className: string): Instance
	local existing = ReplicatedStorage:FindFirstChild(name)
	if existing then return existing end
	local new = Instance.new(className)
	new.Name = name
	new.Parent = ReplicatedStorage
	return new
end

local remote    = getOrCreateRemote("BeeRescue_Remote", "RemoteEvent")
local guiRemote = getOrCreateRemote("BeeRescue_GUI", "RemoteEvent")

-- ===== STATE =====
type RunState = {
	runId: number,
	startedAt: number,
	lastEndedAt: number,
	active: boolean,
}

local runs: {[number]: RunState} = {}
local touchDebounce: {[number]: number} = {}

local lastSavedPoints: {[number]: number} = {}
local pendingPoints: {[number]: number} = {}
local loadedOk: {[number]: boolean} = {}
local loading: {[number]: boolean} = {}

local COLOR_PALETTE = {
	Color3.fromRGB(255, 214, 64),
	Color3.fromRGB(255, 170, 0),
	Color3.fromRGB(0, 255, 170),
	Color3.fromRGB(0, 170, 255),
	Color3.fromRGB(255, 105, 180),
	Color3.fromRGB(170, 85, 255),
	Color3.fromRGB(255, 255, 255),
}

-- ===== HELPER FUNCTIONS =====
local function getLeaderstatsPoints(plr: Player): IntValue?
	local ls = plr:FindFirstChild("leaderstats")
	if not ls then
		ls = Instance.new("Folder")
		ls.Name = "leaderstats"
		ls.Parent = plr
	end

	local v = ls:FindFirstChild("RescuePoints") :: IntValue?
	if not v then
		v = Instance.new("IntValue")
		v.Name = "RescuePoints"
		v.Value = 0
		v.Parent = ls
	end
	return v
end

local function getPointsValue(plr: Player): number
	local ls = plr:FindFirstChild("leaderstats")
	local v = ls and ls:FindFirstChild("RescuePoints")
	return v and (tonumber(v.Value) or 0) or 0
end

local function ensureRun(plr: Player): RunState
	local st = runs[plr.UserId]
	if not st then
		st = { runId = 0, startedAt = 0, lastEndedAt = 0, active = false }
		runs[plr.UserId] = st
	end
	return st
end

local function setRescueActive(plr: Player, isActive: boolean)
	plr:SetAttribute("BeeRescueActive", isActive)
end

local function ensureColor(plr: Player)
	if plr:GetAttribute("BeeRescueColor") ~= nil then return end
	plr:SetAttribute("BeeRescueColor", COLOR_PALETTE[math.random(1, #COLOR_PALETTE)])
end

local function setLoaded(plr: Player, ok: boolean)
	loadedOk[plr.UserId] = ok
	plr:SetAttribute("BeeRescueLoaded", ok)
end

local function isLoaded(plr: Player): boolean
	return loadedOk[plr.UserId] == true
end

-- ===== LEADERBOARD SYNC =====
local function updateLeaderboard(userId: number, points: number)
	if not orderedLB then return end
	task.spawn(function()
		pcall(function()
			orderedLB:SetAsync(tostring(userId), tonumber(points) or 0)
		end)
	end)
end

-- ===== RUN MANAGEMENT =====
local function endRun(plr: Player, _reason: string?)
	local st = ensureRun(plr)
	if not st.active then return end

	st.active = false
	st.lastEndedAt = os.clock()
	setRescueActive(plr, false)
	guiRemote:FireClient(plr, "HideTutorial")
end

local function startRun(plr: Player): (boolean, string?)
	if CONFIG.SAVE_DATASTORE and not isLoaded(plr) then
		return false, "Data masih loading, tunggu sebentar ya..."
	end

	local st = ensureRun(plr)
	if st.active then
		return false, "Rescue masih aktif."
	end

	local now = os.clock()
	if (now - st.lastEndedAt) < CONFIG.COOLDOWN_SEC then
		return false, ("Tunggu %d detik lagi."):format(math.ceil(CONFIG.COOLDOWN_SEC - (now - st.lastEndedAt)))
	end

	ensureColor(plr)
	st.runId += 1
	st.active = true
	st.startedAt = now

	plr:SetAttribute("BeeRescueRunId", st.runId)
	setRescueActive(plr, true)
	guiRemote:FireClient(plr, "ShowTutorial")

	local userId, myRunId = plr.UserId, st.runId
	task.delay(CONFIG.MAX_RUN_SEC, function()
		local p = Players:GetPlayerByUserId(userId)
		if not p then return end
		local cur = ensureRun(p)
		if cur.active and cur.runId == myRunId then
			endRun(p, "timeout")
			guiRemote:FireClient(p, "ShowTimeout")
		end
	end)

	return true, nil
end

local function completeRun(plr: Player)
	if CONFIG.SAVE_DATASTORE and not isLoaded(plr) then return end

	local st = ensureRun(plr)
	if not st.active then return end
	if (os.clock() - st.startedAt) < CONFIG.MIN_RUN_SEC then return end

	local v = getLeaderstatsPoints(plr)
	if not v then return end

	v.Value += 1
	local total = v.Value
	pendingPoints[plr.UserId] = total

	endRun(plr, "success")
	guiRemote:FireClient(plr, "ShowSuccess", { points = 1, total = total })

	remote:FireAllClients("Success", {
		userId = plr.UserId,
		name = plr.DisplayName or plr.Name,
		total = total,
	})

	-- ? DAILY QUEST NOTIFICATION (hanya sekali via BindableEvent)
	notifyDailyQuest(plr)
end

-- ===== DATASTORE =====
local function savePointsCore(userId: number, valueToSave: number): boolean
	if not store or valueToSave <= 0 then return true end
	local key = "U_" .. userId

	for attempt = 1, CONFIG.SAVE_RETRY_TIMES do
		local success, result = pcall(function()
			return store:UpdateAsync(key, function(old)
				return math.max((type(old) == "number") and old or 0, valueToSave)
			end)
		end)

		if success then
			local finalVal = (type(result) == "number") and result or valueToSave
			lastSavedPoints[userId] = finalVal
			updateLeaderboard(userId, finalVal)
			return true
		end

		if attempt < CONFIG.SAVE_RETRY_TIMES then
			task.wait(CONFIG.SAVE_RETRY_WAIT)
		end
	end

	warn("[BeeRescue] Save failed for userId:", userId)
	return false
end

local function savePoints(plr: Player, force: boolean?): boolean
	if not store then return true end

	local userId = plr.UserId
	local points = getPointsValue(plr)

	if not isLoaded(plr) and points <= 0 then return false end
	if not force and lastSavedPoints[userId] == points then return true end

	pendingPoints[userId] = points
	local success = savePointsCore(userId, points)

	if success and lastSavedPoints[userId] and lastSavedPoints[userId] > points then
		local v = getLeaderstatsPoints(plr)
		if v then v.Value = lastSavedPoints[userId] end
	end

	return success
end

local function loadPoints(plr: Player)
	if not store then
		setLoaded(plr, true)
		return
	end

	local userId = plr.UserId
	if loading[userId] then return end
	loading[userId] = true
	setLoaded(plr, false)

	local v = getLeaderstatsPoints(plr)
	if not v then
		loading[userId] = false
		return
	end

	local key = "U_" .. userId

	for attempt = 1, CONFIG.LOAD_RETRY_TIMES do
		local success, data = pcall(function()
			return store:GetAsync(key)
		end)

		if success then
			if type(data) == "number" and data > 0 then
				v.Value = data
			end
			lastSavedPoints[userId] = v.Value
			pendingPoints[userId] = v.Value
			setLoaded(plr, true)
			updateLeaderboard(userId, v.Value)
			loading[userId] = false
			return
		end

		if attempt < CONFIG.LOAD_RETRY_TIMES then
			task.wait(CONFIG.LOAD_RETRY_WAIT)
		end
	end

	warn("[BeeRescue] Load failed for:", plr.Name)
	loading[userId] = false

	task.delay(15, function()
		local p = Players:GetPlayerByUserId(userId)
		if p and not isLoaded(p) then
			loading[userId] = false
			loadPoints(p)
		end
	end)
end

-- ===== PROMPT & ZONE HOOKS =====
local hookedPrompts: {[ProximityPrompt]: boolean} = setmetatable({}, { __mode = "k" })

local function hookPrompt(prompt: ProximityPrompt)
	if hookedPrompts[prompt] then return end
	hookedPrompts[prompt] = true

	prompt.Triggered:Connect(function(plr)
		local ok, msg = startRun(plr)
		if not ok and msg then
			guiRemote:FireClient(plr, "ShowNotice", msg)
		end
	end)
end

local function scanForPrompts()
	for _, obj in workspace:GetDescendants() do
		if obj:IsA("ProximityPrompt") and obj.Name == CONFIG.START_PROMPT_NAME then
			hookPrompt(obj)
		end
	end
end

workspace.DescendantAdded:Connect(function(obj)
	if obj:IsA("ProximityPrompt") and obj.Name == CONFIG.START_PROMPT_NAME then
		hookPrompt(obj)
	end
end)

local function hookSummitZone()
	local zone = workspace:FindFirstChild(CONFIG.SUMMIT_ZONE_NAME, true)
	if not zone or not zone:IsA("BasePart") then
		task.delay(5, hookSummitZone)
		return
	end

	zone.CanCollide = false
	zone.CanTouch = true

	zone.Touched:Connect(function(hit: BasePart)
		if hit.Name ~= "HumanoidRootPart" then return end

		local char = hit.Parent
		local plr = char and Players:GetPlayerFromCharacter(char)
		if not plr then return end

		local hum = char:FindFirstChildOfClass("Humanoid")
		if not hum or hum.Health <= 0 then return end

		local now = os.clock()
		local last = touchDebounce[plr.UserId]
		if last and (now - last) < CONFIG.TOUCH_DEBOUNCE then return end
		touchDebounce[plr.UserId] = now

		completeRun(plr)
	end)
end

-- ===== PLAYER LIFECYCLE =====
Players.PlayerAdded:Connect(function(plr)
	ensureRun(plr)
	setRescueActive(plr, false)
	ensureColor(plr)
	setLoaded(plr, not CONFIG.SAVE_DATASTORE)

	task.defer(loadPoints, plr)

	plr.CharacterAdded:Connect(function(char)
		local hum = char:WaitForChild("Humanoid", 10)
		if hum then
			hum.Died:Connect(function()
				if ensureRun(plr).active then
					endRun(plr, "died")
					guiRemote:FireClient(plr, "ShowFailed", "Kamu mati! Lebah kecil tersesat...")
				end
			end)
		end
	end)
end)

Players.PlayerRemoving:Connect(function(plr)
	local userId = plr.UserId

	local st = runs[userId]
	if st and st.active then st.active = false end

	local points = getPointsValue(plr)
	if points > 0 then pendingPoints[userId] = points end

	savePoints(plr, true)

	local backup = pendingPoints[userId]
	if backup and backup > 0 then
		task.spawn(function()
			task.wait(0.3)
			savePointsCore(userId, backup)
		end)
	end

	task.delay(3, function()
		runs[userId] = nil
		touchDebounce[userId] = nil
		lastSavedPoints[userId] = nil
		pendingPoints[userId] = nil
		loadedOk[userId] = nil
		loading[userId] = nil
	end)
end)

-- ===== BIND TO CLOSE =====
game:BindToClose(function()
	local players = Players:GetPlayers()

	if RunService:IsStudio() then
		for _, plr in ipairs(players) do
			task.spawn(savePoints, plr, true)
		end
		task.wait(2)
		return
	end

	for i, plr in ipairs(players) do
		task.spawn(savePoints, plr, true)
		if i % 5 == 0 then task.wait(0.2) end
	end

	task.wait(6)
end)

-- ===== AUTO-SAVE =====
task.spawn(function()
	while true do
		task.wait(CONFIG.AUTO_SAVE_INTERVAL)

		local players = Players:GetPlayers()
		local toSave = {}

		for _, plr in ipairs(players) do
			if isLoaded(plr) then
				local current = getPointsValue(plr)
				local last = lastSavedPoints[plr.UserId] or 0
				if current > last then
					table.insert(toSave, plr)
				end
			end
		end

		for i, plr in ipairs(toSave) do
			task.spawn(savePoints, plr, false)
			if i % 3 == 0 then
				task.wait(CONFIG.SAVE_STAGGER_DELAY)
			end
		end
	end
end)

-- ===== INIT =====
scanForPrompts()
hookSummitZone()

print("[BeeRescue] Server ready! ?? (fixed: no double honey)")