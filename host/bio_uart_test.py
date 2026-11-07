#!/usr/bin/env python3
import argparse
import sys
import time


DEFAULT_PATTERN = "ACGTACGT"
DEFAULT_SEQUENCE = "ACGTACGTACGTACGT"


def require_serial():
    try:
        import serial
    except ImportError:
        print("Missing dependency: pyserial", file=sys.stderr)
        print("Install with: python3 -m pip install --user pyserial", file=sys.stderr)
        sys.exit(2)
    return serial


def count_exact_overlapping(sequence: str, pattern: str) -> int:
    if not pattern:
        return 0
    count = 0
    for index in range(0, len(sequence) - len(pattern) + 1):
        if sequence[index:index + len(pattern)] == pattern:
            count += 1
    return count


def validate_dna(label: str, value: str) -> None:
    invalid = sorted(set(ch for ch in value if ch not in "ACGT"))
    if invalid:
        raise ValueError(f"{label} contains invalid DNA characters: {''.join(invalid)}")


def drain_startup(ser) -> None:
    deadline = time.time() + 0.25
    while time.time() < deadline:
        waiting = getattr(ser, "in_waiting", 0)
        if waiting:
            ser.read(waiting)
            deadline = time.time() + 0.05
        else:
            time.sleep(0.01)


def send_command(ser, command: str, timeout_label: str) -> str:
    ser.write((command + "\n").encode("ascii"))
    ser.flush()
    reply = ser.readline().decode("ascii", errors="replace").strip()
    if not reply:
        raise TimeoutError(f"timeout waiting for response to {timeout_label}")
    return reply


def parse_count(reply: str) -> int:
    parts = reply.split()
    if len(parts) != 2 or parts[0] != "COUNT":
        raise ValueError(f"expected COUNT reply, got: {reply}")
    return int(parts[1])


def run_stream_count(ser, pattern: str, chunks) -> int:
    setpat_reply = send_command(ser, f"SETPAT {pattern}", "SETPAT")
    if setpat_reply != "OK":
        raise ValueError(f"SETPAT failed before stream: {setpat_reply}")
    begin_reply = send_command(ser, "STREAM_BEGIN", "STREAM_BEGIN")
    if begin_reply != "OK":
        raise ValueError(f"STREAM_BEGIN failed: {begin_reply}")
    for chunk in chunks:
        stream_reply = send_command(ser, f"STREAM {chunk}", "STREAM")
        if stream_reply != "OK":
            raise ValueError(f"STREAM failed for chunk {chunk!r}: {stream_reply}")
    end_reply = send_command(ser, "STREAM_END", "STREAM_END")
    return parse_count(end_reply)


def run_quiet_stream_count(ser, pattern: str, chunks) -> int:
    setpat_reply = send_command(ser, f"SETPAT {pattern}", "SETPAT")
    if setpat_reply != "OK":
        raise ValueError(f"SETPAT failed before quiet stream: {setpat_reply}")
    begin_reply = send_command(ser, "STREAM_BEGIN_QUIET", "STREAM_BEGIN_QUIET")
    if begin_reply != "OK":
        raise ValueError(f"STREAM_BEGIN_QUIET failed: {begin_reply}")
    for chunk in chunks:
        ser.write((f"STREAM {chunk}\n").encode("ascii"))
        ser.flush()
    end_reply = send_command(ser, "STREAM_END", "STREAM_END")
    return parse_count(end_reply)


