-- i18n: a table-level lookup (e.g. Spring.I18N("ui.unitstats")) must still fall back per key
-- to the fallback locale when the active locale's table is only partly translated (PR #8076).
local SpecEnv = VFS.Include("spec/support/spec_env.lua")

local I18N_PATH = "modules/i18n/i18nlib/i18n/"
local i18n = SpecEnv.include(
	SpecEnv.new({
		I18N_PATH = I18N_PATH,
		Spring = {
			-- translate() reads the "English unit names" option
			GetConfigInt = function(_, default)
				return default
			end,
		},
	}),
	I18N_PATH .. "init.lua"
)

describe("i18n table-level fallback", function()
	before_each(function()
		i18n.reset()
		i18n.set("en.ui.stats.hp", "Health")
		i18n.set("en.ui.stats.speed", "Speed")
		i18n.set("de.ui.stats.hp", "Leben")
		i18n.setLocale("de")
	end)

	it("keeps the active locale's own translations", function()
		assert.are.equal("Leben", i18n.translate("ui.stats").hp)
	end)

	it("fills keys missing in the active locale from the fallback locale", function()
		assert.are.equal("Speed", i18n.translate("ui.stats").speed)
	end)

	it("returns nil for keys no locale has", function()
		assert.is_nil(i18n.translate("ui.stats").armor)
	end)

	it("still falls back for single keys", function()
		assert.are.equal("Speed", i18n.translate("ui.stats.speed"))
	end)
end)
