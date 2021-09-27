LimitedDailyIncome = {}

LimitedDailyIncome.sales = {}
LimitedDailyIncome.wasPlayerOnline = {}
LimitedDailyIncome.salesLimit = {}

-- Daily Limit
LimitedDailyIncome.STANDARD_LIMIT = 500000
-- Increase when player was not online.
LimitedDailyIncome.INCREASE_LIMIT_OFFLINE = 250000
-- Daily Limit that gets ignored.
LimitedDailyIncome.IGNORE_INCOME_LIMIT = 30000
-- Increase when player stays below the limit.
LimitedDailyIncome.INCREASE_LIMIT_IGNORE = 50000

function LimitedDailyIncome:loadFromXMLFile(xmlFilename)
    if xmlFilename == nil then
        --load default values
        self.sales = {}
        self.salesLimit = {}
        self.wasPlayerOnline = {}

        return
    end

    local xmlFile = loadXMLFile("farmsXML", xmlFilename)

    local i = 0
    while true do
        local key = string.format("farms.farm(%d)", i)
        
		if not hasXMLProperty(xmlFile, key) then
			break
		end

        local farmId = getXMLInt(xmlFile, key .. "#farmId")

        -- added tag of limitedDayIncome to key
        key = key .. ".limitedDayIncome"
        self.sales[farmId] = getXMLFloat(xmlFile, key .. ".sales")
        self.salesLimit[farmId] = getXMLInt(xmlFile, key .. ".salesLimit")
        self.wasPlayerOnline[farmId] = getXMLBool(xmlFile, key .. ".wasPlayerOnline")

        i = i + 1
    end
end

function LimitedDailyIncome:saveToXMLFile(xmlFilename)
    local xmlFile = loadXMLFile("farmsXML", xmlFilename)
    local index = 0
    local farms = g_farmManager:getFarms()

    for _, farm in pairs(farms) do
        if farm.farmId ~= 0 then
			local key = string.format("farms.farm(%d).limitedDayIncome", index)
            local farmId = farm.farmId

            setXMLFloat(xmlFile, key .. ".sales", self.sales[farmId])
            setXMLInt(xmlFile, key .. ".salesLimit", self.salesLimit[farmId])
            setXMLBool(xmlFile, key .. ".wasPlayerOnline", self.wasPlayerOnline[farmId])
			
			index = index + 1
		end
    end
end

-- daily reset to defaults
function LimitedDailyIncome:onDayChanged()
    for farmId, _ in pairs(self.sales) do
        self.sales[farmId] = 0

        if not self.wasPlayerOnline[farmId] then
            self.salesLimit[farmId] = self.salesLimit[farmId] + self.INCREASE_LIMIT_OFFLINE
        else if self.sales <= LimitedDailyIncome.IGNORE_INCOME_LIMIT then
            self.salesLimit[farmId] = self.salesLimit[farmId] + self.INCREASE_LIMIT_IGNORE
        else
            self.salesLimit[farmId] = self.STANDARD_LIMIT
        end

        self.wasPlayerOnline[farmId] = false
    end
end

--register new farm with default values
function LimitedDailyIncome:createFarm(superFunc, name, color, password, farmId)
    local farm = superFunc(self, name, color, password, farmId)

    if farm ~= nil then
        farmId = farm.farmId
        LimitedDailyIncome.sales[farmId] = 0
        LimitedDailyIncome.wasPlayerOnline[farmId] = false
        LimitedDailyIncome.salesLimit[farmId] = LimitedDailyIncome.STANDARD_LIMIT
    end

    return farm
end

--remove farm if deleted
function LimitedDailyIncome:removeFarm(farmId)
    self.sales[farmId] = nil
    self.salesLimit[farmId] = nil
    self.wasPlayerOnline[farmId] = nil
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
    
    LimitedDailyIncome:checkTotalSum(self, superFunc, farmId)
end

-- disable making money with selling animals through selling at animalTrader and husbandaries
function LimitedDailyIncome:applyChangesFarms(superFunc)
    -- get vehicle the trailer is attached to
    local farmId = self.husbandry.ownerFarmId
    
    LimitedDailyIncome:checkTotalSum(self, superFunc, farmId)
end

function LimitedDailyIncome:checkTotalSum(this, superFunc, farmId)
    local _, _, _, total = this:getPrices()

    if LimitedDailyIncome.sales[farmId] >= LimitedDailyIncome.salesLimit[farmId] and total > 0 then
        --TODO: Show error "you have earned to much money today to make money with selling animals. Please wait till the next day." on screen
        return
    end

    superFunc(self)
end

function LimitedDailyIncome:addFillLevelFromTool(superFunc, farmId, deltaFillLevel, fillType, fillInfo, toolType)
    if LimitedDailyIncome.sales[farmId] > LimitedDailyIncome.salesLimit[farmId] then
        --TODO: show error message
        return
    end

    superFunc(self, farmId, deltaFillLevel, fillLevel, fillInfo, toolType)
end

function LimitedDailyIncome:sellWood(superFunc, farmId)
    if LimitedDailyIncome.sales[farmId] > LimitedDailyIncome.salesLimit[farmId] then
        --TODO: show error message
        return
    end

    superFunc(self, farmId)
end

--tracking money
FSBaseMission.addMoney = Utils.prependedFunction(FSBaseMission.addMoney, LimitedDailyIncome.addMoney)
--farms Management
FarmManager.createFarm = Utils.overwrittenFunction(FarmManager.createFarm, LimitedDailyIncome.createFarm)
FarmManager.removeFarm = Utils.appendedFunction(FarmManager.removeFarm, LimitedDailyIncome.removeFarm)
-- permission managing
MissionManager.startMission = Utils.overwrittenFunction(MissionManager.startMission, LimitedDailyIncome.startMission)
DealerFarmStrategie.applyChanges = Utils.overwrittenFunction(DealerFarmStrategie.applyChanges, LimitedDailyIncome.applyChangesFarms)
DealerTrailerStrategie.applyChanges = Utils.overwrittenFunction(DealerTrailerStrategie.applyChanges, LimitedDailyIncome.applyChangesTrailer)
SellingStation.addFillLevelFromTool = Utils.overwrittenFunction(SellingStation.addFillLevelFromTool, LimitedDailyIncome.addFillLevelFromTool)
WoodSellStationPlaceable.sellWood = Utils.overwrittenFunction(WoodSellStationPlaceable.sellWood, LimitedDailyIncome.sellWood)
--TODO
--g_currentMission:addUpdateable()