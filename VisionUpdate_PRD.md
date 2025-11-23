# Vision & Coaching Update PRD

**Goal:** Add visual analysis capabilities to the Lightroom Coach plugin, allowing it to critique photos and automate comprehensive edits (Exposure, Color, Crop, Tone Curve, Effects) using Gemini 3 Pro Image Preview.

## Lessons Learned (Requirements)
1.  **Separate Utility File:** Create a dedicated `Base64.lua` file for encoding logic.
2.  **Robust Syntax:** Use standard, verbose Lua 5.1 syntax in `Base64.lua` to ensure compatibility and prevent "Could not load" errors. Avoid complex one-liners.
3.  **Scope:** Implementation must handle comprehensive Lightroom edits (Basic, Presence, Curves, Effects).

## Implementation Plan

### 1. Create `Base64.lua`
-   Implement a standard Lua 5.1 Base64 encoder.
-   Use explicit loops and `math.floor` for bitwise operations (no bitwise operators).
-   Ensure the file returns a table with an `encode` function.

### 2. Update `Gemini.lua`
-   **Import Base64:** `local Base64 = require 'Base64'`.
-   **Add `Gemini.analyze(photo)`:**
    -   Request JPEG thumbnail (1024px) via `photo:requestJpegThumbnail`.
    -   Base64 encode the result using the new utility.
    -   Send to model: `gemini-3-pro-image-preview`.
    -   **System Prompt:** Instruct model to critique (Composition, Exposure, Color) and return JSON for **all** relevant settings (Basic, Tone Curve, Presence, Vignette, Crop).

### 3. Update `ChatDialog.lua`
-   **UI:** Add a "📷 Analyze & Coach" button next to "New Chat".
-   **Logic:**
    -   On click: Get active photo -> `Gemini.analyze()`.
    -   Display text critique in chat.
    -   Auto-apply JSON edits (Magic Fix).
    -   Show "Keep/Undo" confirmation dialog.

## Success Criteria
-   `require 'Base64'` loads successfully without error.
-   Clicking "Analyze" sends the image and returns a valid critique + edit suggestions.
-   Edits are applied to the photo automatically.

## Verification Log
-   **[2025-11-23] Rich Text Formatting:** Implemented Unicode/ASCII pseudo-formatting in `Gemini.lua` system prompt to improve readability of plain text responses. Increased `ChatDialog.lua` output window height to 100 lines to accommodate formatted text. ✅
