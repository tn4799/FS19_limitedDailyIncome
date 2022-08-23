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
    MoneyType.TRANSFER,
    MoneyType.COLLECTIBLE
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
LimitedDailyIncome.backgroundElement = nil
LimitedDailyIncome.GAP_WIDTH = 20

LimitedDailyIncome.backupSellingStationFillAllowed = SellingStation.getIsFillAllowedFromFarm

function LimitedDailyIncome:loadMapFinished(node, arguments, callAsyncCallback)
    LimitedDailyIncome.staticValuesFilename = string.format(getUserProfileAppPath() .. "savegame%d/LimitedDailyIncome.xml", g_currentMission.missionInfo.savegameIndex)
    if g_currentMission:getIsServer() then
        g_messageCenter:subscribe(MessageType.DAY_CHANGED, LimitedDailyIncome.dayChanged, LimitedDailyIncome)
    end

    local vehicleTypes = g_vehicleTypeManager:getTypes()
    for _, vehicleType in pairs(vehicleTypes) do
        if SpecializationUtil.hasSpecialization(Dischargeable, vehicleType.specializations) then
            SpecializationUtil.registerOverwrittenFunction(vehicleType, "handleDischarge", LimitedDailyIncome.handleDischarge)
        end
    end

    vehicleTypes = g_placeableTypeManager:getTypes()
    for _, placeableType in pairs(vehicleTypes) do
        if SpecializationUtil.hasSpecialization(PlaceableTrainSystem, placeableType.specializations) then
            SpecializationUtil.registerOverwrittenFunction(placeableType, "onSellGoodsQuestion", LimitedDailyIncome.onSellGoodsQuestion)
        end
    end

    local screenClass = g_gui.nameScreenTypes["ConstructionScreen"]
    local screenElement = g_gui.screens[screenClass]

    screenElement.onOpen = Utils.appendedFunction(screenElement.onOpen, LimitedDailyIncome.onOpenConstructionScreen)

    g_messageCenter:subscribe(MessageType.FARM_CREATED, LimitedDailyIncome.onFarmCreated, LimitedDailyIncome)
    g_messageCenter:subscribe(MessageType.FARM_DELETED, LimitedDailyIncome.onFarmDeleted, LimitedDailyIncome)

    LimitedDailyIncome:createHUDComponents(g_baseHUDFilename, g_currentMission.hud.gameInfoDisplay)
end

function LimitedDailyIncome:loadFromXMLFile(xmlFilename)
    if xmlFilename == nil then
        --load default values
        self.sales = {}
        self.salesLimit = {}
        return
    end

    local xmlFile = XMLFile.load("TempXML", xmlFilename)

    local i = 0
    while true do
        local key = string.format("farms.farm(%d)", i)

		if not xmlFile:hasProperty(key) then
			break
		end

        local farmId = xmlFile:getInt(key .. "#farmId")
        key = key .. ".limitedDayIncome"

        -- added tag of limitedDayIncome to key
        LimitedDailyIncome.sales[farmId] = Utils.getNoNil(xmlFile:getFloat(key .. ".sales"), 0)
        LimitedDailyIncome.salesLimit[farmId] = Utils.getNoNil(xmlFile:getInt( key .. ".salesLimit"), LimitedDailyIncome.STANDARD_LIMIT)

        i = i + 1
    end

    xmlFile:delete()

    if g_currentMission:getIsServer() then
        LimitedDailyIncome:loadStaticValues()
    end
end

function LimitedDailyIncome:saveToXMLFile(xmlFilename)
    local xmlFile = XMLFile.load("TempXML", xmlFilename)

    local index = 0
    local farms = g_farmManager:getFarms()

    for _, farm in pairs(farms) do
        if farm.farmId ~= g_farmManager.SPECTATOR_FARM_ID then
			local key = string.format("farms.farm(%d).limitedDayIncome", index)
            local farmId = farm.farmId

            xmlFile:setFloat(key .. ".sales", LimitedDailyIncome.sales[farmId])
            xmlFile:setInt(key .. ".salesLimit", LimitedDailyIncome.salesLimit[farmId])

			index = index + 1
		end
    end

    xmlFile:save()
	xmlFile:delete()

    if g_currentMission:getIsServer() then
        LimitedDailyIncome:saveStaticValues()
    end
end

