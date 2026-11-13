import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasma5support as P5Support
import org.kde.kirigami as Kirigami
import org.kde.taskmanager as TaskManager

PlasmoidItem {
    id: root

    preferredRepresentation: fullRepresentation
    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground

    readonly property bool vertical: Plasmoid.formFactor === PlasmaCore.Types.Vertical

    // Indices (0-based) of desktops to show: occupied ones plus the current one.
    property var shownIndices: []

    TaskManager.VirtualDesktopInfo { id: vdInfo }
    TaskManager.ActivityInfo { id: activityInfo }

    TaskManager.TasksModel {
        id: tasksModel
        groupMode: TaskManager.TasksModel.GroupDisabled
        filterByVirtualDesktop: false
        filterByScreen: false
        filterByActivity: true
        activity: activityInfo.currentActivity
        filterMinimized: false
        filterHidden: false
    }

    // One lightweight object per window, mirroring the roles we need.
    Instantiator {
        id: windows
        model: tasksModel
        delegate: QtObject {
            readonly property var desktops: model.VirtualDesktops
            readonly property bool onAll: model.IsOnAllVirtualDesktops === true
            readonly property bool skip: model.SkipTaskbar === true
            readonly property bool isWindow: model.IsWindow === true
            onDesktopsChanged: recompute.restart()
            onOnAllChanged: recompute.restart()
            onSkipChanged: recompute.restart()
        }
        onObjectAdded: recompute.restart()
        onObjectRemoved: recompute.restart()
    }

    // Coalesce bursts of model changes into one recompute.
    Timer {
        id: recompute
        interval: 0
        onTriggered: root.updateShown()
    }

    Connections {
        target: vdInfo
        function onCurrentDesktopChanged() { recompute.restart() }
        function onDesktopIdsChanged() { recompute.restart() }
    }

    Component.onCompleted: recompute.restart()

    function updateShown() {
        const ids = vdInfo.desktopIds;
        const occupied = {};
        for (let i = 0; i < windows.count; ++i) {
            const w = windows.objectAt(i);
            if (!w || !w.isWindow || w.onAll || w.skip || !w.desktops) {
                continue;
            }
            for (let j = 0; j < w.desktops.length; ++j) {
                occupied[w.desktops[j]] = true;
            }
        }
        const result = [];
        for (let i = 0; i < ids.length; ++i) {
            if (occupied[ids[i]] || ids[i] === vdInfo.currentDesktop) {
                result.push(i);
            }
        }
        shownIndices = result;
    }

    P5Support.DataSource {
        id: executable
        engine: "executable"
        connectedSources: []
        onNewData: (sourceName, data) => disconnectSource(sourceName)
    }

    function switchTo(index) {
        const id = vdInfo.desktopIds[index];
        if (id === undefined || id === vdInfo.currentDesktop) {
            return;
        }
        // Desktop ids are KWin UUIDs; reject anything else before building a command.
        if (!/^[A-Za-z0-9-]+$/.test(String(id))) {
            return;
        }
        executable.connectSource("busctl --user set-property org.kde.KWin /VirtualDesktopManager "
                                 + "org.kde.KWin.VirtualDesktopManager current s " + id);
    }

    function cycle(step) {
        const list = shownIndices;
        if (list.length < 2) {
            return;
        }
        const cur = vdInfo.desktopIds.indexOf(vdInfo.currentDesktop);
        let pos = list.indexOf(cur);
        pos = (pos + step + list.length) % list.length;
        switchTo(list[pos]);
    }

    fullRepresentation: Item {
        id: rep

        readonly property real pillSize: Math.round(Kirigami.Units.gridUnit * 1.1)

        Layout.minimumWidth: root.vertical ? pillSize : grid.implicitWidth
        Layout.preferredWidth: Layout.minimumWidth
        Layout.maximumWidth: Layout.minimumWidth
        Layout.minimumHeight: root.vertical ? grid.implicitHeight : pillSize
        Layout.preferredHeight: Layout.minimumHeight
        Layout.fillHeight: !root.vertical
        Layout.fillWidth: root.vertical

        WheelHandler {
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            property real accum: 0
            onWheel: event => {
                accum += event.angleDelta.y !== 0 ? event.angleDelta.y : event.angleDelta.x;
                while (accum >= 120) { accum -= 120; root.cycle(-1); }
                while (accum <= -120) { accum += 120; root.cycle(1); }
            }
        }

        Grid {
            id: grid
            anchors.centerIn: parent
            rows: root.vertical ? -1 : 1
            columns: root.vertical ? 1 : -1
            spacing: Math.round(Kirigami.Units.smallSpacing * 0.75)

            move: Transition {
                NumberAnimation { properties: "x,y"; duration: 150; easing.type: Easing.OutCubic }
            }
            add: Transition {
                NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 150 }
            }

            Repeater {
                model: root.shownIndices

                delegate: Rectangle {
                    id: pill
                    required property int modelData
                    readonly property bool active: vdInfo.desktopIds[modelData] === vdInfo.currentDesktop

                    width: active ? Math.round(rep.pillSize * 1.6) : rep.pillSize
                    height: rep.pillSize
                    radius: height / 2
                    color: active ? Kirigami.Theme.highlightColor
                         : mouse.containsMouse ? Qt.alpha(Kirigami.Theme.textColor, 0.18)
                         : Qt.alpha(Kirigami.Theme.textColor, 0.08)

                    Behavior on width { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                    Behavior on color { ColorAnimation { duration: 150 } }

                    Text {
                        anchors.centerIn: parent
                        text: String(pill.modelData + 1)
                        color: pill.active ? Kirigami.Theme.highlightedTextColor
                                           : Qt.alpha(Kirigami.Theme.textColor, 0.7)
                        font.pixelSize: Math.round(rep.pillSize * 0.6)
                        font.weight: pill.active ? Font.DemiBold : Font.Normal
                        Behavior on color { ColorAnimation { duration: 150 } }
                    }

                    MouseArea {
                        id: mouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.switchTo(pill.modelData)
                    }
                }
            }
        }
    }
}
