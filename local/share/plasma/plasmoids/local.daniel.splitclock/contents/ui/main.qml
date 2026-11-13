/*
    SPDX-FileCopyrightText: 2022 qewer33
    SPDX-License-Identifier: GPL-3.0-or-later
*/

import QtQuick 2.12
import QtQuick.Layouts 1.12
import Qt5Compat.GraphicalEffects
import org.kde.plasma.plasma5support as Plasma5Support

import org.kde.plasma.core 2.0 as PlasmaCore
import org.kde.plasma.plasmoid 2.0
import org.kde.plasma.components 3.0 as PlasmaComponents
import org.kde.plasma.extras 2.0 as PlasmaExtras

PlasmoidItem {
    id: root

    preferredRepresentation: fullRepresentation
    Plasmoid.backgroundHints: PlasmaCore.Types.ConfigurableBackground

    readonly property date currentDateTime: dataSource.data.Local ? dataSource.data.Local.DateTime : new Date()

    Plasma5Support.DataSource {
        id: dataSource
        engine: "time"
        connectedSources: ["Local"]
        interval: plasmoid.configuration.clockShowSeconds ? 1000 : 60000
        intervalAlignment: plasmoid.configuration.clockShowSeconds ? Plasma5Support.Types.NoAlignment : Plasma5Support.Types.AlignToMinute
    }

    FontLoader {
        id: fontOutfitBold
        source: "../fonts/Outfit-Bold.ttf"
    }

    FontLoader {
        id: fontOutfitRegular
        source: "../fonts/Outfit-Regular.ttf"
    }

    FontLoader {
        id: fontSmooch
        source: "../fonts/Smooch-Regular.ttf"
    }

    // Split-tone patch: the text is drawn once as an alpha mask and filled with
    // a two-colour gradient whose hard edge sits on the wallpaper diagonal, so
    // letters are in the text colour on one side and a quiet dim tone on the other (PineCabin).
    fullRepresentation: Item {
        id: splitRoot

        implicitWidth: textColumn.implicitWidth
        implicitHeight: textColumn.implicitHeight
        Layout.minimumWidth: textColumn.Layout.minimumWidth
        Layout.minimumHeight: textColumn.Layout.minimumHeight

        // Wallpaper diagonal edge measured on forest-triangle-nordic.png scaled
        // to 2560x1440: screen X - Y = 1172.7 (scaled with the screen width).
        readonly property real diagOffset: 1172.7 * (Window.width > 0 ? Window.width / 2560 : 1)
        readonly property color skyTone: Qt.rgba(plasmoid.configuration.clockFontColor.r,
                                                 plasmoid.configuration.clockFontColor.g,
                                                 plasmoid.configuration.clockFontColor.b, 1)
        readonly property color wedgeTone: "#869180"   // PineCabin dim text: quiet second tone
        // The diagonal in this item's coordinates is localX - localY = lineK.
        property real lineK: diagOffset

        function updateLine() {
            var p = splitRoot.mapToItem(null, 0, 0)
            lineK = diagOffset - p.x + p.y
        }

        onDiagOffsetChanged: updateLine()
        onWindowChanged: updateLine()
        Component.onCompleted: {
            // The applet moves via its ancestors, so follow every one of them.
            for (var it = splitRoot; it; it = it.parent) {
                it.xChanged.connect(updateLine)
                it.yChanged.connect(updateLine)
            }
            updateLine()
        }

        // Two-tone fill: sky tone everywhere, plus a 45-degree rotated square
        // in the wedge tone whose (antialiased) edge lies exactly on the line.
        Item {
            id: toneFill
            anchors.fill: textColumn
            visible: false

            readonly property real side: 4000
            // Line point (k, 0) pushed half a side towards the dark wedge.
            readonly property real k: splitRoot.lineK - textColumn.x + textColumn.y
            readonly property real cx: k + side / 2 / Math.SQRT2
            readonly property real cy: -side / 2 / Math.SQRT2

            Rectangle {
                anchors.fill: parent
                color: splitRoot.skyTone
            }
            Rectangle {
                x: toneFill.cx - width / 2
                y: toneFill.cy - height / 2
                width: toneFill.side
                height: toneFill.side
                rotation: 45
                antialiasing: true
                color: splitRoot.wedgeTone
            }
        }

        OpacityMask {
            anchors.fill: textColumn
            source: toneFill
            maskSource: textColumn
        }

        ColumnLayout {
            id: textColumn
            anchors.fill: parent
            visible: false
            spacing: -20

            TextMetrics {
                id: textMetricsClockLabel
                font.family: clockLabel.font.family
                font.pixelSize: clockLabel.font.pixelSize
                font.bold: clockLabel.font.bold
                text: if (!plasmoid.configuration.clockShowSeconds) " 99:99 "
                      else " 99:99:99 "
            }

            TextMetrics {
                id: textMetricsDayLabel
                font.family: dayLabel.font.family
                font.pixelSize: dayLabel.font.pixelSize
                font.bold: dayLabel.font.bold
                text: " Wednesday "
            }

            Item {
                implicitWidth: Math.max(textMetricsClockLabel.width, textMetricsDayLabel.width)
                implicitHeight: Math.max(textMetricsClockLabel.height, textMetricsDayLabel.height)
                Layout.alignment: Qt.AlignHCenter

                Text {
                    id: clockLabel
                    anchors.centerIn: parent

                    property var getTextFormat: {
                        var AMPM = plasmoid.configuration.clockUse24hFormat ? "" : " AP"
                        if (plasmoid.configuration.clockShowSeconds)
                            return Qt.formatTime(currentDateTime, "hh.mm.ss" + AMPM).split(".").join(plasmoid.configuration.clockSeparator)
                        else
                            return Qt.formatTime(currentDateTime, "hh.mm" + AMPM).split(".").join(plasmoid.configuration.clockSeparator)
                    }

                    text: getTextFormat

                    color: plasmoid.configuration.clockFontColor
                    font.family: if (plasmoid.configuration.clockFontFamily === "ccdefault") fontOutfitBold.name
                                 else plasmoid.configuration.clockFontFamily
                    font.bold: plasmoid.configuration.clockBoldText
                    font.italic: plasmoid.configuration.clockItalicText
                    font.pixelSize: plasmoid.configuration.clockFontSize

                    // Halo off: a layered child does not render inside the hidden mask source.
                    layer.enabled: false
                    layer.effect: DropShadow {
                        color: plasmoid.configuration.clockShadowColor
                        radius: plasmoid.configuration.clockShadowRadius
                        horizontalOffset: plasmoid.configuration.clockShadowXOffset
                        verticalOffset: plasmoid.configuration.clockShadowYOffset
                        samples: plasmoid.configuration.clockShadowRadius*2
                    }
                }

                Text {
                    id: dayLabel
                    visible: plasmoid.configuration.showDayDisplay
                    anchors.centerIn: parent

                    text: Qt.formatDate(currentDateTime, "dddd")

                    color: plasmoid.configuration.dayFontColor
                    font.family: if (plasmoid.configuration.dayFontFamily === "ccdefault") fontSmooch.name
                                 else plasmoid.configuration.dayFontFamily
                    font.bold: plasmoid.configuration.dayBoldText
                    font.italic: plasmoid.configuration.dayItalicText
                    font.pixelSize: plasmoid.configuration.dayFontSize

                    layer.enabled: plasmoid.configuration.dayShadowEnabled
                    layer.effect: DropShadow {
                        color: plasmoid.configuration.dayShadowColor
                        radius: plasmoid.configuration.dayShadowRadius
                        horizontalOffset: plasmoid.configuration.dayShadowXOffset
                        verticalOffset: plasmoid.configuration.dayShadowYOffset
                        samples: plasmoid.configuration.dayShadowYOffset*2
                    }
                }
            }

            Text {
                id: dateLabel
                visible: plasmoid.configuration.showDateDisplay
                Layout.alignment: Qt.AlignHCenter

                text: Qt.formatDate(currentDateTime, plasmoid.configuration.dateCustomDateFormat)

                color: plasmoid.configuration.dateFontColor
                font.family: if (plasmoid.configuration.dateFontFamily === "ccdefault") fontOutfitRegular.name
                             else plasmoid.configuration.dateFontFamily
                font.bold: plasmoid.configuration.dateBoldText
                font.italic: plasmoid.configuration.dateItalicText
                font.pixelSize: plasmoid.configuration.dateFontSize
                font.capitalization: Font.AllUppercase
                font.letterSpacing: plasmoid.configuration.dateLetterSpacing

                layer.enabled: plasmoid.configuration.dateShadowEnabled
                layer.effect: DropShadow {
                    color: plasmoid.configuration.dateShadowColor
                    radius: plasmoid.configuration.dateShadowRadius
                    horizontalOffset: plasmoid.configuration.dateShadowXOffset
                    verticalOffset: plasmoid.configuration.dateShadowYOffset
                    samples: plasmoid.configuration.dateShadowYOffset*2
                }
            }
        }
    }
}
