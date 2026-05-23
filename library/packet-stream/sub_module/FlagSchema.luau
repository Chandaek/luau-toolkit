local RunService = game:GetService("RunService")

type SecurityListener = (FlagName: string, Value: boolean) -> (nil?, string?)
type GuardListener = (FlagName: string, Value: boolean, Reason: string) -> ()

type SchemaEntry = {
	Index: number,
	Default: boolean,
}

local FlagSchema = {}
FlagSchema.__index = FlagSchema

function FlagSchema.new(): (any)
	local self = setmetatable({}, FlagSchema)
	self._schema = {} :: {[string]: SchemaEntry}
	self._order = {} :: {string}
	self._values = {} :: {[string]: boolean}
	self._locked = false
	self._securityListener = nil :: SecurityListener?
	self._securityValidated = false
	self._guardListeners = {} :: {GuardListener}
	self._changeListeners = {} :: {(FlagName: string, Value: boolean) -> ()}
	return self
end

function FlagSchema:Define(Flags: {[string]: boolean}): ()
	assert(not self._locked, "[PacketStream:FlagSchema] Schema already defined")
	assert(not RunService:IsRunning(), "[PacketStream:FlagSchema] Schema cannot be defined after server start")
	for FlagName, Default in pairs(Flags) do
		assert(type(FlagName) == "string", "[PacketStream:FlagSchema] Flag name must be a string")
		assert(type(Default) == "boolean", "[PacketStream:FlagSchema] Flag default must be a boolean")
		local Index = #self._order + 1
		self._schema[FlagName] = {Index = Index, Default = Default}
		table.insert(self._order, FlagName)
		self._values[FlagName] = Default
	end
	self._locked = true
end

function FlagSchema:AddSecurityListener(Listener: (FlagName: string, Value: boolean) -> (nil?, string?)): ()
	assert(not RunService:IsRunning(), "[PacketStream:FlagSchema] Security listener cannot be added after server start")
	self._securityListener = Listener
end

function FlagSchema:AddGuardListener(Listener: (FlagName: string, Value: boolean, Reason: string) -> ()): ()
	table.insert(self._guardListeners, Listener)
end

function FlagSchema:OnChange(Listener: (FlagName: string, Value: boolean) -> ()): ()
	table.insert(self._changeListeners, Listener)
end

function FlagSchema:ValidateSecurity(): ()
	if not self._securityListener then
		self._securityValidated = true
		return
	end
	
	local AllResponded = true
	for FlagName, Entry in pairs(self._schema) do
		local Ok, Reason = self._securityListener(FlagName, not Entry.Default)
		if Ok ~= nil or type(Reason) ~= "string" then
			warn(`[PacketStream:FlagSchema] Security listener gave invalid response for flag "{FlagName}". Feature disabled.`)
			AllResponded = false
			break
		end
	end
	
	if not AllResponded then
		self._securityListener = nil
		warn("[PacketStream:FlagSchema] Security validation failed. Security listener disabled.")
	else
		self._securityValidated = true
	end
end

function FlagSchema:SetFlag(FlagName: string, Value: boolean): ()
	assert(self._locked, "[PacketStream:FlagSchema] Schema must be defined before setting flags")
	assert(self._schema[FlagName], `[PacketStream:FlagSchema] Unknown flag: "{FlagName}"`)
	
	if self._securityListener and self._securityValidated then
		local Ok, Reason = self._securityListener(FlagName, Value)
		if Ok == nil and type(Reason) == "string" then
			if #self._guardListeners == 0 then
				warn(`[PacketStream:FlagSchema] Flag "{FlagName}" blocked: {Reason}`)
			else
				for _, Guard in self._guardListeners do
					Guard(FlagName, Value, Reason)
				end
			end
			return
		end
	end
	
	self._values[FlagName] = Value
	
	for _, Listener in self._changeListeners do
		Listener(FlagName, Value)
	end
end

function FlagSchema:GetFlag(FlagName: string): (boolean)
	return self._values[FlagName] or false
end

function FlagSchema:Pack(): (string)
	local Count = #self._order
	local ByteCount = math.ceil(Count / 8)
	local Bytes = table.create(ByteCount, 0)
	for BitIndex, FlagName in self._order do
		if self._values[FlagName] then
			local ByteIndex = math.ceil(BitIndex / 8)
			local BitOffset = (BitIndex - 1) % 8
			Bytes[ByteIndex] = bit32.bor(Bytes[ByteIndex], bit32.lshift(1, BitOffset))
		end
	end
	return string.char(table.unpack(Bytes))
end

function FlagSchema:Unpack(Packed: string): ()
	for BitIndex, FlagName in self._order do
		local ByteIndex = math.ceil(BitIndex / 8)
		local BitOffset = (BitIndex - 1) % 8
		local Byte = string.byte(Packed, ByteIndex) or 0
		local Value = bit32.band(bit32.rshift(Byte, BitOffset), 1) == 1
		local Old = self._values[FlagName]
		self._values[FlagName] = Value
		if Value ~= Old then
			for _, Listener in self._changeListeners do
				Listener(FlagName, Value)
			end
		end
	end
end

function FlagSchema:IsLocked(): (boolean)
	return self._locked
end

function FlagSchema:GetOrder(): ({string})
	return self._order
end

function FlagSchema:GetAll(): ({[string]: boolean})
	return table.clone(self._values)
end

return FlagSchema
