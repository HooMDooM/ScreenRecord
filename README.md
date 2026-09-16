# ScreenRecord — macOS screen recorder & screenshot tool

Open-source **screen recorder** and **screenshot** app for **macOS**. Lives in the **menu bar** (system tray). Record the full display, a window, or a custom region to MP4; grab annotated screenshots with arrows, shapes, and text.

Search terms: macOS screen recording, screen capture, region capture, window recorder, 60 FPS, system audio, microphone, screenshot annotation, Snipping Tool alternative, CleanShot / iScreen Shoter style markup, global hotkeys.

- Record up to 60 FPS with system audio and microphone
- Capture a region and draw arrows, shapes, and text on the still frame
- Hotkeys (default: `⇧⌘S` for video, `⇧⌘A` for a screenshot)
- Output folder, quality, codec, and shortcuts are configurable

Requires **macOS 15** or later and **Xcode** (Swift toolchain).

## Install from source

1. Clone the repository:

```bash
git clone https://github.com/HooMDooM/ScreenRecord.git
cd ScreenRecord
```

2. Build the app:

```bash
./build.sh
```

3. Launch it:

```bash
open build/ScreenRecord.app
```

Or drag `build/ScreenRecord.app` into **Applications**.

If an Apple Development certificate is available, the script signs the app with it so Screen Recording permission survives rebuilds. Without a certificate it uses an ad-hoc signature.

## Permissions

On first launch macOS will ask for access:

1. **System Settings → Privacy & Security → Screen Recording** — enable ScreenRecord.
2. Microphone access, if you want voice in the recording.
3. Accessibility, if you want keystrokes shown in the video.

Relaunch the app if the system asks you to.

## Usage

Click the menu-bar icon to open the panel. Switch **Screenshot / Video** at the top, then pick the screen, a region, or a window.

**Video.** Choose a region or display, set FPS and audio, press REC. While recording, the tray shows Stop and Pause. Pressing `⇧⌘S` again stops the capture.

**Screenshot.** Drag a region, annotate the frozen frame, then copy (`⌘C`) or save. Copy puts the image on the clipboard on the first click.

Files are saved to `~/Movies` by default. Change the folder and other options in Settings (gear icon on the panel, or right-click the tray icon).

## Keywords

`macos` · `screen-recorder` · `screenshot` · `screen-capture` · `screencapturekit` · `menu-bar` · `swift` · `mp4` · `annotation` · `hotkeys`