def run(args) -> int:
    pattern = DEFAULT_PATTERN
    sequence = DEFAULT_SEQUENCE
    validate_dna("pattern", pattern)
    validate_dna("sequence", sequence)
    expected_count = count_exact_overlapping(sequence, pattern)

    serial = require_serial()

    print(f"uart_port={args.port}")
    print(f"baud={args.baud}")
    print()

    with serial.Serial(args.port, args.baud, timeout=args.timeout, write_timeout=args.timeout) as ser:
        drain_startup(ser)

        ping_reply = send_command(ser, "PING", "PING")
        test_ping = ping_reply == "PONG"

        setpat_reply = send_command(ser, f"SETPAT {pattern}", "SETPAT")
        test_setpat = setpat_reply == "OK"

        count_reply = send_command(ser, f"COUNT {sequence}", "COUNT")
        fpga_count = parse_count(count_reply)

        invalid_order_reply = send_command(ser, "STREAM ACGT", "STREAM invalid order")
        test_stream_invalid_order = invalid_order_reply == "ERR NOT_STREAMING"

        stream_single_sequence = DEFAULT_SEQUENCE
        stream_single_count = run_stream_count(ser, pattern, [stream_single_sequence])
        expected_stream_single = count_exact_overlapping(stream_single_sequence, pattern)
        test_stream_single = stream_single_count == expected_stream_single

        stream_cross_chunks = ["ACGT", "ACGT"]
        stream_cross_sequence = "".join(stream_cross_chunks)
        stream_cross_count = run_stream_count(ser, pattern, stream_cross_chunks)
        expected_stream_cross = count_exact_overlapping(stream_cross_sequence, pattern)
        test_stream_cross = stream_cross_count == expected_stream_cross

        stream_multi_chunks = ["ACGT", "ACGT", "ACGT", "ACGT"]
        stream_multi_sequence = "".join(stream_multi_chunks)
        stream_multi_count = run_stream_count(ser, pattern, stream_multi_chunks)
        expected_stream_multi = count_exact_overlapping(stream_multi_sequence, pattern)
        test_stream_multi = stream_multi_count == expected_stream_multi

        stream_short_chunks = ["ACGT"]
        stream_short_sequence = "".join(stream_short_chunks)
        stream_short_count = run_stream_count(ser, pattern, stream_short_chunks)
        expected_stream_short = count_exact_overlapping(stream_short_sequence, pattern)
        test_stream_short = stream_short_count == expected_stream_short

        quiet_cross_count = run_quiet_stream_count(ser, pattern, stream_cross_chunks)
        test_quiet_cross = quiet_cross_count == expected_stream_cross

    correct = fpga_count == expected_count

    print(f"test_ping={str(test_ping).lower()}")
    print(f"test_setpat={str(test_setpat).lower()}")
    print(f"pattern={pattern}")
    print(f"sequence={sequence}")
    print(f"expected_count={expected_count}")
    print(f"fpga_count={fpga_count}")
    print(f"correct={str(correct).lower()}")
    print(f"stream_single_chunk_count={stream_single_count}")
    print(f"stream_single_chunk_correct={str(test_stream_single).lower()}")
    print(f"stream_cross_boundary_count={stream_cross_count}")
    print(f"stream_cross_boundary_correct={str(test_stream_cross).lower()}")
    print(f"stream_multi_chunk_count={stream_multi_count}")
    print(f"stream_multi_chunk_correct={str(test_stream_multi).lower()}")
    print(f"stream_shorter_than_k_count={stream_short_count}")
    print(f"stream_shorter_than_k_correct={str(test_stream_short).lower()}")
    print(f"stream_invalid_order={str(test_stream_invalid_order).lower()}")
    print(f"quiet_stream_cross_boundary_count={quiet_cross_count}")
    print(f"quiet_stream_cross_boundary_correct={str(test_quiet_cross).lower()}")
    print()

    passed = (
        test_ping and test_setpat and correct and
        test_stream_invalid_order and test_stream_single and test_stream_cross and
        test_stream_multi and test_stream_short and test_quiet_cross
    )
    print(f"RESULT {'PASS' if passed else 'FAIL'}")
    return 0 if passed else 1


def build_parser():
    parser = argparse.ArgumentParser(description="Run deterministic FPGA UART bioinformatics regression test")
    parser.add_argument("--port", default="/dev/ttyUSB1")
    parser.add_argument("--baud", type=int, default=115200)
    parser.add_argument("--timeout", type=float, default=2.0)
    return parser


def main() -> None:
    try:
        sys.exit(run(build_parser().parse_args()))
    except Exception as exc:
        print(f"RESULT FAIL", file=sys.stderr)
        print(f"error={exc}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
