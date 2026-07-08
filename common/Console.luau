--- Type ---

export type Console = {
	Assert: (self: Console, Condition: boolean, ...any) -> (),
	SetProcessName: (self: Console, Name: string?) -> (),

	CreateContext: (self: Console, Name: string, Context: {[string]: any}) -> (),
	WithContext: (self: Console, Name: string?) -> (),

	Error: (self: Console, Message: any, StackLevel: number?) -> (),
	Print: (self: Console, ...any) -> (),
	Warn: (self: Console, ...any) -> (),

	Dump: (self: Console, Value: any, Label: string?, MaximumDepth: number?) -> (),
	Trace: (self: Console, ...any) -> (),
}

--- Variable ---

local DEFAULT_MAXIMUM_DUMP_DEPTH = 2
local DEFAULT_PROCESS_NAME = "UnnamedProcess"
local DEFAULT_STACK_LEVEL = 1

--- Main ---

local function composeContextTag(Context: {[string]: any}): (string)
	local ContextParts = {}
	for Key, Value in pairs(Context) do
		table.insert(ContextParts, tostring(Key) .. "=" .. tostring(Value))
	end
	return `[{table.concat(ContextParts, ",")}] `
end

local function dumpTable(Value: any, MaximumDepth: number): (string)
	local Seen = {}
	local function dump(Current: any, Depth: number): (string)
		if type(Current) ~= "table" then
			return tostring(Current)
		end
		if Depth > MaximumDepth then
			return "{...}"
		end
		if Seen[Current] then
			return "{<cycle>}"
		end
		Seen[Current] = true
		local Parts = {}
		for Key, FieldValue in pairs(Current) do
			table.insert(Parts, tostring(Key) .. " = " .. dump(FieldValue, Depth + 1))
		end
		return "{" .. table.concat(Parts, ", ") .. "}"
	end
	return dump(Value, 1)
end

local function getCallerInfo(Level: number): (string?, number?)
	local Source, Line = debug.info(Level, "sl")
	return Source, Line
end

local function getTrace(Level: number): (string)
	return debug.traceback(nil, Level)
end

local function joinArgs(...: any): (string)
	local Parts = {}
	local ArgumentCount = select("#", ...)
	for Index = 1, ArgumentCount do
		table.insert(Parts, tostring(select(Index, ...)))
	end
	return table.concat(Parts, " ")
end

local function prefix(ProcessName: string, Kind: string): (string)
	return `({ProcessName}:{Kind}): `
end

local Console = {}

function Console:_ResolveMessage(Message: string): (string)
	local ActiveContext = self._activeContext
	if not ActiveContext then
		return Message
	end
	local Context = self._contexts[ActiveContext]
	if not Context then
		return Message
	end
	return composeContextTag(Context) .. Message
end

function Console:Assert(Condition: boolean, ...: any): ()
	if Condition then
		return
	end
	local Message = joinArgs(...)
	self.Error(self, "Assertion failed: " .. Message, DEFAULT_STACK_LEVEL + 1)
end

function Console:SetProcessName(Name: string?): ()
	self._processName = Name or self._processName
end

function Console:CreateContext(Name: string, Context: {[string]: any}): ()
	self._contexts[Name] = Context
end

function Console:WithContext(Name: string?): ()
	if not self._activeContext[Name] then
		error(`Context "{Name}" does not exist`, 0)
	end
	self._activeContext = Name
end

function Console:Error(Message: any, StackLevel: number?): ()
	local FormattedMessage = self._ResolveMessage(self, tostring(Message))
	local Level = (StackLevel and tonumber(StackLevel)) or DEFAULT_STACK_LEVEL
	local Source, Line = getCallerInfo(Level + 1)
	local Location = if Source then `{Source}:{Line}` else "unknown"
	local Trace = getTrace(Level + 1)
	error(`{prefix(self._processName, "ERROR")}{FormattedMessage} [{Location}]\n{Trace}`, 0)
end

function Console:Print(...: any): ()
	print(prefix(self._processName, "INFO") .. self._ResolveMessage(self, joinArgs(...)))
end

function Console:Warn(...: any): ()
	warn(prefix(self._processName, "WARN") .. self._ResolveMessage(self, joinArgs(...)))
end

function Console:Dump(Value: any, Label: string?, MaximumDepth: number?): ()
	local LabelPrefix = Label and (self._ResolveMessage(self, tostring(Label)) .. ": ") or ""
	local Dumped = dumpTable(Value, MaximumDepth or DEFAULT_MAXIMUM_DUMP_DEPTH)
	print(prefix(self._processName, "DUMP") .. LabelPrefix .. Dumped)
end

function Console:Trace(...: any): ()
	local Message = self._ResolveMessage(self, joinArgs(...))
	local Source, Line = getCallerInfo(DEFAULT_STACK_LEVEL + 1)
	local Location = if Source then `{Source}:{Line}` else "unknown"
	local Trace = getTrace(DEFAULT_STACK_LEVEL + 1)
	print(`{prefix(self._processName, "TRACE")}{Message} [{Location}]\n{Trace}`)
end

local ConsoleImpl = {}
ConsoleImpl.__index = Console

function ConsoleImpl.new(ProcessName: string?): (Console)
	local self = setmetatable({}, ConsoleImpl)
	self._activeContext = nil
	self._contexts = {}
	self._processName = ProcessName or DEFAULT_PROCESS_NAME
	return self
end

return ConsoleImpl :: {
	new: (ProcessName: string?) -> (Console),
}