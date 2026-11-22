--!nonstrict
-- service.luau — Noctalia v5 lyric service.
--
-- The Luau service owns the authoritative state. A small Quickshell companion
-- (ui/Renderer.qml) draws the real 3D layer because Noctalia's native ui tree
-- only offers 2D affine transforms and no depth blur.

local CACHE = noctalia.expandPath("~/.cache/noctalia-lyrics")
local STATE_PATH = CACHE .. "/state.json"
local CONTROL_PATH = CACHE .. "/control.json"
local PID_PATH = CACHE .. "/renderer.pid"
local LOG_PATH = CACHE .. "/renderer.log"
local CONFIG_PREFIX = 'plugin_settings."alitura/noctalia-lyrics-3d".'
local PLUGIN_ID = "alitura/noctalia-lyrics-3d"
local DISPLAY_MODES = { "auto", "kinetic", "lineByLine", "singleFocus" }
local LRCLIB_UA = "noctalia-lyrics-3d/2.0 (Noctalia v5 plugin)"
local POLL_MS = 500

noctalia.mkdirAll(CACHE)
noctalia.setUpdateInterval(POLL_MS)

local S = {}
local song = {
    hasSong = false, title = "", artist = "", album = "", artUrl = "",
    identity = "", busName = "", url = "", playing = false,
    positionMs = 0, lengthMs = 0, rate = 1, status = "Stopped",
}
local lyrics = {}
local plainText = ""
local lyricsState = "idle"
local lyricsProvider = ""
local lyricsError = ""
local currentSongKey = ""
local currentTrackKey = ""
local fetchGeneration = 0
local trackUrl = ""
local trackUrlKey = ""
local calibrating = false
local userHidden = false
local visible = false
local layer = "bottom"
local activeWindow = nil
local windows = {}
local players = {}
local focusedMonitor = ""
local cursorX = 0
local cursorY = 0
local screenWidth = 1920
local screenHeight = 1080
local tick = 0
local hyprBusy = false
local lastPanelJson = ""

local function log(message)
    noctalia.log("[noctalia-lyrics-3d] " .. tostring(message))
end

