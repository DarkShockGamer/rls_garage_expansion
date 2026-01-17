local M = {}

M.dependencies = {"career_career"}

local computerTetherRangeSphere = 4
local computerTetherRangeBox = 1
local tether

local computerFunctions
local computerId
local computerFacilityName
local menuData = {}
local aiSelection = { active = false, title = "", rows = {}, onSelect = nil }

-- DISABLED: Automatic menu reopening removed to prevent soft-locks on save load.
-- Menu refreshes now only happen in response to explicit user button clicks.
-- Defensive menu reopening: only reopen if computerId is valid and not already in a reopen cycle.
-- This prevents infinite loops and ensures the menu only refreshes in response to user actions.
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

-- openSelection creates a UI overlay for selecting from a list (workers, vehicles, etc.)
-- The onSelect callback is wrapped to clear the selection state.
-- DISABLED automatic reopenMenu() call to prevent refresh loops during save load.
local function openSelection(title, rows, onSelect)
  print("[computer.lua] openSelection() called with title: " .. tostring(title))
  aiSelection.active = true
  aiSelection.title = title
  aiSelection.rows = rows or {}
  aiSelection.onSelect = function(val)
    print("[computer.lua] openSelection onSelect callback triggered with value: " .. tostring(val))
    aiSelection.active = false
    if onSelect then onSelect(val) end
    -- DISABLED: Automatic menu reopen removed to prevent soft-locks
    -- reopenMenu()
  end
end

