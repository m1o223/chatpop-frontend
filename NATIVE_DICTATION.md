# Native Composer Dictation

The microphone inside the iOS composer opens a UIKit bottom sheet for speech-to-text.
It is separate from the existing voice orb. The orb and normal typed-message Send
behavior are unchanged. This feature does not call the ChatPop backend.

## Implementation

- `NativeDictationSession.swift`: `AVAudioSession`, `AVAudioEngine`,
  `SFSpeechRecognizer`, and `SFSpeechAudioBufferRecognitionRequest` with partial results.
- `NativeDictationViewController.swift`: native sheet, live scrollable transcript,
  metered waveform, permission/error recovery, Cancel and Insert.
- `DictationText.swift`: append without replacing the existing draft or its whitespace.
- `NativeChatControlsView.swift`: updates the `UITextView` and emits the existing
  `draft` event, never `send`, on insertion. UTF-16 caret positioning supports Unicode.
- `ChatPopViewController.swift`: presents one sheet at a time and captures the chat
  ID so dictation cannot accidentally insert into a different conversation.

No new Capacitor plugin, npm package, Swift package, signing capability, or entitlement
is required. The new Swift files are registered in the existing App target.

## Permissions and Privacy

`Info.plist` contains `NSMicrophoneUsageDescription` and
`NSSpeechRecognitionUsageDescription`. Both permissions must be granted before audio
capture starts. Permission denial is recoverable through iOS Settings; returning
offers Try Again instead of restarting microphone capture automatically.

On-device recognition is required when the selected recognizer supports it. Otherwise,
Apple's Speech service may process audio under its system authorization. The permission
description explicitly discloses this. Audio is not recorded to files, logged, or sent
to the ChatPop backend. Transcripts are only committed to the existing draft on Insert.

Recognition uses `Locale.current`. The sheet and session accept an injected `Locale`
for a future explicit language preference. Unsupported locales show a friendly error;
there is no silent English-only fallback.

## Metering and Cleanup

The audio tap calculates RMS across actual microphone PCM channels, converts it to
decibels (`20 * log10(RMS)`), maps -60 to -10 dB onto 0...1, and applies attack/release
smoothing. Updates are limited to 20 Hz. The waveform draws those measurements as a
short history of bars. It has no looping or randomized animation.
`PrivacyInfo.xcprivacy` declares reason `35F9.1` for the monotonic elapsed-time API
used by metering and silence/capture deadlines. These timing values stay on-device.

Insert, Cancel, swipe dismissal, backgrounding, interruptions, route changes, and
audio-service resets stop capture. Cleanup closes the audio-buffer append gate,
stops/removes the engine tap, ends the request, cancels/releases the task, deactivates
the audio session with notification to other audio apps, and restores its previous
category/mode/options. Run identifiers reject stale callbacks after cancellation.

Capture finishes after 12 seconds without recognized text, 5 seconds of inactivity
after a transcript, or 55 seconds total. Final results get up to 3 seconds to finish;
available text remains insertable. Opening a new sheet always starts a fresh session.

## Build and Checks

```sh
npm run ios:sync
sh scripts/test-dictation.sh
open ios/App/App.xcodeproj
```

Build and Run the existing App scheme; syncing web assets alone cannot install new
Swift code. Do not recreate the platform or change signing settings.

Text-append regression tests cover empty drafts, whitespace, newlines, and Unicode.
Simulator permission/UI checks are not a substitute for a real microphone test.

Implementation verification:

- Frontend build, lint, and Capacitor sync succeeded.
- Native simulator and signed iPhone builds succeeded; the existing iPhone app was
  updated and launched without changing signing, team, or bundle identifier.
- Nine append regression cases passed.
- Native simulator checks passed for permission denial, duplicate-presentation
  prevention, repeated cancellation, draft preservation, partial transcript display,
  and Insert without Send. Transcript and meter values in these UI checks were injected
  only by an external temporary test harness, never by the production app.
- Actual live speech, real microphone metering, and granting/revoking permissions on
  the physical iPhone still require the hands-on acceptance checks below. Installation
  alone does not establish that recognition worked on the device.

Real-iPhone acceptance checklist:

1. Tap the composer microphone (not the voice orb); grant both iOS prompts.
2. Speak a short phrase. Confirm partial text and volume-responsive bars.
3. Insert. Confirm editable composer text and no automatically sent message.
4. Repeat with existing text; verify sensible spacing and preservation of the draft.
5. Reopen, speak, and use X or swipe down. Confirm the draft remains unchanged and
   the microphone indicator turns off.
6. Repeat several times, including a silent attempt and background/foreground.
7. Deny microphone and Speech Recognition separately in iOS Settings. Confirm friendly
   recovery, no crash, and disabled Insert when there is no transcript.
8. Re-enable permission, return, and tap Try Again. Test the device language, including
   Arabic or Swedish where supported by Apple's installed recognition resources.

References: [Apple live-audio speech requests](https://developer.apple.com/documentation/speech/sfspeechaudiobufferrecognitionrequest),
[speech authorization](https://developer.apple.com/documentation/speech/asking-permission-to-use-speech-recognition),
and [native sheets](https://developer.apple.com/documentation/uikit/uisheetpresentationcontroller).
The elapsed-time privacy reason follows
[Apple's required-reason API documentation](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype).
