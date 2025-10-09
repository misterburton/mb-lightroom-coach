--[[----------------------------------------------------------------------------
Actions.lua
Parses and executes develop settings from AI responses

© 2025 misterburton
------------------------------------------------------------------------------]]

local LrApplication = import 'LrApplication'
local LrDialogs = import 'LrDialogs'
local LrTasks = import 'LrTasks'

local JSON = require 'JSON'
local Actions = {}

-- Store last action for undo
local lastAction = nil

-- Extract JSON from text (handles code blocks)
local function extractJSON(text)
  -- Look for JSON in code blocks ```json ... ``` (with newlines)
  local jsonBlock = text:match("```json\n?([^`]+)```")
  if jsonBlock then
    -- Trim whitespace
    jsonBlock = jsonBlock:match("^%s*(.-)%s*$")
    -- Unescape if needed (OpenAI sometimes returns escaped JSON)
    jsonBlock = jsonBlock:gsub('\\"', '"')
    local success, result = pcall(JSON.decode, jsonBlock)
    if success and result then
      return result
    end
  end
  
  -- Look for raw JSON objects (greedy to capture full object)
  local rawJSON = text:match("({.+})")
  if rawJSON then
    -- Unescape if needed
    rawJSON = rawJSON:gsub('\\"', '"')
    local success, result = pcall(JSON.decode, rawJSON)
    if success and result then 
      return result 
    end
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
  tint = "Tint"
}

-- Apply develop settings to selected photos
local function applyDevelopSettings(params)
  local catalog = LrApplication.activeCatalog()
  local photos = catalog:getTargetPhotos()
  
  if #photos == 0 then
    LrDialogs.message("No photos selected", "Please select photos to edit.", "info")
    return false
  end
  
  -- Check if photo is a valid type for develop settings
  local photo = photos[1]
  if photo:getRawMetadata("isVideo") then
    LrDialogs.message("Invalid photo", "Cannot apply develop settings to videos.", "info")
    return false
  end
  
  -- Store original settings for undo
  local originalSettings = {}
  for i, p in ipairs(photos) do
    originalSettings[i] = p:getDevelopSettings()
  end
  
  -- Map friendly names to SDK names
  local mappedParams = {}
  for key, value in pairs(params) do
    local sdkKey = PARAM_MAP[key] or key
    mappedParams[sdkKey] = value
  end
  
  -- Apply each setting individually so they appear as separate history entries
  local success = false
  for sdkKey, value in pairs(mappedParams) do
    catalog:withWriteAccessDo("Lightroom Coach: " .. sdkKey, function()
      for _, p in ipairs(photos) do
        p:applyDevelopSettings({[sdkKey] = value})
        success = true
      end
    end)
  end
  
  if not success then
    LrDialogs.message("Failed", "Could not apply settings to photo.", "critical")
    return false
  end
  
  -- Store for undo
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
  catalog:withWriteAccessDo("Undo Lightroom Coach Settings", function()
    for i, photo in ipairs(lastAction.photos) do
      photo:applyDevelopSettings(lastAction.originalSettings[i])
    end
  end)
  
  lastAction = nil
  LrDialogs.message("Undone", "Previous edits have been reverted.", "info")
end

-- Main action handler - checks for actions in AI response
function Actions.maybePerform(responseText)
  local action = extractJSON(responseText)
  
  if not action or not action.action then
    return nil
  end
  
  if action.action == "apply_develop_settings" and action.params then
    LrTasks.startAsyncTask(function()
      local success = applyDevelopSettings(action.params)
      
      if success then
        -- Build confirmation message
        local settingsStr = ""
        for key, value in pairs(action.params) do
          settingsStr = settingsStr .. string.format("\n- %s: %s", key, tostring(value))
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

