PROJECT := blink
BITSTREAM := build/$(PROJECT)/impl/pnr/$(PROJECT).fs
BOARD ?= tangprimer20k
GOWIN_HEADLESS_ENV := QT_QPA_PLATFORM=minimal QT_QUICK_BACKEND=software LIBGL_ALWAYS_SOFTWARE=1
GOWIN_PROG ?= $(HOME)/gowin/Programmer/bin/programmer_cli
GOWIN_PROG_LIB ?= $(HOME)/gowin/Programmer/bin:$(HOME)/gowin/Programmer/lib
GOWIN_DEVICE ?= GW2A-18C
GOWIN_CABLE_INDEX ?= 5
GOWIN_LOCATION ?= 49
GOWIN_FREQ ?= 2.5MHz
HDL_SRCS := \
	src/top.v \
	src/uart_tx.v \
	src/uart_rx.v \
	src/command_parser.v \
	src/response_formatter.v \
	src/dna_ascii_to_2bit.v \
	src/kmer_shift_register.v \
	src/exact_match_counter.v \
	src/status_leds.v \
	src/video_timing.v \
	src/sphere_intersect.v \
	src/render_core.v \
	src/debug_overlay.v

PORT ?= /dev/ttyUSB1
BAUD ?= 115200

.PHONY: all build build-uart-smoke check-uart-pin program program-sram-low program-gowin program-gowin-verify program-gowin-status program-gowin-erase program-uart-smoke flash clean detect uart-discover uart-smoke-test sim sim-uart sim-kmer sim-parser sim-video sim-render-small bio-test sim-all bio-hw-test bio-bench bio-bench-stream bio-bench-stream-sweep bio-bench-stream-quiet bench-small

all: build

check-uart-pin:
	@if grep -q 'IO_LOC "UART_TX" <PIN>' constraints/tang_primer_20k_dock.cst; then \
		echo "UART_TX pin is still TODO in constraints/tang_primer_20k_dock.cst."; \
		echo "Fill in the official Tang Primer 20K Dock FPGA-to-USB-UART TX pin before hardware build/program."; \
		exit 1; \
	fi

build: check-uart-pin
	rm -rf build
	$(GOWIN_HEADLESS_ENV) bash -lc 'gowin_sh build.tcl'

build-uart-smoke: check-uart-pin
	rm -rf build
	UART_SMOKE=1 $(GOWIN_HEADLESS_ENV) bash -lc 'gowin_sh build.tcl'

program: build
	openFPGALoader -b $(BOARD) $(BITSTREAM)

program-sram-low:
	openFPGALoader -b $(BOARD) --freq 1000000 --reset $(BITSTREAM)

program-gowin:
	LD_LIBRARY_PATH=$(GOWIN_PROG_LIB) $(GOWIN_PROG) --cable-index $(GOWIN_CABLE_INDEX) --location $(GOWIN_LOCATION) -d $(GOWIN_DEVICE) --freq $(GOWIN_FREQ) -f $(abspath $(BITSTREAM)) -r 2

program-gowin-verify:
	LD_LIBRARY_PATH=$(GOWIN_PROG_LIB) $(GOWIN_PROG) --cable-index $(GOWIN_CABLE_INDEX) --location $(GOWIN_LOCATION) -d $(GOWIN_DEVICE) --freq $(GOWIN_FREQ) -f $(abspath $(BITSTREAM)) -r 4

program-gowin-status:
	LD_LIBRARY_PATH=$(GOWIN_PROG_LIB) $(GOWIN_PROG) --cable-index $(GOWIN_CABLE_INDEX) --location $(GOWIN_LOCATION) -d $(GOWIN_DEVICE) --freq $(GOWIN_FREQ) -r 74

program-gowin-erase:
	LD_LIBRARY_PATH=$(GOWIN_PROG_LIB) $(GOWIN_PROG) --cable-index $(GOWIN_CABLE_INDEX) --location $(GOWIN_LOCATION) -d $(GOWIN_DEVICE) --freq $(GOWIN_FREQ) -r 24

program-uart-smoke: build-uart-smoke program-sram-low

detect:
	openFPGALoader --detect

uart-discover:
	python3 host/uart_discover.py --timeout 1.5

uart-smoke-test:
	python3 host/uart_discover.py --ports $(PORT) --baud $(BAUD) --timeout 1.5 --render-controls

flash:
	@if [ "$(CONFIRM_FLASH)" != "1" ]; then \
		echo "Refusing to flash permanently."; \
		echo "Use: make flash CONFIRM_FLASH=1"; \
		exit 1; \
	fi
	$(MAKE) build
	openFPGALoader -b $(BOARD) --write-flash $(BITSTREAM)

clean:
	rm -rf build

sim:
	@command -v iverilog >/dev/null 2>&1 || { \
		echo "iverilog is not installed; install it to run make sim."; \
		exit 1; \
	}
	mkdir -p build/sim
	iverilog -g2012 -I src -o build/sim/top_tb.vvp sim/top_tb.v $(HDL_SRCS)
	vvp build/sim/top_tb.vvp

