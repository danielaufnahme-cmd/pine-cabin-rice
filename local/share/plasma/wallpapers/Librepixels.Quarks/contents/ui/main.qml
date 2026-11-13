/*
 *  SPDX-FileCopyrightText: 2026 zayronxio <adolfo@librepixels.com>
 *
 *  SPDX-License-Identifier: GPL-3.0-or-later
 */

import QtQuick
import org.kde.plasma.plasmoid

WallpaperItem {
    id: root

    property color firstColor: root.configuration.gradientStart
    property color endColor: root.configuration.gradientEnd
    // Propiedad para controlar la opacidad del ruido
    property real noiseOpacity: 0.5
    // Propiedad para activar/desactivar el ruido
    property bool noiseEnabled: true

    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: firstColor } // Puedes cambiar los colores
            GradientStop { position: 1.0; color: endColor }
        }
    }

    Loader {
        id: fxLoader
        // Área del efecto, centrada. Usa las mismas medidas que usaba tu efecto original:
        width: root.configuration.elementWidth
        height: root.configuration.elementHeight
        anchors.centerIn: parent
        source: "imports/ConnectionsEffect/ConnectionsEffectView.qml"
    }
}

