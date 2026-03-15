# SPECTRAL UI Polish — Claude Code Instructions

## Design Philosophy

SPECTRAL's visual identity should reference FabFilter's design language: clean, precise, confidence-inspiring. Every pixel should communicate "this is a professional instrument, not a toy." The UI should feel like a high-end hardware meter panel — the kind of thing you'd find rackmounted in a mastering suite beside a Dangerous Music monitor controller. Think TC Electronic Clarity M meets iOS.

Do NOT make it look like a generic SwiftUI app with rounded rectangles and system fonts. Do NOT use Apple's default component styles. Every element should be custom-styled.

---

## Color System

### Background Layers (depth via elevation)
The current flat `#0D0D0D` everywhere is wrong. Use a layered elevation system where surfaces closer to the user are progressively lighter, creating depth without borders.

```
Level 0 (deepest background):    #080808
Level 1 (page background):      #0F0F0F
Level 2 (card / panel surface): #161620
Level 3 (elevated element):     #1C1C2A
Level 4 (active / hover):       #242438
```

### Accent Colors (desaturated for dark mode comfort)
The current cyan `#00D4FF` is too saturated — it vibrates against dark backgrounds and causes eye fatigue. Desaturate it.

```
Primary accent (cyan):     #4ECDC4   (teal-cyan, softer)
Secondary accent (green):  #2ECC71   (pass / good)
Warning (amber):           #E6A817   (slightly desaturated from #FFB800)
Error (red-pink):          #E74C6F   (softer than #FF3366)
Neutral text primary:      #E8E8E8   (not pure white — pure white on black causes halation)
Neutral text secondary:    #7A7A8E   (muted lavender-gray, not flat gray)
Neutral text tertiary:     #4A4A5A   (for labels, dividers)
```

### Data Series Colors (comparison mode)
```
File A:  #E8E8E8   (near-white, reference)
File B:  #4ECDC4   (teal)
File C:  #E74C6F   (rose)
File D:  #E6A817   (amber)
```

### Chart Colors
```
Grid lines:              #1E1E2E   (barely visible, not distracting)
Axis labels:             #5A5A6E
Momentary loudness:      #4ECDC4 at 40% opacity
Short-term loudness:     #2ECC71
Integrated reference:    #4ECDC4 at full opacity, dashed
Spectrum average:        #4ECDC4
Spectrum peak-hold:      #E74C6F at 60% opacity
Crest factor:            #4ECDC4
Correlation positive:    #2ECC71
Correlation negative:    #E74C6F
Threshold / reference lines: #E6A817 at 60% opacity, dashed
```

---

## Typography

Use SF Pro throughout — it's the system font and renders perfectly on iOS. The key is establishing a strict hierarchy with consistent weight/size pairings. Never mix arbitrary sizes.

```
Hero metric (e.g., "-14.2 LUFS"):
  Font: SF Mono (monospaced), 44pt, Bold
  Tracking: -0.5 (tighter)
  Color: primary accent or white depending on context

Section header:
  Font: SF Pro Display, 13pt, Semibold
  Tracking: 1.5pt (expanded)
  Transform: UPPERCASE
  Color: secondary text (#7A7A8E)

Metric label (above a value):
  Font: SF Pro Text, 11pt, Medium
  Color: tertiary text (#4A4A5A)

Metric value (secondary readouts):
  Font: SF Mono, 20pt, Semibold
  Color: primary text (#E8E8E8)

Unit suffix (dBTP, LUFS, LU):
  Font: SF Pro Text, 11pt, Regular
  Color: secondary text (#7A7A8E)
  Baseline-aligned with value

Body / description text:
  Font: SF Pro Text, 13pt, Regular
  Color: secondary text

Small data (axis labels, timestamps):
  Font: SF Mono, 9pt, Regular
  Color: #5A5A6E
```

### Implementation in SwiftUI
```swift
// Hero metric
.font(.system(size: 44, weight: .bold, design: .monospaced))
.tracking(-0.5)

// Section header
.font(.system(size: 13, weight: .semibold, design: .default))
.tracking(1.5)
.textCase(.uppercase)

// Metric value
.font(.system(size: 20, weight: .semibold, design: .monospaced))
```

---

## Card / Panel Design

The current cards are flat colored rectangles. Make them feel like physical panels.

### Structure
- Background: Level 2 color (`#161620`)
- Corner radius: 16pt (not 12 — slightly more generous feels more premium)
- No visible border — use subtle inner shadow or 1pt top highlight instead
- Inner padding: 16pt horizontal, 14pt vertical
- Between cards: 10pt gap

### Subtle Top Highlight (simulates light from above)
Add a 1pt line at the top of each card with `#242438` (Level 4) — this creates a subtle bevel effect that gives dimensionality without looking skeumorphic.

