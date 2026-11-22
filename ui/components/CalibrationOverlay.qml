// components/CalibrationOverlay.qml
// Temporary calibration layer: live 3D reference grid, draggable position,
// and sliders for X/Y/Z rotation and scale. Values are previewed immediately;
// the host decides when to persist them.

import QtQuick
import QtQuick.Layouts

Item {
    id: root

    property real angleX: 0
    property real angleY: 0
    property real angleZ: 0
    property real sceneScale: 1.0
    property real offsetX: 0
    property real offsetY: 0
    property real positionX: 50
    property real positionY: 78
    property string wallpaperLabel: ""
    property int savedCount: 0
    property color accentColor: "#8ab4f8"
    property color textColor: "#f6f8ff"

    signal edited(var values)
    signal saveRequested()
    signal cancelRequested()
    signal resetRequested()

    visible: false
    focus: true

    onVisibleChanged: {
        if (visible) {
            grid.requestPaint()
            root.forceActiveFocus()
        }
    }

    function clamp(value, minimum, maximum) {
        return Math.max(minimum, Math.min(maximum, value))
    }

    function nudge(dx, dy) {
        root.edited({
            positionX: root.clamp(root.positionX + dx / 4, 0, 100),
            positionY: root.clamp(root.positionY + dy / 4, 0, 100)
        })
    }

    Keys.onPressed: function (event) {
        if (event.key === Qt.Key_Escape) {
            root.cancelRequested()
            event.accepted = true
        } else if (event.key === Qt.Key_Left) {
            root.nudge(event.modifiers & Qt.ShiftModifier ? -20 : -4, 0)
            event.accepted = true
        } else if (event.key === Qt.Key_Right) {
            root.nudge(event.modifiers & Qt.ShiftModifier ? 20 : 4, 0)
            event.accepted = true
        } else if (event.key === Qt.Key_Up) {
            root.nudge(0, event.modifiers & Qt.ShiftModifier ? -20 : -4)
            event.accepted = true
        } else if (event.key === Qt.Key_Down) {
            root.nudge(0, event.modifiers & Qt.ShiftModifier ? 20 : 4)
            event.accepted = true
        }
    }

    // ---------------------------------------------------------------- scrim
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0.02, 0.03, 0.05, 0.5)
    }

    // ------------------------------------------------------------ 3D grid
    Canvas {
        id: grid
        anchors.fill: parent
        opacity: 0.95

        function project(x, y, z) {
            var rx = root.angleX * Math.PI / 180
            var ry = root.angleY * Math.PI / 180
            var rz = root.angleZ * Math.PI / 180

            var y1 = y * Math.cos(rx) - z * Math.sin(rx)
            var z1 = y * Math.sin(rx) + z * Math.cos(rx)

            var x2 = x * Math.cos(ry) + z1 * Math.sin(ry)
            var z2 = -x * Math.sin(ry) + z1 * Math.cos(ry)

            var x3 = x2 * Math.cos(rz) - y1 * Math.sin(rz)
            var y3 = x2 * Math.sin(rz) + y1 * Math.cos(rz)

            var distance = 1500
            var focal = distance / (distance + z2 + 900)
            return {
                x: grid.width * root.positionX / 100 + x3 * focal * root.sceneScale,
                y: grid.height * root.positionY / 100 + y3 * focal * root.sceneScale
            }
        }

        function strokeLine(from, to, color, width) {
            var context = grid.getContext("2d")
            context.beginPath()
            context.moveTo(from.x, from.y)
            context.lineTo(to.x, to.y)
            context.strokeStyle = color
            context.lineWidth = width
            context.stroke()
        }

        onPaint: {
            var context = grid.getContext("2d")
            context.clearRect(0, 0, grid.width, grid.height)
            context.lineCap = "round"

            var faint = Qt.rgba(root.accentColor.r, root.accentColor.g,
                root.accentColor.b, 0.16)
            var strong = Qt.rgba(root.accentColor.r, root.accentColor.g,
                root.accentColor.b, 0.55)
            var labelColor = Qt.rgba(root.textColor.r, root.textColor.g,
                root.textColor.b, 0.72)

            // Floor plane behind the lyrics.
            for (var z = 0; z <= 1600; z += 200) {
                grid.strokeLine(
                    grid.project(-1400, 260, z),
                    grid.project(1400, 260, z),
                    faint, 1)
            }
            for (var x = -1400; x <= 1400; x += 200) {
                grid.strokeLine(
                    grid.project(x, 260, 0),
                    grid.project(x, 260, 1600),
                    faint, 1)
            }

            // Lyric text plane.
            var topLeft = grid.project(-700, -190, 0)
            var topRight = grid.project(700, -190, 0)
            var bottomRight = grid.project(700, 190, 0)
            var bottomLeft = grid.project(-700, 190, 0)
            context.beginPath()
            context.moveTo(topLeft.x, topLeft.y)
            context.lineTo(topRight.x, topRight.y)
            context.lineTo(bottomRight.x, bottomRight.y)
            context.lineTo(bottomLeft.x, bottomLeft.y)
            context.closePath()
            context.fillStyle = Qt.rgba(root.accentColor.r, root.accentColor.g,
                root.accentColor.b, 0.055)
            context.fill()
            context.strokeStyle = strong
            context.lineWidth = 1.5
            context.stroke()

            // Axes.
            var origin = grid.project(0, 0, 0)
            grid.strokeLine(origin, grid.project(760, 0, 0), "rgba(255, 105, 115, 0.9)", 2)
            grid.strokeLine(origin, grid.project(0, 430, 0), "rgba(105, 230, 160, 0.9)", 2)
            grid.strokeLine(origin, grid.project(0, 0, 760), "rgba(100, 170, 255, 0.9)", 2)

            context.font = "600 12px sans-serif"
            context.fillStyle = labelColor
            var xTip = grid.project(800, 0, 0)
            var yTip = grid.project(0, 470, 0)
            var zTip = grid.project(0, 0, 800)
            context.fillText("X", xTip.x + 6, xTip.y + 4)
            context.fillText("Y", yTip.x + 6, yTip.y + 4)
            context.fillText("Z", zTip.x + 6, zTip.y + 4)

            // Crosshair at the text origin.
            context.beginPath()
            context.arc(origin.x, origin.y, 4, 0, Math.PI * 2)
            context.fillStyle = strong
            context.fill()
        }
    }

    Connections {
        target: root
        function onAngleXChanged() { grid.requestPaint() }
        function onAngleYChanged() { grid.requestPaint() }
        function onAngleZChanged() { grid.requestPaint() }
        function onScaleChanged() { grid.requestPaint() }
        function onOffsetXChanged() { grid.requestPaint() }
        function onOffsetYChanged() { grid.requestPaint() }
        function onPositionXChanged() { grid.requestPaint() }
        function onPositionYChanged() { grid.requestPaint() }
        function onWidthChanged() { grid.requestPaint() }
        function onHeightChanged() { grid.requestPaint() }
    }

    // -------------------------------------------------------------- drag area
    MouseArea {
        anchors.fill: parent
        anchors.rightMargin: Math.min(380, root.width * 0.32) + 32
        hoverEnabled: true
        cursorShape: Qt.SizeAllCursor

        property point lastPoint

        onPressed: function (mouse) {
            lastPoint = Qt.point(mouse.x, mouse.y)
            root.forceActiveFocus()
        }

        onPositionChanged: function (mouse) {
            if (!pressed)
                return
            var dx = mouse.x - lastPoint.x
            var dy = mouse.y - lastPoint.y
            lastPoint = Qt.point(mouse.x, mouse.y)
            root.edited({
                positionX: root.clamp(root.positionX + dx / Math.max(1, grid.width) * 100, 0, 100),
                positionY: root.clamp(root.positionY + dy / Math.max(1, grid.height) * 100, 0, 100)
            })
        }
    }

    // ---------------------------------------------------------------- banner
    Rectangle {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.margins: 24
        height: 48
        width: bannerRow.implicitWidth + 32
        radius: 14
        color: Qt.rgba(0.03, 0.05, 0.08, 0.82)
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.12)

        Row {
            id: bannerRow
            anchors.centerIn: parent
            spacing: 12

            Rectangle {
                width: 8
                height: 8
                radius: 4
                color: root.accentColor
                anchors.verticalCenter: parent.verticalCenter
            }
            Text {
                text: "3D KALİBRASYON"
                color: root.textColor
                renderType: Text.NativeRendering
                font.pixelSize: 13
                font.weight: Font.DemiBold
                font.letterSpacing: 1.2
                anchors.verticalCenter: parent.verticalCenter
            }
            Text {
                text: "sürükle: taşı  •  oklar: ince ayar  •  Esc: vazgeç"
                color: Qt.rgba(root.textColor.r, root.textColor.g, root.textColor.b, 0.62)
                renderType: Text.NativeRendering
                font.pixelSize: 11
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    // ----------------------------------------------------------- control panel
    Rectangle {
        id: panel
        width: Math.min(360, root.width * 0.3)
        height: Math.min(root.height - 48, 720)
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.rightMargin: 24
        radius: 20
        color: Qt.rgba(0.035, 0.05, 0.075, 0.95)
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.14)

        // Swallow clicks so the drag surface below does not move the scene.
        MouseArea {
            anchors.fill: parent
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 18
            spacing: 10

            Text {
                Layout.fillWidth: true
                text: "Perspektif"
                color: root.textColor
                renderType: Text.NativeRendering
                font.pixelSize: 17
                font.weight: Font.DemiBold
            }

            Text {
                Layout.fillWidth: true
                text: root.wallpaperLabel.length > 0
                    ? root.wallpaperLabel
                    : "Duvar kağıdı algılanmadı"
                color: Qt.rgba(root.textColor.r, root.textColor.g, root.textColor.b, 0.6)
                renderType: Text.NativeRendering
                font.pixelSize: 11
                elide: Text.ElideMiddle
            }

            CalSlider {
                Layout.fillWidth: true
                label: "X ekseni"
                from: -60
                to: 60
                step: 0.5
                value: root.angleX
                display: root.angleX.toFixed(1) + "°"
                onMoved: function (value) { root.edited({ angleX: value }) }
            }

            CalSlider {
                Layout.fillWidth: true
                label: "Y ekseni"
                from: -60
                to: 60
                step: 0.5
                value: root.angleY
                display: root.angleY.toFixed(1) + "°"
                onMoved: function (value) { root.edited({ angleY: value }) }
            }

            CalSlider {
                Layout.fillWidth: true
                label: "Z dönüşü"
                from: -180
                to: 180
                step: 0.5
                value: root.angleZ
                display: root.angleZ.toFixed(1) + "°"
                onMoved: function (value) { root.edited({ angleZ: value }) }
            }

            CalSlider {
                Layout.fillWidth: true
                label: "Ölçek"
                from: 0.4
                to: 2.0
                step: 0.01
                value: root.sceneScale
                display: root.sceneScale.toFixed(2) + "×"
                onMoved: function (value) { root.edited({ scale: value }) }
            }

            CalSlider {
                Layout.fillWidth: true
                label: "X konumu"
                from: 0
                to: 100
                step: 1
                value: root.positionX
                display: Math.round(root.positionX) + "%"
                onMoved: function (value) { root.edited({ positionX: value }) }
            }

            CalSlider {
                Layout.fillWidth: true
                label: "Y konumu"
                from: 0
                to: 100
                step: 1
                value: root.positionY
                display: Math.round(root.positionY) + "%"
                onMoved: function (value) { root.edited({ positionY: value }) }
            }

            Text {
                Layout.fillWidth: true
                text: "Hızlı hizalama"
                color: Qt.rgba(root.textColor.r, root.textColor.g, root.textColor.b, 0.62)
                renderType: Text.NativeRendering
                font.pixelSize: 10
            }

            GridLayout {
                Layout.fillWidth: true
                columns: 2
                columnSpacing: 6
                rowSpacing: 6

                CalButton {
                    Layout.fillWidth: true
                    label: "Üst Orta"
                    onClicked: root.edited({ positionX: 50, positionY: 18 })
                }
                CalButton {
                    Layout.fillWidth: true
                    label: "Alt Orta"
                    onClicked: root.edited({ positionX: 50, positionY: 78 })
                }
                CalButton {
                    Layout.fillWidth: true
                    label: "Sol Orta"
                    onClicked: root.edited({ positionX: 24, positionY: 50 })
                }
                CalButton {
                    Layout.fillWidth: true
                    label: "Sağ Orta"
                    onClicked: root.edited({ positionX: 76, positionY: 50 })
                }
            }

            Item { Layout.fillHeight: true }

            Text {
                Layout.fillWidth: true
                text: root.savedCount > 0
                    ? root.savedCount + " duvar kağıdı için perspektif kayıtlı"
                    : "Bu duvar kağıdı için henüz kayıt yok"
                color: Qt.rgba(root.textColor.r, root.textColor.g, root.textColor.b, 0.5)
                renderType: Text.NativeRendering
                font.pixelSize: 10
                wrapMode: Text.Wrap
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                CalButton {
                    Layout.fillWidth: true
                    label: "Kaydet"
                    primary: true
                    onClicked: root.saveRequested()
                }
                CalButton {
                    label: "Sıfırla"
                    onClicked: root.resetRequested()
                }
            }

            CalButton {
                Layout.fillWidth: true
                label: "Vazgeç"
                onClicked: root.cancelRequested()
            }
        }
    }

    // ------------------------------------------------------------ inline parts
    component CalSlider: ColumnLayout {
        id: slider

        property string label: ""
        property real from: 0
        property real to: 1
        property real step: 0.1
        property real value: 0
        property string display: ""

        signal moved(real value)

        spacing: 3

        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            Text {
                text: slider.label
                color: Qt.rgba(root.textColor.r, root.textColor.g, root.textColor.b, 0.82)
                renderType: Text.NativeRendering
                font.pixelSize: 11
            }
            Item { Layout.fillWidth: true }
            Text {
                text: slider.display
                color: root.accentColor
                renderType: Text.NativeRendering
                font.pixelSize: 11
                font.weight: Font.DemiBold
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 20

            Rectangle {
                id: track
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width
                height: 4
                radius: 2
                color: Qt.rgba(1, 1, 1, 0.16)
            }

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: track.width * slider.ratio
                height: 4
                radius: 2
                color: root.accentColor
            }

            Rectangle {
                width: 12
                height: 12
                radius: 6
                color: root.textColor
                border.width: 2
                border.color: root.accentColor
                x: track.width * slider.ratio - width / 2
                anchors.verticalCenter: parent.verticalCenter
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor

                function update(mouse) {
                    var ratio = Math.max(0, Math.min(1, mouse.x / track.width))
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

    component CalButton: Rectangle {
        id: button

        property string label: ""
        property bool primary: false

        signal clicked()

        implicitWidth: labelText.implicitWidth + 30
        implicitHeight: 36
        radius: 10
        color: button.primary
            ? root.accentColor
            : Qt.rgba(1, 1, 1, mouseArea.containsMouse ? 0.14 : 0.08)
        border.width: button.primary ? 0 : 1
        border.color: Qt.rgba(1, 1, 1, 0.16)

        Behavior on color {
            ColorAnimation { duration: 120 }
        }

        Text {
            id: labelText
            anchors.centerIn: parent
            text: button.label
            color: button.primary ? "#08111f" : root.textColor
            renderType: Text.NativeRendering
            font.pixelSize: 12
            font.weight: Font.DemiBold
        }

        MouseArea {
            id: mouseArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: button.clicked()
        }
    }
}
