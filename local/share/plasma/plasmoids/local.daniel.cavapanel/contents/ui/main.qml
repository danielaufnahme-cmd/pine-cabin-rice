import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.kirigami as Kirigami

// Small dock visualizer. Data comes from ~/.local/share/kde-cava/kde-cava.py,
// which streams one line of 16 levels (0-100, ';'-separated) per frame over a
// close-delimited HTTP response; QML has no socket API, so a streaming
// XMLHttpRequest reads it and reconnects when the helper ends the response.
PlasmoidItem {
    id: root

    readonly property string streamUrl: "http://127.0.0.1:47830/"
    readonly property int barCount: 16
    readonly property var stops: ["#3d4a3c", "#7f9a6e", "#c88a52", "#d9a26e"]

    property var levels: []
    property bool active: false
    property var xhr: null

    preferredRepresentation: fullRepresentation
    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground

    function colorAt(t) {
        const n = stops.length - 1;
        const x = Math.max(0, Math.min(1, t)) * n;
        const i = Math.min(n - 1, Math.floor(x));
        return Qt.tint(stops[i], Qt.alpha(stops[i + 1], x - i));
    }

    function handleLine(line) {
        const parts = line.split(";");
        const out = [];
        let any = false;
        for (let i = 0; i < barCount; ++i) {
            const v = (parseInt(parts[i]) || 0) / 100;
            out.push(v);
            if (v > 0) any = true;
        }
        levels = out;
        active = any;
        if (any) stall.restart();
    }

    function connect() {
        const req = new XMLHttpRequest();
        xhr = req;
        req.onreadystatechange = () => {
            if (req !== xhr) return;
            if (req.readyState === XMLHttpRequest.LOADING || req.readyState === XMLHttpRequest.DONE) {
                const text = req.responseText;
                const end = text.lastIndexOf("\n");
                if (end > 0) {
                    handleLine(text.substring(text.lastIndexOf("\n", end - 1) + 1, end));
                }
            }
            if (req.readyState === XMLHttpRequest.DONE) {
                // helper ended the response (normal) or is not running (retry slowly)
                reconnect.interval = req.status === 200 ? 10 : 3000;
                reconnect.restart();
            }
        };
        req.open("GET", streamUrl);
        req.send();
    }

    // reconnect after the helper closes a response
    Timer { id: reconnect; onTriggered: root.connect() }
    // helper went away mid-song: collapse
    Timer { id: stall; interval: 500; onTriggered: root.active = false }

    Component.onCompleted: connect()

    fullRepresentation: Item {
        id: rep

        readonly property int barWidth: 3
        readonly property int gap: 2
        readonly property int fullWidth: root.barCount * (barWidth + gap) - gap
        readonly property real maxBar: Math.round(Kirigami.Units.gridUnit * 1.3)

        Layout.minimumWidth: root.active ? fullWidth : 0
        Layout.preferredWidth: Layout.minimumWidth
        Layout.maximumWidth: Layout.minimumWidth
        Layout.fillHeight: true
        Behavior on Layout.minimumWidth { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

        opacity: root.active ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 160 } }
        clip: true

        Row {
            anchors.centerIn: parent
            spacing: rep.gap

            Repeater {
                model: root.barCount

                delegate: Rectangle {
                    required property int index
                    readonly property real value: root.levels[index] || 0

                    anchors.verticalCenter: parent.verticalCenter
                    width: rep.barWidth
                    height: Math.max(rep.barWidth, value * rep.maxBar)
                    radius: width / 2
                    color: root.colorAt(value)
                    opacity: 0.92
                }
            }
        }
    }
}
