# Creative Studio Video

## Source

- User-supplied file: `IMG_5386.MP4`.
- Preserved byte-for-byte as `assets/creative/quwati-original.mp4` (not shipped in the app).
- Original SHA-256: `9f392ad8945073966cad747e6d8aab93f49faf04ed3974470eb14620988c8be6`.
- Original: 464 x 848 portrait, 7.9 seconds, 190 video frames, one audio track, 1,683,817 bytes.
- Variable frame timing uses a 30 Hz grid, approximately 24 frames per second on average.
- The supplied cinematic character remains centered. No character, branding, scene, color, or content was generated or replaced.

## Bundled Derivative

- `public/media/creative/quwati-preview.mp4`: 280 x 512 H.264 Main, 633,714 bytes.
- Complete 7.9-second video track, all 190 frames with original presentation timestamps.
- Audio removed entirely, not merely muted. No audio track or microphone/audio-session access is needed for this preview.
- Network-optimized MP4 with its `moov` atom before `mdat` for fast start.
- `public/media/creative/quwati-poster.jpg`: first preview frame at 280 x 512, JPEG quality 0.88.
- Use aspect-fill with a centered portrait tile; a width/height ratio near 0.547 preserves the full character.
- The original first and last poses differ. Loop playback should keep a rendered frame visible; the gallery's separate repeating layout is seamless, but no artificial crossfade or trim was baked into the user's video.

## Rebuild

Run from the frontend repository root on macOS with Xcode installed:

```sh
env DEVELOPER_DIR=/Users/mohned/Downloads/Xcode.app/Contents/Developer \
  xcrun swift scripts/prepare-studio-video.swift
```

Adjust `DEVELOPER_DIR` to the local Xcode installation if different. The script uses Apple's AVFoundation, CoreGraphics, and ImageIO, with no extra dependencies. SDK 26 reports deprecation notices for the backwards-compatible mutable video-composition preparation APIs; these are offline tooling notices, not app warnings.

The source file is never overwritten. Only the two generated preview files are replaced. Changing the source requires checking its timing grid and portrait crop again rather than assuming every future asset uses this clip's parameters.

## Validation

Decoded the original and derivative fully with AVAssetReader:

- Both contain 190 frames, begin at 0, and end at 7.9 seconds.
- Both have 142 frame gaps of 1/30 second and 47 gaps of 2/30 second.
- No new dropped frames, blank frames, or audio tracks in the derivative.
- Sampled mean frame brightness stayed between 45.87 and 54.72 out of 255, confirming no black or white flash frames were introduced.
- Poster and quarter/half/end frames were visually inspected for character visibility and correct orientation.