sim-uart:
	@command -v iverilog >/dev/null 2>&1 || { \
		echo "iverilog is not installed; install it to run make sim-uart."; \
		exit 1; \
	}
	mkdir -p build/sim
	iverilog -g2012 -o build/sim/tb_uart_rx.vvp sim/tb_uart_rx.v src/uart_rx.v
	vvp build/sim/tb_uart_rx.vvp

sim-kmer:
	@command -v iverilog >/dev/null 2>&1 || { \
		echo "iverilog is not installed; install it to run make sim-kmer."; \
		exit 1; \
	}
	mkdir -p build/sim
	iverilog -g2012 -o build/sim/tb_dna_ascii_to_2bit.vvp sim/tb_dna_ascii_to_2bit.v src/dna_ascii_to_2bit.v
	vvp build/sim/tb_dna_ascii_to_2bit.vvp
	iverilog -g2012 -o build/sim/tb_kmer_shift_register.vvp sim/tb_kmer_shift_register.v src/kmer_shift_register.v
	vvp build/sim/tb_kmer_shift_register.vvp
	iverilog -g2012 -o build/sim/tb_exact_match_counter.vvp sim/tb_exact_match_counter.v src/kmer_shift_register.v src/exact_match_counter.v
	vvp build/sim/tb_exact_match_counter.vvp
	iverilog -g2012 -o build/sim/tb_streaming_counter.vvp sim/tb_streaming_counter.v src/kmer_shift_register.v src/exact_match_counter.v
	vvp build/sim/tb_streaming_counter.vvp

sim-parser:
	@command -v iverilog >/dev/null 2>&1 || { \
		echo "iverilog is not installed; install it to run make sim-parser."; \
		exit 1; \
	}
	mkdir -p build/sim
	iverilog -g2012 -o build/sim/tb_command_parser.vvp sim/tb_command_parser.v src/command_parser.v
	vvp build/sim/tb_command_parser.vvp
	iverilog -g2012 -o build/sim/tb_response_formatter.vvp sim/tb_response_formatter.v src/response_formatter.v
	vvp build/sim/tb_response_formatter.vvp
	iverilog -g2012 -o build/sim/tb_status_leds.vvp sim/tb_status_leds.v src/status_leds.v
	vvp build/sim/tb_status_leds.vvp

sim-video:
	@command -v iverilog >/dev/null 2>&1 || { \
		echo "iverilog is not installed; install it to run make sim-video."; \
		exit 1; \
	}
	mkdir -p build/sim
	iverilog -g2012 -o build/sim/tb_video_timing.vvp sim/tb_video_timing.v src/video_timing.v
	vvp build/sim/tb_video_timing.vvp

sim-render-small:
	@command -v iverilog >/dev/null 2>&1 || { \
		echo "iverilog is not installed; install it to run make sim-render-small."; \
		exit 1; \
	}
	mkdir -p build/sim results/frames
	iverilog -g2012 -I src -o build/sim/tb_sphere_intersect.vvp sim/tb_sphere_intersect.v src/sphere_intersect.v
	vvp build/sim/tb_sphere_intersect.vvp
	iverilog -g2012 -I src -o build/sim/tb_render_core_small.vvp sim/tb_render_core_small.v src/render_core.v src/sphere_intersect.v
	vvp build/sim/tb_render_core_small.vvp

sim-all: sim-uart sim-kmer sim-parser sim-video sim-render-small sim

bio-test:
	python3 host/bio_uart_test.py --port $(PORT) --baud $(BAUD)

bio-hw-test: bio-test

bio-bench:
	python3 host/benchmark_kmer_uart.py --port /dev/ttyUSB1 --baud 115200 --csv results/kmer_uart_benchmark.csv

bio-bench-stream:
	python3 host/benchmark_kmer_uart.py --port /dev/ttyUSB1 --baud 115200 --mode stream --chunk-size 64 --lengths 128,256,512,1024,4096,16384,65536 --csv results/kmer_uart_stream_benchmark.csv

bio-bench-stream-sweep:
	python3 host/benchmark_kmer_uart.py --port /dev/ttyUSB1 --baud 115200 --mode stream --lengths 4096,16384,65536 --chunk-sizes 16,32,48,64,80,96,112 --csv results/kmer_uart_stream_chunk_sweep.csv

bio-bench-stream-quiet:
	python3 host/benchmark_kmer_uart.py --port /dev/ttyUSB1 --baud 115200 --mode stream --ack-mode quiet --chunk-size 112 --lengths 4096,16384,65536 --csv results/kmer_uart_stream_quiet_benchmark.csv

bench-small:
	python3 tools/bio_uart_host.py --port /dev/ttyUSB1 count --pattern ACGTACGT --sequence ACGTACGTACGTACGT
