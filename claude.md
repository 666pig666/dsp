# SPECTRAL — Claude Code Implementation Guide

## Project Overview

SPECTRAL is a native iOS app for offline audio file analysis with multi-file comparison. It targets iOS 17.0+ / iPadOS 17.0+, Swift 5.9+, SwiftUI, dark mode only. No third-party DSP libraries — all signal processing uses Apple's Accelerate framework (vDSP) and AVFoundation.

The full technical specification is in `SPECTRAL_iOS_Audio_Analysis_Spec_v3.docx`. This document segments the build into 14 phases. Execute phases in order. Each phase produces compilable, testable output. Do not skip verification steps.

## Global Rules

- **Language:** Swift 5.9+. SwiftUI for all UI. No UIKit except where SwiftUI has no equivalent (e.g., UIDocumentPickerViewController if .fileImporter proves insufficient).
- **DSP:** Apple Accelerate framework only. vDSP for FFT, filtering, vector math. No AudioKit, no third-party signal processing.
- **Audio I/O:** AVAudioFile / AVAudioPCMBuffer for decoding. No AVAudioEngine, no AudioUnit graph. This is offline batch processing.
- **Precision:** All filter state variables in Double (Float64). PCM buffers in Float (Float32) as delivered by AVAudioPCMBuffer. Accumulation math in Double where noted.
- **UI:** Dark mode only. No light mode support. SwiftUI Canvas or Charts for all visualizations. No WebView.
- **Architecture:** MVVM. ObservableObject view models. Swift Concurrency (async/await, TaskGroup) for background processing.
- **Memory:** Stream-process large files in chunks. Never load an entire large file into memory. Target <100 MB peak per file.
- **Error handling:** No force unwraps in production code. All file I/O wrapped in do/catch. User-facing errors displayed as alerts.

---

## Phase 0: Project Skeleton and File Import

### Goal
Xcode project compiles and runs. User can pick an audio file. File metadata is displayed.

### Tasks
1. Create Xcode project: `SPECTRAL`, iOS 17.0 deployment target, SwiftUI lifecycle.
2. Set `Info.plist`: `UISupportsDocumentBrowser = YES`. Add `UTImportedTypeDeclarations` or rely on system-provided UTTypes for `public.audio`.
3. Create the app entry point with a dark-mode-only color scheme (`.preferredColorScheme(.dark)` on the root view, plus `Info.plist` `UIUserInterfaceStyle = Dark`).
4. Build `FileImportView`: a landing screen with an "Import Audio File" button that presents `.fileImporter(isPresented:allowedContentTypes:allowsMultipleSelection:)` with `UTType.audio`. Allow multiple selection (for comparison workflow).
5. On file selection, read metadata via `AVAudioFile`:
   - `fileFormat.sampleRate`
   - `fileFormat.channelCount`
   - `length` (frames)
   - Duration = length / sampleRate
   - File name from URL
   - Format description string from `fileFormat.formatDescription`
6. Create `AudioFileMetadata` struct (Codable, Identifiable):
   ```
   struct AudioFileMetadata: Codable, Identifiable {
       let id: UUID
       let fileName: String
       let url: URL
       let sampleRate: Double
       let channelCount: Int
       let frameCount: Int64
       let duration: TimeInterval
       let formatDescription: String
   }
   ```
7. Display metadata on screen after import.
8. Reject files with channelCount > 2 with an alert: "SPECTRAL v1 supports mono and stereo files only."

### Verification
- App compiles and launches on simulator.
- Import a WAV, MP3, FLAC, and AAC file. Metadata displays correctly for each.
- Import a file with >2 channels. Error alert appears.

---

## Phase 1: Audio Decoding and Channel Modes

### Goal
Decode any supported audio file to Float32 PCM buffers. Derive M/S channels. Expose channel mode selection.

### Tasks
1. Create `AudioDecoder` class:
   - Method: `func decode(url: URL) async throws -> DecodedAudio`
   - Opens file with `AVAudioFile(forReading:)`.
   - Reads into `AVAudioPCMBuffer` in chunks (e.g., 65536 frames per read) to avoid loading entire file into memory.
   - Stores left and right channel data as `[Float]` arrays.
   - For mono files: single channel array.
2. Create `DecodedAudio` struct:
   ```
   struct DecodedAudio {
       let metadata: AudioFileMetadata
       let sampleRate: Double
       let channelCount: Int
       let left: [Float]       // Always populated
       let right: [Float]?     // nil for mono
   }
   ```
