--[[----------------------------------------------------------------------------
Gemini.lua
Handles Google Gemini API calls with system prompt and context

© 2025 misterburton
------------------------------------------------------------------------------]]

local LrHttp = import 'LrHttp'
local LrPrefs = import 'LrPrefs'
local LrApplication = import 'LrApplication'

local JSON = require 'JSON'
local Gemini = {}

-- System prompt restricting responses to Lightroom Classic only
local SYSTEM_PROMPT = [[You are Lightroom Classic Coach. Answer Lightroom questions and execute photo edits.

For EDIT requests (brighten, adjust, enhance, etc.), return ONLY JSON:
{"action":"apply_develop_settings","params":{"exposure":0.5}}

Available params: exposure, contrast, highlights, shadows, whites, blacks, clarity, vibrance, saturation, temperature, tint

For QUESTIONS (How/Where/What), give concise text answers. Only Lightroom Classic topics.]]

-- Get current Lightroom context
function Gemini.getContext()
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

-- Send message history to Gemini API
function Gemini.ask(history, context)
  local prefs = LrPrefs.prefsForPlugin()
  local apiKey = prefs.gemini_api_key or ""
  
  if apiKey == "" then 
    return { 
      success = false, 
      text = "No API key set. Please configure your Gemini API key in Plug-in Manager." 
    } 
  end

  -- Build context string (only append to the last user message or system prompt)
  local contextStr = ""
  if context then
    contextStr = string.format("\n\nCurrent Context:\n- Module: %s\n- Selected Photos: %d", 
      context.module or "Unknown", 
      context.photoCount or 0)
  end

  -- Convert chat history to Gemini 'contents' format
  local contents = {}
  for i, msg in ipairs(history) do
    local text = msg.text
    -- Append context only to the latest user message
    if i == #history and msg.role == "user" then
      text = text .. contextStr
    end
    
    table.insert(contents, {
      role = msg.role == "assistant" and "model" or "user",
      parts = {
        { text = text }
      }
    })
  end

  -- Build request body for Gemini
  local body = JSON.encode({
    systemInstruction = {
      parts = {
        { text = SYSTEM_PROMPT }
      }
    },
    contents = contents,
    generationConfig = {
      temperature = 0.7,
      maxOutputTokens = 1000,
    }
  })

  -- Make API call to Gemini 3 Pro Preview
  local response, hdrs = LrHttp.post(
    "https://generativelanguage.googleapis.com/v1beta/models/gemini-3-pro-preview:generateContent",
    body,
    { 
      { field = "Content-Type", value = "application/json" },
      { field = "x-goog-api-key", value = apiKey } 
    }
  )

  if not response then
    return { 
      success = false, 
      text = "Network error. Please check your connection." 
    }
  end

  -- Parse response
  local success, decoded = pcall(JSON.decode, response)
  
  -- Error handling for Gemini format
  if not success or not decoded then
    return { 
      success = false, 
      text = "Invalid JSON response from Gemini API." 
    }
  end
  if decoded and decoded.error then
    return { 
      success = false, 
      text = "Gemini API Error: " .. (decoded.error.message or "Unknown error")
    }
  end

  if not decoded or not decoded.candidates or #decoded.candidates == 0 then
    return { 
      success = false, 
      text = "Invalid response from Gemini API." 
    }
  end

  -- Extract text from Gemini candidate
  local content = ""
  local candidate = decoded.candidates[1]
  if candidate.content and candidate.content.parts then
    for _, part in ipairs(candidate.content.parts) do
      content = content .. (part.text or "")
    end
  end

  return { 
    success = true, 
    text = content 
  }
end

return Gemini