local function trim(value)
    return (tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function lower(value)
    return trim(value):lower()
end

local function numberOr(value, fallback)
    local n = tonumber(value)
    if n == nil then return fallback end
    return n
end

local function boolOr(value, fallback)
    if type(value) == "boolean" then return value end
    return fallback
end

local function strList(value)
    local result = {}
    if type(value) == "table" then
        for _, item in ipairs(value) do
            local text = trim(item)
            if text ~= "" then result[#result + 1] = text end
        end
    elseif type(value) == "string" then
        for part in value:gmatch("[^,]+") do
            local text = trim(part)
            if text ~= "" then result[#result + 1] = text end
        end
    end
    return result
end

local function cfg(key, fallback)
    local ok, value = pcall(function() return noctalia.getConfig(key) end)
    if ok and value ~= nil then return value end
    return fallback
end

local POSITION_PRESETS = {
    topCenter = { x = 50, y = 18 },
    leftCenter = { x = 24, y = 50 },
    rightCenter = { x = 76, y = 50 },
    bottomCenter = { x = 50, y = 78 },
}

local function readSettings()
    local preset = tostring(cfg("position_preset", "custom") or "custom")
    local presetPosition = POSITION_PRESETS[preset]
    local positionX = numberOr(cfg("position_x", 50), 50)
    local positionY = numberOr(cfg("position_y", 78), 78)
    if presetPosition ~= nil then
        positionX = presetPosition.x
        positionY = presetPosition.y
    end
    S = {
        enabled = boolOr(cfg("enabled", true), true),
        fontSize = numberOr(cfg("font_size", 38), 38),
        fontFamily = tostring(cfg("font_family", "") or ""),
        fontWeight = numberOr(cfg("font_weight", 600), 600),
        lineSpacing = numberOr(cfg("line_spacing", 12), 12),
        maxLines = numberOr(cfg("max_lines", 9), 9),
        widthPercent = numberOr(cfg("width_percent", 0.62), 0.62),
        angleX = numberOr(cfg("angle_x", 0), 0),
        angleY = numberOr(cfg("angle_y", 0), 0),
        angleZ = numberOr(cfg("angle_z", 0), 0),
        sceneScale = numberOr(cfg("scene_scale", 1.0), 1.0),
        offsetX = numberOr(cfg("offset_x", 0), 0),
        offsetY = numberOr(cfg("offset_y", 0), 0),
        positionPreset = preset,
        positionX = positionX,
        positionY = positionY,
        dynamicPlacement = boolOr(cfg("dynamic_placement", true), true),
        centerSafeZone = numberOr(cfg("center_safe_zone", 32), 32),
        displayMode = tostring(cfg("display_mode", "auto") or "auto"),
        showNowPlaying = boolOr(cfg("show_now_playing", true), true),
        showNextLine = boolOr(cfg("show_next_line", false), false),
        nowPlayingPosition = tostring(cfg("now_playing_position", "topCenter") or "topCenter"),
        typographyStyle = tostring(cfg("typography_style", "modern") or "modern"),
        typographyMaxWidth = numberOr(cfg("typography_max_width", 480), 480),
        depthScale = numberOr(cfg("depth_scale", 0.92), 0.92),
        blurAmount = numberOr(cfg("blur_amount", 0.45), 0.45),
        activeGlow = numberOr(cfg("active_glow", 0.55), 0.55),
        parallax = boolOr(cfg("parallax", false), false),
        parallaxStrength = numberOr(cfg("parallax_strength", 1.2), 1.2),
        syncOffset = numberOr(cfg("sync_offset", 0), 0),
        filterMode = tostring(cfg("filter_mode", "allowAll") or "allowAll"),
        disabledDomains = strList(cfg("disabled_domains", {})),
        customDomains = strList(cfg("custom_domains", {})),
        disabledPlayers = strList(cfg("disabled_players", {})),
        allowedWindows = strList(cfg("allowed_windows", {})),
        visibilityMode = tostring(cfg("visibility_mode", "desktop") or "desktop"),
        hideOnFullscreen = boolOr(cfg("hide_on_fullscreen", true), true),
        hideWhenPaused = boolOr(cfg("hide_when_paused", false), false),
        monitorScope = tostring(cfg("monitor_scope", "focused") or "focused"),
        themeMode = tostring(cfg("theme_mode", "auto") or "auto"),
        accentBlend = numberOr(cfg("accent_blend", 0.65), 0.65),
        customTextColor = tostring(cfg("custom_text_color", "#f6f8ff") or "#f6f8ff"),
        customAccentColor = tostring(cfg("custom_accent_color", "#8ab4f8") or "#8ab4f8"),
        textScrim = numberOr(cfg("text_scrim", 0), 0),
        wallpaperPathOverride = tostring(cfg("wallpaper_path_override", "") or ""),
        showPlainLyrics = boolOr(cfg("show_plain_lyrics", true), true),
        cacheEnabled = boolOr(cfg("cache_enabled", true), true),
        savePerspectives = boolOr(cfg("save_perspectives", true), true),
    }
end

readSettings()

-- ── small helpers ───────────────────────────────────────────────────────────

local function urlEncode(value)
    return (tostring(value or ""):gsub("([^%w%-_%.~])", function(char)
        return string.format("%%%02X", string.byte(char))
    end))
end

local function hashText(value)
    local h = 5381
    local text = tostring(value or "")
    for i = 1, #text do
        h = (h * 33 + text:byte(i)) % 4294967296
    end
    return string.format("%08x", h)
end

local function sanitizePart(value)
    local text = trim(value):gsub("[^%w%-_%. ]", "_")
    text = text:gsub("%s+", " ")
    if #text > 64 then text = text:sub(1, 64) end
    return text
end

local function jsonEncode(value)
    local ok, raw = pcall(function() return noctalia.json.encode(value) end)
    if ok and type(raw) == "string" then return raw end
    return nil
end

local function jsonDecode(raw)
    if type(raw) ~= "string" or trim(raw) == "" then return nil end
    local ok, value = pcall(function() return noctalia.json.decode(raw) end)
    if ok then return value end
    return nil
end

local function writeState()
    local payload = {
        version = 2,
        updatedAtMs = noctalia.nowMs(),
        enabled = S.enabled,
        hasSong = song.hasSong,
        title = song.title,
        artist = song.artist,
        album = song.album,
        artUrl = song.artUrl,
        identity = song.identity,
        busName = song.busName,
        url = song.url,
        playing = song.playing,
        status = song.status,
        positionMs = song.positionMs,
        lengthMs = song.lengthMs,
        rate = song.rate,
        lyricsState = lyricsState,
        lyricsProvider = lyricsProvider,
        lyricsError = lyricsError,
        lyrics = lyrics,
        plainText = plainText,
        visible = visible,
        layer = layer,
        calibrating = calibrating,
        userHidden = userHidden,
        focusedMonitor = focusedMonitor,
        cursorX = cursorX,
        cursorY = cursorY,
        screenWidth = screenWidth,
        screenHeight = screenHeight,
        settings = S,
    }
    local raw = jsonEncode(payload)
    if raw ~= nil then noctalia.writeFile(STATE_PATH, raw) end
end

local function setLyricsIdle()
    lyrics = {}
    plainText = ""
    lyricsState = "idle"
    lyricsProvider = ""
    lyricsError = ""
end

-- ── LRC parser (millisecond timestamps) ─────────────────────────────────────

local function stampToMs(stamp)
    local minutes, seconds, fraction = stamp:match("^(%d+):(%d+)%.(%d+)$")
    if minutes == nil then
        minutes, seconds = stamp:match("^(%d+):(%d+)$")
        fraction = ""
    end
    if minutes == nil then return nil end
    local ms = tonumber(minutes) * 60000 + tonumber(seconds) * 1000
    if fraction ~= "" then
        if #fraction == 1 then ms = ms + tonumber(fraction) * 100
        elseif #fraction == 2 then ms = ms + tonumber(fraction) * 10
        else ms = ms + tonumber(fraction:sub(1, 3)) end
    end
    return ms
end

local function parseLrc(raw)
    local rows = {}
    local offset = 0
    for line in tostring(raw or ""):gmatch("[^\r\n]+") do
        local offsetValue = line:match("^%[offset:([%-%d]+)%]")
        if offsetValue ~= nil then
            offset = numberOr(offsetValue, 0)
        else
            local rest = line
            local stamps = {}
            while true do
                local stamp, after = rest:match("^%[(%d+:%d+[%.%d]*)%](.*)$")
                if stamp == nil then break end
                local ms = stampToMs(stamp)
                if ms ~= nil then stamps[#stamps + 1] = ms end
                rest = after
            end
            local text = trim(rest)
            local words = {}
            if text:find("<%d+:%d+[%.%d]*>") ~= nil then
                for wordStamp, wordText in text:gmatch("<(%d+:%d+[%.%d]*)>([^<]*)") do
                    local wordMs = stampToMs(wordStamp)
                    local word = trim(wordText)
                    if wordMs ~= nil and word ~= "" then
                        words[#words + 1] = {
                            time = math.max(0, wordMs - offset),
                            text = word,
                        }
                    end
                end
                if #words > 0 then
                    local joined = {}
                    for _, word in ipairs(words) do joined[#joined + 1] = word.text end
                    text = table.concat(joined, " ")
                end
            end
            if #stamps > 0 and text ~= "" then
                for _, ms in ipairs(stamps) do
                    rows[#rows + 1] = {
                        time = math.max(0, ms - offset),
                        text = text,
                        words = #words > 0 and words or nil,
                    }
                end
            end
        end
    end
    table.sort(rows, function(a, b) return a.time < b.time end)
    return rows
end

-- ── cache ───────────────────────────────────────────────────────────────────

local function cachePath(artist, title)
    local base = sanitizePart(artist)
    if base ~= "" then base = base .. " - " .. sanitizePart(title) else base = sanitizePart(title) end
    if base == "" then base = "untitled" end
    return CACHE .. "/" .. base .. "-" .. hashText(artist .. "|" .. title) .. ".json"
end

local function readCache(artist, title)
    if not S.cacheEnabled then return nil end
    local raw = noctalia.readFile(cachePath(artist, title))
    return jsonDecode(raw)
end

local function writeCache(artist, title, synced, plain, provider, instrumental)
    if not S.cacheEnabled then return end
    local raw = jsonEncode({
        title = title, artist = artist, syncedLyrics = synced or "",
        plainLyrics = plain or "", provider = provider or "LRCLIB",
        instrumental = instrumental == true, fetchedAtMs = noctalia.nowMs(),
    })
    if raw ~= nil then noctalia.writeFile(cachePath(artist, title), raw) end
end

-- ── lyrics state transitions ────────────────────────────────────────────────

local function applyLyrics(synced, plain, provider, instrumental)
    lyrics = {}
    plainText = ""
    lyricsProvider = provider or "LRCLIB"
    lyricsError = ""
    if trim(synced) ~= "" then
        local ok, parsed = pcall(parseLrc, synced)
        if ok and type(parsed) == "table" and #parsed > 0 then
            lyrics = parsed
            lyricsState = "synced"
            writeCache(song.artist, song.title, synced, plain, provider, false)
            return true
        end
    end
    if trim(plain) ~= "" and S.showPlainLyrics then
        lyricsState = "plain"
        plainText = trim(plain)
        writeCache(song.artist, song.title, "", plain, provider, false)
        return true
    end
    if instrumental == true then
        lyricsState = "instrumental"
        return true
    end
    lyricsState = "notfound"
    return false
end

local function httpGet(url, callback)
    noctalia.runAsync({ "curl", "-sSf", "-m", "8", "-4", "-H", "User-Agent: " .. LRCLIB_UA, url },
        function(result)
            callback({
                ok = type(result) == "table" and result.exitCode == 0,
                body = type(result) == "table" and (result.stdout or "") or "",
                exit = type(result) == "table" and result.exitCode or -1,
            })
        end)
end

local function fetchLyrics()
    local artist, title, album = song.artist, song.title, song.album
    if trim(title) == "" then
        lyricsState = "idle"
        return
    end

    local cached = readCache(artist, title)
    if cached ~= nil then
        local synced = trim(cached.syncedLyrics or "")
        local plain = trim(cached.plainLyrics or "")
        if synced ~= "" or (plain ~= "" and S.showPlainLyrics) or cached.instrumental == true then
            applyLyrics(synced, plain, cached.provider or "cache", cached.instrumental == true)
            if lyricsState ~= "notfound" then return end
        end
    end

    local generation = fetchGeneration
    lyricsState = "loading"
    lyricsError = ""
    lyrics = {}
    plainText = ""

    noctalia.runAsync({ "sleep", "15" }, function()
        if generation == fetchGeneration and lyricsState == "loading" then
            lyricsState = "error"
            lyricsError = "LRCLIB isteği zaman aşımına uğradı"
            writeState()
        end
    end)

    local duration = 0
    if song.lengthMs > 0 then duration = math.floor(song.lengthMs / 1000 + 0.5) end
    local getUrl = "https://lrclib.net/api/get?track_name=" .. urlEncode(title)
        .. "&artist_name=" .. urlEncode(artist or "")
    if trim(album) ~= "" then getUrl = getUrl .. "&album_name=" .. urlEncode(album) end
    if duration > 0 then getUrl = getUrl .. "&duration=" .. tostring(duration) end

    local function searchFallback(hadTransportError)
        if generation ~= fetchGeneration then return end
        local searchUrl = "https://lrclib.net/api/search?track_name=" .. urlEncode(title)
            .. "&artist_name=" .. urlEncode(artist or "")
        httpGet(searchUrl, function(response)
            if generation ~= fetchGeneration then return end
            if not response.ok then
                lyricsState = hadTransportError and "error" or "notfound"
                if lyricsState == "error" then lyricsError = "LRCLIB bağlantı hatası" end
                writeState()
                return
            end
            local list = jsonDecode(response.body)
            if type(list) ~= "table" or #list == 0 then
                lyricsState = "notfound"
                writeState()
                return
            end

            local best, bestScore = nil, -1
            for _, candidate in ipairs(list) do
                local score = 0
                if lower(candidate.trackName or "") == lower(title) then score = score + 4 end
                if lower(candidate.artistName or "") == lower(artist or "") then score = score + 3 end
                local candidateDuration = numberOr(candidate.duration, 0)
                if duration > 0 and candidateDuration > 0 then
                    local delta = math.abs(candidateDuration - duration)
                    if delta <= 2 then score = score + 3
                    elseif delta <= 8 then score = score + 1 end
                end
                if trim(candidate.syncedLyrics or "") ~= "" then score = score + 2 end
                if candidate.instrumental == true then score = score - 1 end
                if score > bestScore then best, bestScore = candidate, score end
            end
            if best == nil then
                lyricsState = "notfound"
            else
                applyLyrics(best.syncedLyrics or "", best.plainLyrics or "",
                    "LRCLIB", best.instrumental == true)
            end
            writeState()
        end)
    end

    httpGet(getUrl, function(response)
        if generation ~= fetchGeneration then return end
        if response.ok then
            local data = jsonDecode(response.body)
            if type(data) == "table" then
                local synced = trim(data.syncedLyrics or "")
                local plain = trim(data.plainLyrics or "")
                if synced ~= "" or plain ~= "" or data.instrumental == true then
                    local accepted = applyLyrics(synced, plain, "LRCLIB", data.instrumental == true)
                    if accepted or data.instrumental == true or not S.showPlainLyrics then
                        writeState()
                        return
                    end
                end
            end
            searchFallback(false)
        else
            -- curl -f exits 22 on HTTP 4xx/5xx (a normal "no match").
            searchFallback(response.exit ~= 22)
        end
    end)
end

local function invalidateLyrics()
    fetchGeneration = fetchGeneration + 1
    currentTrackKey = ""
    setLyricsIdle()
end

-- ── source / domain filters ─────────────────────────────────────────────────

local DEFAULT_DOMAINS = {
    "youtube.com", "music.youtube.com", "open.spotify.com", "spotify.com",
    "soundcloud.com", "bandcamp.com", "deezer.com", "tidal.com",
    "music.apple.com", "music.163.com", "y.qq.com", "bilibili.com",
}
local BROWSER_HINTS = { "brave", "firefox", "chromium", "chrome", "vivaldi", "zen", "opera" }

local function extractDomain(url)
    local text = lower(url)
    if text == "" then return "" end
    text = text:gsub("^[%w+.-]+://", "")
    text = text:gsub("^[^/@]*@", "")
    text = text:gsub("[/?#].*$", "")
    text = text:gsub(":%d+$", "")
    text = text:gsub("^www%.", "")
    return text
end

local function listHasDomain(list, domain)
    if domain == "" then return false end
    for _, entry in ipairs(list) do
        local value = lower(entry):gsub("^https?://", ""):gsub("[/?#].*$", ""):gsub("^www%.", "")
        if value ~= "" and (domain == value or domain:sub(-(#value + 1)) == "." .. value) then
            return true
        end
    end
    return false
end

local function sourceAllowed()
    local identity = lower(song.identity)
    for _, blocked in ipairs(S.disabledPlayers) do
        local needle = lower(blocked)
        if needle ~= "" and (identity:find(needle, 1, true) or lower(song.busName):find(needle, 1, true)) then
            return false
        end
    end
    if S.filterMode ~= "whitelist" then return true end
    local domain = extractDomain(song.url)
    if domain ~= "" then
        if listHasDomain(S.disabledDomains, domain) then return false end
        if listHasDomain(DEFAULT_DOMAINS, domain) or listHasDomain(S.customDomains, domain) then return true end
        return false
    end
    -- Local players usually expose no xesam:url. Browsers in whitelist mode
    -- without a URL cannot be validated, so keep them hidden.
    for _, hint in ipairs(BROWSER_HINTS) do
        if identity:find(hint, 1, true) or lower(song.busName):find(hint, 1, true) then return false end
    end
    return true
end

local function windowMatches(value, class, title)
    local needle = lower(value)
    if needle == "" then return false end
    return lower(class):find(needle, 1, true) ~= nil or lower(title):find(needle, 1, true) ~= nil
end

local function activeWindowAllowed()
    if activeWindow == nil then return false end
    for _, entry in ipairs(S.allowedWindows) do
        if windowMatches(entry, activeWindow.class or "", activeWindow.title or "") then return true end
    end
    return false
end

local function desktopWindow()
    local class = lower(activeWindow and activeWindow.class or "")
    return class == "" or class == "noctalia" or class == "hyprland"
        or class == "swaybg" or class == "desktop"
end

local function computeVisibility()
    if not S.enabled or userHidden then return false, "bottom" end
    if calibrating then return true, "overlay" end
    if not song.hasSong then return false, "bottom" end
    if S.hideWhenPaused and not song.playing then return false, "bottom" end
    if S.hideOnFullscreen and activeWindow ~= nil and numberOr(activeWindow.fullscreen, 0) > 0 then
        return false, "bottom"
    end
    if not sourceAllowed() then return false, "bottom" end

    if S.visibilityMode == "always" then return true, "overlay" end
    if S.visibilityMode == "allowlist" then
        if activeWindowAllowed() then return true, "overlay" end
        if desktopWindow() then return true, "bottom" end
        return false, "bottom"
    end
    if desktopWindow() then return true, "bottom" end
    return false, "bottom"
end

-- ── Hyprland / MPRIS metadata ───────────────────────────────────────────────

local function fetchTrackUrl(busName, key)
    if busName == "" then return end
    noctalia.runAsync({ "busctl", "--user", "--json=short", "call", busName,
        "/org/mpris/MediaPlayer2", "org.freedesktop.DBus.Properties", "Get", "ss",
        "org.mpris.MediaPlayer2.Player", "Metadata" }, function(result)
        if key ~= currentSongKey or result.exitCode ~= 0 then return end
        local payload = jsonDecode(result.stdout or "")
        local outer = payload and payload.data
        local inner = type(outer) == "table" and outer[1] or nil
        local fields = type(inner) == "table" and inner.data or nil
        if type(fields) ~= "table" then return end
        local value = fields["xesam:url"]
        if type(value) == "table" and value.type == "s" then
            trackUrl = tostring(value.data or "")
            trackUrlKey = key
            song.url = trackUrl
            local nextVisible, nextLayer = computeVisibility()
            visible, layer = nextVisible, nextLayer
            writeState()
        end
    end)
end

local function parseActiveWindow(raw)
    local data = jsonDecode(raw)
    if type(data) ~= "table" or trim(data.class or "") == "" and trim(data.title or "") == "" then
        return nil
    end
    return {
        class = tostring(data.class or ""),
        title = tostring(data.title or ""),
        address = tostring(data.address or ""),
        fullscreen = numberOr(data.fullscreen, 0),
        workspace = type(data.workspace) == "table" and tostring(data.workspace.name or "") or "",
    }
end

local function parseClients(raw)
    local data = jsonDecode(raw)
    local result = {}
    if type(data) ~= "table" then return result end
    for _, client in ipairs(data) do
        local class = tostring(client.class or "")
        local title = tostring(client.title or "")
        if class ~= "" or title ~= "" then
            result[#result + 1] = {
                class = class, title = title,
                address = tostring(client.address or ""),
                workspace = type(client.workspace) == "table"
                    and tostring(client.workspace.name or "") or "",
            }
        end
        if #result >= 30 then break end
    end
    return result
end

local function publishPanel()
    local panelState = {
        updatedAtMs = noctalia.nowMs(),
        activeWindow = activeWindow,
        windows = windows,
        players = players,
        visible = visible,
        layer = layer,
        calibrating = calibrating,
        lyricsState = lyricsState,
        lyricsProvider = lyricsProvider,
        title = song.title,
        artist = song.artist,
        identity = song.identity,
        playing = song.playing,
        url = song.url,
        settings = S,
    }
    local raw = jsonEncode(panelState)
    if raw ~= nil and raw ~= lastPanelJson then
        lastPanelJson = raw
        noctalia.state.set("lyrics3d_panel", panelState)
    end
end

local function refreshPlayers()
    noctalia.runAsync({ "playerctl", "-l" }, function(result)
        if result.exitCode ~= 0 then return end
        local nextPlayers = {}
        for name in tostring(result.stdout or ""):gmatch("[^\r\n]+") do
            if trim(name) ~= "" then nextPlayers[#nextPlayers + 1] = trim(name) end
        end
        players = nextPlayers
    end)
end

local function pollHypr()
    if hyprBusy then return end
    hyprBusy = true
    refreshPlayers()
    noctalia.runAsync({ "hyprctl", "-j", "activewindow" }, function(activeResult)
        if activeResult.exitCode == 0 then
            activeWindow = parseActiveWindow(activeResult.stdout or "")
        end
        noctalia.runAsync({ "hyprctl", "-j", "clients" }, function(clientsResult)
            if clientsResult.exitCode == 0 then windows = parseClients(clientsResult.stdout or "") end
            noctalia.runAsync({ "hyprctl", "-j", "monitors" }, function(monitorResult)
                local monitors = jsonDecode(monitorResult.stdout or "")
                if type(monitors) == "table" then
                    for _, monitor in ipairs(monitors) do
                        if monitor.focused == true then
                            focusedMonitor = tostring(monitor.name or "")
                            screenWidth = numberOr(monitor.width, screenWidth)
                            screenHeight = numberOr(monitor.height, screenHeight)
                        end
                    end
                end
                if S.parallax then
                    noctalia.runAsync({ "hyprctl", "cursorpos" }, function(cursorResult)
                        local x, y = tostring(cursorResult.stdout or ""):match("([%-%d]+),%s*([%-%d]+)")
                        if x ~= nil then cursorX, cursorY = tonumber(x), tonumber(y) end
                        hyprBusy = false
                        local nextVisible, nextLayer = computeVisibility()
                        visible, layer = nextVisible, nextLayer
                        publishPanel()
                        writeState()
                    end)
                else
                    hyprBusy = false
                    local nextVisible, nextLayer = computeVisibility()
                    visible, layer = nextVisible, nextLayer
                    publishPanel()
                    writeState()
                end
            end)
        end)
    end)
end

local function clearMedia()
    if not song.hasSong and currentSongKey == "" then return end
    song = {
        hasSong = false, title = "", artist = "", album = "", artUrl = "",
        identity = "", busName = "", url = "", playing = false,
        positionMs = 0, lengthMs = 0, rate = 1, status = "Stopped",
    }
    currentSongKey = ""
    trackUrl = ""
    trackUrlKey = ""
    invalidateLyrics()
    visible, layer = computeVisibility()
end

local function refreshMedia()
    if not S.enabled then
        clearMedia()
        visible, layer = false, "bottom"
        return
    end

    local ok, player = pcall(function() return noctalia.mediaPlayer() end)
    if not ok or type(player) ~= "table" or trim(player.title or "") == "" then
        clearMedia()
        return
    end

    local busName = tostring(player.busName or "")
    local title = tostring(player.title or "")
    local artist = tostring(player.artists and player.artists[1] or "")
    local album = tostring(player.album or "")
    local key = busName .. "|" .. title .. "|" .. artist .. "|" .. tostring(player.lengthMs or 0)

    local changed = key ~= currentSongKey
    song.hasSong = true
    song.title = title
    song.artist = artist
    song.album = album
    song.artUrl = tostring(player.artUrl or "")
    song.identity = tostring(player.identity or busName)
    song.busName = busName
    song.playing = player.status == "Playing"
    song.status = tostring(player.status or "Stopped")
    song.positionMs = numberOr(player.positionMs, 0)
    song.lengthMs = numberOr(player.lengthMs, 0)
    song.rate = numberOr(player.rate, 1)
    song.url = trackUrlKey == key and trackUrl or ""

    if changed then
        currentSongKey = key
        invalidateLyrics()
        fetchTrackUrl(busName, key)
        lyricsState = "loading"
        fetchLyrics()
        log("track: " .. artist .. " — " .. title)
    end

    local nextVisible, nextLayer = computeVisibility()
    visible, layer = nextVisible, nextLayer
end

-- ── settings writes from the panel / calibration ────────────────────────────

local function tomlValue(value)
    if type(value) == "boolean" then return tostring(value) end
    if type(value) == "number" then
        if value == math.floor(value) then return tostring(math.floor(value)) end
        return string.format("%.2f", value)
    end
    if type(value) == "table" then
        local parts = {}
        for _, item in ipairs(value) do
            parts[#parts + 1] = '"' .. tostring(item):gsub('"', '\\"') .. '"'
        end
        return "[ " .. table.concat(parts, ", ") .. " ]"
    end
    return '"' .. tostring(value or ""):gsub('"', '\\"') .. '"'
end

local function setConfig(key, value, done)
    noctalia.runAsync({ "noctalia", "msg", "config-set", CONFIG_PREFIX .. key, tomlValue(value) },
        function(result)
            if result.exitCode ~= 0 then
                log("config-set failed for " .. key .. ": " .. tostring(result.stderr))
            end
            if done ~= nil then done() end
        end)
end

local function toggleList(key, value)
    local current = strList(cfg(key, {}))
    local needle = lower(value)
    local found = false
    local nextList = {}
    for _, item in ipairs(current) do
        if lower(item) == needle then found = true else nextList[#nextList + 1] = item end
    end
    if not found and trim(value) ~= "" then nextList[#nextList + 1] = trim(value) end
    setConfig(key, nextList, function()
        readSettings()
        pollHypr()
    end)
end

local function cycleDisplayMode()
    local current = tostring(S.displayMode or "auto")
    local index = 1
    for i, mode in ipairs(DISPLAY_MODES) do
        if mode == current then index = i end
    end
    local nextMode = DISPLAY_MODES[(index % #DISPLAY_MODES) + 1]
    setConfig("display_mode", nextMode, function()
        readSettings()
        writeState()
        publishPanel()
    end)
end

local function persistAngles(values)
    local keys = { "angle_x", "angle_y", "angle_z", "scene_scale", "offset_x", "offset_y", "position_x", "position_y" }
    local fields = { "angleX", "angleY", "angleZ", "sceneScale", "offsetX", "offsetY", "positionX", "positionY" }
    local index = 0
    local function nextOne()
        index = index + 1
        if index > #keys then
            -- A manually placed block is a custom profile; otherwise the
            -- preset would immediately override the saved coordinates.
            setConfig("position_preset", "custom", function()
                readSettings()
                writeState()
            end)
            return
        end
        local value = numberOr(values[fields[index]], S[fields[index]])
        setConfig(keys[index], value, nextOne)
    end
    nextOne()
end

local function handleCommand(command)
    if type(command) ~= "table" or type(command.action) ~= "string" then return end
    local action = command.action
    if action == "calibrate" then
        calibrating = true
        userHidden = false
        visible, layer = true, "overlay"
        writeState()
        publishPanel()
    elseif action == "calibrate-save" then
        local values = type(command.values) == "table" and command.values or {}
        for _, field in ipairs({ "angleX", "angleY", "angleZ", "sceneScale", "offsetX", "offsetY", "positionX", "positionY" }) do
            if values[field] ~= nil then S[field] = numberOr(values[field], S[field]) end
        end
        calibrating = false
        persistAngles(values)
        writeState()
        publishPanel()
    elseif action == "calibrate-cancel" then
        calibrating = false
        local nextVisible, nextLayer = computeVisibility()
        visible, layer = nextVisible, nextLayer
        writeState()
        publishPanel()
    elseif action == "cycle-display-mode" then
        cycleDisplayMode()
    elseif action == "open-settings" then
        noctalia.runAsync({ "noctalia", "msg", "settings-open-plugin", PLUGIN_ID }, function(result)
            if result.exitCode ~= 0 then
                log("settings-open-plugin failed: " .. tostring(result.stderr))
            end
        end)
    elseif action == "refresh" then
        invalidateLyrics()
        refreshMedia()
        pollHypr()
        writeState()
    elseif action == "toggle" then
        userHidden = not userHidden
        local nextVisible, nextLayer = computeVisibility()
        visible, layer = nextVisible, nextLayer
        writeState()
        publishPanel()
    elseif action == "toggle-list" then
        if type(command.key) == "string" and command.value ~= nil then
            toggleList(command.key, command.value)
        end
    elseif action == "set" then
        if type(command.key) == "string" then
            setConfig(command.key, command.value, function()
                readSettings()
                local nextVisible, nextLayer = computeVisibility()
                visible, layer = nextVisible, nextLayer
                writeState()
                publishPanel()
            end)
        end
    end
end

local function readControl()
    local raw = noctalia.readFile(CONTROL_PATH)
    if raw == nil or trim(raw) == "" or trim(raw) == "{}" then return end
    noctalia.writeFile(CONTROL_PATH, "{}")
    local command = jsonDecode(raw)
    if command ~= nil then handleCommand(command) end
end

noctalia.state.watch("lyrics3d_cmd", function(command)
    handleCommand(command)
end)

noctalia.state.watch("lyrics3d_panel_req", function()
    readSettings()
    publishPanel()
end)

-- ── lifecycle ───────────────────────────────────────────────────────────────

function update()
    tick = tick + 1
    readControl()
    refreshMedia()
    if tick == 1 or tick % 2 == 0 then pollHypr() end
    writeState()
end

function onConfigChanged()
    readSettings()
    local nextVisible, nextLayer = computeVisibility()
    visible, layer = nextVisible, nextLayer
    writeState()
    publishPanel()
end

function onEnable()
    readSettings()
    refreshMedia()
    pollHypr()
    writeState()
    publishPanel()
end

-- The Quickshell companion has its own heartbeat watchdog (it exits when
-- state.json stops updating). Do not kill it from onExit: a settings change
-- restarts the Luau service, and killing the renderer there would flash the
-- layer on every calibration value.
function onExit(_signal, _reason)
    log("service stopped (" .. tostring(_reason) .. ")")
end

local dir = noctalia.pluginDir()
if dir ~= nil then
    local script = dir .. "/bin/renderer.sh"
    if noctalia.fileExists(script) then
        log("starting renderer: " .. script)
        noctalia.runAsync({ script }, function(result)
            if result.exitCode ~= 0 then
                log("renderer launcher exited: " .. tostring(result.exitCode) .. " " .. tostring(result.stderr))
            end
        end)
    else
        log("renderer script missing: " .. script)
    end
end

noctalia.writeFile(CONTROL_PATH, "{}")
refreshMedia()
pollHypr()
writeState()
publishPanel()
