-- HoneyShop_Server.lua
-- Server script untuk sistem Honey Shop Mount Semut
-- Taruh di ServerScriptService
-- ? UPDATE (sesuai diskusi):
--   • Hapus item Mahkota Lebah
--   • Hapus total mekanisme BeeShield (item + efek)
--   • Topi Bunga pakai catalog AccessoryId: 17302569985
--   • Trail sparkle pakai TextureId: 9563941378, dipasang di tangan kanan & kiri (R6/R15)
--   • Pet lebah dari ServerStorage.Pet.Lebah (pet follow)
--   • Boost Lucky Honey = HoneyMultiplier (hanya dipakai oleh DailyQuest BeeRescue bonus)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local InsertService = game:GetService("InsertService")

-- ===== CONFIG =====
local CONFIG = {
	DATASTORE_NAME = "HoneyShop_v1",

	HAT_FLOWER_ASSET_ID = 17302569985,
	TRAIL_TEXTURE_ID = 9563941378,

	PET_FOLDER_NAME = "Pet",
	PET_MODEL_NAME = "Lebah",

	-- Pet follow feel
	PET_OFFSET = Vector3.new(2.2, 1.3, 2.2), -- agak samping + belakang
	PET_RESPONSIVENESS = 18,
	PET_MAX_FORCE = 15000,
}

-- ===== SHOP ITEMS =====
-- Catatan: ID item jangan sering ganti supaya inventory lama tidak rusak.
local SHOP_ITEMS = {
	-- === COSMETICS ===
	{
		id = "hat_flower",
		name = "Topi Bunga",
		desc = "Bunga cantik di kepala",
		icon = "??",
		price = 1,
		category = "cosmetic",
		itemType = "hat",
		assetId = CONFIG.HAT_FLOWER_ASSET_ID,
	},
	{
		id = "trail_honey",
		name = "Sparkle Trail",
		desc = "Efek sparkle di kedua tangan",
		icon = "?",
		price = 20,
		category = "cosmetic",
		itemType = "trail",
		textureId = CONFIG.TRAIL_TEXTURE_ID,
	},
	{
		id = "pet_mini_bee",
		name = "Mini Lebah Pet",
		desc = "Lebah kecil mengikutimu",
		icon = "??",
		price = 1,
		category = "cosmetic",
		itemType = "pet",
		petModel = CONFIG.PET_MODEL_NAME,
	},

	-- === POWER-UPS ===
	{
		id = "boost_speed",
		name = "Speed Boost",
		desc = "+20% kecepatan selama 10 menit",
		icon = "?",
		price = 1,
		category = "powerup",
		itemType = "boost",
		duration = 600,
		stackable = true,
	},
	{
		id = "boost_jump",
		name = "Jump Boost",
		desc = "+50% lompatan selama 10 menit",
		icon = "??",
		price = 1,
		category = "powerup",
		itemType = "boost",
		duration = 600,
		stackable = true,
	},

	-- === SPECIAL ===
	{
		id = "lucky_honey",
		name = "Lucky Honey",
		desc = "2x bonus honey dari BeeRescue selama 1 jam",
		icon = "??",
		price = 1,
		category = "special",
		itemType = "multiplier",
		duration = 3600,
		stackable = true,
	},
	{
		id = "vip_bee_pass",
		name = "VIP Bee Pass",
		desc = "Akses area VIP permanen",
		icon = "?",
		price = 1,
		category = "special",
		itemType = "permanent",
	},
}

-- Build lookup table
local ITEMS_BY_ID = {}
for _, item in ipairs(SHOP_ITEMS) do
	ITEMS_BY_ID[item.id] = item
end

-- ===== DATASTORES =====
local shopStore = DataStoreService:GetDataStore(CONFIG.DATASTORE_NAME)

-- ===== REMOTES (Create immediately) =====
local shopRemote = ReplicatedStorage:FindFirstChild("HoneyShop_Remote")
if not shopRemote then
	shopRemote = Instance.new("RemoteEvent")
	shopRemote.Name = "HoneyShop_Remote"
	shopRemote.Parent = ReplicatedStorage
