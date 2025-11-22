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
    props.transcript = ""
    props.showSuggestions = true
    
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
      
      return t
    end

    -- Helper to add message to transcript
    local function addToTranscript(role, message)
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
        props.transcript = props.transcript .. "COACH: " .. cleanMessage
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
        
        -- Remove ```json...``` blocks (including newlines inside)
        displayText = displayText:gsub("```json[^`]*```", "")
        -- Remove any other ``` code blocks
        displayText = displayText:gsub("```[^`]*```", "")
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
          addToTranscript("assistant", displayText)
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
      addToTranscript("assistant", "Analyzing photo... (This may take up to 30 seconds)")
      
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
      
      -- Header with Analyze and New Chat buttons
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
        },
        f:push_button {
          title = "New Chat",
          action = newChat
        }
      },
      
      f:separator { fill_horizontal = 1, margin_bottom = 5 },
      
      -- Transcript area
      -- FIX: Reverting to edit_field for reliable data binding.
      -- FIX: Using a large height_in_lines (100) inside a constrained scrolled_view.
      -- This forces the edit_field to be tall enough to hold content, triggering the scrolled_view's scrollbar.
      f:scrolled_view {
        width = 480,
        height = 400,
        horizontal_scroller = false,
        vertical_scroller = true,
        margin_bottom = 5,
        
        f:edit_field {
          value = LrView.bind("transcript"),
          width_in_chars = 50, -- Ensure generous width
          height_in_lines = 100, -- FORCE large height to trigger scroll
          enabled = false, -- Read-only
          wraps = true -- Ensure text wrapping
        }
      },
      
      -- Suggestion buttons (conditionally visible)
      f:column {
        visible = LrView.bind("showSuggestions"),
        spacing = 3,
        margin_bottom = 5,
        f:push_button {
          title = SUGGESTIONS[1],
          action = function() sendMessage(SUGGESTIONS[1]) end
        },
        f:push_button {
          title = SUGGESTIONS[2],
          action = function() sendMessage(SUGGESTIONS[2]) end
        },
        f:push_button {
          title = SUGGESTIONS[3],
          action = function() sendMessage(SUGGESTIONS[3]) end
        },
        f:push_button {
          title = SUGGESTIONS[4],
          action = function() sendMessage(SUGGESTIONS[4]) end
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
