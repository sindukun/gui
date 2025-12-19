-- DailyQuestServer.lua (UPDATED)
-- Server script untuk sistem Daily Quest (Mount Semut)
-- ? HoneyMultiplier mempengaruhi honey dari BeeRescue point (bonus harian)
-- ? Tetap aman (DataStore + autosave)
-- Taruh sebagai Script di ServerScriptService

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")

-- =============================
-- CONFIG
-- =============================
local CONFIG = {
	DATASTORE_NAME = "DailyQuestData_v1",
	AUTOSAVE_SEC = 60,

	-- Quest 1: Bee Rescue (1x claim / day)
	QUEST1_TARGET = 1,
	QUEST1_REWARD = 3,

	-- Quest 2: Playtime (10 minutes)
	QUEST2_TARGET_SEC = 600,
	QUEST2_REWARD = 2,

	-- Bee rescue bonus honey (per rescue, max per day)
	BEE_BONUS_PER_RESCUE = 1,
	BEE_BONUS_MAX_PER_DAY = 10,
}

local store = DataStoreService:GetDataStore(CONFIG.DATASTORE_NAME)

-- =============================
-- REMOTES / BINDABLE
-- =============================
local function setupRemotes()
	local remote = ReplicatedStorage:FindFirstChild("DailyQuest_Remote")
	if not remote then
		remote = Instance.new("RemoteEvent")
		remote.Name = "DailyQuest_Remote"
		remote.Parent = ReplicatedStorage
	end

	local fn = ReplicatedStorage:FindFirstChild("DailyQuest_Function")
	if not fn then
		fn = Instance.new("RemoteFunction")
		fn.Name = "DailyQuest_Function"
		fn.Parent = ReplicatedStorage
	end

	local bind = ReplicatedStorage:FindFirstChild("DailyQuest_BeeRescued")
	if not bind then
		bind = Instance.new("BindableEvent")
		bind.Name = "DailyQuest_BeeRescued"
		bind.Parent = ReplicatedStorage
	end

	return remote, fn, bind
end

local DailyQuestRemote, DailyQuestFunction, DailyQuestBindable = setupRemotes()

-- =============================
-- STATE
-- =============================
type PlayerQuestData = {
	dayKey: string,
	quest1Progress: number,
	quest1Target: number,
	quest1Claimed: boolean,
	quest1Reward: number,

	quest2Progress: number,
	quest2Target: number,
	quest2Claimed: boolean,
	quest2Reward: number,

	rescueBonusEarned: number,
	rescueBonusMax: number,

	honeyPoints: number,
	lastSave: number,
}

local dataByUserId: {[number]: PlayerQuestData} = {}
local saveInFlight: {[number]: boolean} = {}

-- =============================
-- HELPERS
-- =============================
local function getDayKeyUTC(): string
	-- Daily reset berbasis UTC (stabil). Kalau mau WIB reset, nanti kita ubah bareng.
	local t = os.date("!*t")
	return string.format("%04d-%02d-%02d", t.year, t.month, t.day)
end

local function secondsUntilNextUTCReset(): number
	local now = os.time(os.date("!*t"))
	local t = os.date("!*t")
	t.hour, t.min, t.sec = 0, 0, 0
	local todayStart = os.time(t)
	local nextReset = todayStart + 24 * 60 * 60
	return math.max(0, nextReset - now)
end

local function formatHHMMSS(seconds: number): string
	local h = math.floor(seconds / 3600)
	local m = math.floor((seconds % 3600) / 60)
	local s = math.floor(seconds % 60)
	return string.format("%02d:%02d:%02d", h, m, s)
end

local function defaultData(): PlayerQuestData
	return {
		dayKey = getDayKeyUTC(),

		quest1Progress = 0,
		quest1Target = CONFIG.QUEST1_TARGET,
		quest1Claimed = false,
		quest1Reward = CONFIG.QUEST1_REWARD,

		quest2Progress = 0,
		quest2Target = CONFIG.QUEST2_TARGET_SEC,
		quest2Claimed = false,
		quest2Reward = CONFIG.QUEST2_REWARD,

		rescueBonusEarned = 0,
		rescueBonusMax = CONFIG.BEE_BONUS_MAX_PER_DAY,

		honeyPoints = 0,
		lastSave = os.time(),
	}
end

local function ensureReset(d: PlayerQuestData)
	local today = getDayKeyUTC()
	if d.dayKey == today then return end

	-- Reset daily progress
	d.dayKey = today

	d.quest1Progress = 0
	d.quest1Claimed = false

	d.quest2Progress = 0
	d.quest2Claimed = false

	d.rescueBonusEarned = 0
	-- honeyPoints tidak di-reset (mata uang)
end

