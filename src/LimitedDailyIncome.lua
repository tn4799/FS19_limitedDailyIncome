LimitedDailyIncome = {}

LimitedDailyIncome.sales = {}
LimitedDailyIncome.wasPlayerOnline = {}
LimitedDailyIncome.salesLimit = {}
LimitedDailyIncome.uniqueUserIdToAssignedFarm = {}
LimitedDailyIncome.allowedMoneyTypes = {
    MoneyType.SHOP_VEHICLE_SELL,
    MoneyType.SHOP_PROPERTY_SELL,
    MoneyType.FIELD_SELL,
    MoneyType.PROPERTY_INCOME,
    MoneyType.INCOME_BGA,
    MoneyType.TRANSFER
}

-- Daily Limit
LimitedDailyIncome.STANDARD_LIMIT = 500000
-- Increase when player was not online.
LimitedDailyIncome.INCREASE_LIMIT_OFFLINE = 250000
-- Daily Limit that gets ignored.
LimitedDailyIncome.SMALL_SALES_LIMIT = 30000
-- Increase when player stays below the limit.
LimitedDailyIncome.INCREASE_LIMIT_SMALL_SALES = 50000

function LimitedDailyIncome:loadMapFinished(node, arguments, callAsyncCallback)
    g_currentMission.environment:addDayChangeListener(LimitedDailyIncome)
    LimitedDailyIncome.staticValuesFilename = string.format(getUserProfileAppPath() .. "savegame%d/LimitedDailyIncome.xml", g_careerScreen.selectedIndex)

    local vehicleTypes = g_vehicleTypeManager:getVehicleTypes()
    for _, vehicleType in pairs(vehicleTypes) do
        if SpecializationUtil.hasSpecialization(Dischargeable, vehicleType.specializations) then
            --print("overwrite function for vehicleType: " .. vehicleType.name)
            SpecializationUtil.registerOverwrittenFunction(vehicleType, "handleDischarge", LimitedDailyIncome.handleDischarge)
        end
    end
end

function LimitedDailyIncome:loadFromXMLFile(xmlFilename)
    if xmlFilename == nil then
        --load default values
        self.sales = {}
        self.salesLimit = {}
        self.wasPlayerOnline = {}
        self.uniqueUserIdToAssignedFarm = {}

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
        LimitedDailyIncome.sales[farmId] = Utils.getNoNil(getXMLFloat(xmlFile, key .. ".sales"), 0)
        LimitedDailyIncome.salesLimit[farmId] = Utils.getNoNil(getXMLInt(xmlFile, key .. ".salesLimit"), LimitedDailyIncome.STANDARD_LIMIT)
        LimitedDailyIncome.wasPlayerOnline[farmId] = Utils.getNoNil(getXMLBool(xmlFile, key .. ".wasPlayerOnline"), false)

        i = i + 1
    end

    i = 0

    while true do
        local key = string.format("farms.assignedPlayers.assignedPlayer(%d)", i)

        if not hasXMLProperty(xmlFile, key) then
			break
		end

        local uniqueUserId = getXMLString(xmlFile, key .. "#uniqueUserId")
        LimitedDailyIncome.uniqueUserIdToAssignedFarm[uniqueUserId] = getXMLInt(xmlFile, key .. "#farmId")

        i = i + 1
    end

    delete(xmlFile)

    if true then--g_server ~= nil then
        LimitedDailyIncome:loadStaticValues()
    end
end

