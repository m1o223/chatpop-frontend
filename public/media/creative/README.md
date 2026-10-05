# Creative Studio Showcase Media

`gallery.json` is the shared native/browser media configuration. It contains
eight original AI-generated images and one user-supplied video, not live user
generations. No generation API or remote media service is called by the app.

## Media

- `anime-cartographer.jpg`: original anime character and fantasy city.
- `architecture.jpg`: sculptural museum interior.
- `future-city.jpg`: cinematic future city and suspended gardens.
- `quwati-preview.mp4` / `quwati-poster.jpg`: the supplied `IMG_5386.MP4` as a
  silent 280 x 512 preview. See `assets/creative/video.md` for provenance,
  original preservation, and reproducible conversion.
- `cartoon-astronomer.jpg`: original animated-film-style astronomer character.
- `coast.jpg`: futuristic coastal environment.
- `portrait.jpg`: fictional cinematic android character.
- `design-atlas.jpg`: exploded botanical-pavilion concept illustration.
- `landscape.jpg`: glacial river environment.

Four new images were created with the built-in image-generation tool on
2026-09-16, then downsampled to 720px JPEGs at quality 82. Existing selected
images have an 880px maximum edge. Prompt descriptions are preserved in
`assets/creative/image-prompts.md`. No existing franchise character was
requested. `product.jpg` is no longer part of the showcase; it is retained
only because the unchanged destination preview still uses the legacy collage.

## Layout And Playback

Each item declares `id`, `type`, `source`, `aspectRatio`, `altText`, and
`columnSpan` (1 or 2). Video also declares `poster`. Paths are filenames relative
to this directory. Replace/add items here without editing the tile layout.
The current renderer supports one video asset with one active decoder.

Two identical masonry tracks, including their trailing gap, move upward by
exactly one cycle height every 20 seconds. Rounded card and tile masks clip
all content. This is translation of the tiles, not panning a large background.
Native Core Animation and browser compositor transforms handle movement.
One muted player is transferred between visible repeated video slots; posters
stay beneath the video. The supplied clip repeats without a blank reset frame;
its original first/last walking poses are not artificially matched.

Animation pauses while hidden, offscreen, interacting, or behind the
destination screen, retaining its phase. Native Low Power Mode pauses it.
Reduce Motion slows the cycle to 100 seconds; native video uses its poster.
Native thumbnails decode off the main thread into a bounded shared cache.

Default card height is 280pt native / 280px browser (previously 312pt / 324px).
Width, 28pt/px outer corners, title size, and existing tap destination remain.
Large Dynamic Type can increase height to preserve readability.

The current checkout hosts this card in Chats/Menu, not a horizontal feature
carousel. No host layout/navigation or unrelated Menu content was changed.
The gallery has no touch recognizers or scrollable interior, so it does not
consume a future parent carousel's horizontal gesture.

Run `npm run ios:sync` after changing media or `gallery.json`; Capacitor bundles
these local files into the existing iOS app.

Run `node --test tests/creative-media.test.mjs` for manifest, source-integrity,
poster, and bundle-budget regression checks.
