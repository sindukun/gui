-- DailyQuestClient.lua (UPDATED)
-- Client script untuk UI Daily Quest Mount Semut
-- ? UI selalu dibuat (tidak return kalau remote telat muncul)
-- ? Hapus tombol "Claim All" + bersihkan semua mekanismenya
-- ? Tombol "Tukar Honey" di tengah
-- ? Ikon dipulihkan (emoji) + UTF-8 safe
-- Taruh di StarterPlayerScripts

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local StarterGui = game:GetService("StarterGui")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- ===== CONFIG =====
local CONFIG = {
	-- Colors (Pastel & Honey Theme)
	HONEY_GOLD   = Color3.fromRGB(255, 214, 64),
	HONEY_ORANGE = Color3.fromRGB(255, 170, 0),
	HONEY_DARK   = Color3.fromRGB(139, 69, 19),

	LEAF_GREEN = Color3.fromRGB(152, 251, 152),
	LEAF_DARK  = Color3.fromRGB(107, 142, 35),

	SKY_BLUE   = Color3.fromRGB(135, 206, 235),
	WOOD_LIGHT = Color3.fromRGB(222, 184, 135),
	WOOD_DARK  = Color3.fromRGB(139, 90, 43),
	CREAM      = Color3.fromRGB(255, 248, 220),

	OPEN_KEY = Enum.KeyCode.Q,
	MOBILE_BUTTON = true,
}

-- ===== REMOTES (late-bind; bisa telat replicate di game besar) =====
local questRemote: RemoteEvent? = nil
local questFunction: RemoteFunction? = nil
local remotesReady = false

-- ===== STATE =====
local questData = {
	quest1Progress = 0,
	quest1Target = 1,
	quest1Claimed = false,
	quest1Reward = 3,

	quest2Progress = 0,
	quest2Target = 600,
	quest2Claimed = false,
	quest2Reward = 2,

	rescueBonusEarned = 0,
	rescueBonusMax = 10,

	honeyPoints = 0,
	resetTimer = "00:00:00",
}

local isOpen = false
local isAnimating = false
local mainGui: ScreenGui? = nil

-- Cache UI refs
local uiRefs: {[string]: any} = {}

-- ===== HELPERS =====
local function notify(title: string, text: string)
	pcall(function()
		StarterGui:SetCore("SendNotification", {
			Title = title,
			Text = text,
			Duration = 2.5,
		})
	end)
end

local function formatTime(seconds: number): string
	local m = math.floor(seconds / 60)
	local s = math.floor(seconds % 60)
	return string.format("%d:%02d", m, s)
end

