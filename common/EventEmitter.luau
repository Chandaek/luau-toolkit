--- Variable ---

local FreeRunnerThread: thread? = nil

--- Type ---

export type EventConnection = {
	Connected: boolean,
	Disconnect: (self: EventConnection) -> (),
}

export type EventEmitter = {
	Connect: (self: EventEmitter, EventFunction: (...any) -> ()) -> (EventConnection),
	Fire: (self: EventEmitter, ...any) -> (),
	Once: (self: EventEmitter, EventFunction: (...any) -> ()) -> (EventConnection),
	Wait: (self: EventEmitter) -> (...any),
}

--- Main ---

local function AcquireRunnerThreadAndCallEventHandler(EventFunction: (...any) -> (), ...: any): ()
	local AcquiredRunnerThread = FreeRunnerThread
	FreeRunnerThread = nil
	EventFunction(...)
	FreeRunnerThread = AcquiredRunnerThread
end

local function RunEventHandlerInFreeThread(...: any): ()
	AcquireRunnerThreadAndCallEventHandler(...)
	while true do
		AcquireRunnerThreadAndCallEventHandler(coroutine.yield())
	end
end

local EventEmitter = {}

function EventEmitter:Connect(EventFunction: (...any) -> ()): (EventConnection)
	local ConnectionList = self._connections
	local Index = #ConnectionList + 1

	local Connection = {
		Connected = true,
		Disconnect = function(self)
			if not self.Connected then return end
			self.Connected = false

			local LastIndex = #ConnectionList
			local SelfIndex = self._index
			if SelfIndex ~= LastIndex then
				local LastConnection = ConnectionList[LastIndex]
				ConnectionList[SelfIndex] = LastConnection
				LastConnection._index = SelfIndex
			end
			ConnectionList[LastIndex] = nil
		end,
		_callback = EventFunction,
		_index = Index,
	}

	ConnectionList[Index] = Connection
	return Connection
end

function EventEmitter:Once(EventFunction: (...any) -> ()): (EventConnection)
	local Connection
	Connection = self.Connect(self, function(...)
		Connection.Disconnect(Connection)
		EventFunction(...)
	end)
	return Connection
end

function EventEmitter:Wait(): (...any)
	local Arguments
	local CurrentThread = coroutine.running()
	local Connection = self.Once(self, function(...)
		Arguments = table.pack(...)
		task.spawn(CurrentThread)
	end)
	if Connection.Connected then
		coroutine.yield()
	end
	return table.unpack(Arguments)
end

function EventEmitter:Fire(...: any): ()
	local ConnectionList = self._connections

	for Index = 1, #ConnectionList do
		local Connection = ConnectionList[Index]
		if not FreeRunnerThread then
			FreeRunnerThread = coroutine.create(RunEventHandlerInFreeThread)
		end
		task.spawn(FreeRunnerThread :: thread, Connection._callback, ...)
	end
end

local EventEmitterImpl = {}
EventEmitterImpl.__index = EventEmitter

function EventEmitterImpl.new(): (EventEmitter)
	local self = setmetatable({}, EventEmitterImpl)
	self._connections = {}
	return self
end

return EventEmitterImpl :: {
	new: () -> (EventEmitter)
}