--[[
    GamepassConfig.lua (v4 - GIFT DEVELOPER PRODUCT)
    ✅ Tambah GiftProductId per pass (Developer Product untuk gift)
    ✅ Tambah Giftable field
    ✅ Tambah ById_Gift lookup
]]

local GC = {}

GC.CategoryOrder = {
	Farming = 1,
	Boost   = 2,
	Fun     = 3,
	Premium = 4,
}

GC.GIFT_ATTRIBUTE_PREFIX = "GP_"

GC.Passes = {
	--                                                                                                        ↓ GANTI DENGAN ID ASLI DARI ROBLOX
	{ Name = "DoublePanen",  Icon = "🌾", Price = 50,  GamepassId = 1711326948, GiftProductId = 3534985546, Category = "Farming", SortOrder = 1, Giftable = true  },
	{ Name = "FastGrow",     Icon = "⚡", Price = 75,  GamepassId = 1711410899, GiftProductId = 3542169435, Category = "Farming", SortOrder = 2, Giftable = true  },
	{ Name = "ExtraSlots",   Icon = "📦", Price = 99,  GamepassId = 1709346337, GiftProductId = 3542169045, Category = "Farming", SortOrder = 3, Giftable = true  },
	{ Name = "DoubleSell",   Icon = "💰", Price = 99,  GamepassId = 1710868999, GiftProductId = 3542168668, Category = "Farming", SortOrder = 4, Giftable = true  },
	{ Name = "DoubleXP",     Icon = "⭐", Price = 150, GamepassId = 1710737068, GiftProductId = 3542168280, Category = "Boost",   SortOrder = 5, Giftable = true  },
	{ Name = "RainLover",    Icon = "🌧️", Price = 150, GamepassId = 1710551126, GiftProductId = 3542167872, Category = "Boost",   SortOrder = 6, Giftable = true  },
	{ Name = "AutoHarvest",  Icon = "🤖", Price = 249, GamepassId = 1708014472, GiftProductId = 3542161637, Category = "Boost",   SortOrder = 7, Giftable = true  },
	{ Name = "Boombox",      Icon = "📻", Price = 199, GamepassId = 1709724203, GiftProductId = 3542161296, Category = "Fun",     SortOrder = 8, Giftable = true },
	{ Name = "VIP",          Icon = "👑", Price = 499, GamepassId = 1708374413, GiftProductId = 3542160882, Category = "Premium", SortOrder = 9, Giftable = true  },
}

-- Auto-build lookup tables
GC.ByName = {}
GC.ById = {}
GC.ByGiftProductId = {}  -- ← BARU: lookup by Developer Product ID

for _, pass in ipairs(GC.Passes) do
	assert(type(pass.Name) == "string" and #pass.Name > 0, "[GamepassConfig] Pass missing Name!")
	assert(pass.GamepassId > 0, "[GamepassConfig] " .. pass.Name .. " has invalid GamepassId!")

	GC.ByName[pass.Name] = pass
	GC.ById[pass.GamepassId] = pass

	-- Gift product lookup (hanya jika valid dan giftable)
	if pass.Giftable and pass.GiftProductId and pass.GiftProductId > 0 then
		GC.ByGiftProductId[pass.GiftProductId] = pass
	end
end

return GC
