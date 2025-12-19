-- HoneyShop_Client.lua
-- Client script untuk UI Honey Shop Mount Semut
-- ? FIX: Emoji UI diganti teks (biar tidak jadi "?")
-- ? FIX: Loop ipairs (biar UI tidak crash)
-- ? FIX: Overlay clickable + camera nil-safe
-- Taruh di StarterPlayerScripts

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- ===== CONFIG =====
local CONFIG = {
	HONEY_GOLD = Color3.fromRGB(255, 214, 64),
	HONEY_ORANGE = Color3.fromRGB(255, 170, 0),
	HONEY_DARK = Color3.fromRGB(139, 69, 19),
	LEAF_GREEN = Color3.fromRGB(152, 251, 152),
	LEAF_DARK = Color3.fromRGB(107, 142, 35),
	SKY_BLUE = Color3.fromRGB(135, 206, 235),
	WOOD_LIGHT = Color3.fromRGB(222, 184, 135),
	WOOD_DARK = Color3.fromRGB(139, 90, 43),
	CREAM = Color3.fromRGB(255, 248, 220),

	CATEGORY_COLORS = {
		cosmetic = Color3.fromRGB(255, 182, 193),
		powerup  = Color3.fromRGB(173, 216, 230),
		special  = Color3.fromRGB(255, 215, 0),
	},
}

-- ===== TEXT (NO EMOJI) =====
local TXT = {
	TITLE = "Honey Shop",
	HONEY = "Honey",
	TAB_COS = "Cosmetic",
	TAB_PWR = "Power-Up",
	TAB_SPC = "Special",
	PICK_ITEM = "Pilih Item",
	CLICK_ITEM = "Klik item untuk melihat detail",
	PRICE_PREFIX = "Honey ",
	BUY = "Beli",
	BUY_AGAIN = "Beli Lagi",
	EQUIP = "Pakai",
	UNEQUIP = "Lepas",
	USE = "Gunakan",
	OWNED = "Sudah dimiliki",
	EQUIPPED = "Sedang dipakai",
	HAVE_PREFIX = "Punya: ",
}

-- ===== REMOTES =====
local shopRemote = ReplicatedStorage:WaitForChild("HoneyShop_Remote", 20)
local shopFunction = ReplicatedStorage:WaitForChild("HoneyShop_Function", 20)

if not shopRemote or not shopFunction then
	warn("[HoneyShop] Remote not found! Pastikan HoneyShopServer.lua jalan dan membuat HoneyShop_Remote & HoneyShop_Function.")
	return
end

-- ===== STATE =====
local shopData = {
	items = {},
	owned = {},
	consumables = {},
	equipped = {},
	activeBoosts = {},
	honeyPoints = 0,
}

local isOpen = false
local isAnimating = false
local currentCategory = "cosmetic"
local selectedItem = nil

local uiRefs = {}

-- ===== UTILITY =====
local function createCorner(parent, radius)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = parent
	return corner
end

local function getOrCreateStroke(parent, color, thickness)
	local stroke = parent:FindFirstChildOfClass("UIStroke")
	if not stroke then
		stroke = Instance.new("UIStroke")
		stroke.Parent = parent
	end
	stroke.Color = color
	stroke.Thickness = thickness
	return stroke
end

local function createGradient(parent, c1, c2, rotation)
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new(c1, c2)
	gradient.Rotation = rotation or 90
	gradient.Parent = parent
	return gradient
end

local selectItem -- forward

