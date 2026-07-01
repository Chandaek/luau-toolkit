export type ResolverConfig = {}

export type Resolver = {
	Memoize: <Identity, Target>(self: Resolver, Identifier: Identity, Action: () -> (Target), ...any) -> (Target),
	Check: <Identity>(self: Resolver, Identifier: Identity) -> (boolean),
}

local Resolver = {}

function Resolver:Insert<Identity, DataValue>(Identifier: Identity, Data: DataValue): ()
	self._normalCache[Identifier] = Data
end

function Resolver:Memoize<Identity, Target>(Identifier: Identity, Action: () -> (Target), ...: any): (Target)
	local Existing = self._normalCache[Identifier]
	if Existing then
		return Existing
	end

	local Success, Result = xpcall(Action, debug.traceback, ...)
	if not Success then
		error(Result, 0)
	end

	self._normalCache[Identifier] = Result
	return Result
end

function Resolver:Remove<Identity>(Identifier: Identity): ()
	local DataValue = self._normalCache[Identifier]
	self._normalCache[Identifier] = nil
	return DataValue
end

function Resolver:Check<Identity>(Identifier: Identity): (boolean)
	return self._normalCache[Identifier] ~= nil
end

local ResolverImpl = {}
ResolverImpl.__index = Resolver

function ResolverImpl.new(): (Resolver)
	local self = setmetatable({}, ResolverImpl)
	self._normalCache = {}

	return self
end

return ResolverImpl :: {
	new: () -> (Resolver),
}