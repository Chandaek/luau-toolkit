--- Type ---

export type TemplateManager = {
	Load: (self: TemplateManager) -> ()
}

--- Module ---

local ModuleUtil = (function()
	local Current: Instance? = script.Parent
	while Current do
		local Target = Current:FindFirstChild("LoaderUtils")
		if Target and Target:IsA("Folder") then
			local ModuleUtil = Target:FindFirstChild("ModuleUtil")
			return require(ModuleUtil :: ModuleScript)
		end
		Current = Current.Parent
	end
	error("[TemplateManager] LoaderUtils not found")
end)()

local function _HasModuleChildren(Target: Instance): (boolean)
	for _, Child in Target:GetChildren() do
		if Child:IsA("ModuleScript") then
			return true
		end
	end
	return false
end

--- Main ---

local TemplateManager = {}

function TemplateManager:Load(): ()
	local LeafModules = {}
	local SubManagers = {}

	for _, Child in self._target:GetChildren() do
		if not Child:IsA("ModuleScript") then
			continue
		end
		if _HasModuleChildren(Child) then
			SubManagers[#SubManagers + 1] = Child
		else
			LeafModules[#LeafModules + 1] = Child
		end
	end

	for _, LeafModule in ModuleUtil.SortModules(LeafModules) do
		ModuleUtil.LoadModule(LeafModule)
	end

	for _, SubManagerScript in ModuleUtil.SortModules(SubManagers) do
		local Success, SubManagerClass = ModuleUtil.LoadModule(SubManagerScript)
		if not Success or not SubManagerClass then
			continue
		end
		local SubManager = SubManagerClass.new()
		SubManager:Load()
	end
end

local TemplateManagerImpl = {}
TemplateManagerImpl.__index = TemplateManager

function TemplateManagerImpl.new(): (TemplateManager)
	local self = setmetatable({}, TemplateManagerImpl)
	self._target = script

	return self
end

return TemplateManagerImpl :: {
	new: () -> (TemplateManager)
}