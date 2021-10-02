LimitedDailyIncome = {}

LimitedDailyIncome.sales = {}
LimitedDailyIncome.wasPlayerOnline = {}
LimitedDailyIncome.salesLimit = {}
LimitedDailyIncome.uniqueUserIdToAssignedFarm = {}

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

-- this function is called when a player joins the game and he already was in a farm the last time he played
-- NOTE: he always is in a farm, but we ignore the Spectator Farm (farmId = 0)
function LimitedDailyIncome:onUserJoinGame(uniqueUserId, userId, user)
    local farm = g_farmManager:getFarmForUniqueUserId(uniqueUserId)
    local farmId = farm.farmId

    if farmId ~= g_farmManager.SPECTATOR_FARM_ID then
        self.wasPlayerOnline[farmId] = self:checkIfUserIsAssignedToFarm(farmId, uniqueUserId)
    end
end

-- this is called when a player joins a farm by himself
-- The first time a player joins a farm, he is assigned to that farm.
-- NOTE: we need overwrittenFunction here because we need to access the farmId of the farm of which addUser is called.
-- this is only possible with self, and to get that self = Farm we need to overwrite the original function
function LimitedDailyIncome:addUser(superFunc, userId, uniqueUserId, isFarmManager, user)
    -- first let the original function do its work, then do our own
    superFunc(self, userId, uniqueUserId, isFarmManager, user)

    local spectator_farm = g_farmManager.SPECTATOR_FARM_ID
    -- assign new user to first farm he joins
    if LimitedDailyIncome.uniqueUserIdToAssignedFarm[uniqueUserId] == nil and self.farmId ~= spectator_farm then
        LimitedDailyIncome.uniqueUserIdToAssignedFarm[uniqueUserId] = self.farmId
        return
    end

    -- check if user that joined the farm is assigned to the farm and if so there was a player online
    self.wasPlayerOnline[self.farmId] = LimitedDailyIncome:checkIfUserIsAssignedToFarm(self.farmId, uniqueUserId)
end

function LimitedDailyIncome:checkIfUserIsAssignedToFarm(farmId, uniqueUserId)
    return farmId == self.uniqueUserIdToAssignedFarm[uniqueUserId]
end

-- daily reset to defaults
function LimitedDailyIncome:onDayChanged()
    for farmId, _ in pairs(self.sales) do
        self.sales[farmId] = 0

        if not self.wasPlayerOnline[farmId] then
            self.salesLimit[farmId] = self.salesLimit[farmId] + self.INCREASE_LIMIT_OFFLINE
        elseif self.sales <= LimitedDailyIncome.IGNORE_INCOME_LIMIT then
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

    -- remove all assigned players from deleted farm
    for uniqueUserId, farmId2 in pairs(self.uniqueUserIdToAssignedFarm) do
        if farmId2 == farmId2 then
            self.uniqueUserIdToAssignedFarm[uniqueUserId] = nil
        end
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
-- player management
Farm.addUser = Utils.overwrittenFunction(Farm.addUser, LimitedDailyIncome.addUser)
-- need own append-function because we need to keep the return value of the original function
Farm.onUserJoinGame = function (...)
    --oldFunc
    local returnValue = Farm.onUserJoinGame(...)
    --newFunc
    LimitedDailyIncome.onUserJoinGame(...)
    return returnValue
end
-- permission managing
-- overwritten is used because we do some code injection. This means we insert some code at the start of the original function
MissionManager.startMission = Utils.overwrittenFunction(MissionManager.startMission, LimitedDailyIncome.startMission)
DealerFarmStrategie.applyChanges = Utils.overwrittenFunction(DealerFarmStrategie.applyChanges, LimitedDailyIncome.applyChangesFarms)
DealerTrailerStrategie.applyChanges = Utils.overwrittenFunction(DealerTrailerStrategie.applyChanges, LimitedDailyIncome.applyChangesTrailer)
SellingStation.addFillLevelFromTool = Utils.overwrittenFunction(SellingStation.addFillLevelFromTool, LimitedDailyIncome.addFillLevelFromTool)
WoodSellStationPlaceable.sellWood = Utils.overwrittenFunction(WoodSellStationPlaceable.sellWood, LimitedDailyIncome.sellWood)
--TODO
--g_currentMission:addUpdateable()