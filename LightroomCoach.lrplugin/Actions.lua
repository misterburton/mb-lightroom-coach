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

  -- 3. Robust Code Block Strategy
  -- Look for specific JSON delimiters that contain our expected "action" key
  -- This avoids greedy matching of unrelated curly braces
  
  -- Pattern: Find { ... "action" ... } 
  -- We iterate through all potential JSON blocks found by matching balanced braces (conceptually)
  -- Lua doesn't support recursive patterns for balanced braces, so we use a heuristic approach
  -- finding the first '{' and trying to parse incrementally larger chunks is safer than greedy regex.
  
  local function findJsonCandidates(str)
    local candidates = {}
    local pos = 1
    while true do
      local startP = string.find(str, "{", pos)
      if not startP then break end
      
      -- Optimization: Only look if it looks like it might contain our keywords nearby
      -- (optional, but good for speed on large texts)
      
      -- Try to find the matching closing brace by counting nesting
      local balance = 0
      local endP = nil
      for i = startP, #str do
        local char = string.sub(str, i, i)
        if char == "{" then
          balance = balance + 1
        elseif char == "}" then
          balance = balance - 1
          if balance == 0 then
            endP = i
            break
          end
        end
      end
      
      if endP then
        table.insert(candidates, string.sub(str, startP, endP))
        pos = startP + 1 -- Advance just past the opening brace to find nested or subsequent objects
      else
        pos = startP + 1 -- Unmatched brace, move on
      end
    end
    return candidates
  end

  local candidates = findJsonCandidates(text)
  for _, candidate in ipairs(candidates) do
    -- Try raw
    local success, result = pcall(JSON.decode, candidate)
    if success and result and result.action then return result end
    
    -- Try unescaped
    success, result = pcall(JSON.decode, unescapeJSON(candidate))
    if success and result and result.action then return result end
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

-- SMURF GUARD 2.0: The "Bridge" Function
-- Centralized Logic to sanitize temperature values
local function sanitizeTemperature(photo, aiValue)
  if not aiValue then return nil end
  
  local currentSettings = photo:getDevelopSettings()
  local currentTemp = currentSettings["Temperature"]
  
  -- If we can't read current temp, safe fallback is to do nothing or pass raw
  if not currentTemp then return aiValue end
  
  -- Check: Is photo in Kelvin mode (>2000) but AI sent a weird value?
  if currentTemp > 2000 then
     local applyVal = aiValue
     
     -- CASE 1: Small Slider Value (e.g., +10, -20)
     -- Logic: Treat as relative shift (1 unit = 20 Kelvin)
     if math.abs(aiValue) <= 100 then
         applyVal = currentTemp + (aiValue * 20)
         
     -- CASE 2: Large Negative Value (e.g., -5000)
     -- Logic: Treat as "Subtract this much Kelvin" (AI meant "make it -5000 cooler")
     elseif aiValue < -100 then
         -- AI sent -5000. We subtract 5000 from current.
         -- Wait, if AI sent -5000, adding it IS subtracting.
         applyVal = currentTemp + aiValue 
     
     -- CASE 3: Large Positive Value (e.g. 5500)
     -- Logic: Valid Kelvin. Use as is.
     else
         applyVal = aiValue
     end
     
     -- FINAL SAFETY CLAMP
     -- Lightroom Kelvin range is generally 2000 to 50000
     if applyVal < 2000 then applyVal = 2000 end
     if applyVal > 50000 then applyVal = 50000 end
     
     return applyVal
  end
  
  -- Fallback for non-Kelvin (JPEG/TIFF slider mode)
  -- Just clamp to slider limits (-100 to 100)
  local sliderVal = aiValue
  if sliderVal < -100 then sliderVal = -100 end
  if sliderVal > 100 then sliderVal = 100 end
  return sliderVal
end

-- TINT GUARD
-- Centralized Logic to sanitize tint values
local function sanitizeTint(photo, aiValue)
    if not aiValue then return nil end
    
    -- Tint is generally -150 to +150 in Lightroom SDK 
    -- However, let's be safe and clamp to this range.
    -- AI might send generic slider values (-100 to 100).
    
    local safeTint = aiValue
    
    -- Safety Clamp
    if safeTint < -150 then safeTint = -150 end
    if safeTint > 150 then safeTint = 150 end
    
    return safeTint
end


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
  
  -- Group updates into logical sequence for history
  -- Order matters for history readability: Crop -> Basics -> Tone -> Color -> Details -> Effects
  local ORDERED_KEYS = {
    -- Basics
    "Exposure2012", "Contrast2012", 
    "Highlights2012", "Shadows2012", "Whites2012", "Blacks2012",
    -- Presence
    "Clarity2012", "Dehaze", "Vibrance", "Saturation", "Texture",
    -- Tone Curve
    "ParametricHighlights", "ParametricLights", "ParametricDarks", "ParametricShadows",
    -- Effects
    "PostCropVignetteAmount", "GrainAmount", "Sharpening", "LuminanceSmoothing", "ColorNoiseReduction"
  }

  -- Create a set for quick lookup of processed keys
  local processed = {}

  -- Apply ordered settings individually to create distinct history steps
  for _, key in ipairs(ORDERED_KEYS) do
    if mappedParams[key] then
      local val = mappedParams[key]
      local niceName = HISTORY_NAMES[key] or key
      
      -- Each setting gets its own transaction for history visibility
      catalog:withWriteAccessDo("AI Coach: " .. niceName, function()
        for _, p in ipairs(photos) do
          -- Use centralized sanitizer for Temperature 
          if key == "Temperature" then
             val = sanitizeTemperature(p, val)
          elseif key == "Tint" then
             val = sanitizeTint(p, val)
          end
          p:applyDevelopSettings({ [key] = val })
        end
      end)
      
      processed[key] = true
      success = true
    end
  end

  -- Apply remaining settings (if any were missed in the ordered list)
  for key, val in pairs(mappedParams) do
    if not processed[key] then
       local niceName = HISTORY_NAMES[key] or key
       catalog:withWriteAccessDo("AI Coach: " .. niceName, function()
         for _, p in ipairs(photos) do
            local finalVal = val
            if key == "Temperature" then
                finalVal = sanitizeTemperature(p, val)
            elseif key == "Tint" then
                finalVal = sanitizeTint(p, val)
            end
            p:applyDevelopSettings({ [key] = finalVal })
         end
       end)
       success = true
    end
  end
  
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
  
  -- Normalizing action name check to handle "applydevelopsettings" vs "apply_develop_settings"
  local actionName = action.action:lower():gsub("_", "")
  if actionName == "applydevelopsettings" and action.params then
    LrTasks.startAsyncTask(function()
      local success = applyDevelopSettings(action.params)
      
      if success then
        -- Build confirmation message with nice names
        local settingsStr = ""
        for key, value in pairs(action.params) do
          -- Try to get a nice name
          local sdkKey = PARAM_MAP[key] or key
          local niceName = HISTORY_NAMES[sdkKey] or key
          
          -- If it was Temperature, we might have changed it, but we show what the AI *intended*
          -- or should we show the *actual* applied value? 
          -- We can't easily get the actual applied value back here without re-reading.
          -- Let's just show the intent.
          settingsStr = settingsStr .. string.format("\n- %s: %s", niceName, tostring(value))
        end
        
        local result = LrDialogs.confirm(
          "Edits Applied",
          string.format("Applied the following settings:%s\n\nTIP: Open your History panel and roll over each step to see how these edits work together to create the final look.", settingsStr),
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