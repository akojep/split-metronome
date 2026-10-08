# Split Metronome

A stage metronome that lives in a phone browser. Left and right ears get their own subdivision of one tempo, a voice guide calls song sections in time like a MultiTracks click track, a warm pad drones in any key, and songs save on the phone and copy between phones by QR code.

Live copy: https://akojep.github.io/split-metronome/ (open it in the phone browser, then Add to Home Screen; after that it runs offline).

**Licence:** this code is shared privately. It carries no open-source licence; use in another product is by permission of the author, akojep. The two bundled libraries have their own licences, listed in `THIRD_PARTY.md`.

This file is for a developer who wants to run it, change it, or put it inside another app. `README.txt` is the end-user sheet for the portable launcher.

## What is in the folder

| File | What it is |
|---|---|
| `index.html` | The whole app: HTML, CSS and one `<script>` block (plain ES5-style JavaScript, no framework, no build step). |
| `guide-voices.js` | The voice clips, as `window.GUIDE_VOICES = { id: "data:audio/wav;base64,..." }`. 16 kHz mono WAV, silence trimmed so the word starts at t = 0. 21 clips: 14 section names, `n1` to `n6`, and `and`. |
| `qrcode.js` | qrcode-generator 1.4.4 by Kazuhiko Arase, MIT (header kept in the file). Draws QR codes. |
| `jsQR.js` | jsQR 1.4.0 by Cosmo Wolfe, Apache 2.0. Reads QR codes from camera frames. The file has no licence header, so if you ship it, carry the Apache 2.0 text and the jsQR credit in your app's third-party notices (see `THIRD_PARTY.md`). |
| `sw.js` | Service worker. Caches every file so the installed app works offline. |
| `manifest.json`, `icon-*.png` | Home-screen install: name, icons, standalone display, landscape orientation. `make_icons.py` regenerates the icons. |
| `START METRONOME.bat`, `server.ps1` | Optional Windows launcher: a dependency-free PowerShell static server that also answers `metro.local` on the LAN. Not needed for hosting. |

There is no package.json and nothing to compile. Any static web server serves it.

## Running and hosting

- Local: any static server in this folder, for example `python -m http.server 8790`, then open `http://localhost:8790/`. (`file://` does not work: the service worker and camera need http or https.) The service worker registers on localhost too and answers cache-first, so after the first load your edits do not show until you bump `CACHE` in `sw.js` and reload twice, or tick "Bypass for network" in the browser devtools.
- Hosting: copy the folder to any static host. The live copy is GitHub Pages serving the public repo `akojep/split-metronome`, branch `main`, from the root.
- **HTTPS is required** on phones for install, offline cache, the screen wake lock and the camera. Localhost is exempt.

### Shipping a change

The service worker caches by name, so phones keep the old version until the name changes.

1. Edit `index.html` (or the other files).
2. In `sw.js` bump `CACHE` (`splitmetro-v54` to `v55`).
3. If `guide-voices.js` changed, also bump the `?v=` query on it in **both** `index.html` and the `FILES` list in `sw.js`.
4. Push to the hosting repo. Installed apps download the new version in the background on their next online open and show it on the open after that.

The install-time settings in `manifest.json` (name, icons, orientation) only take effect when the icon is re-added to the home screen.

## How it works

Everything lives in one IIFE in `index.html`. Reading it top to bottom:

**State.** One object `S` holds the current song: `bpm`, `sig` (`'3/4'`, `'4/4'`, `'6/8'`), per-signature `accents`, `left` and `right` ear settings (`note` `'q'|'e'|'s'`, `vol` 0 to 100, `mute`, `sound` `'beep'|'wood'|'tick'|'snap'`), `pad` (`on`, `key` 0 to 11 from C, `vol`), and `guide` (`vol`, `count`, `countTo` `'bar'|'4'`, `countIn`). `persist()` writes `{ "S": <the state object>, "songName": <loaded song name or ""> }` to `localStorage['splitmetro.state']` on every change; `restore()` reads `S` back out of that wrapper (a bare `S` with no wrapper is ignored), normalises old shapes, and always resets `pad.on` to false because audio cannot start without a tap.

**Tempo model.** BPM is always the quarter note, as in a DAW. In 3/4 and 4/4 a "count" is a quarter; in 6/8 the six counts are eighths (half a beat each) and the main beats fall on counts 1 and 4. `beatsPerBar()`, `countLen()` and `clicksPer(note, count)` encode this.

**Click engine.** Web Audio, lookahead scheduling: `scheduler()` runs every 25 ms and schedules everything due in the next 150 ms with exact `AudioContext` times, so timing never depends on JavaScript timers. `click(side, time, level)` synthesises each click from oscillators and filtered noise (no samples). The left ear is wired to channel 0 and the right to channel 1 of a `ChannelMergerNode`, so with earphones each ear hears only its own part. The level comes from the count's accent value: 0 for any count set to accent, 1 for a normal count, 2 for subdivision clicks and, in 6/8, for the normal in-between counts 2, 3, 5 and 6; pitches per side and level are in `FREQ`. The beat lights are driven from a visual event `queue` consumed in `draw()` on `requestAnimationFrame`.

