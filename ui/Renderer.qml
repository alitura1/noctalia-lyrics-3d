// ui/Renderer.qml — Quickshell companion for the Noctalia v5 plugin.
//
// Noctalia's native ui tree has no 3D rotation or depth blur, so the Luau
// service publishes a JSON snapshot and this separate Quickshell process owns
// the real layer-shell surfaces, 3D scene, calibration and colour engine.

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "components"
import "services"

ShellRoot {
    id: root

    readonly property string homeDir: Quickshell.env("HOME") || ""
    readonly property string cacheDir: Quickshell.env("NOCTALIA_LYRICS_CACHE")
        || (root.homeDir + "/.cache/noctalia-lyrics")
    readonly property string configPrefix: 'plugin_settings."alitura/noctalia-lyrics-3d".'

    property var st: ({})
    property var cfg: ({})
    property real anchorPositionMs: 0
    property real anchorWallMs: 0
    property real livePositionMs: 0
    property real lastUpdatedMs: 0
    property bool sawState: false
    property bool pauseDismissed: false

    readonly property bool hasSong: root.st.hasSong === true
    readonly property bool hideOnPause: root.cfg.hideOnPause !== false

    property bool calibratingLocal: false
    property bool calibrationSaved: false
    property bool calibrationSaveInFlight: false
    property var calibrationBackup: ({})

    property bool perspectiveActive: false
    property var perspectives: ({})
    property bool perspectivesLoaded: false
    property string perspectiveKey: "global"
    property real lastHostAngleX: 0
    property real lastHostAngleY: 0
    property real lastHostAngleZ: 0
    property real lastHostScale: 1
    property real lastHostOffsetX: 0
    property real lastHostOffsetY: 0
    property real lastHostPositionX: 50
    property real lastHostPositionY: 78

    property real angleX: 0
    property real angleY: 0
    property real angleZ: 0
    property real sceneScale: 1
    property real offsetX: 0
    property real offsetY: 0
    property real positionX: 50
    property real positionY: 78

    readonly property var lines: Array.isArray(st.lyrics) ? st.lyrics : []
    readonly property string lyricsState: String(st.lyricsState || "idle")
    readonly property bool playing: st.playing === true
    readonly property bool calibrating: calibratingLocal || st.calibrating === true
    readonly property string effectiveLayer: root.calibrating || st.layer === "overlay" ? "overlay" : "bottom"
    readonly property string calibrationMonitor: String(st.focusedMonitor || "")
    readonly property int monitorWidth: Math.max(1, Number(st.screenWidth) || 1920)
    readonly property int monitorHeight: Math.max(1, Number(st.screenHeight) || 1080)

    readonly property real parallaxX: {
        if (cfg.parallax !== true) return 0
        var normalized = Number(st.cursorX || 0) / root.monitorWidth - 0.5
        var strength = Number(cfg.parallaxStrength) || 1.2
        return Math.max(-2, Math.min(2, -normalized * 2 * strength))
    }
    readonly property real parallaxY: {
        if (cfg.parallax !== true) return 0
        var normalized = Number(st.cursorY || 0) / root.monitorHeight - 0.5
        var strength = Number(cfg.parallaxStrength) || 1.2
        return Math.max(-2, Math.min(2, normalized * 2 * strength))
    }

    // Terminal lyric states (notfound / instrumental / error) are a short
    // toast, not a permanent card: a static card would otherwise keep a full-screen
    // layer mapped and the 60 Hz clock running for the whole song. The toast
    // expires and the surface unmaps until there is something new to draw.
    readonly property bool lyricsReady: (root.lyricsState === "synced" && root.lines.length > 0)
        || (root.lyricsState === "plain" && String(root.st.plainText || "").length > 0)
    readonly property bool statusCardTerminal: root.lyricsState === "notfound"
        || root.lyricsState === "instrumental" || root.lyricsState === "error"
    readonly property bool nowPlayingCardVisible: root.cfg.showNowPlaying !== false
        && String(root.st.title || "").length > 0
    property bool statusToastVisible: false
    readonly property string statusToastKey: root.lyricsState + "|"
        + String(root.st.title || "") + "|" + String(root.st.artist || "")

    Timer {
        id: statusToastTimer
        interval: 4500
        repeat: false
        onTriggered: root.statusToastVisible = false
    }

    function refreshStatusToast() {
        if (!root.statusCardTerminal) {
            statusToastTimer.stop()
            root.statusToastVisible = false
            return
        }
        root.statusToastVisible = true
        statusToastTimer.restart()
    }

    onStatusToastKeyChanged: root.refreshStatusToast()

    readonly property bool statusCardVisible: root.lyricsState === "loading"
        || (root.statusCardTerminal && root.statusToastVisible)
    readonly property bool hasOverlayContent: root.calibrating || root.lyricsReady
        || root.statusCardVisible || root.nowPlayingCardVisible

    // The overlay only exists while it can actually be seen. A mapped
    // full-screen layer surface costs a compositor blend and a QML frame every
    // 16 ms even when a fullscreen game covers it, so the surface is unmapped
    // and the clock stops whenever nothing is drawn.
    readonly property bool overlayOnScreen: root.st.visible === true
        && !root.pauseDismissed && root.hasOverlayContent

    // 60 Hz local clock. The service only publishes anchors (track change,
    // play/pause, seek, 2 s drift sync), so the playhead advances every frame
    // from the local monotonic clock instead of stepping on D-Bus polls.
    Timer {
        interval: 16
        repeat: true
        running: root.playing && !root.calibratingLocal && root.overlayOnScreen
        onTriggered: {
            var rate = Number(root.st.positionRate) || Number(root.st.rate) || 1
            var next = root.anchorPositionMs + (Date.now() - root.anchorWallMs) * rate
            var length = Number(root.st.lengthMs) || 0
            if (length > 0 && next > length) next = length
            root.livePositionMs = next
        }
    }

    // A pause is soft: no blink on a short pause, then the overlay dissolves.
    Timer {
        id: pauseTimer
        interval: 1500
        repeat: false
        onTriggered: root.pauseDismissed = true
    }

    function updatePauseTimer() {
        if (!root.hideOnPause || !root.hasSong) {
            pauseTimer.stop()
            root.pauseDismissed = false
            return
        }
        if (root.playing) {
            pauseTimer.stop()
            if (root.pauseDismissed) root.pauseDismissed = false
            return
        }
        if (!pauseTimer.running && !root.pauseDismissed) pauseTimer.start()
    }

    // Safety net for FileView watchers: a snapshot can be replaced while the
    // watcher is re-arming, so poll the same file at a low rate as well.
    // If the Luau service stops (plugin disabled or shell exit), no new
    // snapshot arrives; do not leave an orphan layer-shell process behind.
    Timer {
        interval: 2000
        repeat: true
        running: root.sawState
        onTriggered: {
            if (root.sawState && root.lastUpdatedMs > 0
                    && Date.now() - root.lastUpdatedMs > 8000) {
                Qt.quit()
            }
        }
    }

    Timer {
        interval: 1500
        repeat: true
        running: true
        onTriggered: {
            if (stateFile.path.length > 0) stateFile.reload()
        }
    }

    FileView {
        id: stateFile
        path: root.cacheDir + "/state.json"
        printErrors: false
        preload: true
        watchChanges: true
        onLoaded: root.applyState(stateFile.text())
        onTextChanged: root.applyState(stateFile.text())
        onFileChanged: stateFile.reload()
    }

    FileView {
        id: perspectiveFile
        path: ""
        printErrors: false
        preload: true
        onLoaded: root.loadPerspectives(perspectiveFile.text())
        onFileChanged: perspectiveFile.reload()
        onLoadFailed: root.perspectivesLoaded = true
    }

    FileView {
        id: controlFile
        path: root.cacheDir + "/control.json"
        printErrors: false
        preload: true
    }

    AdaptiveThemeEngine {
        id: theme
        active: true
        home: root.homeDir
        cacheDir: root.cacheDir
        monitorName: root.st.focusedMonitor || ""
        wallpaperOverride: root.cfg.wallpaperPathOverride || ""
        artUrl: root.st.artUrl || ""
        mode: root.cfg.themeMode || "auto"
        blend: root.cfg.accentBlend !== undefined ? Number(root.cfg.accentBlend) : 0.65
        customTextColor: root.cfg.customTextColor || "#f6f8ff"
        customAccentColor: root.cfg.customAccentColor || "#8ab4f8"

        onWallpaperKeyChanged: {
            root.perspectiveKey = root.themeKey()
            root.applySavedPerspective()
        }
    }


    function themeKey() {
        return theme.wallpaperKey && theme.wallpaperKey.length > 0 ? theme.wallpaperKey : "global"
    }

    function num(value, fallback) {
        var parsed = Number(value)
        return isNaN(parsed) ? fallback : parsed
    }

    function applyState(raw) {
        var parsed = null
        try {
            parsed = JSON.parse(String(raw || ""))
        } catch (error) {
            return
        }
        if (!parsed || typeof parsed !== "object") return

        var previous = cfg || ({})
        var next = parsed.settings || ({})
        var hostChanged = previous.angleX !== undefined && (
            num(previous.angleX, 0) !== num(next.angleX, 0)
            || num(previous.angleY, 0) !== num(next.angleY, 0)
            || num(previous.angleZ, 0) !== num(next.angleZ, 0)
            || num(previous.sceneScale, 1) !== num(next.sceneScale, 1)
            || num(previous.offsetX, 0) !== num(next.offsetX, 0)
            || num(previous.offsetY, 0) !== num(next.offsetY, 0)
            || num(previous.positionX, 50) !== num(next.positionX, 50)
            || num(previous.positionY, 78) !== num(next.positionY, 78)
        )

        // Anchors arrive with the service's wall stamp. Applying one only when
        // that stamp changes keeps the local clock authoritative between
        // events, so a repeated snapshot never yanks the playhead backwards.
        var anchorWall = Number(parsed.positionAnchorWallMs) || 0
        var anchorMs = Number(parsed.positionAnchorMs)
        if (!isNaN(anchorMs) && anchorWall > 0 && anchorWall !== root.anchorWallMs) {
            root.anchorPositionMs = anchorMs
            root.anchorWallMs = anchorWall
            if (parsed.playing !== true) root.livePositionMs = anchorMs
        }
        root.lastUpdatedMs = parsed.updatedAtMs || 0
        root.sawState = true
        root.st = parsed
        root.cfg = next
        root.updatePauseTimer()

        if (hostChanged && root.perspectiveActive) root.perspectiveActive = false
        if (!root.perspectiveActive) root.applyHostGeometry()

        if (parsed.calibrating === true && !root.calibratingLocal
                && !root.calibrationSaveInFlight) {
            root.beginCalibration()
        } else if (parsed.calibrating === false) {
            if (root.calibrationSaveInFlight) root.calibrationSaveInFlight = false
            if (root.calibratingLocal && !root.calibrationSaved) root.cancelLocal()
            if (root.calibrationSaved) root.calibrationSaved = false
        }
    }

    function applyHostGeometry() {
        root.angleX = num(cfg.angleX, 0)
        root.angleY = num(cfg.angleY, 0)
        root.angleZ = num(cfg.angleZ, 0)
        root.sceneScale = num(cfg.sceneScale, 1)
        root.offsetX = num(cfg.offsetX, 0)
        root.offsetY = num(cfg.offsetY, 0)
        root.positionX = num(cfg.positionX, 50)
        root.positionY = num(cfg.positionY, 78)
        root.lastHostAngleX = root.angleX
        root.lastHostAngleY = root.angleY
        root.lastHostAngleZ = root.angleZ
        root.lastHostScale = root.sceneScale
        root.lastHostOffsetX = root.offsetX
        root.lastHostOffsetY = root.offsetY
        root.lastHostPositionX = root.positionX
        root.lastHostPositionY = root.positionY
    }

    function beginCalibration() {
        root.calibrationBackup = {
            angleX: root.angleX, angleY: root.angleY, angleZ: root.angleZ,
            sceneScale: root.sceneScale, offsetX: root.offsetX, offsetY: root.offsetY,
            positionX: root.positionX, positionY: root.positionY
        }
        root.calibrationSaved = false
        root.calibrationSaveInFlight = false
        root.calibratingLocal = true
        root.perspectiveActive = true
        root.perspectiveKey = root.themeKey()
        root.ensurePerspectiveFile()
    }

    function cancelLocal() {
        var backup = root.calibrationBackup || ({})
        root.angleX = num(backup.angleX, 0)
        root.angleY = num(backup.angleY, 0)
        root.angleZ = num(backup.angleZ, 0)
        root.sceneScale = num(backup.sceneScale, 1)
        root.offsetX = num(backup.offsetX, 0)
        root.offsetY = num(backup.offsetY, 0)
        root.positionX = num(backup.positionX, 50)
        root.positionY = num(backup.positionY, 78)
        root.calibratingLocal = false
        root.perspectiveActive = false
    }

    function applyGeometry(values) {
        if (values.angleX !== undefined) root.angleX = num(values.angleX, root.angleX)
        if (values.angleY !== undefined) root.angleY = num(values.angleY, root.angleY)
        if (values.angleZ !== undefined) root.angleZ = num(values.angleZ, root.angleZ)
        if (values.scale !== undefined) root.sceneScale = num(values.scale, root.sceneScale)
        if (values.offsetX !== undefined) root.offsetX = num(values.offsetX, root.offsetX)
        if (values.offsetY !== undefined) root.offsetY = num(values.offsetY, root.offsetY)
        if (values.positionX !== undefined) root.positionX = num(values.positionX, root.positionX)
        if (values.positionY !== undefined) root.positionY = num(values.positionY, root.positionY)
        root.perspectiveActive = true
    }

    function ensurePerspectiveFile() {
        if (perspectiveFile.path.length === 0)
            perspectiveFile.path = root.cacheDir + "/perspectives.json"
    }

    function loadPerspectives(raw) {
        var parsed = ({})
        try {
            parsed = JSON.parse(String(raw || "{}")) || ({})
        } catch (error) {
            parsed = ({})
        }
        root.perspectives = parsed
        root.perspectivesLoaded = true
        root.perspectiveKey = root.themeKey()
        root.applySavedPerspective()
    }

    function applySavedPerspective() {
        if (!root.perspectivesLoaded || cfg.savePerspectives === false) return
        var entry = (root.perspectives || ({}))[root.perspectiveKey]
        if (!entry) {
            if (!root.calibratingLocal) root.applyHostGeometry()
            return
        }
        root.angleX = num(entry.angleX, 0)
        root.angleY = num(entry.angleY, 0)
        root.angleZ = num(entry.angleZ, 0)
        root.sceneScale = num(entry.scale, 1)
        root.offsetX = num(entry.offsetX, 0)
        root.offsetY = num(entry.offsetY, 0)
        root.positionX = num(entry.positionX, num(cfg.positionX, 50))
        root.positionY = num(entry.positionY, num(cfg.positionY, 78))
        root.perspectiveActive = true
        root.lastHostAngleX = num(cfg.angleX, root.angleX)
        root.lastHostAngleY = num(cfg.angleY, root.angleY)
        root.lastHostAngleZ = num(cfg.angleZ, root.angleZ)
        root.lastHostScale = num(cfg.sceneScale, root.sceneScale)
        root.lastHostOffsetX = num(cfg.offsetX, root.offsetX)
        root.lastHostOffsetY = num(cfg.offsetY, root.offsetY)
        root.lastHostPositionX = num(cfg.positionX, root.positionX)
        root.lastHostPositionY = num(cfg.positionY, root.positionY)
    }

    function saveCalibration() {
        root.ensurePerspectiveFile()
        if (cfg.savePerspectives !== false) {
            var map = Object.assign({}, root.perspectives || ({}))
            map[root.perspectiveKey] = {
                path: theme.wallpaperPath || "",
                angleX: root.angleX, angleY: root.angleY, angleZ: root.angleZ,
                scale: root.sceneScale, offsetX: root.offsetX, offsetY: root.offsetY,
                positionX: root.positionX, positionY: root.positionY,
                savedAt: Date.now()
            }
            root.perspectives = map
            perspectiveFile.setText(JSON.stringify(map, null, 2))
        }

        root.calibrationSaved = true
        root.calibrationSaveInFlight = true
        root.calibratingLocal = false
        root.perspectiveActive = true
        root.lastHostAngleX = num(cfg.angleX, root.angleX)
        root.lastHostAngleY = num(cfg.angleY, root.angleY)
        root.lastHostAngleZ = num(cfg.angleZ, root.angleZ)
        root.lastHostScale = num(cfg.sceneScale, root.sceneScale)
        root.lastHostOffsetX = num(cfg.offsetX, root.offsetX)
        root.lastHostOffsetY = num(cfg.offsetY, root.offsetY)
        root.lastHostPositionX = num(cfg.positionX, root.positionX)
        root.lastHostPositionY = num(cfg.positionY, root.positionY)

        controlFile.setText(JSON.stringify({
            action: "calibrate-save",
            values: {
                angleX: root.angleX, angleY: root.angleY, angleZ: root.angleZ,
                sceneScale: root.sceneScale, offsetX: root.offsetX, offsetY: root.offsetY,
                positionX: root.positionX, positionY: root.positionY
            }
        }))
    }

    function cancelCalibration() {
        root.calibrationSaveInFlight = true
        root.calibrationSaved = false
        root.cancelLocal()
        controlFile.setText(JSON.stringify({ action: "calibrate-cancel" }))
    }

    function resetCalibration() {
        root.applyGeometry({
            angleX: 0, angleY: 0, angleZ: 0, scale: 1, offsetX: 0, offsetY: 0,
            positionX: 50, positionY: 78
        })
    }

    Component.onCompleted: {
        root.ensurePerspectiveFile()
        root.lastHostAngleX = num(cfg.angleX, 0)
        root.lastHostAngleY = num(cfg.angleY, 0)
        root.lastHostAngleZ = num(cfg.angleZ, 0)
        root.lastHostScale = num(cfg.sceneScale, 1)
        root.lastHostOffsetX = num(cfg.offsetX, 0)
        root.lastHostOffsetY = num(cfg.offsetY, 0)
        root.lastHostPositionX = num(cfg.positionX, 50)
        root.lastHostPositionY = num(cfg.positionY, 78)
    }

    // Small control surface for debugging and for users who want to bind a
    // compositor shortcut to calibration: qs ipc call lyrics3d calibrate
    IpcHandler {
        target: "lyrics3d"

        function calibrate() {
            controlFile.setText(JSON.stringify({ action: "calibrate" }))
        }

        function save() {
            root.saveCalibration()
        }

        function cancel() {
            controlFile.setText(JSON.stringify({ action: "calibrate-cancel" }))
        }

        function reset() {
            root.resetCalibration()
        }

    }

    Variants {
        model: Quickshell.screens

        delegate: PanelWindow {
            id: surface
            required property var modelData
            readonly property bool cardPointerActive:
                root.st.visible === true && surfaceContent.visible
                    && lyricRenderer.nowPlayingInteractive

            screen: modelData
            // Unmapped while hidden: no buffer, no commit, no compositor work.
            visible: root.overlayOnScreen || root.calibratingLocal
            // A Canvas can only sample the wallpaper while its window is
            // mapped, so the one-time analysis is requested on first show.
            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }
            color: "#00000000"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: root.effectiveLayer === "overlay" ? WlrLayer.Overlay : WlrLayer.Bottom
            WlrLayershell.namespace: "noctalia-lyrics-3d"
            WlrLayershell.keyboardFocus: root.calibratingLocal
                ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

            // Click-through everywhere except the calibration surface and the
            // compact now-playing card. The card gets a small input region so
            // its quick controls work without making the desktop unclickable.
            mask: Region {
                x: root.calibratingLocal ? 0 : (surface.cardPointerActive ? lyricRenderer.nowPlayingX : 0)
                y: root.calibratingLocal ? 0 : (surface.cardPointerActive ? lyricRenderer.nowPlayingY : 0)
                width: root.calibratingLocal ? surface.width
                    : (surface.cardPointerActive ? lyricRenderer.nowPlayingWidth : 0)
                height: root.calibratingLocal ? surface.height
                    : (surface.cardPointerActive ? lyricRenderer.nowPlayingHeight : 0)
            }

            Item {
                id: surfaceContent
                anchors.fill: parent
                visible: root.calibratingLocal
                    ? (modelData && modelData.name === root.calibrationMonitor)
                    : (root.st.visible === true && !root.pauseDismissed
                        && (cfg.monitorScope === "all"
                            || (modelData && modelData.name === root.st.focusedMonitor)))
                opacity: visible ? 1 : 0

                // 180 ms in, 300 ms out: resuming is immediate, a pause
                // dissolves instead of blinking the layer away.
                Behavior on opacity {
                    NumberAnimation {
                        duration: surfaceContent.visible ? 180 : 300
                        easing.type: Easing.OutCubic
                    }
                }

                LyricsRenderer3D {
                    id: lyricRenderer
                    anchors.fill: parent

                    lyrics: root.lines
                    lyricState: root.calibratingLocal && root.st.hasSong !== true
                        ? "synced" : root.lyricsState
                    previewMode: root.calibratingLocal && root.st.hasSong !== true
                    statusCardAllowed: root.statusCardVisible
                    positionMs: root.livePositionMs
                    syncOffset: num(cfg.syncOffset, 0)
                    songLengthMs: Number(root.st.lengthMs) || 0
                    plainText: String(root.st.plainText || "")
                    songTitle: String(root.st.title || "")
                    songArtist: String(root.st.artist || "")

                    fontFamily: String(cfg.fontFamily || "")
                    fontSize: Math.max(12, num(cfg.fontSize, 38))
                    fontWeight: Math.max(100, num(cfg.fontWeight, 600))
                    lineSpacing: num(cfg.lineSpacing, 12)
                    maxLines: Math.max(3, num(cfg.maxLines, 9))
                    widthPercent: Math.max(0.2, Math.min(1, num(cfg.widthPercent, 0.62)))
                    typographyMaxWidth: num(cfg.typographyMaxWidth, 480)
                    typographyStyle: String(cfg.typographyStyle || "modern")
                    nowPlayingPosition: String(cfg.nowPlayingPosition || "topCenter")
                    offsetX: root.offsetX
                    offsetY: root.offsetY
                    positionX: root.positionX
                    positionY: root.positionY
                    dynamicPlacement: cfg.dynamicPlacement !== false
                    wallpaperAware: cfg.wallpaperAware !== false
                    // The service analyses the wallpaper once per change and
                    // publishes its energy grid; the renderer roams the calm cells.
                    wallpaperGrid: root.st.wallpaperGrid || null
                    wallpaperOrder: String(cfg.wallpaperOrder || "tour")
                    centerSafeZone: num(cfg.centerSafeZone, 32)
                    displayMode: String(cfg.displayMode || "auto")
                    showNowPlaying: cfg.showNowPlaying !== false
                    showNextLine: cfg.showNextLine === true
                    angleX: root.angleX + root.parallaxY
                    angleY: root.angleY + lyricRenderer.regionalAngleY + root.parallaxX
                    angleZ: root.angleZ
                    sceneScale: Math.max(0.1, root.sceneScale)
                    depthScale: Math.max(0.5, Math.min(1, num(cfg.depthScale, 0.92)))
                    blurAmount: Math.max(0, Math.min(1, num(cfg.blurAmount, 0.45)))
                    activeGlow: Math.max(0, Math.min(1, num(cfg.activeGlow, 0.55)))
                    textScrim: Math.max(0, Math.min(1, num(cfg.textScrim, 0)))

                    textColor: theme.textColor
                    accentColor: theme.accentColor
                    activeWordColor: theme.activeWordColor
                    activeGlowColor: theme.activeGlowColor
                    shadowColor: theme.shadowColor
                    scrimColor: theme.scrimColor

                    onModeToggleRequested: controlFile.setText(JSON.stringify({ action: "cycle-display-mode" }))
                    onCalibrateRequested: controlFile.setText(JSON.stringify({ action: "calibrate" }))
                    onSettingsRequested: controlFile.setText(JSON.stringify({ action: "open-settings" }))
                }

                CalibrationOverlay {
                    anchors.fill: parent
                    visible: root.calibratingLocal
                    angleX: root.angleX
                    angleY: root.angleY
                    angleZ: root.angleZ
                    sceneScale: root.sceneScale
                    offsetX: root.offsetX
                    offsetY: root.offsetY
                    positionX: root.positionX
                    positionY: root.positionY
                    wallpaperLabel: theme.wallpaperPath
                    savedCount: Object.keys(root.perspectives || ({})).length
                    accentColor: theme.accentColor
                    textColor: "#eef3fb"

                    onEdited: function (values) { root.applyGeometry(values) }
                    onSaveRequested: root.saveCalibration()
                    onCancelRequested: root.cancelCalibration()
                    onResetRequested: root.resetCalibration()
                }
            }
        }
    }
}
