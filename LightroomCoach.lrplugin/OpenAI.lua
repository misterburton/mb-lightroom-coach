local LrHttp = import 'LrHttp'
local LrPrefs = import 'LrPrefs'
local LrFunctionContext = import 'LrFunctionContext'
local LrApplication = import 'LrApplication'

local json = require 'JSON'
local OpenAI = {}

-- System prompt that restricts responses to Lightroom-only topics
local SYSTEM_PROMPT = [[You are Lightroom Coach, an AI assistant specialized exclusively in Adobe Lightroom Classic (the desktop application for macOS and Windows). Your purpose is to help users with Lightroom Classic features, editing workflows, and to perform editing actions when requested.

CRITICAL RULES:
- You MUST only respond to Lightroom Classic desktop application questions
- DO NOT provide guidance for Lightroom CC (cloud), Lightroom Mobile, or Lightroom Web
- If asked about other Lightroom versions, clarify: "I'm specialized in Lightroom Classic desktop only. That feature may be available in Lightroom CC or Mobile."
- If asked about topics outside of Lightroom entirely, politely redirect: "I'm specialized in Lightroom Classic. How can I help with your photo editing?"
- When providing editing guidance that can be automated, include a JSON action block in your response

AVAILABLE ACTIONS:
When appropriate, include a JSON block like this:
```json
{
  "action": "apply_develop_settings",
  "params": {
    "exposure": 0.5,
    "contrast": 10,
    "highlights": -20,
    "shadows": 15
  }
}
```

Available develop settings: exposure, contrast, highlights, shadows, whites, blacks, clarity, vibrance, saturation, temperature, tint

Remember: All guidance must be specific to Lightroom Classic desktop (macOS/Windows) only.]]

function OpenAI.ask(question, context)
  local prefs = LrPrefs.prefsForPlugin()
  local apiKey = prefs.openai_api_key or ""
  if apiKey == "" then 
    return { success = false, text = "No API key set. Please configure your OpenAI API key in Plug-in Manager." } 
  end

  -- Build context string
  local contextStr = ""
  if context then
    contextStr = string.format("\n\nCurrent Context:\n- Module: %s\n- Selected Photos: %d", 
      context.module or "Unknown", 
      context.photoCount or 0)
  end

  local body = json.encode({
    model = "gpt-5-mini",
    messages = {
      { role = "system", content = SYSTEM_PROMPT },
      { role = "user", content = question .. contextStr }
    }
  })

  local response, hdrs = LrHttp.post(
    "https://api.openai.com/v1/chat/completions",
    body,
    { 
      { field = "Content-Type", value = "application/json" },
      { field = "Authorization", value = "Bearer " .. apiKey } 
    }
  )

  if not response then
    return { success = false, text = "Network error. Please check your connection." }
  end

  -- Parse response
  local decoded = json.decode(response)
  if not decoded or not decoded.choices or #decoded.choices == 0 then
    return { success = false, text = "Invalid response from OpenAI API." }
  end

  local content = decoded.choices[1].message.content

  return { success = true, text = content }
end

-- Get current Lightroom context
function OpenAI.getContext()
  local catalog = LrApplication.activeCatalog()
  local photos = catalog:getTargetPhotos()
  local moduleName = "Unknown"
  
  -- Try to get current module (may not be available in all SDK versions)
  pcall(function()
    local LrApplicationView = import 'LrApplicationView'
    moduleName = LrApplicationView.getCurrentModuleName() or "Unknown"
  end)

  return {
    module = moduleName,
    photoCount = #photos
  }
end

return OpenAI