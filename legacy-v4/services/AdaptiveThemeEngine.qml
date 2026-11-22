// services/AdaptiveThemeEngine.qml
// Wallpaper-aware colour engine. Quantizes the active wallpaper (Noctalia
// wallpaper.toml, swww/awww, hyprpaper or a manual override) and the current
// album art, then derives contrast-safe text, accent, glow and shadow colours.

import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: root

    // ---------------------------------------------------------------- config
    property bool active: true
    property string home: ""
    property string cacheDir: ""
    property string wallpaperOverride: ""
    property string artUrl: ""
    property string mode: "auto"             // auto | wallpaper | album | custom
    property real blend: 0.65
    property string customTextColor: "#f6f8ff"
    property string customAccentColor: "#8ab4f8"

    // --------------------------------------------------------------- outputs
    property string wallpaperPath: ""
    property string wallpaperKey: ""
    property var wallpaperColors: []
    property var albumColors: []
    property var walColors: []
    property var palette: []
    property string wallpaperAccent: ""
    property string albumAccent: ""
    property string accentColor: "#8ab4f8"
    property string textColor: "#f6f8ff"
    property string mutedColor: "#b9c5da"
    property string glowColor: "#8ab4f8"
    property string shadowColor: "#000000"
    property string scrimColor: "#000000"
    property real shadowOpacity: 0.85
    property bool lightBackground: false
    property real backgroundLuminance: 0
    property real contrastRatio: 0
    property string sourceLabel: "default"
    property string albumImagePath: ""

    readonly property var fallbackPalette: [
        "#0b1020", "#17233d", "#2b3f66", "#8ab4f8", "#f6f8ff"
    ]

    // -------------------------------------------------------------- internal
    property string artTarget: ""

    Component.onCompleted: {
        if (root.active)
            root.detectWallpaper()
        root.scheduleRecompute()
    }

    onActiveChanged: {
        if (root.active)
            root.detectWallpaper()
    }
    onWallpaperOverrideChanged: {
        if (root.wallpaperOverride)
            root.setWallpaper(root.wallpaperOverride)
        else
            root.detectWallpaper()
    }
    onArtUrlChanged: artDebounce.restart()
    onBlendChanged: root.scheduleRecompute()
    onModeChanged: root.scheduleRecompute()
    onCustomTextColorChanged: root.scheduleRecompute()
    onCustomAccentColorChanged: root.scheduleRecompute()

    Timer {
        interval: 7000
        repeat: true
        running: root.active
        onTriggered: {
            if (!root.wallpaperOverride)
                root.detectWallpaper()
        }
    }

    Timer {
        id: paletteTimer
        interval: 90
        repeat: false
        onTriggered: root.recompute()
    }

    Timer {
        id: artDebounce
        interval: 180
        repeat: false
        onTriggered: root.resolveArt()
    }

    Process {
        id: wallpaperProbe
        command: ["sh", "-c", "out=\"\"; "
            + "if [ -f \"$HOME/.config/noctalia/wallpaper.toml\" ]; then "
            + "out=$(awk -F'\"' '/^[[:space:]]*path[[:space:]]*=/{print $2; exit}' \"$HOME/.config/noctalia/wallpaper.toml\"); fi; "
            + "if [ -z \"$out\" ] && command -v swww >/dev/null 2>&1; then "
            + "out=$(swww query 2>/dev/null | sed -n 's/.*currently displaying: image: //p' | head -n 1); fi; "
            + "if [ -z \"$out\" ] && command -v awww >/dev/null 2>&1; then "
            + "out=$(awww query 2>/dev/null | sed -n 's/.*currently displaying: image: //p' | head -n 1); fi; "
            + "if [ -z \"$out\" ] && command -v hyprctl >/dev/null 2>&1; then "
            + "out=$(hyprctl hyprpaper listloaded 2>/dev/null | head -n 1); fi; "
            + "printf '%s' \"$out\""]
        stdout: StdioCollector {
            id: wallpaperOutput
            onStreamFinished: root.handleWallpaperProbe(wallpaperOutput.text)
        }
        stderr: StdioCollector {}
    }

    Process {
        id: artDownload
        command: []
        stdout: StdioCollector {}
        stderr: StdioCollector {}
        onExited: function (exitCode, exitStatus) {
            if (exitCode === 0 && root.artTarget.length > 0) {
                root.albumImagePath = root.artTarget
                root.sourceLabel = "wallpaper + album"
            } else {
                root.albumImagePath = ""
                root.scheduleRecompute()
            }
        }
    }

    // Native Qt colour quantization: no ImageMagick dependency.
    ColorQuantizer {
        id: wallpaperQuantizer
        source: root.wallpaperPath ? root.fileUrl(root.wallpaperPath) : ""
        depth: 2
        rescaleSize: 64
        onColorsChanged: root.collectWallpaperColors()
    }

    ColorQuantizer {
        id: albumQuantizer
        source: root.albumImagePath ? root.fileUrl(root.albumImagePath) : ""
        depth: 2
        rescaleSize: 48
        onColorsChanged: root.collectAlbumColors()
    }

    // Optional Wallust / pywal palette when no image can be read.
    FileView {
        id: walFile
        printErrors: false
        watchChanges: true
        path: root.home ? root.home + "/.cache/wal/colors.json" : ""
        onLoaded: root.parseWal(walFile.text())
        onFileChanged: walFile.reload()
    }

    // ---------------------------------------------------------------- public
    function detectWallpaper() {
        if (root.wallpaperOverride)
            return
        if (wallpaperProbe.running)
            return
        wallpaperProbe.running = true
    }

    function refresh() {
        root.detectWallpaper()
        root.collectWallpaperColors()
        root.collectAlbumColors()
    }

    function setWallpaper(path) {
        var next = root.stripFileUrl(String(path || "").trim())
        if (!next)
            return
        if (next === root.wallpaperPath) {
            root.scheduleRecompute()
            return
        }
        root.wallpaperPath = next
        root.wallpaperKey = root.hash(next)
        root.wallpaperColors = []
        root.wallpaperAccent = ""
        root.sourceLabel = "wallpaper"
        root.scheduleRecompute()
    }

    // --------------------------------------------------------------- helpers
    function stripFileUrl(value) {
        var text = String(value || "")
        if (text.indexOf("file://") === 0)
            text = text.substring(7)
        try {
            text = decodeURIComponent(text)
        } catch (error) {
            // Keep the raw path if it contains a stray percent sign.
        }
        return text
    }

    function fileUrl(path) {
        var text = String(path || "")
        if (!text)
            return ""
        if (text.indexOf("file://") === 0)
            return text
        var encoded = text.split("/").map(function (part) {
            return encodeURIComponent(part)
        }).join("/")
        return "file://" + encoded
    }

    function hash(value) {
        var h = 5381
        var text = String(value || "")
        for (var i = 0; i < text.length; i++)
            h = ((h * 33) ^ text.charCodeAt(i)) >>> 0
        return h.toString(16)
    }

    function handleWallpaperProbe(text) {
        var value = String(text || "").trim().split(/\r?\n/)[0].trim()
        if (!value)
            return
        if (value.indexOf("file://") === 0)
            value = root.stripFileUrl(value)
        root.setWallpaper(value)
    }

    function qcolorToHex(color) {
        if (!color)
            return ""
        if (color.r === undefined)
            return String(color)
        return root.rgbToHex(
            Math.round(Number(color.r) * 255),
            Math.round(Number(color.g) * 255),
            Math.round(Number(color.b) * 255)
        )
    }

    function collectColors(list) {
        var result = []
        if (!list)
            return result
        for (var i = 0; i < list.length; i++) {
            var color = list[i]
            if (!color)
                continue
            if (color.a !== undefined && Number(color.a) < 0.4)
                continue
            var hex = root.qcolorToHex(color)
            if (root.validHex(hex) && result.indexOf(hex) < 0)
                result.push(hex)
            if (result.length >= 12)
                break
        }
        return result
    }

    function collectWallpaperColors() {
        var colors = root.collectColors(wallpaperQuantizer.colors)
        if (colors.length === 0) {
            root.scheduleRecompute()
            return
        }
        root.wallpaperColors = colors
        root.wallpaperAccent = root.pickAccent(colors)
        root.sourceLabel = "wallpaper"
        root.scheduleRecompute()
    }

    function collectAlbumColors() {
        var colors = root.collectColors(albumQuantizer.colors)
        if (colors.length === 0) {
            root.albumColors = []
            root.albumAccent = ""
            root.scheduleRecompute()
            return
        }
        root.albumColors = colors
        root.albumAccent = root.pickAccent(colors)
        root.sourceLabel = root.wallpaperPath ? "wallpaper + album" : "album"
        root.scheduleRecompute()
    }

    function resolveArt() {
        var url = String(root.artUrl || "").trim()
        if (!url) {
            root.albumImagePath = ""
            root.albumColors = []
            root.albumAccent = ""
            root.scheduleRecompute()
            return
        }

        if (url.indexOf("file://") === 0 || (url.indexOf("http://") !== 0
                && url.indexOf("https://") !== 0 && url.indexOf("data:") !== 0)) {
            root.albumImagePath = root.stripFileUrl(url)
            return
        }

        if (url.indexOf("http://") === 0 || url.indexOf("https://") === 0) {
            if (!root.cacheDir)
                return
            var target = root.cacheDir + "/art-" + root.hash(url) + ".img"
            if (root.albumImagePath === target)
                return
            root.artTarget = target
            artDownload.exec([
                "curl", "-fsSL", "--max-time", "10",
                "-o", target, url
            ])
            return
        }

        root.albumImagePath = ""
    }

    function parseWal(text) {
        if (!text)
            return
        try {
            var data = JSON.parse(text)
            var colors = []
            for (var i = 0; i < 16; i++) {
                var value = data["color" + i]
                if (root.validHex(value))
                    colors.push(root.normalizeHex(value))
            }
            if (colors.length > 0) {
                root.walColors = colors
                root.scheduleRecompute()
            }
        } catch (error) {
            // Ignore malformed pywal files.
        }
    }

    function scheduleRecompute() {
        paletteTimer.restart()
    }

    // ------------------------------------------------------------- colour math
    function validHex(value) {
        return /^#([0-9a-fA-F]{3}|[0-9a-fA-F]{6})$/.test(String(value || ""))
    }

    function normalizeHex(value) {
        var text = String(value || "").trim()
        if (!root.validHex(text))
            return "#000000"
        if (text.length === 4)
            return "#" + text[1] + text[1] + text[2] + text[2] + text[3] + text[3]
        return text.toLowerCase()
    }

    function hexToRgb(value) {
        var text = root.normalizeHex(value)
        return {
            r: parseInt(text.substring(1, 3), 16),
            g: parseInt(text.substring(3, 5), 16),
            b: parseInt(text.substring(5, 7), 16)
        }
    }

    function rgbToHex(r, g, b) {
        function part(value) {
            var clamped = Math.max(0, Math.min(255, Math.round(value)))
            var hex = clamped.toString(16)
            return hex.length === 1 ? "0" + hex : hex
        }
        return "#" + part(r) + part(g) + part(b)
    }

    function mixHex(first, second, amount) {
        var a = root.hexToRgb(first)
        var b = root.hexToRgb(second)
        var t = Math.max(0, Math.min(1, Number(amount)))
        return root.rgbToHex(
            a.r + (b.r - a.r) * t,
            a.g + (b.g - a.g) * t,
            a.b + (b.b - a.b) * t
        )
    }

    function channelLuminance(value) {
        var c = value / 255
        return c <= 0.03928 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4)
    }

    function luminance(value) {
        var rgb = root.hexToRgb(value)
        return 0.2126 * root.channelLuminance(rgb.r)
            + 0.7152 * root.channelLuminance(rgb.g)
            + 0.0722 * root.channelLuminance(rgb.b)
    }

    function contrast(first, second) {
        var a = root.luminance(first)
        var b = root.luminance(second)
        var lighter = Math.max(a, b)
        var darker = Math.min(a, b)
        return (lighter + 0.05) / (darker + 0.05)
    }

    function averageColor(colors) {
        if (!colors || colors.length === 0)
            return "#101522"
        var r = 0
        var g = 0
        var b = 0
        for (var i = 0; i < colors.length; i++) {
            var rgb = root.hexToRgb(colors[i])
            r += rgb.r
            g += rgb.g
            b += rgb.b
        }
        return root.rgbToHex(r / colors.length, g / colors.length, b / colors.length)
    }

    function colorStats(value) {
        var rgb = root.hexToRgb(value)
        var max = Math.max(rgb.r, rgb.g, rgb.b) / 255
        var min = Math.min(rgb.r, rgb.g, rgb.b) / 255
        var lightness = (max + min) / 2
        var saturation = 0
        if (max !== min)
            saturation = (max - min) / (1 - Math.abs(2 * lightness - 1))
        return { saturation: saturation, lightness: lightness }
    }

    function pickAccent(colors) {
        var best = ""
        var bestScore = -1
        if (!colors)
            return "#8ab4f8"
        for (var i = 0; i < colors.length; i++) {
            var stats = root.colorStats(colors[i])
            if (stats.lightness < 0.07 || stats.lightness > 0.94)
                continue
            var score = stats.saturation * 2.2 + (1 - Math.abs(stats.lightness - 0.55))
            if (stats.lightness > 0.86)
                score -= 0.35
            if (score > bestScore) {
                bestScore = score
                best = colors[i]
            }
        }
        if (!best && colors.length > 0)
            best = colors[0]
        return root.ensureVisible(best || "#8ab4f8")
    }

    function ensureVisible(value) {
        if (!root.validHex(value))
            return "#8ab4f8"
        var lum = root.luminance(value)
        if (lum < 0.2)
            return root.mixHex(value, "#ffffff", 0.42)
        if (lum > 0.88)
            return root.mixHex(value, "#000000", 0.28)
        return root.normalizeHex(value)
    }

    function ensureContrast(foreground, background, target) {
        if (!root.validHex(foreground) || !root.validHex(background))
            return "#f6f8ff"
        if (root.contrast(foreground, background) >= target)
            return root.normalizeHex(foreground)
        var direction = root.luminance(background) > 0.42 ? "#000000" : "#ffffff"
        var best = foreground
        for (var i = 1; i <= 10; i++) {
            var candidate = root.mixHex(foreground, direction, i / 10)
            best = candidate
            if (root.contrast(candidate, background) >= target)
                return candidate
        }
        return best
    }

    function recompute() {
        var wp = root.wallpaperColors.length > 0 ? root.wallpaperColors
            : (root.walColors.length > 0 ? root.walColors : root.fallbackPalette)
        root.palette = wp

        if (root.wallpaperColors.length > 0)
            root.wallpaperAccent = root.pickAccent(root.wallpaperColors)
        else if (!root.wallpaperAccent)
            root.wallpaperAccent = root.pickAccent(wp)

        if (root.albumColors.length > 0)
            root.albumAccent = root.pickAccent(root.albumColors)

        var average = root.averageColor(wp)
        var backgroundLum = root.luminance(average)
        root.backgroundLuminance = backgroundLum
        root.lightBackground = backgroundLum > 0.5

        var accent = root.wallpaperAccent || "#8ab4f8"
        if (root.mode === "album") {
            accent = root.albumAccent || accent
        } else if (root.mode === "custom") {
            accent = root.validHex(root.customAccentColor)
                ? root.normalizeHex(root.customAccentColor) : accent
        } else if (root.mode === "auto") {
            if (root.albumAccent)
                accent = root.mixHex(root.wallpaperAccent || accent, root.albumAccent, root.blend)
        }

        var desiredText = root.lightBackground ? "#0b1020" : "#f6f8ff"
        if (root.mode === "custom" && root.validHex(root.customTextColor))
            desiredText = root.normalizeHex(root.customTextColor)

        root.accentColor = root.ensureVisible(accent)
        root.textColor = root.ensureContrast(desiredText, average, 4.5)
        root.mutedColor = root.ensureContrast(
            root.mixHex(root.textColor, average, 0.38), average, 3.0)
        root.shadowColor = root.lightBackground ? "#ffffff" : "#000000"
        root.shadowOpacity = root.lightBackground ? 0.55 : 0.85
        root.glowColor = root.mixHex(root.accentColor,
            root.lightBackground ? "#000000" : "#ffffff", 0.12)
        root.scrimColor = root.lightBackground ? "#ffffff" : "#000000"
        root.contrastRatio = root.contrast(root.textColor, average)
    }
}
