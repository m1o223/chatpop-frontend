# Native Chat Controls

The existing Capacitor application now includes a Swift/UIKit control layer.
No additional npm packages, Swift packages, or third-party UI libraries are
required. The local plugin is named `NativeChatControls`.

## Rendering

- iOS 26+: `UIVisualEffectView` with Apple's `UIGlassEffect`. Interactive
  surfaces use `isInteractive`; the enabled Send surface uses the ChatPop tint.
- iOS 15-25: Apple's adaptive `UIBlurEffect(.systemThinMaterial)`. This is a native
  system material, not Liquid Glass. The deployment target remains unchanged.
- Browser: existing plain React controls, without simulated glass.
- An iOS bridge failure displays an explicit unavailable state with Retry.
  It does not silently substitute HTML controls for native controls.

Build the native code with Xcode 26 or newer and the iOS 26 SDK or newer.
Runtime availability checks protect older supported iOS versions; they do not
make the new APIs available to an older SDK.

## Files and Ownership

- `ios/App/App/ChatPopViewController.swift`: retains Capacitor's WKWebView and
  adds the native control layer as its UIKit sibling. Registers the plugin,
  presents the native model picker, and presents native attachment/mock alerts.
- `ios/App/App/NativeChatControlsPlugin.swift`: main-thread configuration,
  state updates, visibility, and native-to-JavaScript events.
- `ios/App/App/NativeChatControlsView.swift`: native materials, Menu/New Chat,
  model button, UITextView composer, attachment/microphone/Send controls,
  keyboard constraints, and measured layout insets.
- `ios/App/App/NativeModelViewController.swift`: native material model panel,
  provider descriptions, selection checkmark, scrolling, and dismissal.
- `ios/App/App/NativeAttachmentViewController.swift`: composer-anchored quick actions,
  native blurred backdrop, upward spring expansion, and downward collapse.
- `ios/App/App/SceneDelegate.swift`: instantiates `ChatPopViewController`.
- `ios/App/App/NativeSettingsViewController.swift`: grouped UIKit settings,
  device-local preferences, information placeholders, and native navigation.
- `ios/App/App/NativePaywallViewController.swift`: Plus/Pro and billing selectors,
  planned benefits, placeholder pricing, restore, and delayed visual close control.
- `ios/App/App.xcodeproj/project.pbxproj`: registers the Swift source files in
  the existing App target; build settings and signing are unchanged.
- `src/nativeChatControls.ts` and `src/useNativeChatControls.ts`: typed bridge,
  lifecycle, subscription cleanup, capability failure, and layout measurements.
- `src/App.tsx` and `src/App.css`: React conversation/state and native layout
  spacing. The browser-only controls are omitted on iOS.

## State and Keyboard

React owns chat history and the selected provider. Native draft/send events carry
a chat ID; Send also carries a message ID to prevent duplicate messages. Native
typing is authoritative until switching chats, so delayed React echoes cannot
replace the text or disturb marked text/caret position.

The composer uses `UITextView` and `UIKeyboardLayoutGuide`, including the bottom
safe area. UIKit reports its occupied top/bottom area to React so the conversation
does not sit under native controls. In cramped keyboard/landscape layouts, the
top native controls hide to leave room for input. Empty native overlay space
passes touches through to the web conversation.

The iOS Menu is an opaque UIKit full-screen layer presented through the existing
plugin; browser previews use React. A custom UIKit presentation keeps the chat
and its native controls mounted underneath. A 380ms horizontal page transition
enters from off-screen left and exits left; UIKit dismisses the Menu only after
the exit completes. Early close requests wait for presentation to finish, and
returning from Settings does not replay the entrance. Reduce Motion uses a
shorter 200ms slide. Browser previews retain their modal until the Web Animations
API exit finishes and reverse interrupted motion from its current position. Models
are supplied from `src/models.ts`. Attachments remain mock actions. The composer
microphone now uses native speech-to-text dictation; see
[NATIVE_DICTATION.md](NATIVE_DICTATION.md) for permissions, privacy, cleanup, and testing.
The separate voice orb remains a UI-only preview.

## Attachment Quick Actions

The composer `+` opens Camera, Photos, Audio, and File in that order above its native
button anchor. A 48-point native-material X aligns with the trigger. UIKit spring
animation lifts the rows from that origin; closing reverses their movement with
`beginFromCurrentState`, including when closing during the opening animation.
The native `UIVisualEffectView` backdrop blurs and dims the chat. Reduce Motion uses
a fade; Reduce Transparency uses an opaque dark backdrop. Compact layouts scroll
the actions instead of pushing them outside safe areas.

The keyboard dismisses without clearing the draft, and the menu tracks the final
composer position. X, the trigger area, outside taps, and accessibility Escape all
close it. Selection waits for the collapse and dismissal before invoking the
existing action handler. Camera, Photos, Audio, and File still display their explicit
not-connected placeholders; this UI change adds no capture, picker, upload, or
permissions. Browser previews use `AttachmentMenu.tsx` with the same order and
behavior, a plain dimming scrim, and no simulated native glass.

