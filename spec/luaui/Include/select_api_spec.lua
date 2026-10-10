---@diagnostic disable: undefined-field, undefined-global

-- The "guarding" select filter (e.g. select all guarding constructors). A guarding unit
-- keeps its GUARD order second in the queue while it repairs or attacks for the guarded
-- unit, so the filter must look past those (PR #9497; before it only saw GUARD first).

local GUARD, REPAIR, ATTACK, MOVE = 25, 40, 20, 10

-- unitID -> command queue (ids, current first)
local queues

local function loadSelectApi()
	_G.CMD.GUARD, _G.CMD.REPAIR, _G.CMD.ATTACK, _G.CMD.MOVE = GUARD, REPAIR, ATTACK, MOVE
	_G.Game.armorTypes = { default = 0, vtol = 1 }
	_G.WG = {}
	_G.UnitDefs = { [1] = { name = "armck" } }
	_G.Spring.GetUnitDefID = function(uid)
		return queues[uid] and 1 or nil
	end
	_G.Spring.GetUnitCurrentCommand = function(uid, index)
		return (queues[uid] or {})[index]
	end
	_G.Spring.GetUnitCommands = function(uid, count)
		local cmds = {}
		for i, id in ipairs(queues[uid] or {}) do
			if i > count then break end
			cmds[i] = { id = id, params = {} }
		end
		return cmds
	end
	_G.Spring.GetUnitCommandCount = function(uid)
		return #(queues[uid] or {})
	end
	local api = require("luaui/Include/select_api")
	return api
end

describe("select filter 'guarding'", function()
	local api

	before_each(function()
		queues = {}
		api = loadSelectApi()
	end)

	local function passes(filterDef, queue)
		queues[1] = queue
		return api.unitPassesFilter(1, api.getFilter(filterDef))
	end

	it("matches a unit whose current order is guard", function()
		assert.is_true(passes("Guarding", { GUARD }))
	end)

	it("matches a guarding unit that is repairing or attacking for its charge", function()
		assert.is_true(passes("Guarding", { REPAIR, GUARD }))
		assert.is_true(passes("Guarding", { ATTACK, GUARD }))
	end)

	it("does not match a unit that only has guard queued after other work", function()
		assert.is_false(passes("Guarding", { MOVE, GUARD }))
		assert.is_false(passes("Guarding", { REPAIR, MOVE, GUARD }))
	end)

	it("does not match idle units or units repairing on their own", function()
		assert.is_false(passes("Guarding", {}))
		assert.is_false(passes("Guarding", { REPAIR }))
	end)

	it("inverts with Not", function()
		assert.is_false(passes("Not_Guarding", { REPAIR, GUARD }))
		assert.is_true(passes("Not_Guarding", { MOVE, GUARD }))
	end)
end)
