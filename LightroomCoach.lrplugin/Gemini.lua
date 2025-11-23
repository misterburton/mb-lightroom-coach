--[[----------------------------------------------------------------------------
Gemini.lua
Handles Google Gemini API calls with system prompt and context

© 2025 misterburton
------------------------------------------------------------------------------]]

local LrHttp = import 'LrHttp'
local LrPrefs = import 'LrPrefs'
local LrApplication = import 'LrApplication'
local LrTasks = import 'LrTasks'

local JSON = require 'JSON'

-- Inline Base64 Encoder for maximum compatibility
-- Prevents "Could not load toolkit script" errors with external files
local function base64Encode(data)
    if not data then return "" end
    
    local b64chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
    local b64 = {}
    local len = #data
    local k = 1
    
    local function charAt(str, i)
        return str:sub(i, i)
    end
    
    while k <= len do
        local b1 = string.byte(data, k)
        k = k + 1
        
        local b2 = nil
        if k <= len then
            b2 = string.byte(data, k)
            k = k + 1
        end
        
        local b3 = nil
        if k <= len then
            b3 = string.byte(data, k)
            k = k + 1
        end
        
        local sixBit1 = math.floor(b1 / 4)
        
        local sixBit2 = (b1 % 4) * 16
        if b2 then
            sixBit2 = sixBit2 + math.floor(b2 / 16)
        end
        
        local sixBit3 = 0
        if b2 then
            sixBit3 = (b2 % 16) * 4
            if b3 then
                sixBit3 = sixBit3 + math.floor(b3 / 64)
            end
        end
        
        local sixBit4 = 0
        if b3 then
            sixBit4 = b3 % 64
        end
        
        table.insert(b64, charAt(b64chars, sixBit1 + 1))
        table.insert(b64, charAt(b64chars, sixBit2 + 1))
        
        if b2 then
            table.insert(b64, charAt(b64chars, sixBit3 + 1))
        else
            table.insert(b64, "=")
        end
        
        if b3 then
            table.insert(b64, charAt(b64chars, sixBit4 + 1))
        else
            table.insert(b64, "=")
        end
    end
    
    return table.concat(b64)
end

local Gemini = {}

-- System prompt restricting responses to Lightroom Classic only
local SYSTEM_PROMPT = [[You are Lightroom Classic Coach, an expert photo editor.
Your goal is to help users achieve professional results in Adobe Lightroom Classic.

For EDIT requests (brighten, fix lighting, make it pop), return a JSON object to apply settings:
{"action":"apply_develop_settings","params":{"exposure":0.5,"contrast":10}}

Supported params: exposure, contrast, highlights, shadows, whites, blacks, clarity, vibrance, saturation, texture, dehaze, temperature, tint, sharpness, luminanceNoise.

For QUESTIONS, provide concise, expert answers about Lightroom Classic workflow and tools.]]