function LimitedDailyIncome:saveToXMLFile(xmlFilename)
    local xmlFile = loadXMLFile("farmsXML", xmlFilename)
    local index = 0
    local farms = g_farmManager:getFarms()

    for _, farm in pairs(farms) do
        if farm.farmId ~= g_farmManager.SPECTATOR_FARM_ID then
			local key = string.format("farms.farm(%d).limitedDayIncome", index)
            local farmId = farm.farmId

            setXMLFloat(xmlFile, key .. ".sales", LimitedDailyIncome.sales[farmId])
            setXMLInt(xmlFile, key .. ".salesLimit", LimitedDailyIncome.salesLimit[farmId])
            setXMLBool(xmlFile, key .. ".wasPlayerOnline", LimitedDailyIncome.wasPlayerOnline[farmId])

			index = index + 1
		end
    end

    index = 0

    for uniqueUserId, farmId in pairs(LimitedDailyIncome.uniqueUserIdToAssignedFarm) do
        local key = string.format("farms.assignedPlayers.assignedPlayer(%d)", index)

        setXMLString(xmlFile, key .. "#uniqueUserId", uniqueUserId)
        setXMLInt(xmlFile, key .. "#farmId", farmId)

        index = index + 1
        --print("assignedUser: " .. tostring(uniqueUserId), tostring(farmId))
    end

    saveXMLFile(xmlFile)
	delete(xmlFile)

    if true then-- g_server ~= nil then
        LimitedDailyIncome:saveStaticValues()
    end
end

function LimitedDailyIncome:loadStaticValues()
    if not fileExists(LimitedDailyIncome.staticValuesFilename) then
        return
    end

    local xmlFile = loadXMLFile("TempXML", LimitedDailyIncome.staticValuesFilename)
    local key = "limitedDailyIncome"

    LimitedDailyIncome.STANDARD_LIMIT = getXMLInt(xmlFile, key .. ".standardLimit")
    LimitedDailyIncome.SMALL_SALES_LIMIT = getXMLInt(xmlFile, key .. ".smallSalesLimit")
    LimitedDailyIncome.INCREASE_LIMIT_OFFLINE = getXMLInt(xmlFile, key .. ".increaseLimitOffline")
    LimitedDailyIncome.INCREASE_LIMIT_SMALL_SALES = getXMLInt(xmlFile, key .. ".increaseLimitSmallSales")

    delete(xmlFile)
end

function LimitedDailyIncome:saveStaticValues()
    local modSettingsPath = getUserProfileAppPath() .. "/modsSettings/LimitedDailyIncome"
    local savegamePath = string.format(modSettingsPath .. "/savegame%d", g_careerScreen.selectedIndex)
    createFolder(modSettingsPath)
    createFolder(savegamePath)

    local xmlFile = createXMLFile("LimitedDailyIncomeXML", LimitedDailyIncome.staticValuesFilename, "limitedDailyIncome")
    local key = "limitedDailyIncome"

    setXMLInt(xmlFile, key .. ".standardLimit", LimitedDailyIncome.STANDARD_LIMIT)
    setXMLInt(xmlFile, key .. ".smallSalesLimit", LimitedDailyIncome.SMALL_SALES_LIMIT)
    setXMLInt(xmlFile, key .. ".increaseLimitOffline", LimitedDailyIncome.INCREASE_LIMIT_OFFLINE)
    setXMLInt(xmlFile, key .. ".increaseLimitSmallSales", LimitedDailyIncome.INCREASE_LIMIT_SMALL_SALES)

    saveXMLFile(xmlFile)
    delete(xmlFile)
end

-- this function is called when a player joins the game and he already was in a farm the last time he played
-- NOTE: he always is in a farm, but we ignore the Spectator Farm (farmId = 0)
function LimitedDailyIncome:onUserJoinGame(superFunc, uniqueUserId, userId, user)
    local farm = g_farmManager:getFarmForUniqueUserId(uniqueUserId)
    local farmId = farm.farmId

    if farmId ~= g_farmManager.SPECTATOR_FARM_ID then
        LimitedDailyIncome.wasPlayerOnline[farmId] = LimitedDailyIncome:checkIfUserIsAssignedToFarm(farmId, uniqueUserId)
    end

    return superFunc(self, uniqueUserId, userId, user)
end

