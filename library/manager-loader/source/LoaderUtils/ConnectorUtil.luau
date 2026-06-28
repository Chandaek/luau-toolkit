--- Main ---

export type ConnectorUtil = {
	Connect: (self: ConnectorUtil, Listener: any, Disconnector: (() -> (boolean))?, StepUpdater: (() -> ("Break"))?) -> ()
}

local ConnectorUtil = {}

function ConnectorUtil:Connect(Listener: any, Disconnector: (() -> (boolean))?, StepUpdater: (() -> ("Break"))?): ()
	local Connection = self._event:Connect(Listener)
	
	Disconnector = Disconnector or self._disconnector :: (() -> (boolean))
	StepUpdater = StepUpdater or self._stepUpdater :: (() -> ("Break"))

	task.spawn(function()
		local function NextStep()
			if StepUpdater then
				local StepStatu = StepUpdater()
				if StepStatu == "Break" then
					return true
				end
			end
			return if Disconnector then Disconnector() else false
		end
		
		local ReadyToDisconnect = NextStep()
		while not ReadyToDisconnect do
			task.wait()
			ReadyToDisconnect = NextStep()
		end
		
		self._event = nil
		Connection:Disconnect()
	end)
end

local ConnectorUtilImpl = {}
ConnectorUtilImpl.__index = ConnectorUtil

function ConnectorUtilImpl.new(Event: any, Disconnector: (() -> (boolean))?, StepUpdater: (() -> ("Break"))?): (ConnectorUtil)
	local self = setmetatable({}, ConnectorUtilImpl)
	self._event = Event
	
	self._disconnector = Disconnector or function() return false end
	self._stepUpdater = StepUpdater or function() return nil end
	
	return self
end

return ConnectorUtilImpl :: {
	new: () -> (ConnectorUtil)
}