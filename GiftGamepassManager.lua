--[[
    GiftGamepassManager.lua (v6 - BULLETPROOF + CANCEL DETECTION)
    
    FIX dari v5:
    • FIX #1: Pending dihapus SETELAH semua grant/save sukses, bukan sebelum
    • FIX #2: PROMPT_GIFT cek pending aktif — tidak bisa ditimpa
    • FIX #3: Semua DM.Save() dibungkus pcall
    • FIX #4: Offline recipient oldData nil → return nil (batal, retry)
    • FIX #5: HandleReceipt full pcall-safe — tidak pernah throw error ke caller
    • FIX #6: PromptProductPurchaseFinished listener dengan grace period
             → detect purchase cancel → bersihkan pending → notify client
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")

local GamepassConfig = require(RS:WaitForChild("Modules"):WaitForChild("GamepassConfig"))
local LC = require(RS:WaitForChild("Modules"):WaitForChild("LocaleConfig"))

local Remotes = RS:WaitForChild("Remotes"):WaitForChild("TutorialRemotes")

local PREFIX = GamepassConfig.GIFT_ATTRIBUTE_PREFIX or "GP_"

local function ensureRemote(className, name)
	local existing = Remotes:FindFirstChild(name)
	if existing then return existing end
	local r = Instance.new(className)
	r.Name = name
	r.Parent = Remotes
	return r
end

local RequestGift  = ensureRemote("RemoteFunction", "RequestGift")
local GiftNotify   = ensureRemote("RemoteEvent", "GiftNotify")
local Notification = Remotes:WaitForChild("Notification")
local RefreshShop  = Remotes:FindFirstChild("RefreshShop")

local DM  -- DataManager
local GM  -- GamepassManager

local GiftMgr = {}

-----------------------------------------------
-- PERSISTENT PENDING STORE
-----------------------------------------------

local PendingStore = DataStoreService:GetDataStore("GiftPending_v1")

-----------------------------------------------
-- STATE
-----------------------------------------------

local PendingGifts = {}
local Cooldowns    = {}
local COOLDOWN     = 3
local PENDING_TTL  = 600
local GRACE_PERIOD = 5  -- detik grace period sebelum cancel dianggap valid

local MainStore = DataStoreService:GetDataStore("FarmGame_v12")

-----------------------------------------------
-- HELPERS
-----------------------------------------------

local function now()
	return workspace:GetServerTimeNow()
end

local function isOnCooldown(uid)
	local t = Cooldowns[uid]
	return t and (now() - t) < COOLDOWN
end

local function getAttrName(passName)
	return PREFIX .. passName
end

-----------------------------------------------
-- PENDING: SAVE & LOAD dari DataStore
-----------------------------------------------

local function savePendingToStore(senderUid, pendingData)
	local ok, err = pcall(function()
		PendingStore:SetAsync("pending_" .. tostring(senderUid), pendingData)
	end)
	if not ok then
		warn("[GiftMgr] Failed to save pending to store:", err)
	end
end

local function loadPendingFromStore(senderUid)
	local ok, data = pcall(function()
		return PendingStore:GetAsync("pending_" .. tostring(senderUid))
	end)
	if ok and data and type(data) == "table" then
		return data
	end
	return nil
end

local function clearPendingFromStore(senderUid)
	pcall(function()
		PendingStore:RemoveAsync("pending_" .. tostring(senderUid))
	end)
end

-----------------------------------------------
-- FIX #2: Cek apakah ada pending aktif yang masih fresh
-----------------------------------------------

local function hasActivePending(uid)
	-- Cek memory
	local mem = PendingGifts[uid]
	if mem and (now() - mem.Timestamp) < PENDING_TTL then
		return true
	end
	-- Cek DataStore
	local stored = loadPendingFromStore(uid)
	if stored and stored.Timestamp and (now() - stored.Timestamp) < PENDING_TTL then
		return true
	end
	return false
end

-----------------------------------------------
-- CANCEL PENDING HELPER
-- Dipakai oleh PromptProductPurchaseFinished
-----------------------------------------------

local function cancelPending(userId, productId)
	PendingGifts[userId] = nil
	clearPendingFromStore(userId)
	Cooldowns[userId] = nil

	local player = Players:GetPlayerByUserId(userId)
	if player and player.Parent then
		pcall(function()
			GiftNotify:FireClient(player, {
				Type = "GIFT_CANCELLED",
			})
		end)
	end
end

-----------------------------------------------
-- ATTRIBUTE MANAGEMENT
-----------------------------------------------

local function setGiftAttribute(player, passName, value)
	player:SetAttribute(getAttrName(passName), value)
end

local function restoreGiftAttributes(player)
	local data = DM.Get(player)
	if not data or not data.GiftedPasses then return end
	for passName, _ in pairs(data.GiftedPasses) do
		if GamepassConfig.ByName[passName] then
			setGiftAttribute(player, passName, true)
		end
	end
	if data.GiftedPasses["VIP"] then
		player:SetAttribute("IsVIP", true)
	end
end

-----------------------------------------------
-- DATASTORE: SAVE GIFT (online recipient)
-- FIX #3: return false jika DM.Save gagal
-----------------------------------------------

local function saveGiftToRecipient(recipient, passName, senderUid, senderName)
	local data = DM.Get(recipient)
	if not data then return false end

	if not data.GiftedPasses then data.GiftedPasses = {} end

	data.GiftedPasses[passName] = {
		SenderUid  = senderUid,
		SenderName = senderName,
		Timestamp  = math.floor(now()),
	}

	if not data.GiftHistory then data.GiftHistory = { Sent = {}, Received = {} } end
	if not data.GiftHistory.Received then data.GiftHistory.Received = {} end

	table.insert(data.GiftHistory.Received, {
		PassName   = passName,
		SenderName = senderName,
		SenderUid  = senderUid,
		Timestamp  = math.floor(now()),
	})

	while #data.GiftHistory.Received > 50 do
		table.remove(data.GiftHistory.Received, 1)
	end

	local ok, err = pcall(function()
		DM.Save(recipient)
	end)

	if not ok then
		warn("[GiftMgr] DM.Save failed for recipient:", err)
		return false
	end

	return true
end

-----------------------------------------------
-- DATASTORE: SAVE GIFT (offline recipient)
-- FIX #4: oldData nil → return nil (batal UpdateAsync)
-----------------------------------------------

local function saveGiftToOfflineRecipient(recipientUid, passName, senderUid, senderName)
	local ok, err = pcall(function()
		local recipientKey = "player_" .. tostring(recipientUid)
		MainStore:UpdateAsync(recipientKey, function(oldData)
			if type(oldData) ~= "table" then
				warn("[GiftMgr] Offline recipient has no existing data — aborting UpdateAsync")
				return nil
			end

			if not oldData.GiftedPasses then oldData.GiftedPasses = {} end
			oldData.GiftedPasses[passName] = {
				SenderUid  = senderUid,
				SenderName = senderName,
				Timestamp  = math.floor(now()),
			}

			if not oldData.GiftHistory then oldData.GiftHistory = { Sent = {}, Received = {} } end
			if not oldData.GiftHistory.Received then oldData.GiftHistory.Received = {} end

			table.insert(oldData.GiftHistory.Received, {
				PassName   = passName,
				SenderName = senderName,
				SenderUid  = senderUid,
				Timestamp  = math.floor(now()),
			})

			while #oldData.GiftHistory.Received > 50 do
				table.remove(oldData.GiftHistory.Received, 1)
			end

			return oldData
		end)
	end)

	if not ok then
		warn("[GiftMgr] CRITICAL: Failed to save gift for offline recipient:", err)
		return false
	end
	return true
end

-----------------------------------------------
-- DATASTORE: SAVE SENT HISTORY
-- FIX #3: pcall DM.Save
-----------------------------------------------

local function saveSentHistory(sender, passName, recipientName, recipientUid)
	local data = DM.Get(sender)
	if not data then return end

	if not data.GiftHistory then data.GiftHistory = { Sent = {}, Received = {} } end
	if not data.GiftHistory.Sent then data.GiftHistory.Sent = {} end

	table.insert(data.GiftHistory.Sent, {
		PassName      = passName,
		RecipientName = recipientName,
		RecipientUid  = recipientUid,
		Timestamp     = math.floor(now()),
	})

	while #data.GiftHistory.Sent > 50 do
		table.remove(data.GiftHistory.Sent, 1)
	end

	pcall(function()
		DM.Save(sender)
	end)
end

-----------------------------------------------
-- SAVE SENT HISTORY (offline sender)
-----------------------------------------------

local function saveSentHistoryOffline(senderUid, passName, recipientName, recipientUid)
	pcall(function()
		local senderKey = "player_" .. tostring(senderUid)
		MainStore:UpdateAsync(senderKey, function(oldData)
			if type(oldData) ~= "table" then return nil end

			if not oldData.GiftHistory then oldData.GiftHistory = { Sent = {}, Received = {} } end
			if not oldData.GiftHistory.Sent then oldData.GiftHistory.Sent = {} end

			table.insert(oldData.GiftHistory.Sent, {
				PassName      = passName,
				RecipientName = recipientName,
				RecipientUid  = recipientUid,
				Timestamp     = math.floor(now()),
			})

			while #oldData.GiftHistory.Sent > 50 do
				table.remove(oldData.GiftHistory.Sent, 1)
			end

			return oldData
		end)
	end)
end

-----------------------------------------------
-- CHECK GIFTED
-----------------------------------------------

function GiftMgr.HasGiftedPass(player, passName)
	return player:GetAttribute(getAttrName(passName)) == true
end

-----------------------------------------------
-- HANDLE RECEIPT
-- FIX #1: Pending dihapus SETELAH grant sukses
-- FIX #5: Seluruh body di-pcall
-----------------------------------------------

function GiftMgr.HandleReceipt(receiptInfo)
	local buyerUid  = receiptInfo.PlayerId
	local productId = receiptInfo.ProductId

	local passInfo = GamepassConfig.ByGiftProductId and GamepassConfig.ByGiftProductId[productId]
	if not passInfo then
		return nil
	end

	local success, result = pcall(function()

		local pending = PendingGifts[buyerUid]

		if not pending or pending.PassName ~= passInfo.Name then
			pending = loadPendingFromStore(buyerUid)
		end

		if not pending or pending.PassName ~= passInfo.Name then
			warn("[GiftMgr] ProcessReceipt: no matching pending for uid", buyerUid, "product", productId)
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end

		local sender = Players:GetPlayerByUserId(buyerUid)
		local senderName = pending.SenderName or "???"
		if sender and sender.Parent then
			senderName = sender.DisplayName
		end

		local recipient = Players:GetPlayerByUserId(pending.RecipientUid)
		local recipientOnline = recipient and recipient.Parent

		-- ============================
		-- GRANT GIFT
		-- ============================

		if recipientOnline then
			setGiftAttribute(recipient, passInfo.Name, true)
			local saved = saveGiftToRecipient(recipient, passInfo.Name, buyerUid, senderName)

			if not saved then
				warn("[GiftMgr] saveGiftToRecipient failed — keeping pending for retry")
				return Enum.ProductPurchaseDecision.NotProcessedYet
			end

			if passInfo.Name == "VIP" then
				recipient:SetAttribute("IsVIP", true)
			end

			pcall(function()
				local passDisplayR = LC.GetFor(recipient, "Pass_" .. passInfo.Name)
				Notification:FireClient(recipient,
					LC.GetFor(recipient, "GiftReceived", senderName, passInfo.Icon, passDisplayR))

				GiftNotify:FireClient(recipient, {
					Type       = "GIFT_RECEIVED",
					PassName   = passInfo.Name,
					PassIcon   = passInfo.Icon,
					SenderName = senderName,
				})
			end)

			pcall(function()
				if GM and GM.RefreshPass then
					GM.RefreshPass(recipient, passInfo.Name)
				end
			end)

			pcall(function()
				DM.SyncLeaderstats(recipient)
			end)
		else
			warn("[GiftMgr] Recipient", pending.RecipientName, "(uid:", pending.RecipientUid, ") offline — saving to DataStore")
			local saved = saveGiftToOfflineRecipient(
				pending.RecipientUid, passInfo.Name, buyerUid, senderName)

			if not saved then
				warn("[GiftMgr] CRITICAL: saveGiftToOfflineRecipient failed — keeping pending for retry")
				return Enum.ProductPurchaseDecision.NotProcessedYet
			end
		end

		-- ============================
		-- GRANT SUKSES — BARU hapus pending
		-- ============================
		PendingGifts[buyerUid] = nil
		clearPendingFromStore(buyerUid)

		-- ============================
		-- NOTIFY SENDER
		-- ============================
		pcall(function()
			if sender and sender.Parent then
				GiftNotify:FireClient(sender, {
					Type          = "GIFT_SENT_OK",
					PassName      = passInfo.Name,
					PassIcon      = passInfo.Icon,
					RecipientUid  = pending.RecipientUid,
					RecipientName = pending.RecipientName,
				})
			end
		end)

		-- ============================
		-- SAVE SENT HISTORY (non-critical)
		-- ============================
		pcall(function()
			if sender and sender.Parent then
				local passDisplayS = LC.GetFor(sender, "Pass_" .. passInfo.Name)
				Notification:FireClient(sender,
					LC.GetFor(sender, "GiftSentOk", passInfo.Icon, passDisplayS, pending.RecipientName))
				saveSentHistory(sender, passInfo.Name, pending.RecipientName, pending.RecipientUid)
				DM.SyncLeaderstats(sender)
			else
				saveSentHistoryOffline(buyerUid, passInfo.Name, pending.RecipientName, pending.RecipientUid)
			end
		end)

		return Enum.ProductPurchaseDecision.PurchaseGranted
	end)

	if not success then
		warn("[GiftMgr] HandleReceipt ERROR:", result)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	return result
end

-----------------------------------------------
-- BUILD LISTS
-----------------------------------------------

local function buildPlayerList(sender)
	local list = {}
	local sUid = sender.UserId
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr.UserId ~= sUid then
			table.insert(list, {
				UserId      = plr.UserId,
				DisplayName = plr.DisplayName,
				Username    = plr.Name,
			})
		end
	end
	table.sort(list, function(a, b) return a.DisplayName < b.DisplayName end)
	return list
end

local function buildGiftableList(sender, recipient)
	local list = {}
	for _, pass in ipairs(GamepassConfig.Passes) do
		if pass.Giftable == false then continue end
		if not pass.GiftProductId or pass.GiftProductId <= 0 then continue end

		local recipientOwns = GM.HasPass(recipient, pass.Name)
			or GiftMgr.HasGiftedPass(recipient, pass.Name)

		table.insert(list, {
			Name          = pass.Name,
			DisplayName   = LC.GetFor(sender, "Pass_" .. pass.Name),
			Desc          = LC.GetFor(sender, "Desc_" .. pass.Name),
			Icon          = pass.Icon,
			Price         = pass.Price,
			Category      = pass.Category,
			SortOrder     = pass.SortOrder,
			RecipientOwns = recipientOwns,
		})
	end
	table.sort(list, function(a, b) return a.SortOrder < b.SortOrder end)
	return list
end

-----------------------------------------------
-- GIFT HISTORY
-----------------------------------------------

local function getHistory(player)
	local data = DM.Get(player)
	if not data or not data.GiftHistory then
		return { Sent = {}, Received = {} }
	end

	local sent = {}
	local rawS = data.GiftHistory.Sent or {}
	for i = #rawS, math.max(1, #rawS - 19), -1 do
		local e = rawS[i]
		if e then
			local cfg = GamepassConfig.ByName[e.PassName]
			table.insert(sent, {
				PassName      = e.PassName,
				PassDisplay   = LC.GetFor(player, "Pass_" .. e.PassName),
				PassIcon      = cfg and cfg.Icon or "🎮",
				RecipientName = e.RecipientName,
				Timestamp     = e.Timestamp,
			})
		end
	end

	local received = {}
	local rawR = data.GiftHistory.Received or {}
	for i = #rawR, math.max(1, #rawR - 19), -1 do
		local e = rawR[i]
		if e then
			local cfg = GamepassConfig.ByName[e.PassName]
			table.insert(received, {
				PassName    = e.PassName,
				PassDisplay = LC.GetFor(player, "Pass_" .. e.PassName),
				PassIcon    = cfg and cfg.Icon or "🎮",
				SenderName  = e.SenderName,
				Timestamp   = e.Timestamp,
			})
		end
	end

	return { Sent = sent, Received = received }
end

-----------------------------------------------
-- GC
-----------------------------------------------

local function gcPendings()
	local t = now()
	for uid, p in pairs(PendingGifts) do
		if (t - p.Timestamp) > PENDING_TTL then
			PendingGifts[uid] = nil
			clearPendingFromStore(uid)
		end
	end
	for uid, t2 in pairs(Cooldowns) do
		if (t - t2) > COOLDOWN * 3 then
			Cooldowns[uid] = nil
		end
	end
end

-----------------------------------------------
-- INIT
-----------------------------------------------

function GiftMgr.Init(Registry)
	DM = Registry.Get("DataManager")
	GM = Registry.Get("GamepassManager")

	if not DM then error("[GiftGamepassManager] DataManager not found!") end
	if not GM then error("[GiftGamepassManager] GamepassManager not found!") end

	-------------------------------------------
	-- REMOTE HANDLER
	-------------------------------------------

	RequestGift.OnServerInvoke = function(player, action, arg1, arg2)
		if type(action) ~= "string" then return { Success = false } end
		local uid = player.UserId

		if action == "GET_PLAYERS" then
			return {
				Success = true,
				Players = buildPlayerList(player),
			}

		elseif action == "GET_GIFTABLE_LIST" then
			local recipientUid = arg1
			if type(recipientUid) ~= "number" then
				return { Success = false, Message = LC.GetFor(player, "GiftInvalidPlayer") }
			end
			if recipientUid == uid then
				return { Success = false, Message = LC.GetFor(player, "GiftCantSelf") }
			end

			local recipient = Players:GetPlayerByUserId(recipientUid)
			if not recipient or not recipient.Parent then
				return { Success = false, Message = LC.GetFor(player, "GiftPlayerOffline") }
			end

			return {
				Success       = true,
				Passes        = buildGiftableList(player, recipient),
				RecipientName = recipient.DisplayName,
				RecipientUid  = recipientUid,
			}

		elseif action == "PROMPT_GIFT" then
			local recipientUid = arg1
			local passName     = arg2

			if type(recipientUid) ~= "number" or type(passName) ~= "string" then
				return { Success = false, Message = LC.GetFor(player, "GiftInvalid") }
			end

			if isOnCooldown(uid) then
				return { Success = false, Message = LC.GetFor(player, "GiftCooldown") }
			end

			if recipientUid == uid then
				return { Success = false, Message = LC.GetFor(player, "GiftCantSelf") }
			end

			if hasActivePending(uid) then
				return { Success = false, Message = LC.GetFor(player, "GiftCooldown") }
			end

			local recipient = Players:GetPlayerByUserId(recipientUid)
			if not recipient or not recipient.Parent then
				return { Success = false, Message = LC.GetFor(player, "GiftPlayerOffline") }
			end

			local pass = GamepassConfig.ByName[passName]
			if not pass or pass.Giftable == false then
				return { Success = false, Message = LC.GetFor(player, "GiftInvalidPass") }
			end

			if not pass.GiftProductId or pass.GiftProductId <= 0 then
				return { Success = false, Message = LC.GetFor(player, "GiftInvalidPass") }
			end

			local recipientHas = GM.HasPass(recipient, passName)
				or GiftMgr.HasGiftedPass(recipient, passName)
			if recipientHas then
				return {
					Success = false,
					Message = LC.GetFor(player, "GiftAlreadyOwned",
						recipient.DisplayName,
						LC.GetFor(player, "Pass_" .. passName)),
				}
			end

			Cooldowns[uid] = now()

			local pendingData = {
				RecipientUid  = recipientUid,
				RecipientName = recipient.DisplayName,
				PassName      = passName,
				ProductId     = pass.GiftProductId,
				SenderName    = player.DisplayName,
				Timestamp     = now(),
			}
			PendingGifts[uid] = pendingData
			savePendingToStore(uid, pendingData)

			local ok = pcall(function()
				MarketplaceService:PromptProductPurchase(player, pass.GiftProductId)
			end)

			if not ok then
				PendingGifts[uid] = nil
				clearPendingFromStore(uid)
				return { Success = false, Message = LC.GetFor(player, "GiftPromptFail") }
			end

			return { Success = true, Message = LC.GetFor(player, "GiftPrompted") }

		elseif action == "GET_HISTORY" then
			return {
				Success = true,
				History = getHistory(player),
			}
		end

		return { Success = false }
	end

	-------------------------------------------
	-- FIX #6: DETECT PURCHASE CANCELLED/FAILED
	-- PromptProductPurchaseFinished fires saat
	-- purchase dialog ditutup (berhasil ATAU batal).
	-- Grace period mencegah race condition dimana
	-- event fires sebelum dialog sempat muncul.
	-------------------------------------------
	MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId, productId, isPurchased)
		-- Kalau berhasil beli → ProcessReceipt akan handle, skip
		if isPurchased then return end

		-- Hanya handle gift products
		local passInfo = GamepassConfig.ByGiftProductId and GamepassConfig.ByGiftProductId[productId]
		if not passInfo then return end

		-- Cek ada pending yang cocok
		local pending = PendingGifts[userId]
		if not pending then return end
		if pending.ProductId ~= productId then return end

		-- Grace period: jika pending baru dibuat < GRACE_PERIOD detik,
		-- tunggu dulu — Roblox mungkin belum sempat tampilkan dialog.
		-- Tanpa ini, event bisa fire sebelum dialog muncul → cancel prematur.
		local age = now() - pending.Timestamp
		if age < GRACE_PERIOD then
			task.delay(GRACE_PERIOD - age + 0.5, function()
				-- Setelah grace period, cek lagi apakah pending masih ada
				-- (bisa sudah di-handle oleh HandleReceipt jika player beli cepat)
				local stillPending = PendingGifts[userId]
				if not stillPending then return end
				if stillPending.ProductId ~= productId then return end

				-- Masih ada dan belum berubah → benar-benar batal
				cancelPending(userId, productId)
			end)
			return
		end

		-- Pending sudah cukup lama (> GRACE_PERIOD detik) → aman untuk cancel
		cancelPending(userId, productId)
	end)

	-------------------------------------------
	-- PLAYER ADDED
	-------------------------------------------
	local function onPlayerAdded(player)
		local maxWait = 15
		local waited = 0
		while not DM.Get(player) and waited < maxWait do
			task.wait(0.5)
			waited += 0.5
		end

		if not player or not player.Parent then return end

		local data = DM.Get(player)
		if not data then
			warn("[GiftMgr] Data not loaded for", player.Name, "after", maxWait, "seconds — skipping restore")
			return
		end

		restoreGiftAttributes(player)
	end

	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, p in ipairs(Players:GetPlayers()) do
		task.spawn(function() onPlayerAdded(p) end)
	end

	-------------------------------------------
	-- CLEANUP
	-------------------------------------------
	Players.PlayerRemoving:Connect(function(player)
		local uid = player.UserId
		Cooldowns[uid] = nil
	end)

	-------------------------------------------
	-- GC LOOP
	-------------------------------------------
	task.spawn(function()
		while true do
			task.wait(60)
			gcPendings()
		end
	end)

end

return GiftMgr
