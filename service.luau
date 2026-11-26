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
local POLL_MS = 250
-- Playback position is dead-reckoned from a local clock. D-Bus only supplies
-- anchors: track changes, play/pause, seeks and a slow drift sync.
local POSITION_SYNC_MS = 2000
local POSITION_DRIFT_MS = 150
local LYRIC_TIMEOUT_MS = 2500

noctalia.mkdirAll(CACHE)
noctalia.setUpdateInterval(POLL_MS)

local S = {}
local song = {
    hasSong = false, title = "", artist = "", album = "", artUrl = "",
    identity = "", busName = "", url = "", playing = false,
    positionMs = 0, lengthMs = 0, rate = 1, status = "Stopped",
    anchorMs = 0, anchorWallMs = 0, anchorStatus = "Stopped", anchorRate = 1,
    positionGraceUntil = 0,
}
local lyrics = {}
local plainText = ""
local lyricsState = "idle"
local lyricsProvider = ""
local lyricsError = ""
local currentSongKey = ""
local currentTrackKey = ""
local fetchGeneration = 0
local lyricsDeadlineMs = 0
local lyricsLatencyMs = 0
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

-- Cheap "is there anything but whitespace?" probe for payload-sized text.
-- trim() runs two gsub passes, so calling it on an HTTP body or on stored
-- lyrics burns most of the 25 ms callback budget before the real work starts.
-- find("%S") stops at the first printable byte, which is the common case.
local function hasText(value)
    if type(value) ~= "string" or value == "" then return false end
    return value:find("%S") ~= nil
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
        wallpaperAware = boolOr(cfg("wallpaper_aware", true), true),
        wallpaperOrder = tostring(cfg("wallpaper_order", "tour") or "tour"),
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
        hideOnPause = boolOr(cfg("hide_on_pause", true), true),
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
    if not hasText(raw) then return nil end
    local ok, value = pcall(function() return noctalia.json.decode(raw) end)
    if ok then return value end
    return nil
end

-- ── wallpaper-aware placement ──────────────────────────────────────────────
-- Analysed once whenever the wallpaper changes: a tool scales it to a 48x27
-- RGB grid, the calmest candidate spot wins, and the result is published in
-- state.json. Nothing runs while music plays.

local PLACEMENT_RAW = CACHE .. "/placement.rgb"
local PLACEMENT_COLS, PLACEMENT_ROWS = 48, 27
local GRID_COLS, GRID_ROWS = 24, 14

local placementPath = ""
local placementCheckedAtMs = 0
local placementBusy = false
local placementTool = ""
local placementToolResolved = false
-- { cols, rows, data } where data holds one hex nibble of busy-ness per cell.
local placementGrid = nil

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
        positionMs = song.anchorMs,
        positionAnchorMs = song.anchorMs,
        positionAnchorWallMs = song.anchorWallMs,
        positionStatus = song.anchorStatus,
        positionRate = song.anchorRate,
        hideOnPause = S.hideOnPause,
        lengthMs = song.lengthMs,
        rate = song.rate,
        lyricsState = lyricsState,
        lyricsProvider = lyricsProvider,
        lyricsError = lyricsError,
        lyricsLatencyMs = lyricsLatencyMs,
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
        wallpaperGrid = placementGrid,
        settings = S,
    }
    local raw = jsonEncode(payload)
    if raw ~= nil then noctalia.writeFile(STATE_PATH, raw) end
end

local function placementToolName()
    if placementToolResolved then
        if placementTool == "" then return nil end
        return placementTool
    end
    placementToolResolved = true
    if noctalia.commandExists("magick") then
        placementTool = "magick"
    elseif noctalia.commandExists("convert") then
        placementTool = "convert"
    elseif noctalia.commandExists("ffmpeg") then
        placementTool = "ffmpeg"
    else
        placementTool = ""
        log("wallpaper placement skipped: neither ImageMagick nor ffmpeg is installed")
    end
    if placementTool == "" then return nil end
    return placementTool
end

