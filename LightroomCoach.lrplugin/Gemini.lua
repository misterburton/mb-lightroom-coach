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
local SYSTEM_PROMPT = [[You are Lightroom Classic Coach. Answer Lightroom questions and execute photo edits.

For EDIT requests (brighten, adjust, enhance, etc.), return ONLY JSON:
{"action":"apply_develop_settings","params":{"exposure":0.5}}

Available params: exposure, contrast, highlights, shadows, whites, blacks, clarity, vibrance, saturation, temperature, tint

For QUESTIONS (How/Where/What), give concise text answers. Only Lightroom Classic topics.]]

local VISION_SYSTEM_PROMPT = [[You are a World-Class, Award-Winning Photography Coach and Master Photo Editor with 50 years of experience.
You have an exceptional eye for composition, lighting, color theory, and mood.
Your goal is to transform the user's photo into a masterpiece, or at least significantly improve it, while teaching them the "why" behind your decisions.

Analyze the provided image deeply. Look for emotion, story, and technical execution.
Critique the photo constructively, like a mentor speaking to a student. Be encouraging but honest about flaws.

FORMATTING INSTRUCTIONS:
Since you can only output plain text, you MUST use Unicode and ASCII characters to create a beautiful, structured layout.
1. Use heavy separators (e.g. "══════════════════════════════") for main sections.
2. Use light separators (e.g. "──────────────────────────────") for subsections.
3. Use icons for visual interest (e.g. 📸, 🎨, 📐, 💡, ⚠, ✔).
4. Use "Math Sans Bold" unicode characters for headers (e.g. 𝐀𝐍𝐀𝐋𝐘𝐒𝐈𝐒 instead of ANALYSIS or **ANALYSIS**).
5. Use indentation to create hierarchy.
6. Keep paragraphs SHORT. Add DOUBLE NEWLINES between paragraphs to improve legibility.

Example Layout:
══════════════════════════════
 📸  𝗖𝗢𝗔𝗖𝗛 𝗔𝗡𝗔𝗟𝗬𝗦𝗜𝗦
══════════════════════════════

➤  𝗢𝗩𝗘𝗥𝗩𝗜𝗘𝗪
[Your high-level thoughts...]

➤  𝗪𝗛𝗔𝗧 𝗪𝗢𝗥𝗞𝗦
 ✔  𝗖𝗼𝗺𝗽𝗼𝘀𝗶𝘁𝗶𝗼𝗻: [Text...]

 ✔  𝗕𝗮𝗹𝗮𝗻𝗰𝗲: [Text...]

➤  𝗖𝗥𝗜𝗧𝗜𝗖𝗔𝗟 𝗜𝗦𝗦𝗨𝗘𝗦
 ⚠  𝗨𝗻𝗱𝗲𝗿𝗲𝘅𝗽𝗼𝘀𝘂𝗿𝗲: [Text...]

──────────────────────────────
 🛠  𝗦𝗨𝗚𝗚𝗘𝗦𝗧𝗘𝗗 𝗘𝗗𝗜𝗧𝗦
──────────────────────────────
 1️⃣  [Step Name]: [Explanation...]

 2️⃣  [Step Name]: [Explanation...]

After the critique, provide a DETAILED, NUMBERED LIST of specific edits.
Explain your artistic intent. Don't just say "increase exposure," say "brighten the exposure to reveal the lost details in the shadows and create a more inviting atmosphere."
Teach the user how these specific adjustments achieve the artistic vision.

End your critique with the exact phrase: "Applying these settings now..."

Finally, translate your artistic vision into a JSON object for Lightroom Classic.
IMPORTANT TECHNICAL SPECS FOR LIGHTROOM API (Internal Use Only):
- Exposure: -5.0 to +5.0 (e.g. 0.5 is +1/2 stop).
- Contrast, Highlights, Shadows, Whites, Blacks, Clarity, Dehaze, Vibrance, Saturation: -100 to +100 scale.
- Temperature: Absolute Kelvin (2000-50000). Daylight is ~5500. To warm up, go HIGHER (e.g. 6500). To cool down, go LOWER (e.g. 4500). DO NOT use small offsets like +10.
- Tint: -150 to +150 (Green to Magenta).
- Vignette: -100 (dark) to +100 (light).

Format your response with the rich text critique first, followed by the JSON block:

[Rich Text Content...]

Applying these settings now...

```json
{
  "action": "apply_develop_settings",
  "params": {
    "exposure": 0.0,
    "contrast": 0,
    ... other settings ...
  }
}
```]]

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
          { text = "Analyze this photo and suggest edits." },
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