end

local shopFunction = ReplicatedStorage:FindFirstChild("HoneyShop_Function")
if not shopFunction then
	shopFunction = Instance.new("RemoteFunction")
	shopFunction.Name = "HoneyShop_Function"
	shopFunction.Parent = ReplicatedStorage
end

-- ===== STATE =====
local playerInventory: {[number]: any} = {}
local playerLoaded: {[number]: boolean} = {}

-- untuk mencegah schedule boost bertumpuk
local boostTokens: {[number]: {[string]: number}} = {} -- userId -> itemId -> token int

-- ===== UTILITY =====
local function getDefaultInventory()
	return {
		owned = {},
		consumables = {},
		equipped = {
			hat = nil,
			trail = nil,
			aura = nil,
			pet = nil,
		},
		activeBoosts = {}, -- itemId -> endTime(os.time())
	}
end

local function getOrCreateFolder(parent: Instance, name: string): Folder
	local f = parent:FindFirstChild(name)
	if f and f:IsA("Folder") then return f end
	f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

local function getCharacterHumanoid(plr: Player)
	local char = plr.Character
	if not char then return nil, nil end
	local hum = char:FindFirstChildOfClass("Humanoid")
	return char, hum
end

-- ===== HONEY FUNCTIONS (DailyQuest) =====
local function waitDailyQuestAPI(maxWaitSec: number)
	local t0 = os.clock()
	while not _G.DailyQuestAPI and (os.clock() - t0) < maxWaitSec do
		task.wait(0.1)
	end
	return _G.DailyQuestAPI
end

local function getHoneyPoints(plr: Player): number
	waitDailyQuestAPI(5)
	if _G.DailyQuestAPI and _G.DailyQuestAPI.GetPlayerData then
		local data = _G.DailyQuestAPI.GetPlayerData(plr)
		if data then
			return data.honeyPoints or 0
		end
	end
	warn("[HoneyShop] DailyQuestAPI not found!")
	return 0
end

local function deductHoney(plr: Player, amount: number): boolean
	if amount <= 0 then return true end
	waitDailyQuestAPI(5)
	if _G.DailyQuestAPI and _G.DailyQuestAPI.GetPlayerData then
		local data = _G.DailyQuestAPI.GetPlayerData(plr)
		if data and (data.honeyPoints or 0) >= amount then
			data.honeyPoints -= amount
			local questRemote = ReplicatedStorage:FindFirstChild("DailyQuest_Remote")
			if questRemote then
				questRemote:FireClient(plr, "HoneyUpdate", data.honeyPoints)
			end
			return true
		end
	end
	return false
end

-- ===== DATASTORE =====
local function loadInventory(plr: Player)
	local userId = plr.UserId
	local key = "INV_" .. userId
	local inventory = getDefaultInventory()

	local success, data = pcall(function()
		return shopStore:GetAsync(key)
	end)

	if success and data and type(data) == "table" then
		if type(data.owned) == "table" then inventory.owned = data.owned end
		if type(data.consumables) == "table" then inventory.consumables = data.consumables end
		if type(data.equipped) == "table" then
			for slot, itemId in pairs(data.equipped) do
				inventory.equipped[slot] = itemId
			end
		end
		if type(data.activeBoosts) == "table" then
			local now = os.time()
			for itemId, endTime in pairs(data.activeBoosts) do
				if type(endTime) == "number" and endTime > now then
					inventory.activeBoosts[itemId] = endTime
				end
			end
		end

		-- Cleanup: jika ada item lama (mahkota/shield), biarkan owned-nya (tidak dipakai),
		-- tapi tidak akan muncul di UI karena SHOP_ITEMS sudah tidak memuatnya.
	end

	playerInventory[userId] = inventory
	playerLoaded[userId] = true
	boostTokens[userId] = boostTokens[userId] or {}

	print("[HoneyShop] Loaded inventory for", plr.Name)
	return inventory
end

