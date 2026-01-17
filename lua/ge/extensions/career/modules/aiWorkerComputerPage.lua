local M = {}
local computerFunctions = {} -- used only for AI page; you can expand/remove as needed
local parentId = nil -- which computer/facility called us?

local function gotoAIWorkerMenu(computerId)
  parentId = computerId
  computerFunctions = {}

  local AIWorkerManager = require("career/modules/AIWorkerManager")
  AIWorkerManager.loadState()

  local iconHire   = "user-plus"
  local iconFire   = "user-minus"
  local iconAssign = "user-cog"
  local iconList   = "users"
  local iconListCars = "car-side"
  local iconBack = "arrow-left"

  -- Hire
  computerFunctions["hireAIWorker"] = {
    id = "hireAIWorker",
    label = "Hire AI Worker (random)",
    icon = iconHire,
    order = 11,
    callback = function()
      local ok,msg = AIWorkerManager.hireWorker()
      ui_message(msg, 7, "career")
    end
  }

  -- Fire (random)
  computerFunctions["fireAIWorker"] = {
    id = "fireAIWorker",
    label = "Fire AI Worker (random)",
    icon = iconFire,
    order = 12,
    callback = function()
      local curr = AIWorkerManager.listFirableWorkers()
      if #curr == 0 then ui_message("No workers hired!",7,"career") return end
      local fired = curr[math.random(1,#curr)].name
      local ok,msg = AIWorkerManager.fireWorker(fired)
      ui_message(msg,7,"career")
    end
  }

  -- Assign (random)
  computerFunctions["assignAIToVehicle"] = {
    id = "assignAIToVehicle",
    label = "Assign AI to Vehicle (random)",
    icon = iconAssign,
    order = 13,
    callback = function()
      local as = AIWorkerManager.getAssignments()
      local workers = AIWorkerManager.listFirableWorkers()
      if #workers == 0 then ui_message("No workers!",7,"career") return end
      local vehicles = {}
      for vid, v in pairs(career_modules_inventory.getVehicles()) do
        if not as[vid] then
          table.insert(vehicles, vid)
        end
      end
      if #vehicles == 0 then ui_message("No vehicles!",7,"career") return end
      local worker = workers[math.random(1,#workers)].name
      local vid = vehicles[math.random(1,#vehicles)]
      local v = career_modules_inventory.getVehicles()[vid]
      local ok,msg = AIWorkerManager.assignWorkerToVehicle(worker, vid, v.type or "car")
      ui_message(msg,7,"career")
    end
  }

  -- List AIs
  computerFunctions["listAIWorkers"] = {
    id = "listAIWorkers",
    label = "List Hired AI Workers",
    icon = iconList,
    order = 14,
    callback = function()
      ui_message(AIWorkerManager.listWorkers(), 7, "career")
    end
  }

  -- List assignments
  computerFunctions["listAssignments"] = {
    id = "listAssignments",
    label = "List AI Assignments",
    icon = iconListCars,
    order = 15,
    callback = function()
      ui_message(AIWorkerManager.listVehicleAssignments(career_modules_inventory.getVehicles()), 7, "career")
    end
  }

  -- Back to main computer
  computerFunctions["ai_back"] = {
    id = "ai_back",
    label = "Back",
    icon = iconBack,
    order = 100,
    callback = function()
      aiWorkerComputerPage.goBack()
    end
  }

  -- Actually show the menu (refresh)
  guihooks.trigger("ChangeState", {
    state = "computer",
    extraMenu = true, -- indicate that this is an alternative custom menu - optional
    computerFunctions = computerFunctions,
    facilityName = "AI Worker Management", -- appears as menu heading
    computerId = parentId or "",
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