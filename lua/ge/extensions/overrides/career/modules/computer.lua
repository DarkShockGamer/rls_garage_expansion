local M = {}

M.dependencies = {"career_career"}

local computerTetherRangeSphere = 4
local computerTetherRangeBox = 1
local tether

local computerFunctions
local computerId
local computerFacilityName
local menuData = {}

local reopenInProgress = false
local function reopenMenu()
	print("[computer.lua] reopenMenu() called - DISABLED to prevent automatic refresh loops")
	-- DISABLED: All automatic menu refresh logic has been disabled.
	-- This function is now a no-op to prevent soft-locking during save game loading.
	-- Menu refreshes should only occur from explicit user button callbacks.
	return
	
	-- OLD CODE (DISABLED):
	-- if reopenInProgress then
	-- 	-- Prevent overlapping/recursive reopenMenu calls
	-- 	return
	-- end
	-- if not computerId then
	-- 	-- Defensive check: if computerId is nil, we cannot reopen the menu
	-- 	return
	-- end
	-- reopenInProgress = true
	-- career_career.closeAllMenus()
	-- extensions.core_jobsystem.create(function(job)
	-- 	job.sleep(0.1)  -- Brief delay to allow UI state to settle
	-- 	-- Double-check computerId is still valid before reopening
	-- 	if computerId then
	-- 		career_modules_computer.openComputerMenuById(computerId)
	-- 	end
	-- 	reopenInProgress = false
	-- end)
end

local function openMenu(computerFacility, resetActiveVehicleIndex, activityElement)
  print("[computer.lua] openMenu() called for facility: " .. tostring(computerFacility and computerFacility.id or "nil"))
  computerFunctions = {general = {}, vehicleSpecific = {}}
  computerId = computerFacility.id
  computerFacilityName = computerFacility.name

  menuData = {vehiclesInGarage = {}, resetActiveVehicleIndex = resetActiveVehicleIndex}
  local inventoryIds = career_modules_inventory.getInventoryIdsInClosestGarage()
  for _, inventoryId in ipairs(inventoryIds) do
    local vehicleData = {}
    vehicleData.inventoryId = inventoryId
    vehicleData.needsRepair = career_modules_insurance_insurance.inventoryVehNeedsRepair(inventoryId) or nil
    local vehicleInfo = career_modules_inventory.getVehicles()[inventoryId]
    vehicleData.vehicleName = vehicleInfo and vehicleInfo.niceName
    vehicleData.dirtyDate = vehicleInfo and vehicleInfo.dirtyDate
    table.insert(menuData.vehiclesInGarage, vehicleData)
    computerFunctions.vehicleSpecific[inventoryId] = {}
    -- No need for lockout logic here! It's all handled in inventory.lua now.
  end

  menuData.computerFacility = computerFacility
  if not career_modules_linearTutorial.getTutorialFlag("partShoppingComplete") then
    menuData.tutorialPartShoppingActive = true
  elseif not career_modules_linearTutorial.getTutorialFlag("tuningComplete") then
    menuData.tutorialTuningActive = true
  end

  extensions.hook("onComputerAddFunctions", menuData, computerFunctions)

  -- Single "Workers" button that opens dedicated AI worker management page
  computerFunctions.general["workersManagement"] = {
    id = "workersManagement",
    label = "Workers",
    icon = "users",
    order = 210,
    callback = function()
      -- Load the AI worker computer page module and open it
      local aiWorkerPage = require("career/modules/aiWorkerComputerPage")
      aiWorkerPage.openAIWorkerPage(computerId)
    end
  }

  local computerPos = freeroam_facilities.getAverageDoorPositionForFacility(computerFacility)
  local door = computerFacility.doors and computerFacility.doors[1]
  tether = nil
  if door then
    tether = career_modules_tether.startDoorTether(door, computerTetherRangeBox, M.closeMenu)
  end
  if not tether and computerPos then
    tether = career_modules_tether.startSphereTether(computerPos, computerTetherRangeSphere, M.closeMenu)
  end

  guihooks.trigger('ChangeState', {state = 'computer'})
  extensions.hook("onComputerMenuOpened")
end

local function computerButtonCallback(buttonId, inventoryId)
  print("[computer.lua] computerButtonCallback() called - buttonId: " .. tostring(buttonId) .. ", inventoryId: " .. tostring(inventoryId))
  local functionData
  if inventoryId then
    functionData = computerFunctions.vehicleSpecific[inventoryId][buttonId]
  else
    functionData = computerFunctions.general[buttonId]
  end
  if functionData and functionData.callback then
    functionData.callback(computerId)
  end
end

local function getComputerUIData()
  print("[computer.lua] getComputerUIData() called")
  local data = {}
  local invVehicles = career_modules_inventory.getVehicles()
  local computerFunctionsForUI = deepcopy(computerFunctions)
  computerFunctionsForUI.vehicleSpecific = {}
  for inventoryId, computerFunction in pairs(computerFunctions.vehicleSpecific) do
    if invVehicles and invVehicles[inventoryId] then
      computerFunctionsForUI.vehicleSpecific[tostring(inventoryId)] = computerFunction
    end
  end
  local vehiclesForUI = {}
  for _, vehicleData in ipairs(menuData.vehiclesInGarage) do
    local invId = vehicleData.inventoryId
    if invVehicles and invVehicles[invId] then
      local vd = deepcopy(vehicleData)
      local thumb = career_modules_inventory.getVehicleThumbnail(invId)
      if thumb then
        vd.thumbnail = thumb .. "?" .. (vd.dirtyDate or "")
      end
      vd.inventoryId = tostring(invId)
      table.insert(vehiclesForUI, vd)
    end
  end
  data.computerFunctions = computerFunctionsForUI
  data.vehicles = vehiclesForUI
  data.facilityName = computerFacilityName
  data.resetActiveVehicleIndex = menuData.resetActiveVehicleIndex
  data.computerId = computerId
  return data
end

local function onMenuClosed()
  print("[computer.lua] onMenuClosed() called")
  if tether then tether.remove = true tether = nil end
end

local function closeMenu()
  print("[computer.lua] closeMenu() called")
  career_career.closeAllMenus()
end

local function openComputerMenuById(id)
  print("[computer.lua] openComputerMenuById() called with id: " .. tostring(id))
  local computer = freeroam_facilities.getFacility("computer", id)
  M.openMenu(computer)
end

M.reasons = {
  tutorialActive = { type = "text", label = "Disabled during tutorial." },
  needsRepair    = { type = "needsRepair", label = "The vehicle needs to be repaired first." }
}

local function getComputerId() return computerId end

M.openMenu = openMenu
M.openComputerMenuById = openComputerMenuById
M.onMenuClosed = onMenuClosed
M.closeMenu = closeMenu
M.getComputerUIData = getComputerUIData
M.computerButtonCallback = computerButtonCallback
M.getComputerId = getComputerId

return M
