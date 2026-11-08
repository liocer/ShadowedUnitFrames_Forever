-- Block Timers
local BlockTimers = {}
function BlockTimers:Inject(module, event)
	ShadowUF.Tags.customEvents["SUF_" .. event] = module
	module.EnableTag = BlockTimers.EnableTag
	module.DisableTag = BlockTimers.DisableTag
end

function BlockTimers:EnableTag(frame, fontString)
	fontString.block.fontString = fontString
end

function BlockTimers:DisableTag(frame, fontString)
	fontString.block.fontString = nil
end


ShadowUF.BlockTimers = BlockTimers;

-- Dynamic Blocks
local DynamicBlocks = {}
function DynamicBlocks:Inject(module)
	module.OnLayoutWidgets = function(_, frame)
		if( not frame.visibility[module.moduleKey] or not frame[module.moduleKey].blocks) then return end

		local height = frame[module.moduleKey]:GetHeight()
		for _, block in pairs(frame[module.moduleKey].blocks) do
			block:SetHeight(height)
		end
	end
end

ShadowUF.DynamicBlocks = DynamicBlocks

-- Zone type used for the per-zone visibility settings: "none", "pvp", "arena", "party", "raid" or "neighborhood".
-- CanHearthAndResurrectFromArea() returns true for world pvp areas (see QueueStatusFrame.lua); it's an old C
-- function that isn't in the API docs, so it's looked up defensively.
local CanHearthAndResurrectFromArea = _G["CanHearthAndResurrectFromArea"]
-- ignoreWorldPvP: only look at the instance type (what module visibility has always used)
function ShadowUF:GetInstanceType(ignoreWorldPvP)
	local instanceType = not ignoreWorldPvP and CanHearthAndResurrectFromArea and CanHearthAndResurrectFromArea() and "pvp" or select(2, IsInInstance())
	if( instanceType == "scenario" ) then instanceType = "party" end
	if( instanceType == "interior" ) then instanceType = "neighborhood" end
	-- Anything we don't have visibility settings for counts as the open world
	if( not instanceType or not ShadowUF.db.profile.visibility[instanceType] and instanceType ~= "none" ) then instanceType = "none" end

	return instanceType
end
