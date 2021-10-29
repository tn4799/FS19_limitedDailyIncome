source(g_currentModDirectory .. "src/events/UpdateDataEvent.lua")

LimitedDailyIncome = {}

LimitedDailyIncome.isDevelopmentVersion = true

LimitedDailyIncome.sales = {}
LimitedDailyIncome.salesLimit = {}
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
LimitedDailyIncome.INCREASE_LIMIT_NO_SALES = 250000
-- Daily Limit that gets ignored.
LimitedDailyIncome.SMALL_SALES_LIMIT = 30000
-- Increase when player stays below the limit.
LimitedDailyIncome.INCREASE_LIMIT_SMALL_SALES = 50000

LimitedDailyIncome.overlayPath = g_currentModDirectory .. "back.dds"
LimitedDailyIncome.salesLimitBox = nil
LimitedDailyIncome.salesBox = nil
LimitedDailyIncome.moneyIconOverlay = nil

function LimitedDailyIncome:loadMapFinished(node, arguments, callAsyncCallback)
    LimitedDailyIncome.staticValuesFilename = string.format(getUserProfileAppPath() .. "savegame%d/LimitedDailyIncome.xml", g_careerScreen.selectedIndex)
    if g_currentMission:getIsServer() then
        g_currentMission.environment:addDayChangeListener(LimitedDailyIncome)
    end

    local vehicleTypes = g_vehicleTypeManager:getVehicleTypes()
    for _, vehicleType in pairs(vehicleTypes) do
        if SpecializationUtil.hasSpecialization(Dischargeable, vehicleType.specializations) then
            SpecializationUtil.registerOverwrittenFunction(vehicleType, "handleDischarge", LimitedDailyIncome.handleDischarge)
        end
    end

    g_messageCenter:subscribe(MessageType.FARM_CREATED, LimitedDailyIncome.onFarmCreated, LimitedDailyIncome)
    g_messageCenter:subscribe(MessageType.FARM_DELETED, LimitedDailyIncome.onFarmDeleted, LimitedDailyIncome)
    --g_messageCenter:subscribe(MessageType.PLAYER_FARM_CHANGED, LimitedDailyIncome.onPlayerFarmChanged, LimitedDailyIncome)

    LimitedDailyIncome:createHUDComponents(g_baseHUDFilename, g_currentMission.hud.gameInfoDisplay)
end

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
        LimitedDailyIncome.sales[farmId] = Utils.getNoNil(getXMLFloat(xmlFile, key .. ".sales"), 0)
        LimitedDailyIncome.salesLimit[farmId] = Utils.getNoNil(getXMLInt(xmlFile, key .. ".salesLimit"), LimitedDailyIncome.STANDARD_LIMIT)

        i = i + 1
    end

    delete(xmlFile)

    if g_currentMission:getIsServer() then
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

			index = index + 1
		end
    end

    index = 0

    saveXMLFile(xmlFile)
	delete(xmlFile)

    if g_currentMission:getIsServer() then
        LimitedDailyIncome:saveStaticValues()
    end
end

function LimitedDailyIncome:loadStaticValues()
    if not fileExists(LimitedDailyIncome.staticValuesFilename) then
        return
    end

    local xmlFile = loadXMLFile("TempXML", LimitedDailyIncome.staticValuesFilename)
    local key = "limitedDailyIncome"

    LimitedDailyIncome.STANDARD_LIMIT = Utils.getNoNil(getXMLInt(xmlFile, key .. ".standardLimit"), LimitedDailyIncome.STANDARD_LIMIT)
    LimitedDailyIncome.SMALL_SALES_LIMIT = Utils.getNoNil(getXMLInt(xmlFile, key .. ".smallSalesLimit"), LimitedDailyIncome.SMALL_SALES_LIMIT)
    LimitedDailyIncome.INCREASE_LIMIT_NO_SALES = Utils.getNoNil(getXMLInt(xmlFile, key .. ".increaseLimitNoSales"), LimitedDailyIncome.INCREASE_LIMIT_NO_SALES)
    LimitedDailyIncome.INCREASE_LIMIT_SMALL_SALES = Utils.getNoNil(getXMLInt(xmlFile, key .. ".increaseLimitSmallSales"), LimitedDailyIncome.INCREASE_LIMIT_SMALL_SALES)

    delete(xmlFile)
