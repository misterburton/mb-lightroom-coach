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

local OpenAI = require 'OpenAI'
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

    -- Helper to add message to transcript
    local function addToTranscript(role, message)
      if props.transcript ~= "" then
        props.transcript = props.transcript .. "\n\n"
      end
      
      if role == "user" then
        props.transcript = props.transcript .. "You: " .. message
      else
        props.transcript = props.transcript .. "Coach: " .. message
      end
    end

    -- Send message handler
    local function sendMessage(message)
      if message == "" then return end
      
      props.showSuggestions = false
      addToTranscript("user", message)
      props.userInput = ""

      LrTasks.startAsyncTask(function()
        local contextData = OpenAI.getContext()
        local response = OpenAI.ask(message, contextData)
        
        if response.success then
          -- Parse and execute actions first
          local actionResult = Actions.maybePerform(response.text)
          
          -- Strip JSON code blocks from display
          local displayText = response.text
          
          -- Remove ```json...``` blocks (including newlines inside)
          displayText = displayText:gsub("```json[^`]*```", "")
          -- Remove any other ``` code blocks
          displayText = displayText:gsub("```[^`]*```", "")
          -- Clean up extra whitespace
          displayText = displayText:gsub("^%s+", ""):gsub("%s+$", "")
          
          -- Only show if there's actual text left after stripping JSON
          if displayText ~= "" then
            addToTranscript("assistant", displayText)
          elseif actionResult then
            addToTranscript("assistant", "Applying settings...")
          else
            addToTranscript("assistant", "Done.")
          end
        else
          addToTranscript("assistant", "Error: " .. response.text)
        end
      end)
    end

    -- New chat handler
    local function newChat()
      props.transcript = ""
      props.userInput = ""
      props.showSuggestions = true
    end

    -- Build UI
    local contents = f:column {
      bind_to_object = props,
      fill_horizontal = 1,
      spacing = f:label_spacing(),
      margin = 15,
      
      -- Header with New Chat button
      f:row {
        fill_horizontal = 1,
        margin_bottom = 10,
        f:static_text {
          title = "Lightroom Coach",
          font = "<system/bold>"
        },
        f:spacer { fill_horizontal = 1 },
        f:push_button {
          title = "New Chat",
          font = "<system/small>",
          action = newChat
        }
      },
      
      f:separator { fill_horizontal = 1, margin_bottom = 10 },
      
      -- Transcript area (read-only, reactive)
      f:scrolled_view {
        width = 600,
        height = 400,
        horizontal_scroller = false,
        margin_bottom = 10,
        f:edit_field {
          value = LrView.bind("transcript"),
          height_in_lines = 20,
          width = 580,
          enabled = false,
          fill_horizontal = 1
        }
      },
      
      -- Suggestion buttons (conditionally visible)
      f:column {
        visible = LrView.bind("showSuggestions"),
        spacing = f:label_spacing(),
        margin_bottom = 10,
        f:static_text {
          title = "Try asking:",
          font = "<system/small>",
          margin_bottom = 5
        },
        f:push_button {
          title = SUGGESTIONS[1],
          font = "<system/small>",
          action = function() sendMessage(SUGGESTIONS[1]) end
        },
        f:push_button {
          title = SUGGESTIONS[2],
          font = "<system/small>",
          action = function() sendMessage(SUGGESTIONS[2]) end
        },
        f:push_button {
          title = SUGGESTIONS[3],
          font = "<system/small>",
          action = function() sendMessage(SUGGESTIONS[3]) end
        },
        f:push_button {
          title = SUGGESTIONS[4],
          font = "<system/small>",
          action = function() sendMessage(SUGGESTIONS[4]) end
        }
      },
      
      f:separator { fill_horizontal = 1, margin_bottom = 10 },
      
      -- Input area
      f:row {
        fill_horizontal = 1,
        spacing = f:label_spacing(),
        f:edit_field {
          value = LrView.bind("userInput"),
          width_in_chars = 50,
          fill_horizontal = 1
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

