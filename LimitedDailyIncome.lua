LimitedDailyIncome = {}

LimitedDailyIncome.sales = {}
LimitedDailyIncome.salesLimit = {}

LimitedDailyIncome.STANDARD_LIMIT = 450000
LimitedDailyIncome.INCREASE_LIMIT_FACTOR = 250000

function LimitedDailyIncome:loadFromXMLFile(xmlFilename)
    if xmlFilename == nil then
        --load default values
        self.sales = {}
        self.salesLimit = {}

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
			
			index = index + 1
		end
    end
end

-- daily reset to defaults
function LimitedDailyIncome:onDayChanged()
    for farmId, _ in pairs(self.sales) do
        self.sales[farmId] = 0

        if not self.sales[farmId] <= 50.000 then
            self.salesLimit[farmId] = self.salesLimit[farmId] + self.INCREASE_LIMIT_FACTOR
        else
            self.salesLimit[farmId] = self.STANDARD_LIMIT
        end
    end
end

--register new farm with default values
function LimitedDailyIncome:createFarm(superFunc, name, color, password, farmId)
    local farm = superFunc(self, name, color, password, farmId)

    if farm ~= nil then
        farmId = farm.farmId
        LimitedDailyIncome.sales[farmId] = 0
        LimitedDailyIncome.salesLimit[farmId] = LimitedDailyIncome.STANDARD_LIMIT
    end

    return farm
end

--remove farm if deleted
function LimitedDailyIncome:removeFarm(farmId)
    self.sales[farmId] = nil
    self.salesLimit[farmId] = nil
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

--tracking money
FSBaseMission.addMoney = Utils.prependedFunction(FSBaseMission.addMoney, LimitedDailyIncome.addMoney)
--farms Management
FarmManager.createFarm = Utils.overwrittenFunction(FarmManager.createFarm, LimitedDailyIncome.createFarm)
FarmManager.removeFarm = Utils.appendedFunction(FarmManager.removeFarm, LimitedDailyIncome.removeFarm)
-- permission mamaging
MissionManager.startMission = Utils.overwrittenFunction(MissionManager.startMission, LimitedDailyIncome.startMission)
DealerFarmStrategie.applyChanges = Utils.overwrittenFunction(DealerFarmStrategie.applyChanges, LimitedDailyIncome.applyChangesFarms)
DealerTrailerStrategie.applyChanges = Utils.overwrittenFunction(DealerTrailerStrategie.applyChanges, LimitedDailyIncome.applyChangesTrailer)

--TODO
--g_currentMission:addUpdateable()