-- ===== BUILD UI =====
local function buildUI(): ScreenGui
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "HoneyShopUI"
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.IgnoreGuiInset = true

	-- Overlay
	local overlay = Instance.new("Frame")
	overlay.Name = "Overlay"
	overlay.Size = UDim2.new(1, 0, 1, 0)
	overlay.BackgroundColor3 = Color3.new(0, 0, 0)
	overlay.BackgroundTransparency = 1
	overlay.BorderSizePixel = 0
	overlay.ZIndex = 200
	overlay.Visible = false
	overlay.Active = true -- ? penting biar bisa klik untuk close
	overlay.Parent = screenGui

	-- Main Frame (600 x 420)
	local mainFrame = Instance.new("Frame")
	mainFrame.Name = "MainFrame"
	mainFrame.Size = UDim2.new(0, 600, 0, 420)
	mainFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
	mainFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	mainFrame.BackgroundColor3 = CONFIG.CREAM
	mainFrame.BorderSizePixel = 0
	mainFrame.Visible = false
	mainFrame.ZIndex = 201
	mainFrame.Parent = screenGui
	createCorner(mainFrame, 16)
	getOrCreateStroke(mainFrame, CONFIG.WOOD_DARK, 4)

	local uiScale = Instance.new("UIScale")
	uiScale.Name = "UIScale"
	uiScale.Scale = 1
	uiScale.Parent = mainFrame

	-- ===== HEADER =====
	local header = Instance.new("Frame")
	header.Name = "Header"
	header.Size = UDim2.new(1, -20, 0, 50)
	header.Position = UDim2.new(0, 10, 0, 10)
	header.BackgroundColor3 = CONFIG.HONEY_GOLD
	header.BorderSizePixel = 0
	header.ZIndex = 202
	header.Parent = mainFrame
	createCorner(header, 12)
	createGradient(header, Color3.fromRGB(255, 228, 181), CONFIG.HONEY_ORANGE, 135)
	getOrCreateStroke(header, CONFIG.HONEY_DARK, 2)

	-- Title
	local titleLabel = Instance.new("TextLabel")
	titleLabel.Size = UDim2.new(0, 200, 1, 0)
	titleLabel.Position = UDim2.new(0, 15, 0, 0)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Text = TXT.TITLE
	titleLabel.TextColor3 = CONFIG.WOOD_DARK
	titleLabel.TextSize = 20
	titleLabel.Font = Enum.Font.FredokaOne
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.ZIndex = 203
	titleLabel.Parent = header

	-- Honey Display
	local honeyFrame = Instance.new("Frame")
	honeyFrame.Name = "HoneyDisplay"
	honeyFrame.Size = UDim2.new(0, 150, 0, 36)
	honeyFrame.Position = UDim2.new(1, -200, 0.5, 0)
	honeyFrame.AnchorPoint = Vector2.new(0, 0.5)
	honeyFrame.BackgroundColor3 = CONFIG.CREAM
	honeyFrame.BorderSizePixel = 0
	honeyFrame.ZIndex = 203
	honeyFrame.Parent = header
	createCorner(honeyFrame, 10)
	getOrCreateStroke(honeyFrame, Color3.fromRGB(218, 165, 32), 2)

	local honeyIcon = Instance.new("TextLabel")
	honeyIcon.Size = UDim2.new(0, 60, 1, 0)
	honeyIcon.Position = UDim2.new(0, 6, 0, 0)
	honeyIcon.BackgroundTransparency = 1
	honeyIcon.Text = TXT.HONEY
	honeyIcon.TextColor3 = CONFIG.WOOD_DARK
	honeyIcon.TextSize = 14
	honeyIcon.Font = Enum.Font.GothamBold
	honeyIcon.ZIndex = 204
	honeyIcon.Parent = honeyFrame

	local honeyValue = Instance.new("TextLabel")
	honeyValue.Name = "HoneyValue"
	honeyValue.Size = UDim2.new(0, 80, 1, 0)
	honeyValue.Position = UDim2.new(0, 70, 0, 0)
	honeyValue.BackgroundTransparency = 1
	honeyValue.Text = "0"
	honeyValue.TextColor3 = Color3.fromRGB(210, 105, 30)
	honeyValue.TextSize = 22
	honeyValue.Font = Enum.Font.FredokaOne
	honeyValue.TextXAlignment = Enum.TextXAlignment.Left
	honeyValue.ZIndex = 204
	honeyValue.Parent = honeyFrame

	-- Close Button
	local closeBtn = Instance.new("TextButton")
	closeBtn.Name = "CloseButton"
	closeBtn.Size = UDim2.new(0, 32, 0, 32)
	closeBtn.Position = UDim2.new(1, -10, 0.5, 0)
	closeBtn.AnchorPoint = Vector2.new(1, 0.5)
	closeBtn.BackgroundColor3 = Color3.fromRGB(255, 100, 100)
	closeBtn.BorderSizePixel = 0
	closeBtn.Text = "X"
	closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	closeBtn.TextSize = 18
	closeBtn.Font = Enum.Font.GothamBold
	closeBtn.ZIndex = 204
	closeBtn.Parent = header
	createCorner(closeBtn, 16)
	getOrCreateStroke(closeBtn, Color3.fromRGB(180, 60, 60), 2)

	-- ===== CATEGORY TABS =====
	local tabFrame = Instance.new("Frame")
	tabFrame.Name = "TabFrame"
	tabFrame.Size = UDim2.new(1, -20, 0, 36)
	tabFrame.Position = UDim2.new(0, 10, 0, 68)
	tabFrame.BackgroundTransparency = 1
	tabFrame.ZIndex = 202
	tabFrame.Parent = mainFrame

	local categories = {
		{id = "cosmetic", name = TXT.TAB_COS, color = CONFIG.CATEGORY_COLORS.cosmetic},
		{id = "powerup",  name = TXT.TAB_PWR, color = CONFIG.CATEGORY_COLORS.powerup},
		{id = "special",  name = TXT.TAB_SPC, color = CONFIG.CATEGORY_COLORS.special},
	}

	local tabButtons = {}
	for i, cat in ipairs(categories) do -- ? FIX
		local btn = Instance.new("TextButton")
		btn.Name = cat.id .. "Tab"
		btn.Size = UDim2.new(0, 180, 0, 32)
		btn.Position = UDim2.new(0, (i - 1) * 190, 0, 0)
		btn.BackgroundColor3 = cat.color
		btn.BorderSizePixel = 0
		btn.Text = cat.name
		btn.TextColor3 = CONFIG.WOOD_DARK
		btn.TextSize = 13
		btn.Font = Enum.Font.FredokaOne
		btn.ZIndex = 203
		btn.Parent = tabFrame
		createCorner(btn, 8)
		local st = getOrCreateStroke(btn, CONFIG.WOOD_DARK, 2)

		tabButtons[cat.id] = {btn = btn, stroke = st}
	end
	uiRefs.tabButtons = tabButtons

	-- ===== ITEMS CONTAINER =====
	local itemsFrame = Instance.new("ScrollingFrame")
	itemsFrame.Name = "ItemsFrame"
	itemsFrame.Size = UDim2.new(0, 350, 0, 295)
	itemsFrame.Position = UDim2.new(0, 10, 0, 112)
	itemsFrame.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	itemsFrame.BackgroundTransparency = 0.3
	itemsFrame.BorderSizePixel = 0
	itemsFrame.ScrollBarThickness = 6
	itemsFrame.ScrollBarImageColor3 = CONFIG.HONEY_DARK
	itemsFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
	itemsFrame.ZIndex = 202
	itemsFrame.Parent = mainFrame
	createCorner(itemsFrame, 12)
	getOrCreateStroke(itemsFrame, CONFIG.WOOD_LIGHT, 2)

	local gridLayout = Instance.new("UIGridLayout")
	gridLayout.CellSize = UDim2.new(0, 105, 0, 120)
	gridLayout.CellPadding = UDim2.new(0, 8, 0, 8)
	gridLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
	gridLayout.Parent = itemsFrame

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 8)
	padding.PaddingTop = UDim.new(0, 8)
	padding.Parent = itemsFrame

	-- ===== DETAIL PANEL =====
	local detailPanel = Instance.new("Frame")
	detailPanel.Name = "DetailPanel"
	detailPanel.Size = UDim2.new(0, 220, 0, 295)
	detailPanel.Position = UDim2.new(0, 370, 0, 112)
	detailPanel.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	detailPanel.BackgroundTransparency = 0.1
	detailPanel.BorderSizePixel = 0
	detailPanel.ZIndex = 202
	detailPanel.Parent = mainFrame
	createCorner(detailPanel, 12)
	getOrCreateStroke(detailPanel, CONFIG.WOOD_LIGHT, 2)

	-- Preview Icon (no emoji)
	local previewIcon = Instance.new("TextLabel")
	previewIcon.Name = "PreviewIcon"
	previewIcon.Size = UDim2.new(0, 80, 0, 80)
	previewIcon.Position = UDim2.new(0.5, 0, 0, 15)
	previewIcon.AnchorPoint = Vector2.new(0.5, 0)
	previewIcon.BackgroundColor3 = CONFIG.HONEY_GOLD
	previewIcon.BorderSizePixel = 0
	previewIcon.Text = "?"
	previewIcon.TextColor3 = CONFIG.WOOD_DARK
	previewIcon.TextSize = 50
	previewIcon.Font = Enum.Font.GothamBlack
	previewIcon.ZIndex = 203
	previewIcon.Parent = detailPanel
	createCorner(previewIcon, 15)
	getOrCreateStroke(previewIcon, CONFIG.HONEY_DARK, 2)

	-- Item Name
	local itemName = Instance.new("TextLabel")
	itemName.Name = "ItemName"
	itemName.Size = UDim2.new(1, -20, 0, 24)
	itemName.Position = UDim2.new(0, 10, 0, 100)
	itemName.BackgroundTransparency = 1
	itemName.Text = TXT.PICK_ITEM
	itemName.TextColor3 = CONFIG.WOOD_DARK
	itemName.TextSize = 16
	itemName.Font = Enum.Font.FredokaOne
	itemName.ZIndex = 203
	itemName.Parent = detailPanel

	-- Item Desc
	local itemDesc = Instance.new("TextLabel")
	itemDesc.Name = "ItemDesc"
	itemDesc.Size = UDim2.new(1, -20, 0, 40)
	itemDesc.Position = UDim2.new(0, 10, 0, 125)
	itemDesc.BackgroundTransparency = 1
	itemDesc.Text = TXT.CLICK_ITEM
	itemDesc.TextColor3 = Color3.fromRGB(100, 100, 100)
	itemDesc.TextSize = 11
	itemDesc.Font = Enum.Font.GothamMedium
	itemDesc.TextWrapped = true
	itemDesc.ZIndex = 203
	itemDesc.Parent = detailPanel

	-- Price
	local priceLabel = Instance.new("TextLabel")
	priceLabel.Name = "PriceLabel"
	priceLabel.Size = UDim2.new(1, -20, 0, 28)
	priceLabel.Position = UDim2.new(0, 10, 0, 170)
	priceLabel.BackgroundColor3 = CONFIG.HONEY_GOLD
	priceLabel.BorderSizePixel = 0
	priceLabel.Text = TXT.PRICE_PREFIX .. "0"
	priceLabel.TextColor3 = CONFIG.WOOD_DARK
	priceLabel.TextSize = 18
	priceLabel.Font = Enum.Font.FredokaOne
	priceLabel.ZIndex = 203
	priceLabel.Parent = detailPanel
	createCorner(priceLabel, 8)

	-- Status
	local statusLabel = Instance.new("TextLabel")
	statusLabel.Name = "StatusLabel"
	statusLabel.Size = UDim2.new(1, -20, 0, 20)
	statusLabel.Position = UDim2.new(0, 10, 0, 205)
	statusLabel.BackgroundTransparency = 1
	statusLabel.Text = ""
	statusLabel.TextColor3 = CONFIG.LEAF_DARK
	statusLabel.TextSize = 11
	statusLabel.Font = Enum.Font.GothamBold
	statusLabel.ZIndex = 203
	statusLabel.Parent = detailPanel

	-- Buy Button
	local buyBtn = Instance.new("TextButton")
	buyBtn.Name = "BuyButton"
	buyBtn.Size = UDim2.new(1, -20, 0, 36)
	buyBtn.Position = UDim2.new(0, 10, 1, -90)
	buyBtn.BackgroundColor3 = Color3.fromRGB(76, 175, 80)
	buyBtn.BorderSizePixel = 0
	buyBtn.Text = TXT.BUY
	buyBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	buyBtn.TextSize = 14
	buyBtn.Font = Enum.Font.FredokaOne
	buyBtn.ZIndex = 203
	buyBtn.Visible = false
	buyBtn.Parent = detailPanel
	createCorner(buyBtn, 10)
	getOrCreateStroke(buyBtn, Color3.fromRGB(56, 142, 60), 2)

	-- Action Button
	local actionBtn = Instance.new("TextButton")
	actionBtn.Name = "ActionButton"
	actionBtn.Size = UDim2.new(1, -20, 0, 36)
	actionBtn.Position = UDim2.new(0, 10, 1, -48)
	actionBtn.BackgroundColor3 = CONFIG.SKY_BLUE
	actionBtn.BorderSizePixel = 0
	actionBtn.Text = TXT.EQUIP
	actionBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	actionBtn.TextSize = 14
	actionBtn.Font = Enum.Font.FredokaOne
	actionBtn.ZIndex = 203
	actionBtn.Visible = false
	actionBtn.Parent = detailPanel
	createCorner(actionBtn, 10)
	getOrCreateStroke(actionBtn, Color3.fromRGB(70, 130, 180), 2)

	-- Cache UI refs
	uiRefs.overlay = overlay
	uiRefs.mainFrame = mainFrame
	uiRefs.uiScale = uiScale
	uiRefs.honeyValue = honeyValue
	uiRefs.closeBtn = closeBtn
	uiRefs.itemsFrame = itemsFrame
	uiRefs.gridLayout = gridLayout
	uiRefs.previewIcon = previewIcon
	uiRefs.itemName = itemName
	uiRefs.itemDesc = itemDesc
	uiRefs.priceLabel = priceLabel
	uiRefs.statusLabel = statusLabel
	uiRefs.buyBtn = buyBtn
	uiRefs.actionBtn = actionBtn

	return screenGui