end

function LimitedDailyIncome:saveStaticValues()
    local xmlFile = createXMLFile("LimitedDailyIncomeXML", LimitedDailyIncome.staticValuesFilename, "limitedDailyIncome")
    local key = "limitedDailyIncome"

    setXMLInt(xmlFile, key .. ".standardLimit", LimitedDailyIncome.STANDARD_LIMIT)
    setXMLInt(xmlFile, key .. ".smallSalesLimit", LimitedDailyIncome.SMALL_SALES_LIMIT)
    setXMLInt(xmlFile, key .. ".increaseLimitNoSales", LimitedDailyIncome.INCREASE_LIMIT_NO_SALES)
    setXMLInt(xmlFile, key .. ".increaseLimitSmallSales", LimitedDailyIncome.INCREASE_LIMIT_SMALL_SALES)

    saveXMLFile(xmlFile)
    delete(xmlFile)
end

function LimitedDailyIncome:playerJoinedGame(uniqueUserId, userId, user, connection)
    if g_currentMission:getIsServer() then
        -- sync sales and salesLimit for all farms (because user could switch farm to earn money for them)
        for farmId, sales in pairs(LimitedDailyIncome.sales) do
            local salesLimit = LimitedDailyIncome.salesLimit[farmId]
            g_server:broadcastEvent(UpdateDataEvent:new(farmId, sales, salesLimit), nil, connection)
        end
    end
end

-- daily reset to defaults
function LimitedDailyIncome:dayChanged()
    for farmId, sales in pairs(self.sales) do
        if sales == 0 then
            LimitedDailyIncome.salesLimit[farmId] = LimitedDailyIncome.salesLimit[farmId] + LimitedDailyIncome.INCREASE_LIMIT_NO_SALES
        elseif sales <= LimitedDailyIncome.SMALL_SALES_LIMIT then
            LimitedDailyIncome.salesLimit[farmId] = LimitedDailyIncome.salesLimit[farmId] + LimitedDailyIncome.INCREASE_LIMIT_SMALL_SALES
        else
            LimitedDailyIncome.salesLimit[farmId] = LimitedDailyIncome.STANDARD_LIMIT
        end

        LimitedDailyIncome.sales[farmId] = 0

        g_server:broadcastEvent(UpdateDataEvent:new(farmId, LimitedDailyIncome.sales[farmId], LimitedDailyIncome.salesLimit[farmId]))
    end
end

--register new farm with default values
function LimitedDailyIncome:onFarmCreated(farmId)
    if farmId == g_farmManager.SPECTATOR_FARM_ID then
        return
    end

    if g_currentMission:getIsClient() then
        return
    end

    LimitedDailyIncome.sales[farmId] = 0
    LimitedDailyIncome.salesLimit[farmId] = LimitedDailyIncome.STANDARD_LIMIT

    if g_currentMission:getIsServer() then
        local sales = LimitedDailyIncome.sales[farmId]
        local salesLimit = LimitedDailyIncome.salesLimit[farmId]
        g_server:broadcastEvent(UpdateDataEvent:new(farmId, sales, salesLimit))
    end
end

--remove farm if deleted
function LimitedDailyIncome:onFarmDeleted(farmId)
    LimitedDailyIncome.sales[farmId] = nil
    LimitedDailyIncome.salesLimit[farmId] = nil

    if g_currentMission:getIsServer() then
        g_server:broadcastEvent(UpdateDataEvent:new(farmId, LimitedDailyIncome.sales[farmId], LimitedDailyIncome.salesLimit[farmId]))
    end
end

