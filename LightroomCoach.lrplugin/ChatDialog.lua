--[[----------------------------------------------------------------------------
ChatDialog.lua
Floating chat dialog UI with reactive property binding

© 2025 misterburton
------------------------------------------------------------------------------]]

local LrDialogs = import 'LrDialogs'
local LrView = import 'LrView'
local LrBinding = import 'LrBinding'
local LrFunctionContext = import 'LrFunctionContext'
local LrTasks = import 'LrTasks'
local LrApplication = import 'LrApplication'
local LrHttp = import 'LrHttp'
local LrColor = import 'LrColor'

local Gemini = require 'Gemini'
local Actions = require 'Actions'

-- GitHub repository info for update checks
local GITHUB_OWNER = "misterburton"
local GITHUB_REPO = "mb-lightroom-coach"

-- Current plugin version (update this alongside Info.lua when releasing)
local CURRENT_VERSION = "2.1.0"

local ChatDialog = {}

-- Preset suggestions
local SUGGESTIONS = {
  "How do I adjust white balance?",
  "Explain the tone curve controls",
  "Brighten this photo by +0.5 exposure",
  "How do I use masks?"
}

-- Get current plugin version as string
local function getCurrentVersion()
  return CURRENT_VERSION
end

-- Parse version string to comparable table (e.g., "v1.2.3" or "1.2.3" -> {1, 2, 3})
local function parseVersion(versionStr)
  -- Remove leading 'v' if present
  local clean = versionStr:gsub("^v", "")
  local major, minor, revision = clean:match("(%d+)%.(%d+)%.(%d+)")
  if major then
    return { tonumber(major), tonumber(minor), tonumber(revision) }
  end
  return nil
end

-- Compare two version tables, returns true ONLY if remote is strictly newer than local
local function isNewerVersion(localVer, remoteVer)
  if not localVer or not remoteVer then return false end
  if #localVer < 3 or #remoteVer < 3 then return false end
  
  -- Check each component: major, minor, revision
  for i = 1, 3 do
    local local_i = tonumber(localVer[i]) or 0
    local remote_i = tonumber(remoteVer[i]) or 0
    if remote_i > local_i then return true end
    if remote_i < local_i then return false end
  end
  return false -- versions are equal, NOT newer
end

-- Check GitHub for latest release (synchronous, called within async task)
local function checkForUpdatesSync()
  local url = string.format(
    "https://api.github.com/repos/%s/%s/releases/latest",
    GITHUB_OWNER, GITHUB_REPO
  )
  
  local response, headers = LrHttp.get(url, {
    { field = "Accept", value = "application/vnd.github.v3+json" },
    { field = "User-Agent", value = "LightroomCoach-Plugin" }
  })
  
  if response then
    local tagName = response:match('"tag_name":%s*"([^"]+)"')
    local htmlUrl = response:match('"html_url":%s*"(https://github.com/[^"]+/releases/[^"]+)"')
    
    if tagName and #tagName > 0 and htmlUrl and #htmlUrl > 0 then
      local currentVer = parseVersion(getCurrentVersion())
      local remoteVer = parseVersion(tagName)
      
      if currentVer and remoteVer and #currentVer == 3 and #remoteVer == 3 then
        if isNewerVersion(currentVer, remoteVer) then
          return true, tagName, htmlUrl
        end
      end
    end
  end
  
  return false, nil, nil
end

