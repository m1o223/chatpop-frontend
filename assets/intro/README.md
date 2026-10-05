# ChatPop native launch intro

Approved timeline: supplied images #2 -> #3 -> #4 -> #6 -> #7 -> #10 -> #11 -> #12 -> #13.
Images #1, #5, #8, #9 are identity references only. `references/` preserves the supplied
JPEGs with production-readable names; these are design sources, not runtime frames.
The existing `ChatPopLogo` asset is the single normalized runtime texture. It keeps
the original P/star/orbit proportions and avoids generated-frame shape flicker.
CHATPOP is a native white, bold 38-point system-font label, not image text.
The logo image view is 148 points square, reduced only where needed to retain
16-point outer margins on narrow phones. The original image proportions are unchanged.

Implementation: `ChatPopIntroView` in `ios/App/App/ChatPopBrand.swift`, installed
above the existing app by `ChatPopViewController`. No new package or bridge.
The static LaunchScreen is black so it joins the initial black pose without a logo jump.

Timeline (seconds, total 3.95):
- 0.00-0.20: black
- 0.20-0.95: left-to-center logo entry
- 0.95-1.20: small 1.03/0.99/1.00 settle
- 1.20-2.10: logo settles into the lockup; native left-to-right wordmark mask opens
- 2.10-3.05: full brand hold (0.95 seconds)
- 3.05-3.85: wordmark retracts toward the logo
- 3.45-3.95: logo exits left
- 3.05-3.95: brand scales down to 97% while the entire black overlay fades,
  revealing the already-initializing application underneath without a black gap

Core Animation interpolates position, scale, opacity and mask width on one timeline.
No image swaps, video, extra blur, particles or colored background are used. Only the
original asset's local blue orbit glow remains. Reduce Motion uses opacity-only
branding with the same bounded duration. Backgrounding cancels and removes the intro;
navigation and foreground returns do not replay it. The process-level launch guard
also prevents recreation of the main controller from replaying it.

The animation never waits on network/authentication or web initialization. A slow app
startup does not freeze or lengthen it. The runtime logo is loaded before animation.
Reference JPEGs are deliberately not duplicated into the shipped asset catalog.
