// services/WindowVisibilityManager.qml
// Hyprland IPC visibility manager. Polls hyprctl for the focused window,
// open clients, active workspace and pointer position, then decides whether
// the lyrics surface belongs on the desktop layer or above an allowed window.

import QtQuick
import Quickshell.Io

Item {
    id: root

    // ---------------------------------------------------------------- config
    property bool active: true
    property var allowedWindows: []      // [{ class, title, matchTitle }]
    property string mode: "desktop"      // desktop | always
    property bool hideOnFullscreen: true
    property int pollInterval: 700

    // --------------------------------------------------------------- outputs
    property bool compositorAvailable: false
    property var activeWindow: ({})
    property var clients: []
    property var activeWorkspace: ({})
    property string activeMonitor: ""
    property real cursorX: 0
    property real cursorY: 0
    property bool cursorValid: false

    readonly property bool onDesktop: !root.activeWindow || !root.activeWindow.class
    readonly property bool activeFullscreen: root.activeWindow
        && (Number(root.activeWindow.fullscreen || 0) > 0
            || Number(root.activeWindow.fullscreenClient || 0) > 0)
    readonly property bool activeAllowed: root.windowAllowed(root.activeWindow)
    // An explicitly allow-listed window wins over the fullscreen guard.
    readonly property bool fullscreenBlocks: root.hideOnFullscreen
        && root.activeFullscreen && !root.activeAllowed
    readonly property bool shouldShow: {
        if (!root.active)
            return false
        if (root.mode === "always")
            return !root.fullscreenBlocks
        if (root.onDesktop)
            return true
        if (root.mode === "desktop")
            return false
        if (root.fullscreenBlocks)
            return false
        return root.activeAllowed
    }
    readonly property string surfaceLayer: (root.mode !== "desktop"
        && root.activeAllowed && !root.onDesktop) ? "overlay" : "bottom"

    readonly property string probeScript: "printf '@@A@@'; hyprctl -j activewindow 2>/dev/null; "
        + "printf '\n@@C@@'; hyprctl -j clients 2>/dev/null; "
        + "printf '\n@@W@@'; hyprctl -j activeworkspace 2>/dev/null; "
        + "printf '\n@@P@@'; hyprctl cursorpos 2>/dev/null"

    onActiveChanged: {
        if (root.active)
            root.refresh()
    }
    Component.onCompleted: {
        if (root.active)
            root.refresh()
    }

    Timer {
        // A faster poll is wasteful; 300 ms is the practical floor.
        interval: Math.max(300, Math.min(5000, root.pollInterval))
        repeat: true
        running: root.active
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    Process {
        id: probe
        command: ["sh", "-c", root.probeScript]
        stdout: StdioCollector {
            id: probeOutput
            onStreamFinished: root.applyProbe(probeOutput.text)
        }
        stderr: StdioCollector {}
    }

    // ---------------------------------------------------------------- public
    function refresh() {
        if (!root.active || probe.running)
            return
        probe.running = true
    }


    // --------------------------------------------------------------- helpers
    function section(text, start, end) {
        var from = text.indexOf(start)
        if (from < 0)
            return ""
        from += start.length
        var to = end ? text.indexOf(end, from) : text.length
        if (to < 0)
            to = text.length
        return text.slice(from, to).trim()
    }

    function parseJson(text) {
        if (!text)
            return null
        try {
            return JSON.parse(text)
        } catch (error) {
            return null
        }
    }

    function windowFrom(raw) {
        if (!raw)
            return ({})
        return {
            class: String(raw.class || ""),
            title: String(raw.title || ""),
            address: String(raw.address || ""),
            workspace: raw.workspace ? String(raw.workspace.name || "") : "",
            workspaceId: raw.workspace ? Number(raw.workspace.id || 0) : 0,
            fullscreen: Number(raw.fullscreen || 0),
            fullscreenClient: Number(raw.fullscreenClient || 0),
            monitor: String(raw.monitor || ""),
            floating: raw.floating === true,
            mapped: raw.mapped !== false
        }
    }

    function windowAllowed(win) {
        if (!win || !win.class)
            return false
        var list = root.allowedWindows || []
        for (var i = 0; i < list.length; i++) {
            var entry = list[i]
            if (!entry)
                continue
            if (entry.class && entry.class === win.class) {
                if (entry.matchTitle !== true)
                    return true
                if (entry.title && entry.title === win.title)
                    return true
            } else if (!entry.class && entry.title && entry.title === win.title) {
                return true
            }
        }
        return false
    }

    function applyProbe(text) {
        var raw = String(text || "")
        if (raw.indexOf("@@A@@") < 0) {
            root.compositorAvailable = false
            root.activeWindow = ({})
            root.clients = []
            return
        }

        var activeRaw = root.section(raw, "@@A@@", "@@C@@")
        var clientsRaw = root.section(raw, "@@C@@", "@@W@@")
        var workspaceRaw = root.section(raw, "@@W@@", "@@P@@")
        var cursorRaw = root.section(raw, "@@P@@", "")

        var active = root.parseJson(activeRaw)
        var clientList = root.parseJson(clientsRaw)
        var workspace = root.parseJson(workspaceRaw)

        root.compositorAvailable = activeRaw.charAt(0) === "{"
        root.activeWindow = root.windowFrom(active)
        root.activeWorkspace = workspace || ({})

        var mapped = []
        if (Array.isArray(clientList)) {
            for (var i = 0; i < clientList.length; i++) {
                var entry = root.windowFrom(clientList[i])
                if (entry.mapped && (entry.class.length > 0 || entry.title.length > 0))
                    mapped.push(entry)
            }
        }
        mapped.sort(function (a, b) {
            if (a.workspace === b.workspace)
                return a.class.localeCompare(b.class)
            return a.workspace.localeCompare(b.workspace)
        })
        root.clients = mapped

        root.activeMonitor = String(root.activeWindow.monitor
            || (workspace ? workspace.monitor : "") || "")

        var cursorParts = cursorRaw.split(",")
        if (cursorParts.length >= 2) {
            var x = parseFloat(cursorParts[0])
            var y = parseFloat(cursorParts[1])
            if (!isNaN(x) && !isNaN(y)) {
                root.cursorX = x
                root.cursorY = y
                root.cursorValid = true
            }
        }
    }
}
