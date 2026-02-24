--[[
    GamepassManager.lua (v11 - FIXED IsGifted)
    
    FIX LIST:
    • FIX: buildPassList sekarang kirim IsGifted ke client
    • Semua logic lain TIDAK BERUBAH
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local SS = game:GetService("ServerStorage")

local GamepassConfig = require(RS:WaitForChild("Modules"):WaitForChild("GamepassConfig"))
local LC = require(RS:WaitForChild("Modules"):WaitForChild("LocaleConfig"))

local Remotes = RS:WaitForChild("Remotes"):WaitForChild("TutorialRemotes")

local function ensureRemote(className, name)
	local existing = Remotes:FindFirstChild(name)
	if existing then return existing end
	local r = Instance.new(className)
	r.Name = name
	r.Parent = Remotes
	return r
end

local RequestGamepass = ensureRemote("RemoteFunction", "RequestGamepass")
local PromptGamepass = ensureRemote("RemoteEvent", "PromptGamepass")
local RefreshShop = ensureRemote("RemoteEvent", "RefreshShop")
local Notification = Remotes:WaitForChild("Notification")

local GM = {}
local Cache = {}
local CheckCooldown = {}

-----------------------------------------------
-- OWNERSHIP
-----------------------------------------------

local function queryOwnership(uid, passId)
	if passId <= 0 then return false end
	for attempt = 1, 3 do
		local ok, owns = pcall(function()
			return MarketplaceService:UserOwnsGamePassAsync(uid, passId)
		end)
		if ok then return owns end
		if attempt < 3 then task.wait(1) end
	end
	return nil
end

function GM.LoadAll(player)
	local uid = player.UserId
	Cache[uid] = {}

	local total = #GamepassConfig.Passes
	local done = 0

	for _, pass in ipairs(GamepassConfig.Passes) do
		task.spawn(function()
			local result = queryOwnership(uid, pass.GamepassId)
			if result ~= nil then
				Cache[uid][pass.Name] = result
			else
				-- nil = transient failure; keep existing value, schedule one delayed retry
				task.delay(10, function()
					if not Cache[uid] then return end
					local retry = queryOwnership(uid, pass.GamepassId)
					if retry ~= nil then
						Cache[uid][pass.Name] = retry
					end
				end)
			end
			done += 1
		end)
	end

	local t = tick()
	while done < total and (tick() - t) < 5 do
		task.wait(0.1)
	end
end

function GM.HasPass(player, passName)
	local uid = player.UserId
	-- 1. Cache dari MarketplaceService (player beli sendiri)
	if Cache[uid] and Cache[uid][passName] == true then
		return true
	end
	-- 2. Gift attribute (player dapat dari gift orang lain)
	if player:GetAttribute("GP_" .. passName) == true then
		return true
	end
	return false
end

function GM.RefreshPass(player, passName)
	local uid = player.UserId
	if not Cache[uid] then Cache[uid] = {} end
	local pass = GamepassConfig.ByName[passName]
	if not pass then return false end
	local result = queryOwnership(uid, pass.GamepassId)
	if result ~= nil then
		Cache[uid][passName] = result
	end
	return Cache[uid][passName] or false
end

-----------------------------------------------
-- MULTIPLIERS
-----------------------------------------------

function GM.GetHarvestMultiplier(player)
	local m = 1
	if GM.HasPass(player, "DoublePanen") then m += 1 end
	if GM.HasPass(player, "VIP") then m += 1 end
	return math.min(m, 3)
end

function GM.GetSellMultiplier(player)
	local m = 1
	if GM.HasPass(player, "DoubleSell") then m += 1 end
	if GM.HasPass(player, "VIP") then m += 1 end
	return math.min(m, 3)
end

function GM.GetXPMultiplier(player)
	local m = 1
	if GM.HasPass(player, "DoubleXP") then m += 1 end
	if GM.HasPass(player, "VIP") then m += 1 end
	return math.min(m, 3)
end

function GM.GetGrowthTimeMultiplier(player)
	return GM.HasPass(player, "FastGrow") and 0.5 or 1
end

function GM.GetRainMultiplier(player)
	return GM.HasPass(player, "RainLover") and 3 or 1.5
end

function GM.GetMaxCrops(player)
	return GM.HasPass(player, "ExtraSlots") and 25 or 15
end

function GM.HasAutoHarvest(player) return GM.HasPass(player, "AutoHarvest") end
function GM.HasBoombox(player) return GM.HasPass(player, "Boombox") end
function GM.IsVIP(player) return GM.HasPass(player, "VIP") end

-----------------------------------------------
-- ACTIVE BOOSTS
-----------------------------------------------

function GM.GetActiveBoosts(player)
	local b = {}

	local h = GM.GetHarvestMultiplier(player)
	if h > 1 then
		table.insert(b, {
			Icon = "🌾", Text = LC.GetFor(player, "Boost_Harvest", h),
			LocKey = "Boost_Harvest", Value = h, IsMax = h >= 3,
		})
	end

	local s = GM.GetSellMultiplier(player)
	if s > 1 then
		table.insert(b, {
			Icon = "💰", Text = LC.GetFor(player, "Boost_Sell", s),
			LocKey = "Boost_Sell", Value = s, IsMax = s >= 3,
		})
	end

	local x = GM.GetXPMultiplier(player)
	if x > 1 then
		table.insert(b, {
			Icon = "⭐", Text = LC.GetFor(player, "Boost_XP", x),
			LocKey = "Boost_XP", Value = x, IsMax = x >= 3,
		})
	end

	if GM.HasPass(player, "FastGrow") then
		table.insert(b, { Icon = "⚡", Text = LC.GetFor(player, "Boost_FastGrow"), LocKey = "Boost_FastGrow", Value = 0, IsMax = false })
	end
	if GM.HasPass(player, "ExtraSlots") then
		table.insert(b, { Icon = "📦", Text = LC.GetFor(player, "Boost_Slots"), LocKey = "Boost_Slots", Value = 0, IsMax = false })
	end
	if GM.HasPass(player, "RainLover") then
		table.insert(b, { Icon = "☔️", Text = LC.GetFor(player, "Boost_Rain"), LocKey = "Boost_Rain", Value = 0, IsMax = false })
	end
	if GM.HasPass(player, "AutoHarvest") then
		table.insert(b, { Icon = "🤖", Text = LC.GetFor(player, "Boost_Auto"), LocKey = "Boost_Auto", Value = 0, IsMax = false })
	end
	if GM.IsVIP(player) then
		table.insert(b, { Icon = "👑", Text = LC.GetFor(player, "Boost_VIP"), LocKey = "Boost_VIP", Value = 0, IsMax = false })
	end

	-- Tool buffs dari BuffManager
	if _G.BuffManager then
		local toolBuffs = _G.BuffManager.GetActiveToolBuffs(player)
		for _, tb in ipairs(toolBuffs) do
			table.insert(b, {
				Icon = tb.Icon,
				Text = LC.GetFor(player, tb.Key, tb.Value),
				LocKey = tb.Key, Value = tb.Value, IsMax = false,
			})
		end
	end

	return b
end

-----------------------------------------------
-- HELPERS — FIXED buildPassList
-----------------------------------------------

local function buildPassList(player)
	local list = {}
	local uid = player.UserId

	for _, pass in ipairs(GamepassConfig.Passes) do
		local owned = GM.HasPass(player, pass.Name)

		-- Tentukan apakah pass ini dari gift
		local isGifted = false
		if owned then
			local fromMarketplace = Cache[uid] and Cache[uid][pass.Name] == true
			local fromGift = player:GetAttribute("GP_" .. pass.Name) == true
			-- Gifted = punya via gift DAN bukan dari marketplace
			-- Jika punya keduanya, tetap anggap "owned" biasa (bukan gift badge)
			isGifted = fromGift and (not fromMarketplace)
		end

		table.insert(list, {
			Name = pass.Name,
			DisplayName = LC.GetFor(player, "Pass_" .. pass.Name),
			Desc = LC.GetFor(player, "Desc_" .. pass.Name),
			Icon = pass.Icon,
			Price = pass.Price,
			GamepassId = pass.GamepassId,
			Category = pass.Category,
			SortOrder = pass.SortOrder,
			Owned = owned,
			IsGifted = isGifted,
		})
	end
	table.sort(list, function(a, b) return a.SortOrder < b.SortOrder end)
	return list
end

local function syncVIPAttribute(player)
	player:SetAttribute("IsVIP", GM.IsVIP(player))
end

local function grantBoombox(player)
	if not GM.HasBoombox(player) then return end
	local tf = SS:FindFirstChild("Tools")
	if not tf then return end
	local bb = tf:FindFirstChild("Boombox")
	if not bb or not bb:IsA("Tool") then return end

	local function has(p)
		if not p then return false end
		for _, it in ipairs(p:GetChildren()) do
			if it:IsA("Tool") and it.Name == "Boombox" then return true end
		end
		return false
	end

	local sg = player:FindFirstChild("StarterGear")
	local bp = player:FindFirstChild("Backpack")
	local ch = player.Character
	if sg and not has(sg) then bb:Clone().Parent = sg end
	if bp and not has(bp) and not has(ch) then bb:Clone().Parent = bp end
end

-----------------------------------------------
-- INIT
-----------------------------------------------

function GM.Init()
	-----------------------------------------------
	-- REMOTE HANDLER
	-----------------------------------------------

	RequestGamepass.OnServerInvoke = function(player, action, passName)
		if type(action) ~= "string" then return { Success = false } end
		local uid = player.UserId

		if action == "GET_LIST" then
			return {
				Success = true,
				Passes = buildPassList(player),
				Boosts = GM.GetActiveBoosts(player),
			}

		elseif action == "PROMPT" then
			if type(passName) ~= "string" then return { Success = false } end
			local pass = GamepassConfig.ByName[passName]
			if not pass then return { Success = false } end
			if GM.HasPass(player, passName) then return { Success = false } end
			pcall(function()
				MarketplaceService:PromptGamePassPurchase(player, pass.GamepassId)
			end)
			return { Success = true }

		elseif action == "CHECK" then
			if CheckCooldown[uid] and (tick() - CheckCooldown[uid]) < 3 then
				return { Success = true, Owned = GM.HasPass(player, passName) }
			end
			CheckCooldown[uid] = tick()
			if type(passName) ~= "string" then return { Success = false } end
			local owns = GM.RefreshPass(player, passName)
			if passName == "VIP" then syncVIPAttribute(player) end
			return { Success = true, Owned = owns }

		elseif action == "GET_BOOSTS" then
			return { Success = true, Boosts = GM.GetActiveBoosts(player) }
		end

		return { Success = false }
	end

	-----------------------------------------------
	-- PURCHASE CALLBACK
	-----------------------------------------------

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
		if not purchased then return end
		local uid = player.UserId
		if not Cache[uid] then Cache[uid] = {} end

		local passInfo = GamepassConfig.ById[passId]
		if not passInfo then return end

		Cache[uid][passInfo.Name] = true
		if passInfo.Name == "VIP" then syncVIPAttribute(player) end
		if passInfo.Name == "Boombox" then grantBoombox(player) end

		local passDisplayName = LC.GetFor(player, "Pass_" .. passInfo.Name)
		Notification:FireClient(player,
			string.format(LC.GetFor(player, "GPActivated"), passInfo.Icon, passDisplayName))

		RefreshShop:FireClient(player, {
			Passes = buildPassList(player),
			Boosts = GM.GetActiveBoosts(player),
		})

		task.delay(1.5, function()
			if not player or not player.Parent then return end
			local st = {}
			if GM.GetHarvestMultiplier(player) >= 3 then
				table.insert(st, "🌾 " .. LC.GetFor(player, "Boost_Harvest", 3))
			end
			if GM.GetSellMultiplier(player) >= 3 then
				table.insert(st, "💰 " .. LC.GetFor(player, "Boost_Sell", 3))
			end
			if GM.GetXPMultiplier(player) >= 3 then
				table.insert(st, "⭐ " .. LC.GetFor(player, "Boost_XP", 3))
			end
			if #st > 0 then
				Notification:FireClient(player, "🔥 STACK! " .. table.concat(st, " | ") .. " — MAX!")
			end
		end)
	end)

	-----------------------------------------------
	-- LIFECYCLE
	-----------------------------------------------

	local function onPlayerAdded(player)
		GM.LoadAll(player)

		-- Delay syncVIPAttribute sedikit agar gift attributes punya waktu di-restore
		task.delay(3, function()
			if player and player.Parent then
				syncVIPAttribute(player)
			end
		end)

		player.CharacterAdded:Connect(function()
			task.wait(2)
			if GM.HasBoombox(player) then grantBoombox(player) end
		end)

		if player.Character then
			task.spawn(function()
				task.wait(2)
				if GM.HasBoombox(player) then grantBoombox(player) end
			end)
		end
	end

	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, p in ipairs(Players:GetPlayers()) do
		task.spawn(function() onPlayerAdded(p) end)
	end

	Players.PlayerRemoving:Connect(function(player)
		Cache[player.UserId] = nil
		CheckCooldown[player.UserId] = nil
	end)

	print("[GamepassManager] Initialized successfully")
end

return GM
