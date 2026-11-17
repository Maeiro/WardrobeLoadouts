require "TimedActions/ISBaseTimedAction"

ISWLMFinalizeRecoveryAction = ISBaseTimedAction:derive("ISWLMFinalizeRecoveryAction")

function ISWLMFinalizeRecoveryAction:isValid()
    return true
end

function ISWLMFinalizeRecoveryAction:start()
end

function ISWLMFinalizeRecoveryAction:update()
end

function ISWLMFinalizeRecoveryAction:perform()
    WardrobeLoadouts.Client.finishStoreRecovery(self.pending)
    ISBaseTimedAction.perform(self)
end

function ISWLMFinalizeRecoveryAction:new(character, pending)
    local action = ISBaseTimedAction.new(self, character)
    action.pending = pending
    action.maxTime = 1
    action.stopOnWalk = false
    action.stopOnRun = false
    return action
end
