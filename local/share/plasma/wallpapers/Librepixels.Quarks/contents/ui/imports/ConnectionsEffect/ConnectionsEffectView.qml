import QtQuick 2.0
import "../ConnectionsEffect"
import ConnectionsEffect 1.0
import org.kde.plasma.plasmoid

Item {
    id: view

    property alias level: fx.level
    property alias connectionsLevel: fx.connectionsLevel
    property alias lineColor: fx.lineColor
    property alias pointSize: fx.pointSize
    property alias animationSpeed: fx.animationSpeed
    property alias running: fx.running
    property alias softEdges: fx.softEdges
    property alias connectionsFactor: fx.connectionsFactor   // 0 = automático (según connectionsLevel)

    // --- Margen de conexión en función del tamaño del área (decidido aquí, en QML) ---
    // false -> el plugin usa su margen automático (40 / 38 / 33 según connectionsLevel)
    property bool autoScaleThreshold: true
    // Tamaño (px) del área en el que el margen vale su valor base
    property real referenceSize: 400
    // 0.5 = raíz cuadrada: mantiene ~constante el nº de vecinos por punto al crecer el área
    // 0 = sin escalar, 1 = proporcional al tamaño
    property real scaleExponent: 1

    readonly property real baseThreshold: connectionsLevel === 1 ? 40 : connectionsLevel === 2 ? 38 : 33
    readonly property real sizeFactor: Math.max(1, Math.pow(((width + height) / 2) / referenceSize, scaleExponent))

    ConnectionsEffect {
        id: fx
        level: root.configuration.level
        lineColor: root.configuration.quarksColor
        connectionsLevel: root.configuration.connectionsLevel
        connectionThreshold: view.autoScaleThreshold ? view.baseThreshold * view.sizeFactor : 0
        anchors.fill: parent
    }
}