local function createCorner(parent: Instance, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = parent
end

local function createStroke(parent: Instance, color: Color3, thickness: number)
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = thickness
	stroke.Parent = parent
end

local function createGradient(parent: Instance, c1: Color3, c2: Color3, rotation: number?)
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new(c1, c2)
	gradient.Rotation = rotation or 90
	gradient.Parent = parent
end

-- ===== UI BUILD =====
local function buildUI(): ScreenGui
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "DailyQuestUI"
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
	overlay.ZIndex = 100
	overlay.Visible = false
	overlay.Parent = screenGui

	-- Main Frame (540 x 320)
	local mainFrame = Instance.new("Frame")
	mainFrame.Name = "MainFrame"
	mainFrame.Size = UDim2.new(0, 540, 0, 320)
	mainFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
	mainFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	mainFrame.BackgroundColor3 = CONFIG.SKY_BLUE
	mainFrame.BorderSizePixel = 0
	mainFrame.Visible = false
	mainFrame.ZIndex = 101
	mainFrame.Parent = screenGui
	createCorner(mainFrame, 16)
	createGradient(mainFrame, CONFIG.SKY_BLUE, CONFIG.LEAF_GREEN, 180)
	createStroke(mainFrame, CONFIG.WOOD_DARK, 4)

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
	header.ZIndex = 102
	header.Parent = mainFrame
	createCorner(header, 12)
	createGradient(header, Color3.fromRGB(255, 228, 181), CONFIG.HONEY_ORANGE, 135)
	createStroke(header, CONFIG.HONEY_DARK, 2)

	-- Title
	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "Title"
	titleLabel.Size = UDim2.new(0, 170, 0, 24)
	titleLabel.Position = UDim2.new(0, 15, 0, 5)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Text = "Daily Quest ??"
	titleLabel.TextColor3 = CONFIG.WOOD_DARK
	titleLabel.TextSize = 18
	titleLabel.Font = Enum.Font.GothamBold
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.ZIndex = 103
	titleLabel.Parent = header

	-- Reset Timer
	local resetLabel = Instance.new("TextLabel")
	resetLabel.Name = "ResetTimer"
	resetLabel.Size = UDim2.new(0, 170, 0, 16)
	resetLabel.Position = UDim2.new(0, 15, 0, 30)
	resetLabel.BackgroundTransparency = 1
	resetLabel.Text = "? Reset: 00:00:00"
	resetLabel.TextColor3 = CONFIG.HONEY_DARK
	resetLabel.TextSize = 11
	resetLabel.Font = Enum.Font.GothamBold
	resetLabel.TextXAlignment = Enum.TextXAlignment.Left
	resetLabel.ZIndex = 103
	resetLabel.Parent = header

	-- Honey Display
	local honeyFrame = Instance.new("Frame")
	honeyFrame.Name = "HoneyDisplay"
	honeyFrame.Size = UDim2.new(0, 100, 0, 36)
	honeyFrame.Position = UDim2.new(0, 200, 0.5, 0)
	honeyFrame.AnchorPoint = Vector2.new(0, 0.5)
	honeyFrame.BackgroundColor3 = CONFIG.CREAM
	honeyFrame.BorderSizePixel = 0
	honeyFrame.ZIndex = 103
	honeyFrame.Parent = header
	createCorner(honeyFrame, 10)
	createStroke(honeyFrame, Color3.fromRGB(218, 165, 32), 2)

	local honeyIcon = Instance.new("TextLabel")
	honeyIcon.Name = "HoneyIcon"
	honeyIcon.Size = UDim2.new(0, 30, 1, 0)
	honeyIcon.Position = UDim2.new(0, 6, 0, 0)
	honeyIcon.BackgroundTransparency = 1
	honeyIcon.Text = "??"
	honeyIcon.TextSize = 20
	honeyIcon.Font = Enum.Font.GothamBold
	honeyIcon.ZIndex = 104
	honeyIcon.Parent = honeyFrame

	local honeyValue = Instance.new("TextLabel")
	honeyValue.Name = "HoneyValue"
	honeyValue.Size = UDim2.new(0, 58, 1, 0)
	honeyValue.Position = UDim2.new(0, 38, 0, 0)
	honeyValue.BackgroundTransparency = 1
	honeyValue.Text = "0"
	honeyValue.TextColor3 = Color3.fromRGB(210, 105, 30)
	honeyValue.TextSize = 20
	honeyValue.Font = Enum.Font.GothamBold
	honeyValue.TextXAlignment = Enum.TextXAlignment.Left
	honeyValue.ZIndex = 104
	honeyValue.Parent = honeyFrame

	-- Bonus Display
	local bonusFrame = Instance.new("Frame")
	bonusFrame.Name = "BonusDisplay"
	bonusFrame.Size = UDim2.new(0, 85, 0, 36)
	bonusFrame.Position = UDim2.new(0, 315, 0.5, 0)
	bonusFrame.AnchorPoint = Vector2.new(0, 0.5)
	bonusFrame.BackgroundColor3 = CONFIG.LEAF_GREEN
	bonusFrame.BorderSizePixel = 0
	bonusFrame.ZIndex = 103
	bonusFrame.Parent = header
	createCorner(bonusFrame, 10)
	createGradient(bonusFrame, Color3.fromRGB(152, 251, 152), Color3.fromRGB(50, 205, 50), 135)
	createStroke(bonusFrame, Color3.fromRGB(34, 139, 34), 2)

	local bonusLabel = Instance.new("TextLabel")
	bonusLabel.Name = "BonusLabel"
	bonusLabel.Size = UDim2.new(1, 0, 0, 14)
	bonusLabel.Position = UDim2.new(0, 0, 0, 3)
	bonusLabel.BackgroundTransparency = 1
	bonusLabel.Text = "Bonus"
	bonusLabel.TextColor3 = Color3.fromRGB(0, 100, 0)
	bonusLabel.TextSize = 10
	bonusLabel.Font = Enum.Font.GothamBold
	bonusLabel.ZIndex = 104
	bonusLabel.Parent = bonusFrame

	local bonusValue = Instance.new("TextLabel")
	bonusValue.Name = "BonusValue"
	bonusValue.Size = UDim2.new(1, 0, 0, 18)
	bonusValue.Position = UDim2.new(0, 0, 0, 16)
	bonusValue.BackgroundTransparency = 1
	bonusValue.Text = "0/10"
	bonusValue.TextColor3 = Color3.fromRGB(34, 139, 34)
	bonusValue.TextSize = 14
	bonusValue.Font = Enum.Font.GothamBold
	bonusValue.ZIndex = 104
	bonusValue.Parent = bonusFrame

	-- Close Button
	local closeBtn = Instance.new("TextButton")
	closeBtn.Name = "CloseButton"
	closeBtn.Size = UDim2.new(0, 32, 0, 32)
	closeBtn.Position = UDim2.new(1, -10, 0.5, 0)
	closeBtn.AnchorPoint = Vector2.new(1, 0.5)
	closeBtn.BackgroundColor3 = Color3.fromRGB(255, 100, 100)
	closeBtn.BorderSizePixel = 0
	closeBtn.Text = "?"
	closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	closeBtn.TextSize = 18
	closeBtn.Font = Enum.Font.GothamBold
	closeBtn.ZIndex = 104
	closeBtn.Parent = header
	createCorner(closeBtn, 16)
	createStroke(closeBtn, Color3.fromRGB(180, 60, 60), 2)

	-- ===== QUEST CARDS =====
	local cardsContainer = Instance.new("Frame")
	cardsContainer.Name = "CardsContainer"
	cardsContainer.Size = UDim2.new(1, -20, 0, 130)
	cardsContainer.Position = UDim2.new(0, 10, 0, 70)
	cardsContainer.BackgroundTransparency = 1
	cardsContainer.ZIndex = 102
	cardsContainer.Parent = mainFrame

	local function createQuestCard(name: string, icon: string, title: string, subtitle: string, reward: number, bgColor: Color3, borderColor: Color3, posX: number)
		local card = Instance.new("Frame")
		card.Name = name
		card.Size = UDim2.new(0, 250, 0, 130)
		card.Position = UDim2.new(0, posX, 0, 0)
		card.BackgroundColor3 = bgColor
		card.BorderSizePixel = 0
		card.ZIndex = 103
		card.Parent = cardsContainer
		createCorner(card, 12)
		createStroke(card, borderColor, 2)

		-- Icon
		local iconFrame = Instance.new("Frame")
		iconFrame.Name = "IconFrame"
		iconFrame.Size = UDim2.new(0, 42, 0, 42)
		iconFrame.Position = UDim2.new(0, 10, 0, 10)
		iconFrame.BackgroundColor3 = CONFIG.HONEY_GOLD
		iconFrame.BorderSizePixel = 0
		iconFrame.ZIndex = 104
		iconFrame.Parent = card
		createCorner(iconFrame, 10)
		createStroke(iconFrame, Color3.fromRGB(218, 165, 32), 2)

		local iconLabel = Instance.new("TextLabel")
		iconLabel.Name = "Icon"
		iconLabel.Size = UDim2.new(1, 0, 1, 0)
		iconLabel.BackgroundTransparency = 1
		iconLabel.Text = icon
		iconLabel.TextSize = 24
		iconLabel.Font = Enum.Font.GothamBold
		iconLabel.ZIndex = 105
		iconLabel.Parent = iconFrame

		-- Title
		local titleLbl = Instance.new("TextLabel")
		titleLbl.Name = "Title"
		titleLbl.Size = UDim2.new(0, 150, 0, 18)
		titleLbl.Position = UDim2.new(0, 58, 0, 10)
		titleLbl.BackgroundTransparency = 1
		titleLbl.Text = title
		titleLbl.TextColor3 = borderColor
		titleLbl.TextSize = 14
		titleLbl.Font = Enum.Font.GothamBold
		titleLbl.TextXAlignment = Enum.TextXAlignment.Left
		titleLbl.ZIndex = 104
		titleLbl.Parent = card

		-- Subtitle
		local subLbl = Instance.new("TextLabel")
		subLbl.Name = "Subtitle"
		subLbl.Size = UDim2.new(0, 80, 0, 14)
		subLbl.Position = UDim2.new(0, 58, 0, 28)
		subLbl.BackgroundTransparency = 1
		subLbl.Text = subtitle
		subLbl.TextColor3 = Color3.fromRGB(100, 100, 90)
		subLbl.TextSize = 10
		subLbl.Font = Enum.Font.GothamMedium
		subLbl.TextXAlignment = Enum.TextXAlignment.Left
		subLbl.ZIndex = 104
		subLbl.Parent = card

		-- Reward Badge
		local rewardBadge = Instance.new("Frame")
		rewardBadge.Name = "RewardBadge"
		rewardBadge.Size = UDim2.new(0, 56, 0, 24)
		rewardBadge.Position = UDim2.new(1, -10, 0, 10)
		rewardBadge.AnchorPoint = Vector2.new(1, 0)
		rewardBadge.BackgroundColor3 = CONFIG.HONEY_GOLD
		rewardBadge.BorderSizePixel = 0
		rewardBadge.ZIndex = 104
		rewardBadge.Parent = card
		createCorner(rewardBadge, 8)
		createStroke(rewardBadge, Color3.fromRGB(255, 140, 0), 2)

		local rewardText = Instance.new("TextLabel")
		rewardText.Name = "RewardText"
		rewardText.Size = UDim2.new(1, 0, 1, 0)
		rewardText.BackgroundTransparency = 1
		rewardText.Text = "+" .. tostring(reward) .. "??"
		rewardText.TextColor3 = CONFIG.HONEY_DARK
		rewardText.TextSize = 11
		rewardText.Font = Enum.Font.GothamBold
		rewardText.ZIndex = 105
		rewardText.Parent = rewardBadge

		-- Progress Bar
		local progressBg = Instance.new("Frame")
		progressBg.Name = "ProgressBg"
		progressBg.Size = UDim2.new(1, -20, 0, 18)
		progressBg.Position = UDim2.new(0, 10, 0, 55)
		progressBg.BackgroundColor3 = Color3.fromRGB(80, 60, 40)
		progressBg.BackgroundTransparency = 0.6
		progressBg.BorderSizePixel = 0
		progressBg.ZIndex = 104
		progressBg.Parent = card
		createCorner(progressBg, 9)
		createStroke(progressBg, borderColor, 2)

		local progressFill = Instance.new("Frame")
		progressFill.Name = "ProgressFill"
		progressFill.Size = UDim2.new(0, 0, 1, -4)
		progressFill.Position = UDim2.new(0, 2, 0, 2)
		progressFill.BackgroundColor3 = CONFIG.HONEY_GOLD
		progressFill.BorderSizePixel = 0
		progressFill.ZIndex = 105
		progressFill.Parent = progressBg
		createCorner(progressFill, 7)

		local progressText = Instance.new("TextLabel")
		progressText.Name = "ProgressText"
		progressText.Size = UDim2.new(1, 0, 1, 0)
		progressText.BackgroundTransparency = 1
		progressText.Text = "0/1"
		progressText.TextColor3 = Color3.fromRGB(255, 255, 255)
		progressText.TextSize = 11
		progressText.Font = Enum.Font.GothamBold
		progressText.ZIndex = 106
		progressText.Parent = progressBg

		-- Note for Quest 1
		if name == "Quest1Card" then
			local note = Instance.new("TextLabel")
			note.Name = "Note"
			note.Size = UDim2.new(1, -20, 0, 12)
			note.Position = UDim2.new(0, 10, 0, 75)
			note.BackgroundTransparency = 1
			note.Text = "?? +1 Honey/rescue (max 10/hari)"
			note.TextColor3 = Color3.fromRGB(90, 140, 50)
			note.TextSize = 9
			note.Font = Enum.Font.GothamMedium
			note.TextXAlignment = Enum.TextXAlignment.Left
			note.ZIndex = 104
			note.Parent = card
		end

		-- Claim Button
		local claimBtn = Instance.new("TextButton")
		claimBtn.Name = "ClaimButton"
		claimBtn.Size = UDim2.new(1, -20, 0, 28)
		claimBtn.Position = UDim2.new(0, 10, 1, -38)
		claimBtn.BackgroundColor3 = Color3.fromRGB(180, 180, 180)
		claimBtn.BorderSizePixel = 0
		claimBtn.Text = "? Belum Selesai"
		claimBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
		claimBtn.TextSize = 11
		claimBtn.Font = Enum.Font.GothamBold
		claimBtn.AutoButtonColor = false
		claimBtn.ZIndex = 104
		claimBtn.Parent = card
		createCorner(claimBtn, 8)
		createStroke(claimBtn, Color3.fromRGB(150, 150, 150), 2)

		return card
	end

	createQuestCard("Quest1Card", "??", "Selamatkan Lebah", "1x / hari", 3,
		Color3.fromRGB(235, 255, 235), CONFIG.LEAF_DARK, 0)

	createQuestCard("Quest2Card", "?", "Main 10 Menit", "Per hari", 2,
		Color3.fromRGB(255, 250, 230), Color3.fromRGB(249, 168, 37), 260)

	-- ===== BOTTOM SECTION =====
	local bottomFrame = Instance.new("Frame")
	bottomFrame.Name = "BottomFrame"
	bottomFrame.Size = UDim2.new(1, -20, 0, 100)
	bottomFrame.Position = UDim2.new(0, 10, 0, 210)
	bottomFrame.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	bottomFrame.BackgroundTransparency = 0.1
	bottomFrame.BorderSizePixel = 0
	bottomFrame.ZIndex = 102
	bottomFrame.Parent = mainFrame
	createCorner(bottomFrame, 12)
	createStroke(bottomFrame, CONFIG.WOOD_LIGHT, 2)

	-- Shop Button (CENTER)
	local shopBtn = Instance.new("TextButton")
	shopBtn.Name = "ShopButton"
	shopBtn.Size = UDim2.new(0, 200, 0, 38)
	shopBtn.Position = UDim2.new(0.5, 0, 0, 10)
	shopBtn.AnchorPoint = Vector2.new(0.5, 0)
	shopBtn.BackgroundColor3 = CONFIG.WOOD_LIGHT
	shopBtn.BorderSizePixel = 0
	shopBtn.Text = "?? Tukar Honey"
	shopBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	shopBtn.TextSize = 13
	shopBtn.Font = Enum.Font.GothamBold
	shopBtn.ZIndex = 103
	shopBtn.Parent = bottomFrame
	createCorner(shopBtn, 10)
	createGradient(shopBtn, CONFIG.WOOD_LIGHT, Color3.fromRGB(180, 90, 20), 180)
	createStroke(shopBtn, CONFIG.HONEY_DARK, 2)

	-- Info
	local infoLabel = Instance.new("TextLabel")
	infoLabel.Name = "Info"
	infoLabel.Size = UDim2.new(1, -30, 0, 16)
	infoLabel.Position = UDim2.new(0, 15, 0, 56)
	infoLabel.BackgroundTransparency = 1
	infoLabel.Text = "?? Honey untuk membeli item & cosmetic"
	infoLabel.TextColor3 = CONFIG.HONEY_DARK
	infoLabel.TextSize = 10
	infoLabel.Font = Enum.Font.GothamMedium
	infoLabel.TextXAlignment = Enum.TextXAlignment.Left
	infoLabel.ZIndex = 103
	infoLabel.Parent = bottomFrame

	-- Mascot
	local mascot = Instance.new("TextLabel")
	mascot.Name = "Mascot"
	mascot.Size = UDim2.new(0, 50, 0, 50)
	mascot.Position = UDim2.new(1, -60, 0, 44)
	mascot.BackgroundTransparency = 1
	mascot.Text = "??"
	mascot.TextSize = 28
	mascot.Font = Enum.Font.GothamBold
	mascot.ZIndex = 103
	mascot.Parent = bottomFrame

	-- Speech Bubble
	local bubble = Instance.new("Frame")
	bubble.Name = "Bubble"
	bubble.Size = UDim2.new(0, 60, 0, 20)
	bubble.Position = UDim2.new(1, -116, 0, 52)
	bubble.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	bubble.BorderSizePixel = 0
	bubble.ZIndex = 103
	bubble.Parent = bottomFrame
	createCorner(bubble, 8)

	local bubbleText = Instance.new("TextLabel")
	bubbleText.Name = "BubbleText"
	bubbleText.Size = UDim2.new(1, 0, 1, 0)
	bubbleText.BackgroundTransparency = 1
	bubbleText.Text = "Ayo! ??"
	bubbleText.TextColor3 = CONFIG.WOOD_DARK
	bubbleText.TextSize = 10
	bubbleText.Font = Enum.Font.GothamBold
	bubbleText.ZIndex = 104
	bubbleText.Parent = bubble

	-- Cache refs
	uiRefs.overlay = overlay
	uiRefs.mainFrame = mainFrame
	uiRefs.uiScale = uiScale
	uiRefs.resetTimer = resetLabel
	uiRefs.honeyValue = honeyValue
	uiRefs.bonusValue = bonusValue
	uiRefs.closeBtn = closeBtn
	uiRefs.shopBtn = shopBtn

	local q1 = cardsContainer:FindFirstChild("Quest1Card")
	local q2 = cardsContainer:FindFirstChild("Quest2Card")

	uiRefs.quest1 = {
		fill = q1.ProgressBg.ProgressFill,
		text = q1.ProgressBg.ProgressText,
		btn  = q1.ClaimButton,
	}
	uiRefs.quest2 = {
		fill = q2.ProgressBg.ProgressFill,
		text = q2.ProgressBg.ProgressText,
		btn  = q2.ClaimButton,
	}

	return screenGui
end

-- ===== MOBILE OPEN BUTTON =====
local function createMobileButton(parent: Instance)
	local btn = Instance.new("TextButton")
	btn.Name = "OpenButton"
	btn.Size = UDim2.new(0, 50, 0, 50)
	btn.Position = UDim2.new(0, 15, 0.5, -80)
	btn.BackgroundColor3 = CONFIG.HONEY_GOLD
	btn.BorderSizePixel = 0
	btn.Text = "??"
	btn.TextSize = 26
	btn.Font = Enum.Font.GothamBold
	btn.ZIndex = 50
	btn.Parent = parent
	createCorner(btn, 25)
	createStroke(btn, CONFIG.HONEY_DARK, 3)

	uiRefs.openBtn = btn
	return btn
end

-- ===== UI UPDATE =====
local function updateUI()
	if not uiRefs.honeyValue then return end

	uiRefs.honeyValue.Text = tostring(questData.honeyPoints)
	uiRefs.bonusValue.Text = tostring(questData.rescueBonusEarned) .. "/" .. tostring(questData.rescueBonusMax)

	if uiRefs.resetTimer then
		uiRefs.resetTimer.Text = "? Reset: " .. tostring(questData.resetTimer)
	end

	-- Quest 1
	local q1 = uiRefs.quest1
	local pct1 = 0
	if questData.quest1Target > 0 then
		pct1 = math.clamp(questData.quest1Progress / questData.quest1Target, 0, 1)
	end
	q1.fill.Size = UDim2.new(pct1, -4, 1, -4)
	q1.fill.BackgroundColor3 = (pct1 >= 1) and Color3.fromRGB(50, 200, 50) or CONFIG.HONEY_GOLD
	q1.text.Text = tostring(questData.quest1Progress) .. "/" .. tostring(questData.quest1Target)

	if questData.quest1Claimed then
		q1.btn.Text = "? Sudah Diklaim"
		q1.btn.BackgroundColor3 = Color3.fromRGB(150, 150, 150)
	elseif pct1 >= 1 then
		q1.btn.Text = "?? CLAIM +" .. tostring(questData.quest1Reward) .. " ??"
		q1.btn.BackgroundColor3 = Color3.fromRGB(76, 175, 80)
	else
		q1.btn.Text = "? Belum Selesai"
		q1.btn.BackgroundColor3 = Color3.fromRGB(180, 180, 180)
	end

	-- Quest 2
	local q2 = uiRefs.quest2
	local pct2 = 0
	if questData.quest2Target > 0 then
		pct2 = math.clamp(questData.quest2Progress / questData.quest2Target, 0, 1)
	end
	q2.fill.Size = UDim2.new(pct2, -4, 1, -4)
	q2.fill.BackgroundColor3 = (pct2 >= 1) and Color3.fromRGB(50, 200, 50) or Color3.fromRGB(66, 165, 245)
	q2.text.Text = formatTime(questData.quest2Progress) .. "/" .. formatTime(questData.quest2Target)

	if questData.quest2Claimed then
		q2.btn.Text = "? Sudah Diklaim"
		q2.btn.BackgroundColor3 = Color3.fromRGB(150, 150, 150)
	elseif pct2 >= 1 then
		q2.btn.Text = "?? CLAIM +" .. tostring(questData.quest2Reward) .. " ??"
		q2.btn.BackgroundColor3 = Color3.fromRGB(255, 152, 0)
	else
		q2.btn.Text = "? Belum Selesai"
		q2.btn.BackgroundColor3 = Color3.fromRGB(180, 180, 180)
	end
end

-- ===== SCALE =====
local function calculateScale(): number
	local camera = workspace.CurrentCamera
	if not camera then return 1 end

	local viewportSize = camera.ViewportSize
	local scaleX = (viewportSize.X - 40) / 540
	local scaleY = (viewportSize.Y - 60) / 320
	return math.clamp(math.min(scaleX, scaleY), 0.5, 1)
end

-- ===== DATA FETCH =====
local function fetchData()
	if not remotesReady or not questFunction then return end

	local ok, data = pcall(function()
		return questFunction:InvokeServer("GetData")
	end)

	if ok and type(data) == "table" then
		for k, v in pairs(data) do
			questData[k] = v
		end
		updateUI()
	end
end

-- ===== OPEN/CLOSE =====
local function openUI()
	if isOpen or isAnimating then return end
	isAnimating = true

	fetchData()

	uiRefs.uiScale.Scale = calculateScale()
	uiRefs.overlay.BackgroundTransparency = 1
	uiRefs.overlay.Visible = true
	uiRefs.mainFrame.Visible = true

	TweenService:Create(uiRefs.overlay, TweenInfo.new(0.2), {
		BackgroundTransparency = 0.5
	}):Play()

	task.delay(0.2, function()
		isOpen = true
		isAnimating = false
	end)
end

local function closeUI()
	if not isOpen or isAnimating then return end
	isAnimating = true

	local tween = TweenService:Create(uiRefs.overlay, TweenInfo.new(0.15), {
		BackgroundTransparency = 1
	})
	tween:Play()

	tween.Completed:Connect(function()
		uiRefs.mainFrame.Visible = false
		uiRefs.overlay.Visible = false
		isOpen = false
		isAnimating = false
	end)
end

local function toggleUI()
	if isAnimating then return end
	if isOpen then closeUI() else openUI() end
end

-- ===== HANDLERS =====
local function setupHandlers()
	-- Close
	uiRefs.closeBtn.MouseButton1Click:Connect(closeUI)
	uiRefs.overlay.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			closeUI()
		end
	end)

	-- Quest 1 Claim
	uiRefs.quest1.btn.MouseButton1Click:Connect(function()
		if questData.quest1Claimed or questData.quest1Progress < questData.quest1Target then return end
		if not remotesReady or not questFunction then
			notify("Daily Quest", "Server belum siap, coba sebentar lagi.")
			return
		end

		local ok, result = pcall(function()
			return questFunction:InvokeServer("ClaimQuest", 1)
		end)

		if ok and result and result.success then
			questData.quest1Claimed = true
			questData.honeyPoints = result.honeyPoints or questData.honeyPoints
			updateUI()
		end
	end)

	-- Quest 2 Claim
	uiRefs.quest2.btn.MouseButton1Click:Connect(function()
		if questData.quest2Claimed or questData.quest2Progress < questData.quest2Target then return end
		if not remotesReady or not questFunction then
			notify("Daily Quest", "Server belum siap, coba sebentar lagi.")
			return
		end

		local ok, result = pcall(function()
			return questFunction:InvokeServer("ClaimQuest", 2)
		end)

		if ok and result and result.success then
			questData.quest2Claimed = true
			questData.honeyPoints = result.honeyPoints or questData.honeyPoints
			updateUI()
		end
	end)

	-- Shop
	uiRefs.shopBtn.MouseButton1Click:Connect(function()
		-- Nanti bisa kamu hubungkan ke HoneyShop GUI kamu
		print("[DailyQuest] Shop clicked")
	end)

	-- Mobile open button
	if uiRefs.openBtn then
		uiRefs.openBtn.MouseButton1Click:Connect(openUI)
	end
