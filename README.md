# Tang Primer Demos

FPGA demos for the Sipeed Tang Primer 20K with Dock board.

- [`demos/blink.v`](demos/blink.v): standalone 1 Hz LED blink.
- [`demos/dna_count.v`](demos/dna_count.v): UART DNA pattern counting
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
