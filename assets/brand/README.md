# Official ChatPop artwork

`chatpop-original.jpg` is an unchanged copy of the supplied official logo,
`5859200548941271153.jpg` (1254 x 1254 pixels).

SHA-256: `d07bc1d914eeca1b80f32edd9ad0530f5628c2ca87d02a0bb677f8063567be25`

The white P, orbit, lighting, and colors are not redrawn or recolored. Asset
preparation removes 115 pixels of empty outer padding on each edge, retaining
the complete artwork in a centered 1024 x 1024 square. All smaller assets use
proportional high-quality downsampling and lossless PNG encoding, not repeated
JPEG recompression. The supplied JPEG remains the quality ceiling; PNG cannot
recover detail already lost in that source.

## Regenerate

From the frontend repository root on a Mac with Swift installed:

```sh
swift scripts/prepare-brand-assets.swift
npm run ios:sync
```

Generated assets:

- `ios/App/App/Assets.xcassets/AppIcon.appiconset/AppIcon-512@2x.png`: opaque
  1024px app icon. Xcode generates the system icon sizes. No baked-in rounded
  corners or text; iOS applies its own icon mask.
- `ios/App/App/Assets.xcassets/ChatPopLogo.imageset/`: 128/256/384px native mark.
- `public/brand/chatpop-logo.png`: 512px shared web mark.
- `public/brand/chatpop-icon.png`: 192px browser icon.

`ChatPopBrand` (UIKit) and `BrandMark` (React) share the supplied identity.
In light appearance, the unchanged image sits in a small rounded black badge
with a neutral hairline, not a large background rectangle. Semantic icons,
provider logos, and the voice visualization are not replaced with branding.

The existing `LaunchScreen.storyboard` uses a 128pt centered `ChatPopLogo` on
pure black in both appearances, with no artificial launch delay or spinner.

## Integration points

- Empty/new chat: `src/App.tsx` / `src/App.css`; hidden by the existing message
  list state once a conversation begins.
- Auth entry, login, and create account: `NativeAuthViewController.swift` and
  the browser fallback `src/AuthFlow.tsx` / `src/AuthFlow.css`.
- Plus/Pro: `NativePaywallViewController.swift` and `src/SettingsScreen.tsx`.
- About: `NativeSettingsViewController.swift` and `src/SettingsScreen.tsx` /
  `src/SettingsScreen.css`.
- Voice header: `NativeVoiceViewController.swift` and `src/VoiceModal.tsx` /
  `src/VoiceModal.css`; audio controls and visualization are unchanged.
- Shared rendering: `ios/App/App/ChatPopBrand.swift`, `src/BrandMark.tsx`,
  and `src/BrandMark.css`.
- Browser icon: `index.html`.

The existing Xcode project's only source-registration change adds
`ChatPopBrand.swift`. Bundle identifier, development team, signing,
deployment target, authentication logic, and Capacitor configuration are
unchanged. No additional packages are required.
