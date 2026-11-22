// components/LyricsRenderer3D.qml
// 3D lyric stage: X/Y/Z rotated scene, depth-scaled and blurred neighbours,
// accent glow on the active line, karaoke progress and a plain/card fallback.

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
    property bool previewMode: false

    property string fontFamily: ""
    property int fontSize: 38
    property int fontWeight: 600
    property real lineSpacing: 12
    property int maxLines: 9
    property real widthPercent: 0.62
    property real offsetX: 0
    property real offsetY: 0
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
    property color shadowColor: "#000000"
    property color scrimColor: "#000000"

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
    readonly property var displayLines: {
        if (root.previewMode)
            return root.demoLines
        return root.renderState === "synced" ? (root.lyrics || []) : []
    }

    readonly property int activeIndex: {
        var lines = root.displayLines
        if (!lines || lines.length === 0)
            return -1
        var position = root.effectivePosition
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
        return Math.max(0, answer)
    }

    readonly property real activeProgress: {
        var lines = root.displayLines
        var index = root.activeIndex
        if (!lines || index < 0 || index >= lines.length)
            return 0
        var start = Number(lines[index].time || 0)
        var end = index + 1 < lines.length
            ? Number(lines[index + 1].time || 0)
            : (root.songLengthMs > start ? root.songLengthMs : start + 5000)
        if (end <= start)
            return 0
        return Math.max(0, Math.min(1, (root.effectivePosition - start) / (end - start)))
    }

    readonly property bool showCard: {
        if (root.renderState === "synced")
            return root.displayLines.length === 0
        if (root.renderState === "plain")
            return String(root.plainText || "").length === 0
        return true
    }

    visible: root.renderState !== "idle"
    clip: false

    // ------------------------------------------------------------- background
    Rectangle {
        anchors.centerIn: parent
        width: Math.min(parent.width * 0.82, 1100)
        height: Math.min(parent.height * 0.62, 520)
        radius: 30
        color: root.scrimColor
        opacity: root.textScrim
        visible: root.textScrim > 0.001
    }

    // -------------------------------------------------------------- 3D stage
    Item {
        id: anchorItem
        width: Math.max(320, parent.width * root.widthPercent)
        height: Math.max(240, parent.height * 0.86)
        anchors.centerIn: parent
        anchors.horizontalCenterOffset: root.offsetX
        anchors.verticalCenterOffset: root.offsetY

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

            ListView {
                id: list
                anchors.fill: parent
                clip: true
                model: root.displayLines
                spacing: root.lineSpacing
                interactive: false
                focus: false
                boundsBehavior: Flickable.StopAtBounds
                cacheBuffer: 600
                reuseItems: true
                topMargin: Math.max(0, list.height / 2 - root.fontSize * 1.2)
                bottomMargin: Math.max(0, list.height / 2 - root.fontSize * 1.2)

                delegate: Item {
                    id: lineItem

                    required property int index
                    required property var modelData

                    readonly property int distance: Math.abs(index - root.activeIndex)
                    readonly property bool isActive: index === root.activeIndex

                    width: list.width
                    height: Math.max(root.fontSize * 1.4, lineText.implicitHeight)
                        + root.fontSize * 0.55
                    z: 100 - Math.min(60, lineItem.distance)

                    opacity: {
                        if (lineItem.isActive)
                            return 1
                        return Math.max(0.05, Math.pow(0.55, lineItem.distance))
                    }
                    scale: Math.max(0.6, Math.pow(root.depthScale, lineItem.distance))
                    transformOrigin: Item.Center

                    Behavior on opacity {
                        NumberAnimation { duration: 260; easing.type: Easing.OutCubic }
                    }
                    Behavior on scale {
                        NumberAnimation { duration: 320; easing.type: Easing.OutCubic }
                    }


                    Text {
                        id: lineText
                        width: parent.width
                        anchors.verticalCenter: parent.verticalCenter
                        text: lineItem.modelData ? String(lineItem.modelData.text || "") : ""
                        visible: false
                        layer.enabled: true

                        color: root.textColor
                        renderType: Text.NativeRendering
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.Wrap
                        maximumLineCount: 3
                        elide: Text.ElideRight

                        font.family: root.fontFamily
                        font.pixelSize: root.fontSize
                        font.weight: lineItem.isActive
                            ? root.fontWeight
                            : Math.max(300, root.fontWeight - 150)
                        font.letterSpacing: lineItem.isActive ? 0.2 : 0
                    }

                    MultiEffect {
                        anchors.fill: lineText
                        source: lineText

                        blurEnabled: true
                        blur: Math.min(1.0,
                            root.blurAmount * Math.min(1.5, lineItem.distance / 1.35))
                        blurMax: 20
                        blurMultiplier: 0.45
                        autoPaddingEnabled: true

                        shadowEnabled: lineItem.isActive && root.activeGlow > 0.01
                        shadowColor: root.accentColor
                        shadowBlur: 0.8
                        shadowOpacity: root.activeGlow
                        shadowHorizontalOffset: 0
                        shadowVerticalOffset: 0

                        colorizationColor: root.accentColor
                        colorization: lineItem.isActive ? 0.1 : 0
                        brightness: lineItem.isActive ? 0.05 : -0.08
                        saturation: lineItem.isActive ? 0.12 : -0.1
                    }

                    Rectangle {
                        visible: lineItem.isActive && root.renderState === "synced"
                        width: Math.min(420, lineText.width * 0.55) * root.activeProgress
                        height: 3
                        radius: 1.5
                        color: root.accentColor
                        opacity: 0.92
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.top: lineText.bottom
                        anchors.topMargin: 4

                        Behavior on width {
                            NumberAnimation { duration: 140; easing.type: Easing.Linear }
                        }
                    }
                }
            }

            Text {
                visible: root.renderState === "plain" && !root.showCard
                anchors.centerIn: parent
                width: scene.width * 0.92
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

            Rectangle {
                id: card
                visible: root.showCard
                anchors.centerIn: parent
                width: Math.min(scene.width * 0.88, 680)
                height: cardColumn.implicitHeight + 44
                radius: 18
                color: Qt.rgba(0.03, 0.05, 0.08, 0.52)
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.14)

                Column {
                    id: cardColumn
                    width: parent.width - 44
                    anchors.centerIn: parent
                    spacing: 6

                    Text {
                        width: parent.width
                        text: root.songTitle.length > 0 ? root.songTitle : "Noctalia Lyrics 3D"
                        color: "#f5f8ff"
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.Wrap
                        maximumLineCount: 3
                        elide: Text.ElideRight
                        renderType: Text.NativeRendering
                        font.pixelSize: Math.max(18, root.fontSize * 0.58)
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
                        font.pixelSize: Math.max(13, root.fontSize * 0.36)
                    }

                    Text {
                        width: parent.width
                        text: {
                            if (root.renderState === "loading")
                                return "Sözler aranıyor..."
                            if (root.renderState === "instrumental")
                                return "Enstrümantal parça"
                            if (root.renderState === "notfound")
                                return "Söz bulunamadı"
                            if (root.renderState === "error")
                                return "LRCLIB bağlantı hatası"
                            return ""
                        }
                        visible: text.length > 0
                        color: "#c9d5e8"
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.Wrap
                        renderType: Text.NativeRendering
                        font.pixelSize: Math.max(12, root.fontSize * 0.32)
                        opacity: 0.85
                    }
                }
            }
        }
    }

    // ------------------------------------------------------------- positioning
    NumberAnimation {
        id: scrollAnimation
        target: list
        property: "contentY"
        duration: 480
        easing.type: Easing.OutCubic
    }

    function positionActive(animate) {
        if (!list || root.activeIndex < 0)
            return
        list.currentIndex = root.activeIndex
        var item = list.itemAtIndex(root.activeIndex)
        if (!item) {
            list.positionViewAtIndex(root.activeIndex, ListView.Center)
            Qt.callLater(function () { root.positionActive(false) })
            return
        }
        var maximum = Math.max(0, list.contentHeight - list.height)
        var target = item.y + item.height / 2 - list.height / 2
        target = Math.max(0, Math.min(maximum, target))
        if (animate && Math.abs(target - list.contentY) > 0.5) {
            scrollAnimation.stop()
            scrollAnimation.to = target
            scrollAnimation.start()
        } else {
            list.contentY = target
        }
    }

    onActiveIndexChanged: root.positionActive(true)
    onDisplayLinesChanged: Qt.callLater(function () { root.positionActive(false) })
    onHeightChanged: Qt.callLater(function () { root.positionActive(false) })
    Component.onCompleted: Qt.callLater(function () { root.positionActive(false) })

    Connections {
        target: list
        function onContentHeightChanged() {
            Qt.callLater(function () { root.positionActive(false) })
        }
    }
}
