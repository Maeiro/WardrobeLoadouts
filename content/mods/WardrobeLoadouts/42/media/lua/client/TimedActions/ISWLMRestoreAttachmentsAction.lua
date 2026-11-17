require "TimedActions/ISBaseTimedAction"

ISWLMRestoreAttachmentsAction = ISBaseTimedAction:derive("ISWLMRestoreAttachmentsAction")

function ISWLMRestoreAttachmentsAction:isValid()
    return true
end

function ISWLMRestoreAttachmentsAction:start()
end

function ISWLMRestoreAttachmentsAction:update()
end

function ISWLMRestoreAttachmentsAction:perform()
    WardrobeLoadouts.Client.restoreAttachments(self.character, self.entries)
    ISBaseTimedAction.perform(self)
end

function ISWLMRestoreAttachmentsAction:new(character, entries, durationFrames)
    local action = ISBaseTimedAction.new(self, character)
    action.entries = entries or {}
    action.maxTime = durationFrames
    action.stopOnWalk = false
    action.stopOnRun = false
    return action
end
