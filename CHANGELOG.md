# Changelog

## 2.4.2

- New `wallpaper_order` setting: `tour` walks the calm wallpaper spots in order,
  `shuffle` hops between them randomly.
- Placement is clamped against the real painted block size with bar and edge
  insets, so a wide or wrapped line is never cut off at the screen border.

## 2.4.1

- Lyrics roam every calm area of the wallpaper (left, right, top, bottom) instead
  of a single fixed spot; the busy subject in the middle is skipped.
- The service publishes a coarse 24×14 energy grid, so the renderer scores spots
  against the actual text block instead of a fixed box.

## 2.4.0

- Wallpaper-aware placement: the wallpaper is analysed once per change with
  ImageMagick (`magick`/`convert`) or `ffmpeg`; nothing is recomputed while
  music plays, and the configured position stays in charge without either tool.
- New `wallpaper_aware` setting, translated into 8 languages, README updates.

## 2.3.2

- The hidden overlay unmaps its layer surface and stops its 16 ms frame clock,
  cutting idle cost from 16 to 4 scheduler ticks per 10 s.

## 2.3.1

- Fixed lyric lag, render stutter and pause handling.

## 2.3.0

- Multi-zone 3D dynamics and translations.
