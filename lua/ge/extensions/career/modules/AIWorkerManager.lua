-- AI Worker & Vehicle Assignment System (all-Lua)
-- Saves to: <save>/career/rls_career/aiAssignments.json

local M = {}

local saveFile = "aiAssignments.json"

-- State
local assignments = {} -- { vehicleID -> { worker, startTime, vehicleType, wagePercent, skill, reliability, mileage, wear } }
local workers = {}     -- { workerName -> { wagePercent, skill, reliability } }
local potentialHiresPool = {} -- ephemeral list shown in Hire menu

-- Tunables
local incomeRates = {
  ["semi"]      = 600,
  ["truck"]     = 450,
  ["trailer"]   = 250,
  ["van"]       = 250,
  ["sportscar"] = 200,
  ["coupe"]     = 150,
  ["wagon"]     = 130,
  ["hatchback"] = 110,
  ["sedan"]     = 100,
  ["car"]       = 100,
  ["default"]   = 75
}
local baseWearRate = 0.02          -- 2% wear per hour at skill=0, scales down with skill
local reliabilityThreshold = 0.08  -- breakdown sensitivity factor
local FIRE_COST = 1000             -- cost to fire a worker

-- Persistence helpers
local function getSaveDir()
  local _, path = career_saveSystem.getCurrentSaveSlot()
  if not path then return nil end
  local dirPath = path .. "/career/rls_career"
  if not FS:directoryExists(dirPath) then FS:directoryCreate(dirPath) end
  return dirPath
end

local function loadState()
  local dirPath = getSaveDir()
  local data = dirPath and jsonReadFile(dirPath .. "/" .. saveFile) or {}
  assignments = data.assignments or {}
  workers     = data.workers     or {}
end

local function saveState()
  local dirPath = getSaveDir()
  if dirPath then
    career_saveSystem.jsonWriteFileSafe(dirPath .. "/" .. saveFile, { assignments = assignments, workers = workers }, true)
  end
end

