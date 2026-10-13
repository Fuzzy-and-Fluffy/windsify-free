# Interface localization

The official and Free targets bundle the same five complete tables: `en`,
`zh-Hans`, `zh-Hant`, `zh-Hant-TW`, and `zh-Hant-HK`. Complete regional tables
make SwiftUI locale-based lookup and explicit `L10n.text` lookup use the same
translation without requiring an application-specific fallback. Every table
must have English key parity and preserve all format placeholders. Do not
convert keys, shortcut names, product names, diagnostic fields, or OS errors.

## System selection and persistence

Follow System calls `Bundle.preferredLocalizations(from:forPreferences:)` using
the actual supported identifiers, then takes the first result. This follows
Apple's [TN2418 localization guidance](https://developer.apple.com/library/archive/technotes/tn2418/_index.html)
and avoids treating every `zh` preference as Simplified Chinese. Explicit
Taiwan and Hong Kong choices persist as `zh-Hant-TW` and `zh-Hant-HK`.
`zh-Hant` remains region-neutral, rather than becoming a Taiwan alias.

The existing `interfaceLanguage` and `interfaceLanguageInitialized` migration
is unchanged. Unknown stored values remain on disk and render English. Existing
installations keep English unless already choosing another language. The first
welcome includes both Chinese scripts but does not repeat after an upgrade.
Keyboard, window, trial, and license preferences remain independent.

Guide destinations are `/guides` for English, `/zh/guides` for Simplified,
`/zh-tw/guides` for Taiwan, and `/zh-hk/guides` for Hong Kong. The neutral
Traditional UI links to the Taiwan Traditional-script guide because there is
no neutral site route; this does not change its localization identity.

## Editorial glossary

The initial character-conversion scaffold was reviewed and edited for actual
UI context. Regional spelling is applied to values only. Apple terminology is
based on the [Taiwan](https://support.apple.com/zh-tw/102650) and
[Hong Kong](https://support.apple.com/zh-hk/102650) macOS shortcut references.

| Meaning | Taiwan | Hong Kong |
| --- | --- | --- |
| Keyboard shortcut | 快速鍵 | 快捷鍵 |
| Software update | 軟體更新 | 軟件更新 |
| Copy to clipboard | 拷貝 | 複製 |
| Folder | 檔案夾 | 資料夾 |
| User account | 使用者帳號 | 用戶帳戶 |
| File / document | 檔案 / 文件 | 檔案 / 文件 |
| Settings / clipboard / window | 設定 / 剪貼板 / 視窗 | 設定 / 剪貼板 / 視窗 |
| Accessibility | 輔助使用 | 輔助使用 |
| Terminal | 終端機 | 終端機 |
| Shortcut Help | 快速鍵說明 | 快捷鍵說明 |
| Screen recording | 螢幕錄製 | 螢幕錄製 |

Copy labels here refer to clipboard operations, including Finder copy-and-move.
A future Duplicate action must use `複製` in Taiwan; do not blindly rewrite
all instances of Copy or Duplicate. Product names such as Spotlight, Raycast,
VS Code, and Polar remain unchanged. The neutral table uses region-neutral
Traditional wording and remains a separate complete resource.

## Verification

Shared `AppLanguageTests` run in both target schemes and check preference
priority, script/region matching, explicit choices, unknown values, restart,
migration, guide routes, actual bundle directories, every table key and format
placeholder, explicit lookup, regional vocabulary, and dynamic service errors.
Check real SwiftUI menu, settings, onboarding, permission explanations, and
Shortcut Help in each language after building both targets. macOS-owned
permission dialogs use the system's localization and are outside these tables.
The Free source exporter includes all localization assets and this document.