function LimitedDailyIncome:loadStaticValues()
    if not fileExists(LimitedDailyIncome.staticValuesFilename) then
        return
    end

    local xmlFile = XMLFile.load("TempXML", LimitedDailyIncome.staticValuesFilename)
    local key = "limitedDailyIncome"

    LimitedDailyIncome.STANDARD_LIMIT = Utils.getNoNil(xmlFile:getInt(key .. ".standardLimit"), LimitedDailyIncome.STANDARD_LIMIT)
    LimitedDailyIncome.SMALL_SALES_LIMIT = Utils.getNoNil(xmlFile:getInt(key .. ".smallSalesLimit"), LimitedDailyIncome.SMALL_SALES_LIMIT)
    LimitedDailyIncome.INCREASE_LIMIT_NO_SALES = Utils.getNoNil(xmlFile:getInt(key .. ".increaseLimitNoSales"), LimitedDailyIncome.INCREASE_LIMIT_NO_SALES)
    LimitedDailyIncome.INCREASE_LIMIT_SMALL_SALES = Utils.getNoNil(xmlFile:getInt(key .. ".increaseLimitSmallSales"), LimitedDailyIncome.INCREASE_LIMIT_SMALL_SALES)

    xmlFile:delete()
end

function LimitedDailyIncome:saveStaticValues()
    if LimitedDailyIncome.staticValuesFilename == nil then
        return
    end

    local xmlFile = XMLFile.create("LimitedDailyIncomeXML", LimitedDailyIncome.staticValuesFilename, "limitedDailyIncome")
    local key = "limitedDailyIncome"

    xmlFile:setInt(key .. ".standardLimit", LimitedDailyIncome.STANDARD_LIMIT)
    xmlFile:setInt(key .. ".smallSalesLimit", LimitedDailyIncome.SMALL_SALES_LIMIT)
    xmlFile:setInt(key .. ".increaseLimitNoSales", LimitedDailyIncome.INCREASE_LIMIT_NO_SALES)
    xmlFile:setInt(key .. ".increaseLimitSmallSales", LimitedDailyIncome.INCREASE_LIMIT_SMALL_SALES)

    xmlFile:save()
    xmlFile:delete()
end

function LimitedDailyIncome:playerJoinedGame(uniqueUserId, userId, user, connection)
    if g_currentMission:getIsServer() then

        for farmId, sales in pairs(LimitedDailyIncome.sales) do
            local salesLimit = LimitedDailyIncome.salesLimit[farmId]
            g_server:broadcastEvent(UpdateDataEvent.new(farmId, sales, salesLimit), nil, connection)
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

        g_server:broadcastEvent(UpdateDataEvent.new(farmId, LimitedDailyIncome.sales[farmId], LimitedDailyIncome.salesLimit[farmId]))
    end
end

--register new farm with default values
function LimitedDailyIncome:onFarmCreated(farmId)
    if farmId == g_farmManager.SPECTATOR_FARM_ID then
        return
    end

    if not g_currentMission:getIsServer() then
        return
    end

    LimitedDailyIncome.sales[farmId] = 0
    LimitedDailyIncome.salesLimit[farmId] = LimitedDailyIncome.STANDARD_LIMIT

    local sales = LimitedDailyIncome.sales[farmId]
    local salesLimit = LimitedDailyIncome.salesLimit[farmId]
    g_server:broadcastEvent(UpdateDataEvent.new(farmId, sales, salesLimit))
end

--remove farm if deleted
function LimitedDailyIncome:onFarmDeleted(farmId)
    LimitedDailyIncome.sales[farmId] = nil
    LimitedDailyIncome.salesLimit[farmId] = nil

    if g_currentMission ~= nil and g_currentMission:getIsServer() then
        g_server:broadcastEvent(UpdateDataEvent.new(farmId, LimitedDailyIncome.sales[farmId], LimitedDailyIncome.salesLimit[farmId]))
    end
end

-- keep track of earned money to measure the total amount
function LimitedDailyIncome:addMoney(amount, farmId, moneyType, addChange, forceShowChange)
    if amount > 0 and moneyType == MoneyType.MISSIONS then
        LimitedDailyIncome.sales[farmId] = LimitedDailyIncome.sales[farmId] + amount

        if g_currentMission:getIsServer() then
            g_server:broadcastEvent(UpdateDataEvent.new(farmId, LimitedDailyIncome.sales[farmId], LimitedDailyIncome.salesLimit[farmId]))
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

    superFunc(self, mission, farmId, spawnVehicles)
end

