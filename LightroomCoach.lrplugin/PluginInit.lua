local LrFunctionContext = import 'LrFunctionContext'
local LrDialogs = import 'LrDialogs'
local LrView = import 'LrView'
local LrBinding = import 'LrBinding'
local LrPrefs = import 'LrPrefs'
local LrTasks = import 'LrTasks'

local OpenAI = require 'OpenAI'
local Actions = require 'Actions'

-- Prompt suggestions
local SUGGESTIONS = {
  "How do I adjust white balance?",
  "Explain the tone curve controls",
  "Brighten this photo by +0.5 exposure",
  "How do I use masks?"
}

LrFunctionContext.callWithContext("showDialog", function(context)
  local prefs = LrPrefs.prefsForPlugin()
  local f = LrView.osFactory()
  local props = LrBinding.makePropertyTable(context)
  
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
        addToTranscript("assistant", response.text)
        Actions.maybePerform(response.text)
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

  local contents = f:column {
    bind_to_object = props,
    fill_horizontal = 1,
    spacing = f:control_spacing(),
    
    -- Header with New Chat button
    f:row {
      fill_horizontal = 1,
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
    
    f:separator { fill_horizontal = 1 },
    
    -- Transcript area
    f:scrolled_view {
      width = 600,
      height = 400,
      horizontal_scroller = false,
      f:edit_field {
        value = LrView.bind("transcript"),
        width_in_chars = 70,
        height_in_lines = 20,
        enabled = false,
        fill_horizontal = 1
      }
    },
    
    -- Suggestion chips
    f:column {
      visible = LrView.bind("showSuggestions"),
      spacing = f:control_spacing(),
      f:static_text {
        title = "Try asking:",
        font = "<system/small>"
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
    
    f:separator { fill_horizontal = 1 },
    
    -- Input area
    f:row {
      fill_horizontal = 1,
      spacing = f:control_spacing(),
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

  -- Use a simple blocking dialog instead
  local result = LrDialogs.presentModalDialog({
    title = "Lightroom Coach",
    contents = contents,
    actionVerb = "< exclude >",
  })
end)
