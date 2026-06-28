--- Module ---

local EventEmitter = require("@game/ReplicatedStorage/Common/EventEmitter")

local ConnectorUtil = require("@self/LoaderUtils/ConnectorUtil")
local ModuleUtil = require("@self/LoaderUtils/ModuleUtil")
local ManagerUtil = require("@self/LoaderUtils/ManagerUtil")

--- Variable ---

local FirstInstantiatedRoot = nil
local FIrstInstantiatedManager = nil

--- Type ---

export type ManagerLoader = {
	Bootstrap: (self: ManagerLoader) -> (),
	GetManager: (self: ManagerLoader, Name: string) -> (any?),
	OnManagerLoaded: ConnectorUtil.ConnectorUtil,
}

--- Main ---

local function _HasModuleChildren(Target: Instance): (boolean)
	for _, Child in Target:GetChildren() do
		if Child:IsA("ModuleScript") then
			return true
		end
	end
	return false
end

local ManagerLoader = {}

function ManagerLoader:Bootstrap(): ()
	local Selection = ManagerUtil.new(self._root)
	local Candidates = Selection:GetSelections()

	local ManagerScripts = {}
	for _, Candidate in Candidates do
		if Candidate == script then
			continue
		end
		if not _HasModuleChildren(Candidate) then
			continue
		end
		ManagerScripts[#ManagerScripts + 1] = Candidate
	end

	for _, ManagerScript in ModuleUtil.SortModules(ManagerScripts) do
		local Success, ManagerClass = ModuleUtil.LoadModule(ManagerScript)
		if not Success or not ManagerClass then
			continue
		end
		local Manager = ManagerClass.new()
		Manager:Load()
		self._managerMap[ManagerScript.Name] = Manager
		self._onManagerLoadedSignal:Fire(ManagerScript.Name, Manager)
	end
end

function ManagerLoader:GetManager(Name: string): (any?)
	return self._managerMap[Name]
end

local ManagerLoaderImpl = {}
ManagerLoaderImpl.__index = ManagerLoader

function ManagerLoaderImpl.new(Root: Instance): (ManagerLoader)
	if not FirstInstantiatedRoot then
		FirstInstantiatedRoot = Root
	else
		if Root ~= FirstInstantiatedRoot then
			warn("There has already been a Main Loader.")
		end
		return FIrstInstantiatedManager
	end

	local self = setmetatable({}, ManagerLoaderImpl)

	self._root = Root
	self._managerMap = {}

	local Signal = EventEmitter.new()
	self._onManagerLoadedSignal = Signal
	self.OnManagerLoaded = ConnectorUtil.new(Signal)

	if not FIrstInstantiatedManager then
		FIrstInstantiatedManager = self
	end
	return self
end

return ManagerLoaderImpl :: {
	new: (Root: Instance) -> (ManagerLoader)
}
