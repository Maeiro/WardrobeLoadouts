require "TimedActions/ISBaseTimedAction"

ISWLMFinalizeStoreAction = ISBaseTimedAction:derive("ISWLMFinalizeStoreAction")

function ISWLMFinalizeStoreAction:isValid()
    return true
end

function ISWLMFinalizeStoreAction:start()
end

function ISWLMFinalizeStoreAction:update()
end

function ISWLMFinalizeStoreAction:perform()
    WardrobeLoadouts.Client.finishStore(self.success, self.message)
    ISBaseTimedAction.perform(self)
end

function ISWLMFinalizeStoreAction:new(character, success, message)
    local action = ISBaseTimedAction.new(self, character)
    action.success = success
    action.message = message
    action.maxTime = 1
    action.stopOnWalk = false
    action.stopOnRun = false
    return action
end
