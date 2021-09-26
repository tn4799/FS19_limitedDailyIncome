LimitedDailyIncome = {}

LimitedDailyIncome.sales = {}
LimitedDailyIncome.wasPlayerOnline = {}
LimitedDailyIncome.salesLimit = {}

LimitedDailyIncome.STANDARD_LIMIT = 500000
LimitedDailyIncome.INCREASE_LIMIT_FACTOR = 250000

-- daily reset to defaults
function LimitedDailyIncome:onDayChanged()
    for farmId, _ in pairs(self.sales) do
        self.sales[farmId] = 0

        if not self.wasPlayerOnline[farmId] then
            self.salesLimit[farmId] = self.salesLimit[farmId] + self.INCREASE_LIMIT_FACTOR
        else
            self.salesLimit[farmId] = self.STANDARD_LIMIT
        end

        self.wasPlayerOnline[farmId] = false
    end
end

-- keep track of earned money to measure the total amount
function LimitedDailyIncome:addMoney(amount, farmId, moneyType, addChange, forceShowChange)
    if amount > 0 and not moneytype == MoneyType.SHOP_VEHICLE_SELL then
        LimitedDailyIncome.sales[farmId] = LimitedDailyIncome.sales[farmId] + amount
    end
end

-- disable mission activation if sales limit is passed
function LimitedDailyIncome:startMission(superFunc, mission, farmId, spawnVehicles)
    if LimitedDailyIncome.sales[farmId] >= LimitedDailyIncome.salesLimit[farmId] then
        --TODO: Show error "you have earned to much money today. Please wait till the next day." on screen
        return
    end

    superFunc(mission, farmId, spawnVehicles)
end

-- disable making money with selling animals through trailer
function LimitedDailyIncome:applyChangesTrailer(superFunc)
    -- get vehicle the trailer is attached to
    local farmId = 0
    local vehicle = self.trailer:getAttacherVehicle()

    if vehicle ~= nil then
        farmId = vehicle:getActiveFarm()
    else
        farmId = self.trailer:getOwnerFarmId()
        --alternative solution: g_currentMission.player.farmId
        --must look deeper into it to decide which solution is better
    end
    
    if LimitedDailyIncome.sales[farmId] >= LimitedDailyIncome.salesLimit[farmId] then
        --TODO: Show error "you have earned to much money today. Please wait till the next day." on screen
        return
    end

    superFunc(self)
end

-- disable making money with selling animals through selling at animalTrader and husbandaries
function LimitedDailyIncome:applyChangesFarms(superFunc)
    -- get vehicle the trailer is attached to
    local farmId = self.husbandry.ownerFarmId
    
    if LimitedDailyIncome.sales[farmId] >= LimitedDailyIncome.salesLimit[farmId] then
        --TODO: Show error "you have earned to much money today. Please wait till the next day." on screen
        
        return
    end

    superFunc(self)
end

FSBaseMission.addMoney = Utils.prependedFunction(FSBaseMission.addMoney, LimitedDailyIncome.addMoney)
MissionManager.startMission = Utils.overwrittenFunction(MissionManager.startMission, LimitedDailyIncome.startMission)


--TODO
--g_currentMission:addUpdateable()