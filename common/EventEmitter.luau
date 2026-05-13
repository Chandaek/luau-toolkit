export type EventConnection = typeof({
	Connected = true,
	Disconnect = function(self) end,
})

local FreeRunnerThread: thread? = nil

local function AcquireRunnerThreadAndCallEventHandler(EventFunction: (...any) -> (), ...: any): ()
	local AcquiredRunnerThread = FreeRunnerThread
	FreeRunnerThread = nil
	EventFunction(...)
	FreeRunnerThread = AcquiredRunnerThread
end

local function RunEventHandlerInFreeThread()
	while true do
		AcquireRunnerThreadAndCallEventHandler(coroutine.yield())
	end
end

local EventEmitter = {}

function EventEmitter:Connect(EventName: string, EventFunction: (...any) -> ()): (EventConnection)
	if type(EventName) ~= "string" then
		error("EventName must be a string", 2)
	end
	local Designators = self[1]
	Designators[EventName] = Designators[EventName] or {}
	
	local DesignatorList = Designators[EventName]
	local Connection = {
		Connected = true,
		Disconnect = function(self)
			if not self.Connected then return end
			self.Connected = false
			local Index = table.find(DesignatorList, self)
			if Index then
				table.remove(DesignatorList, Index)
			end
		end,
		[1] = EventFunction,
	}
	
	table.insert(DesignatorList, Connection)
	return Connection
end

function EventEmitter:Once(EventName: string, EventFunction: (...any) -> ()): (EventConnection)
	local Connection
	Connection = self.Connect(self, EventName, function(...)
		Connection:Disconnect()
		EventFunction(...)
	end)
	return Connection
end

function EventEmitter:Wait(EventName: string): (...any)
	local Arguments
	local CurrentThread = coroutine.running()
	local Connection = self:Once(EventName, function(...)
		Arguments = table.pack(...)
		task.spawn(CurrentThread)
	end)
	if Connection.Connected then
		coroutine.yield()
	end
	return table.unpack(Arguments)
end

function EventEmitter:Fire(EventName: string, ...: any): ()
	local DesignatorList = self[1][EventName]
	if not DesignatorList then return end
	
	for _, Connection in ipairs(DesignatorList) do
		if Connection.Connected then
			if not FreeRunnerThread then
				FreeRunnerThread = coroutine.create(RunEventHandlerInFreeThread)
				coroutine.resume(FreeRunnerThread :: any)
			end
			task.spawn(FreeRunnerThread :: any, Connection[1], ...)
		end
	end
end

export type EventEmitter = {
	Connect: (self: EventEmitter, EventName: string, EventFunction: (...any) -> ()) -> (EventConnection),
	Once: (self: EventEmitter, EventName: string, EventFunction: (...any) -> ()) -> (EventConnection),
	Wait: (self: EventEmitter, EventName: string) -> (...any),
	Fire: (self: EventEmitter, EventName: string, ...any) -> (),
	Destroy: (self: EventEmitter) -> (),
}

local EventEmitterImpl = {}
EventEmitterImpl.__index = EventEmitter

function EventEmitterImpl.new(): (EventEmitter)
	local Event = setmetatable({ {} }, EventEmitterImpl)
	return Event
end

return EventEmitterImpl :: {
	new: () -> EventEmitter,
}
