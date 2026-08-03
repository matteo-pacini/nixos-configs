#!/usr/bin/env python3
"""Print 8BitDo Ultimate 2 battery for MangoHud's exec= param.

Battery lives in byte 14 of the 34-byte DInput input report; there is no
standard HID battery usage, so the kernel registers no power_supply node.
Only the 2.4GHz dongle in DInput mode (2dc8:6012) reports it.
"""

import glob
import os
import select
import sys

HID_ID = "0003:00002DC8:00006012"
REPORT_ID = 0x01
REPORT_LEN = 34
SERIAL = os.environ.get("PAD_SERIAL")


def find_node():
    for uevent in sorted(glob.glob("/sys/class/hidraw/*/device/uevent")):
        try:
            with open(uevent) as f:
                props = dict(
                    line.strip().split("=", 1) for line in f if "=" in line
                )
        except OSError:
            continue
        if props.get("HID_ID") != HID_ID:
            continue
        if SERIAL and props.get("HID_UNIQ") != SERIAL:
            continue
        return "/dev/" + uevent.split("/")[4]
    return None


def read_battery(node):
    fd = os.open(node, os.O_RDONLY | os.O_NONBLOCK)
    try:
        for _ in range(3):
            if not select.select([fd], [], [], 0.08)[0]:
                continue
            buf = os.read(fd, 64)
            if len(buf) >= REPORT_LEN and buf[0] == REPORT_ID:
                return buf[14]
    finally:
        os.close(fd)
    return None


node = find_node()
raw = read_battery(node) if node else None

if raw is None:
    print("PAD missing")
    sys.exit(0)

percent = raw & 0x7F
if percent == 100:
    print("PAD 100%")
elif raw >> 7:
    print(f"PAD {percent}% chg")
else:
    print(f"PAD {percent}%")