-- keep track of earned money to measure the total amount
function LimitedDailyIncome:addMoney(amount, farmId, moneyType, addChange, forceShowChange)
    if amount > 0 and not LimitedDailyIncome:isMoneyTypeAllowed(moneyType) then
        LimitedDailyIncome.sales[farmId] = LimitedDailyIncome.sales[farmId] + amount

        if g_currentMission:getIsServer() then
            g_server:broadcastEvent(UpdateDataEvent:new(farmId, LimitedDailyIncome.sales[farmId], LimitedDailyIncome.salesLimit[farmId]))
        end
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
        LimitedDailyIncome:showErrorDialog("LIMIT_REACHED_MISSION")
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
        LimitedDailyIncome:showErrorDialog("LIMIT_REACHED_ANIMAL")
        return
    end

    superFunc(this)
end

function LimitedDailyIncome:addFillLevelFromTool(superFunc, farmId, deltaFillLevel, fillType, fillInfo, toolType)
    --TODO: check if this method is called when limit is reached
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
        LimitedDailyIncome:showErrorDialog("LIMIT_REACHED_FRUIT")
        return 0
    end

    return superFunc(self, farmId, deltaFillLevel, fillType, fillInfo, toolType)
end

function LimitedDailyIncome:sellWood(superFunc, farmId)
    if LimitedDailyIncome.sales[farmId] > LimitedDailyIncome.salesLimit[farmId] then
        LimitedDailyIncome:showErrorDialog("LIMIT_REACHED_WOOD")
        return
    end

    superFunc(self, farmId)
end

function LimitedDailyIncome:getIsFillAllowedFromFarm(superFunc, farmId)
    if LimitedDailyIncome.sales[farmId] > LimitedDailyIncome.salesLimit[farmId] then
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

function LimitedDailyIncome:draw()
    if not g_currentMission.hud:getIsVisible() then
        return
    end

    local gameInfoDisplay = g_currentMission.hud.gameInfoDisplay

    setTextBold(false)
	setTextAlignment(RenderText.ALIGN_RIGHT)
	setTextColor(unpack(gameInfoDisplay.COLOR.TEXT))

    local textOffX, textOffY = gameInfoDisplay:scalePixelToScreenVector(gameInfoDisplay.POSITION.MONEY_TEXT)
    local salesLimitBoxPosX, salesLimitBoxPosY = LimitedDailyIncome.salesLimitBox:getPosition()
    local salesBoxPosX, salesBoxPosY = LimitedDailyIncome.salesBox:getPosition()
    local salesLimitTextPositionX = salesLimitBoxPosX + LimitedDailyIncome.salesLimitBox:getWidth() + textOffX
    local salesTextPositionX = salesBoxPosX + LimitedDailyIncome.salesBox:getWidth() + textOffX - 0.005
    local textPositionY = salesBoxPosY + LimitedDailyIncome.salesBox:getHeight() * 0.5 + textOffY

    if g_currentMission.player ~= nil then
		local farmId = g_currentMission.player.farmId
		local salesLimitText = g_i18n:formatMoney(LimitedDailyIncome.salesLimit[farmId], 0, false, true)
        local salesText = g_i18n:formatMoney(LimitedDailyIncome.sales[farmId], 0, false, true)

		renderText(salesLimitTextPositionX, textPositionY, gameInfoDisplay.moneyTextSize, salesLimitText)
        renderText(salesTextPositionX, textPositionY, gameInfoDisplay.moneyTextSize, salesText)
	end

    LimitedDailyIncome.moneyIconOverlay:setUVs(getNormalizedUVs(gameInfoDisplay.UV.MONEY_ICON[gameInfoDisplay.moneyUnit]))
end

