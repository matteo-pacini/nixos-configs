pragma Singleton

import QtQuick
import Quickshell

// The weather drawings' own tints: the sky, clouds, ground and map, which
// are not palette colours (the palette's are Theme's and Style's). Each sky
// is three stops, top, 62 % down and bottom.
Singleton {
    readonly property color sunCore: "#fbffb0"
    readonly property color moonShade: "#c9b1f5"

    // Condition art clouds, light, dark and black, top and bottom stops.
    readonly property var cloud: ["#eef0f5", "#9ea9cc"]
    readonly property var cloudDark: ["#8f9abf", "#535b82"]
    readonly property var cloudBlack: ["#6f7aa3", "#434a6c"]

    readonly property var skyBlank: ["#20212b", "#242530", "#2a2b38"]
    readonly property var skyNight: ["#11121a", "#1c1a30", "#2c2646"]
    readonly property var skyEdge: ["#232246", "#7a4c87", "#ffb07a"]
    readonly property var skyDay: ["#2a3763", "#4a6da2", "#8dbbd8"]
    // The overcast veil over the sky, by day and by night.
    readonly property color veilDay: "#3c4160"
    readonly property color veilNight: "#12131a"
    // Scene clouds: at night, in rain or snow, at sunrise or sunset, by day.
    readonly property color sceneCloudNight: "#474d72"
    readonly property color sceneCloudWet: "#7f89ad"
    readonly property color sceneCloudEdge: "#c9b6cf"
    readonly property color sceneCloudDay: "#dfe3ec"
    readonly property color ground: "#15161d"
    readonly property color windowDark: "#2b2d3a"

    readonly property color sea: "#14151c"
    readonly property color land: "#2b2d3a"
    // The legend's steps, light to heavy. Drawn as the design has them; the
    // radar tiles carry the provider's own colours.
    readonly property var radarSteps: ["#8fc2ff", "#3f7fe0", "#f1e05a", "#ff9f40", "#ff4545"]
}
