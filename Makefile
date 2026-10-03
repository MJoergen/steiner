XILINX_DIR = /opt/Xilinx/2025.1/Vivado
# src/ holds the sources of the bitstream, sim/ the testbenches. Everything is built
# in this directory.
SRC  = src/steiner_pkg.vhd
SRC += src/valid.vhd
SRC += src/steiner.vhd
SRC += src/steiner2uart.vhd
SRC += src/uart.vhd
SRC += src/display.vhd
TOP = nexys4ddr

# Sources that are only synthesized, because they use Xilinx primitives
BOARD_SRC = src/clk_rst.vhd

TB = steiner_tb
TEXT_TB = steiner2uart_tb

# Search parameters for simulation
T = 2
K = 3
N = 9

# Admissible parameter sets that "make check" compares with steiner_ref.py, both the
# solutions and the text from steiner2uart.vhd
CHECK = 1_2_4 1_2_6 1_3_6 2_3_7 1_2_8 1_4_8 3_4_8 1_3_9 2_3_9 1_2_10 1_5_10

# Clock divisors that "make uart" simulates uart.vhd with
UART_DIVISORS = 2 5 16 17

.PHONY: help sim check uart display show formal vivado clean

help:
	@echo "Supported targets:"
	@echo "  make help        Show this help text (default)"
	@echo "  make sim         Simulate the design using GHDL, writing $(TB).ghw"
	@echo "                   and checking each solution"
	@echo "  make check       Simulate the design for each parameter set in CHECK, and"
	@echo "                   compare the solutions and the text from steiner2uart.vhd"
	@echo "                   with steiner_ref.py"
	@echo "  make uart        Simulate uart.vhd using GHDL for each clock divisor in"
	@echo "                   UART_DIVISORS"
	@echo "  make display     Simulate display.vhd using GHDL"
	@echo "  make show        Show the simulation waveform using GTKWave"
	@echo "  make formal      Run formal verification using SymbiYosys"
	@echo "  make vivado      Synthesize the design using Vivado, writing $(TOP).bit"
	@echo "  make clean       Remove the generated files"

sim:
	ghdl -a --std=08 $(SRC) sim/$(TB).vhd
	ghdl -e --std=08 $(TB)
	ghdl -r --std=08 $(TB) -gG_T=$(T) -gG_K=$(K) -gG_N=$(N) \
		--assert-level=error --wave=$(TB).ghw

# Compares each parameter set in CHECK with steiner_ref.py, see sim/check.sh
check:
	ghdl -a --std=08 $(SRC) sim/$(TB).vhd sim/$(TEXT_TB).vhd
	ghdl -e --std=08 $(TB)
	ghdl -e --std=08 $(TEXT_TB)
	@for p in $(CHECK); do \
	  sim/check.sh $$(echo $$p | tr _ ' ') || exit 1; \
	done
	@echo "All solutions and texts match steiner_ref.py"

uart:
	ghdl -a --std=08 src/uart.vhd sim/uart_tb.vhd
	ghdl -e --std=08 uart_tb
	@for g in $(UART_DIVISORS); do \
	  ghdl -r --std=08 uart_tb -gG_DIVISOR=$$g --assert-level=error || exit 1; \
	done

display:
	ghdl -a --std=08 src/display.vhd sim/display_tb.vhd
	ghdl -e --std=08 display_tb
	ghdl -r --std=08 display_tb --assert-level=error

show:
	gtkwave $(TB).ghw sim/$(TB).gtkw

formal:
	$(MAKE) -C formal


################################################
## Synthesis using Vivado
################################################

vivado: $(TOP).bit

$(TOP).bit: $(TOP).tcl $(SRC) $(BOARD_SRC) src/$(TOP).vhd src/$(TOP).xdc
	bash -c "source $(XILINX_DIR)/settings64.sh ; vivado -mode batch -source $<"

$(TOP).tcl: Makefile
	echo "# This is a tcl command script for the Vivado tool chain" > $@
	echo "read_vhdl -vhdl2008 { $(SRC) $(BOARD_SRC) src/$(TOP).vhd }" >> $@
	echo "read_xdc src/$(TOP).xdc" >> $@
	echo "synth_design -top $(TOP) -part xc7a100tcsg324-1 -flatten_hierarchy rebuilt -assert" >> $@
	echo "write_checkpoint -force post_synth.dcp" >> $@
	echo "opt_design" >> $@
	echo "place_design -directive ExtraTimingOpt" >> $@
	echo "phys_opt_design -directive AggressiveExplore" >> $@
	echo "route_design -directive AggressiveExplore" >> $@
	echo "phys_opt_design -directive AggressiveExplore" >> $@
	echo "write_checkpoint -force post_route.dcp" >> $@
	echo "report_timing_summary -file $(TOP)_timing.rpt" >> $@
	echo "if {[get_property SLACK [get_timing_paths -setup]] < 0 || [get_property SLACK [get_timing_paths -hold]] < 0} {" >> $@
	echo "  puts {ERROR: Timing constraints not met. See $(TOP)_timing.rpt}" >> $@
	echo "  exit 1" >> $@
	echo "}" >> $@
	echo "write_bitstream -force $(TOP).bit" >> $@
	echo "exit" >> $@


################################################
## Generated files
################################################

clean:
	rm -f *.cf *.o *.ghw $(TB) $(TB).txt $(TEXT_TB) $(TEXT_TB).txt check_* uart_tb display_tb
	rm -rf .Xil
	rm -f $(TOP).tcl $(TOP).bit *.dcp *.rpt *.jou *.log
	rm -f clockInfo.txt tight_setup_hold_pins.txt usage_statistics_webtalk.*
	$(MAKE) -C formal clean
