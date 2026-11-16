import QtQuick
import Quickshell
import qs
import qs.common

// The bar system item's hover list: every temperature in the machine, each
// coloured by its own limit. It takes no keyboard focus and has no keys.
PopupWindow {
    id: root

    required property Item item
    property bool shown: false

    readonly property var s: Sensors.s
    readonly property color soft: Style.soft
    readonly property var rows: {
        const s = root.s;
        const t = x => x === null || x === undefined ? "–" : `${Math.round(x)} °C`;
        const rows = [["CPU", t(s.cpuTemp), Sensors.heat("cpu", s.cpuTemp)], ["hottest core", t(s.cpuHottest), Sensors.heat("core", s.cpuHottest)]];
        if (s.egpuPresent && s.egpuAwake)
            rows.push(["eGPU edge", t(s.egpuEdge), Sensors.heat("edge", s.egpuEdge)], ["eGPU junction", t(s.egpuJunction), Sensors.heat("junction", s.egpuJunction)], ["eGPU memory", t(s.egpuMem), Sensors.heat("mem", s.egpuMem)]);
        else
            rows.push(["eGPU", s.egpuPresent ? "asleep" : "not connected", 0]);
        rows.push(["iGPU", t(s.igpuTemp), Sensors.heat("igpu", s.igpuTemp)]);
        const dimms = s.dimms ?? [];
        rows.push(["memory modules", dimms.length ? dimms.map(x => Math.round(x)).join(" · ") + " °C" : "–", Sensors.heat("dimm", dimms.length ? Math.max(...dimms) : null)]);
        rows.push(["NVMe", t(s.nvmeTemp), Sensors.heat("nvme", s.nvmeTemp)]);
        return rows;
    }

    visible: shown
    color: "transparent"
    implicitWidth: 230
    implicitHeight: list.implicitHeight + 2
    anchor.item: item
    // Centred under the item, as far below the bar as the panels.
    anchor.rect.x: item.width / 2
    anchor.rect.y: item.height + Style.belowBar
    anchor.gravity: Edges.Bottom

    Rectangle {
        anchors.fill: parent
        radius: Style.radius
        color: Style.surface
        border.width: 1
        border.color: Theme.purple

        Column {
            id: list

            x: 14
            y: 9
            width: parent.width - 28
            bottomPadding: 16
            spacing: 2

            Repeater {
                model: root.rows

                Item {
                    required property var modelData

                    width: parent.width
                    height: label.implicitHeight

                    Text {
                        id: label

                        text: parent.modelData[0]
                        color: Theme.comment
                        font.family: Theme.fontMono
                        font.pixelSize: 12
                    }

                    Text {
                        anchors.right: parent.right
                        text: parent.modelData[1]
                        color: parent.modelData[2] === 2 ? Theme.red : parent.modelData[2] === 1 ? Theme.orange : root.soft
                        font.family: Theme.fontMono
                        font.pixelSize: 12
                    }
                }
            }
        }
    }
}
