# Float

Picture-in-picture for your dev setup. Terminals and live web previews float as small cards on one transparent macOS window, so they fly around like a YouTube PiP but still behave like a single app in Stage Manager.

## Features
- **Real terminals** (SwiftTerm): your login shell, truecolor, mouse, runs `claude`, vim, htop
- **Web previews that scale, not squash**: pages render at a virtual 1440px (or 1280 / 834 / 390) viewport and zoom down to fit the card
- **PiP physics**: fling a card and it projects its landing spot and springs into a corner (Apple WWDC18 "Designing Fluid Interfaces" recipe)
- **Two-finger move**: swipe on a card's top strip, or ⌘ + two fingers anywhere
- **⌥Space launcher**: type `3000` for a preview, `~/code/app` for a terminal there, or `pnpm dev` to run it
- **Arrange All** tiles everything onto one screen

## Shortcuts
| Keys | Action |
|---|---|
| ⌥Space | Launcher |
| ⌥⌘T / ⌥⌘P | New terminal / preview |
| ⌥⌘A | Arrange all |
| ⌥⌘← / ⌥⌘→ | Cycle focus |
| ⌘+ / ⌘− | Terminal font size |

## Build
Requires macOS 14+, Xcode, and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
xcodegen generate
xcodebuild -scheme Float -destination 'platform=macOS' -derivedDataPath build build
open build/Build/Products/Debug/Float.app        # add --args --demo for a sample layout
```

Tunables (padding, spring bounce, default sizes, hotkeys) live in `Float/Core/Settings.swift`.
