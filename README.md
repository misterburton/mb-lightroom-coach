# Lightroom Classic Coach

An AI-powered assistant that lives inside Adobe Lightroom Classic, providing real-time guidance and autonomous editing capabilities powered by OpenAI's GPT-5.

## Features

- **In-App Chat Interface**: Floating dialog with Adobe-matched design language
- **Lightroom-Specific Guidance**: AI restricted to Lightroom Classic topics only
- **Autonomous Editing**: Natural language commands like "Brighten this photo by +0.5 exposure"
- **Smart Suggestions**: Four contextual prompt suggestions to get started
- **Nondestructive Edits**: All changes logged to history panel with easy undo
- **Session Management**: Start fresh chats while maintaining clean UI

## Installation

1. **Download or clone this repository**

2. **Install the plug-in**:
   - Open Lightroom Classic
   - Go to `File > Plug-in Manager`
   - Click `Add` button
   - Navigate to and select the `LightroomCoach.lrplugin` folder
   - Click `Done`

3. **Get your OpenAI API Key**:
   - Visit [OpenAI Platform](https://platform.openai.com/api-keys)
   - Create a new API key
   - Copy the key (you'll need it in the next step)

4. **Launch Lightroom Coach**:
   - Go to `File > Plug-in Extras > Lightroom Coach…`
   - On first launch, you'll be prompted to enter your OpenAI API key
   - Paste your key and click `Save`

## Usage

### Asking Questions
Simply type questions about Lightroom features:
- "How do I adjust white balance?"
- "Explain the tone curve controls"
- "How do I use masks?"

### Requesting Edits
Use natural language to perform edits:
- "Brighten this photo by +0.5 exposure"
- "Increase contrast by 15 and reduce highlights by 20"
- "Warm up the temperature"

The AI will execute the edit immediately and show a confirmation dialog with options to keep or undo the changes.

### Managing Conversations
- Click **New Chat** to clear the transcript and start fresh
- Prompt suggestions appear when starting a new chat

## Supported Develop Settings

The assistant can adjust these develop settings:
- `exposure`
- `contrast`
- `highlights`
- `shadows`
- `whites`
- `blacks`
- `clarity`
- `vibrance`
- `saturation`
- `temperature`
- `tint`

## Requirements

- Adobe Lightroom Classic (with SDK 12.0+)
- OpenAI API Key with GPT-5-mini access
- Active internet connection

## Cost Considerations

This plug-in uses OpenAI's GPT-5-mini model:
- Input: $1.25 per 1M tokens
- Output: $10.00 per 1M tokens

Typical queries cost fractions of a cent. Monitor your usage at [OpenAI Usage Dashboard](https://platform.openai.com/usage).

## Updating Your API Key

To change your API key:
1. Go to `File > Plug-in Manager`
2. Select `Lightroom Coach` from the list
3. Enter your new API key in the field
4. Changes save automatically

## Troubleshooting

**"No API key set" error**:
- Enter your API key via Plug-in Manager preferences

**"Network error" message**:
- Check your internet connection
- Verify your API key is valid

**Edits not applying**:
- Ensure you have photos selected in Library or Develop module
- Check that you're not in a restricted module (e.g., Print, Web)

**Dialog doesn't open**:
- Restart Lightroom Classic
- Remove and re-add the plug-in via Plug-in Manager

## Architecture

```
LightroomCoach.lrplugin/
├── Info.lua           # Plug-in metadata and registration
├── PluginInit.lua     # Menu command initialization
├── ChatDialog.lua     # Main chat UI and interaction logic
├── OpenAI.lua         # API integration and context extraction
├── Actions.lua        # JSON parsing and develop settings execution
├── Prefs.lua          # API key preferences interface
└── JSON.lua           # Lightweight JSON encoder/decoder
```

## License

MIT License - See LICENSE file for details

## Support

For issues, feature requests, or questions, please open an issue on GitHub.