local function clonePublic(d: PlayerQuestData)
	return {
		quest1Progress = d.quest1Progress,
		quest1Target = d.quest1Target,
		quest1Claimed = d.quest1Claimed,
		quest1Reward = d.quest1Reward,

		quest2Progress = d.quest2Progress,
		quest2Target = d.quest2Target,
		quest2Claimed = d.quest2Claimed,
		quest2Reward = d.quest2Reward,

		rescueBonusEarned = d.rescueBonusEarned,
		rescueBonusMax = d.rescueBonusMax,

		honeyPoints = d.honeyPoints,
		resetTimer = formatHHMMSS(secondsUntilNextUTCReset()),
	}
end

-- =============================
-- DATASTORE
-- =============================
local function loadPlayer(plr: Player)
	local userId = plr.UserId
	local d = defaultData()

	local ok, saved = pcall(function()
		return store:GetAsync(tostring(userId))
	end)

	if ok and type(saved) == "table" then
		for k, v in pairs(saved) do
			d[k] = v
		end
	end

	-- repair / clamp
	d.quest1Target = CONFIG.QUEST1_TARGET
	d.quest1Reward = CONFIG.QUEST1_REWARD
	d.quest2Target = CONFIG.QUEST2_TARGET_SEC
	d.quest2Reward = CONFIG.QUEST2_REWARD
	d.rescueBonusMax = CONFIG.BEE_BONUS_MAX_PER_DAY

	d.quest1Progress = math.max(0, tonumber(d.quest1Progress) or 0)
	d.quest2Progress = math.max(0, tonumber(d.quest2Progress) or 0)
	d.rescueBonusEarned = math.max(0, tonumber(d.rescueBonusEarned) or 0)
	d.honeyPoints = math.max(0, tonumber(d.honeyPoints) or 0)

	ensureReset(d)

	dataByUserId[userId] = d
	plr:SetAttribute("HoneyPoints", d.honeyPoints)

	-- initial push
	DailyQuestRemote:FireClient(plr, "InitData", clonePublic(d))
end

local function savePlayer(userId: number, force: boolean?)
	if saveInFlight[userId] then return end
	local d = dataByUserId[userId]
	if not d then return end

	local now = os.time()
	if not force and (now - (d.lastSave or 0)) < CONFIG.AUTOSAVE_SEC then
		return
	end

	saveInFlight[userId] = true
	d.lastSave = now

	local payload = table.clone(d)
	-- jangan simpan field runtime kalau kamu tambah nanti

	task.spawn(function()
		local ok, err = pcall(function()
			store:SetAsync(tostring(userId), payload)
		end)
		if not ok then
			warn("[DailyQuest] Save failed for", userId, err)
		end
		saveInFlight[userId] = nil
	end)
end

-- =============================
-- CORE LOGIC
-- =============================
local function applyHoneyMultiplier(plr: Player, base: number): number
	local mult = tonumber(plr:GetAttribute("HoneyMultiplier")) or 1
	if mult < 1 then mult = 1 end
	if mult > 10 then mult = 10 end
	return base * mult
end

local function onBeeRescued(plr: Player)
	local d = dataByUserId[plr.UserId]
	if not d then return end

	ensureReset(d)

	-- quest1 progress
	if not d.quest1Claimed and d.quest1Progress < d.quest1Target then
		d.quest1Progress = math.min(d.quest1Target, d.quest1Progress + 1)
	end

	-- bonus honey per rescue (capped per day) + multiplier
	if d.rescueBonusEarned < d.rescueBonusMax then
		local remaining = d.rescueBonusMax - d.rescueBonusEarned
		local baseGain = CONFIG.BEE_BONUS_PER_RESCUE
		local gain = applyHoneyMultiplier(plr, baseGain)
		gain = math.max(0, math.min(remaining, gain))

		if gain > 0 then
			d.rescueBonusEarned += gain
			d.honeyPoints += gain
			plr:SetAttribute("HoneyPoints", d.honeyPoints)

			DailyQuestRemote:FireClient(plr, "BeeRescueUpdate", {
				quest1Progress = d.quest1Progress,
				rescueBonusEarned = d.rescueBonusEarned,
				honeyPoints = d.honeyPoints,
			})
		else
			-- still update quest1 progress if needed
			DailyQuestRemote:FireClient(plr, "BeeRescueUpdate", {
				quest1Progress = d.quest1Progress,
				rescueBonusEarned = d.rescueBonusEarned,
				honeyPoints = d.honeyPoints,
			})
		end
	else
		-- bonus already maxed, but quest progress might change
		DailyQuestRemote:FireClient(plr, "BeeRescueUpdate", {
			quest1Progress = d.quest1Progress,
			rescueBonusEarned = d.rescueBonusEarned,
			honeyPoints = d.honeyPoints,
		})
	end
end

local function updatePlaytime(plr: Player, delta: number)
	local d = dataByUserId[plr.UserId]
	if not d then return end

	ensureReset(d)

	if not d.quest2Claimed and d.quest2Progress < d.quest2Target then
		d.quest2Progress = math.min(d.quest2Target, d.quest2Progress + delta)
		DailyQuestRemote:FireClient(plr, "PlaytimeUpdate", {
			progress = d.quest2Progress,
			target = d.quest2Target,
		})
	end
end

