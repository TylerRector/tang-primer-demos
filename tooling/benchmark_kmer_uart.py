#!/usr/bin/env python3
import argparse
import csv
import os
import sys
import time
from datetime import datetime, timezone


DEFAULT_LENGTHS = "16,32,64,128,256,512,1024"
DEFAULT_PATTERN = "ACGTACGT"
DEFAULT_MAX_COMMAND_BYTES = 128
FPGA_CLK_HZ = 27_000_000


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


def cpu_naive_timed(sequence: str, pattern: str):
    start = time.perf_counter()
    count = count_exact_overlapping(sequence, pattern)
    elapsed = time.perf_counter() - start
    return count, elapsed


def validate_dna(label: str, value: str) -> None:
    invalid = sorted(set(ch for ch in value if ch not in "ACGT"))
    if invalid:
        raise ValueError(f"{label} contains invalid DNA characters: {''.join(invalid)}")


def deterministic_sequence(length: int) -> str:
    return ("ACGT" * ((length + 3) // 4))[:length]


def parse_lengths(value: str):
    lengths = []
    for item in value.split(","):
        item = item.strip()
        if not item:
            continue
        length = int(item)
        if length <= 0:
            raise ValueError("lengths must be positive")
        lengths.append(length)
    if not lengths:
        raise ValueError("at least one length is required")
    return lengths


def parse_positive_ints(value: str, label: str):
    parsed = []
    for item in value.split(","):
        item = item.strip()
        if not item:
            continue
        number = int(item)
        if number <= 0:
            raise ValueError(f"{label} must contain positive integers")
        parsed.append(number)
    if not parsed:
        raise ValueError(f"at least one {label} value is required")
    return parsed


def drain_startup(ser) -> None:
    deadline = time.time() + 0.25
    while time.time() < deadline:
        waiting = getattr(ser, "in_waiting", 0)
        if waiting:
            ser.read(waiting)
            deadline = time.time() + 0.05
        else:
            time.sleep(0.01)


def send_command(ser, command: str) -> str:
    ser.write((command + "\n").encode("ascii"))
    ser.flush()
    reply = ser.readline().decode("ascii", errors="replace").strip()
    if not reply:
        raise TimeoutError(f"timeout waiting for response to {command.split()[0]}")
    return reply


def maybe_pace(args):
    if args.command_delay > 0:
        time.sleep(args.command_delay)


def parse_count_reply(reply: str) -> int:
    parts = reply.split()
    if len(parts) != 2 or parts[0] != "COUNT":
        raise ValueError(f"expected COUNT reply, got: {reply}")
    return int(parts[1])


def format_float(value):
    if value is None:
        return ""
    return f"{value:.9f}"


def build_row(args, length: int, chunk_size, num_chunks, expected_count: int, fpga_count, correct, cpu_seconds,
              fpga_seconds, upload_seconds, response_seconds, compute_seconds, notes: str):
    compute_speedup = None
    end_to_end_speedup = None
    if cpu_seconds is not None and compute_seconds and compute_seconds > 0:
        compute_speedup = cpu_seconds / compute_seconds
    if cpu_seconds is not None and fpga_seconds and fpga_seconds > 0:
        end_to_end_speedup = cpu_seconds / fpga_seconds

    return {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "port": args.port,
        "baud": args.baud,
        "mode": args.mode,
        "ack_mode": args.ack_mode if args.mode == "stream" else "",
        "chunk_size": chunk_size if args.mode == "stream" else "",
        "num_chunks": num_chunks if args.mode == "stream" else "",
        "pattern": args.pattern,
        "sequence_length": length,
        "expected_count": expected_count,
        "fpga_count": "" if fpga_count is None else fpga_count,
        "correct": "" if correct is None else str(correct).lower(),
        "cpu_naive_seconds": format_float(cpu_seconds),
        "fpga_end_to_end_seconds": format_float(fpga_seconds),
        "estimated_uart_upload_seconds": format_float(upload_seconds),
        "estimated_uart_response_seconds": format_float(response_seconds),
        "estimated_fpga_compute_seconds": format_float(compute_seconds),
        "effective_e2e_bases_per_second": format_float((length / fpga_seconds) if fpga_seconds and fpga_seconds > 0 else None),
        "speedup_compute_only_vs_cpu_naive": format_float(compute_speedup),
        "speedup_end_to_end_vs_cpu_naive": format_float(end_to_end_speedup),
        "notes": notes,
    }


def run(args) -> int:
    args.pattern = args.pattern.upper()
    validate_dna("pattern", args.pattern)
    if len(args.pattern) != 8:
        raise ValueError("pattern must be exactly 8 A/C/G/T bases for the current FPGA image")
    if args.chunk_size <= 0:
        raise ValueError("chunk size must be positive")
    chunk_sizes = parse_positive_ints(args.chunk_sizes, "chunk-sizes") if args.chunk_sizes else [args.chunk_size]

    lengths = parse_lengths(args.lengths)
    serial = require_serial()
    uart_byte_rate = args.baud / 10.0

    os.makedirs(os.path.dirname(args.csv) or ".", exist_ok=True)
    fieldnames = [
        "timestamp",
        "port",
        "baud",
        "mode",
        "ack_mode",
        "chunk_size",
        "num_chunks",
        "pattern",
        "sequence_length",
        "expected_count",
        "fpga_count",
        "correct",
        "cpu_naive_seconds",
        "fpga_end_to_end_seconds",
        "estimated_uart_upload_seconds",
        "estimated_uart_response_seconds",
        "estimated_fpga_compute_seconds",
        "effective_e2e_bases_per_second",
        "speedup_compute_only_vs_cpu_naive",
        "speedup_end_to_end_vs_cpu_naive",
        "notes",
    ]

    rows = []
    failures = 0
    with serial.Serial(args.port, args.baud, timeout=args.timeout, write_timeout=args.timeout) as ser:
        drain_startup(ser)
        setpat_reply = send_command(ser, f"SETPAT {args.pattern}")
        if setpat_reply != "OK":
            raise RuntimeError(f"SETPAT failed before benchmark: {setpat_reply}")

        for length in lengths:
            for active_chunk_size in ([""] if args.mode == "count" else chunk_sizes):
                sequence = deterministic_sequence(length)
                validate_dna("sequence", sequence)
                expected_count, cpu_seconds = cpu_naive_timed(sequence, args.pattern)

                if args.mode == "count":
                    count_command = f"COUNT {sequence}"
                    command_bytes = len(count_command) + 1
                    if command_bytes > args.max_command_bytes:
                        note = f"skipped: COUNT command is {command_bytes} bytes, parser limit is {args.max_command_bytes}"
                        rows.append(build_row(
                            args, length, "", "", expected_count, None, None, cpu_seconds, None,
                            None, None, None, note,
                        ))
                        print(f"length={length} skipped notes=\"{note}\"")
                        continue

                    start = time.perf_counter()
                    reply = send_command(ser, count_command)
                    maybe_pace(args)
                    fpga_seconds = time.perf_counter() - start
                    upload_command_bytes = command_bytes
                    response_count = 1
                    num_chunks = ""
                else:
                    chunks = [sequence[index:index + active_chunk_size] for index in range(0, len(sequence), active_chunk_size)]
                    begin_command = "STREAM_BEGIN_QUIET" if args.ack_mode == "quiet" else "STREAM_BEGIN"
                    stream_commands = [begin_command] + [f"STREAM {chunk}" for chunk in chunks] + ["STREAM_END"]
                    too_large = [cmd for cmd in stream_commands if len(cmd) + 1 > args.max_command_bytes]
                    if too_large:
                        note = f"parser limit: stream chunk command exceeds parser limit {args.max_command_bytes}"
                        rows.append(build_row(
                            args, length, active_chunk_size, len(chunks), expected_count, None, None, cpu_seconds, None,
                            None, None, None, note,
                        ))
                        print(f"length={length} chunk_size={active_chunk_size} skipped notes=\"{note}\"")
                        continue

                    start = time.perf_counter()
                    try:
                        if args.ack_mode == "ack":
                            for command in stream_commands[:-1]:
                                stream_reply = send_command(ser, command)
                                maybe_pace(args)
                                if stream_reply != "OK":
                                    raise RuntimeError(f"{command.split()[0]} failed: {stream_reply}")
                        else:
                            begin_reply = send_command(ser, begin_command)
                            maybe_pace(args)
                            if begin_reply != "OK":
                                raise RuntimeError(f"{begin_command} failed: {begin_reply}")
                            for command in stream_commands[1:-1]:
                                ser.write((command + "\n").encode("ascii"))
                                ser.flush()
                                maybe_pace(args)
                        reply = send_command(ser, stream_commands[-1])
                        maybe_pace(args)
                    except Exception as exc:
                        failures += 1
                        fpga_seconds = time.perf_counter() - start
                        upload_command_bytes = sum(len(command) + 1 for command in stream_commands)
                        response_count = len(stream_commands) if args.ack_mode == "ack" else 2
                        response_bytes = len("ERR UNKNOWN_CMD\n")
                        upload_seconds = upload_command_bytes / uart_byte_rate
                        response_seconds = response_bytes / uart_byte_rate
                        compute_seconds = length / FPGA_CLK_HZ
                        rows.append(build_row(
                            args, length, active_chunk_size, len(chunks), expected_count, None, False,
                            cpu_seconds, fpga_seconds, upload_seconds, response_seconds, compute_seconds,
                            f"uart error: {exc}",
                        ))
                        print(f"length={length} chunk_size={active_chunk_size} correct=false notes=\"uart error: {exc}\"")
                        send_command(ser, "RESET")
                        setpat_reply = send_command(ser, f"SETPAT {args.pattern}")
                        if setpat_reply != "OK":
                            raise RuntimeError(f"SETPAT failed after reset: {setpat_reply}")
                        continue
                    fpga_seconds = time.perf_counter() - start
                    upload_command_bytes = sum(len(command) + 1 for command in stream_commands)
                    response_count = len(stream_commands) if args.ack_mode == "ack" else 2
                    num_chunks = len(chunks)

                fpga_count = parse_count_reply(reply)
                correct = fpga_count == expected_count
                if not correct:
                    failures += 1

                response_bytes = len(reply) + 1
                if args.mode == "stream":
                    response_bytes += (response_count - 1) * len("OK\n")
                upload_seconds = upload_command_bytes / uart_byte_rate
                response_seconds = response_bytes / uart_byte_rate
                compute_seconds = length / FPGA_CLK_HZ
                note = "pass" if correct else "wrong count"
                rows.append(build_row(
                    args, length, active_chunk_size, num_chunks, expected_count, fpga_count, correct, cpu_seconds, fpga_seconds,
                    upload_seconds, response_seconds, compute_seconds, note,
                ))
                chunk_text = f" chunk_size={active_chunk_size}" if args.mode == "stream" else ""
                print(
                    f"length={length}{chunk_text} expected={expected_count} fpga={fpga_count} "
                    f"correct={str(correct).lower()} cpu_s={cpu_seconds:.9f} fpga_e2e_s={fpga_seconds:.9f}"
                )

    with open(args.csv, "w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)

    print(f"csv={args.csv}")
    print("benchmark_note=End-to-end results include 115200 baud UART transfer and host overhead.")
    print("benchmark_note=Compute-only speedups are estimates and must not be interpreted as measured end-to-end acceleration.")
    return 0 if failures == 0 else 1


def build_parser():
    parser = argparse.ArgumentParser(description="Benchmark Tang Primer 20K UART ASCII k-mer COUNT path")
    parser.add_argument("--port", default="/dev/ttyUSB1")
    parser.add_argument("--baud", type=int, default=115200)
    parser.add_argument("--timeout", type=float, default=2.0)
    parser.add_argument("--pattern", default=DEFAULT_PATTERN)
    parser.add_argument("--lengths", default=DEFAULT_LENGTHS)
    parser.add_argument("--csv", default="results/kmer_uart_benchmark.csv")
    parser.add_argument("--max-command-bytes", type=int, default=DEFAULT_MAX_COMMAND_BYTES)
    parser.add_argument("--mode", choices=("count", "stream"), default="count")
    parser.add_argument("--chunk-size", type=int, default=64)
    parser.add_argument("--chunk-sizes", default="")
    parser.add_argument("--ack-mode", choices=("ack", "quiet"), default="ack")
    parser.add_argument("--command-delay", type=float, default=0.0)
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