3. Create `ChannelMode` enum:
   ```
   enum ChannelMode: String, CaseIterable {
       case stereo = "Stereo"
       case leftOnly = "Left"
       case rightOnly = "Right"
       case mid = "Mid"
       case side = "Side"
   }
   ```
4. Create `ChannelDeriver` utility:
   - `static func derive(from audio: DecodedAudio, mode: ChannelMode) -> ChannelData`
   - `ChannelData` contains one or two `[Float]` arrays depending on mode.
   - Mid: `(L + R) / 2` — use `vDSP_vadd` then `vDSP_vsmul` with scalar 0.5.
   - Side: `(L - R) / 2` — use `vDSP_vsub` then `vDSP_vsmul` with scalar 0.5.
   - Left/Right: extract the corresponding channel.
   - Stereo: pass through both channels.
5. For mono input files: only `ChannelMode.stereo` is available (treated as single channel at G=1.0). Disable other mode options in UI.

### Verification
- Decode a known stereo WAV file. Print first 10 samples of L and R. Compare against a hex editor or another tool.
- Derive Mid and Side. Verify: Mid + Side should reconstruct L. Mid - Side should reconstruct R. Verify with `vDSP_vsub`/`vDSP_vadd` and check max error < 1e-6.
- Decode a mono file. Confirm right channel is nil and only stereo mode is available.

### Memory Note
For a 4-minute stereo WAV at 48 kHz: 2 channels × 48000 × 240s × 4 bytes = ~88 MB. This is within the 100 MB budget. For longer files, implement chunked processing in Phase 2+ where the full buffer is not retained — instead, process and accumulate statistics per chunk. For v1, retaining the full decoded buffer is acceptable for files up to ~5 minutes at 96 kHz. Add a file size check: if decoded PCM would exceed 200 MB, warn the user.

---

## Phase 2: K-Weighting Filter

### Goal
Implement the BS.1770-5 K-weighting filter. Validate against known test signals.

### Spec Reference
Section 2.1 of the v3 spec.

### Tasks
1. Create `KWeightingFilter` class:
   - Two cascaded biquad stages: high-shelf and high-pass (RLB).
   - Filter state in Double precision.
   - 48 kHz coefficients hardcoded from the spec (Section 2.1).
   - For non-48 kHz sample rates: implement coefficient derivation per Brecht De Man's method. The high-shelf filter is characterized by: fc ≈ 1681 Hz, gain ≈ +3.9997 dB, Q ≈ 0.7084. The RLB high-pass: fc ≈ 38.13 Hz, Q ≈ 0.5003. Use the bilinear transform with frequency pre-warping to compute biquad coefficients at arbitrary sample rates.
   - Method: `func process(samples: [Float]) -> [Float]` — applies both stages in series.
   - Use `vDSP_deq22` for biquad filtering. Note: `vDSP_deq22` operates on Float (single precision) but we need Double state. Two options:
     a. Convert to Double, filter with manual biquad loop, convert back.
     b. Use `vDSP_deq22` (Float) and accept the precision trade-off for files under 10 minutes.
   - **Decision: Use manual Double-precision biquad for correctness.** Write a direct-form-II transposed biquad in Swift with Double state variables. Process the Float input by casting sample-by-sample to Double, filtering, casting output back to Float.
2. The filter processes each channel independently. Provide a method that takes `ChannelData` and returns K-weighted `ChannelData`.

### Verification
- Generate a 48 kHz sine wave at 1 kHz, 0 dBFS. K-weight it. Output should be ≈ 0 dB (the K-filter is approximately unity at 1 kHz).
- Generate a 48 kHz sine wave at 100 Hz, 0 dBFS. K-weight it. Output should be attenuated by ≈ 0.2 dB (slight attenuation from the RLB high-pass).
- Generate a 48 kHz sine wave at 10 kHz, 0 dBFS. K-weight it. Output should be boosted by ≈ 2.4 dB (shelf boost).
- Compare frequency response shape against the published BS.1770-4 Figure 3 curve at 48 kHz.
- **Critical:** Repeat for 44.1 kHz sample rate with derived coefficients. Response shape must match the 48 kHz shape.

---

## Phase 3: Loudness Measurement

### Goal
Compute integrated loudness, momentary max, short-term max, and LRA.

### Spec Reference
Sections 2.2–2.5 of the v3 spec.