local VISION_SYSTEM_PROMPT = [[Analyze this photo and provide a professional editing guide for Adobe Lightroom Classic.

Role: You are a high-end professional photo editor and Lightroom expert. Your goal is to maximize the visual impact of the image while maintaining a professional, realistic aesthetic.

FORMATTING INSTRUCTIONS:
Since you can only output plain text, you MUST use Unicode and ASCII characters to create a beautiful, structured layout.
1. Use heavy separators (e.g. "══════════════════════════════") for main sections.
2. Use light separators (e.g. "──────────────────────────────") for subsections.
3. Use icons for visual interest (e.g. 📸, 🛠, 1️⃣, •).
4. Use "Math Sans Bold" unicode characters for ALL headers (e.g. 𝐀𝐍𝐀𝐋𝐘𝐒𝐈𝐒 instead of ANALYSIS).
5. Use "Math Sans Bold" unicode characters for Parameter + Value pairs AND tool names (e.g. 𝗘𝘅𝗽𝗼𝘀𝘂𝗿𝗲 +𝟬.𝟱𝟬: or 𝗥𝗮𝗱𝗶𝗮𝗹 𝗚𝗿𝗮𝗱𝗶𝗲𝗻𝘁:).
6. Do NOT use bullet points. Use indentation only.
7. Use "Math Sans Bold" for key concepts followed by a colon (e.g. 𝗟𝗶𝗴𝗵𝘁𝗶𝗻𝗴:, 𝗖𝗼𝗹𝗼𝗿:, 𝗙𝗼𝗰𝘂𝘀:).
8. Keep paragraphs SHORT. Add DOUBLE NEWLINES after introductory phrases (like "adjustments:") and between paragraphs.

Example Layout:
══════════════════════════════
 📸  𝗖𝗢𝗔𝗖𝗛 𝗔𝗡𝗔𝗟𝗬𝗦𝗜𝗦
══════════════════════════════

➤  𝗢𝗩𝗘𝗥𝗩𝗜𝗘𝗪
[Concise summary...]

──────────────────────────────
 🛠  𝗦𝗧𝗘𝗣-𝗕𝗬-𝗦𝗧𝗘𝗣 𝗚𝗨𝗜𝗗𝗘
──────────────────────────────
 1️⃣  𝗜𝗺𝗽𝗼𝗿𝘁 & 𝗦𝘁𝗿𝗮𝗶𝗴𝗵𝘁𝗲𝗻
 •  Crop: [Instructions...]

 2️⃣  𝗕𝗮𝘀𝗶𝗰 𝗣𝗮𝗻𝗲𝗹
 •  Exposure: +0.50

***

JSON Command:
(A JSON block containing the *apply_develop_settings* action.)

Supported JSON Parameters (for automation):
- exposure, contrast, highlights, shadows, whites, blacks
- clarity, vibrance, saturation, texture, dehaze
- temperature, tint
- sharpness, luminanceNoise, colorNoise, vignetteAmount

CRITICAL INSTRUCTIONS FOR TEMPERATURE/TINT:
1. Check the "Context" provided in the user message for "White Balance Mode".
2. If Mode is "Kelvin":
   - You MUST use Kelvin values for 'temperature' (Range: 2000 to 50000).
   - Example: "temperature": 5500
3. If Mode is "Slider":
   - You MUST use Slider values for 'temperature' (Range: -100 to +100).
   - Example: "temperature": 10

JSON Format Example:
```json
{
  "action": "apply_develop_settings",
  "params": {
    "exposure": 0.20,
    "contrast": 15,
    "highlights": -30,
    "shadows": 40,
    "whites": 20,
    "blacks": -10,
    "temperature": 5500,
    "tint": 10,
    "clarity": 25,
    "vibrance": 20,
    "saturation": 5
  }
}
```

IMPORTANT Guidelines:
- Ensure the values in the text guide MATCH the values in the JSON block.
- If a tool (like Spot Removal or Crop) cannot be automated via JSON, describe it clearly in the text guide so the user can do it manually.

Tone: Professional, encouraging, and expert.]]

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

-- Helper to handle API response
local function handleResponse(response)
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

  return handleResponse(response)
end

-- Analyze photo using Gemini Vision
function Gemini.analyze(photo)
  local prefs = LrPrefs.prefsForPlugin()
  local apiKey = prefs.gemini_api_key or ""
  
  if apiKey == "" then 
    return { success = false, text = "No API key set." } 
  end
  
  -- 1. Get Photo Context (File Type & Current Settings)
  local currentSettings = photo:getDevelopSettings()
  local currentTemp = currentSettings["Temperature"]
  local currentTint = currentSettings["Tint"] or 0
  
  -- Robustly determine White Balance Mode based on current value
  local wbMode = "Slider (-100 to +100)"
  if currentTemp and currentTemp > 2000 then
    wbMode = "Kelvin (2000 to 50000)"
  end
  
  local photoContext = string.format(
      "Context:\n- White Balance Mode: %s\n- Current Temperature: %s\n- Current Tint: %s",
      wbMode,
      tostring(currentTemp or "0"),
      tostring(currentTint)
  )

  -- Get thumbnail synchronously (simulated)
  local jpegData = nil
  local done = false
  
  -- Reduce requested size to 512x512 to increase success rate
  photo:requestJpegThumbnail(512, 512, function(data)
    jpegData = data
    done = true
  end)
  
  -- Timeout mechanism to prevent infinite hanging
  local timeout = 0
  while not done and timeout < 50 do -- Wait up to 5 seconds
    LrTasks.yield() -- Yields to let async tasks run
    LrTasks.sleep(0.1) -- Explicit sleep
    timeout = timeout + 1
  end
  
  if not jpegData then
    return { success = false, text = "Could not generate thumbnail (Timeout or Missing)." }
  end
  
  local base64Image = base64Encode(jpegData)
  
  local body = JSON.encode({
    systemInstruction = {
      parts = { { text = VISION_SYSTEM_PROMPT } }
    },
    contents = {
      {
        role = "user",
        parts = {
          { text = "Analyze this photo and suggest edits.\n" .. photoContext },
          {
            inlineData = {
              mimeType = "image/jpeg",
              data = base64Image
            }
          }
        }
      }
    },
    generationConfig = {
      temperature = 0.4,
      maxOutputTokens = 8192,
      thinkingConfig = { includeThoughts = true }, -- Enable thinking for Nano Banana
    }
  })
  
  local response, hdrs = LrHttp.post(
    "https://generativelanguage.googleapis.com/v1beta/models/gemini-3-pro-image-preview:generateContent",
    body,
    { 
      { field = "Content-Type", value = "application/json" },
      { field = "x-goog-api-key", value = apiKey } 
    }
  )
  
  return handleResponse(response)
end

return Gemini