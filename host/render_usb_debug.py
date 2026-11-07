#!/usr/bin/env python3
"""UART debug/control utility for the FPGA rendering demo."""

import argparse
import sys
import time

try:
    import serial
except ImportError:
    serial = None


def transact(port, command, timeout=1.0):
    port.write((command + "\n").encode("ascii"))
    port.flush()
    deadline = time.time() + timeout
    data = bytearray()
    while time.time() < deadline:
        b = port.read(1)
        if not b:
            continue
        data.extend(b)
        if b == b"\n":
            return data.decode("ascii", errors="replace").strip()
    return ""


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", default="/dev/ttyUSB1")
    parser.add_argument("--baud", type=int, default=115200)
    parser.add_argument("--telemetry-only", action="store_true")
    parser.add_argument("--mode", type=int)
    parser.add_argument("--debug", type=int)
    parser.add_argument("--precision", type=int)
    args = parser.parse_args()

    if serial is None:
        print("pyserial is required: python3 -m pip install pyserial", file=sys.stderr)
        return 2

    with serial.Serial(args.port, args.baud, timeout=0.05) as ser:
        time.sleep(0.2)
        ser.reset_input_buffer()
        for cmd in ("PING", "VERSION"):
            print(f"> {cmd}")
            print(f"< {transact(ser, cmd, 2.0)}")

        for name, value in (("MODE", args.mode), ("DEBUG", args.debug), ("PRECISION", args.precision)):
            if value is not None:
                cmd = f"{name} {value}"
                print(f"> {cmd}")
                print(f"< {transact(ser, cmd)}")

        if args.telemetry_only:
            print(f"> STATUS")
            print(f"< {transact(ser, 'STATUS')}")
            return 0

        print("Interactive commands: 0-8 mode, d debug, p precision, space start/stop, s status, r reset, q quit")
        debug = args.debug or 0
        precision = args.precision if args.precision is not None else 3
        running = False
        while True:
            key = input("render> ").strip().lower()
            if key in ("q", "quit", "exit"):
                return 0
            if key in tuple(str(i) for i in range(9)):
                cmd = f"MODE {key}"
            elif key == "d":
                debug = (debug + 1) % 3
                cmd = f"DEBUG {debug}"
            elif key == "p":
                precision = (precision + 1) % 4
                cmd = f"PRECISION {precision}"
            elif key in ("", " "):
                running = not running
                cmd = "DEMO_START" if running else "DEMO_STOP"
            elif key == "s":
                cmd = "STATUS"
            elif key == "r":
                cmd = "RESET"
            else:
                cmd = key.upper()
            print(f"< {transact(ser, cmd)}")


if __name__ == "__main__":
    raise SystemExit(main())