end

-- ===== CREATE ITEM CARD =====
local function createItemCard(item)
	local card = Instance.new("TextButton")
	card.Name = item.id
	card.Size = UDim2.new(0, 105, 0, 120)
	card.BackgroundColor3 = CONFIG.CATEGORY_COLORS[item.category] or CONFIG.CREAM
	card.BorderSizePixel = 0
	card.Text = ""
	card.AutoButtonColor = false
	card.ZIndex = 203
	createCorner(card, 10)
	getOrCreateStroke(card, CONFIG.WOOD_DARK, 2)

	-- Icon (server icon mungkin emoji -> bisa jadi "?" juga; sementara fallback "?")
	local icon = Instance.new("TextLabel")
	icon.Size = UDim2.new(0, 50, 0, 50)
	icon.Position = UDim2.new(0.5, 0, 0, 8)
	icon.AnchorPoint = Vector2.new(0.5, 0)
	icon.BackgroundColor3 = CONFIG.CREAM
	icon.BorderSizePixel = 0
	icon.Text = tostring(item.icon or "?")
	icon.TextColor3 = CONFIG.WOOD_DARK
	icon.TextSize = 30
	icon.Font = Enum.Font.GothamBlack
	icon.ZIndex = 204
	icon.Parent = card
	createCorner(icon, 10)

	-- Name
	local name = Instance.new("TextLabel")
	name.Size = UDim2.new(1, -6, 0, 28)
	name.Position = UDim2.new(0, 3, 0, 60)
	name.BackgroundTransparency = 1
	name.Text = tostring(item.name or "")
	name.TextColor3 = CONFIG.WOOD_DARK
	name.TextSize = 10
	name.Font = Enum.Font.GothamBold
	name.TextWrapped = true
	name.ZIndex = 204
	name.Parent = card

	-- Price Badge
	local priceBadge = Instance.new("Frame")
	priceBadge.Size = UDim2.new(0, 70, 0, 18)
	priceBadge.Position = UDim2.new(0.5, 0, 1, -24)
	priceBadge.AnchorPoint = Vector2.new(0.5, 0)
	priceBadge.BackgroundColor3 = CONFIG.HONEY_GOLD
	priceBadge.BorderSizePixel = 0
	priceBadge.ZIndex = 204
	priceBadge.Parent = card
	createCorner(priceBadge, 6)

	local priceText = Instance.new("TextLabel")
	priceText.Size = UDim2.new(1, 0, 1, 0)
	priceText.BackgroundTransparency = 1
	priceText.Text = (TXT.HONEY .. " " .. tostring(item.price or 0))
	priceText.TextColor3 = CONFIG.WOOD_DARK
	priceText.TextSize = 10
	priceText.Font = Enum.Font.GothamBold
	priceText.ZIndex = 205
	priceText.Parent = priceBadge

	-- Owned Badge
	local ownedBadge = Instance.new("TextLabel")
	ownedBadge.Name = "OwnedBadge"
	ownedBadge.Size = UDim2.new(0, 24, 0, 24)
	ownedBadge.Position = UDim2.new(1, -5, 0, 5)
	ownedBadge.AnchorPoint = Vector2.new(1, 0)
	ownedBadge.BackgroundColor3 = CONFIG.LEAF_GREEN
	ownedBadge.BorderSizePixel = 0
	ownedBadge.Text = "OK"
	ownedBadge.TextColor3 = CONFIG.LEAF_DARK
	ownedBadge.TextSize = 10
	ownedBadge.Font = Enum.Font.GothamBold
	ownedBadge.ZIndex = 205
	ownedBadge.Visible = false
	ownedBadge.Parent = card
	createCorner(ownedBadge, 12)

	-- Count Badge
	local countBadge = Instance.new("TextLabel")
	countBadge.Name = "CountBadge"
	countBadge.Size = UDim2.new(0, 24, 0, 24)
	countBadge.Position = UDim2.new(0, 5, 0, 5)
	countBadge.BackgroundColor3 = CONFIG.SKY_BLUE
	countBadge.BorderSizePixel = 0
	countBadge.Text = "0"
	countBadge.TextColor3 = Color3.fromRGB(255, 255, 255)
	countBadge.TextSize = 12
	countBadge.Font = Enum.Font.GothamBold
	countBadge.ZIndex = 205
	countBadge.Visible = false
	countBadge.Parent = card
	createCorner(countBadge, 12)

	return card
