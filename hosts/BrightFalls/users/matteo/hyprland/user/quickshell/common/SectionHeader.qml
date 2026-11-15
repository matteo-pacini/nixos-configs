import QtQuick
import qs

// A section's title in a panel, given in capitals ("SET IN NIX"): small,
// letter-spaced mono.
Text {
    leftPadding: 14
    topPadding: 10
    bottomPadding: 3
    color: Theme.comment
    font.family: Theme.fontMono
    font.pixelSize: 11
    font.weight: Font.Medium
    font.letterSpacing: 0.88
}
