// services/LrclibClient.qml
// LRCLIB client: /api/get with /api/search fallback, LRC timestamp parsing,
// millisecond timing and a persistent JSON cache in ~/.cache/noctalia-lyrics/.

import QtQuick
import Quickshell.Io

Item {
    id: root

    // ---------------------------------------------------------------- config
    property var song: ({})
    property string cacheDir: ""
    property bool cacheEnabled: true
    property string userAgent: "noctalia-lyrics-3d/1.0.0 (https://github.com/alitura/noctalia-lyrics-3d)"
    property int timeoutSeconds: 12

    // --------------------------------------------------------------- outputs
    property string lyricsState: "idle"      // idle | loading | synced | plain | instrumental | notfound | error
    property var syncedLyrics: []
    property string plainLyrics: ""
    property bool instrumental: false
    property string errorMessage: ""
    property string cacheKey: ""
    property bool cacheHit: false
    property var activeSong: ({})
    property string identity: ""

    readonly property var plainLines: {
        var result = []
        var raw = String(root.plainLyrics || "").split(/\r?\n/)
        for (var i = 0; i < raw.length; i++) {
            var line = raw[i].replace(/\s+/g, " ").trim()
            if (line.length > 0)
                result.push(line)
        }
        return result
    }
    readonly property bool hasLyrics: root.lyricsState === "synced" || root.lyricsState === "plain"
    readonly property string statusText: {
        if (root.lyricsState === "loading")
            return "Sözler aranıyor..."
        if (root.lyricsState === "instrumental")
            return "Enstrümantal parça"
        if (root.lyricsState === "notfound")
            return "LRCLIB'de söz bulunamadı"
        if (root.lyricsState === "error")
            return root.errorMessage || "LRCLIB hatası"
        return ""
    }

    // -------------------------------------------------------------- internal
    property int generation: 0
    property int httpGeneration: 0
    property bool loadingCache: false
    property bool awaitingHttp: false
    property string attempt: ""        // get | search
    property var fallbackPlain: null
    property bool cacheDirReady: false
    property string pendingCacheAction: ""
    property var pendingCachePayload: null
    property int pendingCacheGeneration: -1

    onSongChanged: root.fetch(root.song)
    onCacheDirChanged: root.cacheDirReady = false
    Component.onCompleted: {
        if (root.song && root.song.title)
            root.fetch(root.song)
    }

    FileView {
        id: cacheFile
        printErrors: false
        onLoaded: root.consumeCache(cacheFile.text())
        onLoadFailed: root.consumeCacheMiss()
    }

    // The cache directory is created by Main, but a lyric request can arrive
    // first on startup. This process makes reads/writes wait for mkdir.
    Process {
        id: cacheDirProcess
        command: ["mkdir", "-p", root.cacheDir]
        onExited: function (exitCode, exitStatus) {
            root.cacheDirReady = true
            var action = root.pendingCacheAction
            var payload = root.pendingCachePayload
            var generation = root.pendingCacheGeneration
            root.pendingCacheAction = ""
            root.pendingCachePayload = null
            root.pendingCacheGeneration = -1
            if (generation !== root.generation)
                return
            if (action === "read")
                root.loadCacheNow()
            else if (action === "write" && payload)
                root.writeCacheNow(payload)
        }
    }

    Process {
        id: http
        command: []
        stdout: StdioCollector {
            id: httpStdout
            onStreamFinished: root.handleHttp(httpStdout.text)
        }
        stderr: StdioCollector {}
        onExited: function (exitCode, exitStatus) {
            if (root.awaitingHttp && root.httpGeneration === root.generation)
                root.handleHttp(httpStdout.text || "")
        }
    }

    // ---------------------------------------------------------------- public
    function fetch(candidate) {
        if (!candidate || !candidate.title) {
            root.reset()
            return
        }

        var nextIdentity = root.identityOf(candidate)
        if (nextIdentity === root.identity && root.lyricsState !== "idle"
                && root.lyricsState !== "error" && root.lyricsState !== "notfound")
            return

        // A track often arrives first without a duration. Retry a previous miss
        // once the player reports it, otherwise wait for a real track change.
        if (nextIdentity === root.identity && root.lyricsState === "notfound"
                && Number(root.activeSong.lengthMs || 0) === 0
                && Number(candidate.lengthMs || 0) === 0)
            return

        root.generation++
        root.identity = nextIdentity
        root.activeSong = candidate
        root.cacheKey = root.keyFor(candidate)
        root.cacheHit = false
        root.lyricsState = "loading"
        root.syncedLyrics = []
        root.plainLyrics = ""
        root.instrumental = false
        root.errorMessage = ""
        root.fallbackPlain = null
        root.loadingCache = false
        root.awaitingHttp = false
        root.attempt = ""

        if (root.cacheEnabled && root.cacheDir.length > 0)
            root.loadCache()
        else
            root.requestGet()
    }

    function reset() {
        root.generation++
        root.identity = ""
        root.activeSong = ({})
        root.cacheKey = ""
        root.lyricsState = "idle"
        root.syncedLyrics = []
        root.plainLyrics = ""
        root.instrumental = false
        root.errorMessage = ""
        root.cacheHit = false
        root.loadingCache = false
        root.awaitingHttp = false
        root.fallbackPlain = null
        cacheFile.path = ""
    }

    function refresh() {
        var current = root.song
        root.identity = ""
        root.fetch(current)
    }

    // ---------------------------------------------------------------- helpers
    function asString(value) {
        return value === undefined || value === null ? "" : String(value)
    }

    function normalized(value) {
        return root.asString(value).toLowerCase().replace(/\s+/g, " ").trim()
    }

    function identityOf(candidate) {
        return root.normalized(candidate.artist) + "|"
            + root.normalized(candidate.title) + "|"
            + root.normalized(candidate.album)
    }

    function hash(value) {
        var h = 5381
        var text = String(value)
        for (var i = 0; i < text.length; i++)
            h = ((h * 33) ^ text.charCodeAt(i)) >>> 0
        return h.toString(16)
    }

    function keyFor(candidate) {
        var durationBucket = Math.round(Number(candidate.lengthMs || 0) / 5000) * 5
        return root.hash(root.identityOf(candidate) + "|" + durationBucket)
    }

    // ------------------------------------------------------------ cache read
    function ensureCacheDir() {
        if (root.cacheDir.length === 0)
            return false
        if (root.cacheDirReady)
            return true
        if (!cacheDirProcess.running)
            cacheDirProcess.running = true
        return false
    }

    function loadCache() {
        if (!root.ensureCacheDir()) {
            root.pendingCacheAction = "read"
            root.pendingCachePayload = null
            root.pendingCacheGeneration = root.generation
            return
        }
        root.loadCacheNow()
    }

    function loadCacheNow() {
        root.loadingCache = true
        var path = root.cacheDir + "/" + root.cacheKey + ".json"
        if (cacheFile.path === path)
            cacheFile.reload()
        else
            cacheFile.path = path
    }

    function consumeCache(text) {
        if (!root.loadingCache)
            return
        root.loadingCache = false
        if (!text) {
            root.requestGet()
            return
        }
        try {
            var payload = JSON.parse(text)
            if (payload && payload.version === 2 && payload.key === root.cacheKey) {
                root.applyPayload(payload, true)
                return
            }
        } catch (error) {
            // Corrupt cache entries are simply replaced by a network result.
        }
        root.requestGet()
    }

    function consumeCacheMiss() {
        if (!root.loadingCache)
            return
        root.loadingCache = false
        root.requestGet()
    }

    function writeCache(payload) {
        if (!root.cacheEnabled || !root.cacheDir || !root.cacheKey)
            return
        if (!root.ensureCacheDir()) {
            root.pendingCacheAction = "write"
            root.pendingCachePayload = payload
            root.pendingCacheGeneration = root.generation
            return
        }
        root.writeCacheNow(payload)
    }

    function writeCacheNow(payload) {
        if (!payload || payload.key !== root.cacheKey)
            return
        var path = root.cacheDir + "/" + root.cacheKey + ".json"
        if (cacheFile.path !== path)
            cacheFile.path = path
        cacheFile.setText(JSON.stringify(payload))
    }

    // ------------------------------------------------------------ networking
    function requestGet() {
        root.loadingCache = false
        if (!root.activeSong || !root.activeSong.title) {
            root.reset()
            return
        }
        root.attempt = "get"
        root.httpGeneration = root.generation
        root.awaitingHttp = true

        var params = {
            artist_name: root.asString(root.activeSong.artist),
            track_name: root.asString(root.activeSong.title)
        }
        if (root.asString(root.activeSong.album).length > 0)
            params.album_name = root.asString(root.activeSong.album)
        if (Number(root.activeSong.lengthMs || 0) > 0)
            params.duration = Math.round(Number(root.activeSong.lengthMs) / 1000)

        root.httpGet("https://lrclib.net/api/get", params)
    }

    function requestSearch() {
        root.attempt = "search"
        root.httpGeneration = root.generation
        root.awaitingHttp = true
        root.httpGet("https://lrclib.net/api/search", {
            artist_name: root.asString(root.activeSong.artist),
            track_name: root.asString(root.activeSong.title)
        })
    }

    function httpGet(endpoint, params) {
        var args = [
            "curl", "-sS", "-L", "--max-time", String(root.timeoutSeconds),
            "-H", "User-Agent: " + root.userAgent,
            "-H", "Accept: application/json",
            "-w", "\n__HTTP__%{http_code}",
            "-G", endpoint
        ]
        var keys = Object.keys(params || {})
        for (var i = 0; i < keys.length; i++) {
            var value = params[keys[i]]
            if (value === undefined || value === null || String(value).length === 0)
                continue
            args.push("--data-urlencode")
            args.push(keys[i] + "=" + String(value))
        }
        http.exec(args)
    }

    function handleHttp(raw) {
        if (!root.awaitingHttp)
            return
        root.awaitingHttp = false
        if (root.generation !== root.httpGeneration)
            return

        var text = String(raw || "")
        if (text.length === 0) {
            root.fail("LRCLIB'ye ulaşılamadı (curl)")
            return
        }

        var marker = text.lastIndexOf("__HTTP__")
        var body = marker >= 0 ? text.slice(0, marker) : text
        var status = marker >= 0 ? parseInt(text.slice(marker + 8).trim(), 10) : 0
        var data = null

        if (body) {
            try {
                data = JSON.parse(body)
            } catch (error) {
                data = null
            }
        }

        if (status === 200 && data !== null) {
            if (root.attempt === "get") {
                if (data && data.syncedLyrics) {
                    root.applyApi(data)
                    return
                }
                // Keep plain lyrics as a fallback while trying to find a synced
                // version for the same track.
                if (data && (data.plainLyrics || data.instrumental)) {
                    root.fallbackPlain = data
                    root.requestSearch()
                    return
                }
                root.requestSearch()
                return
            }

            if (Array.isArray(data)) {
                var best = root.pickSearchResult(data)
                if (best) {
                    root.fallbackPlain = null
                    root.applyApi(best)
                } else if (root.fallbackPlain) {
                    root.applyApi(root.fallbackPlain)
                    root.fallbackPlain = null
                } else {
                    root.notFound()
                }
                return
            }
            root.fail("LRCLIB yanıtı beklenen biçimde değil")
            return
        }

        if (root.attempt === "get" && (status === 404 || status === 400)) {
            root.requestSearch()
            return
        }

        if (root.attempt === "search" && root.fallbackPlain) {
            // The search endpoint failed; the earlier /api/get plain result is
            // still better than showing nothing.
            root.applyApi(root.fallbackPlain)
            root.fallbackPlain = null
            return
        }

        if (status === 429)
            root.fail("LRCLIB istek sınırı (HTTP 429) - biraz sonra tekrar deneyin")
        else if (status === 0)
            root.fail("LRCLIB yanıtı okunamadı")
        else
            root.fail("LRCLIB HTTP " + status)
    }

    function scoreResult(result) {
        if (!result)
            return -1000000
        var score = 0
        if (result.syncedLyrics)
            score += 1000
        if (result.plainLyrics)
            score += 100
        if (result.instrumental)
            score += 50
        if (result.trackName && root.normalized(result.trackName) === root.normalized(root.activeSong.title))
            score += 120
        if (result.artistName && root.normalized(root.activeSong.artist).length > 0
                && root.normalized(result.artistName).indexOf(root.normalized(root.activeSong.artist)) >= 0)
            score += 60
        if (result.albumName && root.normalized(result.albumName) === root.normalized(root.activeSong.album))
            score += 30
        var expected = Number(root.activeSong.lengthMs || 0) / 1000
        if (result.duration && expected > 0)
            score -= Math.min(400, Math.abs(Number(result.duration) - expected) * 8)
        return score
    }

    function pickSearchResult(results) {
        var best = null
        var bestScore = -1000000
        for (var i = 0; i < results.length; i++) {
            var candidate = results[i]
            if (!candidate)
                continue
            if (!candidate.syncedLyrics && !candidate.plainLyrics && !candidate.instrumental)
                continue
            var score = root.scoreResult(candidate)
            if (score > bestScore) {
                bestScore = score
                best = candidate
            }
        }
        return best
    }

    // --------------------------------------------------------------- parsing
    function applyApi(data) {
        var parsed = root.parseLrc(root.asString(data.syncedLyrics))
        var plain = root.asString(data.plainLyrics)
        var isInstrumental = data.instrumental === true
        var nextState = parsed.length > 0 ? "synced"
            : (isInstrumental ? "instrumental" : (plain.length > 0 ? "plain" : "notfound"))

        var payload = {
            version: 2,
            key: root.cacheKey,
            state: nextState,
            lyrics: parsed,
            plain: plain,
            instrumental: isInstrumental,
            title: root.asString(data.trackName || root.activeSong.title),
            artist: root.asString(data.artistName || root.activeSong.artist),
            album: root.asString(data.albumName || root.activeSong.album),
            duration: Number(data.duration || 0),
            source: "lrclib",
            fetchedAt: Date.now()
        }

        root.applyPayload(payload, false)
        if (nextState !== "notfound")
            root.writeCache(payload)
    }

    function applyPayload(payload, fromCache) {
        if (!payload || (payload.key && payload.key !== root.cacheKey))
            return
        root.lyricsState = payload.state || "notfound"
        root.syncedLyrics = Array.isArray(payload.lyrics) ? payload.lyrics : []
        root.plainLyrics = root.asString(payload.plain)
        root.instrumental = payload.instrumental === true
        root.errorMessage = ""
        root.cacheHit = fromCache === true
    }

    function parseLrc(text) {
        var result = []
        if (!text)
            return result

        var rows = String(text).split(/\r?\n/)
        var offset = 0

        // The offset tag is normally first but may legally appear anywhere.
        for (var o = 0; o < rows.length; o++) {
            var offsetMatch = rows[o].match(/^\s*\[offset:\s*([+-]?\d+)\s*\]/i)
            if (offsetMatch)
                offset = parseInt(offsetMatch[1], 10) || 0
        }

        for (var i = 0; i < rows.length; i++) {
            var row = rows[i]
            var content = row.replace(/\[[^\]]*\]/g, " ")
                .replace(/<[^>]*>/g, "")
                .replace(/\s+/g, " ")
                .trim()
            if (!content)
                continue

            var pattern = /\[(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?\]/g
            var match = null
            while ((match = pattern.exec(row)) !== null) {
                var minutes = parseInt(match[1], 10) || 0
                var seconds = parseInt(match[2], 10) || 0
                var fraction = match[3] ? parseInt(match[3], 10) : 0
                var ms = minutes * 60000 + seconds * 1000
                if (match[3]) {
                    if (match[3].length === 1)
                        ms += fraction * 100
                    else if (match[3].length === 2)
                        ms += fraction * 10
                    else
                        ms += fraction
                }
                result.push({ time: Math.max(0, ms + offset), text: content })
            }
        }

        result.sort(function (a, b) { return a.time - b.time })

        var deduped = []
        for (var j = 0; j < result.length; j++) {
            if (deduped.length > 0 && Math.abs(deduped[deduped.length - 1].time - result[j].time) < 1)
                deduped[deduped.length - 1] = result[j]
            else
                deduped.push(result[j])
        }
        return deduped
    }

    function notFound() {
        root.lyricsState = "notfound"
        root.syncedLyrics = []
        root.plainLyrics = ""
        root.instrumental = false
        root.errorMessage = ""
    }

    function fail(message) {
        root.lyricsState = "error"
        root.errorMessage = message
        root.syncedLyrics = []
        root.plainLyrics = ""
    }
}
