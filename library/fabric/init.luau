--- Module ---

local FabricShared = require("@self/source/Shared")
local ThreadMaster = require("@self/source/ThreadMaster")

--- Type ---

export type DeterminableChoice = FabricShared.DeterminableChoice

export type ThreadConfiguration = FabricShared.ThreadConfiguration
export type ThreadMaster = FabricShared.ThreadMaster
export type Fabric = FabricShared.Fabric

export type PrivateThreadMaster = FabricShared.PrivateThreadMaster

--- Variable ---

local FabricGScopeDataRegister: { All: { [string]: any }, [string]: any } = { ["All"] = {} }
local FabricIdentifierRegisters: { [thread]: string } = {}
local FabricMasterRegisters: { [string]: ThreadMaster } = {}
local FabricRecycledMaster: { [number]: ThreadMaster } = {}

local FabricUniqueMasterNumericAmount = 0

--- Main ---

local FabricImpl: Fabric = {} :: Fabric

local function AllocateRunnerThreadSequence(): (thread)
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

function FabricImpl:Bind(Identifier: string?, ThreadConfig: ThreadConfiguration): (ThreadMaster)
	FabricUniqueMasterNumericAmount += 1
	local TypedIdentifier = typeof(Identifier) == "string" and Identifier or `Fabric_Default_{FabricUniqueMasterNumericAmount}`

	local FreeRunnerThread: thread?
	local ResolvedThreadConfig = {
		Name = ThreadConfig.Name or TypedIdentifier
	}

	local CurrentMaster
	if #FabricRecycledMaster > 0 then
		local RecycledMaster = table.remove(FabricRecycledMaster) :: PrivateThreadMaster
		CurrentMaster = FabricShared.SetConfigurationToMaster(RecycledMaster, ResolvedThreadConfig)
		CurrentMaster._fabric = self

		if coroutine.status(CurrentMaster._freeRunnerThread) == "dead" then
			CurrentMaster._freeRunnerThread = AllocateRunnerThreadSequence()
		end
		FreeRunnerThread = CurrentMaster._freeRunnerThread
	else
		FreeRunnerThread = AllocateRunnerThreadSequence()
		CurrentMaster = ThreadMaster.new(FreeRunnerThread :: thread, ResolvedThreadConfig)
		CurrentMaster._fabric = self
	end

	if FreeRunnerThread then
		FabricIdentifierRegisters[FreeRunnerThread] = TypedIdentifier
	end
	FabricMasterRegisters[TypedIdentifier] = CurrentMaster
	return CurrentMaster
end

function FabricImpl:Determine(GetChoice: DeterminableChoice, Thread: thread?): ((string | boolean | ThreadMaster)?)
	local CurrentThread = Thread or coroutine.running()
	local Identifier = FabricIdentifierRegisters[CurrentThread]
	local ExistingData = GetChoice == "Identifier" and Identifier
		or GetChoice == "IsThread" and Identifier ~= nil
		or GetChoice == "Master" and FabricMasterRegisters[Identifier]
		or nil

	return ExistingData
end

function FabricImpl:GetPublicScope(Master: ThreadMaster, Key: string): (any)
	return (Master :: PrivateThreadMaster)._publicScopeDataRegister[Key]
end

function FabricImpl:GetGScopeValue(Key: string): (any)
	return FabricGScopeDataRegister[Key]
end

function FabricImpl:SetGScopeValue<ValueType>(Key: string, Value: ValueType): ()
	FabricGScopeDataRegister["All"][Key] = Value
	FabricGScopeDataRegister[Key] = Value
end

function FabricImpl:Recycle(Master: ThreadMaster): ()
	local TypedMaster: PrivateThreadMaster = Master :: PrivateThreadMaster

	local CurrentThread = TypedMaster._freeRunnerThread
	local Identifier = FabricIdentifierRegisters[CurrentThread]
	if Identifier then
		FabricIdentifierRegisters[CurrentThread] = nil
		FabricMasterRegisters[Identifier] = nil
	end

	TypedMaster._fabric = nil
	TypedMaster._resolver:Clear()
	table.clear(TypedMaster._privateScopeDataRegister)
	table.clear(TypedMaster._publicScopeDataRegister)
	table.insert(FabricRecycledMaster, TypedMaster)
end

return FabricImpl :: Fabric