local function saveInventory(plr: Player)
	local userId = plr.UserId
	local inventory = playerInventory[userId]
	if not inventory then return end

	local key = "INV_" .. userId

	local success, err = pcall(function()
		shopStore:SetAsync(key, {
			owned = inventory.owned,
			consumables = inventory.consumables,
			equipped = inventory.equipped,
			activeBoosts = inventory.activeBoosts,
		})
	end)

	if not success then
		warn("[HoneyShop] Failed to save:", err)
	end
end

-- ===== COSMETIC APPLY (SERVER) =====
local accessoryCache: {[number]: Accessory} = {}

local function loadAccessoryTemplate(assetId: number): Accessory?
	if accessoryCache[assetId] then
		return accessoryCache[assetId]
	end

	local ok, model = pcall(function()
		return InsertService:LoadAsset(assetId)
	end)

	if not ok or not model then
		warn("[HoneyShop] LoadAsset gagal untuk assetId:", assetId)
		return nil
	end

	local acc: Accessory? = nil
	for _, inst in ipairs(model:GetChildren()) do
		if inst:IsA("Accessory") then
			acc = inst
			break
		end
	end

	if not acc then
		model:Destroy()
		warn("[HoneyShop] AssetId bukan Accessory:", assetId)
		return nil
	end

	acc.Parent = nil
	accessoryCache[assetId] = acc
	model:Destroy()
	return acc
end

local function removeTaggedAccessories(char: Model, tag: string)
	for _, child in ipairs(char:GetChildren()) do
		if child:IsA("Accessory") and child:GetAttribute("HS_Tag") == tag then
			child:Destroy()
		end
	end
end

local function applyHatFlower(plr: Player)
	local char, hum = getCharacterHumanoid(plr)
	if not char or not hum then return end

	-- remove previous HS hat
	removeTaggedAccessories(char, "hat")

	local template = loadAccessoryTemplate(CONFIG.HAT_FLOWER_ASSET_ID)
	if not template then return end

	local acc = template:Clone()
	acc:SetAttribute("HS_Tag", "hat")
	hum:AddAccessory(acc)
end

local function getHandParts(char: Model): {BasePart}
	local parts = {}

	local right = char:FindFirstChild("RightHand") or char:FindFirstChild("Right Arm")
	local left  = char:FindFirstChild("LeftHand") or char:FindFirstChild("Left Arm")

	if right and right:IsA("BasePart") then table.insert(parts, right) end
	if left and left:IsA("BasePart") then table.insert(parts, left) end

	return parts
end

local function clearTrail(char: Model)
	local parts = getHandParts(char)
	for _, hand in ipairs(parts) do
		local att = hand:FindFirstChild("HS_TrailAtt")
		if att and att:IsA("Attachment") then
			for _, em in ipairs(att:GetChildren()) do
				if em:IsA("ParticleEmitter") and em.Name == "HS_TrailEmitter" then
					em:Destroy()
				end
			end
		end
	end
end

local function applySparkleTrail(plr: Player)
	local char = plr.Character
	if not char then return end

	clearTrail(char)

	local parts = getHandParts(char)
	if #parts == 0 then
		warn("[HoneyShop] Tidak menemukan tangan (R6/R15) untuk trail:", plr.Name)
		return
	end

	for _, hand in ipairs(parts) do
		local att = hand:FindFirstChild("HS_TrailAtt")
		if not att then
			att = Instance.new("Attachment")
			att.Name = "HS_TrailAtt"
			att.Parent = hand
		end

		local emitter = Instance.new("ParticleEmitter")
		emitter.Name = "HS_TrailEmitter"
		emitter.Texture = "rbxassetid://" .. tostring(CONFIG.TRAIL_TEXTURE_ID)
		emitter.Rate = 28
		emitter.Lifetime = NumberRange.new(0.35, 0.55)
		emitter.Speed = NumberRange.new(0.5, 1.2)
		emitter.SpreadAngle = Vector2.new(25, 25)
		emitter.Rotation = NumberRange.new(0, 360)
		emitter.RotSpeed = NumberRange.new(-90, 90)
		emitter.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.6),
			NumberSequenceKeypoint.new(1, 0),
		})
		emitter.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.05),
			NumberSequenceKeypoint.new(1, 1),
		})
		emitter.LightEmission = 0.9
		emitter.Parent = att
	end
