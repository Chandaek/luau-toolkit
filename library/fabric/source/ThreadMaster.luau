--- Module ---

local SharedFabric = require("./Shared")

--- Type ---

export type ScopeDataVisibility = SharedFabric.ScopeDataVisibility

export type ThreadConfiguration = SharedFabric.ThreadConfiguration
export type ThreadMaster = SharedFabric.ThreadMaster

--- Main ---

local ThreadMaster = {}

function ThreadMaster:Run(ProcessName: string?, Action: (Master: ThreadMaster, ...any) -> (...any), ...: any): (...any)
	assert(typeof(Action) == "function", "Action must be a function")
	assert(self._freeRunnerThread and coroutine.status(self._freeRunnerThread) ~= "dead", `{self.Name}: Runner thread is not available`)

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

function ThreadMaster:GetScopeValue(Key: string): (...any)
	if not self._fabric then
		error(`{self.Name}: attempt to get from destroyed ThreadMaster.`, 0)
		return
	end
	local Value = self._privateScopeDataRegister[Key]
	if Value ~= nil then
		return Value
	end

	return self._fabric and self._fabric:GetGScopeValue(Key)
end

function ThreadMaster:SetScopeValue<ValueType>(Key: string, Value: ValueType, Visibility: ScopeDataVisibility): ()
	if Visibility == "Global" then
		if not self._fabric then
			error(`{self.Name}: attempt to set to destroyed ThreadMaster.`, 0)
			return
		end
		self._fabric:SetGScopeValue(Key, Value)
	elseif Visibility == "Private" then
		self._privateScopeDataRegister[Key] = Value
		self._privateScopeDataRegister["All"][Key] = Value
	else
		self._publicScopeDataRegister[Key] = Value
		self._publicScopeDataRegister["All"][Key] = Value
	end
end

function ThreadMaster:Destroy(): ()
	if not self._fabric then
		error(`{self.Name}: attempt to destroy an already destroyed ThreadMaster.`, 0)
		return
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