**Accents.** Each count in the bar is accent (2), normal (1) or silent (0), tapped on the lights. Silent drops only the click on the count itself; an ear on 1/8 or 1/16 still clicks its subdivisions inside that count. Stored per signature in `S.accents`.

**Voice guide.** Clips from `guide-voices.js` are decoded once into `AudioBuffer`s (`ensureGuide()`) and started at exact times with `sayGuide(id, time, ...)`. Tapping a section name while running calls `callSection(id)`: the name on beat 1 of the next bar and, when `guide.count` is on, the count "2, 3, 4" on the remaining counts (all six in 6/8, or to 4 when `countTo` is `'4'`; `countTo` only matters in 6/8), so the section lands on the 1 after. With `guide.count` off only the name is spoken; the `count` button cycles off, count to the end of the bar, count to 4 (6/8 only). Press and hold (380 ms) calls `callSectionNow(id)`, which starts on the very next count. Tapping the same name again cancels (`cancelCue()`). The `Count` button is different: it has no clip of its own and goes through `callCount(now)`, which speaks one bar of numbers **per ear**: an ear on 1/4 hears "1 2 3 4", an ear on 1/8 or 1/16 hears "1 and 2 and ..."; these go through `guideSide.left/right` gains into the same merger channels as the clicks. Section calls and the START count-in (`guide.countIn`) play centred through `guideGain`.

**Pad.** `startPad()` builds a chord in the chosen key from detuned triangle and sine oscillators, a slow filter sweep, a stereo chorus and a convolution reverb; it is generated live, so it never loops. Tap a key to start, the lit key to stop. Always major.

**Screen and orientation.** A screen wake lock is requested whenever the app is open (`keepAwake()`, re-asked every 5 s and on touch). START also asks for landscape (`lockLandscape()`); the manifest sets landscape for the installed app.

**Layout.** Two CSS layouts: portrait (scrolling cards) and, under `@media (min-width:640px) and (orientation:landscape)`, a fixed three-column single screen that fills the viewport height with no scrolling (BPM, beats and song slots | ears and pad | guide). The landscape layout is the one used on stage.

**Songs.** `saveSong()` takes no argument: it reads the name from the `nameIn` input and the settings from `S`, and stores them in `localStorage['splitmetro.songs']` (a JSON array, see format below). Six quick slots (`localStorage['splitmetro.slots']`, an array of six song names) load a song with one tap. The Saved songs window (assign) lists, loads, deletes and assigns slots.