end

local function destroyPet(plr: Player)
	local char = plr.Character
	if not char then return end

	local existing = char:FindFirstChild("HS_PetBee")
	if existing then
		existing:Destroy()
	end

	local hrp = char:FindFirstChild("HumanoidRootPart")
	if hrp then
		local att = hrp:FindFirstChild("HS_PetTargetAtt")
		if att and att:IsA("Attachment") then
			att:Destroy()
		end
	end
end

local function getPetTemplate(): Model?
	local folder = ServerStorage:FindFirstChild(CONFIG.PET_FOLDER_NAME)
	if not folder then return nil end
	local model = folder:FindFirstChild(CONFIG.PET_MODEL_NAME)
	if model and model:IsA("Model") then
		return model
	end
	return nil
end

local function ensurePrimaryPart(model: Model): BasePart?
	if model.PrimaryPart and model.PrimaryPart:IsA("BasePart") then
		return model.PrimaryPart
	end
	local best: BasePart? = nil
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			best = d
			break
		end
	end
	if best then
		model.PrimaryPart = best
	end
	return best
end

local function applyPetBee(plr: Player)
	local char = plr.Character
	if not char then return end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not (hrp and hrp:IsA("BasePart")) then return end

	destroyPet(plr)

	local template = getPetTemplate()
	if not template then
		warn("[HoneyShop] Pet template tidak ditemukan: ServerStorage." .. CONFIG.PET_FOLDER_NAME .. "." .. CONFIG.PET_MODEL_NAME)
		return
	end

	local pet = template:Clone()
	pet.Name = "HS_PetBee"
	pet.Parent = char

	local root = ensurePrimaryPart(pet)
	if not root then
		warn("[HoneyShop] Pet tidak punya BasePart:", pet:GetFullName())
		pet:Destroy()
		return
	end

	-- Sanitasi part
	for _, d in ipairs(pet:GetDescendants()) do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.CanQuery = false
			d.Massless = true
			d.Anchored = false
		end
	end

	-- Attach follow (AlignPosition + AlignOrientation)
	local targetAtt = hrp:FindFirstChild("HS_PetTargetAtt")
	if not targetAtt then
		targetAtt = Instance.new("Attachment")
		targetAtt.Name = "HS_PetTargetAtt"
		targetAtt.Position = CONFIG.PET_OFFSET
		targetAtt.Parent = hrp
	else
		targetAtt.Position = CONFIG.PET_OFFSET
	end

	local petAtt = root:FindFirstChild("HS_PetAtt")
	if not petAtt then
		petAtt = Instance.new("Attachment")
		petAtt.Name = "HS_PetAtt"
		petAtt.Parent = root
	end

	local alignPos = root:FindFirstChild("HS_AlignPos")
	if not alignPos then
		alignPos = Instance.new("AlignPosition")
		alignPos.Name = "HS_AlignPos"
		alignPos.Parent = root
	end
	alignPos.Attachment0 = petAtt
	alignPos.Attachment1 = targetAtt
	alignPos.Responsiveness = CONFIG.PET_RESPONSIVENESS
	alignPos.MaxForce = CONFIG.PET_MAX_FORCE
	alignPos.RigidityEnabled = false

	local alignOri = root:FindFirstChild("HS_AlignOri")
	if not alignOri then
		alignOri = Instance.new("AlignOrientation")
		alignOri.Name = "HS_AlignOri"
		alignOri.Parent = root
	end
	alignOri.Attachment0 = petAtt
	alignOri.Attachment1 = targetAtt
	alignOri.Responsiveness = CONFIG.PET_RESPONSIVENESS
	alignOri.MaxTorque = CONFIG.PET_MAX_FORCE
	alignOri.RigidityEnabled = false

	-- Network owner ke player biar follow halus
	pcall(function()
		root:SetNetworkOwner(plr)
	end)
end

local function clearAllCosmetics(plr: Player)
	local char = plr.Character
	if not char then return end
	removeTaggedAccessories(char, "hat")
	clearTrail(char)
	destroyPet(plr)
end

