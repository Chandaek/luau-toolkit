--- Module ---

local SharedFabric = require("./Shared")

--- Type ---

export type ScopeDataVisibility = SharedFabric.ScopeDataVisibility

export type ThreadConfiguration = SharedFabric.ThreadConfiguration
export type ThreadMaster = SharedFabric.ThreadMaster

--- Main ---

local ThreadMaster = {}

function ThreadMaster:_Run(ProcessName: string?, Action: (Master: ThreadMaster, ...any) -> (...any), ...: any): (...any)
	if self._fabric == nil then
		error(`{self.Name}: Attempt to run task for destroyed ThreadMaster.`, 0)
	end

	local Name = self.Name or "ThreadMaster"
	ProcessName = ProcessName and tostring(ProcessName) or "unnamed"

	local PackedTuple: { any }?
	local Success, Error = coroutine.resume(self._freeRunnerThread, function(...: any)
		PackedTuple = self._resolver:Resolve(`{Name}({ProcessName}):`, function(...: any)
			return table.pack(Action(self, ...))
		end, true, ...)
	end, ...)

	if not Success then
		error(Error, 0)
	end

	if typeof(PackedTuple) == "table" then
		return table.unpack(PackedTuple)
	end

	return nil
end

function ThreadMaster:Run(ProcessName: string?, Action: (Master: ThreadMaster, ...any) -> (...any), ...: any): (...any)
	if self._fabric == nil then
		error(`{self.Name}: Attempt to run task for destroyed ThreadMaster.`, 0)
	end

	if typeof(Action) ~= "function" then
		error("Action must be a function", 0)
	end

	if not self._freeRunnerThread or coroutine.status(self._freeRunnerThread) == "dead" then
		error(`{self.Name}: Runner thread is not available`, 0)
	end

	return self:_Run(ProcessName, Action, ...)
end

function ThreadMaster:GetScopeValue(Key: string): (...any)
	if self._fabric == nil then
		error(`{self.Name}: Attempt to get from destroyed ThreadMaster.`, 0)
	end

	local Value = self._privateScopeDataRegister[Key] or self._publicScopeDataRegister[Key]
	if Value ~= nil then
		return Value
	end

	return self._fabric and self._fabric:GetGScopeValue(Key)
end

function ThreadMaster:SetScopeValue<ValueType>(Key: string, Value: ValueType, Visibility: ScopeDataVisibility): ()
	if self._fabric == nil then
		error(`{self.Name}: Attempt to set to destroyed ThreadMaster.`, 0)
	end

	if Visibility == "Global" then
		self._fabric:SetGScopeValue(Key, Value)
	elseif Visibility == "Private" then
		self._privateScopeDataRegister[Key] = Value
		self._privateScopeDataRegister["All"][Key] = Value
	else
		self._publicScopeDataRegister[Key] = Value
		self._publicScopeDataRegister["All"][Key] = Value
	end
end

function ThreadMaster:RemoveScopeValue(Key: string, Visibility: ScopeDataVisibility): ()
	if self._fabric == nil then
		error(`{self.Name}: Attempt to remove from destroyed ThreadMaster.`, 0)
	end

	if Visibility == "Global" then
		self._fabric:RemoveGScopeValue(Key)
	elseif Visibility == "Private" then
		self._privateScopeDataRegister[Key] = nil
		self._privateScopeDataRegister["All"][Key] = nil
	else
		self._publicScopeDataRegister[Key] = nil
		self._publicScopeDataRegister["All"][Key] = nil
	end
end

function ThreadMaster:Destroy(): ()
	if self._fabric == nil then
		error(`{self.Name}: Attempt to destroy an already destroyed ThreadMaster.`, 0)
	end

	self._fabric:Recycle(self)
end

local ThreadMasterImpl = {}
ThreadMasterImpl.__index = ThreadMaster

function ThreadMasterImpl.new(RunningThread: thread, ThreadConfig: ThreadConfiguration): (ThreadMaster)
	local self = setmetatable({}, ThreadMasterImpl)
	self._freeRunnerThread = RunningThread
	self._resolver = SharedFabric.Resolver.new()
	self._privateScopeDataRegister = { ["All"] = {} }
	self._publicScopeDataRegister = { ["All"] = {} }

	return SharedFabric.SetConfigurationToMaster(self, ThreadConfig)
end

return ThreadMasterImpl :: {
	new: (RunningThread: thread, ThreadConfig: ThreadConfiguration) -> (ThreadMaster)
}