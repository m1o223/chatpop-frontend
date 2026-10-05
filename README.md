# ChatPop Frontend

Mobile-first ChatPop chat screen built with React, Vite, and TypeScript inside
the existing Capacitor iOS application, with real UIKit chat controls on iOS.
See [Native Chat Controls](NATIVE_UI.md) for APIs, files, and validation limits.
For real native email/password login, Keychain sessions, and Mac/iPhone LAN
configuration, see [Native Authentication](NATIVE_AUTH.md).
The supplied P/orbit artwork is the official identity. Use the shared brand
components and [Official Brand Assets](assets/brand/README.md); do not redraw or
replace the mark.

## Development

Use Node.js 24 LTS and npm.

```sh
npm ci
npm run dev
```

## Checks

```sh
npm run lint
npm run build
```

The build checks TypeScript and produces static files in `dist/`.
Use `npm run preview` to preview the production build locally.

## iOS

- App name: `ChatPop`
- Development bundle ID: `com.m1o223.chatpop`
- Capacitor: `8.5.2` (core, CLI, and iOS use the same version)
- Web output: `dist/`, bundled locally without a development server URL
- Native dependencies: Swift Package Manager
- Xcode project: `ios/App/App.xcodeproj`

```sh
npm run ios:sync
npm run ios:open
```

`ios:sync` builds the frontend, copies the web output, and updates iOS dependencies.
Run it after changing web source. Generated web assets and Capacitor JSON are
ignored by Git and recreated by this command after a fresh clone and `npm ci`.

To open the already generated project without Node on your shell path:

```sh
open ios/App/App.xcodeproj
```

Open the existing Xcode project, select its App scheme and your iPhone, then Run.
Keep the working bundle identifier, signing, team, and deployment settings.
Do not recreate the iOS platform or run `cap add ios`.

Reference: https://capacitorjs.com/docs/getting-started/environment-setup

The existing iOS application has been tested on an iPhone by the project owner.
This UI update is verified with frontend build/lint and browser interaction
checks. Keyboard viewport resize is simulated in browser tests; native keyboard,
safe areas, and status-bar contrast should also be checked on the real iPhone.

For the local Node runtime prepared alongside this checkout, this session can use:

```sh
export PATH="/Users/mohned/Desktop/ks/.tools/node-v24.21.0-darwin-x64/bin:$PATH"
```

Dependency audit reports three moderate entries in the development-only chain
`@capacitor/cli -> xcode -> uuid`. No forced downgrade or dependency override
has been applied. These packages are not included in the web bundle.

## Current scope

One chat screen with a menu, New Chat, model selection (Auto, ChatGPT, Claude,
Gemini, DeepSeek), scrolling conversation, expanding composer, attachments,
microphone, and Send. The appearance uses black, near-black, white, and light blue.

Messages, drafts, recent chats, and model selection stay in memory and reset on
reload. Send adds only the user's message, marked Local only. There are no AI
responses or chat network calls. Camera, Photos, Audio, File, and Microphone show
mock availability feedback without opening device permissions or uploading data.

The browser uses `useViewport` for keyboard resize/panning and CSS safe-area
insets. iOS uses a native UITextView and UIKeyboardLayoutGuide. UIKit communicates
its measured insets to React. The full-screen Menu stays in React and hides native
controls while open. The iOS model picker and attachment prompts use UIKit.

The native authentication screens connect to the separate existing backend;
the browser authentication preview and subscriptions remain unconnected.
Authentication uses native URLSession/Keychain, not the NativeChatControls
JavaScript bridge. Keep existing signing, team, Bundle Identifier, and deployment
target unchanged.