end

-- ===== REMOTE HOOK =====
local function hookRemotes()
	-- Guard
	if not questRemote then return end

	questRemote.OnClientEvent:Connect(function(action, data)
		if action == "InitData" and type(data) == "table" then
			for k, v in pairs(data) do
				questData[k] = v
			end
			if isOpen then updateUI() end

		elseif action == "BeeRescueUpdate" and type(data) == "table" then
			questData.quest1Progress = data.quest1Progress or questData.quest1Progress
			questData.rescueBonusEarned = data.rescueBonusEarned or questData.rescueBonusEarned
			questData.honeyPoints = data.honeyPoints or questData.honeyPoints
			if isOpen then updateUI() end

		elseif action == "PlaytimeUpdate" and type(data) == "table" then
			questData.quest2Progress = data.progress or questData.quest2Progress
			if isOpen then updateUI() end

		elseif action == "HoneyUpdate" then
			if typeof(data) == "number" then
				questData.honeyPoints = data
				if isOpen then updateUI() end
			end

		elseif action == "ResetTimer" then
			questData.resetTimer = tostring(data or questData.resetTimer)
			if isOpen and uiRefs.resetTimer then
				uiRefs.resetTimer.Text = "? Reset: " .. questData.resetTimer
			end
		end
	end)
end