local function applyEquippedCosmetics(plr: Player)
	local inv = playerInventory[plr.UserId]
	if not inv then return end

	-- Jika tidak ada character, cukup return
	local char = plr.Character
	if not char then return end

	-- Hat
	if inv.equipped.hat == "hat_flower" then
		applyHatFlower(plr)
	else
		-- unequipped / item lain
		removeTaggedAccessories(char, "hat")
	end

	-- Trail
	if inv.equipped.trail == "trail_honey" then
		applySparkleTrail(plr)
	else
		clearTrail(char)
	end

	-- Pet
	if inv.equipped.pet == "pet_mini_bee" then
		applyPetBee(plr)
	else
		destroyPet(plr)
	end
end

-- ===== BOOSTS / MULTIPLIER =====
local function clearExpiredBoosts(inv)
	local now = os.time()
	local changed = false
	for itemId, endTime in pairs(inv.activeBoosts) do
		if type(endTime) ~= "number" or endTime <= now then
			inv.activeBoosts[itemId] = nil
			changed = true
		end
	end
	return changed
end

local function scheduleBoostEnd(plr: Player, itemId: string, endTime: number, token: number)
	local userId = plr.UserId
	local delaySec = math.max(0, endTime - os.time())
	task.delay(delaySec, function()
		if not Players:GetPlayerByUserId(userId) then return end
		if not boostTokens[userId] or boostTokens[userId][itemId] ~= token then return end

		local inv = playerInventory[userId]
		if not inv then return end

		-- remove boost
		inv.activeBoosts[itemId] = nil

		-- revert effects
		local item = ITEMS_BY_ID[itemId]
		if item then
			local char, hum = getCharacterHumanoid(plr)
			if itemId == "boost_speed" and hum then
				local orig = hum:GetAttribute("HS_OrigWalkSpeed")
				if orig then
					hum.WalkSpeed = orig
					hum:SetAttribute("HS_OrigWalkSpeed", nil)
				end
			elseif itemId == "boost_jump" and hum then
				local orig = hum:GetAttribute("HS_OrigJumpPower")
				if orig then
					hum.JumpPower = orig
					hum:SetAttribute("HS_OrigJumpPower", nil)
				end
			elseif itemId == "lucky_honey" then
				if plr and plr.Parent then
					plr:SetAttribute("HoneyMultiplier", 1)
				end
			end

			shopRemote:FireClient(plr, "BoostExpired", item.name)
		end

		task.defer(saveInventory, plr)
	end)
end

local function applyBoostNow(plr: Player, itemId: string, endTime: number)
	local item = ITEMS_BY_ID[itemId]
	if not item then return end

	local userId = plr.UserId
	boostTokens[userId] = boostTokens[userId] or {}
	boostTokens[userId][itemId] = (boostTokens[userId][itemId] or 0) + 1
	local token = boostTokens[userId][itemId]

	local char, hum = getCharacterHumanoid(plr)

	if itemId == "boost_speed" and hum then
		if hum:GetAttribute("HS_OrigWalkSpeed") == nil then
			hum:SetAttribute("HS_OrigWalkSpeed", hum.WalkSpeed)
		end
		local orig = hum:GetAttribute("HS_OrigWalkSpeed") or hum.WalkSpeed
		hum.WalkSpeed = orig * 1.2

	elseif itemId == "boost_jump" and hum then
		if hum:GetAttribute("HS_OrigJumpPower") == nil then
			hum:SetAttribute("HS_OrigJumpPower", hum.JumpPower)
		end
		local orig = hum:GetAttribute("HS_OrigJumpPower") or hum.JumpPower
		hum.JumpPower = orig * 1.5

	elseif itemId == "lucky_honey" then
		plr:SetAttribute("HoneyMultiplier", 2)
	end

	local remaining = math.max(0, endTime - os.time())
	shopRemote:FireClient(plr, "BoostActivated", { name = item.name, duration = remaining })

	scheduleBoostEnd(plr, itemId, endTime, token)
end

