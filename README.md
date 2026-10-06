# Lumen

Live wallpapers for jailbroken iOS 7–10.

- **Bundle ID:** `com.lime.lumen`
- **Supported:** iOS 7.0 – 10.x (armv7, arm64)
- **Language:** Objective-C / Logos, built with [Theos](https://theos.dev)

## Features

- **Animated gradient** – a shimmering, slowly shifting gradient (lime by default).
- **Floating circles** – translucent bokeh-style circles drifting across the screen, with pulsing size and opacity. Works on top of both the gradient and video.
- **Video wallpapers** – use your own H.264 `.mp4` as a muted, looping wallpaper.
- **Color themes** – 8 presets (Lime, Mint, Cyan, Blue, Purple, Pink, Orange, Red) or any custom HEX color. The gradient and circles are generated from the chosen color.
- **Settings pane** – enable/disable the tweak, switch wallpaper type, change color, toggle circles, adjust circle count and speed.
- **Battery friendly** – animation and video pause automatically while the screen is off.
- **Live updates** – settings are applied immediately via Darwin notifications.

## Requirements

On the device:

- A jailbroken iOS 7–10 device
- Substrate (`mobilesubstrate`)
- `preferenceloader`

## Installation

### From a `.deb`

1. Download the latest `.deb` from the [Releases](../../releases) page.
2. Install it with your package manager, Filza, or over SSH:
```bash
   dpkg -i com.lime.lumen_*.deb
```
3. Respring.

### Build from source

See [Building](#building).

## Usage

Open **Settings → Lumen**.

| Option | Description |
| --- | --- |
| Enable Lumen | Master switch. When off, your normal wallpaper is shown. |
| Wallpaper type | `Gradient` or `Video`. |
| Video | Path to an `.mp4` file, e.g. `/var/mobile/Library/Lumen/video.mp4`. Falls back to the gradient if the file is missing. |
| Color scheme | One of 8 presets, or `Custom color`. |
| HEX | Used when the color scheme is `Custom color`, e.g. `#FF4DB8`. Invalid values fall back to lime. |
| Floating circles | Show/hide the drifting circles overlay. |
| Count | Number of circles (3–24). |
| Speed | Circle animation speed (0.5×–2.5×). |

> In **Video** mode the color scheme only affects the circles overlay; the video itself is not tinted.

### Using a video

1. Copy an H.264 `.mp4` to the device (SSH, Filza, etc.), for example to `/var/mobile/Library/Lumen/`.
2. In **Settings → Lumen**, set **Wallpaper type** to `Video`.
3. Enter the file path in the **Video** field.

Tips: use a resolution close to your screen size, keep the clip short and seamless for a clean loop, and remember that video playback costs more battery than the gradient.

### Manual reload

If you edit preferences from the command line, you can force a refresh:

```bash
notifyutil -p com.lime.lumen/reload
```

## Building

### 1. Install Theos

```bash
# macOS (Linux / WSL works too, see the Theos docs)
brew install ldid dpkg
export THEOS=~/theos
git clone --recursive https://github.com/theos/theos.git $THEOS
```

### 2. Get an SDK

```bash
git clone --depth=1 https://github.com/theos/sdks.git /tmp/sdks
cp -R /tmp/sdks/iPhoneOS10.3.sdk $THEOS/sdks/   # or iPhoneOS9.3.sdk
```

### 3. Build

```bash
git clone https://github.com/<your-username>/lumen.git
cd lumen
make package
```

To build and install directly on a device with OpenSSH:

```bash
export THEOS_DEVICE_IP=192.168.x.x
make package install
```

The resulting `.deb` is placed in `packages/`.

> **Note:** the public SDK has no `Preferences.framework` stub, so the preference bundle is linked with `-undefined dynamic_lookup`. The classes are resolved at runtime because Settings loads `Preferences.framework` itself.

## Project structure

```
lumen/
├── Makefile                  # tweak + prefs bundle (aggregate)
├── control                   # Debian package metadata
├── Lumen.plist               # injection filter (SpringBoard)
├── Tweak.xm                  # hooks SBFWallpaperView
├── LMNWallpaperView.h/.m     # wallpaper view: gradient, circles, video
└── lumenprefs/               # Settings pane (PreferenceLoader bundle)
    ├── Makefile
    ├── entry.plist
    ├── LMNRootListController.h/.m
    └── Resources/
        ├── Info.plist
        ├── Root.plist        # preference specifiers
        └── icon*.png
```

## How it works

Lumen hooks `SBFWallpaperView` in SpringBoard and adds an `LMNWallpaperView` on top of the system wallpaper. That view builds a Core Animation layer tree (gradient layer, circle layers with keyframe animations, or an `AVPlayerLayer` for video). Preferences are stored in the `com.lime.lumen` domain, and the settings pane posts the `com.lime.lumen/reload` Darwin notification so the wallpaper rebuilds itself on change. The `com.apple.springboard.hasBlankedScreen` notification is used to pause and resume everything when the screen turns off or on.

### Preference keys

Domain: `com.lime.lumen`

| Key | Type | Default | Description |
| --- | --- | --- | --- |
| `enabled` | bool | `true` | Master switch |
| `style` | string | `gradient` | `gradient` or `video` |
| `videoPath` | string | `""` | Path to the video file |
| `colorTheme` | string | `lime` | `lime`, `mint`, `cyan`, `blue`, `purple`, `pink`, `orange`, `red`, `custom` |
| `customColor` | string | `""` | HEX color used when `colorTheme` is `custom` |
| `circles` | bool | `true` | Show floating circles |
| `circleCount` | number | `10` | Number of circles (3–24) |
| `circleSpeed` | number | `1.0` | Speed multiplier (0.5–2.5) |

## Known limitations

- SpringBoard's wallpaper classes differ slightly between iOS versions, so behavior (for example on the lock screen vs. the home screen, or in blurred copies such as Control Center) may vary. Bug reports with your iOS version and device are welcome.
- Video playback in SpringBoard uses the GPU and will affect battery life.
- Video selection is currently by file path; a gallery picker is not implemented yet.
