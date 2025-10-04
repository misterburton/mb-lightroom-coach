local LrView = import 'LrView'
local LrPrefs = import 'LrPrefs'

local prefs = LrPrefs.prefsForPlugin()

return {
  sectionsForTopOfDialog = function(f, propertyTable)
    return {
      {
        title = "OpenAI Configuration",
        bind_to_object = prefs,
        
        f:row {
          spacing = f:control_spacing(),
          f:static_text { 
            title = "OpenAI API Key:",
            alignment = 'right',
            width = LrView.share 'label_width'
          },
          f:edit_field {
            value = LrView.bind("openai_api_key"),
            width_in_chars = 50,
            immediate = true
          }
        },
        
        f:row {
          spacing = f:control_spacing(),
          f:static_text { 
            title = "",
            width = LrView.share 'label_width'
          },
          f:static_text {
            title = "Get your API key from platform.openai.com/api-keys",
            font = "<system/small>",
            text_color = import 'LrColor'(0.5, 0.5, 0.5)
          }
        }
      }
    }
  end
}