-- this is called when a player joins a farm by himself
-- The first time a player joins a farm, he is assigned to that farm.
-- NOTE: we need overwrittenFunction here because we need to access the farmId of the farm of which addUser is called.
-- this is only possible with self, and to get that self = Farm we need to overwrite the original function
function LimitedDailyIncome:addUser(superFunc, userId, uniqueUserId, isFarmManager, user)
    -- first let the original function do its work, then do our own
    superFunc(self, userId, uniqueUserId, isFarmManager, user)
    -- need to get the user for the uniqueUserId from the userManager. the uniqueUserId passed by the function could be "player"
    -- which is the static value of g_farmManager.SINGLEPLAYER_UUID
    user = g_currentMission.userManager:getUserByUserId(userId)
    uniqueUserId = user:getUniqueUserId()

    local spectator_farm = g_farmManager.SPECTATOR_FARM_ID
    -- assign new user to first farm he joins
    if LimitedDailyIncome.uniqueUserIdToAssignedFarm[uniqueUserId] == nil and self.farmId ~= spectator_farm then
        LimitedDailyIncome.uniqueUserIdToAssignedFarm[uniqueUserId] = self.farmId
    end

    -- check if user that joined the farm is assigned to the farm and if so there was a player online
    LimitedDailyIncome.wasPlayerOnline[self.farmId] = LimitedDailyIncome:checkIfUserIsAssignedToFarm(self.farmId, uniqueUserId)
end

function LimitedDailyIncome:checkIfUserIsAssignedToFarm(farmId, uniqueUserId)
    return farmId == LimitedDailyIncome.uniqueUserIdToAssignedFarm[uniqueUserId]
end

-- daily reset to defaults
function LimitedDailyIncome:dayChanged()
    for farmId, _ in pairs(self.sales) do
        LimitedDailyIncome.sales[farmId] = 0

        if not LimitedDailyIncome.wasPlayerOnline[farmId] then
            LimitedDailyIncome.salesLimit[farmId] = LimitedDailyIncome.salesLimit[farmId] + LimitedDailyIncome.INCREASE_LIMIT_OFFLINE
        elseif LimitedDailyIncome.sales[farmId] <= LimitedDailyIncome.SMALL_SALES_LIMIT then
            LimitedDailyIncome.salesLimit[farmId] = LimitedDailyIncome.salesLimit[farmId] + LimitedDailyIncome.INCREASE_LIMIT_SMALL_SALES
        else
            LimitedDailyIncome.salesLimit[farmId] = LimitedDailyIncome.STANDARD_LIMIT
        end

        LimitedDailyIncome.wasPlayerOnline[farmId] = false
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
    LimitedDailyIncome.sales[farmId] = nil
    LimitedDailyIncome.salesLimit[farmId] = nil
    LimitedDailyIncome.wasPlayerOnline[farmId] = nil

    -- remove all assigned players from deleted farm
    for uniqueUserId, farmId2 in pairs(LimitedDailyIncome.uniqueUserIdToAssignedFarm) do
        if farmId2 == farmId2 then
            LimitedDailyIncome.uniqueUserIdToAssignedFarm[uniqueUserId] = nil
        end
    end
end

-- keep track of earned money to measure the total amount
function LimitedDailyIncome:addMoney(amount, farmId, moneyType, addChange, forceShowChange)
    if amount > 0 and not LimitedDailyIncome:isMoneyTypeAllowed(moneyType) then
        LimitedDailyIncome.sales[farmId] = LimitedDailyIncome.sales[farmId] + amount
    end
end

function LimitedDailyIncome:isMoneyTypeAllowed(moneyType)
    for _, type in pairs(self.allowedMoneyTypes) do
        if moneyType == type then
            return true
        end
    end
    return false
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
    local usedByMission = false

    -- need to check for missions since unloading for mission is still allowed
    for _, mission in pairs(self.missions) do
        if mission.fillSold ~= nil and mission.fillType == fillType and mission.farmId == farmId then
            mission:fillSold(deltaFillLevel)

            usedByMission = true

            break
        end
    end

    if not usedByMission and LimitedDailyIncome.sales[farmId] > LimitedDailyIncome.salesLimit[farmId] then
        --TODO: show error message
        --TODO: stop tipping animation of trailer
        return 0
    end

    return superFunc(self, farmId, deltaFillLevel, fillType, fillInfo, toolType)
