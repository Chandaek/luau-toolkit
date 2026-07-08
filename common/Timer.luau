--- Type ---

export type TimeUnit = "Minute" | "Second" | "MilliSecond"

export type TimerConnection = {
	IsRunning: boolean,
	IsPaused: boolean,
	Current: number,
	LagTime: number,
	SinceLastUpdate: number,

	Pause: (self: TimerConnection) -> (),
	Resume: (self: TimerConnection) -> (),
	Stop: (self: TimerConnection, StopCallback: boolean?) -> (),
}

export type IntervalConnection = {
	IsRunning: boolean,
	IsPaused: boolean,
	TicksElapsed: number,
	LagTime: number,
	SinceLastUpdate: number,

	Pause: (self: IntervalConnection) -> (),
	Resume: (self: IntervalConnection) -> (),
	Stop: (self: IntervalConnection) -> (),
}

export type StopwatchConnection = {
	IsRunning: boolean,

	GetElapsed: (self: StopwatchConnection) -> (number),
	Stop: (self: StopwatchConnection) -> (number),
}

export type Timer = {
	Countdown: (self: Timer, Start: number, Goal: number, HighPrecision: boolean, Callback: () -> ()) -> TimerConnection?,
	Interval: (self: Timer, Duration: number, Callback: () -> (), RepeatCount: number?) -> IntervalConnection?,
	Stopwatch: (self: Timer) -> StopwatchConnection,
}

--- Variable ---

local DEFAULT_TIME_TICK = 50
local DEFAULT_TIME_UNIT = "MilliSecond"

local FreeRunnerThreads: { thread } = {}

--- Main ---

local function allocateRunnerThreadSequence(): (thread)
	local FreeRunnerThread: thread? = nil
	local function RunnerThreadSequence(Action: (...any) -> (), ...: any)
		local AcquiredRunnerThread = FreeRunnerThread
		FreeRunnerThread = nil
		Action(...)
		FreeRunnerThread = AcquiredRunnerThread
	end

	FreeRunnerThread = coroutine.create(function(...: any)
		RunnerThreadSequence(...)
		while true do
			RunnerThreadSequence(coroutine.yield())
		end
	end)

	return FreeRunnerThread :: thread
end

local function acquireRunnerThread(): (thread)
	local Thread = table.remove(FreeRunnerThreads)
	if not Thread then
		Thread = allocateRunnerThreadSequence()
	end
	return Thread
end

local function releaseRunnerThread(Thread: thread): ()
	table.insert(FreeRunnerThreads, Thread)
end

local function normalizeTimeToSecond(Time: number, Unit: TimeUnit): (number)
	local NormalizedTime = Time
	if Unit == "MilliSecond" then
		NormalizedTime /= 1000
	elseif Unit == "Minute" then
		NormalizedTime /= 60
	end
	return NormalizedTime
end

local TimerConnection = {}

function TimerConnection:Pause(): ()
	if not self._isPaused and self.IsRunning then
		self._isPaused = true
		self.IsPaused = true
		self._pauseStartedAt = os.clock()
	end
end

function TimerConnection:Resume(): ()
	if self._isPaused then
		self._isPaused = false
		self.IsPaused = false
		self._pausedAccumulated += os.clock() - self._pauseStartedAt
	end
end

function TimerConnection:Stop(StopCallback: boolean?): ()
	self.IsRunning = false

	if StopCallback then
		self._callback()
	end
end

function TimerConnection:_ApplyTick(LagTime: number, SinceLastUpdate: number): ()
	self.Current = self._timeHasElapsed
	self.LagTime = LagTime
	self.SinceLastUpdate = SinceLastUpdate

	if self.Current >= self._timeToElapse then
		self.IsRunning = false
		self._callback()
	end
end

function TimerConnection:_RunLoop(): ()
	local SinceStarted = os.clock()
	local LastRealTime = SinceStarted

	if self._highPrecision then
		while self.IsRunning and self._timeToElapse > self._timeHasElapsed and task.wait(self._normalizedTick) do
			if self._isPaused then
				continue
			end

			local CurrentTime = os.clock()
			local LastTimeHasElapsed = self._timeHasElapsed
			self._timeHasElapsed = (CurrentTime - SinceStarted) - self._pausedAccumulated

			local TimeSinceLastElapsed = self._timeHasElapsed - LastTimeHasElapsed
			local CurrentLoopLagTime = TimeSinceLastElapsed - self._tick

			coroutine.resume(self._dispatchThread, TimerConnection._ApplyTick, self, CurrentLoopLagTime, TimeSinceLastElapsed)
		end
	else
		while self.IsRunning and self._timeToElapse > self._timeHasElapsed and task.wait(self._normalizedTick) do
			if self._isPaused then
				continue
			end

			local CurrentTime = os.clock()
			self._timeHasElapsed += self._normalizedTick -- deterministic progress, not real time

			-- LagTime/SinceLastUpdate still reflect actual wall-clock drift,
			-- independent of the deterministic Current progression above.
			local TimeSinceLastElapsed = CurrentTime - LastRealTime
			local CurrentLoopLagTime = TimeSinceLastElapsed - self._tick
			LastRealTime = CurrentTime

			coroutine.resume(self._dispatchThread, TimerConnection._ApplyTick, self, CurrentLoopLagTime, TimeSinceLastElapsed)
		end
	end

	releaseRunnerThread(self._loopThread)
	releaseRunnerThread(self._dispatchThread)
end

local TimerConnectionImpl = {}
TimerConnectionImpl.__index = TimerConnection

