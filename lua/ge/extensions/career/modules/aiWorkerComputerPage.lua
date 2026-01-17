local M = {}
local computerFunctions = {} -- used only for AI page
local parentId = nil -- which computer/facility called us?
local aiSelection = { active = false, title = "", rows = {}, onSelect = nil }

-- openSelection creates a UI overlay for selecting from a list (workers, vehicles, etc.)
local function openSelection(title, rows, onSelect)
  print("[aiWorkerComputerPage.lua] openSelection() called with title: " .. tostring(title))
  aiSelection.active = true
  aiSelection.title = title
  aiSelection.rows = rows or {}
  aiSelection.onSelect = function(val)
    print("[aiWorkerComputerPage.lua] openSelection onSelect callback triggered with value: " .. tostring(val))
    aiSelection.active = false
    if onSelect then onSelect(val) end
    -- Reopen the AI worker menu after selection
    M.openAIWorkerPage(parentId)
  end
  -- Trigger menu refresh to show selection UI
  M.openAIWorkerPage(parentId)
end

local function gotoAIWorkerMenu(computerId)
  parentId = computerId
  computerFunctions = {}

  local AIWorkerManager = require("career/modules/AIWorkerManager")
  AIWorkerManager.loadState()

  local iconHire   = "star"
  local iconFire   = "undo"
  local iconAssign = "car"
  local iconRecall = "undo"
  local iconList   = "users"
  local iconListCars = "clipboard"
  local iconBack = "arrow-left"

  -- If we're in selection mode, show selection UI
  if aiSelection.active and aiSelection.rows and #aiSelection.rows > 0 then
    print("[aiWorkerComputerPage.lua] Building selection menu with " .. #aiSelection.rows .. " rows")
    
    -- Back button
    computerFunctions["ai_back"] = {
      id = "ai_back",
      label = "Back",
      icon = iconBack,
      order = 100,
      callback = function()
        print("[aiWorkerComputerPage.lua] Selection back button clicked - clearing selection")
        aiSelection.active = false
        M.openAIWorkerPage(parentId)
      end,
    }
    
    -- Header
    computerFunctions["ai_header"] = {
      id = "ai_header",
      label = aiSelection.title,
      icon = "clipboard",
      order = 101,
      callback = function() end,
    }
    
    -- Selection rows
    for i, row in ipairs(aiSelection.rows) do
      local btnId = "ai_select_"..i
      computerFunctions[btnId] = {
        id = btnId,
        label = row.label,
        icon  = row.icon or "clipboard",
        order = 101 + i,
        callback = function() aiSelection.onSelect(row.value) end
      }
    end
  else
    -- Normal AI worker menu
    
    -- Hire Worker
    computerFunctions["hireAIWorker"] = {
      id = "hireAIWorker",
      label = "Hire Worker",
      icon = iconHire,
      order = 11,
      callback = function()
        local candidates = AIWorkerManager.listPotentialHires()
        local rows = {}
        for _, cand in ipairs(candidates) do
          rows[#rows+1] = {
            label = string.format("%s | Wage: %.0f%% | Skill: %.0f%% | Reliab: %.0f%% | $%d",
              cand.name, cand.wagePercent*100, cand.skill*100, cand.reliability*100, cand.cost),
            value = cand.name,
            icon  = "star"
          }
        end
        openSelection("Choose New Worker to Hire", rows, function(selName)
          if not selName then return end
          local ok, msg = AIWorkerManager.hireWorkerNamed(selName)
          ui_message(msg, 7, "career")
        end)
      end
    }

    -- Fire Worker
    computerFunctions["fireAIWorker"] = {
      id = "fireAIWorker",
      label = "Fire Worker",
      icon = iconFire,
      order = 12,
      callback = function()
        local current = AIWorkerManager.listFirableWorkers()
        if #current == 0 then ui_message("No workers hired.", 6, "career") return end
        local rows = {}
        for _, w in ipairs(current) do
          rows[#rows+1] = {
            label = string.format("%s | Wage %.0f%% | Skill %.0f%% | Reliab %.0f%%",
              w.name, w.wagePercent*100, w.skill*100, w.reliability*100),
            value = w.name,
            icon  = "user"
          }
        end
        openSelection("Select Worker to Fire", rows, function(workerName)
          local ok, msg = AIWorkerManager.fireWorker(workerName)
          ui_message(msg, 9, "career")
        end)
      end
    }

    -- Assign Worker to Vehicle
    computerFunctions["assignAIToVehicle"] = {
      id = "assignAIToVehicle",
      label = "Assign Worker to Vehicle",
      icon = iconAssign,
      order = 13,
      callback = function()
        local ai = AIWorkerManager.listFirableWorkers()
        if #ai == 0 then ui_message("No workers available.", 6, "career") return end
        local assignments = AIWorkerManager.getAssignments()
        local vehicles = {}
        for vid, v in pairs(career_modules_inventory.getVehicles()) do
          if not assignments[vid] then
            vehicles[#vehicles+1] = {id=vid, name=v.niceName or tostring(vid), type=v.type or "car"}
          end
        end
        if #vehicles == 0 then ui_message("No vehicles available.", 6, "career") return end
        local workerRows = {}
        for _, w in ipairs(ai) do
          workerRows[#workerRows+1] = {
            label = string.format("%s | Wage %.0f%% | Skill %.0f%% | Reliab %.0f%%",
              w.name, w.wagePercent*100, w.skill*100, w.reliability*100),
            value = w.name,
            icon  = "user"
          }
        end
        openSelection("Assign Worker", workerRows, function(workerSel)
          local vehRows = {}
          for _, v in ipairs(vehicles) do
            vehRows[#vehRows+1] = {
              label = v.name .. " (" .. v.type .. ")",
              value = v.id,
              icon  = "car"
            }
          end
          openSelection("Assign " .. workerSel .. " to Vehicle", vehRows, function(carSel)
            local vdata = career_modules_inventory.getVehicles()[carSel]
            local ok, msg = AIWorkerManager.assignWorkerToVehicle(workerSel, carSel, (vdata and vdata.type) or "car")
            ui_message(msg, 8, "career")
          end)
        end)
      end
    }

    -- Recall Worker from Vehicle
    computerFunctions["recallAIAssignment"] = {
      id = "recallAIAssignment",
      label = "Recall Worker from Vehicle",
      icon = iconRecall,
      order = 14,
      callback = function()
        local assignments = AIWorkerManager.getAssignments()
        local vids = {}
        for vid, _ in pairs(assignments) do vids[#vids+1]=vid end
        if #vids==0 then ui_message("No AI assignments found.", 8, "career") return end
        local vehRows = {}
        for _, vid in ipairs(vids) do
          local v = career_modules_inventory.getVehicles()[vid]
          local txt = (v and v.niceName or tostring(vid)) .. " (assigned to " .. assignments[vid].worker .. ")"
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
              career_modules_payment.reward({money={amount=math.floor(data.netIncome)}}, {label="AI earnings"})
            end
            ui_message(data.message or "AI assignment ended.", 10, "career")
          else
            ui_message(data or "Could not recall.", 10, "career")
          end
        end)
      end
    }

    -- List All Workers
    computerFunctions["listAIWorkers"] = {
      id = "listAIWorkers",
      label = "List All Workers",
      icon = iconList,
      order = 15,
      callback = function()
        ui_message(AIWorkerManager.listWorkers(), 9, "career")
      end
    }

    -- List AI Assignments
    computerFunctions["listAssignments"] = {
      id = "listAssignments",
      label = "List AI Assignments",
      icon = iconListCars,
      order = 16,
      callback = function()
        ui_message(AIWorkerManager.listVehicleAssignments(career_modules_inventory.getVehicles()), 10, "career")
      end
    }

    -- Back to main computer
    computerFunctions["ai_back"] = {
      id = "ai_back",
      label = "Back to Computer",
      icon = iconBack,
      order = 100,
      callback = function()
        M.goBack()
      end
    }
  end

  -- Actually show the menu (refresh)
  guihooks.trigger("ChangeState", {
    state = "computer",
    extraMenu = true, -- indicate that this is an alternative custom menu
    computerFunctions = {general = computerFunctions, vehicleSpecific = {}},
    facilityName = "Workers Management",
    computerId = parentId or "",
    vehicles = {}, -- Empty vehicles list since this is workers page
  })
end

function M.goBack()
  if career_modules_computer and career_modules_computer.openComputerMenuById then
    career_modules_computer.openComputerMenuById(parentId)
  end
end

function M.openAIWorkerPage(computerId)
  gotoAIWorkerMenu(computerId)
end

return M