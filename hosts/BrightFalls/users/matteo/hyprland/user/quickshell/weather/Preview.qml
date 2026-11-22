import QtQuick
import qs

// Every weather drawing in its states, with fixed invented inputs, for a
// look during development: the twelve kinds at 64 and 22 px, nine skies,
// four hour strips and four radar maps. Not loaded by shell.qml; put it in
// a temporary window to see it. `coast` is the generated coast file's
// rings, `frames` and `frameDir` as RadarMap takes them, `running` starts
// the motion.
Item {
    id: root

    property var coast: []
    property var frames: []
    property string frameDir: ""
    property bool running: false

    readonly property var kinds: ["sunny", "clear-night", "partlycloudy", "partlycloudy-night", "cloudy", "rainy", "pouring", "lightning-rainy", "snowy", "snowy-rainy", "fog", "windy"]

    // The design page's scenes: hour of day against sunrise 7.5 and sunset
    // 16.1, turned into SkyScene's inputs.
    function sky(o) {
        const sr = 7.5, ss = 16.1, t = o.t || 0;
        const day = !o.blank && t >= sr && t <= ss;
        const frac = o.blank ? 0 : day ? (t - sr) / (ss - sr) : ((t < sr ? t + 24 : t) - ss) / (24 - ss + sr);
        const edge = day && (frac < 0.12 || frac > 0.88);
        return {
            blank: !!o.blank,
            day: day,
            frac: frac,
            edge: edge,
            cloud: o.cloud || 0,
            rain: o.rain || 0,
            snow: !!o.snow,
            fog: !!o.fog,
            lit: !o.blank && (!day || edge),
            seed: o.seed || 11
        };
    }

    readonly property var skies: [
        {
            t: 11.8
        },
        {
            t: 14,
            cloud: 0.45,
            seed: 4
        },
        {
            t: 15.6,
            cloud: 0.8,
            rain: 1,
            seed: 9
        },
        {
            t: 22,
            seed: 3
        },
        {
            t: 2,
            cloud: 0.85,
            snow: true,
            seed: 14
        },
        {
            t: 8.1,
            cloud: 0.3,
            fog: true,
            seed: 6
        },
        {
            t: 12.5,
            cloud: 1,
            rain: 2.4,
            seed: 17
        },
        {
            t: 20,
            cloud: 1,
            seed: 8
        },
        {
            blank: true
        }
    ].map(sky)

    function hours(start, temps, wet, kinds, now) {
        return temps.map((t, i) => {
            const p = wet[i] || 0, r = Math.round(t);
            return {
                label: i === 0 && now ? "now" : String((start + i) % 24).padStart(2, "0"),
                now: i === 0 && now,
                art: kinds[i] || (p > 1.5 ? "pouring" : p ? "rainy" : "cloudy"),
                temp: t,
                tempText: (r < 0 ? "−" : "") + Math.abs(r) + "°",
                precip: p,
                precipText: p.toFixed(1)
            };
        });
    }

    readonly property var strips: [hours(16, [9, 8.6, 8.2, 7.6, 7, 6.2, 5.4, 4.8], [0.4, 1.3, 2.2, 1.6, 0.7, 0.2], [, , , , , , "partlycloudy-night", "partlycloudy-night"], true), hours(12, [11.2, 12.4, 13, 12.6, 11.4, 9.6, 8, 6.8], [], ["sunny", "sunny", "sunny", "partlycloudy", "partlycloudy", "clear-night", "clear-night", "clear-night"], true), hours(2, [-1.8, -2.2, -2.6, -2.9, -3, -2.4, -1.2, 0.3], [0.6, 0.9, 1.1, 0.5, 0.2], ["snowy", "snowy", "snowy", "snowy", "snowy", "cloudy", "cloudy", "partlycloudy"], false), hours(15, [31.6, 31, 29.4, 27, 24.8, 23, 21.6, 20.8], [0, 6.4, 12.8, 5.2, 0.8], ["partlycloudy", "lightning-rainy", "lightning-rainy", "pouring", "rainy", "cloudy", "partlycloudy-night", "clear-night"], true)]

    implicitWidth: 1720
    implicitHeight: layout.implicitHeight

    Column {
        id: layout

        spacing: 16

        Row {
            spacing: 10

            Repeater {
                model: root.kinds

                Column {
                    id: cell

                    required property string modelData

                    spacing: 6

                    ConditionArt {
                        kind: cell.modelData
                        size: 64
                    }

                    ConditionArt {
                        anchors.horizontalCenter: parent.horizontalCenter
                        kind: cell.modelData
                        size: 22
                    }
                }
            }
        }

        Flow {
            width: root.implicitWidth
            spacing: 12

            Repeater {
                model: root.skies

                SkyScene {
                    required property var modelData

                    width: 420
                    height: 170
                    blank: modelData.blank
                    day: modelData.day
                    frac: modelData.frac
                    edge: modelData.edge
                    cloud: modelData.cloud
                    rain: modelData.rain
                    snow: modelData.snow
                    fog: modelData.fog
                    lit: modelData.lit
                    seed: modelData.seed
                    running: root.running
                }
            }
        }

        Flow {
            width: root.implicitWidth
            spacing: 12

            Repeater {
                model: root.strips

                Rectangle {
                    id: strip

                    required property var modelData

                    width: 420
                    height: 120
                    color: Theme.background

                    HoursStrip {
                        x: 14
                        y: 4
                        hours: strip.modelData
                    }
                }
            }
        }

        Flow {
            width: root.implicitWidth
            spacing: 12

            Repeater {
                // The contract's sample centre; a note; no centre; no frame.
                model: [
                    {
                        centre: [412.3, 520.8],
                        note: ""
                    },
                    {
                        centre: [412.3, 520.8],
                        note: "No rain on the radar."
                    },
                    {
                        centre: null,
                        note: "Radar not available."
                    },
                    {
                        centre: [700, 980],
                        note: ""
                    }
                ]

                Rectangle {
                    id: map

                    required property var modelData

                    width: 420
                    height: 260
                    color: Theme.background

                    RadarMap {
                        x: 14
                        y: 4
                        coast: root.coast
                        centre: map.modelData.centre
                        note: map.modelData.note
                        frames: root.frames
                        frameDir: root.frameDir
                    }
                }
            }
        }
    }
}