**QR sharing.** `Send` encodes all songs with `songToBytes()` into a compact binary (about 15 bytes per song plus the name), splits them into pages of at most 320 song bytes, and draws each page as a QR code whose text is `SM1.` + base64url([page, totalPages, ...songBytes]), where `page` is 1-based; the receiver rejects a code without that 2-byte header. Pages are self-contained and rotate every 2.5 s. `Receive` opens the camera in-app (`getUserMedia`), reads frames with `BarcodeDetector` when the phone has it and with jsQR otherwise (both are tried, because Android's detector can silently return nothing), collects every page, then `importSongs()` merges: same name replaces, new names are added, slots are untouched, and a confirm dialog shows the count first. `copy as text` / `paste code` carry the same payload without a camera, as a single page holding every song. Scanning is in-app on purpose: a QR that opened a URL would land in Safari, whose storage is separate from the installed app's.

## Song format

One entry of `localStorage['splitmetro.songs']`:

```json
{
  "name": "Great Are You Lord",
  "bpm": 72,
  "sig": "6/8",
  "accents": { "3/4": [2,1,1], "4/4": [2,1,1,1], "6/8": [2,1,1,1,1,1] },
  "left":  { "note": "q", "vol": 80, "mute": false, "sound": "beep" },
  "right": { "note": "e", "vol": 80, "mute": false, "sound": "wood" },
  "pad":   { "on": true, "key": 4, "mode": "major", "vol": 50 },
  "guide": { "vol": 80, "count": true, "countTo": "bar", "countIn": true },
  "accV": 2
}
```

`note` is `q` quarter, `e` eighth, `s` sixteenth. `key` counts semitones from C (4 = E). `accV` marks the accent format version. `loadSong()` normalises `sig` (old saves with `beatsPerBar`), `accents`, `left`/`right` (old saves with a numeric `sub`), `pad` and `guide`, and ignores unknown fields. `name` and `bpm` are required and copied as they are: a numeric `bpm` is clamped to 30 to 300, a missing or non-numeric `bpm` stops the click, and an entry without `name` breaks the saved songs list.

## Putting it in another app

Two workable routes, from least to most work.

**1. Embed the page as it is.** Serve the folder from your app's own origin (same scheme, host and port, for example under `/metronome/`) and show it in an `<iframe>`. Do not point the frame at the live copy or at a copy on another origin or port:

```html
<iframe src="/metronome/"
        allow="camera; autoplay; screen-wake-lock; clipboard-write"
        style="width:100%;height:100%;border:0"></iframe>
```

Notes:

- The app uses `confirm()` and `prompt()` for delete, for the import step after Receive or paste code, for the copy-as-text fallback and for the landscape Save button. Chrome and Edge block those dialogs inside cross-origin frames, so in a cross-origin embed those actions silently do nothing. That is why the frame must be same-origin.
- The `allow` list is what lets the camera, wake lock and clipboard work inside a frame (`microphone` is not needed, the camera request is video only).
- Audio can only start from a tap inside the frame (browser rule).
- The three-column stage layout only appears when the frame is at least 640 px wide and wider than it is tall (the media query is judged on the iframe's own size, not the phone's), so a tall panel gets the portrait scrolling layout. The landscape layout also fills the frame's height, so give the iframe a real height, not just `height:100%` inside a parent with no height.
- Saved songs go to localStorage under `splitmetro.*` keys, so on the same origin they sit next to your app's own storage; leave those keys alone.

**2. Lift the engine.** The script has no dependencies apart from the two QR libraries (only used by Send and Receive). Copy the audio sections whole rather than picking functions by name, because they lean on each other: `click` needs `noise`/`env`; `scheduleBeat` needs `clicksPer`/`accentOf`/`countLen`/`beatsPerBar`; `sayGuide` needs `playBuf`; the section calls need `nextBarTime`/`cancelCue`/`callPositions`/`sideUsesAnd`; `startPad` needs `ensurePad`/`makeIR`; and they all share the module globals (`ctx`, the gain nodes, `queue`/`cueEvents`/`pendingCue`, `guideBuf`/`guideLoad`, `FREQ`, `LOOKAHEAD`/`INTERVAL`). In order, the pieces are: the constants and `S` state at the top, `ensureAudio`/`applyVolumes`/`click`/`scheduleBeat`/`scheduler`/`start`/`stop` (the metronome), `ensureGuide`/`sayGuide`/`callSection`/`callSectionNow`/`callCount` plus `guide-voices.js` (the voice), and `startPad`/`stopPad` (the pad).

They reach the page through `$()` lookups of the control ids and the `render*` functions, and also through `flashCue`/`toast` (section buttons and the little message), `draw`/`lightBeat` (the dots and lights, started by `requestAnimationFrame` in `start()` and cleared with `querySelectorAll('.light')` in `stop()`), and `keepAwake`/`lockLandscape` (browser only). Replacing the UI means replacing or stubbing all of those. Keep the lookahead scheduler as is; it is what keeps the click steady while the UI is busy.

A chord chart app would most naturally drive it by setting `S.bpm`, `S.sig` and the ear notes from the chart, then calling `start()`/`stop()` and `callSection(id)` (or `callSectionNow(id)`) as the chart moves. `callSection()` only schedules a cue while the metronome is running (stopped, it just previews the clip), and calling it again with the same id while that cue is still pending cancels it, so do not re-fire it for the same section inside one bar. Section ids are the first element of each `SECTIONS` entry except `count`: `intro`, `verse`, `prechorus`, `chorus`, `bridge`, `tag`, `buildup`, `allin`, `break`, `drumonly`, `voiceonly`, `interlude`, `instrumental`, `outro`. `count` is the exception: it is not a clip, so drive it with `callCount(false)` (next bar) or `callCount(true)` (now) rather than `callSection('count')`, which would play only the centred "2, 3, 4" and skip the per-ear count.

## Voice clips

The clips were generated with the Windows built-in text-to-speech voice "Microsoft Mark" and trimmed so the onset sits at t = 0 (which is what makes the words land exactly on the beat). To replace a voice, record each word as 16 kHz mono WAV, trim leading silence, base64 it as a `data:audio/wav;base64,` URI and keep the same 21 keys in `guide-voices.js`: the section ids above except `count` (the Count button has no clip of its own; it speaks the numbers through `callCount`), plus `n1` to `n6` and `and`. Then bump the `?v=` on the file (see Shipping a change). If this ever becomes a public release, re-record the clips with a voice you have clear rights to.

## Phone notes

- iPhone: the silent switch mutes web audio. Safari ignores orientation lock, so Auto Rotate decides landscape. Camera and wake lock work in the installed app on iOS 16 and later.
- Android: Chrome installs it as a WebAPK; the manifest's landscape setting is honoured.
- Both: the first open after installing should be online so the service worker finishes caching; from then on it is fully offline.