local function openMenu(computerFacility, resetActiveVehicleIndex, activityElement)
  print("[computer.lua] openMenu() called for facility: " .. tostring(computerFacility and computerFacility.id or "nil"))
  computerFunctions = {general = {}, vehicleSpecific = {}}
  computerId = computerFacility.id
  computerFacilityName = computerFacility.name

  -- Load AIWorkerManager inside function scope to avoid circular dependencies
  -- This ensures the module is only required when the menu is actually opened
  local AIWorkerManager = require("career/modules/AIWorkerManager")
  AIWorkerManager.loadState()

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

  computerFunctions.general["hireAIWorker"] = {
    id = "hireAIWorker",
    label = "Hire Worker",
    icon = "star",
    order = 211,
    callback = function()
      local candidates = AIWorkerManager.listPotentialHires()
      local rows = {}
      for _,cand in ipairs(candidates) do
        rows[#rows+1] = {
          label = string.format("%s | Wage: %.0f%% | Skill: %.0f%% | Reliab: %.0f%% | $%d",
            cand.name, cand.wagePercent*100, cand.skill*100, cand.reliability*100, cand.cost),
          value = cand.name,
          icon  = "star"
        }
      end
      openSelection("Choose New Worker to Hire", rows, function(selName)
        if not selName then return end
        local ok,msg = AIWorkerManager.hireWorkerNamed(selName)
        ui_message(msg, 7, "career")
        -- Menu will be reopened by openSelection's onSelect wrapper
      end)
    end
  }

  computerFunctions.general["fireAIWorker"] = {
    id = "fireAIWorker",
    label = "Fire Worker",
    icon = "undo",
    order = 212,
    callback = function()
      local current = AIWorkerManager.listFirableWorkers()
      if #current == 0 then ui_message("No workers hired.",6,"career") return end
      local rows = {}
      for _,w in ipairs(current) do
        rows[#rows+1] = {
          label = string.format("%s | Wage %.0f%% | Skill %.0f%% | Reliab %.0f%%",
                  w.name, w.wagePercent*100, w.skill*100, w.reliability*100),
          value = w.name,
          icon  = "user"
        }
      end
      openSelection("Select Worker to Fire", rows, function(workerName)
        local ok,msg = AIWorkerManager.fireWorker(workerName)
        ui_message(msg,9,"career")
        -- Menu will be reopened by openSelection's onSelect wrapper
      end)
    end
  }

  computerFunctions.general["assignAIToVehicle"] = {
    id = "assignAIToVehicle",
    label = "Assign Worker to Vehicle",
    icon = "car",
    order = 213,
    callback = function()
      local ai = AIWorkerManager.listFirableWorkers()
      if #ai == 0 then ui_message("No workers available.",6,"career") return end
      local assignments = AIWorkerManager.getAssignments()
      local vehicles = {}
      for vid, v in pairs(career_modules_inventory.getVehicles()) do
        if not assignments[vid] then
          vehicles[#vehicles+1] = {id=vid, name=v.niceName or tostring(vid), type=v.type or "car"}
        end
      end
      if #vehicles == 0 then ui_message("No vehicles available.",6,"career") return end
      local workerRows = {}
      for _,w in ipairs(ai) do
        workerRows[#workerRows+1] = {
          label = string.format("%s | Wage %.0f%% | Skill %.0f%% | Reliab %.0f%%",
                  w.name, w.wagePercent*100, w.skill*100, w.reliability*100),
          value = w.name,
          icon  = "user"
        }
      end
      openSelection("Assign Worker", workerRows, function(workerSel)
        local vehRows = {}
        for _,v in ipairs(vehicles) do
          vehRows[#vehRows+1] = {
            label = v.name .. " ("..v.type..")",
            value = v.id,
            icon  = "car"
          }
        end
        openSelection("Assign "..workerSel.." to Vehicle", vehRows, function(carSel)
          local vdata = career_modules_inventory.getVehicles()[carSel]
          local ok,msg = AIWorkerManager.assignWorkerToVehicle(workerSel, carSel, (vdata and vdata.type) or "car")
          ui_message(msg,8,"career")
          -- Menu will be reopened by openSelection's onSelect wrapper
        end)
      end)
    end
  }

  computerFunctions.general["recallAIAssignment"] = {
    id = "recallAIAssignment",
    label = "Recall Worker from Vehicle",
    icon = "undo",
    order = 214,
    callback = function()
      local assignments = AIWorkerManager.getAssignments()
      local vids = {}
      for vid,_ in pairs(assignments) do vids[#vids+1]=vid end
      if #vids==0 then ui_message("No AI assignments found.",8,"career") return end
      local vehRows = {}
      for _,vid in ipairs(vids) do
        local v = career_modules_inventory.getVehicles()[vid]
        local txt = (v and v.niceName or tostring(vid)).." (assigned to "..assignments[vid].worker..")"
        vehRows[#vehRows+1] = {
          label = txt,
          value = vid,
          icon = "car"
        }
      end
      openSelection("Recall Assignment", vehRows, function(vid)
        local ok, data = AIWorkerManager.unassignWorkerFromVehicle(vid)
        if ok then
          if data.netIncome and career_modules_payment then
            career_modules_payment.reward({money={amount=math.floor(data.netIncome)}},{label="AI earnings"})
          end
          ui_message(data.message or "AI assignment ended.",10,"career")
        else
          ui_message(data or "Could not recall.",10,"career")
        end
        -- Menu will be reopened by openSelection's onSelect wrapper
      end)
    end
  }

  computerFunctions.general["listAIWorkers"] = {
    id = "listAIWorkers",
    label = "List All Workers",
    icon = "users",
    order = 215,
    callback = function()
      ui_message(AIWorkerManager.listWorkers(), 9, "career")
    end
  }

  computerFunctions.general["listAssignments"] = {
    id = "listAssignments",
    label = "List AI Assignments",
    icon = "clipboard",
    order = 216,
    callback = function()
      ui_message(AIWorkerManager.listVehicleAssignments(career_modules_inventory.getVehicles()), 10, "career")
    end
  }

  if aiSelection.active and aiSelection.rows and #aiSelection.rows > 0 then
    print("[computer.lua] openMenu() - Building AI selection menu with " .. #aiSelection.rows .. " rows")
    computerFunctions.general["ai_back"] = {
      id = "ai_back",
      label = "Back",
      icon = "arrow-left",
      order = 100,
      callback = function()
        print("[computer.lua] AI back button clicked - clearing selection")
        aiSelection.active = false
        -- DISABLED: Automatic menu reopen removed to prevent soft-locks
        -- reopenMenu()
      end,
    }
    computerFunctions.general["ai_header"] = {
      id = "ai_header",
      label = aiSelection.title,
      icon = "clipboard",
      order = 101,
      callback = function() end,
    }
    for i,row in ipairs(aiSelection.rows) do
      local btnId = "ai_select_"..i
      computerFunctions.general[btnId] = {
        id = btnId,
        label = row.label,
        icon  = row.icon or "clipboard",
        order = 101 + i,
        callback = function() aiSelection.onSelect(row.value) end
      }
    end
  end

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
