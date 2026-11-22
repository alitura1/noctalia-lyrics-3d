// Settings.qml
// Noctalia plugin settings UI. The dialog calls saveSettings() when the user
// confirms; list toggles (players, domains, windows) are applied immediately
// because the task requires one-click source control.

import QtQuick
import QtQuick.Layouts

ColumnLayout {
    id: root

    property var pluginApi: null
    property var mainRef: pluginApi ? pluginApi.mainInstance : null

    readonly property var defaults: pluginApi && pluginApi.manifest
        && pluginApi.manifest.metadata
        ? pluginApi.manifest.metadata.defaultSettings : ({})
    readonly property var builtinDomains: [
        "youtube.com", "music.youtube.com", "soundcloud.com", "open.spotify.com"
    ]

    readonly property color fg: "#eef3fb"
    readonly property color sub: "#9caac2"
    readonly property color accent: "#8ab4f8"
    readonly property color line: Qt.rgba(1, 1, 1, 0.09)
    readonly property color field: Qt.rgba(1, 1, 1, 0.06)

    Layout.fillWidth: true
    spacing: 0

    // ---------------------------------------------------------------- local state
    property bool editEnabled: true
    property string editFontFamily: ""
    property real editFontSize: 38
    property real editFontWeight: 600
    property real editLineSpacing: 12
    property real editMaxLines: 9
    property real editWidthPercent: 0.62
    property real editOffsetX: 0
    property real editOffsetY: 0
    property real editAngleX: 0
    property real editAngleY: 0
    property real editAngleZ: 0
    property real editScale: 1.0
    property real editDepthScale: 0.92
    property real editBlur: 0.45
    property real editGlow: 0.55
    property bool editParallax: false
    property real editParallaxStrength: 1.2
    property real editSyncOffset: 0
    property string editFilterMode: "allowAll"
    property var editDisabledDomains: []
    property var editCustomDomains: []
    property var editDisabledPlayers: []
    property var editAllowedWindows: []
    property string editVisibilityMode: "desktop"
    property bool editHideOnFullscreen: true
    property bool editHideWhenPaused: false
    property string editMonitorScope: "focused"
    property string editThemeMode: "auto"
    property real editAccentBlend: 0.65
    property string editCustomTextColor: "#f6f8ff"
    property string editCustomAccentColor: "#8ab4f8"
    property real editTextScrim: 0.0
    property string editWallpaperPath: ""
    property bool editShowPlainLyrics: true
    property bool editCacheEnabled: true
    property bool editSavePerspective: true

    property string statusText: ""
    property string domainError: ""

    Component.onCompleted: root.initFromSettings()
    onMainRefChanged: root.initFromSettings()

    Timer {
        id: statusTimer
        interval: 2400
        repeat: false
        onTriggered: root.statusText = ""
    }

    Connections {
        target: root.mainRef
        ignoreUnknownSignals: true
        function onPerspectiveApplied() {
            root.syncGeometry()
        }
    }

    // ---------------------------------------------------------------- data flow
    function copyArray(value) {
        if (!value)
            return []
        return Array.prototype.slice.call(value)
    }

    function copyWindows(value) {
        var result = []
        var list = root.copyArray(value)
        for (var i = 0; i < list.length; i++) {
            var entry = list[i]
            if (!entry)
                continue
            result.push({
                class: String(entry.class || ""),
                title: String(entry.title || ""),
                matchTitle: entry.matchTitle === true
            })
        }
        return result
    }

    function value(key, fallback) {
        var source = root.mainRef ? root.mainRef.s
            : (pluginApi && pluginApi.pluginSettings ? pluginApi.pluginSettings : null)
        if (source && source[key] !== undefined && source[key] !== null)
            return source[key]
        if (root.defaults && root.defaults[key] !== undefined)
            return root.defaults[key]
        return fallback
    }

    function initFromSettings() {
        root.editEnabled = root.value("enabled", true) !== false
        root.editFontFamily = String(root.value("fontFamily", ""))
        root.editFontSize = Number(root.value("fontSize", 38))
        root.editFontWeight = Number(root.value("fontWeight", 600))
        root.editLineSpacing = Number(root.value("lineSpacing", 12))
        root.editMaxLines = Number(root.value("maxLines", 9))
        root.editWidthPercent = Number(root.value("widthPercent", 0.62))
        root.editOffsetX = Number(root.value("offsetX", 0))
        root.editOffsetY = Number(root.value("offsetY", 0))
        root.editAngleX = Number(root.value("angleX", 0))
        root.editAngleY = Number(root.value("angleY", 0))
        root.editAngleZ = Number(root.value("angleZ", 0))
        root.editScale = Number(root.value("scale", 1.0))
        root.editDepthScale = Number(root.value("depthScale", 0.92))
        root.editBlur = Number(root.value("blurAmount", 0.45))
        root.editGlow = Number(root.value("activeGlow", 0.55))
        root.editParallax = root.value("parallax", false) === true
        root.editParallaxStrength = Number(root.value("parallaxStrength", 1.2))
        root.editSyncOffset = Number(root.value("syncOffset", 0))
        root.editFilterMode = String(root.value("filterMode", "allowAll"))
        root.editDisabledDomains = root.copyArray(root.value("disabledDomains", []))
        root.editCustomDomains = root.copyArray(root.value("customDomains", []))
        root.editDisabledPlayers = root.copyArray(root.value("disabledPlayers", []))
        root.editAllowedWindows = root.copyWindows(root.value("allowedWindows", []))
        root.editVisibilityMode = String(root.value("visibilityMode", "desktop"))
        root.editHideOnFullscreen = root.value("hideOnFullscreen", true) !== false
        root.editHideWhenPaused = root.value("hideWhenPaused", false) === true
        root.editMonitorScope = String(root.value("monitorScope", "focused"))
        root.editThemeMode = String(root.value("themeMode", "auto"))
        root.editAccentBlend = Number(root.value("accentBlend", 0.65))
        root.editCustomTextColor = String(root.value("customTextColor", "#f6f8ff"))
        root.editCustomAccentColor = String(root.value("customAccentColor", "#8ab4f8"))
        root.editTextScrim = Number(root.value("textScrim", 0))
        root.editWallpaperPath = String(root.value("wallpaperPathOverride", ""))
        root.editShowPlainLyrics = root.value("showPlainLyrics", true) !== false
        root.editCacheEnabled = root.value("cacheEnabled", true) !== false
        root.editSavePerspective = root.value("savePerspectivePerWallpaper", true) !== false
    }

    function syncGeometry() {
        if (!root.mainRef)
            return
        var state = root.mainRef.s
        root.editAngleX = Number(state.angleX || 0)
        root.editAngleY = Number(state.angleY || 0)
        root.editAngleZ = Number(state.angleZ || 0)
        root.editScale = Number(state.scale || 1.0)
        root.editOffsetX = Number(state.offsetX || 0)
        root.editOffsetY = Number(state.offsetY || 0)
    }

    function collect() {
        return {
            enabled: root.editEnabled,
            fontFamily: root.editFontFamily,
            fontSize: root.editFontSize,
            fontWeight: root.editFontWeight,
            lineSpacing: root.editLineSpacing,
            maxLines: root.editMaxLines,
            widthPercent: root.editWidthPercent,
            offsetX: root.editOffsetX,
            offsetY: root.editOffsetY,
            angleX: root.editAngleX,
            angleY: root.editAngleY,
            angleZ: root.editAngleZ,
            scale: root.editScale,
            depthScale: root.editDepthScale,
            blurAmount: root.editBlur,
            activeGlow: root.editGlow,
            parallax: root.editParallax,
            parallaxStrength: root.editParallaxStrength,
            syncOffset: root.editSyncOffset,
            filterMode: root.editFilterMode,
            disabledDomains: root.copyArray(root.editDisabledDomains),
            customDomains: root.copyArray(root.editCustomDomains),
            disabledPlayers: root.copyArray(root.editDisabledPlayers),
            allowedWindows: root.copyWindows(root.editAllowedWindows),
            visibilityMode: root.editVisibilityMode,
            hideOnFullscreen: root.editHideOnFullscreen,
            hideWhenPaused: root.editHideWhenPaused,
            monitorScope: root.editMonitorScope,
            themeMode: root.editThemeMode,
            accentBlend: root.editAccentBlend,
            customTextColor: root.editCustomTextColor,
            customAccentColor: root.editCustomAccentColor,
            textScrim: root.editTextScrim,
            wallpaperPathOverride: root.editWallpaperPath,
            showPlainLyrics: root.editShowPlainLyrics,
            cacheEnabled: root.editCacheEnabled,
            savePerspectivePerWallpaper: root.editSavePerspective
        }
    }

    // Called automatically by Noctalia's settings dialog.
    function saveSettings() {
        var values = root.collect()
        if (root.mainRef) {
            root.mainRef.applySettings(values)
        } else if (pluginApi && pluginApi.pluginSettings) {
            for (var key in values)
                pluginApi.pluginSettings[key] = values[key]
            if (pluginApi.saveSettings)
                pluginApi.saveSettings()
        }
        root.statusText = "Ayarlar uygulandı"
        statusTimer.restart()
    }

    function applyLive(key, valueToApply) {
        if (root.mainRef) {
            root.mainRef.updateSetting(key, valueToApply)
        } else if (pluginApi && pluginApi.pluginSettings) {
            pluginApi.pluginSettings[key] = valueToApply
            if (pluginApi.saveSettings)
                pluginApi.saveSettings()
        }
    }

    function startCalibration() {
        root.saveSettings()
        if (root.mainRef) {
            root.mainRef.startCalibration()
        } else {
            root.statusText = "Eklenti ana örneği henüz hazır değil"
            statusTimer.restart()
        }
    }

    function clearCache() {
        if (!root.mainRef)
            return
        root.mainRef.clearCache()
        root.statusText = "Önbellek temizlendi"
        statusTimer.restart()
    }

    // ---------------------------------------------------------------- windows
    function windowAllowed(win) {
        if (!win)
            return false
        for (var i = 0; i < root.editAllowedWindows.length; i++) {
            var entry = root.editAllowedWindows[i]
            if (entry.class === win.class) {
                if (!entry.matchTitle || entry.title === win.title)
                    return true
            }
        }
        return false
    }

    function toggleWindow(win) {
        if (!win || !win.class)
            return
        var list = root.copyWindows(root.editAllowedWindows)
        var index = -1
        for (var i = 0; i < list.length; i++) {
            if (list[i].class === win.class) {
                index = i
                break
            }
        }
        if (index >= 0)
            list.splice(index, 1)
        else
            list.push({ class: win.class, title: win.title, matchTitle: false })

        root.editAllowedWindows = list
        root.applyLive("allowedWindows", list)

        // Adding the first allowed window should immediately make the overlay
        // usable over that window, without a second trip to the mode selector.
        if (index < 0 && root.editVisibilityMode === "desktop") {
            root.editVisibilityMode = "allowlist"
            root.applyLive("visibilityMode", "allowlist")
        }
    }

    function toggleWindowTitle(index) {
        var list = root.copyWindows(root.editAllowedWindows)
        if (index < 0 || index >= list.length)
            return
        list[index].matchTitle = !list[index].matchTitle
        root.editAllowedWindows = list
        root.applyLive("allowedWindows", list)
    }

    function removeWindow(index) {
        var list = root.copyWindows(root.editAllowedWindows)
        if (index < 0 || index >= list.length)
            return
        list.splice(index, 1)
        root.editAllowedWindows = list
        root.applyLive("allowedWindows", list)
    }

    // ----------------------------------------------------------------- players
    function playerDisabled(key) {
        return root.editDisabledPlayers.indexOf(key) >= 0
    }

    function togglePlayer(key) {
        var list = root.copyArray(root.editDisabledPlayers)
        var index = list.indexOf(key)
        if (index >= 0)
            list.splice(index, 1)
        else
            list.push(key)
        root.editDisabledPlayers = list
        root.applyLive("disabledPlayers", list)
    }

    // ---------------------------------------------------------------- domains
    function domainDisabled(domain) {
        return root.editDisabledDomains.indexOf(domain) >= 0
    }

    function toggleDomain(domain) {
        var list = root.copyArray(root.editDisabledDomains)
        var index = list.indexOf(domain)
        if (index >= 0)
            list.splice(index, 1)
        else
            list.push(domain)
        root.editDisabledDomains = list
        root.applyLive("disabledDomains", list)
    }

    function normalizeDomain(value) {
        var text = String(value || "").trim().toLowerCase()
        text = text.replace(/^[a-z][a-z0-9+.-]*:\/\//, "")
        text = text.split("/")[0].split("?")[0].split("#")[0]
        text = text.replace(/:\d+$/, "")
        text = text.replace(/^\*\./, "").replace(/^www\./, "")
        if (!text)
            return ""
        if (text === "localhost")
            return text
        if (!/^[a-z0-9][a-z0-9.-]*\.[a-z0-9-]+$/.test(text))
            return ""
        return text
    }

    function addCustomDomain() {
        var normalized = root.normalizeDomain(newDomainInput.text)
        if (!normalized) {
            root.domainError = "Geçerli bir alan adı girin (örn. music.apple.com)"
            return
        }
        var list = root.copyArray(root.editCustomDomains)
        if (list.indexOf(normalized) < 0)
            list.push(normalized)
        root.editCustomDomains = list
        root.applyLive("customDomains", list)
        newDomainInput.text = ""
        root.domainError = ""
    }

    function removeCustomDomain(domain) {
        var list = root.copyArray(root.editCustomDomains)
        var index = list.indexOf(domain)
        if (index >= 0)
            list.splice(index, 1)
        root.editCustomDomains = list
        root.applyLive("customDomains", list)
    }

    // ------------------------------------------------------------------- card
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: contentColumn.implicitHeight + 40
        radius: 18
        color: "#0e1522"
        border.width: 1
        border.color: root.line

        ColumnLayout {
            id: contentColumn
            x: 20
            y: 20
            width: parent.width - 40
            spacing: 12

            // ------------------------------------------------------------ header
            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    Text {
                        text: "Noctalia Lyrics 3D"
                        color: root.fg
                        renderType: Text.NativeRendering
                        font.pixelSize: 20
                        font.weight: Font.DemiBold
                    }
                    Text {
                        text: "3D perspektif • duvar kağıdı renkleri • LRCLIB"
                        color: root.sub
                        renderType: Text.NativeRendering
                        font.pixelSize: 11
                    }
                }

                Rectangle {
                    implicitWidth: statusLabel.implicitWidth + 18
                    implicitHeight: 26
                    radius: 13
                    color: root.mainRef ? Qt.rgba(0.54, 0.82, 0.6, 0.14)
                        : Qt.rgba(1, 0.72, 0.35, 0.14)
                    border.width: 1
                    border.color: root.mainRef ? Qt.rgba(0.54, 0.82, 0.6, 0.4)
                        : Qt.rgba(1, 0.72, 0.35, 0.4)

                    Text {
                        id: statusLabel
                        anchors.centerIn: parent
                        text: root.mainRef ? "canlı" : "bekliyor"
                        color: root.mainRef ? "#9ee6b0" : "#ffc77a"
                        renderType: Text.NativeRendering
                        font.pixelSize: 10
                        font.weight: Font.DemiBold
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                ActionButton {
                    label: "Kaydet"
                    primary: true
                    onClicked: root.saveSettings()
                }
                ActionButton {
                    label: "3D kalibrasyon"
                    onClicked: root.startCalibration()
                }
                Item { Layout.fillWidth: true }
                Text {
                    text: root.statusText
                    color: root.accent
                    renderType: Text.NativeRendering
                    font.pixelSize: 11
                    visible: text.length > 0
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 34
                radius: 8
                color: Qt.rgba(1, 0.72, 0.35, 0.1)
                border.width: 1
                border.color: Qt.rgba(1, 0.72, 0.35, 0.28)
                visible: !root.mainRef

                Text {
                    anchors.fill: parent
                    anchors.margins: 8
                    verticalAlignment: Text.AlignVCenter
                    text: "Canlı oynatıcı ve pencere listeleri, eklenti ana örneği yüklenince görünür."
                    color: "#ffcf94"
                    renderType: Text.NativeRendering
                    font.pixelSize: 10
                    elide: Text.ElideRight
                }
            }

            // ---------------------------------------------------------- general
            SectionTitle { text: "GENEL" }

            ToggleRow {
                label: "Eklentiyi etkinleştir"
                description: "Kapalıyken hiçbir katman oluşturulmaz."
                checked: root.editEnabled
                onToggled: function (checked) {
                    root.editEnabled = checked
                    root.applyLive("enabled", checked)
                }
            }

            ToggleRow {
                label: "Duraklatınca gizle"
                description: "Müzik duraklatıldığında sözleri yumuşakça gizle."
                checked: root.editHideWhenPaused
                onToggled: function (checked) {
                    root.editHideWhenPaused = checked
                    root.applyLive("hideWhenPaused", checked)
                }
            }

            ToggleRow {
                label: "Tam ekranda gizle"
                description: "Tam ekran oyun ve videolarda katmanı görünmez tut."
                checked: root.editHideOnFullscreen
                onToggled: function (checked) {
                    root.editHideOnFullscreen = checked
                    root.applyLive("hideOnFullscreen", checked)
                }
            }

            ToggleRow {
                label: "Senkron söz yoksa düz sözleri göster"
                description: "LRCLIB yalnızca plainLyrics döndürdüğünde metni göster."
                checked: root.editShowPlainLyrics
                onToggled: function (checked) {
                    root.editShowPlainLyrics = checked
                    root.applyLive("showPlainLyrics", checked)
                }
            }

            ToggleRow {
                label: "LRCLIB önbelleği"
                description: "Sonuçları ~/.cache/noctalia-lyrics/ altında JSON olarak sakla."
                checked: root.editCacheEnabled
                onToggled: function (checked) {
                    root.editCacheEnabled = checked
                    root.applyLive("cacheEnabled", checked)
                }
            }

            // -------------------------------------------------------- visibility
            SectionTitle { text: "GÖRÜNÜRLÜK" }

            SegmentRow {
                label: "Katman davranışı"
                options: ["Masaüstünde", "İzinli pencereler", "Her zaman"]
                current: root.editVisibilityMode === "always"
                    ? 2 : (root.editVisibilityMode === "allowlist" ? 1 : 0)
                onSelected: function (index) {
                    root.editVisibilityMode = index === 2 ? "always"
                        : (index === 1 ? "allowlist" : "desktop")
                    root.applyLive("visibilityMode", root.editVisibilityMode)
                }
            }

            Hint {
                text: "Masaüstünde: yalnızca pencere yokken. İzinli pencereler: masaüstü + listedeki pencerelerin üzerinde. Her zaman: masaüstünde ve pencerelerin arkasında."
            }

            SegmentRow {
                label: "Monitör kapsamı"
                options: ["Odaklı monitör", "Tüm monitörler"]
                current: root.editMonitorScope === "all" ? 1 : 0
                onSelected: function (index) {
                    root.editMonitorScope = index === 1 ? "all" : "focused"
                    root.applyLive("monitorScope", root.editMonitorScope)
                }
            }

            Hint {
                text: root.mainRef && !root.mainRef.visibility.compositorAvailable
                    ? "Hyprland IPC algılanamadı. Pencere takibi ve izin listesi devre dışı; katman masaüstünde kalır."
                    : "Varsayılan katman WlrLayer.Bottom ve tam tıklama geçirgendir. İzin listesindeki bir pencere odaktayken Overlay katmanına geçer."
                warning: root.mainRef && !root.mainRef.visibility.compositorAvailable
            }

            Text {
                Layout.fillWidth: true
                text: "Açık pencereler"
                color: root.fg
                renderType: Text.NativeRendering
                font.pixelSize: 12
                font.weight: Font.DemiBold
            }

            Repeater {
                model: root.mainRef ? root.mainRef.visibility.clients : []

                delegate: RowLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: 8

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1

                        Text {
                            Layout.fillWidth: true
                            text: modelData.class.length > 0 ? modelData.class : "(sınıf yok)"
                            color: root.fg
                            renderType: Text.NativeRendering
                            font.pixelSize: 11
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }
                        Text {
                            Layout.fillWidth: true
                            text: modelData.title.length > 0 ? modelData.title : "(başlık yok)"
                            color: root.sub
                            renderType: Text.NativeRendering
                            font.pixelSize: 10
                            elide: Text.ElideRight
                        }
                    }

                    ActionButton {
                        label: root.windowAllowed(modelData) ? "Kaldır" : "+ Ekle"
                        primary: !root.windowAllowed(modelData)
                        onClicked: root.toggleWindow(modelData)
                    }
                }
            }

            Hint {
                visible: !root.mainRef || root.mainRef.visibility.clients.length === 0
                text: "Şu anda algılanan açık pencere yok. Hyprland'de bir uygulama açtığınızda liste canlı güncellenir."
            }

            Text {
                Layout.fillWidth: true
                Layout.topMargin: 4
                text: "İzin verilen pencereler"
                color: root.fg
                renderType: Text.NativeRendering
                font.pixelSize: 12
                font.weight: Font.DemiBold
            }

            Repeater {
                model: root.editAllowedWindows

                delegate: RowLayout {
                    required property var modelData
                    required property int index
                    Layout.fillWidth: true
                    spacing: 8

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1

                        Text {
                            Layout.fillWidth: true
                            text: modelData.class
                            color: root.fg
                            renderType: Text.NativeRendering
                            font.pixelSize: 11
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }
                        Text {
                            Layout.fillWidth: true
                            text: modelData.matchTitle
                                ? "yalnızca: " + (modelData.title || "(başlık yok)")
                                : "tüm pencereler: " + modelData.class
                            color: root.sub
                            renderType: Text.NativeRendering
                            font.pixelSize: 10
                            elide: Text.ElideRight
                        }
                    }

                    ActionButton {
                        label: modelData.matchTitle ? "Başlık: açık" : "Tüm pencere"
                        onClicked: root.toggleWindowTitle(index)
                    }
                    ActionButton {
                        label: "Sil"
                        onClicked: root.removeWindow(index)
                    }
                }
            }

            Hint {
                visible: root.editAllowedWindows.length === 0
                text: "Henüz izin verilen pencere yok. Yukarıdaki listeden + Ekle ile tek tıkla ekleyin."
            }

            // ------------------------------------------------------------ sources
            SectionTitle { text: "MEDYA KAYNAKLARI" }

            SegmentRow {
                label: "URL filtresi"
                options: ["Tümü (engellenenler hariç)", "Yalnızca izinliler"]
                current: root.editFilterMode === "whitelist" ? 1 : 0
                onSelected: function (index) {
                    root.editFilterMode = index === 1 ? "whitelist" : "allowAll"
                    root.applyLive("filterMode", root.editFilterMode)
                }
            }

            Text {
                Layout.fillWidth: true
                text: "Web medya alan adları"
                color: root.fg
                renderType: Text.NativeRendering
                font.pixelSize: 12
                font.weight: Font.DemiBold
            }

            Repeater {
                model: root.builtinDomains

                delegate: RowLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: 10

                    Text {
                        Layout.fillWidth: true
                        text: modelData
                        color: root.fg
                        renderType: Text.NativeRendering
                        font.pixelSize: 11
                    }
                    MiniSwitch {
                        checked: !root.domainDisabled(modelData)
                        onClicked: root.toggleDomain(modelData)
                    }
                }
            }

            Hint {
                text: "Bu liste tarayıcı oturumlarındaki xesam:url alanına uygulanır. Alttaki anahtar kapalıysa alan adı engellenir."
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 38
                    radius: 9
                    color: root.field
                    border.width: 1
                    border.color: root.domainError.length > 0 ? "#ff8a8a" : root.line

                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        text: "music.apple.com veya 192.168.1.10"
                        color: Qt.rgba(0.61, 0.67, 0.76, 0.7)
                        renderType: Text.NativeRendering
                        font.pixelSize: 12
                        visible: newDomainInput.text.length === 0
                    }

                    TextInput {
                        id: newDomainInput
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        verticalAlignment: TextInput.AlignVCenter
                        color: root.fg
                        selectionColor: root.accent
                        selectedTextColor: "#08111f"
                        font.pixelSize: 12
                        clip: true
                        selectByMouse: true
                        cursorDelegate: Rectangle {
                            width: 1
                            color: root.accent
                        }
                        onAccepted: root.addCustomDomain()
                    }
                }

                ActionButton {
                    label: "Ekle"
                    primary: true
                    onClicked: root.addCustomDomain()
                }
            }

            Text {
                Layout.fillWidth: true
                visible: root.domainError.length > 0
                text: root.domainError
                color: "#ff9a9a"
                renderType: Text.NativeRendering
                font.pixelSize: 10
                wrapMode: Text.Wrap
            }

            Repeater {
                model: root.editCustomDomains

                delegate: RowLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: 8

                    Text {
                        Layout.fillWidth: true
                        text: modelData
                        color: root.fg
                        renderType: Text.NativeRendering
                        font.pixelSize: 11
                    }
                    MiniSwitch {
                        checked: !root.domainDisabled(modelData)
                        onClicked: root.toggleDomain(modelData)
                    }
                    ActionButton {
                        label: "Sil"
                        onClicked: root.removeCustomDomain(modelData)
                    }
                }
            }

            Hint {
                visible: root.editCustomDomains.length === 0
                text: "Özel alan adı yok. Yerel sunucular, radyo siteleri veya kendi URL kalıplarınızı ekleyin."
            }

            Text {
                Layout.fillWidth: true
                Layout.topMargin: 4
                text: "Algılanan oynatıcılar"
                color: root.fg
                renderType: Text.NativeRendering
                font.pixelSize: 12
                font.weight: Font.DemiBold
            }

            Repeater {
                model: root.mainRef ? root.mainRef.mpris.availablePlayers : []

                delegate: RowLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: 8

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1

                        Text {
                            Layout.fillWidth: true
                            text: modelData.identity.length > 0
                                ? modelData.identity : modelData.dbusName
                            color: root.fg
                            renderType: Text.NativeRendering
                            font.pixelSize: 11
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }
                        Text {
                            Layout.fillWidth: true
                            text: {
                                var line = modelData.title || "(parça yok)"
                                if (modelData.artist)
                                    line += " — " + modelData.artist
                                if (modelData.reason)
                                    line += "  •  " + modelData.reason
                                return line
                            }
                            color: modelData.reason ? "#ffb27a" : root.sub
                            renderType: Text.NativeRendering
                            font.pixelSize: 10
                            elide: Text.ElideRight
                        }
                    }

                    MiniSwitch {
                        checked: !root.playerDisabled(modelData.key)
                        onClicked: root.togglePlayer(modelData.key)
                    }
                }
            }

            Hint {
                visible: !root.mainRef || root.mainRef.mpris.availablePlayers.length === 0
                text: "MPRIS oynatıcı bulunamadı. Spotify, tarayıcı sekmesi veya mpv başlatın."
            }

            // --------------------------------------------------------- typography
            SectionTitle { text: "TIPOGRAFİ VE YERLEŞİM" }

            TextRow {
                label: "Yazı tipi ailesi"
                description: "Boş bırakılırsa sistem varsayılanı kullanılır."
                placeholder: "Örn. Inter, Noto Sans"
                value: root.editFontFamily
                onEdited: function (v) { root.editFontFamily = v }
            }

            SliderRow {
                label: "Punto"
                from: 18
                to: 72
                step: 1
                decimals: 0
                suffix: " px"
                value: root.editFontSize
                onMoved: function (v) { root.editFontSize = v }
            }

            SliderRow {
                label: "Yazı ağırlığı"
                from: 300
                to: 800
                step: 100
                decimals: 0
                value: root.editFontWeight
                onMoved: function (v) { root.editFontWeight = v }
            }

            SliderRow {
                label: "Satır aralığı"
                from: 0
                to: 40
                step: 1
                decimals: 0
                suffix: " px"
                value: root.editLineSpacing
                onMoved: function (v) { root.editLineSpacing = v }
            }

            SliderRow {
                label: "Görünür satır"
                from: 3
                to: 15
                step: 1
                decimals: 0
                value: root.editMaxLines
                onMoved: function (v) { root.editMaxLines = v }
            }

            SliderRow {
                label: "Metin genişliği"
                from: 30
                to: 95
                step: 1
                decimals: 0
                suffix: " %"
                value: root.editWidthPercent * 100
                onMoved: function (v) { root.editWidthPercent = v / 100 }
            }

            SliderRow {
                label: "Senkron gecikmesi"
                from: -500
                to: 500
                step: 10
                decimals: 0
                suffix: " ms"
                value: root.editSyncOffset
                onMoved: function (v) { root.editSyncOffset = v }
            }

            // ---------------------------------------------------------------- 3d
            SectionTitle { text: "3D PERSPEKTİF" }

            SliderRow {
                label: "X ekseni"
                from: -60
                to: 60
                step: 0.5
                decimals: 1
                suffix: "°"
                value: root.editAngleX
                onMoved: function (v) { root.editAngleX = v }
            }

            SliderRow {
                label: "Y ekseni"
                from: -60
                to: 60
                step: 0.5
                decimals: 1
                suffix: "°"
                value: root.editAngleY
                onMoved: function (v) { root.editAngleY = v }
            }

            SliderRow {
                label: "Z dönüşü"
                from: -180
                to: 180
                step: 0.5
                decimals: 1
                suffix: "°"
                value: root.editAngleZ
                onMoved: function (v) { root.editAngleZ = v }
            }

            SliderRow {
                label: "Ölçek"
                from: 0.4
                to: 2.0
                step: 0.01
                decimals: 2
                suffix: "×"
                value: root.editScale
                onMoved: function (v) { root.editScale = v }
            }

            SliderRow {
                label: "X konumu"
                from: -1200
                to: 1200
                step: 1
                decimals: 0
                suffix: " px"
                value: root.editOffsetX
                onMoved: function (v) { root.editOffsetX = v }
            }

            SliderRow {
                label: "Y konumu"
                from: -800
                to: 800
                step: 1
                decimals: 0
                suffix: " px"
                value: root.editOffsetY
                onMoved: function (v) { root.editOffsetY = v }
            }

            SliderRow {
                label: "Derinlik küçülmesi"
                description: "Komşu satırların Z derinliğinde küçülme oranı."
                from: 0.70
                to: 1.0
                step: 0.01
                decimals: 2
                suffix: "×"
                value: root.editDepthScale
                onMoved: function (v) { root.editDepthScale = v }
            }

            SliderRow {
                label: "Derinlik bulanıklığı"
                from: 0
                to: 1
                step: 0.01
                decimals: 2
                value: root.editBlur
                onMoved: function (v) { root.editBlur = v }
            }

            SliderRow {
                label: "Aktif satır ışıması"
                from: 0
                to: 1
                step: 0.01
                decimals: 2
                value: root.editGlow
                onMoved: function (v) { root.editGlow = v }
            }

            ToggleRow {
                label: "Mikro paralaks"
                description: "Fare konumuna göre 1-2 derecelik yumuşak açı tepkisi."
                checked: root.editParallax
                onToggled: function (checked) {
                    root.editParallax = checked
                    root.applyLive("parallax", checked)
                }
            }

            SliderRow {
                label: "Paralaks gücü"
                visible: root.editParallax
                from: 0
                to: 3
                step: 0.1
                decimals: 1
                value: root.editParallaxStrength
                onMoved: function (v) { root.editParallaxStrength = v }
            }

            ToggleRow {
                label: "Duvar kağıdı başına perspektif"
                description: "X/Y/Z açıları, ölçek ve konum duvar kağıdı anahtarına göre saklanır."
                checked: root.editSavePerspective
                onToggled: function (checked) {
                    root.editSavePerspective = checked
                    root.applyLive("savePerspectivePerWallpaper", checked)
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                ActionButton {
                    label: "Kalibrasyonu aç"
                    primary: true
                    onClicked: root.startCalibration()
                }
                ActionButton {
                    label: "Bu duvar kağıdını sıfırla"
                    onClicked: {
                        if (root.mainRef)
                            root.mainRef.resetPerspective()
                        root.syncGeometry()
                    }
                }
                Item { Layout.fillWidth: true }
                Text {
                    text: (root.mainRef ? Object.keys(root.mainRef.perspectives).length : 0)
                        + " kayıt"
                    color: root.sub
                    renderType: Text.NativeRendering
                    font.pixelSize: 10
                }
            }

            // ------------------------------------------------------------- theme
            SectionTitle { text: "RENK MOTORU" }

            SegmentRow {
                label: "Palet kaynağı"
                options: ["Otomatik", "Duvar kağıdı", "Albüm kapağı", "Özel"]
                current: {
                    if (root.editThemeMode === "wallpaper")
                        return 1
                    if (root.editThemeMode === "album")
                        return 2
                    if (root.editThemeMode === "custom")
                        return 3
                    return 0
                }
                onSelected: function (index) {
                    var modes = ["auto", "wallpaper", "album", "custom"]
                    root.editThemeMode = modes[index]
                    root.applyLive("themeMode", root.editThemeMode)
                }
            }

            SliderRow {
                label: "Albüm / duvar kağıdı karışımı"
                visible: root.editThemeMode === "auto"
                from: 0
                to: 1
                step: 0.01
                decimals: 2
                value: root.editAccentBlend
                onMoved: function (v) { root.editAccentBlend = v }
            }

            SliderRow {
                label: "Metin arkası örtü"
                description: "Okunabilirlik için sözlerin arkasına yumuşak renk örtüsü ekler."
                from: 0
                to: 0.8
                step: 0.01
                decimals: 2
                value: root.editTextScrim
                onMoved: function (v) { root.editTextScrim = v }
            }

            TextRow {
                label: "Özel metin rengi"
                description: "Palet kaynağı 'Özel' iken kullanılır."
                placeholder: "#f6f8ff"
                value: root.editCustomTextColor
                onEdited: function (v) { root.editCustomTextColor = v }
            }

            TextRow {
                label: "Özel vurgu rengi"
                description: "Aktif satır ışıması ve ilerleme çubuğu."
                placeholder: "#8ab4f8"
                value: root.editCustomAccentColor
                onEdited: function (v) { root.editCustomAccentColor = v }
            }

            TextRow {
                label: "Duvar kağıdı yolu (isteğe bağlı)"
                description: "Boşsa Noctalia wallpaper.toml, swww/awww veya hyprpaper algılanır."
                placeholder: "/home/user/Pictures/wallpaper.jpg"
                value: root.editWallpaperPath
                onEdited: function (v) {
                    root.editWallpaperPath = v
                    root.applyLive("wallpaperPathOverride", v)
                }
            }

            // ------------------------------------------------------------ footer
            SectionTitle { text: "BAKIM" }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                ActionButton {
                    label: "Önbelleği temizle"
                    onClicked: root.clearCache()
                }
                ActionButton {
                    label: "Yeniden algıla"
                    onClicked: {
                        if (root.mainRef)
                            root.mainRef.refreshAll()
                        root.statusText = "Yeniden algılanıyor"
                        statusTimer.restart()
                    }
                }
                Item { Layout.fillWidth: true }
                Text {
                    text: "v1.0.0 · MIT"
                    color: root.sub
                    renderType: Text.NativeRendering
                    font.pixelSize: 10
                }
            }

            Hint {
                text: "Liste anahtarları anında uygulanır; tipografi ve 3D kaydırıcıları Kaydet veya kalibrasyondaki Kaydet ile yazılır. Duvar kağıdı değiştiğinde kayıtlı perspektif otomatik geri yüklenir."
            }
        }
    }

    // ------------------------------------------------------------ inline parts
    component SectionTitle: ColumnLayout {
        id: section

        property string text: ""

        Layout.fillWidth: true
        Layout.topMargin: 12
        spacing: 7

        Text {
            Layout.fillWidth: true
            text: section.text
            color: root.sub
            renderType: Text.NativeRendering
            font.pixelSize: 10
            font.weight: Font.DemiBold
            font.letterSpacing: 1.4
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            color: root.line
        }
    }

    component Hint: Text {
        id: hint

        property bool warning: false

        Layout.fillWidth: true
        color: hint.warning ? "#ffb27a" : root.sub
        renderType: Text.NativeRendering
        font.pixelSize: 10
        wrapMode: Text.Wrap
        opacity: 0.9
    }

    component ToggleRow: RowLayout {
        id: toggle

        property string label: ""
        property string description: ""
        property bool checked: false

        signal toggled(bool checked)

        Layout.fillWidth: true
        spacing: 12

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2

            Text {
                Layout.fillWidth: true
                text: toggle.label
                color: root.fg
                renderType: Text.NativeRendering
                font.pixelSize: 12
            }
            Text {
                Layout.fillWidth: true
                visible: text.length > 0
                text: toggle.description
                color: root.sub
                renderType: Text.NativeRendering
                font.pixelSize: 10
                wrapMode: Text.Wrap
                opacity: 0.9
            }
        }

        MiniSwitch {
            checked: toggle.checked
            onClicked: toggle.toggled(!toggle.checked)
        }
    }

    component SliderRow: ColumnLayout {
        id: slider

        property string label: ""
        property string description: ""
        property real from: 0
        property real to: 1
        property real step: 0
        property real value: 0
        property int decimals: 0
        property string suffix: ""

        signal moved(real value)

        Layout.fillWidth: true
        spacing: 3

        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            Text {
                text: slider.label
                color: root.fg
                renderType: Text.NativeRendering
                font.pixelSize: 11
            }
            Item { Layout.fillWidth: true }
            Text {
                text: {
                    var number = slider.decimals === 0
                        ? String(Math.round(slider.value))
                        : slider.value.toFixed(slider.decimals)
                    return number + slider.suffix
                }
                color: root.accent
                renderType: Text.NativeRendering
                font.pixelSize: 11
                font.weight: Font.DemiBold
            }
        }

        Text {
            Layout.fillWidth: true
            visible: text.length > 0
            text: slider.description
            color: root.sub
            renderType: Text.NativeRendering
            font.pixelSize: 9
            wrapMode: Text.Wrap
            opacity: 0.85
        }

        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 20

            Rectangle {
                id: sliderTrack
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width
                height: 4
                radius: 2
                color: Qt.rgba(1, 1, 1, 0.14)
            }

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: sliderTrack.width * slider.ratio
                height: 4
                radius: 2
                color: root.accent
            }

            Rectangle {
                width: 12
                height: 12
                radius: 6
                color: root.fg
                border.width: 2
                border.color: root.accent
                x: sliderTrack.width * slider.ratio - width / 2
                anchors.verticalCenter: parent.verticalCenter
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor

                function update(mouse) {
                    var ratio = Math.max(0, Math.min(1, mouse.x / sliderTrack.width))
                    var raw = slider.from + ratio * (slider.to - slider.from)
                    if (slider.step > 0)
                        raw = Math.round(raw / slider.step) * slider.step
                    slider.moved(raw)
                }

                onPressed: function (mouse) { update(mouse) }
                onPositionChanged: function (mouse) { if (pressed) update(mouse) }
            }
        }

        readonly property real ratio: {
            var span = slider.to - slider.from
            if (span <= 0)
                return 0
            return Math.max(0, Math.min(1, (slider.value - slider.from) / span))
        }
    }

    component TextRow: ColumnLayout {
        id: textRow

        property string label: ""
        property string description: ""
        property string placeholder: ""
        property string value: ""

        signal edited(string value)

        Layout.fillWidth: true
        spacing: 3

        Text {
            Layout.fillWidth: true
            text: textRow.label
            color: root.fg
            renderType: Text.NativeRendering
            font.pixelSize: 11
        }
        Text {
            Layout.fillWidth: true
            visible: text.length > 0
            text: textRow.description
            color: root.sub
            renderType: Text.NativeRendering
            font.pixelSize: 9
            wrapMode: Text.Wrap
            opacity: 0.85
        }
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 36
            radius: 9
            color: root.field
            border.width: 1
            border.color: root.line

            Text {
                anchors.left: parent.left
                anchors.leftMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                text: textRow.placeholder
                color: Qt.rgba(0.61, 0.67, 0.76, 0.65)
                renderType: Text.NativeRendering
                font.pixelSize: 11
                visible: textInputLine.text.length === 0 && textRow.placeholder.length > 0
            }

            TextInput {
                id: textInputLine
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                verticalAlignment: TextInput.AlignVCenter
                text: textRow.value
                color: root.fg
                selectionColor: root.accent
                selectedTextColor: "#08111f"
                font.pixelSize: 11
                clip: true
                selectByMouse: true
                cursorDelegate: Rectangle {
                    width: 1
                    color: root.accent
                }
                onEditingFinished: textRow.edited(text)
                onAccepted: textRow.edited(text)
            }
        }
    }

    component SegmentRow: ColumnLayout {
        id: segment

        property string label: ""
        property var options: []
        property int current: 0

        signal selected(int index)

        Layout.fillWidth: true
        spacing: 4

        Text {
            Layout.fillWidth: true
            text: segment.label
            color: root.fg
            renderType: Text.NativeRendering
            font.pixelSize: 11
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            Repeater {
                model: segment.options

                delegate: Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 30
                    radius: 8
                    color: index === segment.current
                        ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.2)
                        : root.field
                    border.width: 1
                    border.color: index === segment.current
                        ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.55)
                        : root.line

                    Text {
                        anchors.centerIn: parent
                        width: parent.width - 10
                        text: modelData
                        color: index === segment.current ? root.accent : root.sub
                        renderType: Text.NativeRendering
                        font.pixelSize: 10
                        font.weight: index === segment.current ? Font.DemiBold : Font.Normal
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: segment.selected(index)
                    }
                }
            }
        }
    }

    component ActionButton: Rectangle {
        id: button

        property string label: ""
        property bool primary: false

        signal clicked()

        implicitWidth: buttonText.implicitWidth + 24
        implicitHeight: 32
        radius: 8
        color: button.primary
            ? root.accent
            : Qt.rgba(1, 1, 1, buttonMouse.containsMouse ? 0.13 : 0.07)
        border.width: button.primary ? 0 : 1
        border.color: root.line

        Behavior on color {
            ColorAnimation { duration: 120 }
        }

        Text {
            id: buttonText
            anchors.centerIn: parent
            text: button.label
            color: button.primary ? "#08111f" : root.fg
            renderType: Text.NativeRendering
            font.pixelSize: 11
            font.weight: Font.DemiBold
        }

        MouseArea {
            id: buttonMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: button.clicked()
        }
    }

    component MiniSwitch: Rectangle {
        id: toggleSwitch

        property bool checked: false

        signal clicked()

        implicitWidth: 38
        implicitHeight: 21
        radius: 11
        color: toggleSwitch.checked
            ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.85)
            : Qt.rgba(1, 1, 1, 0.16)

        Behavior on color {
            ColorAnimation { duration: 140 }
        }

        Rectangle {
            width: 15
            height: 15
            radius: 7.5
            y: 3
            x: toggleSwitch.checked ? toggleSwitch.width - width - 3 : 3
            color: "#ffffff"

            Behavior on x {
                NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
            }
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: toggleSwitch.clicked()
        }
    }
}
