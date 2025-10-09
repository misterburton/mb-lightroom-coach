--[[----------------------------------------------------------------------------
OpenAI.lua
Handles OpenAI API calls with system prompt and context

© 2025 misterburton
------------------------------------------------------------------------------]]

local LrHttp = import 'LrHttp'
local LrPrefs = import 'LrPrefs'
local LrApplication = import 'LrApplication'

local JSON = require 'JSON'
local OpenAI = {}

-- System prompt restricting responses to Lightroom Classic only
local SYSTEM_PROMPT = [[You are Lightroom Classic Coach. Answer Lightroom questions and execute photo edits.

For EDIT requests (brighten, adjust, enhance, etc.), return ONLY JSON:
{"action":"apply_develop_settings","params":{"exposure":0.5}}

Available params: exposure, contrast, highlights, shadows, whites, blacks, clarity, vibrance, saturation, temperature, tint

For QUESTIONS (How/Where/What), give concise text answers. Only Lightroom Classic topics.]]

-- Get current Lightroom context
function OpenAI.getContext()
  local catalog = LrApplication.activeCatalog()
  local photos = catalog:getTargetPhotos()
  local moduleName = "Unknown"
  
  -- Try to get current module
  pcall(function()
    local LrApplicationView = import 'LrApplicationView'
    moduleName = LrApplicationView.getCurrentModuleName() or "Unknown"
  end)

  return {
    module = moduleName,
    photoCount = #photos
  }
end

-- Send question to OpenAI API
function OpenAI.ask(question, context)
  local prefs = LrPrefs.prefsForPlugin()
  local apiKey = prefs.openai_api_key or ""
  
  if apiKey == "" then 
    return { 
      success = false, 
      text = "No API key set. Please configure your OpenAI API key in Plug-in Manager." 
    } 
  end

  -- Build context string
  local contextStr = ""
  if context then
    contextStr = string.format("\n\nCurrent Context:\n- Module: %s\n- Selected Photos: %d", 
      context.module or "Unknown", 
      context.photoCount or 0)
  end

  -- Build request body
  local body = JSON.encode({
    model = "gpt-5-mini",
    messages = {
      { role = "system", content = SYSTEM_PROMPT },
      { role = "user", content = question .. contextStr }
    }
  })

  -- Make API call
  local response, hdrs = LrHttp.post(
    "https://api.openai.com/v1/chat/completions",
    body,
    { 
      { field = "Content-Type", value = "application/json" },
      { field = "Authorization", value = "Bearer " .. apiKey } 
    }
  )

  if not response then
    return { 
      success = false, 
      text = "Network error. Please check your connection." 
    }
  end

  -- Parse response
  local decoded = JSON.decode(response)
  if not decoded or not decoded.choices or #decoded.choices == 0 then
    -- Try to extract error message
    local errorMsg = "Invalid response from OpenAI API."
    if decoded and decoded.error and decoded.error.message then
      errorMsg = decoded.error.message
    end
    return { 
      success = false, 
      text = errorMsg 
    }
  end

  local content = decoded.choices[1].message.content

  return { 
    success = true, 
    text = content 
  }
end

return OpenAI

