// PineCabin splash: dark pine background, cedar emblem, thin progress line.
import QtQuick

Rectangle {
    id: root
    color: "#141815"

    // Set by ksplashqml as Plasma starts up (1..6).
    property int stage
    readonly property int lastStage: 6

    Component.onCompleted: fadeIn.start()

    Item {
        id: content
        anchors.fill: parent
        opacity: 0

        Image {
            id: emblem
            anchors.centerIn: parent
            anchors.verticalCenterOffset: -height * 0.08
            width: Math.round(Math.min(root.width, root.height) * 0.16)
            height: Math.round(width * sourceSize.height / sourceSize.width)
            source: "images/emblem.png"
            smooth: true
            mipmap: true
        }

        Rectangle {
            id: track
            width: emblem.width * 1.1
            height: 2
            radius: 1
            color: "#3d4a3c"
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: emblem.bottom
            anchors.topMargin: emblem.height * 0.35

            Rectangle {
                height: parent.height
                radius: 1
                color: "#c88a52"
                width: parent.width * Math.min(root.stage, root.lastStage) / root.lastStage
                Behavior on width { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
            }
        }
    }

    OpacityAnimator { id: fadeIn;  target: content; from: 0; to: 1; duration: 200; easing.type: Easing.OutQuad }
}
