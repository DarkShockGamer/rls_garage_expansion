-- Garage Expansions module (RLS add-on, updated for instant refresh & click animation)
-- https://github.com/DarkShockGamer/rls_garage_expansion

local M = {}
M.dependencies = { 'career_career', 'career_saveSystem', 'freeroam_facilities' }

local saveFile = "garageExpansions.json"

-- expansions[garageId] = tier (0..maxTier), stored with string keys
local expansions = {}

local tiers = {
  [1] = { bonusSlots = 2, basePrice = 50000  },
  [2] = { bonusSlots = 3, basePrice = 75000  },
  [3] = { bonusSlots = 5, basePrice = 100000 },
}
local maxTier = 3

local hardcorePriceMultiplier = 1.6

local function getSaveDir(currentSavePath)
  if not currentSavePath then
    local _, path = career_saveSystem.getCurrentSaveSlot()
    currentSavePath = path
  end
  if not currentSavePath then return nil end

  local dirPath = currentSavePath .. "/career/rls_career"
  if not FS:directoryExists(dirPath) then
    FS:directoryCreate(dirPath)
  end
  return dirPath
end

local function loadExpansions(currentSavePath)
  local dirPath = getSaveDir(currentSavePath)
  if not dirPath then return end

  local fullPath = dirPath .. "/" .. saveFile
  if FS:fileExists(fullPath) then
    local data = jsonReadFile(fullPath)
    if data and type(data.expansions) == "table" then
      expansions = data.expansions
      print("Loaded Garage Expansions from: " .. fullPath)
      return
    end
  end
  expansions = {}
end

local function saveExpansions(currentSavePath)
  local dirPath = getSaveDir(currentSavePath)
  if not dirPath then return end
  career_saveSystem.jsonWriteFileSafe(dirPath .. "/" .. saveFile, { expansions = expansions }, true)
  print("Saved Garage Expansions to: " .. dirPath .. "/" .. saveFile)
end

local function onSaveCurrentSaveSlot(currentSavePath)
  saveExpansions(currentSavePath)
end

local function onCareerActivated()
  loadExpansions()
end

local function onExtensionLoaded()
  if career_career and career_career.isActive and career_career.isActive() then
    loadExpansions()
  end
end

local function getExpansionTier(garageId)
  if not garageId then return 0 end
  return tonumber(expansions[tostring(garageId)] or 0) or 0
end

local function getBonusSlotsForTier(tier)
  tier = tonumber(tier or 0) or 0
  local total = 0
  for t = 1, math.min(tier, maxTier) do
    total = total + (tiers[t] and tiers[t].bonusSlots or 0)
  end
  return total
end

local function getBonusSlots(garageId)
  return getBonusSlotsForTier(getExpansionTier(garageId))
end

local function getNextTier(garageId)
  local current = getExpansionTier(garageId)
  if current >= maxTier then return nil end
  return current + 1
end

local function getTierPrice(tier)
  local cfg = tiers[tier]
  if not cfg then return nil end
  local price = cfg.basePrice
  if career_modules_hardcore and career_modules_hardcore.isHardcoreMode and career_modules_hardcore.isHardcoreMode() then
    price = math.floor(price * hardcorePriceMultiplier + 0.5)
  end
  return price
end

local function canAfford(amount)
  if career_modules_cheats and career_modules_cheats.isCheatsMode and career_modules_cheats.isCheatsMode() then
    return true
  end
  if career_modules_playerAttributes and career_modules_playerAttributes.getAttributeValue then
    return career_modules_playerAttributes.getAttributeValue("money") >= amount
  end
  return false
end