end

-- ===== POPULATE ITEMS =====
local function populateItems()
	for _, child in ipairs(uiRefs.itemsFrame:GetChildren()) do
		if child:IsA("TextButton") then
			child:Destroy()
		end
	end

	local count = 0
	for _, item in ipairs(shopData.items) do -- ? FIX
		if item.category == currentCategory then
			local card = createItemCard(item)
			card.Parent = uiRefs.itemsFrame

			if shopData.owned[item.id] then
				card.OwnedBadge.Visible = true
			end
			local c = shopData.consumables[item.id]
			if c and c > 0 then
				card.CountBadge.Text = tostring(c)
				card.CountBadge.Visible = true
			end

			card.MouseButton1Click:Connect(function()
				selectItem(item)
			end)

			count += 1
		end
	end

	local rows = math.ceil(count / 3)
	uiRefs.itemsFrame.CanvasSize = UDim2.new(0, 0, 0, rows * 128 + 16)
end

-- ===== SELECT ITEM =====
selectItem = function(item)
	selectedItem = item

	uiRefs.previewIcon.Text = tostring(item.icon or "?")
	uiRefs.itemName.Text = tostring(item.name or "")
	uiRefs.itemDesc.Text = tostring(item.desc or "")
	uiRefs.priceLabel.Text = TXT.PRICE_PREFIX .. tostring(item.price or 0)

	local isOwned = (shopData.owned[item.id] == true)
	local count = tonumber(shopData.consumables[item.id] or 0) or 0

	local isEquipped = false
	for _, equippedId in pairs(shopData.equipped) do
		if equippedId == item.id then
			isEquipped = true
			break
		end
	end

	if isEquipped then
		uiRefs.statusLabel.Text = TXT.EQUIPPED
		uiRefs.statusLabel.TextColor3 = CONFIG.LEAF_DARK
	elseif isOwned then
		uiRefs.statusLabel.Text = TXT.OWNED
		uiRefs.statusLabel.TextColor3 = CONFIG.LEAF_DARK
	elseif count > 0 then
		uiRefs.statusLabel.Text = TXT.HAVE_PREFIX .. tostring(count)
		uiRefs.statusLabel.TextColor3 = CONFIG.SKY_BLUE
	else
		uiRefs.statusLabel.Text = ""
	end

	if isOwned then
		uiRefs.buyBtn.Visible = false
		if item.category == "cosmetic" then
			uiRefs.actionBtn.Visible = true
			uiRefs.actionBtn.Text = isEquipped and TXT.UNEQUIP or TXT.EQUIP
		else
			uiRefs.actionBtn.Visible = false
		end
	elseif count > 0 then
		uiRefs.buyBtn.Visible = true
		uiRefs.buyBtn.Text = TXT.BUY_AGAIN
		uiRefs.actionBtn.Visible = true
		uiRefs.actionBtn.Text = TXT.USE
	else
		uiRefs.buyBtn.Visible = true
		uiRefs.buyBtn.Text = TXT.BUY
		uiRefs.actionBtn.Visible = false
	end

	if shopData.honeyPoints < (item.price or 0) then
		uiRefs.buyBtn.BackgroundColor3 = Color3.fromRGB(180, 180, 180)
	else
		uiRefs.buyBtn.BackgroundColor3 = Color3.fromRGB(76, 175, 80)
	end
