local LrDialogs = import 'LrDialogs'
local LrView = import 'LrView'
local LrTasks = import 'LrTasks'
local LrPrefs = import 'LrPrefs'
local LrColor = import 'LrColor'

local OpenAI = require 'OpenAI'
local Actions = require 'Actions'

local ChatDialog = {}

-- Prompt suggestions
local SUGGESTIONS = {
  "How do I adjust white balance?",
  "Explain the tone curve controls",
  "Brighten this photo by +0.5 exposure",
  "How do I use masks?"
}

function ChatDialog.present()
  local prefs = LrPrefs.prefsForPlugin()
  
  -- Skip API key check if already set (it's visible in Plug-in Manager)
  -- Dialog will error gracefully if key is missing during API call

  local f = LrView.osFactory()
  local props = LrView.bindings.makePropertyTable(_G)
  
  props.userInput = ""
  props.transcript = ""
  props.isLoading = false
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
    if props.isLoading or message == "" then return end
    
    props.showSuggestions = false
    addToTranscript("user", message)
    props.userInput = ""
    props.isLoading = true

    LrTasks.startAsyncTask(function()
      local context = OpenAI.getContext()
      local response = OpenAI.ask(message, context)
      
      props.isLoading = false
      
      if response.success then
        addToTranscript("assistant", response.text)
        
        -- Check for actions in response
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

  -- Build suggestion chips
  local suggestionChips = {}
  for i, suggestion in ipairs(SUGGESTIONS) do
    table.insert(suggestionChips, f:push_button {
      title = suggestion,
      font = "<system/small>",
      action = function() sendMessage(suggestion) end,
      enabled = LrView.bind {
        key = "showSuggestions",
        transform = function(value) return value end
      }
    })
  end

  local c = f:column {
    bind_to_object = props,
    fill_horizontal = 1,
    spacing = f:control_spacing(),
    
    -- Header with New Chat button
    f:row {
      fill_horizontal = 1,
      f:static_text {
        title = "Lightroom Coach",
        font = "<system/bold>",
        text_color = LrColor(0.9, 0.9, 0.9)
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
    
    -- Suggestion chips (shown when transcript is empty)
    f:column {
      visible = LrView.bind("showSuggestions"),
      spacing = f:control_spacing(),
      f:static_text {
        title = "Try asking:",
        font = "<system/small>",
        text_color = LrColor(0.7, 0.7, 0.7)
      },
      suggestionChips[1],
      suggestionChips[2],
      suggestionChips[3],
      suggestionChips[4]
    },
    
    f:separator { fill_horizontal = 1 },
    
    -- Input area
    f:row {
      fill_horizontal = 1,
      spacing = f:control_spacing(),
      f:edit_field {
        value = LrView.bind("userInput"),
        width_in_chars = 50,
        fill_horizontal = 1,
        enabled = LrView.bind {
          key = "isLoading",
          transform = function(value) return not value end
        }
      },
      f:push_button {
        title = LrView.bind {
          key = "isLoading",
          transform = function(value) return value and "Sending..." or "Send" end
        },
        enabled = LrView.bind {
          key = "isLoading",
          transform = function(value) return not value end
        },
        action = function() sendMessage(props.userInput) end
      }
    }
  }

  local result = LrDialogs.presentFloatingDialog(_PLUGIN, {
    title = "Lightroom Coach",
    contents = c,
    resizable = true,
  })
end

return ChatDialog