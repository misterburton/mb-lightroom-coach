--[[----------------------------------------------------------------------------
Actions.lua
Parses and executes develop settings from AI responses
------------------------------------------------------------------------------]]

local LrApplication = import 'LrApplication'
local LrDialogs = import 'LrDialogs'
local LrTasks = import 'LrTasks'

local JSON = require 'JSON'
local Actions = {}

-- Store last action for undo
local lastAction = nil

-- Helper to unescape doubled-escaped strings from Gemini 3
local function unescapeJSON(text)
  return text:gsub('\\"', '"'):gsub('\\n', '\n')
end

-- Extract JSON from text
local function extractJSON(text)
  -- 1. Try exact decoding first
  local success, result = pcall(JSON.decode, text)
  if success and result then return result end

  -- 2. Try exact decoding of UNESCAPED text
  local unescaped = unescapeJSON(text)
  success, result = pcall(JSON.decode, unescaped)
  if success and result then return result end

  -- 3. Code Block Strategy
  for jsonBlock in text:gmatch("```json\n?(.-)```") do
    success, result = pcall(JSON.decode, jsonBlock)
    if success and result and result.action then return result end
    
    success, result = pcall(JSON.decode, unescapeJSON(jsonBlock))
    if success and result and result.action then return result end
  end
  
  for jsonBlock in text:gmatch("```\n?(.-)```") do
    success, result = pcall(JSON.decode, jsonBlock)
    if success and result and result.action then return result end
    
    success, result = pcall(JSON.decode, unescapeJSON(jsonBlock))
    if success and result and result.action then return result end
  end
  
  -- 4. Fallback: Greedy match
  local startPos = text:find("{")
  local endPos = nil
  if startPos then
    for i = #text, startPos, -1 do
      if text:sub(i, i) == "}" then
        endPos = i
        break
      end
    end
  end
  
  if startPos and endPos then
    local rawJSON = text:sub(startPos, endPos)
    success, result = pcall(JSON.decode, rawJSON)
    if success and result then return result end
    
    success, result = pcall(JSON.decode, unescapeJSON(rawJSON))
    if success and result then return result end
  end
  
  return nil
end

-- Map friendly param names to Lightroom SDK names
local PARAM_MAP = {
  exposure = "Exposure2012",
  contrast = "Contrast2012",
  highlights = "Highlights2012",
  shadows = "Shadows2012",
  whites = "Whites2012",
  blacks = "Blacks2012",
  clarity = "Clarity2012",
  vibrance = "Vibrance",
  saturation = "Saturation",
  temperature = "Temperature",
  tint = "Tint",
  texture = "Texture",
  dehaze = "Dehaze",
  sharpness = "Sharpness",
  luminanceNoise = "LuminanceSmoothing",
  colorNoise = "ColorNoiseReduction",
  vignetteAmount = "PostCropVignetteAmount",
  grainAmount = "GrainAmount",
  
  -- Tone Curve (Parametric)
  toneCurveHighlights = "ParametricHighlights",
  toneCurveLights = "ParametricLights",
  toneCurveDarks = "ParametricDarks",
  toneCurveShadows = "ParametricShadows",
  
  -- HSL (Hue, Saturation, Luminance) - Examples, these are arrays in SDK usually but simple keys here
  hueRed = "HueAdjustmentRed",
  hueOrange = "HueAdjustmentOrange",
  hueYellow = "HueAdjustmentYellow",
  hueGreen = "HueAdjustmentGreen",
  hueAqua = "HueAdjustmentAqua",
  hueBlue = "HueAdjustmentBlue",
  huePurple = "HueAdjustmentPurple",
  hueMagenta = "HueAdjustmentMagenta",
  
  satRed = "SaturationAdjustmentRed",
  satOrange = "SaturationAdjustmentOrange",
  satYellow = "SaturationAdjustmentYellow",
  satGreen = "SaturationAdjustmentGreen",
  satAqua = "SaturationAdjustmentAqua",
  satBlue = "SaturationAdjustmentBlue",
  satPurple = "SaturationAdjustmentPurple",
  satMagenta = "SaturationAdjustmentMagenta",
  
  lumRed = "LuminanceAdjustmentRed",
  lumOrange = "LuminanceAdjustmentOrange",
  lumYellow = "LuminanceAdjustmentYellow",
  lumGreen = "LuminanceAdjustmentGreen",
  lumAqua = "LuminanceAdjustmentAqua",
  lumBlue = "LuminanceAdjustmentBlue",
  lumPurple = "LuminanceAdjustmentPurple",
  lumMagenta = "LuminanceAdjustmentMagenta",
}