function LimitedDailyIncome:createHUDComponents(hudAtlasPath, gameInfoDisplay)
    local topRightX, topRightY = GameInfoDisplay.getBackgroundPosition(1)
    -- we want to position our HUD below the standard HUD. so we need to reduce the height of the topRight corner 2 times.
    -- the last value is to create a little gap between our hud and the giants hud
	local bottomY = topRightY - 2*gameInfoDisplay:getHeight() - 0.003
    local marginWidth, marginHeight = gameInfoDisplay:scalePixelToScreenVector(GameInfoDisplay.SIZE.BOX_MARGIN)
	local rightX, salesLimitBox = LimitedDailyIncome:createBox(hudAtlasPath, topRightX, bottomY, gameInfoDisplay, false)
    LimitedDailyIncome.salesLimitBox = salesLimitBox
    local sepX = rightX - marginWidth
    rightX, LimitedDailyIncome.salesBox = LimitedDailyIncome:createBox(hudAtlasPath, rightX - marginWidth, bottomY, gameInfoDisplay, true)
    rightX = rightX - marginWidth
    local centerY = bottomY + gameInfoDisplay:getHeight() * 0.5
	local separator = gameInfoDisplay:createVerticalSeparator(hudAtlasPath, sepX, centerY)
    LimitedDailyIncome.salesBox:addChild(separator)

    local posX, posY = LimitedDailyIncome.salesBox:getPosition()
    local widthBackground = -marginWidth 
                    + LimitedDailyIncome.salesBox:getWidth() + marginWidth * 2
                    + LimitedDailyIncome.salesLimitBox:getWidth() + marginWidth
    local backgroundOverlay = Overlay:new(LimitedDailyIncome.overlayPath, posX, posY, widthBackground, gameInfoDisplay:getHeight())
    local backgroundElement = HUDElement:new(backgroundOverlay)
    backgroundElement:addChild(LimitedDailyIncome.salesLimitBox)
    backgroundElement:addChild(LimitedDailyIncome.salesBox)
    
    gameInfoDisplay:addChild(backgroundElement)
end

function LimitedDailyIncome:createBox(hudAtlasPath, rightX, bottomY, gameInfoDisplay, withIcon)
    local iconWidth, iconHeight = gameInfoDisplay:scalePixelToScreenVector(gameInfoDisplay.SIZE.MONEY_ICON)
    local boxWidth, boxHeight = gameInfoDisplay:scalePixelToScreenVector(gameInfoDisplay.SIZE.MONEY_BOX)
    if not withIcon then
        boxWidth = boxWidth - iconWidth
        boxHeight = boxHeight - iconHeight
    end
	local posX = rightX - boxWidth
	local posY = bottomY + boxHeight * 0.5
	local boxOverlay = Overlay:new(nil, posX, bottomY, boxWidth, boxHeight)
	local boxElement = HUDElement:new(boxOverlay)
    
    if withIcon then
        posY = bottomY + (boxHeight - iconHeight) * 0.5

        local iconOverlay = Overlay:new(hudAtlasPath, posX, posY, iconWidth, iconHeight)

        iconOverlay:setUVs(getNormalizedUVs(gameInfoDisplay.UV.MONEY_ICON[gameInfoDisplay.moneyUnit]))
        iconOverlay:setColor(unpack(gameInfoDisplay.COLOR.ICON))
        LimitedDailyIncome.moneyIconOverlay = iconOverlay

        boxElement:addChild(HUDElement:new(iconOverlay))
    end

    return posX, boxElement
end

function LimitedDailyIncome:showErrorDialog(errorMessage)
    g_gui:showInfoDialog({
        text = g_i18n:getText(errorMessage)
    })
end

function LimitedDailyIncome.sendObjects(self,connection)
    for farmId, sales in pairs(LimitedDailyIncome.sales) do
       local salesLimit = LimitedDailyIncome.salesLimit[farmId]
       connection:sendEvent(UpdateDataEvent:new(farmId, sales, salesLimit))
   end
end

function LimitedDailyIncome:addConsoleCommands()
    addConsoleCommand("ldiPrintFarmData", "Prints the sales and salesLimit of the farm", "printDataFromFarm", LimitedDailyIncome)
    addConsoleCommand("ldiPrintAll", "Prints the whole content of sales and salesLimit.", "printAllData", LimitedDailyIncome)
    addConsoleCommand("ldiSetSalesForFarm", "set the current sales of the farm with the farmId to the chosen value", "setSalesForFarm", LimitedDailyIncome)
    addConsoleCommand("ldiSetSalesLimitForFarm", "set the current sales limit of the farm with the farmId to the entered value", "setSalesLimitForFarm", LimitedDailyIncome)
    addConsoleCommand("restartSavegame", "load and start a savegame", "restartSaveGame", LimitedDailyIncome)
    addConsoleCommand("printGUITable", "prints the content of a table in g_gui", "printGUITable", LimitedDailyIncome)
    addConsoleCommand("printHUDTable", "prints the content of the table g_currentMission.hud", "printHUDTable", LimitedDailyIncome)