### Tasks
1. Create `LoudnessMeter` class:
   - Input: K-weighted channel data + channel count + sample rate.
   - **Momentary loudness:** 400 ms blocks, 100 ms hop (75% overlap). Per block: compute mean square of each channel (`vDSP_measqv`), apply channel weights (G=1.0 for L, R, mono), sum, convert to LUFS: `loudness = -0.691 + 10 * log10(z)`. Store all per-block momentary values.
   - **Short-term loudness:** 3 s blocks, 1 s hop. Same computation. Store all per-block short-term values.
   - **Integrated loudness (gated):**
     a. From the momentary block values, apply absolute gate: discard blocks below -70 LUFS.
     b. Compute mean of remaining blocks (in linear power domain, not dB).
     c. Relative gate threshold = mean_LUFS - 10 LU.
     d. Discard blocks below relative threshold.
     e. Integrated = -0.691 + 10 * log10(mean of remaining blocks in linear).
   - **Momentary max:** max value from all momentary blocks.
   - **Short-term max:** max value from all short-term blocks.
   - **LRA (Loudness Range):** Per spec Section 2.5:
     a. Use 3 s blocks (same as short-term), 1 s hop.
     b. Absolute gate at -70 LUFS.
     c. Relative gate at -20 LU below ungated mean (note: -20 for LRA, -10 for integrated loudness — these are different gates).
     d. From remaining blocks, compute 10th and 95th percentile of the distribution.
     e. LRA = 95th percentile - 10th percentile, in LU.
2. Create `LoudnessResult` struct:
   ```
   struct LoudnessResult: Codable {
       let integratedLUFS: Double
       let momentaryMaxLUFS: Double
       let shortTermMaxLUFS: Double
       let loudnessRangeLU: Double
       let momentaryTimeSeries: [Double]  // per-block momentary values
       let shortTermTimeSeries: [Double]  // per-block short-term values
       let blockDurationMs: Double        // 100 ms hop for time axis
   }
   ```

