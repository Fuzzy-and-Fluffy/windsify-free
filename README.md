# Windsify Free

Windsify Free is the open-source Windows keyboard compatibility layer for
macOS. It provides familiar editing and app-switching shortcuts without
changing macOS Modifier Keys settings and without requiring Karabiner-Elements.

Included behavior:

- Ctrl+C, X, V, Z and other ordinary Ctrl app shortcuts;
- Ctrl+Y redo;
- Home and End line navigation in text fields;
- Ctrl+Arrow and Ctrl+Delete word navigation and deletion;
- Alt+Tab, Alt+Shift+Tab, Alt+F4 and Ctrl+F4;
- Ctrl+Insert and Shift+Insert;
- Win+Space input-source switching;
- native Ctrl+Space, Ctrl+Tab, Shift+Arrow selection, secure input, remote
  desktop input, and Terminal Ctrl sequences including Ctrl+C.

Windsify Free does not include Finder automation, screenshot and system
shortcuts, Windows Terminal app actions, window management, drag-to-edge
snapping, multi-display layouts, licensing, or other Windsify Pro features.

The app processes key metadata locally through one macOS event tap. It does
not record typed text, use a kernel or DriverKit extension, or transmit key
events.

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

The first run requires macOS Accessibility permission. Review the source and
build it yourself, or visit [windsify.com](https://windsify.com) for official
build availability and Windsify Pro information.

## License

Copyright © 2026 EZZY BOOKS PTY LTD.

Windsify Free is licensed under GNU GPL version 3 only. See [LICENSE](LICENSE).
The separately distributed Windsify Pro product is not included in this
repository.
