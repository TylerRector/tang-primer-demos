# Tang Primer 20K FPGA Demo

Verilog project for the Sipeed Tang Primer 20K with Dock board.
Includes a 1 Hz heartbeat LED, UART commands, DNA pattern counting,
and experimental rendering logic. The heartbeat drives `IO_voltage`.

## Build and run

Requires Gowin EDA (`gowin_sh` on `PATH`), Icarus Verilog for simulation,
and openFPGALoader for programming.

```sh
make sim-all       # Run simulations
make build         # Build the bitstream
make program       # Build and load into SRAM
```

Connect the Dock JTAG/UART USB-C port. Pin assignments are in
`constraints/tang_primer_20k_dock.cst`.
The bitstream is written to `build/blink/impl/pnr/blink.fs`.

## Source

- `src/status_leds.v`: heartbeat and activity LEDs.
- `src/top.v`: main design; UART runs at 115200 baud, 8N1.
- `src/`: UART, pattern counter, and experimental renderer modules.
- `sim/`: simulation testbenches.
- `host/` and `tools/`: Python utilities (serial tools require `pyserial`).

UART accepts newline-terminated commands such as `PING`, `VERSION`, and `STATUS`.
Rendering support is experimental; this project does not provide HDMI output.
