import QtQuick
import qs
import qs.common

// A section's title on the left and a plain note on the right, on one line
// the panel's width.
Item {
    id: root

    property string title
    property string note

    width: parent ? parent.width : 0
    height: header.implicitHeight

    SectionHeader {
        id: header

        text: root.title
    }

    Text {
        anchors.right: parent.right
        anchors.rightMargin: 14
        anchors.baseline: header.baseline
        text: root.note
        textFormat: Text.PlainText
        color: Theme.comment
        font.family: Theme.fontMono
        font.pixelSize: 11
    }
}
