// services/MprisMonitor.qml
// Universal MPRIS monitor: discovers every player, exposes millisecond position,
// applies per-player and per-domain filters, and selects one active source.

import QtQuick
import Quickshell
import Quickshell.Services.Mpris

Item {
    id: root

    // ---------------------------------------------------------------- config
    property var disabledPlayers: []          // stable player keys
    property string filterMode: "allowAll"    // allowAll | whitelist
    property var disabledDomains: []
    property var customDomains: []
    readonly property var defaultDomains: [
        "youtube.com",
        "music.youtube.com",
        "soundcloud.com",
        "open.spotify.com"
    ]
    property bool includePaused: true

    // --------------------------------------------------------------- outputs
    readonly property var players: Mpris.players.values
    property var availablePlayers: []         // every detected player, for Settings
    property var song: ({
        valid: false,
        title: "",
        artist: "",
        album: "",
        artUrl: "",
        lengthMs: 0,
        url: "",
        identity: "",
        dbusName: "",
        isBrowser: false
    })
    readonly property bool hasSong: root.song !== null && root.song.valid === true
    property real positionMs: 0
    property real lengthMs: 0
    property var selectedPlayer: null
    readonly property bool playing: root.selectedPlayer !== null
        && root.selectedPlayer.isPlaying === true

    // -------------------------------------------------------------- internal
    property real anchorPosition: 0
    property double anchorTime: 0
    property double lastReadTime: 0
    property string songFingerprint: ""
    property string lastSongKey: ""

    onPlayersChanged: root.scan()
    onDisabledPlayersChanged: root.scan()
    onDisabledDomainsChanged: root.scan()
    onCustomDomainsChanged: root.scan()
    onFilterModeChanged: root.scan()
    onIncludePausedChanged: root.scan()
    Component.onCompleted: root.scan()

    // MPRIS position is not reactive unless explicitly monitored, so sample it
    // periodically and interpolate with a monotonic clock in between.
    Timer {
        interval: 80
        repeat: true
        running: true
        onTriggered: root.tick()
    }

    // Player properties (title, playback state, URL) update without changing the
    // ObjectModel, therefore rebuild the view model once a second.
    Timer {
        interval: 1000
        repeat: true
        running: true
        onTriggered: root.scan()
    }

    Connections {
        target: root.selectedPlayer
        ignoreUnknownSignals: true

        function onTrackChanged() {
            root.syncSong(true)
            root.resetPosition()
        }

        function onPostTrackChanged() {
            root.syncSong(false)
        }

        function onPlaybackStateChanged() {
            root.resetPosition()
            root.scan()
        }

        function onMetadataChanged() {
            root.syncSong(false)
        }
    }

    // ---------------------------------------------------------------- helpers
    function asArray(value) {
        if (!value)
            return []
        return Array.prototype.slice.call(value)
    }

    function hostOf(url) {
        var value = String(url || "").trim().toLowerCase()
        if (!value || value.indexOf("file:") === 0 || value.indexOf("data:") === 0
                || value.indexOf("about:") === 0)
            return ""
        var match = value.match(/^[a-z][a-z0-9+.-]*:\/\/([^\/?#]+)/)
        if (!match)
            return ""
        var authority = match[1].replace(/^[^@]*@/, "")
        authority = authority.replace(/:\d+$/, "")
        if (authority.indexOf("[") === 0)
            return authority       // IPv6 literal, keep the brackets
        return authority.replace(/^www\./, "")
    }

    function normalizePattern(pattern) {
        var value = String(pattern || "").trim().toLowerCase()
        if (!value)
            return ""
        value = value.replace(/^[a-z][a-z0-9+.-]*:\/\//, "")
        value = value.split("/")[0].split("?")[0].split("#")[0]
        value = value.replace(/:\d+$/, "")
        value = value.replace(/^\*\./, "")
        value = value.replace(/^www\./, "")
        return value
    }

    function patternMatches(host, pattern) {
        if (!host || !pattern)
            return false
        var normalized = root.normalizePattern(pattern)
        if (!normalized)
            return false
        return host === normalized || host.slice(-(normalized.length + 1)) === "." + normalized
    }

    function matchingDomain(host, patterns) {
        var list = root.asArray(patterns)
        for (var i = 0; i < list.length; i++) {
            if (root.patternMatches(host, list[i]))
                return String(list[i])
        }
        return ""
    }

    function looksLikeBrowser(player, url) {
        var haystack = String(player.identity || "").toLowerCase() + " "
            + String(player.desktopEntry || "").toLowerCase() + " "
            + String(player.dbusName || "").toLowerCase()
        return /(firefox|librewolf|waterfox|chrom|brave|vivaldi|opera|zen|edge|epiphany|falkon|webkit|browser)/.test(haystack)
    }

    function playerKey(player) {
        var desktop = String(player.desktopEntry || "").toLowerCase()
        if (desktop)
            return "desktop:" + desktop
        var identity = String(player.identity || "").toLowerCase()
        if (identity)
            return "identity:" + identity
        return "dbus:" + String(player.dbusName || "")
    }

    function playerEnabled(player) {
        var disabled = root.asArray(root.disabledPlayers)
        var key = root.playerKey(player)
        var dbus = String(player.dbusName || "")
        var identity = String(player.identity || "")
        for (var i = 0; i < disabled.length; i++) {
            var entry = String(disabled[i] || "")
            if (entry === key || entry === dbus || entry === identity)
                return false
        }
        return true
    }

    function domainDecision(url, browser) {
        if (!browser)
            return { allowed: true, reason: "" }
        var host = root.hostOf(url)
        if (!host) {
            if (root.filterMode === "whitelist")
                return { allowed: false, reason: "URL yok (whitelist)" }
            return { allowed: true, reason: "" }
        }
        var blocked = root.matchingDomain(host, root.disabledDomains)
        if (blocked)
            return { allowed: false, reason: "domain kapalı: " + blocked }
        if (root.filterMode === "whitelist") {
            var known = root.matchingDomain(host, root.defaultDomains)
            if (!known)
                known = root.matchingDomain(host, root.customDomains)
            if (!known)
                return { allowed: false, reason: "whitelist dışı: " + host }
        }
        return { allowed: true, reason: "" }
    }

    function metadataUrl(player) {
        try {
            return player.metadata ? String(player.metadata["xesam:url"] || "") : ""
        } catch (error) {
            return ""
        }
    }

    // ------------------------------------------------------------------ scan
    function scan() {
        var source = root.players || []
        var list = []
        var byId = ({})

        for (var i = 0; i < source.length; i++) {
            var player = source[i]
            if (!player)
                continue
            var url = root.metadataUrl(player)
            var browser = root.looksLikeBrowser(player, url)
            var decision = root.domainDecision(url, browser)
            var title = String(player.trackTitle || "")
            var entry = {
                id: String(player.dbusName || player.identity || ("player-" + i)),
                key: root.playerKey(player),
                dbusName: String(player.dbusName || ""),
                identity: String(player.identity || ""),
                desktopEntry: String(player.desktopEntry || ""),
                title: title,
                artist: String(player.trackArtist || ""),
                album: String(player.trackAlbum || ""),
                artUrl: String(player.trackArtUrl || ""),
                url: url,
                isBrowser: browser,
                playing: player.isPlaying === true,
                enabled: root.playerEnabled(player),
                domainAllowed: decision.allowed,
                reason: decision.reason,
                eligible: root.playerEnabled(player) && decision.allowed && title.length > 0,
                player: player
            }
            list.push(entry)
            byId[entry.id] = entry
        }

        root.availablePlayers = list

        var currentId = root.selectedPlayer ? String(root.selectedPlayer.dbusName || "") : ""
        var currentEntry = currentId ? byId[currentId] : null
        var chosen = null

        if (currentEntry && currentEntry.eligible && currentEntry.playing) {
            chosen = currentEntry.player
        }

        if (!chosen) {
            for (var j = 0; j < list.length; j++) {
                if (list[j].eligible && list[j].playing) {
                    chosen = list[j].player
                    break
                }
            }
        }

        // Keep a paused player selected when nothing else is playing.
        if (!chosen && currentEntry && currentEntry.eligible)
            chosen = currentEntry.player

        if (!chosen && root.includePaused) {
            for (var k = 0; k < list.length; k++) {
                if (list[k].eligible) {
                    chosen = list[k].player
                    break
                }
            }
        }

        root.setSelected(chosen)
        root.syncSong(false)
    }

    function setSelected(player) {
        if (root.selectedPlayer === player) {
            root.syncSong(false)
            return
        }
        root.selectedPlayer = player
        root.songFingerprint = ""
        root.resetPosition()
        root.syncSong(true)
    }

    // ------------------------------------------------------------------ song
    function syncSong(force) {
        var player = root.selectedPlayer
        if (!player) {
            root.song = {
                valid: false, title: "", artist: "", album: "", artUrl: "",
                lengthMs: 0, url: "", identity: "", dbusName: "", isBrowser: false
            }
            root.songFingerprint = ""
            root.lengthMs = 0
            root.positionMs = 0
            return
        }

        var url = root.metadataUrl(player)
        var browser = root.looksLikeBrowser(player, url)
        var newLength = (player.lengthSupported && player.length > 0)
            ? Math.round(Number(player.length) * 1000) : 0
        var next = {
            valid: String(player.trackTitle || "").length > 0,
            title: String(player.trackTitle || ""),
            artist: String(player.trackArtist || ""),
            album: String(player.trackAlbum || ""),
            artUrl: String(player.trackArtUrl || ""),
            lengthMs: newLength,
            url: url,
            identity: String(player.identity || ""),
            dbusName: String(player.dbusName || ""),
            isBrowser: browser
        }

        var fingerprint = [
            next.title, next.artist, next.album, next.artUrl, next.url, next.dbusName
        ].join("\u001f")

        if (!force && fingerprint === root.songFingerprint) {
            if (newLength !== root.lengthMs) {
                root.lengthMs = newLength
                root.song = Object.assign({}, root.song, { lengthMs: newLength })
            }
            return
        }

        root.songFingerprint = fingerprint
        root.lengthMs = newLength
        root.song = next
        root.resetPosition()
    }

    // -------------------------------------------------------------- position
    function resetPosition() {
        var player = root.selectedPlayer
        root.anchorPosition = player ? Math.max(0, Number(player.position || 0) * 1000) : 0
        root.anchorTime = Date.now()
        root.lastReadTime = root.anchorTime
        root.positionMs = root.anchorPosition
    }

    function tick() {
        var player = root.selectedPlayer
        if (!player) {
            if (root.positionMs !== 0)
                root.positionMs = 0
            return
        }

        var now = Date.now()
        var isPlaying = player.isPlaying === true

        // Reading position is always current, but doing it on every frame is
        // wasteful over D-Bus. Re-anchor roughly twice a second and interpolate.
        if (now - root.lastReadTime > 600) {
            root.anchorPosition = Math.max(0, Number(player.position || 0) * 1000)
            root.anchorTime = now
            root.lastReadTime = now
        }

        if (!isPlaying) {
            root.positionMs = root.anchorPosition
            return
        }

        var value = root.anchorPosition + (now - root.anchorTime)
        if (root.lengthMs > 0)
            value = Math.min(value, root.lengthMs)
        root.positionMs = Math.max(0, value)
    }
}