end

-- functions for console commands
function LimitedDailyIncome:printDataFromFarm(farmId)
    farmId = tonumber(farmId)
    print("sales: " .. tostring(LimitedDailyIncome.sales[farmId]))
    print("salesLimit: " .. tostring(LimitedDailyIncome.salesLimit[farmId]))
end

function LimitedDailyIncome:printAllData()
    for farmId, _ in pairs(LimitedDailyIncome.sales) do
        print("farmId: " .. farmId)
        print("sales: " .. tostring(LimitedDailyIncome.sales[farmId]))
        print("salesLimit: " .. tostring(LimitedDailyIncome.salesLimit[farmId]))
    end
end

function LimitedDailyIncome:restartSaveGame(saveGameNumber)
    if g_server then
        restartApplication(" -autoStartSavegameId " .. saveGameNumber)
    end
end

function LimitedDailyIncome:printGUITable(key)
    if type(g_gui[key]) ~= "table" then
        print("value: " .. tostring(g_gui[key]))
        return
    end
    for k,v in pairs(g_gui[key]) do
        print("key: " .. tostring(k) .. "    value: " .. tostring(v))
    end
end

function LimitedDailyIncome:printHUDTable()
    for k,v in pairs(g_currentMission.hud) do
        print("key: " .. tostring(k) .. "    value: " .. tostring(v))
    end
end

function LimitedDailyIncome:setSalesLimitForFarm(farmId, salesLimit)
    farmId = tonumber(farmId)
    salesLimit = tonumber(salesLimit)

    LimitedDailyIncome.salesLimit[farmId] = salesLimit
end

function LimitedDailyIncome:setSalesForFarm(farmId, sales)
    farmId = tonumber(farmId)
    sales = tonumber(sales)

    LimitedDailyIncome.sales[farmId] = sales
end

FarmManager.saveToXMLFile = Utils.appendedFunction(FarmManager.saveToXMLFile, LimitedDailyIncome.saveToXMLFile)
FarmManager.loadFromXMLFile = Utils.appendedFunction(FarmManager.loadFromXMLFile, LimitedDailyIncome.loadFromXMLFile)
--tracking money
FSBaseMission.addMoney = Utils.prependedFunction(FSBaseMission.addMoney, LimitedDailyIncome.addMoney)
-- player management
FarmManager.playerJoinedGame = Utils.appendedFunction(FarmManager.playerJoinedGame, LimitedDailyIncome.playerJoinedGame)
-- permission managing
-- overwritten is used because we do some code injection. This means we insert some code at the start of the original function
MissionManager.startMission = Utils.overwrittenFunction(MissionManager.startMission, LimitedDailyIncome.startMission)
DealerFarmStrategie.applyChanges = Utils.overwrittenFunction(DealerFarmStrategie.applyChanges, LimitedDailyIncome.applyChangesFarms)
DealerTrailerStrategie.applyChanges = Utils.overwrittenFunction(DealerTrailerStrategie.applyChanges, LimitedDailyIncome.applyChangesTrailer)
SellingStation.addFillLevelFromTool = Utils.overwrittenFunction(SellingStation.addFillLevelFromTool, LimitedDailyIncome.addFillLevelFromTool)
SellingStation.getIsFillAllowedFromFarm = Utils.overwrittenFunction(SellingStation.getIsFillAllowedFromFarm, LimitedDailyIncome.getIsFillAllowedFromFarm)
WoodSellStationPlaceable.sellWood = Utils.overwrittenFunction(WoodSellStationPlaceable.sellWood, LimitedDailyIncome.sellWood)

Server.sendObjects = Utils.prependedFunction(Server.sendObjects, LimitedDailyIncome.sendObjects)

BaseMission.loadMapFinished = Utils.appendedFunction(BaseMission.loadMapFinished, LimitedDailyIncome.loadMapFinished)
addModEventListener(LimitedDailyIncome)

if LimitedDailyIncome.isDevelopmentVersion then
    LimitedDailyIncome:addConsoleCommands()
end