local function claimQuest(plr: Player, questId: number)
	local d = dataByUserId[plr.UserId]
	if not d then
		return {success = false, reason = "NoData"}
	end

	ensureReset(d)

	if questId == 1 then
		if d.quest1Claimed then
			return {success = false, reason = "AlreadyClaimed"}
		end
		if d.quest1Progress < d.quest1Target then
			return {success = false, reason = "NotComplete"}
		end

		d.quest1Claimed = true
		d.honeyPoints += d.quest1Reward
		plr:SetAttribute("HoneyPoints", d.honeyPoints)
		DailyQuestRemote:FireClient(plr, "HoneyUpdate", d.honeyPoints)
		savePlayer(plr.UserId, true)

		return {success = true, honeyPoints = d.honeyPoints}

	elseif questId == 2 then
		if d.quest2Claimed then
			return {success = false, reason = "AlreadyClaimed"}
		end
		if d.quest2Progress < d.quest2Target then
			return {success = false, reason = "NotComplete"}
		end

		d.quest2Claimed = true
		d.honeyPoints += d.quest2Reward
		plr:SetAttribute("HoneyPoints", d.honeyPoints)
		DailyQuestRemote:FireClient(plr, "HoneyUpdate", d.honeyPoints)
		savePlayer(plr.UserId, true)

		return {success = true, honeyPoints = d.honeyPoints}
	end

	return {success = false, reason = "InvalidQuest"}
end

-- =============================
-- PUBLIC API (for other server scripts)
-- =============================
_G.DailyQuestAPI = {
	GetPlayerData = function(plr: Player)
		local d = dataByUserId[plr.UserId]
		if not d then return nil end
		ensureReset(d)
		return d
	end,

	AddHoney = function(plr: Player, amount: number)
		local d = dataByUserId[plr.UserId]
		if not d then return false end
		ensureReset(d)
		amount = math.max(0, tonumber(amount) or 0)
		if amount <= 0 then return true end
		d.honeyPoints += amount
		plr:SetAttribute("HoneyPoints", d.honeyPoints)
		DailyQuestRemote:FireClient(plr, "HoneyUpdate", d.honeyPoints)
		savePlayer(plr.UserId, false)
		return true
	end,

	DeductHoney = function(plr: Player, amount: number)
		local d = dataByUserId[plr.UserId]
		if not d then return false end
		ensureReset(d)
		amount = math.max(0, tonumber(amount) or 0)
		if amount <= 0 then return true end
		if d.honeyPoints < amount then return false end
		d.honeyPoints -= amount
		plr:SetAttribute("HoneyPoints", d.honeyPoints)
		DailyQuestRemote:FireClient(plr, "HoneyUpdate", d.honeyPoints)
		savePlayer(plr.UserId, false)
		return true
	end,
}

-- Bindable integration: BeeRescue_Server.lua akan Fire(plr) ke bindable ini
DailyQuestBindable.Event:Connect(function(plr: Player)
	if typeof(plr) == "Instance" and plr:IsA("Player") then
		onBeeRescued(plr)
	end
end)

-- =============================
-- REMOTE FUNCTION
-- =============================
DailyQuestFunction.OnServerInvoke = function(plr: Player, action: string, a, b)
	local d = dataByUserId[plr.UserId]
	if not d then
		loadPlayer(plr)
		d = dataByUserId[plr.UserId]
	end
	if not d then
		return {success = false, reason = "NoData"}
	end

	ensureReset(d)

	if action == "GetData" then
		return clonePublic(d)
	end

	if action == "ClaimQuest" then
		return claimQuest(plr, tonumber(a) or 0)
	end

	return {success = false, reason = "InvalidAction"}
end

-- =============================
-- PLAYER LIFECYCLE
-- =============================
Players.PlayerAdded:Connect(function(plr)
	loadPlayer(plr)
end)

Players.PlayerRemoving:Connect(function(plr)
	savePlayer(plr.UserId, true)
	dataByUserId[plr.UserId] = nil
	saveInFlight[plr.UserId] = nil
end)

game:BindToClose(function()
	for _, plr in ipairs(Players:GetPlayers()) do
		savePlayer(plr.UserId, true)
	end
	task.wait(1)
end)

-- =============================
-- HEARTBEAT LOOP
-- =============================
task.spawn(function()
	local lastTimerSend = 0
	while true do
		task.wait(1)

		local players = Players:GetPlayers()
		if #players == 0 then
			continue
		end

		for _, plr in ipairs(players) do
			updatePlaytime(plr, 1)
		end

		-- broadcast reset timer (every 1s; ringan)
		local now = os.clock()
		if (now - lastTimerSend) >= 1 then
			lastTimerSend = now
			local t = formatHHMMSS(secondsUntilNextUTCReset())
			for _, plr in ipairs(players) do
				DailyQuestRemote:FireClient(plr, "ResetTimer", t)
			end
		end

		-- autosave throttle
		for _, plr in ipairs(players) do
			savePlayer(plr.UserId, false)
		end
	end
end)

