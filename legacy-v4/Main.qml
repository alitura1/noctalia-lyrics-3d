// Main.qml
// Noctalia Lyrics 3D - entry point.
// Owns the per-screen layer surfaces, services, settings and per-wallpaper
// perspective storage. The default surface is a click-through Bottom layer;
// it moves to Overlay only for allow-listed windows or calibration.

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "services"
import "components"

Item {
    id: root

    // Injected by Noctalia's PluginService.
    property var pluginApi: null

    readonly property string home: {
        var value = Quickshell.env("HOME")
        return value ? String(value) : ""
    }
    readonly property string cacheDir: root.home.length > 0
        ? root.home + "/.cache/noctalia-lyrics"
        : "/tmp/noctalia-lyrics"

    readonly property var defaultSettings: ({
        enabled: true,
        fontFamily: "",
        fontSize: 38,
        fontWeight: 600,
        lineSpacing: 12,
        maxLines: 9,
        widthPercent: 0.62,
        offsetX: 0,
        offsetY: 0,
        angleX: 0,
        angleY: 0,
        angleZ: 0,
        scale: 1.0,
        depthScale: 0.92,
        blurAmount: 0.45,
        activeGlow: 0.55,
        parallax: false,
        parallaxStrength: 1.2,
        syncOffset: 0,
        filterMode: "allowAll",
        disabledDomains: [],
        customDomains: [],
        disabledPlayers: [],
        allowedWindows: [],
        visibilityMode: "desktop",
        hideOnFullscreen: true,
        hideWhenPaused: false,
        monitorScope: "focused",
        themeMode: "auto",
        accentBlend: 0.65,
        customTextColor: "#f6f8ff",
        customAccentColor: "#8ab4f8",
        textScrim: 0.0,
        wallpaperPathOverride: "",
        showPlainLyrics: true,
        cacheEnabled: true,
        savePerspectivePerWallpaper: true
    })

    property var s: ({})
    property int settingsRevision: 0
    property bool userHidden: false
    property bool calibrating: false
    property string calibrationScreen: ""
    property var calibrationBackup: ({})
    property var perspectives: ({})
    property bool perspectiveLoaded: false
    property bool perspectiveWriting: false

    readonly property string perspectiveKey: root.theme.wallpaperKey.length > 0
        ? root.theme.wallpaperKey : "global"

    signal settingsChanged()
    signal perspectiveApplied()

    property alias mpris: mprisMonitor
    property alias lyrics: lrclibClient
    property alias visibility: visibilityManager
    property alias theme: themeEngine

    // ---------------------------------------------------------------- services
    MprisMonitor {
        id: mprisMonitor
        disabledPlayers: root.s.disabledPlayers || []
        filterMode: root.s.filterMode || "allowAll"
        disabledDomains: root.s.disabledDomains || []
        customDomains: root.s.customDomains || []
    }

    LrclibClient {
        id: lrclibClient
        song: mprisMonitor.song
        cacheDir: root.cacheDir
        cacheEnabled: root.s.cacheEnabled !== false
    }

    WindowVisibilityManager {
        id: visibilityManager
        active: root.s.enabled !== false
        allowedWindows: root.s.allowedWindows || []
        mode: root.s.visibilityMode || "desktop"
        hideOnFullscreen: root.s.hideOnFullscreen !== false
        pollInterval: 700
    }

    AdaptiveThemeEngine {
        id: themeEngine
        active: root.s.enabled !== false
        home: root.home
        cacheDir: root.cacheDir
        wallpaperOverride: root.s.wallpaperPathOverride || ""
        artUrl: mprisMonitor.song.artUrl || ""
        mode: root.s.themeMode || "auto"
        blend: root.s.accentBlend !== undefined ? Number(root.s.accentBlend) : 0.65
        customTextColor: root.s.customTextColor || "#f6f8ff"
        customAccentColor: root.s.customAccentColor || "#8ab4f8"
    }

    // ------------------------------------------------------------- lifecycle
    Component.onCompleted: {
        root.reloadSettings()
        ensureCache.running = true
    }

    onPluginApiChanged: root.reloadSettings()

    Connections {
        target: themeEngine
        function onWallpaperKeyChanged() {
            root.applySavedPerspective()
        }
    }

    // -------------------------------------------------------------- settings
    function reloadSettings() {
        var merged = {}
        var key = ""
        for (key in root.defaultSettings)
            merged[key] = root.defaultSettings[key]

        var api = root.pluginApi
        var manifestDefaults = api && api.manifest && api.manifest.metadata
            ? api.manifest.metadata.defaultSettings : null
        if (manifestDefaults) {
            for (key in manifestDefaults)
                merged[key] = manifestDefaults[key]
        }

        var saved = api ? api.pluginSettings : null
        if (saved) {
            for (key in saved) {
                if (saved[key] !== undefined)
                    merged[key] = saved[key]
            }
        }

        root.s = merged
        root.settingsRevision++
        root.settingsChanged()
        if (root.perspectiveLoaded)
            root.applySavedPerspective()
    }

    function updateSetting(key, value) {
        var copy = Object.assign({}, root.s)
        copy[key] = value
        root.s = copy
        root.settingsRevision++

        var api = root.pluginApi
        if (api && api.pluginSettings) {
            api.pluginSettings[key] = value
            if (api.saveSettings)
                api.saveSettings()
        }
        root.settingsChanged()
    }

    function applySettings(values) {
        var copy = Object.assign({}, root.s)
        var api = root.pluginApi
        for (var key in values) {
            copy[key] = values[key]
            if (api && api.pluginSettings)
                api.pluginSettings[key] = values[key]
        }
        root.s = copy
        root.settingsRevision++
        if (api && api.saveSettings)
            api.saveSettings()
        root.settingsChanged()
    }

    // Geometry updates are intentionally not persisted on every slider tick.
    function applyGeometry(values) {
        var copy = Object.assign({}, root.s)
        for (var key in values) {
            if (values[key] !== undefined)
                copy[key] = values[key]
        }
        root.s = copy
        root.settingsRevision++
        root.settingsChanged()
    }

    function commitGeometry() {
        var api = root.pluginApi
        if (!api || !api.pluginSettings)
            return
        var keys = ["angleX", "angleY", "angleZ", "scale", "offsetX", "offsetY"]
        for (var i = 0; i < keys.length; i++)
            api.pluginSettings[keys[i]] = root.s[keys[i]]
        if (api.saveSettings)
            api.saveSettings()
    }

    // ----------------------------------------------------------- calibration
    function startCalibration() {
        root.calibrationBackup = {
            angleX: root.s.angleX,
            angleY: root.s.angleY,
            angleZ: root.s.angleZ,
            scale: root.s.scale,
            offsetX: root.s.offsetX,
            offsetY: root.s.offsetY
        }
        root.calibrationScreen = root.visibility.activeMonitor.length > 0
            ? root.visibility.activeMonitor
            : (Quickshell.screens.length > 0 ? Quickshell.screens[0].name : "")
        root.userHidden = false
        root.calibrating = true
    }

    function saveCalibration() {
        root.commitGeometry()
        root.savePerspective()
        root.calibrating = false
        root.perspectiveApplied()
    }

    function cancelCalibration() {
        if (root.calibrationBackup) {
            root.applyGeometry({
                angleX: root.numberOr(root.calibrationBackup.angleX, 0),
                angleY: root.numberOr(root.calibrationBackup.angleY, 0),
                angleZ: root.numberOr(root.calibrationBackup.angleZ, 0),
                scale: root.numberOr(root.calibrationBackup.scale, 1.0),
                offsetX: root.numberOr(root.calibrationBackup.offsetX, 0),
                offsetY: root.numberOr(root.calibrationBackup.offsetY, 0)
            })
        }
        root.calibrating = false
        root.perspectiveApplied()
    }

    function resetCalibration() {
        root.applyGeometry({
            angleX: 0,
            angleY: 0,
            angleZ: 0,
            scale: 1.0,
            offsetX: 0,
            offsetY: 0
        })
    }

    function numberOr(value, fallback) {
        var parsed = Number(value)
        return isNaN(parsed) ? fallback : parsed
    }

    // ------------------------------------------------- per-wallpaper perspective
    FileView {
        id: perspectiveFile
        printErrors: false
        onLoaded: {
            if (!root.perspectiveWriting)
                root.loadPerspectives(perspectiveFile.text())
        }
        onSaved: root.perspectiveWriting = false
        onSaveFailed: root.perspectiveWriting = false
        onLoadFailed: root.perspectiveLoaded = true
    }

    function ensurePerspectiveFile() {
        if (perspectiveFile.path.length > 0)
            return
        perspectiveFile.path = root.cacheDir + "/perspectives.json"
    }

    function loadPerspectives(text) {
        root.perspectiveWriting = false
        var parsed = ({})
        if (text) {
            try {
                parsed = JSON.parse(text) || ({})
            } catch (error) {
                parsed = ({})
            }
        }
        root.perspectives = parsed
        root.perspectiveLoaded = true
        root.applySavedPerspective()
    }

    function savePerspective() {
        if (root.s.savePerspectivePerWallpaper === false)
            return
        var map = Object.assign({}, root.perspectives)
        map[root.perspectiveKey] = {
            path: root.theme.wallpaperPath,
            angleX: root.numberOr(root.s.angleX, 0),
            angleY: root.numberOr(root.s.angleY, 0),
            angleZ: root.numberOr(root.s.angleZ, 0),
            scale: root.numberOr(root.s.scale, 1.0),
            offsetX: root.numberOr(root.s.offsetX, 0),
            offsetY: root.numberOr(root.s.offsetY, 0),
            savedAt: Date.now()
        }
        root.perspectives = map
        root.ensurePerspectiveFile()
        if (perspectiveFile.path.length > 0) {
            root.perspectiveWriting = true
            perspectiveFile.setText(JSON.stringify(map, null, 2))
        }
    }

    function applySavedPerspective() {
        if (root.s.savePerspectivePerWallpaper === false)
            return
        var entry = root.perspectives[root.perspectiveKey]
        if (!entry)
            return
        root.applyGeometry({
            angleX: root.numberOr(entry.angleX, 0),
            angleY: root.numberOr(entry.angleY, 0),
            angleZ: root.numberOr(entry.angleZ, 0),
            scale: root.numberOr(entry.scale, 1.0),
            offsetX: root.numberOr(entry.offsetX, 0),
            offsetY: root.numberOr(entry.offsetY, 0)
        })
        root.perspectiveApplied()
    }

    function resetPerspective() {
        var map = Object.assign({}, root.perspectives)
        delete map[root.perspectiveKey]
        root.perspectives = map
        root.ensurePerspectiveFile()
        if (perspectiveFile.path.length > 0) {
            root.perspectiveWriting = true
            perspectiveFile.setText(JSON.stringify(map, null, 2))
        }
        root.resetCalibration()
    }

    // ------------------------------------------------------------------ cache
    Process {
        id: ensureCache
        command: ["mkdir", "-p", root.cacheDir]
        onExited: function (exitCode, exitStatus) {
            root.ensurePerspectiveFile()
        }
    }

    Process {
        id: cacheClear
        command: ["sh", "-c",
            "find \"$1\" -maxdepth 1 -type f ! -name 'perspectives.json' -delete",
            "sh", root.cacheDir]
        onExited: function (exitCode, exitStatus) {
            lrclibClient.refresh()
            themeEngine.refresh()
        }
    }

    function clearCache() {
        if (root.cacheDir.indexOf("noctalia-lyrics") < 0)
            return
        cacheClear.running = true
    }

    function refreshAll() {
        lrclibClient.refresh()
        visibilityManager.refresh()
        themeEngine.refresh()
    }

    // ------------------------------------------------------------- visibility
    readonly property bool active: root.s.enabled !== false && !root.userHidden
    readonly property bool lyricsVisible: {
        if (!root.active)
            return false
        if (root.calibrating)
            return true
        if (!root.visibility.shouldShow)
            return false
        if (root.s.hideWhenPaused === true && !root.mpris.playing)
            return false
        return root.mpris.hasSong && root.lyrics.lyricsState !== "idle"
    }
    readonly property real overlayOpacity: root.lyricsVisible ? 1.0 : 0.0
    readonly property string effectiveLayer: root.calibrating
        || root.visibility.surfaceLayer === "overlay"
        ? "overlay" : "bottom"

    readonly property string effectiveLyricsState: {
        var state = root.lyrics.lyricsState
        if (state === "plain" && root.s.showPlainLyrics === false)
            return "notfound"
        return state
    }

    function screenInScope(screen) {
        if (!root.active)
            return false
        if (!screen)
            return false
        if (root.calibrating)
            return screen.name === root.calibrationScreen
        if (root.s.monitorScope === "all")
            return true
        return root.visibility.activeMonitor.length === 0
            || screen.name === root.visibility.activeMonitor
    }

    // --------------------------------------------------------- micro parallax
    readonly property real parallaxX: {
        if (root.s.parallax !== true || !root.visibility.cursorValid)
            return 0
        var screen = Quickshell.screens.length > 0 ? Quickshell.screens[0] : null
        var width = screen ? Number(screen.width) : 1920
        var normalized = root.visibility.cursorX / Math.max(1, width) - 0.5
        var strength = root.s.parallaxStrength !== undefined
            ? Number(root.s.parallaxStrength) : 1.2
        return Math.max(-2, Math.min(2, -normalized * 2 * strength))
    }
    readonly property real parallaxY: {
        if (root.s.parallax !== true || !root.visibility.cursorValid)
            return 0
        var screen = Quickshell.screens.length > 0 ? Quickshell.screens[0] : null
        var height = screen ? Number(screen.height) : 1080
        var normalized = root.visibility.cursorY / Math.max(1, height) - 0.5
        var strength = root.s.parallaxStrength !== undefined
            ? Number(root.s.parallaxStrength) : 1.2
        return Math.max(-2, Math.min(2, normalized * 2 * strength))
    }

    // ----------------------------------------------------------- layer surfaces
    Variants {
        model: Quickshell.screens

        delegate: PanelWindow {
            id: surface

            required property var modelData

            readonly property bool isCalibrationScreen: root.calibrating
                && modelData && modelData.name === root.calibrationScreen

            screen: modelData
            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            focusable: surface.isCalibrationScreen

            WlrLayershell.layer: root.effectiveLayer === "overlay"
                ? WlrLayer.Overlay : WlrLayer.Bottom
            WlrLayershell.namespace: "noctalia-lyrics-3d"
            WlrLayershell.keyboardFocus: surface.isCalibrationScreen
                ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

            // Empty input region: every click reaches the desktop or window below.
            // It is expanded only while the calibration panel is open.
            mask: Region {
                x: 0
                y: 0
                width: surface.isCalibrationScreen ? surface.width : 0
                height: surface.isCalibrationScreen ? surface.height : 0
            }

            Item {
                id: surfaceContent
                anchors.fill: parent

                opacity: root.overlayOpacity
                    * (root.screenInScope(surface.modelData) ? 1 : 0)
                visible: opacity > 0.001

                Behavior on opacity {
                    NumberAnimation {
                        duration: 380
                        easing.type: Easing.InOutQuad
                    }
                }

                LyricsRenderer3D {
                    anchors.fill: parent

                    lyrics: root.lyrics.syncedLyrics
                    lyricState: root.calibrating && !root.mpris.hasSong
                        ? "synced"
                        : (root.mpris.hasSong ? root.effectiveLyricsState : "idle")
                    previewMode: root.calibrating && !root.mpris.hasSong

                    positionMs: root.mpris.positionMs
                    syncOffset: root.numberOr(root.s.syncOffset, 0)
                    songLengthMs: root.mpris.lengthMs
                    plainText: root.lyrics.plainLyrics
                    songTitle: root.mpris.song.title || ""
                    songArtist: root.mpris.song.artist || ""

                    fontFamily: root.s.fontFamily || ""
                    fontSize: Math.max(12, root.numberOr(root.s.fontSize, 38))
                    fontWeight: Math.max(100, root.numberOr(root.s.fontWeight, 600))
                    lineSpacing: root.numberOr(root.s.lineSpacing, 12)
                    maxLines: Math.max(3, root.numberOr(root.s.maxLines, 9))
                    widthPercent: Math.max(0.2, Math.min(1.0,
                        root.numberOr(root.s.widthPercent, 0.62)))
                    offsetX: root.numberOr(root.s.offsetX, 0)
                    offsetY: root.numberOr(root.s.offsetY, 0)
                    angleX: root.numberOr(root.s.angleX, 0) + root.parallaxY
                    angleY: root.numberOr(root.s.angleY, 0) + root.parallaxX
                    angleZ: root.numberOr(root.s.angleZ, 0)
                    sceneScale: Math.max(0.1, root.numberOr(root.s.scale, 1.0))
                    depthScale: Math.max(0.5, Math.min(1.0,
                        root.numberOr(root.s.depthScale, 0.92)))
                    blurAmount: Math.max(0, Math.min(1,
                        root.numberOr(root.s.blurAmount, 0.45)))
                    activeGlow: Math.max(0, Math.min(1,
                        root.numberOr(root.s.activeGlow, 0.55)))
                    textScrim: Math.max(0, Math.min(1,
                        root.numberOr(root.s.textScrim, 0)))

                    textColor: root.theme.textColor
                    accentColor: root.theme.accentColor
                    scrimColor: root.theme.scrimColor
                }

                CalibrationOverlay {
                    anchors.fill: parent
                    visible: surface.isCalibrationScreen

                    angleX: root.numberOr(root.s.angleX, 0)
                    angleY: root.numberOr(root.s.angleY, 0)
                    angleZ: root.numberOr(root.s.angleZ, 0)
                    sceneScale: root.numberOr(root.s.scale, 1.0)
                    offsetX: root.numberOr(root.s.offsetX, 0)
                    offsetY: root.numberOr(root.s.offsetY, 0)
                    wallpaperLabel: root.theme.wallpaperPath
                    savedCount: Object.keys(root.perspectives).length
                    accentColor: root.theme.accentColor
                    textColor: "#eef3fb"

                    onEdited: function (values) {
                        root.applyGeometry(values)
                    }
                    onSaveRequested: root.saveCalibration()
                    onCancelRequested: root.cancelCalibration()
                    onResetRequested: root.resetCalibration()
                }
            }
        }
    }

    // -------------------------------------------------------------------- ipc
    IpcHandler {
        target: "plugin:noctalia-lyrics-3d"

        function toggle() {
            root.userHidden = !root.userHidden
        }

        function calibrate() {
            root.startCalibration()
        }

        function refresh() {
            root.refreshAll()
        }
    }
}