end

-- ===== UPDATE UI =====
local function updateUI()
	uiRefs.honeyValue.Text = tostring(shopData.honeyPoints or 0)

	for catId, t in pairs(uiRefs.tabButtons) do
		local btn = t.btn
		local stroke = t.stroke
		if catId == currentCategory then
			btn.BackgroundTransparency = 0
			stroke.Thickness = 3
		else
			btn.BackgroundTransparency = 0.3
			stroke.Thickness = 2
		end
	end

	populateItems()

	if selectedItem then
		selectItem(selectedItem)
	end
end

-- ===== SCALE =====
local function calculateScale(): number
	local camera = workspace.CurrentCamera
	if not camera then return 1 end
	local viewportSize = camera.ViewportSize
	local scaleX = (viewportSize.X - 40) / 600
	local scaleY = (viewportSize.Y - 60) / 420
	return math.clamp(math.min(scaleX, scaleY), 0.5, 1)
end

-- ===== OPEN/CLOSE =====
local function openShop()
	if isOpen or isAnimating then return end
	isAnimating = true

	local ok, data = pcall(function()
		return shopFunction:InvokeServer("GetShopData")
	end)

	if ok and type(data) == "table" then
		shopData.items = data.items or {}
		shopData.owned = data.owned or {}
		shopData.consumables = data.consumables or {}
		shopData.equipped = data.equipped or {}
		shopData.activeBoosts = data.activeBoosts or {}
		shopData.honeyPoints = data.honeyPoints or 0
	end

	updateUI()

	uiRefs.uiScale.Scale = calculateScale()
	uiRefs.overlay.BackgroundTransparency = 1
	uiRefs.overlay.Visible = true
	uiRefs.mainFrame.Visible = true

	TweenService:Create(uiRefs.overlay, TweenInfo.new(0.2), { BackgroundTransparency = 0.5 }):Play()

	task.delay(0.2, function()
		isOpen = true
		isAnimating = false
	end)