-- disable making money with selling animals through trailer
function LimitedDailyIncome:applyTargetTrailer(superFunc, itemIndex, numItems)
    -- get vehicle the trailer is attached to
    local farmId = self.trailer:getOwnerFarmId()

    return LimitedDailyIncome:checkTotalSum(self, superFunc, farmId, itemIndex, numItems)
end

-- disable making money with selling animals through selling at animalTrader and husbandaries
function LimitedDailyIncome:applyTargetFarms(superFunc, itemIndex, numItems)
    local farmId = self.husbandry:getOwnerFarmId()

    return LimitedDailyIncome:checkTotalSum(self, superFunc, farmId, itemIndex, numItems)
end

function LimitedDailyIncome:checkTotalSum(this, superFunc, farmId, itemIndex, numItems)
    if LimitedDailyIncome.sales[farmId] >= LimitedDailyIncome.salesLimit[farmId] then
        LimitedDailyIncome:showErrorDialog("LIMIT_REACHED_ANIMAL")
        return false
    end

    return superFunc(this, itemIndex, numItems)
end

function LimitedDailyIncome:processWood(superFunc, farmId, noEventSend)
    local farmIdOwnerUnloadingStation = self.target:getTarget():getOwnerFarmId()
    if farmIdOwnerUnloadingStation == g_farmManager.SPECTATOR_FARM_ID and self:getWoodLogs() ~= nil and LimitedDailyIncome.sales[farmId] > LimitedDailyIncome.salesLimit[farmId] then
        LimitedDailyIncome:showErrorDialog("LIMIT_REACHED_WOOD")
        return
    end

    superFunc(self, farmId, noEventSend)
end

function LimitedDailyIncome:getIsFillAllowedFromFarm(superFunc, farmId)
    if self.storeSoldGoods then
        return SellingStation:superClass().getIsFillAllowedFromFarm(self, farmId)
	end

    if not self.isOwned and LimitedDailyIncome.sales[farmId] > LimitedDailyIncome.salesLimit[farmId] then
        return false
    end

    return superFunc(self, farmId)
end

function LimitedDailyIncome:load(superFunc, components, xmlFile, key, customEnv, i3dMappings)
    local erg = superFunc(self, components, xmlFile, key, customEnv, i3dMappings)

    function self.unloadingStation.getIsFillAllowedFromFarm(_, farmId)
        if not self.isOwned and LimitedDailyIncome.sales[farmId] > LimitedDailyIncome.salesLimit[farmId] then
            return false
        end

		return g_currentMission.accessHandler:canFarmAccess(farmId, self.owningPlaceable)
	end

    return erg
end

function LimitedDailyIncome:directlySellOutputs(superFunc)
    local farmId = self:getOwnerFarmId()
    if farmId ~= g_farmManager.SPECTATOR_FARM_ID and LimitedDailyIncome.sales[farmId] > LimitedDailyIncome.salesLimit[farmId] then
        return
    end

    superFunc(self)
end

function LimitedDailyIncome:handleDischarge(superFunc, dischargeNode, dischargedLiters, minDropReached, hasMinDropFillLevel)
    superFunc(self, dischargeNode, dischargedLiters, minDropReached, hasMinDropFillLevel)

    local spec = self.spec_dischargeable
    if spec.currentDischargeState == Dischargeable.DISCHARGE_STATE_OBJECT then
        local dischargeNode = spec.currentDischargeNode
        local object = dischargeNode.dischargeObject

        if object.getIsFillAllowedFromFarm ~= nil and not object:getIsFillAllowedFromFarm(self:getActiveFarm()) then
			self:setDischargeState(Dischargeable.DISCHARGE_STATE_OFF)
		end
    end
end

function LimitedDailyIncome:onSellGoodsQuestion(superFunc, yes)
    local farmId = self.spec_trainSystem.rentFarmId

    if yes and farmId ~= g_farmManager.SPECTATOR_FARM_ID and LimitedDailyIncome.sales[farmId] > LimitedDailyIncome.salesLimit[farmId] then
        LimitedDailyIncome:showErrorDialog("LIMIT_REACHED_FRUIT")
        return
    end

    superFunc(self, yes)
end