function TimerConnectionImpl.new(TimeToElapse: number, Tick: number, NormalizedTick: number, HighPrecision: boolean, Callback: () -> ()): (TimerConnection)
	local self = setmetatable({}, TimerConnectionImpl)

	self.IsRunning = true
	self.IsPaused = false
	self.Current = 0
	self.LagTime = 0
	self.SinceLastUpdate = 0

	self._timeToElapse = TimeToElapse
	self._tick = Tick
	self._normalizedTick = NormalizedTick
	self._highPrecision = HighPrecision
	self._callback = Callback

	self._timeHasElapsed = 0
	self._isPaused = false
	self._pausedAccumulated = 0
	self._pauseStartedAt = 0

	self._loopThread = acquireRunnerThread()
	self._dispatchThread = acquireRunnerThread()

	coroutine.resume(self._loopThread, TimerConnection._RunLoop, self)

	return (self :: any) :: TimerConnection
end

local IntervalConnection = {}

function IntervalConnection:Pause(): ()
	if not self._isPaused and self.IsRunning then
		self._isPaused = true
		self.IsPaused = true
	end
end

function IntervalConnection:Resume(): ()
	if self._isPaused then
		self._isPaused = false
		self.IsPaused = false
		self._sinceLastTick = os.clock() -- paused duration shouldn't count toward the next tick
	end
end

function IntervalConnection:Stop(): ()
	self.IsRunning = false
end

function IntervalConnection:_ApplyTick(LagTime: number, SinceLastUpdate: number): ()
	self.TicksElapsed += 1
	self.LagTime = LagTime
	self.SinceLastUpdate = SinceLastUpdate

	self._callback()

	if self._repeatCount and self.TicksElapsed >= self._repeatCount then
		self.IsRunning = false
	end
end

function IntervalConnection:_RunLoop(): ()
	while self.IsRunning and task.wait(self._normalizedTick) do
		if self._isPaused then
			continue
		end

		local CurrentTime = os.clock()
		local ElapsedSinceLastTick = CurrentTime - self._sinceLastTick

		if ElapsedSinceLastTick >= self._tickDuration then
			self._sinceLastTick = CurrentTime
			local LagTime = ElapsedSinceLastTick - self._tickDuration

			coroutine.resume(self._dispatchThread, IntervalConnection._ApplyTick, self, LagTime, ElapsedSinceLastTick)
		end
	end

	releaseRunnerThread(self._loopThread)
	releaseRunnerThread(self._dispatchThread)
end

local IntervalConnectionImpl = {}
IntervalConnectionImpl.__index = IntervalConnection

function IntervalConnectionImpl.new(TickDuration: number, Tick: number, NormalizedTick: number, RepeatCount: number?, Callback: () -> ()): (IntervalConnection)
	local self = setmetatable({}, IntervalConnectionImpl)

	self.IsRunning = true
	self.IsPaused = false
	self.TicksElapsed = 0
	self.LagTime = 0
	self.SinceLastUpdate = 0

	self._tickDuration = TickDuration
	self._tick = Tick
	self._normalizedTick = NormalizedTick
	self._repeatCount = RepeatCount
	self._callback = Callback

	self._isPaused = false
	self._sinceLastTick = os.clock()

	self._loopThread = acquireRunnerThread()
	self._dispatchThread = acquireRunnerThread()

	coroutine.resume(self._loopThread, IntervalConnection._RunLoop, self)

	return (self :: any) :: IntervalConnection
end

local StopwatchConnection = {}

function StopwatchConnection:GetElapsed(): (number)
	if not self.IsRunning then
		return self._frozenElapsed
	end
	return os.clock() - self._startedAt
end

function StopwatchConnection:Stop(): (number)
	if self.IsRunning then
		self._frozenElapsed = os.clock() - self._startedAt
		self.IsRunning = false
	end
	return self._frozenElapsed
end

local StopwatchConnectionImpl = {}
StopwatchConnectionImpl.__index = StopwatchConnection

function StopwatchConnectionImpl.new(): (StopwatchConnection)
	local self = setmetatable({}, StopwatchConnectionImpl)

	self.IsRunning = true
	self._startedAt = os.clock()
	self._frozenElapsed = 0

	return (self :: any) :: StopwatchConnection
end

local Timer = {}

function Timer:Countdown(Start: number, Goal: number, HighPrecision: boolean, Callback: () -> ()): (TimerConnection?)
	local Tick = self._tick
	local Unit = self._unit

	local TimeToElapse = normalizeTimeToSecond(math.abs(Start - Goal), Unit)
	if TimeToElapse <= 0 then
		return nil
	end

	local NormalizedTick = normalizeTimeToSecond(Tick, Unit)
	return TimerConnectionImpl.new(TimeToElapse, Tick, NormalizedTick, HighPrecision, Callback)
end

function Timer:Interval(Duration: number, Callback: () -> (), RepeatCount: number?): (IntervalConnection?)
	local Tick = self._tick
	local Unit = self._unit

	local TickDuration = normalizeTimeToSecond(Duration, Unit)
	if TickDuration <= 0 then
		return nil
	end

	local NormalizedTick = normalizeTimeToSecond(Tick, Unit)
	return IntervalConnectionImpl.new(TickDuration, Tick, NormalizedTick, RepeatCount, Callback)
end

function Timer:Stopwatch(): (StopwatchConnection)
	return StopwatchConnectionImpl.new()
end

local TimerImpl = {}
TimerImpl.__index = Timer

function TimerImpl.new(Tick: number?, Unit: TimeUnit?): (Timer)
	local self = setmetatable({}, TimerImpl)
	self._tick = Tick or DEFAULT_TIME_TICK
	self._unit = Unit or DEFAULT_TIME_UNIT

	return (self :: any) :: Timer
end

return TimerImpl :: {
	new: (Tick: number?, Unit: TimeUnit?) -> (Timer),
}