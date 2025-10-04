local LrApplication = import 'LrApplication'
local LrDialogs = import 'LrDialogs'
local LrTasks = import 'LrTasks'
local LrFunctionContext = import 'LrFunctionContext'

local json = require 'JSON'
local Actions = {}

-- Store the last action for undo
local lastAction = nil

-- Parse JSON from text (handles code blocks)
local function extractJSON(text)
  -- Look for JSON in code blocks ```json ... ```
  local jsonBlock = text:match("```json(.-)```")
  if jsonBlock then
    return json.decode(jsonBlock:match("^%s*(.-)%s*$"))
  end
  
  -- Look for raw JSON objects
  local rawJSON = text:match("{.-}")
  if rawJSON then
    local success, result = pcall(json.decode, rawJSON)
    if success then return result end
  end
  
  return nil
end

-- Apply develop settings to selected photos
local function applyDevelopSettings(params)
  local catalog = LrApplication.activeCatalog()
  local photos = catalog:getTargetPhotos()
  
  if #photos == 0 then
    LrDialogs.message("No photos selected", "Please select photos to edit.", "info")
    return false
  end
  
  -- Store original settings for undo
  local originalSettings = {}
  for i, photo in ipairs(photos) do
    originalSettings[i] = photo:getDevelopSettings()
  end
  
  -- Apply new settings
  catalog:withWriteAccessDo("Apply Lightroom Coach Settings", function()
    for _, photo in ipairs(photos) do
      photo:applyDevelopSettings(params)
    end
  end)
  
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