-- ===== INPUT =====
UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == CONFIG.OPEN_KEY then
		toggleUI()
	end
end)

-- ===== CAMERA RESIZE SAFE =====
local camConn: RBXScriptConnection? = nil
local function attachCamera(cam: Camera?)
	if camConn then camConn:Disconnect(); camConn = nil end
	if not cam then return end

	camConn = cam:GetPropertyChangedSignal("ViewportSize"):Connect(function()
		if isOpen and not isAnimating and uiRefs.uiScale then
			uiRefs.uiScale.Scale = calculateScale()
		end
	end)
end

workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
	attachCamera(workspace.CurrentCamera)
end)
attachCamera(workspace.CurrentCamera)

-- ===== INIT =====
mainGui = buildUI()
mainGui.Parent = playerGui

if CONFIG.MOBILE_BUTTON then
	createMobileButton(mainGui)
end

setupHandlers()
updateUI()

-- Late-bind remotes (tidak bikin UI hilang)
task.spawn(function()
	questRemote = ReplicatedStorage:WaitForChild("DailyQuest_Remote") :: RemoteEvent
	questFunction = ReplicatedStorage:WaitForChild("DailyQuest_Function") :: RemoteFunction
	remotesReady = true

	hookRemotes()
	fetchData()
end)

print("[DailyQuest] Client ready! ?")