## Creative Studio Card

The existing Menu creation entry uses `NativeCreativeStudioCard.swift` on iOS
and `CreativeStudioCard.tsx` in browser previews. It is one card, not a carousel;
there are no artificial page indicators or auto-advance timers.

Five locally bundled JPEG concept images (`public/media/creative`) form an
unequal, clipped collage. Core Animation handles slow pan/zoom and a focal
crossfade without per-frame Swift/JavaScript work. The native implementation
downsamples with ImageIO on a background queue and shares a bounded image cache.
Menu visibility, scroll intersection, destination presentation and app activity
gate playback; paused Core Animation timelines resume at their existing phase.
Reduce Motion replaces spatial motion with a gentle dissolve; Low Power pauses
native playback. Browser previews use compositor transforms/opacity and pause
through IntersectionObserver and document visibility.

The entire card opens the Creative Studio availability screen. iOS 18+ uses
UIKit's source-view zoom transition; older iOS uses native modal presentation,
and Reduce Motion uses cross-dissolve. The destination honestly retains the
not-yet-available state: no image/video generation or backend integration is added.

## Settings and Subscription Preview

Settings and the paywall use a full-screen `UINavigationController` on iOS,
`UITableViewController(.insetGrouped)`, SF Symbols, native segmented controls,
alerts, and the existing Apple material helper. Settings opens from the menu;
the paywall opens from either Settings or the menu subscription card.

Display name, mock voice, and appearance persist in namespaced `UserDefaults`
on iOS, and localStorage in browser previews. Dark, Light, and System affect
native controls and the web conversation through the existing bridge's
`appearance` event. No account or entitlement is created by these preferences.

The paywall visually reveals its close control after 3.5 seconds. Back navigation,
accessibility escape, keyboard Escape, and a Not now action remain available.
VoiceOver users receive the native close control immediately. Prices and benefits
are placeholders; Continue and Restore only display explicit unavailable alerts.
Legal/support pages are unpublished placeholders, not production documents.
No StoreKit, authentication, TTS, or payment dependency has been added.
`PrivacyInfo.xcprivacy` declares app-local UserDefaults access (CA92.1).

## Native Authentication

Email/password authentication now connects to the real backend using native
URLSession and Keychain, without changing these screen layouts. See
[NATIVE_AUTH.md](NATIVE_AUTH.md) for API configuration, LAN setup, session
security, verification and the remaining real-iPhone checklist.

The signed-out Settings entry presents `NativeAuthViewController` inside a
separate full-screen native navigation controller. Back pops one screen;
X dismisses the entire authentication flow to Settings. Login and create-account
views use the real API; reset-password and legal views remain placeholders.

Native forms use UITextField email/secure entry, SF Symbols for password
visibility, and UIKeyboardLayoutGuide for the Continue control. Passwords are
cleared when a native form disappears or submits. Native signup follows the
backend's 12-128 character password policy. Tokens are stored only in Keychain;
passwords are transient request data and are never persisted or logged. Nothing
sensitive is sent over the bridge. The browser auth preview stays unconnected.
Agreement state lasts only for the current flow.

Apple's button uses AuthenticationServices' ASAuthorizationAppleIDButton purely
as a control; there is no ASAuthorizationController, OAuth SDK, capability, or
entitlement change. Google/Microsoft marks are bundled unmodified from their
official branding pages (see public/auth/ASSETS.md). The blue backdrop is a
branding gradient, not simulated glass; the Settings sign-in surface uses the
existing native Apple material helper.

## Verification and Running

```sh
npm run lint
npm run ios:sync
open ios/App/App.xcodeproj
```

This update contains Swift code: syncing web files alone is not sufficient.
Build and Run the existing App scheme in Xcode to install the updated binary on
the iPhone. Keep the current Development Team, signing, and Bundle Identifier.

Checks performed in the implementation environment:

- Frontend build/type check and lint.
- Swift parser checks (syntax only, not UIKit type checking).
- Xcode project/plist parsing and comparison of all existing build settings.
- Browser checks of the React/native bridge contract with a mock transport.
- Existing web Menu layout/direction and draft preservation checks.

Native compilation was attempted but blocked because this environment has only
Command Line Tools and no Xcode. No native visual, simulator, real-iPhone, keyboard,
or VoiceOver run is claimed. Verify those in Xcode before treating this integration
as device-validated, particularly rotation, IME input, large Dynamic Type, model
presentation/dismissal, and reopening the full-screen Menu with the keyboard up.

Official references:

- https://developer.apple.com/documentation/uikit/uiglasseffect
- https://developer.apple.com/documentation/uikit/uikeyboardlayoutguide
- https://capacitorjs.com/docs/ios/custom-code
