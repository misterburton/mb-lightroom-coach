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

local Gemini = require 'Gemini'
local Actions = require 'Actions'

local ChatDialog = {}

-- Preset suggestions
local SUGGESTIONS = {
  "How do I adjust white balance?",
  "Explain the tone curve controls",
  "Brighten this photo by +0.5 exposure",
  "How do I use masks?"
}

function ChatDialog.present()
  LrFunctionContext.callWithContext('chatDialog', function(context)
    local f = LrView.osFactory()
    local props = LrBinding.makePropertyTable(context)
    
    -- Initialize properties
    props.userInput = ""
    
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

    props.showSuggestions = false -- suggestions removed
    
    -- Initialize chat history (not bound to UI, just internal state)
    local chatHistory = {}

    -- Helper to clean markdown syntax for plain text display
    local function cleanMarkdown(text)
      local t = text
      -- Headers: ### Header -> HEADER (uppercase)
      t = t:gsub("###%s*([^\n]+)", function(s) return string.upper(s) end)
      
      -- Bold: **text** -> text
      t = t:gsub("%*%*([^*]+)%*%*", "%1")
      
      -- Italic: _text_ -> text
      t = t:gsub("_([^_]+)_", "%1")
      
      -- Lists: * item or - item -> • item
      t = t:gsub("\n[%*%-]%s", "\n• ")
      t = t:gsub("^[%*%-]%s", "• ")
      
      -- Monospace: `text` -> 'text'
      t = t:gsub("`([^`]+)`", "'%1'")

      -- Unescape quotes: \" -> "
      t = t:gsub('\\"', '"')
      
      -- Specific Fix for "Refining Editing Parameters" to Bold Unicode
      if t:find("Refining Editing Parameters") then
         t = t:gsub("Refining Editing Parameters", "𝗥𝗲𝗳𝗶𝗻𝗶𝗻𝗴 𝗘𝗱𝗶𝘁𝗶𝗻𝗴 𝗣𝗮𝗿𝗮𝗺𝗲𝘁𝗲𝗿𝘀")
      end
      
      -- Bold "Formulating" header
      if t:find("Formulating") then
         t = t:gsub("Formulating", "𝗙𝗼𝗿𝗺𝘂𝗹𝗮𝘁𝗶𝗻𝗴")
      end
      
      -- Sanitize Technical Jargon in Thoughts
      t = t:gsub("JSON parameters", "automated settings")
      t = t:gsub("JSON block", "automated settings")
      t = t:gsub("JSON", "system")
      
      -- Force double newlines after numbered headers (1️⃣ Step Name) for visual separation
      t = t:gsub("(\n%s*%d+️⃣[^\n]+)\n", "%1\n\n")
      t = t:gsub("(\n%s*%d+️⃣[^\n]+)$", "%1\n\n") 
      
      -- Force TRIPLE newline before bulleted lists (• or -) if not present for extra separation
      t = t:gsub("([^\n])\n([•%-]%s)", "%1\n\n\n%2")
      
      return t
    end

    -- Helper to add message to transcript
    local function addToTranscript(role, message, skipPrefix)
      -- Convert literal \n escape sequences to actual newlines
      local cleanMessage = message:gsub("\\n", "\n"):gsub("\\r", "")
      
      -- Clean markdown formatting for display
      cleanMessage = cleanMarkdown(cleanMessage)
      
      if props.transcript ~= "" then
        props.transcript = props.transcript .. "\n\n" -- Add double newline for better separation
      end
      
      if role == "user" then
        props.transcript = props.transcript .. "YOU: " .. cleanMessage
        -- Add to history
        table.insert(chatHistory, { role = "user", text = message })
      else
        if skipPrefix then
            props.transcript = props.transcript .. cleanMessage
        else
            props.transcript = props.transcript .. "COACH: " .. cleanMessage
        end
        -- Add to history
        table.insert(chatHistory, { role = "assistant", text = message })
      end
    end

    -- Helper to process AI response
    local function processResponse(response)
      if response.success then
        -- Parse and execute actions first
        local actionResult = Actions.maybePerform(response.text)
        
        -- Strip JSON from display (code blocks or raw JSON objects)
        local displayText = response.text
        
        -- Remove ```json...``` blocks (handling potential unclosed blocks from truncation)
        displayText = displayText:gsub("```json.*", "")
        -- Remove any other ``` code blocks
        displayText = displayText:gsub("```.*", "")
        -- Remove raw JSON objects - iterate to handle nested braces
        while displayText:find("{") do
          local oldText = displayText
          displayText = displayText:gsub("{[^{}]*}", "")
          if displayText == oldText then break end -- prevent infinite loop
        end
        -- Clean up extra whitespace and newlines
        displayText = displayText:gsub("^%s+", ""):gsub("%s+$", ""):gsub("\n+", "\n")
        
        -- Only show if there's actual text left after stripping JSON
        if displayText ~= "" then
          -- Check if this is a rich formatted analysis (starts with heavy separator or header)
          local isAnalysis = displayText:find("════") or displayText:find("𝐀𝐍𝐀𝐋𝐘𝐒𝐈𝐒") or displayText:find("𝐂𝐎𝐀𝐂𝗛")
          addToTranscript("assistant", displayText, isAnalysis)
        elseif actionResult then
          addToTranscript("assistant", "Applying settings...")
        else
          -- Parsing failed but we received *something*. Show the raw text so the user isn't confused.
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

      LrTasks.startAsyncTask(function()
        -- Standard error handling via success checks in modules
        local contextData = Gemini.getContext()
        
        -- Pass entire history to Gemini.ask
        local response = Gemini.ask(chatHistory, contextData)
        
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
      -- Use more accurate loading text as requested
      addToTranscript("assistant", "Analyzing photo... (This may take up to 30 seconds)", true)
      
      LrTasks.startAsyncTask(function()
         local response = Gemini.analyze(photo)
         processResponse(response)
      end)
    end

    -- New chat handler
    local function newChat()
      props.transcript = ""
      props.userInput = ""
      props.showSuggestions = true
      chatHistory = {} -- Clear history
    end

    -- Build UI
    local contents = f:column {
      bind_to_object = props,
      fill_horizontal = 1,
      spacing = f:label_spacing(),
      margin = 8,
      
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
            action = analyzePhoto
        }
      },
      
      f:separator { fill_horizontal = 1, margin_bottom = 5 },
      
      -- Transcript area
      -- FIX: Reverting to edit_field with MODERATE height.
      -- height_in_lines = 60 forces vertical scrolling (~1000px height)
      -- This is large enough to overflow the 400px view, but small enough
      -- to minimize the massive empty white space issue.
      f:scrolled_view {
        width = 480,
        height = 400,
        horizontal_scroller = false,
        vertical_scroller = true,
        margin_bottom = 5,
        
        f:edit_field {
          value = LrView.bind("transcript"),
          width = 450, -- Prevent horizontal scroll
          height_in_lines = 125, -- Reduced to prevent excessive empty scrolling space
          enabled = false, 
          wraps = true
        }
      },
      
      f:separator { fill_horizontal = 1, margin_bottom = 5 },
      
      -- Input area
      f:row {
        fill_horizontal = 1,
        spacing = 5,
        f:edit_field {
          value = LrView.bind("userInput"),
          width_in_chars = 40,
          fill_horizontal = 1,
          immediate = true,
          validate = function(view, value)
            -- Check for Enter/Return key
            if value:find("\n") or value:find("\r") then
              -- Remove the newline and send
              local cleanValue = value:gsub("\n", ""):gsub("\r", "")
              if cleanValue ~= "" then
                sendMessage(cleanValue)
              end
              return false, "" -- Clear the field
            end
            return true, value
          end
        },
        f:push_button {
          title = "Send",
          action = function() 
            local msg = props.userInput
            sendMessage(msg)
          end
        }
      }
    }

    -- Present floating dialog
    LrDialogs.presentFloatingDialog(_PLUGIN, {
      title = "Lightroom Coach",
      contents = contents
    })
  end)
end

return ChatDialog