end

local function closeShop()
	if not isOpen or isAnimating then return end
	isAnimating = true

	local tween = TweenService:Create(uiRefs.overlay, TweenInfo.new(0.15), { BackgroundTransparency = 1 })
	tween:Play()

	tween.Completed:Connect(function()
		uiRefs.mainFrame.Visible = false
		uiRefs.overlay.Visible = false
		isOpen = false
		isAnimating = false
	end)
end

-- ===== HANDLERS =====
local function setupHandlers()
	uiRefs.closeBtn.MouseButton1Click:Connect(closeShop)

	uiRefs.overlay.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			closeShop()
		end
	end)

	for catId, t in pairs(uiRefs.tabButtons) do
		t.btn.MouseButton1Click:Connect(function()
			currentCategory = catId
			selectedItem = nil
			updateUI()
		end)
	end

	uiRefs.buyBtn.MouseButton1Click:Connect(function()
		if not selectedItem then return end
		if (shopData.honeyPoints or 0) < (selectedItem.price or 0) then return end

		local ok, result = pcall(function()
			return shopFunction:InvokeServer("Purchase", selectedItem.id)
		end)

		if ok and result and result.success then
			shopData.honeyPoints = result.honeyPoints or shopData.honeyPoints
			shopData.owned = result.owned or shopData.owned
			shopData.consumables = result.consumables or shopData.consumables
			updateUI()
		end
	end)

	uiRefs.actionBtn.MouseButton1Click:Connect(function()
		if not selectedItem then return end

		local action = "Equip"
		if selectedItem.stackable then
			action = "Use"
		end

		local ok, result = pcall(function()
			return shopFunction:InvokeServer(action, selectedItem.id)
		end)

		if ok and result and result.success then
			if result.equipped then shopData.equipped = result.equipped end
			if result.consumables then shopData.consumables = result.consumables end
			updateUI()
		end
	end)