local function pathInSection(text, header)
    local start = text:find(header, 1, true)
    if start == nil then return "" end
    local bodyStart = start + #header
    local nextHeader = text:find("\n[", bodyStart, true)
    local body = text:sub(bodyStart, (nextHeader or #text) - 1)
    return body:match('path%s*=%s*"([^"]*)"') or ""
end

local function currentWallpaperPath()
    if focusedMonitor ~= "" and type(noctalia.wallpaperPath) == "function" then
        local ok, path = pcall(noctalia.wallpaperPath, focusedMonitor)
        if ok and type(path) == "string" and path ~= "" then return path end
    end
    local raw = noctalia.readFile(noctalia.expandPath("~/.local/state/noctalia/settings.toml"))
    if raw == nil then return "" end
    local path = ""
    if focusedMonitor ~= "" then
        path = pathInSection(raw, "[wallpaper.monitors." .. focusedMonitor .. "]")
    end
    if path == "" then path = pathInSection(raw, "[wallpaper.default]") end
    if path == "" then path = pathInSection(raw, "[wallpaper.last]") end
    if path == "" then return "" end
    return noctalia.expandPath(path)
end

local function applyPlacement(raw, path)
    local cols, rows = PLACEMENT_COLS, PLACEMENT_ROWS
    local lum = {}
    for i = 0, cols * rows - 1 do
        local b = i * 3 + 1
        lum[i] = 0.2126 * string.byte(raw, b) + 0.7152 * string.byte(raw, b + 1)
            + 0.0722 * string.byte(raw, b + 2)
    end
    local energy = {}
    for y = 0, rows - 1 do
        for x = 0, cols - 1 do
            local i = y * cols + x
            local dx = 0
            local dy = 0
            if x > 0 then dx = math.abs(lum[i] - lum[i - 1]) end
            if y > 0 then dy = math.abs(lum[i] - lum[i - cols]) end
            energy[i] = dx + dy
        end
    end
    -- Publish a coarse hex grid instead of one fixed spot: the renderer scores
    -- candidate positions with the real type-block size and roams the calm ones.
    local nibbles = {}
    for gy = 0, GRID_ROWS - 1 do
        for gx = 0, GRID_COLS - 1 do
            local top = math.floor(gy * rows / GRID_ROWS)
            local bottom = math.max(top, math.floor((gy + 1) * rows / GRID_ROWS) - 1)
            local left = math.floor(gx * cols / GRID_COLS)
            local right = math.max(left, math.floor((gx + 1) * cols / GRID_COLS) - 1)
            local peak = 0
            for y = top, bottom do
                for x = left, right do
                    local value = energy[y * cols + x]
                    if value > peak then peak = value end
                end
            end
            nibbles[#nibbles + 1] = string.format("%x", math.min(15, math.floor(peak / 8)))
        end
    end
    placementPath = path
    placementGrid = { cols = GRID_COLS, rows = GRID_ROWS, data = table.concat(nibbles) }
    log("wallpaper energy grid ready for " .. path)
    writeState()
end

local function analyzeWallpaper(path)
    local tool = placementToolName()
    if tool == nil then return end
    placementBusy = true
    local argv
    if tool == "ffmpeg" then
        argv = { "ffmpeg", "-v", "error", "-y", "-i", path, "-vf", "scale=48:27",
            "-pix_fmt", "rgb24", "-f", "rawvideo", PLACEMENT_RAW }
    else
        argv = { tool, path, "-resize", "48x27!", "-depth", "8", "rgb:" .. PLACEMENT_RAW }
    end
    noctalia.runAsync(argv, function(result)
        placementBusy = false
        local raw = nil
        if result.exitCode == 0 then raw = noctalia.readFile(PLACEMENT_RAW) end
        if raw == nil or #raw < PLACEMENT_COLS * PLACEMENT_ROWS * 3 then
            placementPath = path
            log("wallpaper analysis failed for " .. path .. " (exit " .. tostring(result.exitCode)
                .. ": " .. tostring(result.stderr) .. ")")
            return
        end
        applyPlacement(raw, path)
    end)
end

local function maybeAnalyzeWallpaper()
    if not S.wallpaperAware then return end
    local now = noctalia.nowMs()
    if placementBusy or now - placementCheckedAtMs < 4000 then return end
    placementCheckedAtMs = now
    local path = currentWallpaperPath()
    if path == "" or path == placementPath then return end
    if not noctalia.fileExists(path) then return end
    analyzeWallpaper(path)
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

local cacheIndex = nil

local function cacheIndexKey(artist, title)
    return lower(artist) .. "|" .. lower(title)
end

-- index.json maps every cached track to its file, so a song change resolves
-- the cache with one table lookup instead of guessing a path and probing the
-- filesystem. It is loaded once and kept in memory for the whole session.
local function loadCacheIndex()
    if cacheIndex ~= nil then return cacheIndex end
    cacheIndex = {}
    local parsed = jsonDecode(noctalia.readFile(CACHE .. "/index.json") or "")
    if type(parsed) == "table" then
        for key, entry in pairs(parsed) do
            if type(entry) == "table" and type(entry.file) == "string" then
                cacheIndex[key] = entry
            end
        end
    end
    return cacheIndex
end

local function saveCacheIndex()
    if cacheIndex == nil then return end
    local raw = jsonEncode(cacheIndex)
    if raw ~= nil then noctalia.writeFile(CACHE .. "/index.json", raw) end
end

local function readCache(artist, title)
    if not S.cacheEnabled then return nil end
    local index = loadCacheIndex()
    local key = cacheIndexKey(artist, title)
    local entry = index[key]
    local path = entry and entry.file or cachePath(artist, title)
    local raw = noctalia.readFile(path)
    if not hasText(raw) then return nil end
    if entry == nil then
        index[key] = { file = path, at = noctalia.nowMs() }
        saveCacheIndex()
    end
    return jsonDecode(raw)
end

local function writeCache(artist, title, synced, plain, provider, instrumental)
    if not S.cacheEnabled then return end
    local path = cachePath(artist, title)
    local raw = jsonEncode({
        title = title, artist = artist, syncedLyrics = synced or "",
        plainLyrics = plain or "", provider = provider or "LRCLIB",
        instrumental = instrumental == true, fetchedAtMs = noctalia.nowMs(),
    })
    if raw == nil then return end
    noctalia.writeFile(path, raw)
    local index = loadCacheIndex()
    index[cacheIndexKey(artist, title)] = {
        file = path, artist = artist, title = title, at = noctalia.nowMs(),
    }
    saveCacheIndex()
end

-- ── lyrics state transitions ────────────────────────────────────────────────

local function applyLyrics(synced, plain, provider, instrumental)
    lyrics = {}
    plainText = ""
    lyricsProvider = provider or "LRCLIB"
    lyricsError = ""
    if hasText(synced) then
        local ok, parsed = pcall(parseLrc, synced)
        if ok and type(parsed) == "table" and #parsed > 0 then
            lyrics = parsed
            lyricsState = "synced"
            writeCache(song.artist, song.title, synced, plain, provider, false)
            return true
        end
    end
    if hasText(plain) and S.showPlainLyrics then
        lyricsState = "plain"
        -- Displayed as a block, so leading/trailing whitespace is harmless and
        -- trimming a long plain-lyrics body is not worth a budget overrun.
        plainText = plain
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
    noctalia.runAsync({ "curl", "-sSf", "--connect-timeout", "1", "-m", "3", "-4",
        "-H", "User-Agent: " .. LRCLIB_UA, url },
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
        lyricsLatencyMs = 0
        local synced = tostring(cached.syncedLyrics or "")
        local plain = tostring(cached.plainLyrics or "")
        if synced ~= "" or (plain ~= "" and S.showPlainLyrics) or cached.instrumental == true then
            applyLyrics(synced, plain, cached.provider or "cache", cached.instrumental == true)
            if lyricsState ~= "notfound" then return end
        end
    end

    local generation = fetchGeneration
    local startedMs = noctalia.nowMs()
    lyricsState = "loading"
    lyricsError = ""
    lyrics = {}
    plainText = ""
    lyricsDeadlineMs = noctalia.nowMs() + LYRIC_TIMEOUT_MS

    -- /api/get and /api/search start together: the first usable answer wins,
    -- so a 404 on the exact endpoint no longer costs a second round trip
    -- before the search begins. Both are bounded by LYRIC_TIMEOUT_MS.
    local pending = 2
    local settled = false
    local transportErrors = 0

    local function finishAttempt()
        pending = pending - 1
        if settled or generation ~= fetchGeneration or pending > 0 then return end
        if lyricsState ~= "loading" then return end
        lyricsState = transportErrors >= 2 and "error" or "notfound"
        if lyricsState == "error" then lyricsError = "LRCLIB bağlantı hatası" end
        lyricsDeadlineMs = 0
        writeState()
    end

    local function accept(synced, plain, provider, instrumental)
        if settled or generation ~= fetchGeneration then return false end
        if not applyLyrics(synced, plain, provider, instrumental) then return false end
        settled = true
        lyricsLatencyMs = noctalia.nowMs() - startedMs
        lyricsDeadlineMs = 0
        writeState()
        return true
    end

    local duration = 0
    if song.lengthMs > 0 then duration = math.floor(song.lengthMs / 1000 + 0.5) end
    local getUrl = "https://lrclib.net/api/get?track_name=" .. urlEncode(title)
        .. "&artist_name=" .. urlEncode(artist or "")
    if trim(album) ~= "" then getUrl = getUrl .. "&album_name=" .. urlEncode(album) end
    if duration > 0 then getUrl = getUrl .. "&duration=" .. tostring(duration) end

    local searchUrl = "https://lrclib.net/api/search?track_name=" .. urlEncode(title)
        .. "&artist_name=" .. urlEncode(artist or "")

    httpGet(searchUrl, function(response)
        if generation ~= fetchGeneration then return end
        if not response.ok then
            transportErrors = transportErrors + 1
            finishAttempt()
            return
        end
        local list = jsonDecode(response.body)
        if type(list) ~= "table" or #list == 0 then
            finishAttempt()
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
            if hasText(candidate.syncedLyrics) then score = score + 2 end
            if candidate.instrumental == true then score = score - 1 end
            if score > bestScore then best, bestScore = candidate, score end
        end
        if best ~= nil then
            accept(best.syncedLyrics or "", best.plainLyrics or "",
                "LRCLIB", best.instrumental == true)
        end
        finishAttempt()
    end)

    httpGet(getUrl, function(response)
        if generation ~= fetchGeneration then return end
        if response.ok then
            local data = jsonDecode(response.body)
            if type(data) == "table" then
                accept(data.syncedLyrics, data.plainLyrics, "LRCLIB", data.instrumental == true)
            end
        else
            transportErrors = transportErrors + 1
        end
        finishAttempt()
    end)
end

local function invalidateLyrics()
    fetchGeneration = fetchGeneration + 1
    lyricsDeadlineMs = 0
    lyricsLatencyMs = 0
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
    -- A pause is not an instant hide: the overlay keeps its surface and the
    -- renderer fades it out after 1.5 s, so short pauses never blink.
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
        anchorMs = 0, anchorWallMs = noctalia.nowMs(), anchorStatus = "Stopped", anchorRate = 1,
        positionGraceUntil = 0,
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

    local nowMs = noctalia.nowMs()
    local status = tostring(player.status or "Stopped")
    local actualMs = numberOr(player.positionMs, 0)
    local rate = numberOr(player.rate, 1)
    local expectedMs = song.anchorMs
    if song.anchorStatus == "Playing" then
        expectedMs = expectedMs + math.max(0, nowMs - song.anchorWallMs) * (song.anchorRate or 1)
    end
    local drift = math.abs(actualMs - expectedMs)
    local elapsed = nowMs - song.anchorWallMs
    local statusChanged = status ~= song.anchorStatus
    local inGrace = nowMs < (song.positionGraceUntil or 0)
    if statusChanged and status == "Playing" and not changed then
        -- MPRIS may report a stale Position right after resume. Keep the
        -- pause anchor and restart the local clock instead of jumping back.
        song.anchorWallMs = nowMs
        song.anchorStatus = status
        song.anchorRate = rate
        song.positionGraceUntil = nowMs + 800
    elseif changed or statusChanged or (not inGrace and (drift > 1200
            or (elapsed >= POSITION_SYNC_MS and drift > POSITION_DRIFT_MS))) then
        -- Track change, pause/stop, a seek, or the periodic drift sync.
        song.anchorMs = actualMs
        song.anchorWallMs = nowMs
        song.anchorStatus = status
        song.anchorRate = rate
        song.positionGraceUntil = 0
    end
    song.playing = status == "Playing"
    song.status = status
    song.positionMs = song.anchorMs
    song.lengthMs = numberOr(player.lengthMs, 0)
    song.rate = rate
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
    if lyricsState == "loading" and lyricsDeadlineMs > 0
            and noctalia.nowMs() > lyricsDeadlineMs then
        -- Give up quickly: a slow LRCLIB response must not leave the overlay
        -- stuck on "loading" after the song has already started.
        fetchGeneration = fetchGeneration + 1
        lyricsDeadlineMs = 0
        lyricsState = "error"
        lyricsError = "LRCLIB isteği zaman aşımına uğradı"
        lyrics = {}
        writeState()
    end
    refreshMedia()
    if tick == 1 or tick % 2 == 0 then pollHypr() end
    if tick % 4 == 0 then maybeAnalyzeWallpaper() end
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
maybeAnalyzeWallpaper()
writeState()
publishPanel()