-- Utilities
local function randomWorkerName()
  local names = {"Alex","Jordan","Taylor","Morgan","Casey","Avery","Riley","Quinn","Skyler","Charlie","Harper","Sawyer"}
  return names[math.random(1,#names)] .. " #" .. tostring(math.random(100,999))
end

local function vehicleTypeForIncome(v)
  if not v or not v.type then return "car" end
  local t = v.type:lower()
  for k,_ in pairs(incomeRates) do if t:find(k) then return k end end
  return "car"
end

-- Potential hire generation for the menu
function M.listPotentialHires()
  potentialHiresPool = {}
  for i=1,6 do
    local name = randomWorkerName()
    potentialHiresPool[#potentialHiresPool+1] = {
      name        = name,
      wagePercent = math.random(20,40)/100,  -- 20-40%
      skill       = math.random(60,95)/100,  -- 60-95%
      reliability = math.random(70,97)/100,  -- 70-97%
      cost        = math.random(3000,9000)   -- $3k-$9k upfront
    }
  end
  return potentialHiresPool
end

function M.hireWorkerNamed(name)
  for _,cand in ipairs(potentialHiresPool) do
    if cand.name == name then
      if career_modules_payment and not career_modules_payment.pay({money={amount=cand.cost}}, {label="Hired "..name}) then
        return false, "Not enough money!"
      end
      workers[name] = {
        wagePercent = cand.wagePercent,
        skill       = cand.skill,
        reliability = cand.reliability,
      }
      saveState()
      return true, string.format("%s hired for $%d! Wage: %.0f%%, Skill: %.0f%%, Reliability: %.0f%%",
        name, cand.cost, cand.wagePercent*100, cand.skill*100, cand.reliability*100)
    end
  end
  return false, "Candidate not found."
end

-- Legacy/random hire (still available if needed)
function M.hireWorker(wagePercent, skill, reliability)
  local name = randomWorkerName()
  wagePercent = tonumber(wagePercent) or (math.random(18,40) / 100)
  skill       = tonumber(skill)       or (math.random(50,95)/100)
  reliability = tonumber(reliability) or (math.random(70,97)/100)
  if workers[name] then return false, "Already hired: "..name end
  workers[name] = { wagePercent = wagePercent, skill = skill, reliability = reliability }
  saveState()
  return true, string.format("%s hired! Wage: %.0f%%, Skill: %.0f%%, Reliability: %.0f%%.", name, wagePercent*100, skill*100, reliability*100)
end

function M.fireWorker(name)
  if not workers[name] then return false, "No such worker." end
  if FIRE_COST > 0 and career_modules_payment and not (career_modules_cheats and career_modules_cheats.isCheatsMode()) then
    if not career_modules_payment.pay({money={amount=FIRE_COST}}, {label="Fired "..name}) then
      return false, "Not enough money to fire."
    end
  end
  workers[name] = nil
  saveState()
  return true, name .. " was fired and removed!"
end

function M.listWorkers()
  local summary = {}
  for name, w in pairs(workers) do
    summary[#summary+1] = string.format("%s (Wage: %.0f%%, Skill: %.0f%%, Reliability: %.0f%%)", name, (w.wagePercent or 0)*100, (w.skill or 0)*100, (w.reliability or 0)*100)
  end
  return #summary > 0 and table.concat(summary,"\n") or "No workers hired yet!"
end

function M.listFirableWorkers()
  local list = {}
  for k,v in pairs(workers) do
    list[#list+1] = {name=k, wagePercent=v.wagePercent, skill=v.skill, reliability=v.reliability}
  end
  return list
end

-- Assignment management
function M.getAssignments()
  return assignments
end

function M.assignWorkerToVehicle(workerName, vehicleID, vehicleType)
  if not workers[workerName] then return false, "Worker not hired." end
  if assignments[vehicleID] then return false, "Vehicle already assigned." end
  assignments[vehicleID] = {
    worker      = workerName,
    startTime   = os.time(),
    vehicleType = vehicleType,
    mileage     = 0,
    wear        = 0,
    wagePercent = workers[workerName].wagePercent,
    skill       = workers[workerName].skill,
    reliability = workers[workerName].reliability,
  }
  saveState()
  return true, workerName.." assigned! Vehicle unavailable until recalled."
end

function M.unassignWorkerFromVehicle(vehicleID)
  local data = assignments[vehicleID]
  if not data then return false, "No worker assigned." end

  local elapsedHours = math.max( (os.time() - data.startTime)/3600, 0.001)
  local baseIncome   = incomeRates[data.vehicleType or "default"] or 75
  local grossIncome  = elapsedHours * baseIncome
  local wage         = grossIncome * (data.wagePercent or 0.3)
  local skill        = data.skill or 0.6
  local wear         = baseWearRate * elapsedHours * (1 - skill)
  local mileage      = elapsedHours * 60

  local broken = false
  if math.random() > ((data.reliability or 0.85) - (wear * reliabilityThreshold)) then
    broken = true
  end

  assignments[vehicleID] = nil
  saveState()
  return true, {
    message   = string.format(
      "AI job completed.\nHours: %.1f\nIncome: $%d\nWage to worker: $%d\nVehicle wear: +%.1f%%\nDistance: +%d mi%s",
      elapsedHours, math.floor(grossIncome-wage), math.floor(wage), wear*100, math.floor(mileage), broken and "\n!! Vehicle broke down !!" or ""
    ),
    netIncome = grossIncome - wage,
    wage      = wage,
    wear      = wear,
    mileage   = mileage,
    broken    = broken,
  }
end

function M.listVehicleAssignments(vehicles)
  local out = {}
  for vid, data in pairs(assignments) do
    local vName = (vehicles and vehicles[vid] and vehicles[vid].niceName) or tostring(vid)
    out[#out+1] = string.format("• %s → %s (since %s)", vName, data.worker, os.date("%H:%M", data.startTime))
  end
  return #out>0 and table.concat(out,"\n") or "No vehicles assigned."
end

-- Required exports
M.loadState  = loadState
M.saveState  = saveState
M.hireWorker = M.hireWorker
M.fireWorker = M.fireWorker
M.listWorkers = M.listWorkers
M.listFirableWorkers = M.listFirableWorkers
M.listPotentialHires = M.listPotentialHires
M.hireWorkerNamed = M.hireWorkerNamed
M.assignWorkerToVehicle = M.assignWorkerToVehicle
M.unassignWorkerFromVehicle = M.unassignWorkerFromVehicle
M.getAssignments = M.getAssignments
M.listVehicleAssignments = M.listVehicleAssignments

return M