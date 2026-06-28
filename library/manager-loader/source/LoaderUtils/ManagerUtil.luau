--- Type ---

export type ManagerUtil = {
	GetSelection: (self: ManagerUtil, Name: string) -> (ModuleScript?),
	GetSelections: (self: ManagerUtil) -> ({ ModuleScript }),
}

--- Main ---

local ManagerUtil = {}

--[[
	Returns the selection matching the provided name.
	
	Returns nil if no selection exists with the
	provided name.
]]
function ManagerUtil:GetSelection(Name: string): (ModuleScript?)
	return self._selectionMap[Name]
end

--[[
	Returns a shallow copy of all discovered selections.
]]
function ManagerUtil:GetSelections(): ({ ModuleScript })
	return table.clone(self._selections)
end

local ManagerUtilImpl = {}
ManagerUtilImpl.__index = ManagerUtil

--[[
	Collects all ModuleScripts directly under the
	provided parent instance.
]]
function ManagerUtilImpl.new(SelectionParent: Instance): (ManagerUtil)
	local Selections = {}
	local SelectionMap = {}
	
	for _, Selection in SelectionParent:GetChildren() do
		if not Selection:IsA("ModuleScript") then
			continue
		end
		
		Selections[#Selections + 1] = Selection
		SelectionMap[Selection.Name] = Selection
	end
	
	local self = setmetatable({}, ManagerUtilImpl)
	
	self._selections = Selections
	self._selectionMap = SelectionMap
	
	return self
end

return ManagerUtilImpl :: {
	new: (SelectionParent: Instance) -> (ManagerUtil),
}