end

function LimitedDailyIncome:sellWood(superFunc, farmId)
    if LimitedDailyIncome.sales[farmId] > LimitedDailyIncome.salesLimit[farmId] then
        --TODO: show error message
        -- test-popup
        g_gui:showInfoDialog({
			text = g_l18n:getText(LIMIT_REACHED_WOOD)
		})
        return
    end

    superFunc(self, farmId)
end

function LimitedDailyIncome:getIsFillAllowedFromFarm(superFunc, farmId)
    if LimitedDailyIncome.sales[farmId] > LimitedDailyIncome.salesLimit[farmId] then
        --TODO: show error
        return false
    end

    return true
end

function LimitedDailyIncome:handleDischarge(superFunc, dischargeNode, dischargedLiters, minDropReached, hasMinDropFillLevel)
    superFunc(self, dischargeNode, dischargedLiters, minDropReached, hasMinDropFillLevel)

    local spec = self.spec_dischargeable
    if spec.currentDischargeState == Dischargeable.DISCHARGE_STATE_OBJECT then

        if not LimitedDailyIncome:getIsFillAllowedFromFarm(nil, self:getActiveFarm()) then
			self:setDischargeState(Dischargeable.DISCHARGE_STATE_OFF)
		end
    end
end

FarmManager.saveToXMLFile = Utils.appendedFunction(FarmManager.saveToXMLFile, LimitedDailyIncome.saveToXMLFile)
FarmManager.loadFromXMLFile = Utils.appendedFunction(FarmManager.loadFromXMLFile, LimitedDailyIncome.loadFromXMLFile)
--tracking money
FSBaseMission.addMoney = Utils.prependedFunction(FSBaseMission.addMoney, LimitedDailyIncome.addMoney)
--farms Management
FarmManager.createFarm = Utils.overwrittenFunction(FarmManager.createFarm, LimitedDailyIncome.createFarm)
FarmManager.removeFarm = Utils.appendedFunction(FarmManager.removeFarm, LimitedDailyIncome.removeFarm)
-- player management
Farm.addUser = Utils.overwrittenFunction(Farm.addUser, LimitedDailyIncome.addUser)
Farm.onUserJoinGame = Utils.overwrittenFunction(Farm.onUserJoinGame, LimitedDailyIncome.onUserJoinGame) --overwritten is used to keep the return value
-- permission managing
-- overwritten is used because we do some code injection. This means we insert some code at the start of the original function
MissionManager.startMission = Utils.overwrittenFunction(MissionManager.startMission, LimitedDailyIncome.startMission)
DealerFarmStrategie.applyChanges = Utils.overwrittenFunction(DealerFarmStrategie.applyChanges, LimitedDailyIncome.applyChangesFarms)
DealerTrailerStrategie.applyChanges = Utils.overwrittenFunction(DealerTrailerStrategie.applyChanges, LimitedDailyIncome.applyChangesTrailer)
SellingStation.addFillLevelFromTool = Utils.overwrittenFunction(SellingStation.addFillLevelFromTool, LimitedDailyIncome.addFillLevelFromTool)
SellingStation.getIsFillAllowedFromFarm = Utils.overwrittenFunction(SellingStation.getIsFillAllowedFromFarm, LimitedDailyIncome.getIsFillAllowedFromFarm)
WoodSellStationPlaceable.sellWood = Utils.overwrittenFunction(WoodSellStationPlaceable.sellWood, LimitedDailyIncome.sellWood)

BaseMission.loadMapFinished = Utils.appendedFunction(BaseMission.loadMapFinished, LimitedDailyIncome.loadMapFinished)