# Noctalia Lyrics 3D

**English** · [Türkçe](#türkçe)

3D desktop lyrics for Hyprland, aligned with the perspective of your wallpaper. This is a **Noctalia Shell v5** plugin: a Luau service owns MPRIS, LRCLIB, caching, filters and settings, while a separate Quickshell helper renders the real 3D scene — perspective, depth blur, mouse parallax and the calibration grid.

> **v5 note:** Noctalia v5 does not load QML plugins. The old v4 `manifest.json` / `Main.qml` / `Settings.qml` files are archived under `legacy-v4/` and are ignored by v5. The v5 entry point is `plugin.toml` plus the Luau entries.

## Supported languages

Settings labels and descriptions are translated for all languages below. Noctalia picks the file that matches your shell locale (`LANG`), and falls back to `translations/en.json` for anything missing.

| Language | Code | File |
|---|---|---|
| English | `en` | `translations/en.json` (fallback) |
| Türkçe | `tr` | `translations/tr.json` |
| Español | `es` | `translations/es.json` |
| Deutsch | `de` | `translations/de.json` |
| Français | `fr` | `translations/fr.json` |
| Русский | `ru` | `translations/ru.json` |
| Português | `pt` | `translations/pt.json` |
| 日本語 | `ja` | `translations/ja.json` |

Translation files are plain flat JSON keyed by the `label_key` / `description_key` values in `plugin.toml`. To add a language, copy `translations/en.json` to `translations/<code>.json`, translate the values, and keep the keys unchanged.

## Features

- **Real 3D scene:** independent X/Y/Z rotation, scale, position and true perspective.
- **Kinetic typography block:** a packed, multi-line poster block 420–520 px wide instead of a karaoke list. Short connectives stay small; long key words are clearly larger and heavier.
- **Word-by-word reveal:** the active line is split into words; each word grows with a 140 ms `OutCubic` easing and brightens as it is sung. Contours come from the built-in text outline and a single shared glow layer covers the line, so the scene keeps 60 FPS. Unsung words stay small and dim.
- **Contrast protection:** the active word core is forced to at least **4.5:1** contrast against the wallpaper average, with a cream/white core and album-art outer glow when needed.
- **Typography styles:** Modern Display, Script / Brush and Pixel / Retro; each changes family, weight, italics, letter spacing and capitalisation together.
- **Compact now-playing card (off by default):** 36 px cover, title, artist, live progress bar and elapsed/total time; the card sizes itself between 214 and 320 px. Enable `show_now_playing` to show it — the desktop stays lyric-only out of the box.
- **Intro and silence handling:** nothing is shown before the first line; gaps longer than 4 seconds hide the lyrics, and the scene fades and scales back in when vocals return.
- **Dynamic multi-zone placement:** with `dynamic_placement` on, the type block moves smoothly between safe screen zones on every new line, and `center_safe_zone` keeps the wallpaper's main subject visible.
- **Wallpaper-aware placement:** with `wallpaper_aware` on (default), the wallpaper is sampled once into a coarse energy grid, the lyrics roam the calm areas (left, right, top, bottom of the subject) and skip the busy middle instead of cycling straight over it. The analysis runs once per wallpaper and only repeats when the wallpaper itself changes, so nothing is recomputed while playing. Sampling is a single `magick`/`convert` (or `ffmpeg`) call that writes a 48×27 RGB frame; if none of them is installed the plugin simply keeps the configured position.
- **Four display modes:** `auto`, `kinetic`, `lineByLine` and `singleFocus`; Auto picks a mode from line length and timing.
- **Quick card controls:** hover or click the now-playing card to reveal Mode / Layout / Settings buttons.
- **Wallpaper-aware calibration:** live 3D grid, drag to move, X/Y/Z and scale sliders, saved per wallpaper in `perspectives.json`.
- **Event-driven playhead:** MPRIS position is read only on track changes, play/pause, seeks and a 2 s drift sync; the renderer dead-reckons the playhead from a 60 Hz local clock, so lines never trail the music.
- **Instant lyrics lookup:** an in-memory cache index resolves a track with one lookup, and `/api/get` plus `/api/search` run in parallel with a 2.5 s budget, so even a cold track is ready in a few hundred milliseconds.
- **Optional mouse parallax**, **universal MPRIS** support, **LRCLIB** with `/api/get` then `/api/search`, millisecond LRC parsing, plain-lyrics and instrumental fallbacks, and a **local cache** in `~/.cache/noctalia-lyrics/`.
- **Hyprland visibility rules:** `bottom` on the desktop, `overlay` for allowlisted windows or always-on, fully click-through.

## Requirements

| Component | Version / note |
|---|---|
| Arch Linux + Hyprland | Wayland session; `hyprctl` must work |
| Noctalia Shell | **v5** (`plugin_api` 51; tested with v5.5.0) |
| Quickshell | `qs` 0.3.x |
| `curl` | LRCLIB and remote album art |
| `playerctl` | Player list in the panel |
| Qt | 6.5+ (`QtQuick.Effects` / `MultiEffect`) |

LRCLIB needs no API key. Players must publish MPRIS metadata; in browsers the tab's media session has to be active.

## Installation (Noctalia v5)

```bash
mkdir -p ~/.local/share/noctalia/plugins
ln -sfn /path/to/noctalia-lyrics-3d \
  ~/.local/share/noctalia/plugins/noctalia-lyrics-3d

noctalia msg plugins enable alitura/noctalia-lyrics-3d
noctalia msg plugins list | grep lyrics-3d
```

Then open **Settings → Plugins → Noctalia Lyrics 3D**. Everything is configured there: appearance and typography, X/Y/Z angles, position and alignment preset, dynamic placement with the centre safe zone (`0–60 %`), display mode, now-playing card position, sync offset, source and window filters, visibility, theme colours, cache and per-wallpaper perspective saving.

Open the control panel with:

```bash
noctalia msg panel-toggle alitura/noctalia-lyrics-3d:controls
```

It shows the live track, sources, open windows, domain lists, visibility mode, and **3D Calibration** and **Refresh lyrics** buttons.

## Configuration

Every setting is also available through `noctalia msg config-set`; the table lists the defaults shipped in v2.3.0.

| Setting | Default | Purpose |
|---|---|---|
| `enabled` | `true` | Master switch for the overlay |
| `font_size` / `font_family` / `font_weight` | `38` / Noctalia UI / `600` | Base typography |
| `line_spacing` / `max_lines` | `12` / `9` | Line rhythm and how many lines the scene can hold |
| `width_percent` / `scene_scale` | `0.62` / `1.0` | Scene width (fraction of the monitor) and scale |
| `angle_x` / `angle_y` / `angle_z` | `0` / `0` / `0` | 3D rotation in degrees |
| `offset_x` / `offset_y` | `0` / `0` | Pixel-level nudge on top of the position |
| `position_preset` / `position_x` / `position_y` | `custom` / `50` / `78` | Alignment preset and percentage position |
| `dynamic_placement` | `true` | Move the type block across safe zones on each new line |
| `wallpaper_aware` | `true` | Analyse the wallpaper once and roam only its calm areas, skipping the subject |
| `wallpaper_order` | `tour` | `tour` walks the calm spots in order, `shuffle` hops between them randomly |
| `center_safe_zone` | `32` | Percentage of screen centre kept clear (`0–60`) |
| `display_mode` | `auto` | `auto`, `kinetic`, `lineByLine` or `singleFocus` |
| `typography_style` / `typography_max_width` | `modern` / `480` | Poster style and packed block width (`420–520`) |
| `depth_scale` / `blur_amount` / `active_glow` | `0.92` / `0.45` / `0.55` | Depth spread, depth blur and glow |
| `parallax` / `parallax_strength` | `false` / `1.2` | Optional mouse parallax |
| `show_now_playing` | `false` | Cover/title/artist pill above the lyrics |
| `show_next_line` | `false` | Dimmed preview of the next line |
| `now_playing_position` | `topCenter` | `topCenter`, `topLeft` or `topRight` |
| `sync_offset` | `0` ms | Lyric timing shift (`-500…+500`) |
| `filter_mode` | `allowAll` | `allowAll` or `whitelist` |
| `disabled_domains` / `custom_domains` | empty | Domain deny list and extra allowed sources |
| `disabled_players` / `allowed_windows` | empty | MPRIS identities and window classes |
| `visibility_mode` | `desktop` | `desktop`, `allowlist` or `always` |
| `hide_on_fullscreen` / `hide_on_pause` | `true` / `true` | Extra hiding rules |
| `monitor_scope` | `focused` | `focused` or `all` |
| `theme_mode` / `accent_blend` | `auto` / `0.65` | Colour source and accent mix |
| `custom_text_color` / `custom_accent_color` | `#f6f8ff` / `#8ab4f8` | Palette used in custom mode |
| `text_scrim` | `0.0` | Strength of the dark backing behind the text |
| `wallpaper_path_override` | empty | Alternate image for colour analysis |
| `show_plain_lyrics` / `cache_enabled` / `save_perspectives` | `true` | Plain fallback, LRCLIB cache, per-wallpaper angles |

## Calibration

1. Press **3D Calibration** in the panel.
2. Drag the type block, fine-tune with the arrows, and use the X/Y/Z, scale and X/Y position sliders. Top / Bottom / Left / Right Centre buttons align it instantly.
3. **Save** writes the values to the plugin settings (alignment preset becomes `custom`) and updates `perspectives.json` for the current wallpaper. **Cancel** reverts, **Reset** restores the starting values.

Saved perspectives are applied automatically when the wallpaper changes.

## Visibility rules

| Mode | Layer | Visible when |
|---|---|---|
| `desktop` (default) | `bottom` | On the desktop; hidden while a normal window has focus |
| `allowlist` | `overlay` in allowed windows, `bottom` on the desktop | Only while an `allowed_windows` match is focused, or on the desktop |
| `always` | `overlay` | Always |

`hide_on_fullscreen` and `hide_on_pause` add further conditions; `monitor_scope` limits drawing to the focused output or all outputs. `hide_on_pause` waits 1.5 s, then fades the overlay out over 300 ms and restores it in 180 ms as soon as playback resumes.

While the overlay is not shown, the renderer unmaps its layer surface and stops its 16 ms playhead clock. A hidden overlay therefore holds no full-screen surface and costs no compositor or GPU work, which keeps the frame rate intact while a fullscreen game or another window is in front.

Status cards follow the same rule. *Loading* stays up while LRCLIB is queried, but **Söz bulunamadı / Enstrümantal parça / LRCLIB hatası** is a 4.5 s toast: it fades out, then the surface unmaps instead of holding a static full-screen card (and its playhead clock) for the whole song. The toast reappears when the track changes.

### Source and domain filter

`filter_mode = allowAll` accepts every MPRIS source; `whitelist` only accepts built-in media domains (YouTube, Spotify, SoundCloud, Bandcamp, Deezer, Tidal, Apple Music, NetEase, QQ Music, Bilibili) plus `custom_domains`. `disabled_domains` always blocks. Browsers that do not publish `xesam:url` are hidden in whitelist mode.

## Architecture

```
plugin.toml           Noctalia v5 manifest (settings + service + panel + shortcut)
service.luau          Luau service: MPRIS, LRCLIB, LRC, cache, Hyprland, state.json
controls.luau         Noctalia v5 control panel
shortcut.luau         Control-centre shortcut
bin/renderer.sh       Starts the detached Quickshell helper
ui/Renderer.qml       Wayland layers, 3D scene, calibration, perspectives
ui/components/        LyricsRenderer3D, CalibrationOverlay, NowPlayingPill
ui/services/          AdaptiveThemeEngine
translations/         en, tr, es, de, fr, ru, pt, ja
legacy-v4/            Archived Noctalia v4 QML plugin
```

The built-in v5 `ui.*` tree only offers 2D affine transforms, so the architecture is hybrid: the Luau service owns data and settings and publishes `state.json`, the Quickshell helper renders the layers from it, and the panel/calibration send commands through `control.json`.

## File paths

| Path | Content |
|---|---|
| `~/.cache/noctalia-lyrics/state.json` | Live state published by the service |
| `~/.cache/noctalia-lyrics/index.json` | In-memory cache index (track key → cached file) |
| `~/.cache/noctalia-lyrics/control.json` | UI → service command queue |
| `~/.cache/noctalia-lyrics/perspectives.json` | Per-wallpaper X/Y/Z, scale and position |
| `~/.cache/noctalia-lyrics/renderer.log` | Quickshell output |
| `~/.cache/noctalia-lyrics/renderer.pid` | Helper process PID |
| `~/.cache/noctalia/noctalia.log` | Noctalia host log |

## Verification and troubleshooting

```bash
noctalia plugins lint .                                  # settings/entries check
noctalia msg plugins list | grep lyrics-3d               # loaded?
tail -50 ~/.cache/noctalia-lyrics/renderer.log           # QML errors
hyprctl layers | grep -A3 -B3 noctalia-lyrics            # layer present?
```

- **Panel opens but no layer:** check that `qs` is installed and `renderer.log` has no QML error. The helper exits when `state.json` is not updated for 8 seconds.
- **No lyrics:** is the player `Playing`? In `desktop` mode a focused window hides the layer — try `always`.
- **LRCLIB empty:** the track may be instrumental or missing; enable the plain-lyrics fallback.
- **Whitelist not working:** add the window class from the panel; matching is case-insensitive.

## License

MIT. See `LICENSE`.

---

# Türkçe

[English](#noctalia-lyrics-3d) · **Türkçe**

Hyprland masaüstünde, duvar kağıdının perspektifine oturan **3D şarkı sözleri**. Bu sürüm **Noctalia Shell v5** için Luau tabanlı bir eklentidir: MPRIS kaynaklarını ve LRCLIB sözlerini Luau servisi yönetir; gerçek 3D perspektif, derinlik bulanıklığı, fare paralaksı ve kalibrasyon ızgarası ayrı bir Quickshell yardımcı sürecinde çizilir.

> **v5 notu:** Noctalia v5 QML eklentisi yüklemez. Eski v4 `manifest.json` / `Main.qml` / `Settings.qml` dosyaları `legacy-v4/` altında arşivlenmiştir ve v5 tarafından okunmaz. v5 giriş noktası `plugin.toml` ve Luau dosyalarıdır.

## Desteklenen diller

Ayar etiketleri ve açıklamaları aşağıdaki tüm dillerde çevrilmiştir. Noctalia oturum yereline (`LANG`) uyan dosyayı yükler; eksik anahtarlarda `translations/en.json` yedeğine düşer.

| Dil | Kod | Dosya |
|---|---|---|
| İngilizce | `en` | `translations/en.json` (yedek) |
| Türkçe | `tr` | `translations/tr.json` |
| İspanyolca | `es` | `translations/es.json` |
| Almanca | `de` | `translations/de.json` |
| Fransızca | `fr` | `translations/fr.json` |
| Rusça | `ru` | `translations/ru.json` |
| Portekizce | `pt` | `translations/pt.json` |
| Japonca | `ja` | `translations/ja.json` |

Çeviri dosyaları düz JSON’dur ve `plugin.toml` içindeki `label_key` / `description_key` değerleriyle eşleşir. Yeni dil eklemek için `translations/en.json` dosyasını `translations/<kod>.json` olarak kopyalayın, değerleri çevirin, anahtarları değiştirmeyin.

## Özellikler

- **Gerçek 3D sahne:** X/Y/Z eksenlerinde bağımsız döndürme, ölçek, konum ve gerçek perspektif.
- **Kinetik tipografi bloğu:** Kalabalık karaoke listesi yerine 420–520 px genişliğinde, çok satırlı ve sıkı yerleşimli bir poster bloğu. Kısa bağlaç/ekler küçük, uzun ana kelimeler belirgin biçimde büyük ve kalın render edilir.
- **Kelime kelime canlanma:** Aktif satır kelimelere bölünür; her kelime sırası geldiğinde 140 ms `OutCubic` yumuşatmasıyla büyür ve parlaklığı artar. Konturlar yerleşik metin çizgisinden gelir; satırın tamamı tek bir ışıma katmanıyla çizildiği için sahne 60 FPS’de kalır. Söylenmemiş kelimeler küçük ve sönüktür.
- **Olay tabanlı oynatma konumu:** MPRIS konumu yalnızca parça değişiminde, duraklat/oynat’ta, sarımlarda ve 2 s’lik sapma senkronunda okunur; oynatma konumu 60 Hz yerel saatle ileri hesaplanır, böylece sözler müziğin gerisinde kalmaz.
- **Anında söz bulma:** Bellek içi önbellek indeksi parçayı tek aramada çözer; `/api/get` ve `/api/search` 2,5 s bütçeyle paralel çalışır, önbellekte olmayan parça bile birkaç yüz milisaniyede hazır olur.
- **Kontrast koruması:** Aktif kelime çekirdeği duvar kağıdı ortalamasına karşı en az **4.5:1** kontrasta zorlanır; düşük kontrastta krem/beyaz çekirdek ve albüm kapağı renginde dış ışıma kullanılır.
- **Tipografi stilleri:** Modern Display, Script / Brush ve Pixel / Retro arasında geçiş. Stil; font ailesi, ağırlık, italik, harf aralığı ve büyük harf davranışını birlikte değiştirir.
- **Kompakt now playing kartı (varsayılan kapalı):** 36 px kapak, şarkı adı, sanatçı, canlı ilerleme çubuğu ve geçen/toplam süre; içeriğe göre 214–320 px arasında boyutlanır. Göstermek için `show_now_playing` ayarını açın — masaüstü varsayılan olarak yalnızca sözleri gösterir.
- **İntro ve sessizlik kontrolü:** İlk söz satırından önce hiçbir söz gösterilmez. Satır arasında 4 saniyeden uzun enstrümantal boşluk varsa sözler gizlenir; vokal yeniden girdiğinde sahne fade-in ve ölçek animasyonuyla döner.
- **Dinamik çoklu bölge:** `dynamic_placement` açıkken her yeni satırda tipografi bloğu üst/sol/sağ/alt güvenli bölgeler arasında yumuşakça taşınır; `center_safe_zone` merkezdeki duvar kağıdı objesini korur. Blok kenardayken hafif yönlü 3D açı alır.
- **Duvar kağıdına duyarlı konum:** `wallpaper_aware` açıkken (varsayılan) duvar kağıdı bir kez kaba bir enerji ızgarasına örneklenir, sözler ortadaki objenin üstünden geçmeden boş alanlarda (solda, sağda, üstte, altta) gezinir. Analiz duvar kağıdı başına bir kez çalışır, yalnızca duvar kağıdı değişince tekrarlanır. Örnekleme tek bir `magick`/`convert` (veya `ffmpeg`) çağrısıyla 48×27 RGB kare üretir; hiçbiri kurulu değilse eklenti ayarlı konumu kullanmaya devam eder.
- **Dört gösterim modu:** `auto`, `kinetic`, `lineByLine` ve `singleFocus`; Auto satır uzunluğu ve süresine göre mod seçer.
- **Hızlı kart kontrolleri:** Now playing kartı fareyle üzerine gelince veya tıklanınca Mod / Yerleşim / Ayarlar düğmelerini açar.
- **Duvar kağıdına oturan kalibrasyon:** Canlı 3D ızgara, sürükleyerek taşıma, X/Y/Z ve ölçek kaydırıcıları. Kaydedilen perspektif `perspectives.json` içinde duvar kağıdı başına saklanır.
- **Evrensel MPRIS:** Brave, Firefox, Chromium, Spotify, VLC, mpv ve MPRIS yayan tüm oynatıcılar.
- **LRCLIB:** Önce `/api/get`, eşleşme yoksa `/api/search`; milisaniye hassasiyetinde LRC ayrıştırma; düz söz ve enstrümantal yedekleri; `~/.cache/noctalia-lyrics/` altında yerel önbellek.
- **Hyprland görünürlük kuralları:** Masaüstünde `bottom`, izinli pencere veya “her zaman” modunda `overlay` katmanı; tam tıklama geçirgenliği.
- **Noctalia v5 Settings entegrasyonu:** Tüm ayarlar yerleşik Eklentiler → Noctalia Lyrics 3D sayfasında; panel değişiklikleri `noctalia msg config-set` ile aynı ayarlara yazılır.

## Gereksinimler

| Bileşen | Sürüm / not |
|---|---|
| Arch Linux + Hyprland | Wayland oturumu; `hyprctl` çalışıyor olmalı |
| Noctalia Shell | **v5** (`plugin_api` 51; v5.5.0 ile test edildi) |
| Quickshell | `qs` 0.3.x |
| `curl` | LRCLIB ve uzak albüm kapağı |
| `playerctl` | Paneldeki oynatıcı listesi |
| Qt | 6.5+ (`QtQuick.Effects` / `MultiEffect`) |

LRCLIB için API anahtarı gerekmez. Oynatıcıların MPRIS metadata yayması gerekir; tarayıcılarda site sekmesi çalarken medya oturumunun etkin olması lazımdır.

## Kurulum (Noctalia v5)

```bash
mkdir -p ~/.local/share/noctalia/plugins
ln -sfn /tam/yol/noctalia-lyrics-3d \
  ~/.local/share/noctalia/plugins/noctalia-lyrics-3d

noctalia msg plugins enable alitura/noctalia-lyrics-3d
noctalia msg plugins list | grep lyrics-3d
```

Ardından **Ayarlar → Eklentiler → Noctalia Lyrics 3D** sayfasını açın. Görünüm ve tipografi, X/Y/Z açıları, konum ve hizalama ön ayarı, merkez koruma alanıyla (`%0–%60`) dinamik yerleşim, gösterim modu, şarkı kartı konumu, senkron gecikmesi, kaynak/pencere filtreleri, görünürlük, tema renkleri, önbellek ve duvar kağıdı başına perspektif kaydı burada yönetilir.

Kontrol panelini açmak için:

```bash
noctalia msg panel-toggle alitura/noctalia-lyrics-3d:controls
```

Panelde canlı parça, kaynaklar, açık pencereler, alan adı listeleri, görünürlük modu, **3D Kalibrasyon** ve **Sözleri yenile** düğmeleri vardır.

## Yapılandırma

Tüm ayarlar `noctalia msg config-set` ile de yazılabilir; tablo v2.3.0 varsayılanlarını listeler.

| Ayar | Varsayılan | Amaç |
|---|---|---|
| `enabled` | `true` | Katmanın ana anahtarı |
| `font_size` / `font_family` / `font_weight` | `38` / Noctalia UI / `600` | Temel tipografi |
| `line_spacing` / `max_lines` | `12` / `9` | Satır ritmi ve sahnedeki satır sayısı |
| `width_percent` / `scene_scale` | `0.62` / `1.0` | Sahne genişliği (monitör oranı) ve ölçek |
| `angle_x` / `angle_y` / `angle_z` | `0` / `0` / `0` | Derece cinsinden 3D dönüş |
| `offset_x` / `offset_y` | `0` / `0` | Konum üzerine piksel ince kaydırma |
| `position_preset` / `position_x` / `position_y` | `custom` / `50` / `78` | Hizalama ön ayarı ve yüzde konum |
| `dynamic_placement` | `true` | Her yeni satırda bloğu güvenli bölgeler arasında taşı |
| `wallpaper_aware` | `true` | Duvar kağıdını bir kez analiz et, sözler yalnızca boş alanlarda gezinsin |
| `wallpaper_order` | `tour` | `tour` sakin noktaları sırayla gezer, `shuffle` rastgele atlar |
| `center_safe_zone` | `32` | Merkezde boş bırakılan alan yüzdesi (`%0–%60`) |
| `display_mode` | `auto` | `auto`, `kinetic`, `lineByLine` veya `singleFocus` |
| `typography_style` / `typography_max_width` | `modern` / `480` | Poster stili ve blok genişliği (`420–520`) |
| `depth_scale` / `blur_amount` / `active_glow` | `0.92` / `0.45` / `0.55` | Derinlik aralığı, bulanıklık ve parıltı |
| `parallax` / `parallax_strength` | `false` / `1.2` | İsteğe bağlı fare paralaksı |
| `show_now_playing` | `false` | Sözlerin üstünde kapak/şarkı/sanatçı etiketi |
| `show_next_line` | `false` | Sonraki satırın sönük önizlemesi |
| `now_playing_position` | `topCenter` | `topCenter`, `topLeft` veya `topRight` |
| `sync_offset` | `0` ms | Söz zamanlaması kaydırması (`-500…+500`) |
| `filter_mode` | `allowAll` | `allowAll` veya `whitelist` |
| `disabled_domains` / `custom_domains` | boş | Alan adı engel listesi ve ek izinli kaynaklar |
| `disabled_players` / `allowed_windows` | boş | MPRIS kimlikleri ve pencere sınıfları |
| `visibility_mode` | `desktop` | `desktop`, `allowlist` veya `always` |
| `hide_on_fullscreen` / `hide_on_pause` | `true` / `true` | Ek gizleme kuralları |
| `monitor_scope` | `focused` | `focused` veya `all` |
| `theme_mode` / `accent_blend` | `auto` / `0.65` | Renk kaynağı ve vurgu karışımı |
| `custom_text_color` / `custom_accent_color` | `#f6f8ff` / `#8ab4f8` | Özel modda kullanılan palet |
| `text_scrim` | `0.0` | Yazı arkasındaki koyu zeminin gücü |
| `wallpaper_path_override` | boş | Renk analizi için alternatif görsel |
| `show_plain_lyrics` / `cache_enabled` / `save_perspectives` | `true` | Düz söz yedeği, LRCLIB önbelleği, duvar kağıdı başına açılar |

## Kalibrasyon

1. Panelden **3D Kalibrasyon** düğmesine basın.
2. Tipografi bloğunu fareyle sürükleyin, oklarla ince ayar yapın; X/Y/Z, ölçek ve X/Y konumu kaydırıcılarını kullanın. Üst / Alt / Sol / Sağ Orta düğmeleri hızlı hizalama sağlar.
3. **Kaydet** değerleri eklenti ayarlarına yazar (konum ön ayarı `custom` olur) ve geçerli duvar kağıdı için `perspectives.json` dosyasını günceller. **Vazgeç** geri alır, **Sıfırla** başlangıç değerlerine döner.

Duvar kağıdı değiştiğinde kayıtlı perspektif otomatik uygulanır.

## Görünürlük kuralları

| Mod | Katman | Ne zaman görünür |
|---|---|---|
| `desktop` (varsayılan) | `bottom` | Masaüstünde; normal bir pencere odaktayken gizli |
| `allowlist` | İzinli pencerede `overlay`, masaüstünde `bottom` | Yalnızca `allowed_windows` eşleşen pencere odaktayken veya masaüstünde |
| `always` | `overlay` | Her zaman |

`hide_on_fullscreen` ve `hide_on_pause` ek koşullar ekler; `monitor_scope` yalnızca odaklı çıkışta veya tüm çıkışlarda çizer. `hide_on_pause` 1,5 s bekler, katmanı 300 ms’de soldurur ve oynatma dönünce 180 ms’de geri getirir.

Katman görünmediği sürece renderer yüzeyini hiç map etmez ve 16 ms’lik playhead saatini durdurur. Gizli katman tam ekran bir yüzey tutmadığı için compositor ve GPU işi çıkarmaz; tam ekran oyun ya da başka bir pencere öndeyken kare hızı bozulmaz.

### Kaynak ve alan adı filtresi

`filter_mode = allowAll` tüm MPRIS kaynaklarını kabul eder; `whitelist` yalnızca yerleşik medya alan adlarını (YouTube, Spotify, SoundCloud, Bandcamp, Deezer, Tidal, Apple Music, NetEase, QQ Music, Bilibili) ve `custom_domains` listesini kabul eder. `disabled_domains` her modda engeller. `xesam:url` yaymayan tarayıcılar izin listesi modunda gizlenir.

## Mimari

```
plugin.toml           Noctalia v5 manifesti (settings + service + panel + shortcut)
service.luau          Luau servisi: MPRIS, LRCLIB, LRC, önbellek, Hyprland, state.json
controls.luau         Noctalia v5 kontrol paneli
shortcut.luau         Kontrol merkezi kısayolu
bin/renderer.sh       Quickshell yardımcı sürecini detached başlatır
ui/Renderer.qml       Wayland katmanları, 3D sahne, kalibrasyon, perspektifler
ui/components/        LyricsRenderer3D, CalibrationOverlay, NowPlayingPill
ui/services/          AdaptiveThemeEngine
translations/         en, tr, es, de, fr, ru, pt, ja
legacy-v4/            Arşivlenmiş Noctalia v4 QML eklentisi
```

Noctalia v5’in yerleşik `ui.*` ağacı yalnızca 2D affine dönüşümler sunduğu için mimari hibrittir: Luau servisi verinin ve ayarların tek sahibidir ve `state.json` yayınlar, Quickshell yardımcı süreci katmanları ondan çizer, panel ve kalibrasyon komutlarını `control.json` üzerinden gönderir.

## Dosya yolları

| Yol | İçerik |
|---|---|
| `~/.cache/noctalia-lyrics/state.json` | Servisin yayınladığı canlı durum |
| `~/.cache/noctalia-lyrics/index.json` | Bellek içi önbellek indeksi (parça anahtarı → dosya) |
| `~/.cache/noctalia-lyrics/control.json` | UI → servis komut kuyruğu |
| `~/.cache/noctalia-lyrics/perspectives.json` | Duvar kağıdı başına X/Y/Z, ölçek ve konum |
| `~/.cache/noctalia-lyrics/renderer.log` | Quickshell çıktısı |
| `~/.cache/noctalia-lyrics/renderer.pid` | Yardımcı süreç PID’i |
| `~/.cache/noctalia/noctalia.log` | Noctalia host logu |

## Doğrulama ve sorun giderme

```bash
noctalia plugins lint .                                  # ayar/giriş denetimi
noctalia msg plugins list | grep lyrics-3d               # yüklendi mi?
tail -50 ~/.cache/noctalia-lyrics/renderer.log           # QML hataları
hyprctl layers | grep -A3 -B3 noctalia-lyrics            # katman var mı?
```

- **Panel açılıyor ama katman yok:** `qs` kurulu mu, `renderer.log`’da QML hatası var mı bakın. Yardımcı süreç, `state.json` 8 saniye güncellenmezse kendini kapatır.
- **Sözler görünmüyor:** Oynatıcı `Playing` durumunda mı? `desktop` modunda odakta bir pencere varken katman gizlenir; `always` deneyin.
- **LRCLIB boş:** Parça enstrümantal olabilir veya LRCLIB’de kaydı yoktur; düz söz yedeğini açın.
- **İzin listesi çalışmıyor:** Pencere sınıfını panelden tek tıkla ekleyin; eşleşme büyük/küçük harf duyarsızdır.

## Lisans

MIT. Ayrıntılar için `LICENSE`.
