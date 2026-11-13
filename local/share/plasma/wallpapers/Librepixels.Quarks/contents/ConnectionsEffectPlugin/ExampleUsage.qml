import QtQuick
import ConnectionsEffect 1.0

// Reemplazo directo del Rectangle+Canvas original.
// "configuration" es el mismo objeto de configuracion del wallpaper/widget
// que ya estabas usando (root.configuration.level, .connectionsLevel, etc).
Rectangle {
    id: root
    color: "transparent"
    clip: true

    ConnectionsEffect {
        anchors.fill: parent
        level: root.configuration.level
        connectionsLevel: root.configuration.connectionsLevel
        lineColor: root.configuration.quarksColor
        pointSize: 2
        animationSpeed: 0.6
        running: root.visible // pausa la simulacion si el item no se ve
    }
}
