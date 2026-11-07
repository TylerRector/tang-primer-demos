#!/usr/bin/env python3
import argparse
import sys
import time


def require_serial():
    try:
        import serial
    except ImportError:
        print("pyserial is required. Install it with: python3 -m pip install pyserial", file=sys.stderr)
        sys.exit(2)
    return serial


def validate_dna(label, value):
    bad = sorted(set(ch for ch in value if ch not in "ACGT"))
    if bad:
        raise SystemExit(f"{label} contains non-ACGT characters: {''.join(bad)}")


def overlapping_count(pattern, sequence):
    if not pattern:
        return 0
    total = 0
    start = 0
    while True:
        idx = sequence.find(pattern, start)
        if idx < 0:
            return total
        total += 1
        start = idx + 1


def clean_sequence_file(path):
    text = open(path, "r", encoding="utf-8").read()
    lines = []
    for line in text.splitlines():
        if line.startswith(">"):
            continue
        lines.append("".join(line.split()))
    return "".join(lines)


def open_port(args):
    serial = require_serial()
    return serial.Serial(args.port, args.baud, timeout=args.timeout, write_timeout=args.timeout)


def drain_startup(ser):
    deadline = time.time() + 0.25
    while time.time() < deadline:
        if ser.in_waiting:
            ser.read(ser.in_waiting)
            deadline = time.time() + 0.05
        else:
            time.sleep(0.01)


def transact(args, command):
    with open_port(args) as ser:
        drain_startup(ser)
        wire = (command + "\n").encode("ascii")
        if args.verbose:
            print(f"> {command}")
        ser.write(wire)
        ser.flush()
        reply = ser.readline().decode("ascii", errors="replace").rstrip("\r\n")
        if not reply:
            raise SystemExit(f"timed out waiting for reply to {command!r}")
        if args.verbose:
            print(f"< {reply}")
        return reply


def cmd_ping(args):
    print(transact(args, "PING"))


def cmd_version(args):
    print(transact(args, "VERSION"))


def cmd_reset(args):
    print(transact(args, "RESET"))


def do_count(args, sequence):
    pattern = args.pattern.upper()
    sequence = sequence.upper()
    if len(pattern) != 8:
        raise SystemExit("pattern must be exactly 8 A/C/G/T bases")
    validate_dna("pattern", pattern)
    validate_dna("sequence", sequence)

    expected = overlapping_count(pattern, sequence)
    with open_port(args) as ser:
        drain_startup(ser)
        for command, expected_prefix in ((f"SETPAT {pattern}", "OK"), (f"COUNT {sequence}", "COUNT ")):
            if args.verbose:
                print(f"> {command}")
            ser.write((command + "\n").encode("ascii"))
            ser.flush()
            reply = ser.readline().decode("ascii", errors="replace").rstrip("\r\n")
            if args.verbose:
                print(f"< {reply}")
            if not reply:
                raise SystemExit(f"timed out waiting for reply to {command!r}")
            if not reply.startswith(expected_prefix):
                raise SystemExit(f"unexpected reply to {command!r}: {reply}")

    try:
        fpga_count = int(reply.split()[1])
    except (IndexError, ValueError):
        raise SystemExit(f"invalid COUNT reply: {reply}")

    print(f"expected_count={expected}")
    print(f"fpga_count={fpga_count}")
    print(f"correct={str(fpga_count == expected).lower()}")
    if fpga_count != expected:
        raise SystemExit(1)


def cmd_count(args):
    do_count(args, args.sequence)


def cmd_count_file(args):
    sequence = clean_sequence_file(args.input)
    do_count(args, sequence)


def build_parser():
    parser = argparse.ArgumentParser(description="Tang Primer 20K bioinformatics UART host")
    parser.add_argument("--port", default="/dev/ttyUSB1")
    parser.add_argument("--baud", type=int, default=115200)
    parser.add_argument("--timeout", type=float, default=2.0)
    parser.add_argument("-v", "--verbose", action="store_true")

    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("ping").set_defaults(func=cmd_ping)
    sub.add_parser("version").set_defaults(func=cmd_version)
    sub.add_parser("reset").set_defaults(func=cmd_reset)

    count = sub.add_parser("count")
    count.add_argument("--pattern", required=True)
    count.add_argument("--sequence", required=True)
    count.set_defaults(func=cmd_count)

    count_file = sub.add_parser("count-file")
    count_file.add_argument("--pattern", required=True)
    count_file.add_argument("--input", required=True)
    count_file.set_defaults(func=cmd_count_file)
    return parser


def main():
    args = build_parser().parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
