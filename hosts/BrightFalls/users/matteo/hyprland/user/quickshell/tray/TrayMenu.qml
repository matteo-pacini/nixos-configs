import QtQuick
import Quickshell
import Quickshell.Services.SystemTray
import Quickshell.Wayland
import qs
import qs.common
import "menu.js" as M

// A tray icon's right-click menu, drawn by the shell and hanging under the
// icon on the monitor whose bar was clicked (Bar.qml asks through
// TrayShared). The entries are the application's own, read over DBusMenu,
// and follow its changes while open. Hover selects; a click runs an entry
// and closes, or steps into a submenu in place, with a back row on top; a
// click outside or Esc closes.
Scope {
    id: root

    readonly property bool open: TrayShared.screen !== ""
    readonly property int menuWidth: 250

    property SystemTrayItem item: null
    // The submenus stepped into, outermost first.
    property var stack: []
    readonly property var level: stack.length > 0 ? stack[stack.length - 1] : null

    function show(item: var, screen: string): void {
        Dropdowns.closeOthers("tray");
        window.screen = Array.from(Quickshell.screens).find(s => s.name === screen) ?? Quickshell.screens[0];
        root.item = item;
        stack = [];
        TrayShared.screen = window.screen.name;
    }

    function close(): void {
        TrayShared.screen = "";
        stack = [];
        item = null;
    }

    function run(entry: var): void {
        if (entry.isSeparator || !entry.enabled)
            return;
        if (entry.hasChildren) {
            stack = stack.concat([entry]);
            return;
        }
        entry.triggered();
        close();
    }

    function back(): void {
        stack = stack.slice(0, -1);
    }

    // The application left the tray while its menu was open.
    onItemChanged: if (item === null && open)
        close()

    Component.onCompleted: Dropdowns.add("tray", TrayShared)

    Connections {
        target: TrayShared

        function onOpenRequested(item, screen) {
            root.show(item, screen);
        }
        function onToggleRequested(screen) {
            if (root.open)
                root.close();
        }
    }

    // Holds the whole menu while it is open: DBusMenu drops the tree when the
    // last opener on its root lets go, submenus included.
    QsMenuOpener {
        id: rootOpener

        menu: root.open ? root.item?.menu ?? null : null
    }

    QsMenuOpener {
        id: levelOpener

        menu: root.level
        // The application rebuilt its menu and the submenu shown is gone.
        onMenuChanged: if (menu === null && root.stack.length > 0)
            root.stack = []
    }

    PanelWindow {
        id: window

        visible: root.open
        color: "transparent"
        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
        WlrLayershell.namespace: "desk-tray"
        onVisibleChanged: if (visible)
            keys.forceActiveFocus()

        // A click off the menu closes it, the bar included.
        MouseArea {
            anchors.fill: parent
            onClicked: root.close()
        }

        Item {
            id: keys

            focus: true
            Keys.onEscapePressed: root.close()
        }

        DropCard {
            centre: root.open ? Dropdowns.centre("tray", TrayShared.screen) : -1
            cardWidth: root.menuWidth
            contentHeight: content.implicitHeight

            Column {
                id: content

                x: 6
                y: 1
                width: parent.width - 12
                topPadding: 5
                bottomPadding: 5

                Text {
                    visible: root.level === null && text !== ""
                    width: parent.width
                    leftPadding: 8
                    rightPadding: 8
                    topPadding: 4
                    bottomPadding: 4
                    wrapMode: Text.Wrap
                    textFormat: Text.PlainText
                    text: M.title(root.item?.tooltipTitle, root.item?.title, root.item?.id)
                    color: Theme.comment
                    font.family: Theme.fontMono
                    font.pixelSize: 10
                    font.weight: Font.Medium
                    font.letterSpacing: 0.8
                    font.capitalization: Font.AllUppercase
                }

                MenuRow {
                    visible: root.level !== null
                    mark: "‹"
                    label: root.level?.text ?? ""
                    tone: Theme.cyan
                    markTone: Theme.cyan
                    onPicked: root.back()
                }

                Separator {
                    visible: root.level !== null
                }

                Repeater {
                    model: root.level ? levelOpener.children : rootOpener.children

                    Item {
                        id: entry

                        required property var modelData
                        readonly property var e: modelData
                        readonly property var m: M.mark(e.buttonType, e.checkState)

                        width: parent.width
                        height: e.isSeparator ? separator.height : row.height

                        Separator {
                            id: separator

                            visible: entry.e.isSeparator
                        }

                        MenuRow {
                            id: row

                            visible: !entry.e.isSeparator
                            enabled: entry.e.enabled
                            mark: entry.m.text
                            markOn: entry.m.on
                            label: entry.e.text
                            more: entry.e.hasChildren
                            onPicked: root.run(entry.e)
                        }
                    }
                }
            }
        }
    }

    component Separator: Item {
        width: parent.width
        height: 9

        Rectangle {
            x: 6
            y: 4
            width: parent.width - 12
            height: 1
            color: Theme.currentLine
        }
    }

    // One entry: a mark column, the label wrapping, and › for a submenu.
    // Disabled, it is dim and takes no hover or click.
    component MenuRow: Rectangle {
        id: rowItem

        property string mark
        property bool markOn
        property string label
        property bool more
        property color tone: Theme.foreground
        property color markTone: Theme.comment

        signal picked

        width: parent.width
        height: Math.max(labelText.implicitHeight, 19) + 10
        radius: 6
        color: enabled && area.containsMouse ? Theme.currentLine : "transparent"

        Text {
            x: 8
            y: 5
            width: 18
            height: 19
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            text: rowItem.mark
            color: rowItem.markOn ? Theme.green : rowItem.markTone
            font.family: Theme.fontMono
            font.pixelSize: 13
        }

        Text {
            id: labelText

            x: 8 + 18 + 7
            y: 5
            width: parent.width - x - (rowItem.more ? 24 : 8)
            wrapMode: Text.Wrap
            textFormat: Text.PlainText
            text: rowItem.label
            color: !rowItem.enabled ? Theme.comment : rowItem.tone
            font.family: Theme.fontUi
            font.pixelSize: 14
        }

        Text {
            visible: rowItem.more
            anchors.right: parent.right
            anchors.rightMargin: 8
            y: 5
            height: 19
            verticalAlignment: Text.AlignVCenter
            text: "›"
            color: Theme.comment
            font.family: Theme.fontMono
            font.pixelSize: 13
        }

        MouseArea {
            id: area

            anchors.fill: parent
            hoverEnabled: true
            onClicked: rowItem.picked()
        }
    }
}
