require "TimedActions/ISBaseTimedAction"

ISWLMFinalizeSwitchAction = ISBaseTimedAction:derive("ISWLMFinalizeSwitchAction")

function ISWLMFinalizeSwitchAction:isValid()
    return true
end

function ISWLMFinalizeSwitchAction:start()
end

function ISWLMFinalizeSwitchAction:update()
end

function ISWLMFinalizeSwitchAction:perform()
    WardrobeLoadouts.Client.finishSwitch(self.success, self.message)
    ISBaseTimedAction.perform(self)
end

function ISWLMFinalizeSwitchAction:new(character, success, message)
    local action = ISBaseTimedAction.new(self, character)
    action.success = success
    action.message = message
    action.maxTime = 1
    action.stopOnWalk = false
    action.stopOnRun = false
    return action
end
