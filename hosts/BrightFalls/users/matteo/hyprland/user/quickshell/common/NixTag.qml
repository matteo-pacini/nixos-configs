import QtQuick
import qs

// The small "nix" box marking a value the NixOS configuration fixes.
Rectangle {
    property int pixelSize: 11

    width: tagText.implicitWidth + 10
    height: tagText.implicitHeight + 2
    radius: 4
    color: "transparent"
    border.width: 1
    border.color: Theme.currentLine

    Text {
        id: tagText

        anchors.centerIn: parent
        text: "nix"
        color: Theme.comment
        font.family: Theme.fontMono
        font.pixelSize: parent.pixelSize
    }
}
