--- Module ---

local Resolver = require("@game/ReplicatedStorage/Common/Resolver" :: any)

--- Type ---

export type DeterminableChoice = "Identifier" | "IsThread" | "Master"
export type ScopeDataVisibility = "Global" | "Private" | "Public"

export type ThreadConfiguration = {
	Name: string,
}

export type ThreadMaster = {
	Name: string,

	Run: (self: ThreadMaster, ProcessName: string?, Action: (...any) -> (...any), ...any) -> (...any),
	GetScopeValue: (self: ThreadMaster, Key: string) -> (...any),
	SetScopeValue: (self: ThreadMaster, Key: string, Value: any, Visibility: ScopeDataVisibility) -> (),
	RemoveScopeValue: (self: ThreadMaster, Key: string, Visibility: ScopeDataVisibility) -> (),
	Destroy: (self: ThreadMaster) -> (),
}

export type Fabric = {
	Bind: (self: Fabric, Identifier: string?, ThreadConfig: ThreadConfiguration) -> (ThreadMaster),
	Determine: (self: Fabric, GetChoice: DeterminableChoice, Thread: thread?) -> ((string | boolean | ThreadMaster)?),
	GetPublicScope: (self: Fabric, Master: ThreadMaster, Key: string) -> (any),
	GetGScopeValue: (self: Fabric, Key: string) -> (any),
	SetGScopeValue: <ValueType>(self: Fabric, Key: string, Value: ValueType) -> (),
	RemoveGScopeValue: (self: Fabric, Key: string) -> (),
	Recycle: (self: Fabric, Master: ThreadMaster) -> ()
}

export type PrivateThreadMaster = ThreadMaster & {
	_fabric: Fabric?,
	_freeRunnerThread: thread,
	_resolver: { [any]: any },
	_privateScopeDataRegister: { [string]: any },
	_publicScopeDataRegister: { [string]: any },

	_Run: (self: PrivateThreadMaster, ProcessName: string?, Action: (...any) -> (...any), ...any) -> (...any)
}

--- Main ---

local Shared = {}
Shared.Resolver = Resolver

function Shared.SetConfigurationToMaster(Master: ThreadMaster, ThreadConfig: ThreadConfiguration): (ThreadMaster)
	Master.Name = ThreadConfig.Name

	return Master
end

return Shared