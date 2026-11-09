# Provider artwork

Weeklet uses the providers' actual shipped artwork to identify their quotas. The files are bundled locally, unchanged, and no artwork is requested over the network while the app runs. They are not part of Weeklet's original branding and do not imply endorsement.

| File | Official source | Display |
| --- | --- | --- |
| `Sources/Weeklet/Assets/ClaudeLogo.png` | Claude for macOS 4.23118.0, `Contents/Resources/TrayIconTemplate@3x.png` | Anthropic's monochrome tray mark, rendered as a system template |
| `Sources/Weeklet/Assets/CodexLogo.png` | ChatGPT for macOS 26.1103.60933 (25894), `Contents/Resources/icon-codex-dark-color.png` | OpenAI's Codex product icon in its original colors |

The files were copied byte-for-byte from the installed official applications on November 9, 2026. Their proportions and shapes are preserved. The Claude template is tinted orange (`#D97757`) by the UI, as a macOS template image normally is. The Codex icon is not recolored. Both appear in the popover and menu bar.

## Source checksums

```text
ClaudeLogo.png  eb3faa1ffaf88cf6692a98e7b608cd481a2d202eab096d9dc9efd89dbac60597
CodexLogo.png   69fb4384e161be8a20dcb94a9ac34aea4fbfaeb67514110a71e7b0732eccb0fc
```

Claude's marks belong to Anthropic and Codex's marks belong to OpenAI. Provider artwork retains its owners' applicable rights; it is not represented as Weeklet-authored or relicensed. See the [official Claude download](https://claude.com/download), [Codex product page](https://openai.com/codex/), and [OpenAI design guidelines](https://openai.com/brand/) for provider context.
