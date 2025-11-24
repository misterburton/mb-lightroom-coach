# Lightroom Coach

An AI-powered teaching assistant that lives inside Adobe Lightroom Classic, providing real-time guidance, photo analysis, and transparent editing powered by Google's Gemini 3 AI models.

## Features

- **Visual Analysis & Coaching**: Click "Analyze & Coach" to get a professional critique of your selected photo with step-by-step editing guidance
- **Natural Language Editing**: Type instructions like "Make the sunset more vibrant" or "Give this a moody cinematic look"
- **In-App Chat Interface**: Floating dialog with conversational AI that understands Lightroom Classic
- **Transparent Learning**: All edits appear as separate steps in your History panel so you can see exactly what changed
- **Context-Aware**: AI knows your current module, selected photos, and white balance mode for accurate suggestions
- **Thinking Models**: Powered by Gemini 3 Pro with extended reasoning for nuanced photo analysis

## Installation

1. **Download the plug-in**:
   - Visit [GitHub Releases](https://github.com/misterburton/mb-lightroom-coach/releases/latest)
   - Download `LightroomCoach.lrplugin.zip`
   - Unzip the file

2. **Install in Lightroom Classic**:
   - Open Lightroom Classic
   - Go to `File > Plug-in Manager`
   - Click `Add` button in the bottom left
   - Select the unzipped `LightroomCoach.lrplugin` folder
   - Click `Done`

3. **Get your Google Gemini API Key**:
   - Visit [Google AI Studio](https://aistudio.google.com/app/apikey)
   - **Important**: Set up billing and select the **Pay-as-you-go** plan (free tier keys don't work)
   - Create a new API key in your paid project
   - Copy the key

4. **Configure the plug-in**:
   - In the Plug-in Manager, select `Lightroom Coach` from the left panel
   - Find the `Gemini API Key` field on the right
   - Paste your Pay-as-you-go API key
   - Changes save automatically

5. **Start using it**:
   - Select a photo in the Develop module
   - Go to `File > Plug-in Extras > Lightroom Coach`
   - Ask questions or click "Analyze & Coach" to begin

## Usage

### Photo Analysis & Coaching
Click the **"📷 Analyze & Coach"** button to:
- Get a professional critique of composition, exposure, and color
- Receive a detailed step-by-step editing guide
- Apply automated "Magic Fix" settings with one click
- See each adjustment explained in your History panel

### Natural Language Editing
Type instructions in plain English:
- "Make the sunset more vibrant"
- "Fix the white balance"
- "Give this a moody cinematic look"
- "Brighten shadows and reduce highlights"

The AI will parse your request, apply the edits, and show confirmation with the option to keep or undo changes.

### Asking Questions
Get instant answers about Lightroom Classic:
- "How do I use the Tone Curve to fade the blacks?"
- "What is the difference between Texture and Clarity?"
- "How do I create a radial gradient mask?"

## Supported Develop Settings

The assistant can automatically adjust:

**Basic Panel:**
- `exposure`, `contrast`, `highlights`, `shadows`, `whites`, `blacks`

**Presence:**
- `clarity`, `vibrance`, `saturation`, `texture`, `dehaze`

**White Balance:**
- `temperature` (Kelvin or slider mode), `tint`

**Tone Curve:**
- `toneCurveHighlights`, `toneCurveLights`, `toneCurveDarks`, `toneCurveShadows`

**HSL Adjustments:**
- Hue, Saturation, and Luminance for all color channels (Red, Orange, Yellow, Green, Aqua, Blue, Purple, Magenta)

**Details & Effects:**
- `sharpness`, `luminanceNoise`, `colorNoise`, `vignetteAmount`, `grainAmount`

## Requirements

- Adobe Lightroom Classic (v12.0 or later)
- Google Gemini API key with **Pay-as-you-go billing** enabled
- Active internet connection

## Cost Considerations

This plug-in uses Google's Gemini 3 models:
- **Gemini 3 Pro Preview** (chat/edits): $2.00/1M input tokens, $12.00/1M output tokens
- **Gemini 3 Pro Image Preview** (photo analysis): $2.00/1M input tokens, $12.00/1M output tokens (text), $120.00/1M output tokens (images)

**Typical costs:**
- Edit request: ~$0.005 (half a cent)
- Photo analysis: ~$0.016 (1.6¢)
- Most users spend under $1/month with regular use

Monitor your usage at [Google Cloud Console](https://console.cloud.google.com/billing).

## Updating Your API Key

To change your API key:
1. Go to `File > Plug-in Manager`
2. Select `Lightroom Coach` from the list
3. Enter your new API key in the `Gemini API Key` field
4. Changes save automatically

## Troubleshooting

**"No API key set" error**:
- Enter your API key via Plug-in Manager preferences
- Ensure you're using a **Pay-as-you-go** key (not free tier)

**"Network error" or "Gemini API Error"**:
- Check your internet connection
- Verify your API key is valid and has billing enabled
- Check if you've exceeded rate limits

**"Could not identify action" error**:
- This typically means the AI response was truncated
- The plugin now uses 25,000 token limits to prevent this

**Edits not applying**:
- Ensure you have photos selected in Library or Develop module
- Check that the selected item is not a video

**Dialog doesn't open**:
- Restart Lightroom Classic
- Remove and re-add the plug-in via Plug-in Manager

**Analysis takes too long**:
- Analysis can take up to 30 seconds for complex images
- Large file sizes may slow down thumbnail generation

## Architecture

```
LightroomCoach.lrplugin/
├── Info.lua           # Plug-in metadata and registration
├── PluginInit.lua     # Menu command initialization
├── ChatDialog.lua     # Main chat UI and interaction logic
├── Gemini.lua         # Google Gemini API integration
├── Actions.lua        # JSON parsing and develop settings execution
├── Prefs.lua          # API key preferences interface
└── JSON.lua           # Lightweight JSON encoder/decoder
```

## Technical Details

### AI Models
- **Gemini 3 Pro Preview** (`gemini-3-pro-preview`): Text-based chat and editing requests
- **Gemini 3 Pro Image Preview** (`gemini-3-pro-image-preview`): Photo analysis with vision capabilities
- Both models use extended thinking for improved reasoning

### Special Features
- **Temperature/Tint Intelligence**: Automatically detects if your photo uses Kelvin mode (RAW) or slider mode (JPEG/TIFF) and adjusts values accordingly
- **History Panel Integration**: Each adjustment creates a separate history step for educational transparency
- **Markdown Formatting**: AI responses are automatically formatted for readability in the plain-text dialog
- **Context Caching**: System prompts are optimized for token efficiency

## Privacy & Data Usage

Since this plugin requires **Pay-as-you-go billing**, your content is **NOT** used to train or improve Google's products. Your data is processed according to [Google's Cloud Data Processing Addendum](https://ai.google.dev/gemini-api/terms) and retained only temporarily for abuse monitoring.

This plugin only sends to Google's servers:
- Your chat messages
- Photo thumbnails (512x512 JPEG, only when you click "Analyze & Coach")
- Current Lightroom context (module name, photo count, white balance mode)

No photo metadata, catalog information, or personal data is transmitted.

## License

© 2025 misterburton LLC. All rights reserved.

Beta software offered as-is. No support or updates guaranteed.