local function syncActiveBoostsForPlayer(plr: Player)
	local inv = playerInventory[plr.UserId]
	if not inv then return end

	-- bersihkan expired
	if clearExpiredBoosts(inv) then
		task.defer(saveInventory, plr)
	end

	local now = os.time()
	for itemId, endTime in pairs(inv.activeBoosts) do
		if type(endTime) == "number" and endTime > now then
			applyBoostNow(plr, itemId, endTime)
		end
	end

	-- kalau tidak ada lucky_honey aktif, pastikan multiplier 1
	if not inv.activeBoosts["lucky_honey"] then
		plr:SetAttribute("HoneyMultiplier", 1)
	end
end

-- ===== SHOP FUNCTIONS =====
local function purchaseItem(plr: Player, itemId: string): (boolean, string?)
	local userId = plr.UserId
	local inventory = playerInventory[userId]

	if not inventory or not playerLoaded[userId] then
		return false, "Data belum siap!"
	end

	local item = ITEMS_BY_ID[itemId]
	if not item then
		return false, "Item tidak ditemukan!"
	end

	-- Check if already owned (for non-stackable items)
	if not item.stackable and inventory.owned[itemId] then
		return false, "Sudah dimiliki!"
	end

	-- Check honey
	local honey = getHoneyPoints(plr)
	if honey < item.price then
		return false, "Honey tidak cukup! (Punya: " .. honey .. ", Butuh: " .. item.price .. ")"
	end

	-- Deduct honey
	if not deductHoney(plr, item.price) then
		return false, "Gagal mengurangi honey!"
	end

	-- Add to inventory
	if item.stackable then
		inventory.consumables[itemId] = (inventory.consumables[itemId] or 0) + 1
	else
		inventory.owned[itemId] = true
	end

	task.defer(saveInventory, plr)
	print("[HoneyShop]", plr.Name, "purchased", item.name)

	return true, nil
end

local function equipItem(plr: Player, itemId: string): (boolean, string?)
	local userId = plr.UserId
	local inventory = playerInventory[userId]
	if not inventory then return false, "Data belum siap!" end

	local item = ITEMS_BY_ID[itemId]
	if not item then return false, "Item tidak ditemukan!" end

	if not inventory.owned[itemId] then
		return false, "Belum dimiliki!"
	end

	if item.category ~= "cosmetic" then
		return false, "Item ini tidak bisa di-equip!"
	end

	local slot = item.itemType
	if inventory.equipped[slot] == itemId then
		inventory.equipped[slot] = nil
	else
		inventory.equipped[slot] = itemId
	end

	-- apply langsung
	task.defer(function()
		applyEquippedCosmetics(plr)
	end)

	task.defer(saveInventory, plr)
	return true, nil
end

local function useConsumable(plr: Player, itemId: string): (boolean, string?)
	local userId = plr.UserId
	local inventory = playerInventory[userId]
	if not inventory then return false, "Data belum siap!" end

	local item = ITEMS_BY_ID[itemId]
	if not item then return false, "Item tidak ditemukan!" end

	local count = inventory.consumables[itemId] or 0
	if count <= 0 then
		return false, "Tidak punya item ini!"
	end

	-- consume
	inventory.consumables[itemId] = count - 1
	if inventory.consumables[itemId] <= 0 then
		inventory.consumables[itemId] = nil
	end

	-- timed
	if item.duration and item.duration > 0 then
		local endTime = os.time() + item.duration
		inventory.activeBoosts[itemId] = endTime

		-- apply sekarang
		task.defer(function()
			applyBoostNow(plr, itemId, endTime)
		end)
	end

	task.defer(saveInventory, plr)
	print("[HoneyShop]", plr.Name, "used", item.name)
	return true, nil
end

