UpdateDataEvent = {}
UpdateDataEvent_mt = Class(UpdateDataEvent, Event)

InitEventClass(UpdateDataEvent, "UpdateDataEvent")

function UpdateDataEvent:emptyNew()
    return Event:new(UpdateDataEvent_mt)
end

function UpdateDataEvent:new(farmId, sales, salesLimit)
    local self = UpdateDataEvent:emptyNew()

    self.farmId = farmId
    self.sales = sales
    self.salesLimit = salesLimit

    return self
end

function UpdateDataEvent:readStream(streamId, connection)
    self.farmId = streamReadInt32(streamId)
    self.sales = streamReadFloat32(streamId)
    self.salesLimit = streamReadInt32(streamId)

    self:run(connection)
end

function UpdateDataEvent:writeStream(streamId, connection)
    streamWriteInt32(streamId, self.farmId)
    streamWriteFloat32(streamId, self.sales)
    streamWriteInt32(streamId, self.salesLimit)
end

function UpdateDataEvent:run(connection)
    if not connection:getIsServer() then
        if self.farmId ~= nil then
            LimitedDailyIncome.sales[self.farmId] = self.sales
            LimitedDailyIncome.salesLimit[self.farmId] = self.salesLimit
        else
            print("error: no farmId")
        end
    end
end