```swift
.overlay(alignment: .top) {
    Rectangle()
        .fill(Color(hex: 0x242438))
        .frame(height: 1)
}
```

### Shadow (very subtle — just enough to lift the card)
```swift
.shadow(color: Color.black.opacity(0.4), radius: 8, x: 0, y: 4)
```

---

## Summary Dashboard Layout

### File Metadata Bar
Redesign as a slim horizontal strip at the very top of the page, not a text block.

```
┌──────────────────────────────────────────────┐
│  filename.wav   48.0 kHz  Stereo  4:23  24b  │
└──────────────────────────────────────────────┘
```

- Background: Level 0 (`#080808`)
- Font: SF Mono, 11pt, Regular
- Items separated by subtle dot dividers: `·`
- Filename in primary text color, metadata in secondary

### Metric Cards
Redesign the 2-column grid. Each card should have:

```
┌────────────────────┐
│  INTEGRATED        │  ← section header style (uppercase, tracked, tertiary)
│                    │
│  -14.2             │  ← hero metric (SF Mono, 32pt, bold)
│  LUFS              │  ← unit label (11pt, secondary text)
│                    │
│  ● Pass            │  ← status dot + word, bottom-right aligned
└────────────────────┘
```

The status dot should glow. Use a small circle with a radial gradient or shadow:

```swift
Circle()
    .fill(statusColor)
    .frame(width: 6, height: 6)
    .shadow(color: statusColor.opacity(0.6), radius: 4)
```

---

## Chart Polish (CanvasLineChart improvements)

### Background
Charts should have a subtle gradient background, not flat color:
- Top: `#0F0F0F`
- Bottom: `#080808`

This creates a sense of depth behind the data.

### Grid Lines
- Use dashed lines: `[2, 4]` pattern (short dash, longer gap)
- Color: `#1E1E2E` — barely visible
- No border around the chart area

### Data Lines
- Apply anti-aliased rendering (Canvas does this by default)
- Use `lineWidth: 1.5` for primary data, `1.0` for secondary
- For the loudness momentary trace: use low opacity (0.3) to create a "ghost" effect behind the solid short-term trace

### Axis Labels
- Font: SF Mono 9pt
- Color: `#5A5A6E`
- Left Y-axis labels: right-aligned, 4pt gap from the chart edge
- Bottom X-axis labels: center-aligned below tick marks

### Reference Lines (integrated LUFS, crest factor thresholds)
- Dashed: `[6, 4]` pattern
- Color: accent color at 50% opacity
- Add a tiny label at the right end of the line: e.g., `"-14.0"` in 8pt SF Mono

---

## Navigation and Top Bar

### Top Bar
Redesign from a flat colored strip to a glassy blurred bar:

```swift
.background(.ultraThinMaterial)
.environment(\.colorScheme, .dark)
```

This gives the iOS-native frosted glass effect. The filename and controls float over it.

### Page Indicator Dots
The default `.page(indexDisplayMode: .automatic)` dots are too small and gray. Custom page indicators:

```swift
HStack(spacing: 6) {
    ForEach(0..<7, id: \.self) { i in
        Circle()
            .fill(i == currentPage ? Color(hex: 0x4ECDC4) : Color(hex: 0x3A3A4A))
            .frame(width: i == currentPage ? 8 : 6, height: i == currentPage ? 8 : 6)
            .animation(.easeInOut(duration: 0.2), value: currentPage)
    }
}
```

Place this at the bottom of the screen, above the safe area.

### Page Titles
Add a subtle page title that fades in/out as you swipe:

```
LOUDNESS    TRUE PEAK    SPECTRUM    STEREO    DYNAMICS    COMPLIANCE
```

Style: SF Pro Display, 11pt, Semibold, uppercase, tracked 2.0, color `#7A7A8E`. Centered above the chart area on each page.

---

## Import / Empty State

### Empty State
The current design is functional but generic. Make it atmospheric:

- Remove the SF Symbol icon. Replace with a custom waveform animation:
  - A single horizontal line that subtly undulates (sine wave with very slow animation, amplitude 2-3pt)
  - Color: primary accent at 30% opacity
  - This gives the screen life without being distracting

- "SPECTRAL" text: SF Pro Display, 28pt, Bold, tracked 3.0, uppercase. Color: primary text. Below the waveform line.

- Subtitle: "Audio Analysis Engine" — SF Pro Text, 13pt, Regular, secondary text.

