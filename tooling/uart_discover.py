#!/usr/bin/env python3
"""Discover the FPGA UART port and run a deterministic smoke test."""

import argparse
import glob
import os
import subprocess
import sys
import time

try:
    import serial
except ImportError:
    serial = None


COMMANDS = (
    ("PING", "PONG"),
    ("VERSION", "VERSION "),
    ("STATUS", "STATUS "),
)

RENDER_CONTROL_COMMANDS = (
    ("DEMO_START", "OK"),
    ("MODE 1", "OK"),
    ("DEBUG 1", "OK"),
    ("PRECISION 2", "OK"),
    ("STATUS", "STATUS "),
    ("DEMO_STOP", "OK"),
    ("STATUS", "STATUS "),
)


def read_available(ser, seconds):
    deadline = time.time() + seconds
    data = bytearray()
    while time.time() < deadline:
        chunk = ser.read(256)
        if chunk:
            data.extend(chunk)
            deadline = time.time() + 0.15
    return bytes(data)


def readline_after_command(ser, command, timeout):
    ser.write((command + "\n").encode("ascii"))
    ser.flush()
    deadline = time.time() + timeout
    data = bytearray()
    while time.time() < deadline:
        b = ser.read(1)
        if not b:
            continue
        data.extend(b)
        if b == b"\n":
            break
    return bytes(data)


def probe_port(path, baud, timeout, settle, render_controls=False):
    result = {
        "port": path,
        "baud": baud,
        "opened": False,
        "boot": "",
        "replies": [],
        "pass": False,
        "error": "",
    }
    try:
        with serial.Serial(path, baud, timeout=0.05, write_timeout=timeout) as ser:
            ser.dtr = False
            ser.rts = False
            time.sleep(settle)
            ser.reset_input_buffer()
            result["opened"] = True
            result["boot"] = read_available(ser, 0.25).decode("ascii", errors="replace")
            ok = True
            commands = COMMANDS + (RENDER_CONTROL_COMMANDS if render_controls else ())
            for command, expected_prefix in commands:
                raw = readline_after_command(ser, command, timeout)
                text = raw.decode("ascii", errors="replace").strip()
                result["replies"].append({"command": command, "reply": text, "raw_hex": raw.hex()})
                if not text.startswith(expected_prefix):
                    ok = False
            result["pass"] = ok
    except Exception as exc:
        result["error"] = str(exc)
    return result


def print_result(result):
    print(f"PORT {result['port']} baud={result['baud']}")
    if result["error"]:
        print(f"  error={result['error']}")
        return
    if result["boot"]:
        print(f"  boot={result['boot']!r}")
    for reply in result["replies"]:
        print(f"  {reply['command']} -> {reply['reply']!r} raw={reply['raw_hex']}")
    print(f"  RESULT {'PASS' if result['pass'] else 'FAIL'}")


def run_program(command):
    print("PROGRAM", " ".join(command))
    proc = subprocess.run(command, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    print(proc.stdout)
    return proc.returncode


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--ports", nargs="*", default=None, help="Ports to test; default is all /dev/ttyUSB*")
    parser.add_argument("--baud", type=int, default=115200)
    parser.add_argument("--timeout", type=float, default=1.0)
    parser.add_argument("--settle", type=float, default=0.2)
    parser.add_argument("--program", action="store_true", help="Program SRAM before probing")
    parser.add_argument("--render-controls", action="store_true", help="Also test DEMO/MODE/DEBUG/PRECISION commands")
    parser.add_argument(
        "--program-command",
        nargs="+",
        default=["openFPGALoader", "-b", "tangprimer20k", "--freq", "1000000", "--reset", "build/blink/impl/pnr/blink.fs"],
    )
    args = parser.parse_args()

    if serial is None:
        print("pyserial is required: python3 -m pip install pyserial", file=sys.stderr)
        return 2

    ports = args.ports if args.ports else sorted(glob.glob("/dev/ttyUSB*"))
    if not ports:
        print("No /dev/ttyUSB* ports found", file=sys.stderr)
        return 1

    if args.program:
        rc = run_program(args.program_command)
        if rc != 0:
            return rc

    results = [probe_port(path, args.baud, args.timeout, args.settle, args.render_controls) for path in ports]
    for result in results:
        print_result(result)

    passing = [result for result in results if result["pass"]]
    if passing:
        print(f"SELECTED_PORT {passing[0]['port']}")
        return 0
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
