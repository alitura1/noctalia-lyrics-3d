// components/NowPlayingPill.qml
// Compact glass now-playing card with cover, title, artist, progress and a
// hover/tap quick-control strip (mode, layout calibration, plugin settings).

import QtQuick

Item {
    id: root

    property string title: ""
    property string artist: ""
    property string artUrl: ""
    property string fontFamily: ""
    property real positionMs: 0
    property real lengthMs: 0
    property color accentColor: "#8ab4f8"
    property color glowColor: "#8ab4f8"
    property color textColor: "#f6f8ff"
    property bool expanded: false

    signal modeToggleRequested()
    signal calibrateRequested()
    signal settingsRequested()

    readonly property real progress: root.lengthMs > 0
        ? Math.max(0, Math.min(1, root.positionMs / root.lengthMs)) : 0

    implicitHeight: root.expanded ? 116 : 74
    implicitWidth: Math.min(320, Math.max(214,
        Math.max(titleMetrics.advanceWidth, artistMetrics.advanceWidth) + 36 + 10 + 24))
    width: implicitWidth
    height: implicitHeight
    visible: title.length > 0

    function formatTime(ms) {
        var value = Number(ms)
        if (!isFinite(value) || value <= 0)
            return "0:00"
        var total = Math.floor(value / 1000)
        var minutes = Math.floor(total / 60)
        var seconds = total % 60
        return minutes + ":" + (seconds < 10 ? "0" : "") + seconds
    }

    TextMetrics {
        id: titleMetrics
        text: root.title
        font.family: root.fontFamily
        font.pixelSize: 14
        font.weight: Font.DemiBold
    }

    TextMetrics {
        id: artistMetrics
        text: root.artist
        font.family: root.fontFamily
        font.pixelSize: 11
        font.weight: Font.Medium
    }

    HoverHandler {
        onHoveredChanged: root.expanded = hovered
    }

    TapHandler {
        acceptedButtons: Qt.LeftButton
        onTapped: root.expanded = !root.expanded
    }

    Rectangle {
        id: glass
        anchors.fill: parent
        radius: 15
        color: Qt.rgba(0.022, 0.034, 0.055, 0.8)
        border.width: 1
        border.color: Qt.rgba(root.glowColor.r, root.glowColor.g, root.glowColor.b, 0.32)

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 1
            height: parent.height * 0.32
            radius: parent.radius
            color: Qt.rgba(1, 1, 1, 0.045)
        }

        Row {
            anchors.fill: parent
            anchors.leftMargin: 9
            anchors.rightMargin: 12
            anchors.topMargin: 9
            anchors.bottomMargin: root.expanded ? 42 : 9
            spacing: 10

            Rectangle {
                id: coverFrame
                width: 36
                height: 36
                radius: 8
                anchors.verticalCenter: parent.verticalCenter
                color: Qt.rgba(1, 1, 1, 0.08)
                border.width: 1
                border.color: Qt.rgba(root.accentColor.r, root.accentColor.g,
                    root.accentColor.b, 0.26)
                clip: true

                Image {
                    id: cover
                    anchors.fill: parent
                    source: root.artUrl
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    smooth: true
                    visible: status === Image.Ready
                }

                Text {
                    anchors.centerIn: parent
                    visible: !cover.visible
                    text: "♪"
                    color: root.accentColor
                    font.pixelSize: 17
                    font.weight: Font.DemiBold
                }
            }

            Column {
                width: parent.width - coverFrame.width - parent.spacing
                anchors.verticalCenter: parent.verticalCenter
                spacing: 1

                Text {
                    width: parent.width
                    text: root.title
                    color: root.textColor
                    elide: Text.ElideRight
                    maximumLineCount: 1
                    renderType: Text.NativeRendering
                    font.family: root.fontFamily
                    font.pixelSize: 14
                    font.weight: Font.DemiBold
                }

                Text {
                    width: parent.width
                    text: root.artist
                    color: root.accentColor
                    opacity: 0.9
                    elide: Text.ElideRight
                    maximumLineCount: 1
                    renderType: Text.NativeRendering
                    font.family: root.fontFamily
                    font.pixelSize: 11
                    font.weight: Font.Medium
                }

                Row {
                    width: parent.width
                    spacing: 6

                    Rectangle {
                        id: progressTrack
                        width: Math.max(20, parent.width - timeText.width - parent.spacing)
                        height: 3
                        radius: 1.5
                        anchors.verticalCenter: parent.verticalCenter
                        color: Qt.rgba(1, 1, 1, 0.16)

                        Rectangle {
                            width: progressTrack.width * root.progress
                            height: parent.height
                            radius: parent.radius
                            color: root.accentColor
                        }
                    }

                    Text {
                        id: timeText
                        text: root.formatTime(root.positionMs) + " / " + root.formatTime(root.lengthMs)
                        color: root.textColor
                        opacity: 0.62
                        renderType: Text.NativeRendering
                        font.family: root.fontFamily
                        font.pixelSize: 8
                    }
                }
            }
        }

        Row {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.leftMargin: 7
            anchors.rightMargin: 7
            anchors.bottomMargin: 7
            height: 28
            spacing: 4
            visible: root.expanded
            opacity: root.expanded ? 1 : 0

            Behavior on opacity {
                NumberAnimation { duration: 150; easing.type: Easing.OutQuad }
            }

            Rectangle {
                width: (parent.width - parent.spacing * 2) / 3
                height: parent.height
                radius: 8
                color: Qt.rgba(1, 1, 1, 0.09)
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.12)

                Text {
                    anchors.centerIn: parent
                    text: "Mod"
                    color: root.textColor
                    font.family: root.fontFamily
                    font.pixelSize: 10
                    font.weight: Font.Medium
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.modeToggleRequested()
                }
            }

            Rectangle {
                width: (parent.width - parent.spacing * 2) / 3
                height: parent.height
                radius: 8
                color: Qt.rgba(1, 1, 1, 0.09)
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.12)

                Text {
                    anchors.centerIn: parent
                    text: "Yerleşim"
                    color: root.textColor
                    font.family: root.fontFamily
                    font.pixelSize: 9
                    font.weight: Font.Medium
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.calibrateRequested()
                }
            }

            Rectangle {
                width: (parent.width - parent.spacing * 2) / 3
                height: parent.height
                radius: 8
                color: Qt.rgba(1, 1, 1, 0.09)
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.12)

                Text {
                    anchors.centerIn: parent
                    text: "Ayarlar"
                    color: root.textColor
                    font.family: root.fontFamily
                    font.pixelSize: 9
                    font.weight: Font.Medium
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.settingsRequested()
                }
            }
        }
    }
}