- Import button: no bordered prominent style. Use a custom capsule:
  ```swift
  Text("IMPORT FILE")
      .font(.system(size: 13, weight: .semibold))
      .tracking(1.5)
      .foregroundStyle(Color(hex: 0x080808))  // dark text on accent bg
      .padding(.horizontal, 28)
      .padding(.vertical, 12)
      .background(Color(hex: 0x4ECDC4))
      .clipShape(Capsule())
  ```

### File List
Each row should be a card (Level 2 background) with:
- Filename: SF Pro Text, 15pt, Semibold, primary text
- Metadata pills: small capsules with Level 3 background
  ```
  [48.0 kHz]  [Stereo]  [4:23]
  ```
  Font: SF Mono, 10pt, Regular, secondary text

---

## Compliance Page

### Pass/Fail Indicators
Replace checkmark/xmark circles with filled status bars:

```
INTEGRATED   -14.2 LUFS   -14.0   +0.2   ████████████░░   PASS
TRUE PEAK    -1.3 dBTP    -1.0    +0.3   ████████████████   FAIL
```

The bar fills proportionally to how close the value is to the threshold. Green fill for pass, red for fail. This is more informative than a binary icon.

### Platform Preset Selector
Style as a segmented-style horizontal scroll of capsule buttons, not a dropdown picker:

```
[Spotify] [Apple Music] [YouTube] [EBU R128] [ATSC] ...
```

Active preset: accent background with dark text. Inactive: Level 3 background with secondary text.

---

## Comparison Mode Polish

### Pill Bar
Each file pill should have:
- Color dot (6pt, with glow shadow)
- Filename truncated to 20 chars
- Tiny "×" dismiss button
- Background: Level 3
- Active/primary pill: thin accent border (1pt)

### Delta Values
Use signed formatting with color:
```
+0.3 dB  → amber/red (louder/hotter)
-0.3 dB  → green (quieter/more headroom)
 0.0 dB  → tertiary text (neutral)
```

Monospaced font, right-aligned in columns.

---

## Animations and Transitions

### Page Transitions
The paged TabView handles swipe transitions natively. Add a subtle opacity fade to the page title as it enters:

```swift
.opacity(currentPage == thisPage ? 1 : 0)
.animation(.easeIn(duration: 0.3), value: currentPage)
```

### Analysis Progress
Replace the plain ProgressView with a custom bar:
- Background: Level 2, full width, 4pt height, rounded caps
- Fill: primary accent, animated from left to right
- Below: stage name in secondary text, 11pt

### Value Changes
When a metric value updates (e.g., channel mode change triggers re-analysis), the number should transition:

```swift
.contentTransition(.numericText())
.animation(.easeInOut(duration: 0.4), value: result.loudness.integratedLUFS)
```

---

## Haptics

Add haptic feedback on key interactions:
- Tapping a dashboard card to navigate: `.impact(style: .light)`
- Swipe landing on a new page: `.selection()`
- Analysis complete: `.notification(type: .success)`
- Validation test pass: `.notification(type: .success)`
- Validation test fail: `.notification(type: .error)`

```swift
import UIKit

let impactLight = UIImpactFeedbackGenerator(style: .light)
impactLight.impactOccurred()

let notif = UINotificationFeedbackGenerator()
notif.notificationOccurred(.success)
```

---

## Implementation Order

1. **Color system** — Replace all `Color(hex: ...)` values throughout the codebase with the new palette. Define them as static constants in a `Theme.swift` file.
2. **Typography** — Replace all `.font(...)` calls with the hierarchy defined above.
3. **Card redesign** — Add top highlight, shadow, new corner radius, new padding.
4. **Summary dashboard** — Metadata bar, card layout, status glow dots.
5. **Chart polish** — Update CanvasLineChart with gradient background, new grid style, new colors, reference line labels.
6. **Top bar** — Ultra-thin material blur, custom page indicators, page titles.
7. **Import screen** — Waveform animation, new button style, file list cards.
8. **Compliance page** — Progress bars instead of icons, horizontal preset selector.
9. **Comparison mode** — Pill glow dots, signed delta coloring.
10. **Animations** — Numeric transitions, progress bar, haptics.

---

## What NOT To Do

- No gradients on text. Ever. Text must be flat color for readability.
- No neumorphism or 3D effects on buttons.
- No rounded rectangle borders thicker than 1pt.
- No background images or patterns.
- No blur effects on chart areas (performance killer on Canvas).
- No spring animations — use `.easeInOut` or `.easeIn` only. Spring animations feel playful, not professional.
- No SF Symbols for the main brand/logo area. SF Symbols are for utility icons only (share, plus, chevron).
- Do not change the CanvasLineChart rendering approach — it must remain Canvas-based, not SwiftUI Charts. The previous SwiftUI Charts implementation caused SIGKILL memory crashes.
- Do not add any new dependencies or packages. Pure SwiftUI + UIKit haptics only.
