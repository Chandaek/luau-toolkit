--- Type ---

export type ModuleVersionInfo = {
	Minor: number,
	Patch: number,
}

export type ModuleVersionData = ModuleVersionInfo & {
	Channel: string?,
	Stability: string?,
}

export type ModuleVersionOption = {
	IncludeChannel: boolean?,
	IncludeStability: boolean?
}

export type ModuleUtil = {
	LoadModule: (ModuleTarget: ModuleScript, DisableWatchdog: boolean?) -> (boolean, any?),
	SortModules: (Array: { ModuleScript }) -> ({ ModuleScript }),
	GetSortedModules: (Selections: Folder) -> ({ ModuleScript? }),
}

--- Variable ---

local Default_Priority_Type = 5
local Default_Priority_Value = 0

local PriorityTypes = {
	["engine"] = 1,
	["system"] = 2,
	["sub-system"] = 3,
	["render"] = 4,
	["normal"] = Default_Priority_Type,
	["deferred"] = Default_Priority_Type + 1,
}

--- Public Function ---

local ModuleUtilImpl = {}

--[[
	Loads a single ModuleScript.
	
	Returns (boolean, any?):
	- true, module result on success
	- false, error text on failure or timeout
	
	A watchdog timeout is enabled by default to detect
	modules that hang during require.
	
	Set DisableWatchdog to true to disable timeout protection.
]]
function ModuleUtilImpl.LoadModule(ModuleTarget: ModuleScript, DisableWatchdog: boolean?): (boolean, any?)
	local CurrentThread = coroutine.running()
	local Finished = false
	local WatchdogThread
	
	local function Finish(Success: boolean, Result: any?)
		if Finished then
			return
		end
		
		Finished = true
		
		if WatchdogThread then
			task.cancel(WatchdogThread)
		end
		
		coroutine.resume(CurrentThread, Success, Result)
	end
	
	task.spawn(function()
		local Success, Result = pcall(require, ModuleTarget)
		
		if not Success then
			warn(`[Loader.ModuleUtil.LoadModule] Failed to load module {ModuleTarget.Name}: {Result}`)
		end
		
		Finish(Success, Result)
	end)
	
	if not DisableWatchdog then
		-- Watchdog timeout to prevent hanging modules
		WatchdogThread = task.delay(10, function()
			Finish(false, `Timed out loading module {ModuleTarget.Name}`)
		end)
	end
	
	return coroutine.yield()
end

--[[
	Returns a sorted array of ModuleScripts from the provided array.
	
	Sorting order:
	- PriorityType ascending
	- PriorityValue descending
	- Name ascending
	
	Attribute values are cached before sorted to avoid repeated
	GetAttribute calls during comparator execution.
]]
function ModuleUtilImpl.SortModules(Array: { ModuleScript }): ({ ModuleScript })
	local ArrayData = {}
	
	-- precompute and cache Selection attributes to avoid repeated GetAttribute calls
	for _, Selection in Array do
		if not Selection:IsA("ModuleScript") then
			continue
		end
		
		Array[#Array + 1] = Selection
		
		ArrayData[Selection] = {
			Name = Selection.Name,
			Type = PriorityTypes[Selection:GetAttribute("PriorityType")] or Default_Priority_Type,
			Value = Selection:GetAttribute("PriorityValue") or Default_Priority_Value,
		}
	end
	
	-- sort by type, then descending priority value
	table.sort(Array, function(FirstOrder, SecondOrder)
		local FirstData = ArrayData[FirstOrder]
		local SecondData = ArrayData[SecondOrder]
		
		if FirstData.Type ~= SecondData.Type then
			return FirstData.Type < SecondData.Type
		end
		
		if FirstData.Value ~= SecondData.Value then
			return FirstData.Value > SecondData.Value
		end
		
		return FirstData.Name < SecondData.Name
	end)
	
	return Array
end

--[[
	Collects ModuleScripts from the provided folder and returns
	them sorted by SortModules.
]]
function ModuleUtilImpl.GetSortedModules(SelectionsFolder: Folder): ({ ModuleScript? })
	-- this method took me 13 hours to complete because of distraction.
	
	local SelectionChildren = SelectionsFolder:GetChildren()
	if #SelectionChildren == 0 then -- no selections to process
		return {}
	end
	
	local SelectionsArray = ModuleUtilImpl.SortModules(SelectionChildren)
	
	-- return the sorted array directly; Luau's native table iteration is sufficient and avoids a custom iterator
	return SelectionsArray
end

--[[
	Returns version information from the provided ModuleScript.
	
	Attribute format:
	- ModuleVersion = "minor.patch"
	
	Optional attributes:
	- ModuleChannel
	- ModuleStability
	
	IncludeChannel controls whether the Channel field
	is included in the returned table.
	
	IncludeStability controls whether the Stability field
	is included in the returned table.
	
	Returns nil if ModuleVersion is missing or invalid.
]]
function ModuleUtilImpl.GetModuleVersion(ModuleTarget: ModuleScript, Options: ModuleVersionOption): (ModuleVersionData?)
	local VersionString = ModuleTarget:GetAttribute("ModuleVersion")
	
	if type(VersionString) ~= "string" then
		return nil
	end
	
	local Minor, Patch = string.match(VersionString, "^(%d+)%.(%d+)$")
	if not Minor then
		return nil
	end
	
	local VersionData: ModuleVersionData = {
		Minor = tonumber(Minor),
		Patch = tonumber(Patch),
	}
	
	if Options.IncludeChannel then
		VersionData.Channel = ModuleTarget:GetAttribute("ModuleChannel") :: string
	end
	
	if Options.IncludeStability then
		VersionData.Stability = ModuleTarget:GetAttribute("ModuleStability") :: string
	end
	
	return VersionData
end

return ModuleUtilImpl :: ModuleUtil