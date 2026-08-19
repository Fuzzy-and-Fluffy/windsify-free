# Windsify Free

Windsify Free is the open-source Windows keyboard compatibility layer for
macOS. It provides familiar editing and app-switching shortcuts without
changing macOS Modifier Keys settings and without requiring Karabiner-Elements.

> **Just want it installed?** Get the signed, notarized build from
> **[windsify.com](https://windsify.com)** — one download, drag to Applications,
> done. The free keyboard layer below is yours forever; an optional one-time
> **Windsify Pro** adds Finder file operations, window management, and system
> shortcuts. Every download includes a 14-day Pro trial that falls back to Free.
>
> This repository is the buildable source of the free layer, for anyone who
> wants to read or compile it themselves.

Included behavior:

- Ctrl+C, X, V, Z and other ordinary Ctrl app shortcuts;
- Ctrl+Y redo;
- Home and End line navigation in text fields;
- Ctrl+Arrow and Ctrl+Delete word navigation and deletion;
- Alt+Tab, Alt+Shift+Tab, Alt+F4 and Ctrl+F4;
- Ctrl+Insert and Shift+Insert;
- Win+Space input-source switching;
- the Windows Application/Menu key opens the focused contextual menu;
- native Ctrl+Space, Ctrl+Tab, Shift+Arrow selection, secure input, remote
  desktop input, and Terminal Ctrl sequences including Ctrl+C.

Windsify Free does not include Finder automation, screenshot and system
shortcuts, Windows Terminal app actions, window management, drag-to-edge
snapping, multi-display layouts, licensing, or other Windsify Pro features.

The app processes key metadata locally through one macOS event tap. Because
macOS does not expose the standard Windows Menu key through that event tap, a
non-seizing HID listener additionally accepts only its standard `0x65` usage.
The app does not record typed text, use a kernel or DriverKit extension, or
transmit key events.

## Build and test

Requirements: macOS 15+, Xcode 26+, and
[XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
./scripts/verify.sh
```

Or generate the project directly:

```sh
xcodegen generate
xcodebuild -project WindsifyFree.xcodeproj \
  -scheme WindsifyFree \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO test
```

The first run requires macOS Accessibility permission. Menu-key support may
also require Input Monitoring permission. Review the source and build it
yourself, or visit [windsify.com](https://windsify.com) for official build
availability and Windsify Pro information.

## License

Copyright © 2026 Wondering Works.

Windsify Free is licensed under GNU GPL version 3 only. See [LICENSE](LICENSE).
The separately distributed Windsify Pro product is not included in this
repository.