### Verification
- **EBU test tone (sequence 1):** -23.0 LUFS 1 kHz sine at specified level. Integrated must measure -23.0 ±0.1 LUFS.
- **EBU test tone (sequence 2):** Two-level signal. Integrated must match published value ±0.1 LU.
- If EBU test set is not available, generate a 48 kHz, 0 dBFS 1 kHz stereo sine. Integrated (ungated, since the signal is continuous) should measure approximately -3.01 LUFS (because mean square of a 0 dBFS sine is 0.5, and -0.691 + 10*log10(0.5*2) = -0.691 + 0 = -0.691... actually let's be precise: for a stereo 0 dBFS sine at 1 kHz, K-weighted RMS ≈ 0 dB per channel, z = 1.0 * 0.5 + 1.0 * 0.5 = 1.0, LUFS = -0.691 + 10*log10(1.0) = -0.691 LUFS. Verify this.
- Generate silence followed by a tone. Verify gating excludes silence blocks.

---

## Phase 4: True Peak Measurement

### Goal
Implement true peak with user-selectable oversampling (4×, 8×, 16×, 32×). Default 8×.

### Spec Reference
Section 3 of the v3 spec.

### Tasks
1. Create `TruePeakMeter` class:
   - Input: raw (non-K-weighted) channel data + sample rate + oversampling ratio.
   - Implement polyphase FIR interpolation:
     a. Design the FIR lowpass filter for the target oversampling ratio. For 8×: cutoff at fs/2 (original Nyquist), transition band to 4*fs (oversampled Nyquist). Use `vDSP_hann_window` to design a windowed-sinc FIR. Target: ≥80 dB stopband attenuation. For 8×, a 96-tap filter (8 phases × 12 taps) is appropriate.
     b. Decompose into polyphase branches. For 8× oversampling, 8 branches of 12 taps each.
     c. For each input sample, compute the 8 (or N) interpolated samples by convolving with each polyphase branch. Use `vDSP_desamp` or manual dot product.
     d. Track the maximum absolute value across all interpolated samples and all channels.
   - Convert to dBTP: `20 * log10(maxAbsValue)`. If maxAbsValue is 0, report -inf.
   - Also track per-channel max true peak and the sample index where the global max occurs (for peak location display).
   - Process in chunks to limit memory: do not store the oversampled signal. Just track the running max.
2. Create `OversamplingRatio` enum: `case x4, x8, x16, x32` with associated Int values (4, 8, 16, 32).
3. Create `TruePeakResult` struct:
   ```
   struct TruePeakResult: Codable {
       let maxTruePeakDBTP: Double
       let perChannelTruePeakDBTP: [Double]  // [L, R] or [mono]
       let peakSampleIndex: Int64
       let peakTimeSeconds: Double
       let oversamplingRatio: Int
   }
   ```

### Verification
- Generate a 48 kHz, 0 dBFS 1 kHz sine. True peak at 8× should measure approximately +3.01 dBTP (because the inter-sample peak of a 0 dBFS digital sine exceeds the sample values).

  Wait — that's only true for specific frequencies. For a 1 kHz sine at 48 kHz, samples align reasonably well. Use a **pathological test signal** instead: 997 Hz sine at 0 dBFS, 44.1 kHz. The true peak should exceed sample peak by at least 0.5 dB at 4× and the measurement should converge as oversampling ratio increases.
  
- Generate a -6 dBFS DC signal. True peak should be exactly -6.02 dBTP regardless of oversampling ratio (no inter-sample peaks in DC).
- Verify that 4×, 8×, 16×, 32× produce converging results on the pathological signal (each higher ratio should be closer to the theoretical true peak).

---

## Phase 5: Spectral Analysis

### Goal
Compute average spectrum, peak-hold spectrum, octave bands, and spectral balance.

### Spec Reference
Section 4 of the v3 spec.

### Tasks
1. Create `SpectrumAnalyzer` class:
   - Input: channel data (from active channel mode) + sample rate + FFT size (4096 or 8192).
   - Process the entire file in windowed blocks:
     a. Apply Hann window (`vDSP_hann_window`). Blackman-Harris as option (`vDSP_blkman_window`).
     b. FFT via `vDSP_fft_zrip`. Compute magnitude: `vDSP_zvabs` or manual sqrt(re² + im²).
     c. Convert to dBFS: `20 * log10(magnitude / (N/2))` where N is FFT size.
     d. Accumulate: RMS average (sum of squared magnitudes per bin, then sqrt and convert to dB) and peak-hold (max magnitude per bin across all blocks).
   - 75% overlap between blocks.
2. Create `OctaveBandAnalyzer`:
   - From the average spectrum, sum energy within ISO 266 band edges.
   - Full octave: 10 bands (31.5 Hz to 16 kHz center frequencies).
   - 1/3 octave: 31 bands (20 Hz to 20 kHz).
   - Band edges: lower = fc / 2^(1/(2*n)), upper = fc * 2^(1/(2*n)) where n=1 for full octave, n=3 for 1/3 octave.
3. Create `SpectralBalance`:
   - Sub (≤60 Hz), Low (60–250 Hz), Low-Mid (250 Hz–1 kHz), High-Mid (1–6 kHz), High (6–20 kHz).
   - Each as dB relative to total RMS.
4. Create `SpectrumResult` struct:
   ```
   struct SpectrumResult: Codable {
       let averageSpectrum: [Float]       // dBFS per bin
       let peakHoldSpectrum: [Float]      // dBFS per bin
       let frequencyAxis: [Float]         // Hz per bin
       let fftSize: Int
       let octaveBands: [BandEnergy]      // full octave
       let thirdOctaveBands: [BandEnergy] // 1/3 octave
       let spectralBalance: SpectralBalance
   }
   ```

### Verification
- Generate a 1 kHz sine at -6 dBFS. Average spectrum should show a single peak at the 1 kHz bin at approximately -6 dBFS. All other bins should be well below (>60 dB down with Hann window).
- Generate white noise. Average spectrum should be approximately flat (within ±3 dB across 20 Hz–20 kHz).
- Generate pink noise. Average spectrum should show a -3 dB/octave slope.

---

## Phase 6: Stereo and Phase Analysis

### Goal
Compute correlation coefficient over time and M/S energy ratio.

### Spec Reference
Section 5 of the v3 spec.

### Tasks
1. Create `StereoAnalyzer` class:
   - Input: left and right channel arrays + sample rate.
   - Only operates on stereo data. Returns nil/error for mono.
   - **Correlation coefficient:** 400 ms blocks, 100 ms hop. Per block:
     a. `vDSP_dotpr(L, R)` → dot product.
     b. `vDSP_rmsqv(L)` → rms_L, `vDSP_rmsqv(R)` → rms_R.  
     c. Correlation = dotProduct / (blockLength * rms_L * rms_R). Handle division by zero (silence → correlation = 0).
     
     Actually, more precisely: r = Σ(L·R) / sqrt(Σ(L²) · Σ(R²)). Use `vDSP_dotpr` for the numerator and `vDSP_svesq` (sum of squares) for the denominator terms.
   - Store per-block correlation as time series.
   - **M/S Energy Ratio:**
     a. Compute M = (L+R)/2, S = (L-R)/2 over the full file.
     b. Compute RMS of M and S via `vDSP_rmsqv`.
     c. Ratio in dB: `20 * log10(rms_M / rms_S)`. Handle rms_S = 0 (mono signal → +inf dB, display as "Mono").
2. Create `StereoResult` struct:
   ```
   struct StereoResult: Codable {
       let correlationTimeSeries: [Double]
       let averageCorrelation: Double
       let minimumCorrelation: Double
       let midSideRatioDB: Double        // positive = more mid, negative = more side
       let blockDurationMs: Double
   }
   ```

### Verification
- Generate a stereo file with identical L and R (mono panned center). Correlation should be +1.0 everywhere. M/S ratio should be +inf (or clamped display value).
- Generate a stereo file with R = -L (polarity inverted). Correlation should be -1.0 everywhere. Mid energy should be 0 (or -inf dB).
- Generate a stereo file with uncorrelated white noise on L and R. Average correlation should be near 0.0.

---

## Phase 7: Dynamic Range Metrics

### Goal
Compute PLR, crest factor (Katz), and RMS.

### Spec Reference
Section 6 of the v3 spec.

### Tasks
1. Create `DynamicsAnalyzer` class:
   - Input: raw channel data + `LoudnessResult` + `TruePeakResult` + sample rate.
   - **PLR:** `abs(truePeakDBTP) - abs(integratedLUFS)`. Single value.
   - **Crest factor (Katz):** Per 3 s block (1 s hop):
     a. Compute true peak of the block (use same oversampling as global true peak measurement, or use sample peak for speed — document which).
     b. Compute unweighted RMS of the block: `vDSP_rmsqv`, convert to dBFS: `20 * log10(rms)`.
     c. Crest = peakDBTP - rmsDBFS.
     d. Store as time series.
     
     **Decision on block peak measurement:** Use sample peak (not oversampled true peak) for per-block crest factor. Oversampling every 3 s block is computationally expensive and the crest factor is a relative measure where the systematic under-read of sample peak is consistent across blocks. Document this in the UI: "Crest factor uses sample peak per block."
   - **RMS:** Full-file unweighted RMS per channel and summed, in dBFS.
2. Create `DynamicsResult` struct:
   ```
   struct DynamicsResult: Codable {
       let plrDB: Double
       let crestFactorTimeSeries: [Double]
       let minimumCrestFactor: Double
       let averageCrestFactor: Double
       let rmsPerChannelDBFS: [Double]
       let rmsSummedDBFS: Double
       let blockDurationMs: Double
   }
   ```

### Verification
- Generate a 0 dBFS 1 kHz sine (stereo). Sample peak = 0 dBFS. RMS of a sine = -3.01 dBFS. Crest factor should be ≈ 3.01 dB per block.
- Generate a 0 dBFS square wave. RMS = 0 dBFS. Crest factor should be ≈ 0 dB.
- Verify PLR: if integrated = -14 LUFS and true peak = -1 dBTP, PLR should be 13.

---

## Phase 8: Analysis Result Model and Pipeline Orchestrator

### Goal
Unify all analysis results into a single model. Create the orchestrator that runs all analyzers in sequence.

### Tasks
1. Create `AnalysisResult` struct:
   ```
   struct AnalysisResult: Codable, Identifiable {
       let id: UUID
       let metadata: AudioFileMetadata
       let channelMode: ChannelMode
       let loudness: LoudnessResult
       let truePeak: TruePeakResult
       let spectrum: SpectrumResult
       let stereo: StereoResult?          // nil for mono or non-stereo modes
       let dynamics: DynamicsResult
       let analysisDate: Date
       let oversamplingRatio: Int
   }
   ```
2. Create `AnalysisPipeline` class (ObservableObject):
   - `@Published var progress: Double` (0.0 to 1.0)
   - `@Published var currentStage: String`
   - Method: `func analyze(url: URL, channelMode: ChannelMode, oversamplingRatio: OversamplingRatio) async throws -> AnalysisResult`
   - Pipeline stages in order:
     a. Decode audio (update progress, stage name).
     b. Derive channel data for selected mode.
     c. K-weight the channel data.
     d. Compute loudness from K-weighted data.
     e. Compute true peak from raw (non-K-weighted) data.
     f. Compute spectrum from raw data.
     g. Compute stereo analysis from raw L/R (only if stereo mode and stereo file).
     h. Compute dynamics from raw data + loudness + true peak results.
     i. Assemble and return `AnalysisResult`.
   - Run on a background task. Report progress to UI via @Published.
3. Create `AnalysisCache`:
   - Save `AnalysisResult` as JSON to Documents directory.
   - Cache key: SHA-256 of (fileName + fileSize + modificationDate + channelMode + oversamplingRatio).
   - Load from cache if available. Invalidate if parameters differ.
   - Prune method to clear old cache entries.

### Verification
- Run full pipeline on a test WAV file. All results populated. Print summary to console.
- Run twice on same file with same parameters. Second run loads from cache (verify with timing or log).
- Run with different channel mode. Cache miss, full re-analysis.

---

## Phase 9: UI — Navigation Shell and Summary Dashboard

### Goal
Paged swipe navigation with 7 pages. Summary dashboard with tappable metric cards.

### Tasks
1. Create `ResultsView` as the main results container:
   - SwiftUI `TabView` with `.tabViewStyle(.page(indexDisplayMode: .automatic))`.
   - `@State var currentPage: Int = 0` for programmatic navigation.
   - 7 pages: Summary, Loudness, TruePeak, Spectrum, Stereo, Dynamics, Compliance.
   - Persistent top bar: file name, channel mode pill, "+" button for comparison.
2. Create `SummaryDashboardPage`:
   - Card grid (LazyVGrid, 2 columns).
   - Cards: Integrated LUFS, True Peak, LRA, PLR, Correlation (if stereo), Crest Factor.
   - Each card shows: metric name, value with unit, color-coded status indicator.
   - Each card `.onTapGesture { currentPage = targetPageIndex }`.
   - File metadata section at top.
   - Channel mode selector (Picker or segmented control).
3. Dark color palette:
   - Background: `#0D0D0D`
   - Card background: `#1A1A2E`
   - Primary text: `#E0E0E0`
   - Secondary text: `#888888`
   - Accent: `#00D4FF` (cyan)
   - Warning: `#FFB800` (amber)
   - Error: `#FF3366` (red/pink)
   - Pass: `#00CC66` (green)

### Verification
- App displays summary dashboard after analysis completes.
- Swipe through all 7 pages. Each page shows placeholder content.
- Tap a card on the summary. Page jumps to the correct detail page.
- Channel mode selector changes mode and triggers re-analysis.

---

## Phase 10: UI — Detail Pages

### Goal
Implement all 6 detail pages with charts and readouts.

### Tasks
Build each page as an independent SwiftUI View. Each receives the `AnalysisResult` as input.

1. **LoudnessPage:**
   - Large integrated LUFS readout (primary).
   - Secondary readouts: momentary max, short-term max, LRA.
   - Line chart: loudness over time. Three traces: momentary (thin, 50% opacity), short-term (medium), integrated running value (thick). X-axis: time. Y-axis: LUFS. Use SwiftUI Charts `LineMark`.

2. **TruePeakPage:**
   - Large max true peak readout with oversampling ratio label.
   - Per-channel values.
   - Threshold reference lines at -1.0 and -2.0 dBTP.
   - Waveform overview using SwiftUI Canvas: draw the PCM samples as a waveform path. Mark the peak location with a vertical red line. Allow pinch-to-zoom.

3. **SpectrumPage:**
   - Average spectrum as a line (SwiftUI Canvas, log frequency axis).
   - Peak-hold spectrum overlaid (thinner line, different color).
   - Toggle for octave band view: 1/3-octave or full-octave bars.
   - Spectral balance bar chart: 5 horizontal bars with dB labels.

4. **StereoPage:**
   - Correlation over time as a line chart. Y-axis: -1 to +1. Reference line at 0.
   - Average and minimum correlation readouts.
   - M/S ratio readout.
   - Show "Stereo mode required" message if current channel mode is not Stereo.

5. **DynamicsPage:**
   - PLR readout with interpretation text (computed from value: "Well-preserved headroom" / "Aggressive limiting" / etc.).
   - Crest factor over time as a line chart. Reference lines at 8 dB and 14 dB.
   - Min and average crest factor readouts.
   - RMS readouts per channel.

6. **CompliancePage:**
   - Platform preset selector (Picker).
   - Grid: metric name | measured | target | delta | pass/fail icon.
   - Metrics checked: Integrated LUFS (within tolerance), Max True Peak (below threshold).
   - Pass = green checkmark. Fail = red X.

### Verification
- Each page renders with real data from a test file.
- Charts are scrollable/zoomable where specified.
- Long-press on a metric value copies to clipboard.
- Compliance page correctly flags a hot master (e.g., -8 LUFS) as failing Spotify's -14 LUFS target.

---

## Phase 11: Comparison Data Model and Engine

### Goal
Multi-file comparison stack with delta computation.

### Tasks
1. Create `ComparisonStack` ObservableObject:
   ```
   class ComparisonStack: ObservableObject {
       @Published var files: [AnalysisResult] = []  // max 4
       var primary: AnalysisResult? { files.first }
       
       func add(_ result: AnalysisResult) { ... }  // enforce max 4
       func remove(id: UUID) { ... }
       func promote(id: UUID) { ... }  // move to index 0, recompute deltas
   }
   ```
2. Create `ComparisonDelta` struct:
   - Computed between any file and the primary (File A).
   - Fields: `deltaIntegratedLUFS`, `deltaTruePeakDBTP`, `deltaLRA`, `deltaPLR`, `deltaCorrelation`, `deltaCrestFactor`, `deltaRMS`.
   - All computed as (FileN - FileA), preserving sign.
3. Color assignment: map file index to color (White, Cyan, Magenta, Amber).
4. Sample alignment check:
   - Compare `frameCount` of all files in stack.
   - If any differ by > sampleRate (i.e., > 1 second), set `alignmentWarning: String?` on the stack.
   - If differ by ≤ 4096 samples, no warning.
5. Integrate with the "+" button in the top bar: opens file importer, analyzes the new file, adds to stack.

### Verification
- Add two files to comparison stack. Deltas compute correctly.
- Add a file with a known +1 dB gain offset. Delta integrated LUFS should be approximately +1.0 LU.
- Add a fifth file. Rejected with "Maximum 4 files" error.
- Tap a pill to promote to primary. Deltas recompute relative to new primary.

---

## Phase 12: Comparison UI

### Goal
Overlay and delta views on all detail pages when comparison stack has >1 file.

### Tasks
1. Update each detail page to accept `ComparisonStack` as environment or input.
2. **Conditional rendering:** If `comparisonStack.files.count > 1`, show comparison UI. Otherwise, single-file UI.
3. **Summary dashboard:** Expand cards to table. One column per file. Delta column for B/C/D.
4. **Loudness page:** Overlay loudness time series from all files on same chart. Color per file. Add toggle: Overlay / Split / Delta mode.
5. **Spectrum page:** Overlay average spectra. Add spectral difference trace (B-A, C-A, D-A). Zero-centered y-axis with ±6 dB default range.
6. **Stereo page:** Overlay correlation time series.
7. **Dynamics page:** Overlay crest factor time series.
8. **Compliance page:** All files as columns.
9. **Pill bar:** Collapsible strip below top bar. File pills with color dots and × buttons.
10. **Alignment warning:** If set, display amber banner across all comparison pages.

### Verification
- Import two WAV files. All comparison views render.
- Spectral difference trace shows expected shape for a known EQ difference.
- Remove a file from the stack. Views update.
- Promote a file. Deltas recalculate.

---

## Phase 13: Platform Presets and Export

### Goal
Editable platform preset system. CSV and XML export.

### Tasks
1. Create `PlatformPreset` struct (Codable):
   ```
   struct PlatformPreset: Codable, Identifiable {
       let id: UUID
       var name: String
       var targetIntegratedLUFS: Double
       var targetIntegratedTolerance: Double
       var maxTruePeakDBTP: Double
       var isBuiltIn: Bool
   }
   ```
2. Load built-in presets from a bundled `presets.json` file (values from spec Section 9).
3. Allow user to create custom presets via a settings screen.
4. **CSV export:**
   - One row per file in the comparison stack.
   - Columns: fileName, format, sampleRate, bitDepth, duration, integratedLUFS, momentaryMaxLUFS, shortTermMaxLUFS, LRA, maxTruePeakDBTP, truePeakL, truePeakR, oversamplingRatio, PLR, avgCrestFactor, minCrestFactor, rmsDBFS, avgCorrelation, minCorrelation, midSideRatioDB.
   - Semicolon-delimited. UTF-8.
   - Share via `ShareLink` or `UIActivityViewController`.
5. **XML export:**
   - Root: `<spectral_analysis>`. Child: `<file>` per file with `<metadata>`, `<loudness>`, `<truePeak>`, `<dynamics>`, `<stereo>` element groups.
   - If comparison mode: `<delta>` elements relative to primary.

### Verification
- Export CSV with two files. Open in a spreadsheet. Values match displayed values.
- Export XML. Validate well-formedness with an XML parser.
- Create a custom preset. Compliance page uses it correctly.

---

## Phase 14: Validation Harness

### Goal
Built-in test mode that runs the deterministic validation battery from spec Section 11.4.

### Tasks
1. Create a hidden settings toggle: "Developer Mode" (triple-tap on version number or similar).
2. In developer mode, add a "Run Validation" button that executes:
   - **Test 1 (Null):** Generate a 10-second 1 kHz stereo sine at -14 dBFS, 48 kHz. Analyze as File A. Copy to File B (bit-identical). Compare. All deltas must be 0.0.
   - **Test 2 (Gain Offset):** Take the same signal. Apply +3.000 dB gain to produce File B. Analyze both. Delta integrated LUFS must be 3.0 ±0.1 LU. Spectral difference must be flat at +3.0 ±0.2 dB.
   - **Test 3 (Known EQ):** Apply a high shelf (+3 dB at 8 kHz, Q=0.707) to the reference. Spectral difference at 8 kHz must be +3.0 ±0.5 dB. Below 1 kHz, difference must be < 0.2 dB.
   - **Test 4 (Phase Inversion):** Invert right channel. Correlation must be -1.0 ±0.01. Mid energy must be > 60 dB below side energy.
   - **Test 5 (Length Mismatch):** Append 2 seconds of silence to File B. Warning banner must appear. Loudness delta must reflect the silence (File B should measure lower integrated LUFS).
3. Display test results as pass/fail with measured values.
4. Generate test signals programmatically using `vDSP` (sine generation via `vDSP_vgenp` or manual computation). Do not require external test files.

### Verification
- All 5 tests pass on first run.
- Intentionally break a computation (e.g., flip a sign). Verify that the test catches it.

---

## Build Order Summary

| Phase | Depends On | Delivers |
|-------|-----------|----------|
| 0 | — | Project skeleton, file import, metadata |
| 1 | 0 | Audio decoding, channel modes |
| 2 | 1 | K-weighting filter |
| 3 | 2 | Loudness measurement |
| 4 | 1 | True peak measurement |
| 5 | 1 | Spectral analysis |
| 6 | 1 | Stereo/phase analysis |
| 7 | 3, 4 | Dynamic range metrics |
| 8 | 3, 4, 5, 6, 7 | Unified result model, pipeline orchestrator, cache |
| 9 | 8 | Navigation shell, summary dashboard |
| 10 | 9 | All detail pages |
| 11 | 8 | Comparison data model and engine |
| 12 | 10, 11 | Comparison UI overlays |
| 13 | 10, 11 | Platform presets, CSV/XML export |
| 14 | 8, 11 | Validation harness |

Phases 2–7 are DSP modules that can be developed and tested independently (they share only the decoded audio buffer from Phase 1). Phase 8 integrates them. Phases 9–10 are UI that depends on Phase 8. Phases 11–14 are features that layer on top.

---

## Notes for Claude Code

- Always verify each phase before proceeding to the next. If verification fails, fix before moving on.
- The spec document (`SPECTRAL_iOS_Audio_Analysis_Spec_v3.docx`) is the authoritative reference for all algorithms, tolerances, and standards. This guide provides implementation specifics. When they conflict, the spec wins.
- Do not use `try!` or `fatalError()` in production code. These are acceptable only in the validation harness for programmatically generated test signals.
- When implementing vDSP functions, always check Apple's documentation for the exact function signature. vDSP has many similar-looking functions with different behaviors (e.g., `vDSP_rmsqv` vs `vDSP_rmsq`).
- All @Published properties must be updated on the main thread. Use `@MainActor` or `DispatchQueue.main.async` as needed.
- The `[Float]` arrays for decoded audio can be large. Avoid unnecessary copies. Use `inout` or `UnsafeMutableBufferPointer` where appropriate for vDSP calls.