-- Human-readable names for history steps
local HISTORY_NAMES = {
  Exposure2012 = "Exposure",
  Contrast2012 = "Contrast",
  Highlights2012 = "Highlights",
  Shadows2012 = "Shadows",
  Whites2012 = "Whites",
  Blacks2012 = "Blacks",
  Clarity2012 = "Clarity",
  Vibrance = "Vibrance",
  Saturation = "Saturation",
  Temperature = "Temperature",
  Tint = "Tint",
  Texture = "Texture",
  Dehaze = "Dehaze",
  PostCropVignetteAmount = "Vignette",
  ParametricHighlights = "Tone Curve (Highlights)",
  ParametricLights = "Tone Curve (Lights)",
  ParametricDarks = "Tone Curve (Darks)",
  ParametricShadows = "Tone Curve (Shadows)"
}

-- Apply develop settings to selected photos
local function applyDevelopSettings(params)
  local catalog = LrApplication.activeCatalog()
  local photos = catalog:getTargetPhotos()
  
  if #photos == 0 then
    LrDialogs.message("No photos selected", "Please select photos to edit.", "info")
    return false
  end
  
  local photo = photos[1]
  if photo:getRawMetadata("isVideo") then
    LrDialogs.message("Invalid photo", "Cannot apply develop settings to videos.", "info")
    return false
  end
  
  local originalSettings = {}
  for i, p in ipairs(photos) do
    originalSettings[i] = p:getDevelopSettings()
  end
  
  local mappedParams = {}
  for key, value in pairs(params) do
    -- Attempt to find exact SDK name first, then try lowercase/camelCase matching from our map
    local sdkKey = PARAM_MAP[key] 
    if not sdkKey then
        -- Try to match typical variations if exact match fails
        -- e.g., "CropTop" might come in, but we need "CropTop" (SDK is case sensitive sometimes depending on context)
        -- The most robust way is to use the map. If not in map, we pass it through as-is (risky but flexible).
        sdkKey = key
    end
    mappedParams[sdkKey] = value
  end
  
  local success = false
  
  -- Group updates into a single undoable action per setting to avoid "Camera Raw Settings" generic history
  -- OR group all into ONE history step named "AI Coach Auto-Fix"
  -- The user requested avoiding generic "Camera Raw Settings". 
  -- We can name the transaction.
  
  catalog:withWriteAccessDo("AI Coach Auto-Fix", function()
    for _, p in ipairs(photos) do
      p:applyDevelopSettings(mappedParams)
      success = true
    end
  end)
  
  if not success then
    LrDialogs.message("Failed", "Could not apply settings to photo.", "critical")
    return false
  end
  
  lastAction = {
    photos = photos,
    originalSettings = originalSettings
  }
  
  return true
end

-- Undo last action
function Actions.undo()
  if not lastAction then
    LrDialogs.message("Nothing to undo", "No recent actions to undo.", "info")
    return
  end
  
  local catalog = LrApplication.activeCatalog()
  catalog:withWriteAccessDo("Undo AI Coach Settings", function()
    for i, photo in ipairs(lastAction.photos) do
      photo:applyDevelopSettings(lastAction.originalSettings[i])
    end
  end)
  
  lastAction = nil
  LrDialogs.message("Undone", "Previous edits have been reverted.", "info")
end

-- Main action handler
function Actions.maybePerform(responseText)
  local action = extractJSON(responseText)
  
  if not action or not action.action then
    return nil
  end
  
  if action.action == "apply_develop_settings" and action.params then
    LrTasks.startAsyncTask(function()
      local success = applyDevelopSettings(action.params)
      
      if success then
        -- Build confirmation message with nice names
        local settingsStr = ""
        for key, value in pairs(action.params) do
          -- Try to get a nice name
          local sdkKey = PARAM_MAP[key] or key
          local niceName = HISTORY_NAMES[sdkKey] or key
          settingsStr = settingsStr .. string.format("\n- %s: %s", niceName, tostring(value))
        end
        
        local result = LrDialogs.confirm(
          "Edits Applied",
          string.format("Applied the following settings:%s\n\nThese changes are logged in your history panel.", settingsStr),
          "Keep Changes",
          "Undo"
        )
        
        if result == "cancel" then
          Actions.undo()
        end
      end
    end)
    
    return true
  end
  
  return nil
end

return Actions
