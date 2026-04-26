# Virtual Second Monitor for macOS

Virtual Second Monitor is a small macOS app that creates an OS-recognized virtual second display without attaching an external monitor.

It is designed for rehearsing and debugging multi-display workflows before a live setup. When a real projector, LED processor, capture card, or external display is not available, this app lets you verify second-screen behavior in advance: window placement, fullscreen output, 4K/8K layout assumptions, preview behavior, and display enumeration.

## Why

Live and installation work often depends on a second display, but the actual display hardware is not always available during development. This tool makes that gap easier to handle:

- Test second-display output before arriving at a venue.
- Check fullscreen behavior without connecting an external monitor.
- Verify that apps detect an additional display through macOS.
- Rehearse 4K and 8K output paths from a laptop-only setup.
- Preview the virtual display while keeping the workflow self-contained.

## 日本語での目的

外付けディスプレイ、プロジェクター、LED プロセッサーなどが手元にない状態でも、macOS からは実際のセカンドディスプレイとして認識される仮想ディスプレイを作成できます。ライブや展示の前に、出力先の検出、フルスクリーン表示、解像度設定、4K/8K レイアウト、プレビュー確認を事前にテストできるようにするためのツールです。

## Features

- Creates a macOS-recognized virtual display using `CGVirtualDisplay`.
- Native AppKit UI for creating and removing displays.
- Presets for FHD, QHD, WUXGA, portrait, 4K UHD, 5K Retina, and 8K UHD.
- Manual width, height, PPI, refresh rate, display name, and serial fields.
- Live preview panel for the virtual display.
- Preview refresh mode selector:
  - `Lightweight (auto)` reduces preview frequency at high resolutions.
  - `60 Hz` targets smoother preview updates when motion fidelity matters.
- Preview capture runs on a dedicated serial queue and skips overlapping frames, so high refresh settings do not block the app UI.
- Preview does not block on legacy preflight permission checks; it attempts ScreenCaptureKit capture and uses the actual capture result.
- Online display list inside the app.
- Shortcut to macOS Displays settings.
- CLI helpers for automation and quick testing.

## Requirements

- macOS with `CGVirtualDisplay` support.
- Apple Silicon or Intel Mac supported by the local macOS SDK.
- Xcode Command Line Tools.
- Node.js only for convenience scripts in `package.json`; the app itself is native.

Install Xcode Command Line Tools if needed:

```bash
xcode-select --install
```

## Quick Start

Build and open the app:

```bash
npm run start:app
```

`start:app` opens the existing app bundle and only builds it if missing. This avoids unnecessarily changing the app signature and resetting macOS privacy permissions.

Rebuild explicitly after source changes:

```bash
npm run rebuild:app
```

The app bundle is generated at:

```text
build/Virtual Second Monitor.app
```

In the app:

1. Choose a preset such as `Full HD`, `4K UHD`, or `8K UHD`.
2. Adjust name, resolution, PPI, refresh rate, or serial number if needed.
3. Click `Create Display`.
4. Open macOS Displays settings or your target app and use the new virtual display.
5. Click `Remove`, quit the app, or close the process to remove the virtual display.

## CLI Usage

Build the CLI:

```bash
npm run build:native
```

Start common presets:

```bash
npm run start:native   # 1920 x 1080
npm run start:4k       # 3840 x 2160 backing, HiDPI 1920 x 1080 mode
npm run start:8k       # 7680 x 4320 backing, HiDPI 3840 x 2160 mode
npm run start:hidpi    # 3840 x 2160 backing, HiDPI 1920 x 1080 mode
```

Custom run:

```bash
./build/virtual-second-monitor \
  --width 2560 \
  --height 1440 \
  --ppi 110 \
  --refresh 60 \
  --name "Debug QHD Display"
```

List online displays:

```bash
./build/virtual-second-monitor --list
```

## 4K and 8K Notes

4K and 8K presets use HiDPI backing. This makes macOS report the requested physical resolution while keeping the desktop coordinate space practical:

- 4K preset: reports `3840 x 2160`, UI looks like `1920 x 1080`.
- 8K preset: reports `7680 x 4320`, UI looks like `3840 x 2160`.

If you manually enter `3840 x 2160` or higher in the app, HiDPI is enabled automatically.

## Preview Notes

The preview uses ScreenCaptureKit when available, with a CoreGraphics window-composite fallback for older systems.

If the preview is blank:

1. Open macOS System Settings.
2. Go to Privacy & Security.
3. Grant Screen Recording permission to `Virtual Second Monitor.app`.
4. Click `Refresh Recording Permission` in the app, or restart the app. The button refreshes capture state even if macOS' legacy preflight check reports a stale value.

During development, repeated ad-hoc builds can make macOS privacy permissions appear unstable because the app's code signature changes. The build script automatically uses the first available `Apple Development` signing identity when present. To force a specific stable signing identity, pass it to the build script:

```bash
CODESIGN_IDENTITY="Apple Development: Your Name (TEAMID)" npm run build:app
```

If no `Apple Development` identity is available and `CODESIGN_IDENTITY` is not set, the build script falls back to ad-hoc signing.

## Design

The virtual display is process-scoped:

- `CGVirtualDisplay` creates the OS-recognized display.
- The app keeps the `CGVirtualDisplay` object alive while the display should exist.
- Releasing that object, closing the app, or quitting the process removes the display.

No kernel extension, DriverKit installation, launch daemon, or persistent system modification is used.

## Browser Simulator

A browser-only simulator remains available for quick visual debugging. It does not create an OS-recognized display.

```bash
npm run start:web
```

## Important Limitations

- This project uses macOS private `CGVirtualDisplay` APIs.
- It is intended for local development, rehearsals, and test automation.
- It is not intended for App Store distribution.
- If a workflow needs a persistent display across reboot/login, use a signed DriverKit/System Extension or a dedicated third-party display utility.

## License

No license has been specified yet. Public visibility does not grant reuse rights by itself.