local function buyNextExpansionForGarage(garageId)
  if not garageId then return false, "No garage." end

  local nextTier = getNextTier(garageId)
  if not nextTier then
    return false, "Already at max expansion."
  end

  local price = getTierPrice(nextTier)
  if not price then
    return false, "Invalid expansion tier."
  end

  if not canAfford(price) then
    return false, "Not enough money."
  end

  local label = string.format("Purchased Garage Expansion %d", nextTier)
  local payment = { money = { amount = price, canBeNegative = false } }

  local ok = career_modules_payment and career_modules_payment.pay and career_modules_payment.pay(payment, { label = label })
  if not ok then
    return false, "Payment failed."
  end

  expansions[tostring(garageId)] = nextTier
  career_saveSystem.saveCurrent()

  if career_modules_garageManager and career_modules_garageManager.buildGarageSizes then
    career_modules_garageManager.buildGarageSizes()
  end

  return true
end

local function buyNextExpansionFromComputer(computerId)
  if not (career_modules_garageManager and career_modules_garageManager.computerIdToGarageId) then
    return false, "Garage system not ready."
  end
  local garageId = career_modules_garageManager.computerIdToGarageId(computerId)
  if not garageId then return false, "This computer is not linked to a garage." end
  return buyNextExpansionForGarage(garageId)
end

-- Animation helper: pulses the expansion button in UI for feedback
local function pulseExpansionButton()
  if bngApi and bngApi.engineScript then
    bngApi.engineScript([[
      (function(){
        var btn = document.querySelector('.garage-expansion-btn');
        if(btn){
          btn.classList.add('pulse');
          setTimeout(function(){ btn.classList.remove('pulse'); }, 350);
        }
      })();
    ]])
  end
end

-- Injects into the career computer menu
local function onComputerAddFunctions(menuData, computerFunctions)
  if not menuData or not menuData.computerFacility or not computerFunctions then return end

  if not (career_modules_garageManager and career_modules_garageManager.computerIdToGarageId) then return end
  local garageId = career_modules_garageManager.computerIdToGarageId(menuData.computerFacility.id)
  if not garageId then return end

  local owned = career_modules_garageManager.isPurchasedGarage and career_modules_garageManager.isPurchasedGarage(garageId)
  if not owned then
    local g = freeroam_facilities.getFacility("garage", garageId)
    if not (g and g.starterGarage) then
      return
    end
  end

  local currentTier = getExpansionTier(garageId)
  if currentTier >= maxTier then
    computerFunctions.general["garageExpansionMax"] = {
      id = "garageExpansionMax",
      label = "Garage Expansion: MAX",
      callback = function() end,
      order = 60,
      cssClass = "garage-expansion-btn"
    }
    return
  end

  local nextTier = currentTier + 1
  local price = getTierPrice(nextTier) or 0
  local bonus = tiers[nextTier] and tiers[nextTier].bonusSlots or 0

  local label = string.format("Buy Garage Expansion %d (+%d slots) - $%d", nextTier, bonus, price)
  if career_modules_hardcore and career_modules_hardcore.isHardcoreMode and career_modules_hardcore.isHardcoreMode() then
    label = label .. " (Hardcore pricing)"
  end

  computerFunctions.general["buyGarageExpansion"] = {
    id = "buyGarageExpansion",
    label = label,
    callback = function()
      local ok, msg = buyNextExpansionFromComputer(menuData.computerFacility.id)
      pulseExpansionButton()
      if ok then
        ui_message("Garage expansion purchased.", 5, "career")
        -- Refresh computer menu so button text and slots update immediately
        local comp = menuData and menuData.computerFacility
        if comp and career_modules_computer and career_modules_computer.openMenu then
          career_modules_computer.openMenu(comp)
        else
          guihooks.trigger("ChangeState", {state = "computer"})
        end
      else
        ui_message(msg or "Could not purchase expansion.", 5, "career")
      end
    end,
    order = 55,
    cssClass = "garage-expansion-btn"
  }
end

M.onComputerAddFunctions = onComputerAddFunctions
M.onSaveCurrentSaveSlot = onSaveCurrentSaveSlot
M.onCareerActivated = onCareerActivated
M.onExtensionLoaded = onExtensionLoaded

M.getExpansionTier = getExpansionTier
M.getBonusSlots = getBonusSlots
M.getTierPrice = getTierPrice

return M