function LimitedDailyIncome:draw()
    if not g_currentMission.hud:getIsVisible() then
        return
    end

    if g_currentMission.player ~= nil and g_currentMission.player.farmId == g_farmManager.SPECTATOR_FARM_ID then
        return
    end

    local gameInfoDisplay = g_currentMission.hud.gameInfoDisplay

    if g_currentMission.player ~= nil and g_currentMission.player.farmId == g_farmManager.SPECTATOR_FARM_ID then 
        LimitedDailyIncome.backgroundElement:setVisible(false)
        return
    end

    -- update box possition adjusted to gameInfoDisplayWidth
    local topRightX, topRightY = GameInfoDisplay.getBackgroundPosition(1)
    local bottomY = topRightY - gameInfoDisplay:getHeight()
    topRightX = topRightX - gameInfoDisplay:getVisibleWidth() - gameInfoDisplay:scalePixelToScreenWidth(LimitedDailyIncome.GAP_WIDTH)
    local posX = topRightX - LimitedDailyIncome.salesLimitBox:getWidth()
    LimitedDailyIncome.backgroundElement:setPosition(posX, bottomY)

    LimitedDailyIncome.backgroundElement:setVisible(true)


    setTextBold(false)
	setTextAlignment(RenderText.ALIGN_RIGHT)
	setTextColor(unpack(gameInfoDisplay.COLOR.TEXT))

    local textOffX, textOffY = gameInfoDisplay:scalePixelToScreenVector(gameInfoDisplay.POSITION.MONEY_TEXT)

    local salesLimitBoxPosX, salesLimitBoxPosY = LimitedDailyIncome.salesLimitBox:getPosition()
    local salesLimitTextPositionX = salesLimitBoxPosX + LimitedDailyIncome.salesLimitBox:getWidth() - textOffX
    local textPositionYCenter = salesLimitBoxPosY + LimitedDailyIncome.salesLimitBox:getHeight() * 0.5 - gameInfoDisplay.moneyTextSize * 0.5 + textOffY
    local salesLimitTextPositionY = textPositionYCenter - 3.5 * textOffY
    local textPositionY = textPositionYCenter + 3.5 * textOffY

    if g_currentMission.player ~= nil then
		local farmId = g_currentMission.player.farmId
        local salesLimitText = g_i18n:formatMoney(LimitedDailyIncome.salesLimit[farmId], 0, false, true)
        local salesText = g_i18n:formatMoney(LimitedDailyIncome.sales[farmId], 0, false, true)

		renderText(salesLimitTextPositionX, salesLimitTextPositionY, gameInfoDisplay.moneyTextSize, salesLimitText)
        renderText(salesLimitTextPositionX, textPositionY, gameInfoDisplay.moneyTextSize, salesText)
	end

    LimitedDailyIncome.moneyIconOverlay:setUVs(GuiUtils.getUVs(GameInfoDisplay.UV.MONEY_ICON))
    local x, y = LimitedDailyIncome.moneyIconOverlay:getPosition()
	local moneyCurrencyPositionX = LimitedDailyIncome.moneyIconOverlay.width * 0.5 + x
	local moneyCurrencyPositionY = LimitedDailyIncome.moneyIconOverlay.height * 0.5 + y - gameInfoDisplay.moneyTextSize * 0.5 + textOffY

    setTextAlignment(RenderText.ALIGN_CENTER)
	setTextColor(unpack(GameInfoDisplay.COLOR.ICON))
    renderText(moneyCurrencyPositionX, moneyCurrencyPositionY, gameInfoDisplay.moneyTextSize, gameInfoDisplay.moneyCurrencyText)
end


function LimitedDailyIncome:createHUDComponents(hudAtlasPath, gameInfoDisplay)
    local topRightX, topRightY = GameInfoDisplay.getBackgroundPosition(1)
    local bottomY = topRightY - gameInfoDisplay:getHeight()
    topRightX = topRightX - gameInfoDisplay:getVisibleWidth() - gameInfoDisplay:scalePixelToScreenWidth(LimitedDailyIncome.GAP_WIDTH)
    local marginWidth, marginHeight = gameInfoDisplay:scalePixelToScreenVector(GameInfoDisplay.SIZE.BOX_MARGIN)
    local rightX, salesLimitBox = LimitedDailyIncome:createBox(hudAtlasPath, topRightX, bottomY, gameInfoDisplay, true)
    LimitedDailyIncome.salesLimitBox = salesLimitBox
    local posX, posY = LimitedDailyIncome.salesLimitBox:getPosition()
    local widthBackground = LimitedDailyIncome.salesLimitBox:getWidth() + marginWidth

    local backgroundOverlay = Overlay.new(g_baseUIFilename, posX, posY, widthBackground, gameInfoDisplay:getHeight())
    backgroundOverlay:setUVs(g_colorBgUVs)
	backgroundOverlay:setColor(0, 0, 0, 0.75)

    local backgroundElement = HUDElement.new(backgroundOverlay)
    backgroundElement:addChild(LimitedDailyIncome.salesLimitBox)

    gameInfoDisplay:addChild(backgroundElement)
    LimitedDailyIncome.backgroundElement = backgroundElement
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
	local boxOverlay = Overlay.new(nil, posX, bottomY, boxWidth, boxHeight)
	local boxElement = HUDElement.new(boxOverlay)

    if withIcon then
        posY = bottomY + (boxHeight - iconHeight) * 0.5

        local iconOverlay = Overlay.new(hudAtlasPath, posX + 0.005, posY, iconWidth, iconHeight)

        iconOverlay:setUVs(GuiUtils.getUVs(GameInfoDisplay.UV.MONEY_ICON))
        iconOverlay:setColor(unpack(gameInfoDisplay.COLOR.ICON))
        LimitedDailyIncome.moneyIconOverlay = iconOverlay

        boxElement:addChild(HUDElement.new(iconOverlay))
    end

    return posX, boxElement
