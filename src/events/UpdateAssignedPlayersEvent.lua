UpdateAssignedPlayersEvent = {}
UpdateAssignedPlayersEvent_mt = Class(UpdateAssignedPlayersEvent, Event)

InitEventClass(UpdateAssignedPlayersEvent, "UpdateAssignedPlayersEvent")

function UpdateAssignedPlayersEvent:new(uniqueUserId, assignedFarmId)
    local self = Event:new(UpdateAssignedPlayersEvent_mt)

    self.uniqueUserId = uniqueUserId
    self.assignedFarmId = assignedFarmId

    return self
end

function UpdateAssignedPlayersEvent:readStream(streamId, connection)
    self.uniqueUserId = streamReadString(streamId)
    self.assignedFarmId = streamReadInt32(streamId)

    self:run(connection)
end

function UpdateAssignedPlayersEvent:writeStream(streamId, connection)
    streamWriteString(streamId, self.uniqueUserId)
    streamWriteInt32(streamId, self.assignedFarmId)
end

function UpdateAssignedPlayersEvent:run(connection)
    if not connection:getIsServer() then
        if self.uniqueUserId ~= nil then
            LimitedDailyIncome.uniqueUserIdToAssignedFarm[self.uniqueUserId] = self.assignedFarmId
        else
            print("error: missing uniqueUserId")
        end
    end
end