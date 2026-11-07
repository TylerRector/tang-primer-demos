#!/usr/bin/env python3
"""Play host audio and send timestamped render commands over UART."""

import argparse
import json
import os
import subprocess
import time

try:
    import serial
except ImportError:
    serial = None


MODE_NAMES = {
    "boot_scanline": 0,
    "fixed_precision": 5,
    "bitplane": 6,
    "parallel_units": 1,
    "debug_views": 3,
    "uncertainty_edges": 7,
    "cordic_tunnel": 8,
    "midframe_mutation": 4,
    "finale_splitview": 4,
    "outro_decay": 2,
}


def send_line(ser, line):
    ser.write((line + "\n").encode("ascii"))
    ser.flush()
    return ser.readline().decode("ascii", errors="replace").strip()


def start_audio(path):
    for player in ("cvlc", "ffplay", "vlc"):
        if subprocess.call(["which", player], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL) == 0:
            if player == "ffplay":
                return subprocess.Popen([player, "-nodisp", "-autoexit", path])
            return subprocess.Popen([player, "--play-and-exit", path])
    raise RuntimeError("no supported player found: install vlc/cvlc or ffplay")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", default="/dev/ttyUSB1")
    parser.add_argument("--baud", type=int, default=115200)
    parser.add_argument("--audio", default="assets/song.mp4")
    parser.add_argument("--timeline", default="assets/song_timeline.json")
    args = parser.parse_args()

    if serial is None:
        raise SystemExit("pyserial is required: python3 -m pip install pyserial")
    if not os.path.exists(args.audio):
        raise SystemExit(f"audio file not found: {args.audio}")
    if not os.path.exists(args.timeline):
        raise SystemExit(f"timeline file not found: {args.timeline}")

    with open(args.timeline, "r", encoding="utf-8") as fh:
        timeline = json.load(fh)
    events = sorted(timeline.get("sections", []), key=lambda item: float(item.get("time", 0.0)))
    os.makedirs("results/logs", exist_ok=True)

    with serial.Serial(args.port, args.baud, timeout=0.5) as ser, open("results/logs/demo_sync.log", "w", encoding="utf-8") as log:
        time.sleep(0.2)
        ser.reset_input_buffer()
        for cmd in ("PING", "VERSION"):
            reply = send_line(ser, cmd)
            print(cmd, reply)
            log.write(f"{time.time():.3f} {cmd} -> {reply}\n")

        proc = start_audio(args.audio)
        start = time.monotonic()
        reply = send_line(ser, "DEMO_START")
        log.write(f"{time.time():.3f} DEMO_START -> {reply}\n")

        for event in events:
            target = float(event.get("time", 0.0))
            while time.monotonic() - start < target:
                time.sleep(0.01)
            mode = event.get("mode", 0)
            mode_num = MODE_NAMES.get(mode, mode)
            cmd = f"MODE {int(mode_num)}"
            reply = send_line(ser, cmd)
            print(f"{target:7.3f}s {cmd} {reply}")
            log.write(f"{time.time():.3f} {cmd} -> {reply}\n")

        proc.wait()
        reply = send_line(ser, "DEMO_STOP")
        log.write(f"{time.time():.3f} DEMO_STOP -> {reply}\n")


if __name__ == "__main__":
    main()