end

function LimitedDailyIncome:onOpenConstructionScreen()
    LimitedDailyIncome.backgroundElement:setVisible(false)
end

function LimitedDailyIncome:onCloseConstructionScreen()
    LimitedDailyIncome.backgroundElement:setVisible(true)
end

function LimitedDailyIncome:showErrorDialog(errorMessage)
    g_gui:showInfoDialog({
        text = g_i18n:getText(errorMessage)
    })
end

function LimitedDailyIncome.sendObjects(self,connection)
    for farmId, sales in pairs(LimitedDailyIncome.sales) do
       local salesLimit = LimitedDailyIncome.salesLimit[farmId]
       connection:sendEvent(UpdateDataEvent.new(farmId, sales, salesLimit))
   end
end

function LimitedDailyIncome:addConsoleCommands()
    addConsoleCommand("ldiPrintFarmData", "Prints the sales and salesLimit of the farm", "printDataFromFarm", LimitedDailyIncome)
    addConsoleCommand("ldiPrintAll", "Prints the whole content of sales and salesLimit.", "printAllData", LimitedDailyIncome)
    addConsoleCommand("ldiSetSalesForFarm", "set the current sales of the farm with the farmId to the chosen value", "setSalesForFarm", LimitedDailyIncome)
    addConsoleCommand("ldiSetSalesLimitForFarm", "set the current sales limit of the farm with the farmId to the entered value", "setSalesLimitForFarm", LimitedDailyIncome)
    addConsoleCommand("restartSavegame", "load and start a savegame", "restartSaveGame", LimitedDailyIncome)
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

--[[AnimalScreenDealerFarm.applyTarget = Utils.overwrittenFunction(AnimalScreenDealerFarm.applyTarget, LimitedDailyIncome.applyTargetFarms)
AnimalScreenDealerTrailer.applyTarget = Utils.overwrittenFunction(AnimalScreenDealerTrailer.applyTarget, LimitedDailyIncome.applyTargetTrailer)

SellingStation.getIsFillAllowedFromFarm = Utils.overwrittenFunction(SellingStation.getIsFillAllowedFromFarm, LimitedDailyIncome.getIsFillAllowedFromFarm)
WoodUnloadTrigger.processWood = Utils.overwrittenFunction(WoodUnloadTrigger.processWood, LimitedDailyIncome.processWood)
ProductionPoint.load = Utils.overwrittenFunction(ProductionPoint.load, LimitedDailyIncome.load)
ProductionPoint.directlySellOutputs = Utils.overwrittenFunction(ProductionPoint.directlySellOutputs, LimitedDailyIncome.directlySellOutputs)
]]
ConstructionScreen.onOpen = Utils.appendedFunction(ConstructionScreen.onOpen, LimitedDailyIncome.onOpenConstructionScreen)
ConstructionScreen.onClose = Utils.appendedFunction(ConstructionScreen.onClose, LimitedDailyIncome.onCloseConstructionScreen)

Server.sendObjects = Utils.prependedFunction(Server.sendObjects, LimitedDailyIncome.sendObjects)

BaseMission.loadMapFinished = Utils.appendedFunction(BaseMission.loadMapFinished, LimitedDailyIncome.loadMapFinished)
addModEventListener(LimitedDailyIncome)

if LimitedDailyIncome.isDevelopmentVersion then
    LimitedDailyIncome:addConsoleCommands()
end