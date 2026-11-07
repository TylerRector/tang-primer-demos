# Tang Primer Demos

FPGA demos for the Sipeed Tang Primer 20K with Dock board.

- [`demos/blink.v`](demos/blink.v): standalone 1 Hz LED blink.
- [`demos/dna_count.v`](demos/dna_count.v): UART DNA pattern counting with a heartbeat LED.
- `src/`: supporting HDL and experimental renderer modules.
- `tooling/`: Gowin build script and Python UART, benchmark, and frame utilities.
- `sim/`: simulation testbenches.

## Build and run

Requires Gowin EDA (`gowin_sh` on `PATH`), openFPGALoader for programming,
and Icarus Verilog for simulation. Python serial utilities require `pyserial`.

```sh
make sim-all
make build DEMO=blink
make program DEMO=blink
make build DEMO=dna_count
make program DEMO=dna_count
```

`DEMO` defaults to `dna_count`. Bitstreams are written to
`build/<demo>/<demo>/impl/pnr/<demo>.fs`.
Connect the Dock JTAG/UART USB-C port. Pin assignments are in `constraints/`.

The DNA demo accepts newline-terminated UART commands at 115200 baud, 8N1:

```text
SETPAT ACGTACGT
COUNT ACGTACGTACGTACGT
```

The count reply is `COUNT 3` (overlapping matches). Patterns must contain exactly
eight uppercase A/C/G/T bases. `PING`, `VERSION`, and streaming counts are also supported.

```sh
python3 tooling/bio_uart_host.py --port /dev/ttyUSB1 count --pattern ACGTACGT --sequence ACGTACGTACGTACGT
```