-- ===== REMOTE HANDLERS =====
shopFunction.OnServerInvoke = function(plr: Player, action: string, ...)
	local userId = plr.UserId

	if action == "OpenShop" or action == "GetShopData" then
		if not playerLoaded[userId] then
			loadInventory(plr)
		end

		local inventory = playerInventory[userId] or getDefaultInventory()
		local honey = getHoneyPoints(plr)

		-- Clean expired boosts + build remaining table
		local now = os.time()
		local activeBoosts = {}
		local changed = false
		for itemId, endTime in pairs(inventory.activeBoosts) do
			if type(endTime) == "number" and endTime > now then
				activeBoosts[itemId] = endTime - now
			else
				inventory.activeBoosts[itemId] = nil
				changed = true
			end
		end
		if changed then task.defer(saveInventory, plr) end

		return {
			success = true,
			items = SHOP_ITEMS,
			owned = inventory.owned,
			consumables = inventory.consumables,
			equipped = inventory.equipped,
			activeBoosts = activeBoosts,
			honeyPoints = honey,
		}

	elseif action == "Purchase" then
		local itemId = ...
		local ok, err = purchaseItem(plr, itemId)
		local inventory = playerInventory[userId]
		return {
			success = ok,
			error = err,
			honeyPoints = getHoneyPoints(plr),
			owned = inventory and inventory.owned or {},
			consumables = inventory and inventory.consumables or {},
		}

	elseif action == "Equip" then
		local itemId = ...
		local ok, err = equipItem(plr, itemId)
		local inventory = playerInventory[userId]
		return {
			success = ok,
			error = err,
			equipped = inventory and inventory.equipped or {},
		}

	elseif action == "Use" then
		local itemId = ...
		local ok, err = useConsumable(plr, itemId)
		local inventory = playerInventory[userId]
		return {
			success = ok,
			error = err,
			consumables = inventory and inventory.consumables or {},
		}
	end

	return { success = false, error = "Action tidak valid!" }
end

-- ===== PLAYER LIFECYCLE =====
local function onCharacterAdded(plr: Player, _char: Model)
	-- apply cosmetics + boosts berdasarkan inventory yang sudah loaded
	task.defer(function()
		if not playerLoaded[plr.UserId] then return end
		applyEquippedCosmetics(plr)
		syncActiveBoostsForPlayer(plr)
	end)
end

Players.PlayerAdded:Connect(function(plr)
	-- Pastikan DailyQuest sudah bikin data dulu
	task.defer(function()
		task.wait(3)
		loadInventory(plr)

		plr.CharacterAdded:Connect(function(char)
			onCharacterAdded(plr, char)
		end)

		-- apply kalau char sudah ada
		if plr.Character then
			onCharacterAdded(plr, plr.Character)
		end
	end)
end)

for _, plr in ipairs(Players:GetPlayers()) do
	task.spawn(function()
		task.wait(1)
		loadInventory(plr)

		plr.CharacterAdded:Connect(function(char)
			onCharacterAdded(plr, char)
		end)

		if plr.Character then
			onCharacterAdded(plr, plr.Character)
		end
	end)
end

Players.PlayerRemoving:Connect(function(plr)
	local userId = plr.UserId
	saveInventory(plr)
	task.delay(5, function()
		playerInventory[userId] = nil
		playerLoaded[userId] = nil
		boostTokens[userId] = nil
	end)
end)

game:BindToClose(function()
	for _, plr in ipairs(Players:GetPlayers()) do
		saveInventory(plr)
	end
	task.wait(RunService:IsStudio() and 2 or 5)
end)

-- ===== PUBLIC API =====
_G.HoneyShopAPI = {
	GetInventory = function(plr)
		return playerInventory[plr.UserId]
	end,
	HasItem = function(plr, itemId)
		local inv = playerInventory[plr.UserId]
		if not inv then return false end
		return inv.owned[itemId] == true
	end,
	GetEquipped = function(plr, slot)
		local inv = playerInventory[plr.UserId]
		if not inv then return nil end
		return inv.equipped[slot]
	end,
	IsBoostActive = function(plr, itemId)
		local inv = playerInventory[plr.UserId]
		if not inv then return false end
		local endTime = inv.activeBoosts[itemId]
		return type(endTime) == "number" and endTime > os.time()
	end,
	-- Utility untuk re-apply (kalau ada sistem lain butuh)
	ReapplyCosmetics = function(plr)
		applyEquippedCosmetics(plr)
	end,
	ClearCosmetics = function(plr)
		clearAllCosmetics(plr)
	end,
}

print("[HoneyShop] Server ready! ??")
