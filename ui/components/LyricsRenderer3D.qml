// components/LyricsRenderer3D.qml
// Cinematic 3D lyric stage: one active line, optional next line, word-by-word
// reveal, intro/silence gating, manual position and a now-playing pill.

import QtQuick
import QtQuick.Effects

Item {
    id: root

    // ---------------------------------------------------------------- input
    property var lyrics: []
    property string lyricState: "idle"          // idle | loading | synced | plain | instrumental | notfound | error
    property real positionMs: 0
    property real syncOffset: 0
    property real songLengthMs: 0
    property string plainText: ""
    property string songTitle: ""
    property string songArtist: ""
    property string artUrl: ""
    property bool previewMode: false

    signal modeToggleRequested()
    signal calibrateRequested()
    signal settingsRequested()

    property string fontFamily: ""
    property int fontSize: 38
    property int fontWeight: 600
    property real lineSpacing: 12
    property int maxLines: 9
    property real widthPercent: 0.62
    property real typographyMaxWidth: 480
    property string typographyStyle: "modern"
    property string nowPlayingPosition: "topCenter"
    property real offsetX: 0
    property real offsetY: 0
    property real positionX: 50
    property real positionY: 78
    property bool showNowPlaying: true
    property bool showNextLine: false
    property bool dynamicPlacement: true
    // Wallpaper-aware placement: the service publishes a coarse energy grid of
    // the wallpaper, so the block can roam every calm area while skipping the
    // busy subject in the middle.
    property bool wallpaperAware: false
    property var wallpaperGrid: null
    // "tour" walks the calm spots in order, "shuffle" hops between them.
    property string wallpaperOrder: "tour"
    property int centerSafeZone: 32
    property string displayMode: "auto"
    property int placementCycle: -1
    property string dynamicRegion: "bottomCenter"
    property real angleX: 0
    property real angleY: 0
    property real angleZ: 0
    property real sceneScale: 1.0
    property real depthScale: 0.92
    property real blurAmount: 0.45
    property real activeGlow: 0.55
    property real textScrim: 0.0

    property color textColor: "#f6f8ff"
    property color accentColor: "#8ab4f8"
    property color activeWordColor: "#fff7e6"
    property color activeGlowColor: "#8ab4f8"
    property color shadowColor: "#000000"
    property color scrimColor: "#000000"
    property color mutedColor: "#b9c5da"

    readonly property real resolvedMaxWidth: Math.max(420, Math.min(520,
        Number(root.typographyMaxWidth) || 480))

    function wordLength(text) {
        return String(text || "").replace(/[.,!?;:"'()\[\]…—–-]/g, "").length
    }

    function wordScaleFor(text) {
        var word = String(text || "").toLowerCase()
        var length = root.wordLength(text)
        var joiners = ["ve", "için", "de", "da", "the", "in", "a", "an",
            "of", "to", "and", "bir", "bu", "şu", "o", "ile", "mi", "mı", "ki"]
        if (joiners.indexOf(word) >= 0 || length <= 3)
            return 0.72
        if (length >= 10)
            return 1.45
        if (length >= 7)
            return 1.28
        if (length >= 5)
            return 1.12
        return 0.95
    }

    function wordPixelSize(text) {
        return Math.max(12, root.fontSize * root.wordScaleFor(text))
    }

    function wordFamily() {
        if (root.fontFamily)
            return root.fontFamily
        if (root.typographyStyle === "pixel")
            return "monospace"
        if (root.typographyStyle === "script")
            return "cursive"
        return ""
    }

    function wordWeight(text) {
        if (root.typographyStyle === "script")
            return 600
        if (root.typographyStyle === "pixel")
            return 700
        var length = root.wordLength(text)
        if (length <= 3)
            return Math.max(400, root.fontWeight - 100)
        if (length >= 7)
            return Math.min(900, root.fontWeight + 200)
        return root.fontWeight
    }

    function wordSpacing() {
        if (root.typographyStyle === "pixel")
            return 0.9
        if (root.typographyStyle === "script")
            return 0.15
        return Math.max(-0.6, -0.25 + root.fontSize / 220)
    }

    // ------------------------------------------------------- placement modes
    readonly property int safeZone: Math.max(0, Math.min(60, root.centerSafeZone))
    readonly property real safeHalfPercent: root.safeZone / 2
    readonly property var dynamicRegions: ["topLeft", "topRight", "bottomLeft",
        "bottomRight", "topCenter", "bottomCenter"]
    readonly property real blockHalfWidthPercent: Math.min(22,
        root.resolvedMaxWidth / Math.max(1, root.width) * 50 + 2)
    readonly property real blockHalfHeightPercent: Math.min(22,
        Math.max(80, root.activeBlockHeight) / Math.max(1, root.height) * 50 + 2)

    function regionX(region) {
        var offset = root.safeHalfPercent + root.blockHalfWidthPercent
        if (region === "topLeft" || region === "bottomLeft")
            return Math.max(6, 50 - offset)
        if (region === "topRight" || region === "bottomRight")
            return Math.min(94, 50 + offset)
        return 50
    }

    function regionY(region) {
        var offset = root.safeHalfPercent + root.blockHalfHeightPercent
        if (region === "topLeft" || region === "topRight" || region === "topCenter")
            return Math.max(8, 50 - offset)
        if (region === "bottomLeft" || region === "bottomRight" || region === "bottomCenter")
            return Math.min(92, 50 + offset)
        return 50
    }

    function chooseDynamicRegion() {
        if (root.wallpaperPlaced) {
            root.chooseWallpaperSpot()
            return
        }
        var regions = root.dynamicRegions
        var next = (root.placementCycle + 1) % regions.length
        root.placementCycle = next
        root.dynamicRegion = regions[next]
    }

    // ---------------------------------------------- wallpaper energy grid
    property real spotX: 50
    property real spotY: 78

    readonly property int gridCols: Number(root.wallpaperGrid ? root.wallpaperGrid.cols : 0)
    readonly property int gridRows: Number(root.wallpaperGrid ? root.wallpaperGrid.rows : 0)
    readonly property string gridData: String(root.wallpaperGrid
        ? (root.wallpaperGrid.data || "") : "")
    readonly property bool wallpaperPlaced: root.wallpaperAware && root.gridCols > 0
        && root.gridRows > 0 && root.gridData.length >= root.gridCols * root.gridRows

    function cellEnergy(cx, cy) {
        if (cx < 0 || cy < 0 || cx >= root.gridCols || cy >= root.gridRows)
            return 0
        var code = root.gridData.charCodeAt(cy * root.gridCols + cx)
        if (isNaN(code))
            return 0
        return code <= 57 ? code - 48 : code - 87
    }

    // Average busy-ness under the real type block, so a narrow line may sit
    // closer to the subject than a wide one.
    // Real painted footprint of the block, so a spot never lets the type run
    // off the screen (the estimate includes the glow and the edge margin).
    function spotHalfWidth() {
        var blockWidth = Math.min(root.width * 0.96, root.resolvedMaxWidth) * root.sceneScale
        return Math.min(46, (blockWidth / 2 + 26) / Math.max(1, root.width) * 100)
    }

    function spotHalfHeight() {
        var extra = (root.outgoingVisible || root.showNextLine) ? root.fontSize * 1.7 : 0
        // Never assume less than ~1.5 lines: the next line may wrap taller than
        // the one that was on screen when the spot was picked.
        var blockHeight = Math.max(root.activeBlockHeight, root.fontSize * 2.2)
            * root.sceneScale + extra
        return Math.min(40, (blockHeight / 2 + 24) / Math.max(1, root.height) * 100)
    }

    function spotScore(xPct, yPct) {
        var hw = Math.max(4, root.spotHalfWidth())
        var hh = Math.max(4, root.spotHalfHeight())
        var left = Math.round((xPct - hw) / 100 * root.gridCols)
        var right = Math.round((xPct + hw) / 100 * root.gridCols)
        var top = Math.round((yPct - hh) / 100 * root.gridRows)
        var bottom = Math.round((yPct + hh) / 100 * root.gridRows)
        var sum = 0
        var cells = 0
        for (var cy = Math.max(0, top); cy <= Math.min(root.gridRows - 1, bottom); cy++) {
            for (var cx = Math.max(0, left); cx <= Math.min(root.gridCols - 1, right); cx++) {
                sum += root.cellEnergy(cx, cy)
                cells++
            }
        }
        return cells > 0 ? sum / cells : 0
    }

    // A tour of the calm spots, ordered by nearest neighbour so the block walks
    // through the empty area instead of hopping corner to corner.
    property var wallpaperTour: []
    property int wallpaperTourIndex: 0
    property real tourHalfWidth: -1

    function buildWallpaperTour() {
        var hw = Math.max(4, root.spotHalfWidth())
        var hh = Math.max(4, root.spotHalfHeight())
        // Keep the whole block on screen, margins included.
        var topInset = Math.max(3, 52 / Math.max(1, root.height) * 100)
        var xMin = Math.min(hw + 3, 50)
        var xMax = Math.max(97 - hw, 50)
        var yMin = Math.min(hh + topInset, 50)
        var yMax = Math.max(94 - hh, 50)
        var spots = []
        var best = Infinity
        for (var xi = 0; xi <= 6; xi++) {
            var xPct = xMin + (xMax - xMin) * xi / 6
            for (var yi = 0; yi <= 6; yi++) {
                var yPct = yMin + (yMax - yMin) * yi / 6
                var score = root.spotScore(xPct, yPct)
                spots.push({ x: Math.round(xPct), y: Math.round(yPct), score: score })
                if (score < best)
                    best = score
            }
        }
        var limit = Math.max(best * 1.6, best + 0.8)
        var allowed = spots.filter(function (spot) { return spot.score <= limit })
        if (allowed.length < 4) {
            allowed = spots.slice().sort(function (a, b) { return a.score - b.score })
                .slice(0, 4)
        }
        var tour = []
        var cursorX = root.spotX
        var cursorY = root.spotY
        var pool = allowed.slice()
        while (pool.length > 0) {
            var bestIndex = 0
            var bestDistance = Infinity
            for (var i = 0; i < pool.length; i++) {
                var distance = Math.abs(pool[i].x - cursorX)
                    + Math.abs(pool[i].y - cursorY)
                if (distance < bestDistance) {
                    bestDistance = distance
                    bestIndex = i
                }
            }
            cursorX = pool[bestIndex].x
            cursorY = pool[bestIndex].y
            tour.push(pool.splice(bestIndex, 1)[0])
        }
        root.wallpaperTour = tour
        root.wallpaperTourIndex = 0
        root.tourHalfWidth = hw
    }

    function ensureWallpaperTour() {
        if (!root.wallpaperPlaced)
            return
        if (root.wallpaperTour.length > 0
                && Math.abs(root.tourHalfWidth - root.spotHalfWidth()) < 3)
            return
        root.buildWallpaperTour()
    }

    function chooseWallpaperSpot() {
        root.ensureWallpaperTour()
        if (root.wallpaperTour.length === 0)
            return
        var spot = null
        if (root.wallpaperOrder === "shuffle") {
            var pool = root.wallpaperTour.filter(function (candidate) {
                return candidate.x !== Math.round(root.spotX)
                    || candidate.y !== Math.round(root.spotY)
            })
            if (pool.length === 0)
                pool = root.wallpaperTour
            spot = pool[Math.floor(Math.random() * pool.length)]
        } else {
            // Two or three steps per line, so the drift is visible within a
            // verse instead of crawling one cell at a time.
            var step = 2 + Math.floor(Math.random() * 2)
            root.wallpaperTourIndex = (root.wallpaperTourIndex + step) % root.wallpaperTour.length
            spot = root.wallpaperTour[root.wallpaperTourIndex]
        }
        // Clamp against the current line's real size: the type block must stay
        // fully on screen even when a line is wider than the tour was built for.
        var hw = root.spotHalfWidth()
        var hh = root.spotHalfHeight()
        // The top inset clears the shell bar, so a line never hides under it.
        var topInset = Math.max(3, 52 / Math.max(1, root.height) * 100)
        root.spotX = Math.max(hw + 2, Math.min(98 - hw, spot.x))
        root.spotY = Math.max(hh + topInset, Math.min(94 - hh, spot.y))
        console.log("[placement] spot " + root.spotX + "%/" + root.spotY + "% ("
            + root.wallpaperOrder + ", " + root.wallpaperTour.length + " calm spots)")
    }

    onWallpaperPlacedChanged: {
        if (root.wallpaperPlaced) {
            root.buildWallpaperTour()
            root.chooseWallpaperSpot()
        } else {
            root.wallpaperTour = []
            root.wallpaperTourIndex = 0
            root.tourHalfWidth = -1
        }
    }

    readonly property string activeRegion: root.wallpaperPlaced
        ? (root.spotX < 45 ? (root.spotY < 50 ? "topLeft" : "bottomLeft")
            : (root.spotX > 55 ? (root.spotY < 50 ? "topRight" : "bottomRight")
                : (root.spotY < 50 ? "topCenter" : "bottomCenter")))
        : root.dynamicRegion
    readonly property real resolvedPositionX: root.wallpaperPlaced
        ? root.spotX
        : (root.dynamicPlacement ? root.regionX(root.dynamicRegion) : root.positionX)
    readonly property real resolvedPositionY: root.wallpaperPlaced
        ? root.spotY
        : (root.dynamicPlacement ? root.regionY(root.dynamicRegion) : root.positionY)
    readonly property real regionalAngleY: {
        if (!root.wallpaperPlaced && !root.dynamicPlacement)
            return 0
        if (root.activeRegion === "topLeft" || root.activeRegion === "bottomLeft")
            return 8
        if (root.activeRegion === "topRight" || root.activeRegion === "bottomRight")
            return -8
        return 0
    }

    onDynamicPlacementChanged: {
        if (root.dynamicPlacement && root.wallpaperPlaced)
            root.chooseWallpaperSpot()
        else if (root.dynamicPlacement)
            root.chooseDynamicRegion()
    }

    // Intro / mid-song silence: a line is considered spoken for at most this
    // long (or until the next line, whichever comes first).
    readonly property int silenceGapMs: 4000
    readonly property var demoLines: [
        { time: 0, text: "Işıklar odanın içinde dağılır" },
        { time: 3800, text: "Her gölge kendi yerini bulur" },
        { time: 7600, text: "Perspektifi duvara hizala" },
        { time: 11400, text: "Sözler boşlukta yerini alır" }
    ]

    readonly property string renderState: root.previewMode ? "synced" : root.lyricState
    readonly property real effectivePosition: {
        if (root.previewMode)
            return 4700
        return Math.max(0, root.positionMs + root.syncOffset)
    }
    readonly property var displayLines: root.renderState === "synced"
        ? (root.lyrics || []) : (root.previewMode ? root.demoLines : [])

    readonly property int activeIndex: {
        var lines = root.displayLines
        if (!lines || lines.length === 0)
            return -1
        var position = root.effectivePosition
        var first = Number(lines[0].time || 0)
        if (position < first)
            return -1
        var low = 0
        var high = lines.length - 1
        var answer = -1
        while (low <= high) {
            var middle = Math.floor((low + high) / 2)
            var stamp = Number(lines[middle].time || 0)
            if (stamp <= position) {
                answer = middle
                low = middle + 1
            } else {
                high = middle - 1
            }
        }
        return answer
    }

    readonly property var currentLine: {
        var lines = root.displayLines
        var index = root.activeIndex
        return index >= 0 && index < lines.length ? lines[index] : null
    }
    readonly property var nextLine: {
        var lines = root.displayLines
        var index = root.activeIndex
        return index >= 0 && index + 1 < lines.length ? lines[index + 1] : null
    }
    readonly property real lineStart: currentLine ? Number(currentLine.time || 0) : 0
    readonly property real nextStart: nextLine
        ? Number(nextLine.time || 0)
        : (root.songLengthMs > root.lineStart ? root.songLengthMs : root.lineStart + 4000)
    readonly property real naturalLineDuration: {
        if (!root.currentLine)
            return 1200
        var text = String(root.currentLine.text || "")
        return Math.max(1200, Math.min(6000, 900 + text.length * 65))
    }
    readonly property real lineEnd: Math.min(root.nextStart, root.lineStart + root.naturalLineDuration)
    readonly property real gapToNext: Math.max(0, root.nextStart - root.lineEnd)
    readonly property real wordDuration: (root.nextLine !== null
        && root.nextStart - root.lineStart <= root.naturalLineDuration + root.silenceGapMs)
        ? Math.max(500, root.nextStart - root.lineStart)
        : Math.max(500, root.lineEnd - root.lineStart)
    readonly property bool inIntro: root.renderState === "synced" && root.effectivePosition < root.lineStart
    readonly property bool inLongGap: root.nextLine !== null && root.activeIndex >= 0
        && root.gapToNext > root.silenceGapMs && root.effectivePosition > root.lineEnd
    readonly property bool stageVisible: {
        if (root.renderState !== "synced")
            return false
        if (root.activeIndex < 0 || root.inIntro || root.inLongGap)
            return false
        return true
    }
    readonly property bool headerVisible: root.showNowPlaying
        && String(root.songTitle || "").length > 0

    readonly property var activeWords: {
        var line = root.currentLine
        if (!line)
            return []
        var words = line.words
        if (words && words.length > 0) {
            var fromTags = []
            for (var t = 0; t < words.length; t++) {
                var start = Number(words[t].time || 0)
                var end = t + 1 < words.length ? Number(words[t + 1].time || 0) : root.lineEnd
                fromTags.push({
                    text: String(words[t].text || "").trim(),
                    start: start,
                    end: Math.max(start + 80, end)
                })
            }
            return fromTags
        }

        var parts = String(line.text || "").trim().split(/\s+/)
        var cleaned = []
        var weights = []
        var total = 0
        for (var i = 0; i < parts.length; i++) {
            var part = parts[i].trim()
            if (part.length === 0)
                continue
            cleaned.push(part)
            var weight = Math.max(1, part.length)
            weights.push(weight)
            total += weight
        }
        if (cleaned.length === 0)
            return []

        var duration = root.wordDuration
        var cursor = 0
        var result = []
        for (var j = 0; j < cleaned.length; j++) {
            var span = duration * (weights[j] / total)
            var wordStart = root.lineStart + cursor
            result.push({
                text: cleaned[j],
                start: wordStart,
                end: Math.max(wordStart + 90, wordStart + span)
            })
            cursor += span
        }
        return result
    }

    readonly property var previousLine: {
        var lines = root.displayLines
        var index = root.activeIndex
        return index > 0 && index <= lines.length ? lines[index - 1] : null
    }
    readonly property string effectiveDisplayMode: {
        if (root.displayMode !== "auto")
            return root.displayMode
        var words = root.activeWords.length
        var duration = root.wordDuration
        if (words <= 8 && duration >= 1600)
            return "kinetic"
        if (words >= 12 || duration < 1500)
            return "lineByLine"
        return "singleFocus"
    }
    readonly property real activeBlockHeight: root.effectiveDisplayMode === "singleFocus"
        ? Math.max(60, singleFocusBlock.height) : Math.max(60, activeBlock.height)

    property real lineReveal: 0
    property real outgoingProgress: 0
    property bool outgoingVisible: false
    property string outgoingText: ""
    property bool showCard: root.renderState !== "synced" && root.renderState !== "plain"
        && root.renderState !== "idle"

    visible: root.renderState !== "idle" || root.previewMode
    clip: false

    onActiveIndexChanged: {
        if (root.dynamicPlacement && root.activeIndex >= 0 && root.stageVisible)
            root.chooseDynamicRegion()
        if (root.activeIndex > 0 && root.stageVisible) {
            var previous = root.displayLines[root.activeIndex - 1]
            root.outgoingText = previous ? String(previous.text || "") : ""
            root.outgoingVisible = root.outgoingText.length > 0
            root.outgoingProgress = 0
            outgoingAnimation.restart()
        } else {
            root.outgoingVisible = false
        }
        if (root.activeIndex >= 0 && root.stageVisible) {
            root.lineReveal = 0
            revealAnimation.restart()
        }
    }
    onStageVisibleChanged: {
        if (root.stageVisible) {
            root.lineReveal = 0
            revealAnimation.restart()
        }
    }
    onEffectiveDisplayModeChanged: {
        if (root.stageVisible) {
            root.lineReveal = 0
            revealAnimation.restart()
        }
    }

    NumberAnimation {
        id: revealAnimation
        target: root
        property: "lineReveal"
        from: 0
        to: 1
        duration: 360
        easing.type: Easing.OutCubic
    }

    Component.onCompleted: {
        if (root.dynamicPlacement)
            root.chooseDynamicRegion()
        if (root.stageVisible)
            revealAnimation.restart()
    }

    NumberAnimation {
        id: outgoingAnimation
        target: root
        property: "outgoingProgress"
        from: 0
        to: 1
        duration: 280
        easing.type: Easing.OutCubic
        onFinished: root.outgoingVisible = false
    }

    // ------------------------------------------------------------- background
    Rectangle {
        anchors.centerIn: parent
        width: Math.min(parent.width * 0.84, 1120)
        height: Math.min(parent.height * 0.42, 420)
        radius: 30
        color: root.scrimColor
        opacity: root.textScrim
        visible: root.textScrim > 0.001
    }

    // The now-playing card is deliberately outside the 3D lyric scene: it
    // stays pinned below the bar (or in a chosen top corner) while the type
    // block can be dragged independently.
    NowPlayingPill {
        id: nowPlaying
        x: root.nowPlayingPosition === "topLeft" ? 24
            : (root.nowPlayingPosition === "topRight"
                ? root.width - width - 24
                : (root.width - width) / 2)
        y: 74
        fontFamily: root.fontFamily
        positionMs: root.positionMs
        lengthMs: root.songLengthMs
        title: root.songTitle
        artist: root.songArtist
        artUrl: root.artUrl
        accentColor: root.accentColor
        glowColor: root.activeGlowColor
        textColor: root.textColor
        visible: root.headerVisible

        onModeToggleRequested: root.modeToggleRequested()
        onCalibrateRequested: root.calibrateRequested()
        onSettingsRequested: root.settingsRequested()
    }

    readonly property real nowPlayingX: nowPlaying.x
    readonly property real nowPlayingY: nowPlaying.y
    readonly property real nowPlayingWidth: nowPlaying.width
    readonly property real nowPlayingHeight: nowPlaying.height
    readonly property bool nowPlayingInteractive: nowPlaying.visible

    // -------------------------------------------------------------- 3D stage
    Item {
        id: anchorItem
        width: Math.max(320, parent.width * root.widthPercent)
        height: Math.max(240, parent.height * 0.58)
        x: (parent.width - width) / 2 + root.offsetX
            + (root.resolvedPositionX / 100 - 0.5) * parent.width
        y: (parent.height - height) / 2 + root.offsetY
            + (root.resolvedPositionY / 100 - 0.5) * parent.height

        Behavior on x {
            NumberAnimation { duration: 520; easing.type: Easing.OutCubic }
        }
        Behavior on y {
            NumberAnimation { duration: 520; easing.type: Easing.OutCubic }
        }

        Item {
            id: scene
            anchors.fill: parent

            transform: [
                Rotation {
                    origin.x: scene.width / 2
                    origin.y: scene.height / 2
                    axis { x: 1; y: 0; z: 0 }
                    angle: root.angleX
                },
                Rotation {
                    origin.x: scene.width / 2
                    origin.y: scene.height / 2
                    axis { x: 0; y: 1; z: 0 }
                    angle: root.angleY
                },
                Rotation {
                    origin.x: scene.width / 2
                    origin.y: scene.height / 2
                    axis { x: 0; y: 0; z: 1 }
                    angle: root.angleZ
                },
                Scale {
                    origin.x: scene.width / 2
                    origin.y: scene.height / 2
                    xScale: root.sceneScale
                    yScale: root.sceneScale
                }
            ]

            // Active line: one packed cinematic type block, word by word.
            Item {
                id: activeBlock
                width: Math.min(scene.width * 0.96, root.resolvedMaxWidth)
                height: wordFlow.height
                anchors.centerIn: parent
                visible: root.stageVisible && root.effectiveDisplayMode !== "singleFocus"
                opacity: root.lineReveal
                scale: 0.96 + 0.04 * root.lineReveal
                transform: Translate { y: (1 - root.lineReveal) * -10 }

                // One GPU layer and one MultiEffect for the active line: the
                // glow is composited once per frame, not once per word.
                layer.enabled: true
                layer.effect: MultiEffect {
                    blurEnabled: false
                    shadowEnabled: true
                    shadowColor: root.activeGlowColor
                    shadowBlur: 0.7 * root.activeGlow
                    shadowHorizontalOffset: 0
                    shadowVerticalOffset: 0
                }

                Flow {
                    id: wordFlow
                    width: parent.width
                    spacing: Math.max(2, root.fontSize * 0.12)
                    height: childrenRect.height

                    Repeater {
                        model: root.activeWords

                        delegate: Text {
                            required property var modelData
                            readonly property real wordStart: Number(modelData.start || 0)
                            readonly property real wordEnd: Number(modelData.end || 0)
                            readonly property bool spoken: root.effectivePosition >= wordStart
                            readonly property bool current: spoken && root.effectivePosition < wordEnd

                            text: modelData.text
                            color: current ? root.activeWordColor : root.textColor
                            opacity: current ? 1.0 : (spoken ? 0.86 : 0.42)
                            scale: current ? 1.12 : (spoken ? 1.0 : 0.9)
                            transformOrigin: Item.Center
                            renderType: Text.NativeRendering
                            style: Text.Outline
                            styleColor: Qt.rgba(root.shadowColor.r, root.shadowColor.g,
                                root.shadowColor.b, current ? 0.72 : 0.46)
                            font.family: root.wordFamily()
                            font.pixelSize: root.wordPixelSize(modelData.text)
                            font.weight: root.wordWeight(modelData.text)
                            font.italic: root.typographyStyle === "script"
                            font.letterSpacing: root.wordSpacing()
                            font.capitalization: root.typographyStyle === "pixel"
                                ? Font.AllUppercase : Font.MixedCase

                            // Contours come from Text.Outline above. No
                            // per-word layer or MultiEffect: one shared glow
                            // on activeBlock covers the whole line instead of
                            // a blur effect per glyph run.
                            Behavior on opacity {
                                NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
                            }
                            Behavior on scale {
                                NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
                            }
                            Behavior on color {
                                ColorAnimation { duration: 140 }
                            }
                        }
                    }
                }
            }

            // Single-focus mode: one legible, high-contrast line only.
            Text {
                id: singleFocusBlock
                anchors.centerIn: parent
                width: Math.min(scene.width * 0.9, root.resolvedMaxWidth)
                height: implicitHeight
                visible: root.stageVisible && root.effectiveDisplayMode === "singleFocus"
                opacity: root.lineReveal
                scale: 0.97 + 0.03 * root.lineReveal
                text: root.currentLine ? String(root.currentLine.text || "") : ""
                color: root.activeWordColor
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                maximumLineCount: 3
                elide: Text.ElideRight
                renderType: Text.NativeRendering
                style: Text.Outline
                styleColor: Qt.rgba(root.shadowColor.r, root.shadowColor.g,
                    root.shadowColor.b, 0.7)
                font.family: root.wordFamily()
                font.pixelSize: Math.max(18, root.fontSize * 1.18)
                font.weight: Math.min(900, root.fontWeight + 100)
                font.italic: root.typographyStyle === "script"
                font.letterSpacing: root.wordSpacing()

                layer.enabled: true
                layer.effect: MultiEffect {
                    blurEnabled: false
                    brightness: 0.12
                    shadowEnabled: true
                    shadowColor: root.activeGlowColor
                    shadowBlur: 0.8 * root.activeGlow
                    shadowHorizontalOffset: 0
                    shadowVerticalOffset: 0
                }
            }

            // Line-by-line mode keeps the previous and next lines in a
            // shallow 3D trail around the active line.
            Text {
                id: previousBlock
                anchors.horizontalCenter: parent.horizontalCenter
                y: activeBlock.y - height - root.lineSpacing - 12
                width: Math.min(scene.width * 0.9, root.resolvedMaxWidth)
                visible: root.stageVisible && root.effectiveDisplayMode === "lineByLine"
                    && root.previousLine !== null
                opacity: visible ? 0.24 : 0
                scale: 0.78
                text: root.previousLine ? String(root.previousLine.text || "") : ""
                color: root.mutedColor
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
                renderType: Text.NativeRendering
                font.family: root.fontFamily
                font.pixelSize: Math.max(12, root.fontSize * 0.58)
                font.weight: Math.max(300, root.fontWeight - 150)
            }

            // The previous line leaves with a short upward drift while the
            // new line fades in at the focal point.
            Text {
                visible: root.outgoingVisible && root.stageVisible
                    && root.effectiveDisplayMode === "kinetic"
                opacity: (1 - root.outgoingProgress) * 0.55
                width: Math.min(scene.width * 0.96, root.resolvedMaxWidth)
                anchors.horizontalCenter: parent.horizontalCenter
                y: activeBlock.y - root.outgoingProgress * 30
                text: root.outgoingText
                color: root.textColor
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
                renderType: Text.NativeRendering
                font.family: root.fontFamily
                font.pixelSize: root.fontSize
                font.weight: root.fontWeight
            }

            // Optional preview of the next line, deliberately quieter.
            Text {
                id: nextBlock
                anchors.horizontalCenter: parent.horizontalCenter
                y: activeBlock.y + activeBlock.height + root.lineSpacing + 14
                width: Math.min(scene.width * 0.9, root.resolvedMaxWidth)
                visible: root.stageVisible && root.nextLine !== null
                    && (root.effectiveDisplayMode === "lineByLine"
                        || (root.showNextLine && root.effectiveDisplayMode !== "singleFocus"))
                opacity: visible ? 0.3 : 0
                scale: 0.8
                text: root.nextLine ? String(root.nextLine.text || "") : ""
                color: root.textColor
                renderType: Text.NativeRendering
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
                font.family: root.fontFamily
                font.pixelSize: Math.max(14, root.fontSize * 0.56)
                font.weight: Math.max(300, root.fontWeight - 150)

                Behavior on opacity {
                    NumberAnimation { duration: 240; easing.type: Easing.OutQuad }
                }
            }

            // Unsynced fallback text.
            Text {
                visible: root.renderState === "plain" && String(root.plainText || "").length > 0
                anchors.centerIn: parent
                width: scene.width * 0.9
                text: root.plainText
                color: root.textColor
                opacity: 0.88
                renderType: Text.NativeRendering
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                maximumLineCount: Math.max(4, root.maxLines * 2)
                elide: Text.ElideRight
                font.family: root.fontFamily
                font.pixelSize: Math.max(14, root.fontSize * 0.74)
                font.weight: Math.max(300, root.fontWeight - 150)
            }

            // Status card for loading / notfound / instrumental / error.
            Rectangle {
                id: card
                visible: root.showCard
                anchors.centerIn: parent
                width: Math.min(scene.width * 0.82, 620)
                height: cardColumn.implicitHeight + 34
                radius: 18
                color: Qt.rgba(0.03, 0.05, 0.08, 0.52)
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.14)

                Column {
                    id: cardColumn
                    width: parent.width - 38
                    anchors.centerIn: parent
                    spacing: 6

                    Text {
                        width: parent.width
                        text: root.songTitle.length > 0 ? root.songTitle : "Noctalia Lyrics 3D"
                        color: "#f5f8ff"
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.Wrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                        renderType: Text.NativeRendering
                        font.pixelSize: Math.max(16, root.fontSize * 0.48)
                        font.weight: Font.DemiBold
                    }

                    Text {
                        width: parent.width
                        visible: text.length > 0
                        text: root.songArtist
                        color: root.accentColor
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.Wrap
                        elide: Text.ElideRight
                        renderType: Text.NativeRendering
                        font.pixelSize: Math.max(12, root.fontSize * 0.34)
                    }

                    Text {
                        width: parent.width
                        text: {
                            if (root.renderState === "loading") return "Sözler aranıyor..."
                            if (root.renderState === "instrumental") return "Enstrümantal parça"
                            if (root.renderState === "notfound") return "Söz bulunamadı"
                            if (root.renderState === "error") return "LRCLIB bağlantı hatası"
                            return ""
                        }
                        visible: text.length > 0
                        color: "#c9d5e8"
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.Wrap
                        renderType: Text.NativeRendering
                        font.pixelSize: Math.max(11, root.fontSize * 0.3)
                        opacity: 0.85
                    }
                }
            }
        }
    }
}
