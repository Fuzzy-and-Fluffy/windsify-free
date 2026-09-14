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
The app does not record typed text or use a kernel or DriverKit extension.

Free leaves recognized code editors and AI coding apps entirely native, based
only on their app identifiers; it does not inspect their terminal focus.
Pro adds Windows-style editing and terminal clipboard shortcuts in stable
desktop VS Code. Use **Set up VS Code terminal** and then **Developer: Reload
Window** in VS Code. Ctrl+C copies and clears a selection, or interrupts without
a selection; Ctrl+V pastes, with Ctrl+Shift+C/V also supported.
Setup backs up the default profile and adds removable Pro bridge bindings.
These bindings do not remap ordinary keys when Windsify translation is off,
Free is active, or native VS Code shortcuts are selected. Other recognized
editors remain native until their integrations are individually supported.
Known 1.4.2 terminal bindings are migrated with a backup; edited blocks require
manual review. Reload VS Code after migration, setup or removal.
Windsify reads local input structure only in Pro, never terminal or selection text.

## Shortcut Help

Click **Shortcut Help**, then **Test shortcut**, and press the combination once.
The app explains the result and can fill in an email draft with versions,
keyboard information, driver-advertised function-row mappings when available,
and that one test event. You can review the report before sending it. No report
is sent automatically and no typed text or background key history is collected.

Version 1.3.1 recognizes the dedicated Spotlight action key for Alt+F4 on
compatible Apple keyboards, alongside standard F4 and Fn+F4. Mission Control,
Dictation and Do Not Disturb action keys are recognized too; pressing a bare
action key keeps its native behavior. Function-key delivery varies by keyboard
and macOS, so Fn+Option+F4 remains the standard-function-key fallback.

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