end

-- ===== INIT =====
local mainGui = buildUI()
mainGui.Parent = playerGui
setupHandlers()

-- Connect ke tombol ShopButton dari DailyQuestUI (kalau ada)
task.spawn(function()
	local dailyQuestGui = playerGui:WaitForChild("DailyQuestUI", 10)
	if not dailyQuestGui then return end
	local mainFrame = dailyQuestGui:WaitForChild("MainFrame", 5)
	if not mainFrame then return end
	local bottomFrame = mainFrame:FindFirstChild("BottomFrame")
	if not bottomFrame then return end
	local shopBtn = bottomFrame:FindFirstChild("ShopButton")
	if not shopBtn then return end

	shopBtn.MouseButton1Click:Connect(openShop)
end)

-- Shortcut P
UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.P then
		if isOpen then closeShop() else openShop() end
	end
end)

-- Camera resize nil-safe
task.spawn(function()
	local cam = workspace.CurrentCamera or workspace:WaitForChild("Camera", 10)
	if not cam then return end
	cam:GetPropertyChangedSignal("ViewportSize"):Connect(function()
		if isOpen and not isAnimating and uiRefs.uiScale then
			uiRefs.uiScale.Scale = calculateScale()
		end
	end)
end)

print("[HoneyShop] Client ready!")