function ChatDialog.present()
  LrTasks.startAsyncTask(function()
    -- Check for updates FIRST, before building UI
    local updateAvailable, updateVersion, updateUrl = checkForUpdatesSync()
    
    LrFunctionContext.callWithContext('chatDialog', function(context)
      local f = LrView.osFactory()
      local props = LrBinding.makePropertyTable(context)
      
      -- Initialize properties
      props.userInput = ""
      props.canSend = true
      
      -- Zero-State Welcome Message (Onboarding)
      props.transcript = [[👋 𝗜'𝗺 𝘆𝗼𝘂𝗿 𝗔𝗜 𝗘𝗱𝗶𝘁𝗶𝗻𝗴 𝗖𝗼𝗮𝗰𝗵.

𝗧𝘄𝗼 𝘄𝗮𝘆𝘀 𝗜 𝗰𝗮𝗻 𝗵𝗲𝗹𝗽:

1. 📸 𝗔𝗻𝗮𝗹𝘆𝘇𝗲 & 𝗖𝗼𝗮𝗰𝗵
   Click the button above for a full critique and automated "Magic Fix".

2. 💬 𝗘𝗱𝗶𝘁 𝘄𝗶𝘁𝗵 𝗪𝗼𝗿𝗱𝘀
   Type instructions below like:
   • "Make the sunset more vibrant"
   • "Fix the white balance"
   • "Give this a moody cinematic look"]]

      props.showSuggestions = false
      
      -- Initialize chat history (not bound to UI, just internal state)
      local chatHistory = {}

      -- Spinner animation state
      local spinnerFrames = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }
      local isLoading = false
      local transcriptBeforeLoading = ""

      -- Start spinner animation
      local function startSpinner(loadingMessage)
        isLoading = true
        props.canSend = false
        transcriptBeforeLoading = props.transcript
        
        if transcriptBeforeLoading ~= "" then
          props.transcript = transcriptBeforeLoading .. "\n\n" .. spinnerFrames[1] .. " " .. loadingMessage
        else
          props.transcript = spinnerFrames[1] .. " " .. loadingMessage
        end
        
        LrTasks.startAsyncTask(function()
          local frameIndex = 1
          while isLoading do
            LrTasks.sleep(0.1)
            if not isLoading then break end
            
            frameIndex = frameIndex % #spinnerFrames + 1
            if transcriptBeforeLoading ~= "" then
              props.transcript = transcriptBeforeLoading .. "\n\n" .. spinnerFrames[frameIndex] .. " " .. loadingMessage
            else
              props.transcript = spinnerFrames[frameIndex] .. " " .. loadingMessage
            end
          end
        end)
      end

      -- Stop spinner and restore transcript to pre-loading state
      local function stopSpinner()
        isLoading = false
        props.canSend = true
        props.transcript = transcriptBeforeLoading
      end

      -- Helper to clean markdown syntax for plain text display
      local function cleanMarkdown(text)
        local t = text
        t = t:gsub("###%s*([^\n]+)", function(s) return string.upper(s) end)
        t = t:gsub("%*%*([^*]+)%*%*", "%1")
        t = t:gsub("_([^_]+)_", "%1")
        t = t:gsub("\n[%*%-]%s", "\n• ")
        t = t:gsub("^[%*%-]%s", "• ")
        t = t:gsub("`([^`]+)`", "'%1'")
        t = t:gsub('\\"', '"')
        
        if t:find("Refining Editing Parameters") then
           t = t:gsub("Refining Editing Parameters", "𝗥𝗲𝗳𝗶𝗻𝗶𝗻𝗴 𝗘𝗱𝗶𝘁𝗶𝗻𝗴 𝗣𝗮𝗿𝗮𝗺𝗲𝘁𝗲𝗿𝘀")
        end
        
        if t:find("Formulating") then
           t = t:gsub("Formulating", "𝗙𝗼𝗿𝗺𝘂𝗹𝗮𝘁𝗶𝗻𝗴")
        end
        
        t = t:gsub("JSON parameters", "automated settings")
        t = t:gsub("JSON block", "automated settings")
        t = t:gsub("JSON", "system")
        t = t:gsub("(\n%s*%d+️⃣[^\n]+)\n", "%1\n\n")
        t = t:gsub("(\n%s*%d+️⃣[^\n]+)$", "%1\n\n") 
        t = t:gsub("([^\n])\n([•%-]%s)", "%1\n\n\n%2")
        
        return t
      end

      -- Helper to add message to transcript
      local function addToTranscript(role, message, skipPrefix)
        local cleanMessage = message:gsub("\\n", "\n"):gsub("\\r", "")
        cleanMessage = cleanMarkdown(cleanMessage)
        
        if props.transcript ~= "" then
          props.transcript = props.transcript .. "\n\n"
        end
        
        if role == "user" then
          props.transcript = props.transcript .. "YOU: " .. cleanMessage
          table.insert(chatHistory, { role = "user", text = message })
        else
          if skipPrefix then
              props.transcript = props.transcript .. cleanMessage
          else
              props.transcript = props.transcript .. "COACH: " .. cleanMessage
          end
          table.insert(chatHistory, { role = "assistant", text = message })
        end
      end

      -- Helper to process AI response
      local function processResponse(response)
        if response.success then
          local actionResult = Actions.maybePerform(response.text)
          local displayText = response.text
          
          displayText = displayText:gsub("```json.*", "")
          displayText = displayText:gsub("```.*", "")
          while displayText:find("{") do
            local oldText = displayText
            displayText = displayText:gsub("{[^{}]*}", "")
            if displayText == oldText then break end
          end
          displayText = displayText:gsub("^%s+", ""):gsub("%s+$", ""):gsub("\n+", "\n")
          
          if displayText ~= "" then
            local isAnalysis = displayText:find("════") or displayText:find("𝐀𝐍𝐀𝐋𝐘𝐒𝐈𝐒") or displayText:find("𝐂𝐎𝐀𝐂𝗛")
            addToTranscript("assistant", displayText, isAnalysis)
          elseif actionResult then
            addToTranscript("assistant", "Applying settings...")
          else
            addToTranscript("assistant", "Could not identify action. Raw response:\n" .. response.text)
          end
        else
          addToTranscript("assistant", "Error: " .. response.text)
        end
      end

      -- Send message handler
      local function sendMessage(message)
        if message == "" then return end
        
        props.showSuggestions = false
        addToTranscript("user", message)
        props.userInput = ""

        startSpinner("Thinking...")

        LrTasks.startAsyncTask(function()
          local contextData = Gemini.getContext()
          local response = Gemini.ask(chatHistory, contextData)
          stopSpinner()
          processResponse(response)
        end)
      end
      
      -- Analyze photo handler
      local function analyzePhoto()
        local catalog = LrApplication.activeCatalog()
        local photo = catalog:getTargetPhoto()
        
        if not photo then
           LrDialogs.message("No Photo Selected", "Please select a photo to analyze.", "info")
           return
        end
        
        props.showSuggestions = false
        startSpinner("Analyzing photo... (may take up to 30 seconds)")
        
        LrTasks.startAsyncTask(function()
           local response = Gemini.analyze(photo)
           stopSpinner()
           processResponse(response)
        end)
      end

      -- New chat handler
      local function newChat()
        props.transcript = ""
        props.userInput = ""
        props.showSuggestions = true
        chatHistory = {}
      end

      -- Build UI elements list
      local uiElements = {
        -- Header with Analyze button
        f:row {
          fill_horizontal = 1,
          margin_bottom = 5,
          f:static_text {
            title = "Lightroom Coach",
            font = "<system/bold>"
          },
          f:spacer { fill_horizontal = 1 },
          f:push_button {
              title = "📷 Analyze & Coach",
              action = analyzePhoto,
              enabled = LrView.bind("canSend")
          }
        },
      }
      
      -- CONDITIONALLY add update row ONLY if there's a newer version
      if updateAvailable then
        local newVer = updateVersion:gsub("^v", "")
        table.insert(uiElements, f:row {
          fill_horizontal = 1,
          margin_bottom = 5,
          f:static_text {
            title = "⬆️ Update available: v" .. CURRENT_VERSION .. " → v" .. newVer,
            text_color = LrColor(0.2, 0.5, 0.9),
            font = "<system/bold>"
          },
          f:spacer { fill_horizontal = 1 },
          f:push_button {
            title = "Download",
            action = function()
              LrHttp.openUrlInBrowser(updateUrl)
            end
          }
        })
      end
      
      -- Add remaining UI elements
      table.insert(uiElements, f:separator { fill_horizontal = 1, margin_bottom = 5 })
      
      table.insert(uiElements, f:scrolled_view {
        width = 515,
        height = 400,
        horizontal_scroller = false,
        vertical_scroller = true,
        margin_bottom = 5,
        
        f:edit_field {
          value = LrView.bind("transcript"),
          width = 485,
          height_in_lines = 175,
          enabled = false, 
          wraps = true
        }
      })
      
      table.insert(uiElements, f:separator { fill_horizontal = 1, margin_bottom = 5 })
      
      table.insert(uiElements, f:row {
        fill_horizontal = 1,
        spacing = 5,
        f:edit_field {
          value = LrView.bind("userInput"),
          width_in_chars = 40,
          fill_horizontal = 1,
          immediate = true,
          validate = function(view, value)
            if value:find("\n") or value:find("\r") then
              local cleanValue = value:gsub("\n", ""):gsub("\r", "")
              if cleanValue ~= "" then
                sendMessage(cleanValue)
              end
              return false, ""
            end
            return true, value
          end
        },
        f:push_button {
          title = "Send",
          action = function() 
            local msg = props.userInput
            sendMessage(msg)
          end,
          enabled = LrView.bind("canSend")
        }
      })

      -- Build final column with all elements
      local contents = f:column {
        bind_to_object = props,
        fill_horizontal = 1,
        spacing = f:label_spacing(),
        margin = 8,
        unpack(uiElements)
      }

      -- Present floating dialog
      LrDialogs.presentFloatingDialog(_PLUGIN, {
        title = "Lightroom Coach",
        contents = contents
      })
    end)
  end)
end

return ChatDialog
