--!nonstrict
-- controls.luau — Noctalia v5 control panel.
--
-- The service publishes lyrics3d_panel over noctalia.state. Actions go back
-- through lyrics3d_cmd; the service writes the host settings with
-- `noctalia msg config-set`, so the native Settings page and this panel stay
-- in sync.

local isOpen = false
local snapshot = nil
local nonce = 0

local function trim(value)
    return (tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function lower(value)
    return trim(value):lower()
end

local function cfg(key, fallback)
    local ok, value = pcall(function() return noctalia.getConfig(key) end)
    if ok and value ~= nil then return value end
    return fallback
end

local function settings()
    if type(snapshot) == "table" and type(snapshot.settings) == "table" then
        return snapshot.settings
    end
    return {
        enabled = cfg("enabled", true),
        visibilityMode = cfg("visibility_mode", "desktop"),
        filterMode = cfg("filter_mode", "allowAll"),
        allowedWindows = cfg("allowed_windows", {}) or {},
        disabledPlayers = cfg("disabled_players", {}) or {},
        customDomains = cfg("custom_domains", {}) or {},
        disabledDomains = cfg("disabled_domains", {}) or {},
        showPlainLyrics = cfg("show_plain_lyrics", true),
    }
end

local function send(command)
    nonce = nonce + 1
    command.nonce = nonce
    noctalia.state.set("lyrics3d_cmd", command)
end

local function stateLabel(value)
    local labels = {
        idle = "Hazır", loading = "Sözler aranıyor", synced = "Senkron sözler",
        plain = "Düz sözler", instrumental = "Enstrümantal",
        notfound = "Söz bulunamadı", error = "LRCLIB hatası",
    }
    return labels[value] or tostring(value or "Hazır")
end

local function inList(list, value)
    local needle = lower(value)
    if needle == "" then return false end
    for _, item in ipairs(list or {}) do
        if lower(item) == needle then return true end
    end
    return false
end

local function windowAllowed(win, list)
    local class, title = lower(win.class or ""), lower(win.title or "")
    for _, item in ipairs(list or {}) do
        local needle = lower(item)
        if needle ~= "" and (class:find(needle, 1, true) or title:find(needle, 1, true)) then
            return true
        end
    end
    return false
end

local function section(title, subtitle)
    local kids = {
        ui.label({ text = title, fontSize = 12, fontWeight = "bold", color = "on_surface" }),
    }
    if subtitle ~= nil and subtitle ~= "" then
        kids[#kids + 1] = ui.label({ text = subtitle, fontSize = 10, color = "on_surface_variant/0.7" })
    end
    return ui.column({ gap = 2 }, kids)
end

local function toggleRow(label, caption, checked, key, onChange)
    local textKids = {
        ui.label({ text = label, fontSize = 12, color = "on_surface" }),
    }
    if caption ~= nil and caption ~= "" then
        textKids[#textKids + 1] = ui.label({ text = caption, fontSize = 10, color = "on_surface_variant" })
    end
    return ui.row({ align = "center", gap = 10 }, {
        ui.column({ flexGrow = 1, gap = 1 }, textKids),
        ui.toggle({
            key = key,
            checked = checked == true,
            onChange = function(value)
                onChange(value == true or value == "true")
            end,
        }),
    })
end

local function button(text, variant, onClick)
    return ui.button({ text = text, variant = variant or "outline", controlSize = "sm", onClick = onClick })
end

local function buildHeader(s)
    return ui.row({ align = "center", justify = "space_between", gap = 8 }, {
        ui.column({ gap = 1, flexGrow = 1 }, {
            ui.label({ text = "Noctalia Lyrics 3D", fontSize = 16, fontWeight = "bold", color = "primary" }),
            ui.label({
                text = (s.enabled and "Etkin" or "Kapalı") .. " · "
                    .. (snapshot and snapshot.layer or "bottom") .. " katmanı",
                fontSize = 10,
                color = "on_surface_variant",
            }),
        }),
        ui.button({ glyph = "refresh", glyphSize = 14, variant = "ghost", tooltip = "Sözleri yenile", onClick = function()
            send({ action = "refresh" })
        end }),
        ui.button({ glyph = "settings", glyphSize = 14, variant = "ghost", tooltip = "Eklenti ayarları", onClick = function()
            noctalia.openSettings()
        end }),
        ui.button({ glyph = "close", glyphSize = 14, variant = "ghost", onClick = function()
            panel.close()
        end }),
    })
end

local function buildNowPlaying(s)
    if type(snapshot) ~= "table" or trim(snapshot.title or "") == "" then
        return ui.column({ gap = 4, padding = 12 }, {
            ui.label({ text = "Şu anda çalan bir medya yok", fontSize = 12, color = "on_surface_variant" }),
            ui.label({ text = "Bir tarayıcı sekmesi veya MPRIS oynatıcısı başlatın.", fontSize = 10, color = "on_surface_variant/0.7" }),
        })
    end
    local status = snapshot.playing and "Çalıyor" or "Duraklatıldı"
    return ui.column({ gap = 4, padding = 12 }, {
        ui.label({ text = snapshot.title or "", fontSize = 14, fontWeight = "bold", color = "on_surface" }),
        ui.label({ text = (snapshot.artist or "Bilinmeyen sanatçı") .. " · " .. status, fontSize = 11, color = "on_surface_variant" }),
        ui.label({
            text = (snapshot.identity or "MPRIS") .. " · " .. stateLabel(snapshot.lyricsState)
                .. (snapshot.url ~= nil and snapshot.url ~= "" and (" · " .. snapshot.url) or ""),
            fontSize = 10,
            color = "primary",
        }),
        ui.row({ gap = 6, align = "center" }, {
            ui.label({ text = snapshot.visible and "Görünür" or "Gizli", fontSize = 10, color = snapshot.visible and "primary" or "on_surface_variant" }),
            ui.label({ text = "·", fontSize = 10, color = "on_surface_variant/0.5" }),
            ui.label({ text = "katman: " .. (snapshot.layer or "bottom"), fontSize = 10, color = "on_surface_variant" }),
        }),
    })
end

local function buildVisibility(s)
    local modes = { { "desktop", "Masaüstü" }, { "allowlist", "İzinli" }, { "always", "Her zaman" } }
    local modeRow = {}
    for _, mode in ipairs(modes) do
        modeRow[#modeRow + 1] = button(mode[2], s.visibilityMode == mode[1] and "primary" or "ghost", function()
            send({ action = "set", key = "visibility_mode", value = mode[1] })
        end)
    end
    return ui.column({ gap = 8 }, {
        section("Görünürlük", "Masaüstünde alt katman; izinli pencere veya her zaman üst katman."),
        toggleRow("Sözleri etkinleştir", "Ana anahtar; kapatınca servis ve katman susar.",
            s.enabled == true, "lyrics-enabled", function(value)
                send({ action = "set", key = "enabled", value = value })
            end),
        ui.row({ gap = 6 }, modeRow),
        toggleRow("Duraklatınca gizle", "Oynatma durduğunda sahneyi kapat.", s.hideWhenPaused == true, "hide-paused", function(value)
            send({ action = "set", key = "hide_when_paused", value = value })
        end),
        toggleRow("Tam ekranda gizle", "Tam ekran pencere varken sahneyi kapat.", s.hideOnFullscreen ~= false, "hide-full", function(value)
            send({ action = "set", key = "hide_on_fullscreen", value = value })
        end),
    })
end

local function buildPlayers(s)
    local rows = {}
    local disabled = s.disabledPlayers or {}
    local seen = {}
    local list = {}
    if type(snapshot) == "table" and type(snapshot.players) == "table" then
        for _, value in ipairs(snapshot.players) do list[#list + 1] = value end
    end
    if #list == 0 and type(snapshot) == "table" and trim(snapshot.identity or "") ~= "" then
        list[#list + 1] = snapshot.identity
    end
    for _, name in ipairs(list) do
        if not seen[name] then
            seen[name] = true
            local blocked = inList(disabled, name)
            rows[#rows + 1] = toggleRow(name, blocked and "Kaynak devre dışı" or "Kaynak etkin",
                not blocked, "player-" .. name, function(value)
                    send({ action = "toggle-list", key = "disabled_players", value = name })
                end)
        end
    end
    if #rows == 0 then
        rows[#rows + 1] = ui.label({ text = "MPRIS oynatıcısı bulunamadı.", fontSize = 10, color = "on_surface_variant" })
    end
    return ui.column({ gap = 6 }, {
        section("Kaynaklar", "Bir oynatıcıyı kapatmak sözleri yalnızca o kaynakta gizler."),
        ui.column({ gap = 4 }, rows),
    })
end

local function buildWindows(s)
    local rows = {}
    local switchable = {}
    if type(snapshot) == "table" and type(snapshot.windows) == "table" then
        for _, win in ipairs(snapshot.windows) do
            if trim(win.class or "") ~= "" then switchable[#switchable + 1] = win end
            if #switchable >= 8 then break end
        end
    end
    for _, win in ipairs(switchable) do
        local allowed = windowAllowed(win, s.allowedWindows or {})
        rows[#rows + 1] = toggleRow(
            win.class or "Pencere",
            trim(win.title or ""),
            allowed,
            "win-" .. (win.address or win.class),
            function(value)
                send({ action = "toggle-list", key = "allowed_windows", value = win.class })
            end)
    end
    if #rows == 0 then
        rows[#rows + 1] = ui.label({ text = "Açık pencere bulunamadı.", fontSize = 10, color = "on_surface_variant" })
    end
    return ui.column({ gap = 6 }, {
        section("Açık pencereler", "Tek tıkla izin listesine ekle; izinliyken katman üste çıkar."),
        ui.column({ gap = 4 }, rows),
    })
end

local function buildDomains(s)
    local custom = s.customDomains or {}
    local blocked = s.disabledDomains or {}
    local chips = {}
    for _, domain in ipairs(custom) do
        chips[#chips + 1] = button(domain, "ghost", function()
            send({ action = "toggle-list", key = "custom_domains", value = domain })
        end)
    end
    for _, domain in ipairs(blocked) do
        chips[#chips + 1] = button("⊘ " .. domain, "destructive", function()
            send({ action = "toggle-list", key = "disabled_domains", value = domain })
        end)
    end
    if #chips == 0 then
        chips[#chips + 1] = ui.label({
            text = "Alan adı listeleri boş. Kalıcı eklemek için Ayarlar → Eklentiler → Noctalia Lyrics 3D kullanın.",
            fontSize = 10,
            color = "on_surface_variant",
        })
    end
    return ui.column({ gap = 6 }, {
        section("Alan adları", "Kaynak filtresi: " .. (s.filterMode == "whitelist" and "izin listesi" or "tüm kaynaklar")),
        ui.column({ gap = 4 }, chips),
        ui.row({ gap = 6 }, {
            button("Tüm kaynaklar", s.filterMode ~= "whitelist" and "primary" or "ghost", function()
                send({ action = "set", key = "filter_mode", value = "allowAll" })
            end),
            button("İzin listesi", s.filterMode == "whitelist" and "primary" or "ghost", function()
                send({ action = "set", key = "filter_mode", value = "whitelist" })
            end),
        }),
    })
end

local function render()
    if not isOpen then return end
    local s = settings()
    local body = {
        buildNowPlaying(s),
        buildVisibility(s),
        buildPlayers(s),
        buildWindows(s),
        buildDomains(s),
        ui.row({ gap = 6, paddingV = 8 }, {
            button("3D Kalibrasyon", "primary", function()
                send({ action = "calibrate" })
                panel.close()
            end),
            button("Sözleri yenile", "outline", function()
                send({ action = "refresh" })
            end),
            button("Ayarlar", "ghost", function()
                noctalia.openSettings()
            end),
        }),
    }
    panel.render(ui.column({ gap = 10, padding = 16, flexGrow = 1 }, {
        buildHeader(s),
        ui.scroll({ flexGrow = 1, gap = 10 }, body),
    }))
end

function onOpen(_context)
    isOpen = true
    noctalia.state.set("lyrics3d_panel_req", { nonce = os.time() })
    render()
end

function onClose()
    isOpen = false
end

function onCloseClicked()
    panel.close()
end

function onConfigChanged()
    render()
end

noctalia.state.watch("lyrics3d_panel", function(value)
    if type(value) == "table" then
        snapshot = value
        render()
    end
end)

noctalia.state.watch("lyrics3d_state", function(value)
    if type(value) == "table" then
        snapshot = value
        render()
    end
end)
