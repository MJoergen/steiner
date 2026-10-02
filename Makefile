XILINX_DIR = /opt/Xilinx/2025.1/Vivado
SRC  = steiner_pkg.vhd
SRC += valid.vhd
SRC += steiner.vhd
SRC += uart.vhd
TOP = nexys4ddr

TB = steiner_tb

# Search parameters for simulation
N = 9
K = 3
T = 2

# Admissible parameter sets that "make check" compares with steiner_ref.py
CHECK = 4_2_1 6_2_1 6_3_1 7_3_2 8_2_1 8_4_1 8_4_3 9_3_1 9_3_2 10_2_1 10_5_1

# Clock divisors that "make uart" simulates uart.vhd with
UART_DIVISORS = 2 5 16 17

.PHONY: help sim check uart show formal vivado clean

help:
	@echo "Supported targets:"
	@echo "  make help        Show this help text (default)"
	@echo "  make sim         Simulate the design using GHDL, writing $(TB).ghw"
	@echo "                   and checking each solution"
	@echo "  make check       Simulate the design for each parameter set in CHECK, and"
	@echo "                   compare the solutions with steiner_ref.py"
	@echo "  make uart        Simulate uart.vhd using GHDL for each clock divisor in"
	@echo "                   UART_DIVISORS"
	@echo "  make show        Show the simulation waveform using GTKWave"
	@echo "  make formal      Run formal verification using SymbiYosys"
	@echo "  make vivado      Synthesize the design using Vivado, writing $(TOP).bit"
	@echo "  make clean       Remove the generated files"

sim:
	ghdl -a --std=08 $(SRC) $(TB).vhd
	ghdl -e --std=08 $(TB)
	ghdl -r --std=08 $(TB) -gG_N=$(N) -gG_K=$(K) -gG_T=$(T) \
		--assert-level=error --wave=$(TB).ghw

# The solutions must be exactly those of the reference model, in the same order,
# and those in the results file, if there is one
check:
	ghdl -a --std=08 $(SRC) $(TB).vhd
	ghdl -e --std=08 $(TB)
	@for p in $(CHECK); do \
	  set -- $$(echo $$p | tr _ ' '); \
	  echo "Checking (n, k, t) = ($$1, $$2, $$3)"; \
	  ghdl -r --std=08 $(TB) -gG_N=$$1 -gG_K=$$2 -gG_T=$$3 -gG_OUTPUT=check_$$p.txt \
	    --assert-level=error > check_$$p.log 2>&1 || { tail -5 check_$$p.log; exit 1; }; \
	  python3 steiner_ref.py $$1 $$2 $$3 > check_$$p.ref; \
	  diff check_$$p.txt check_$$p.ref > /dev/null || \
	    { echo "The solutions differ from steiner_ref.py"; exit 1; }; \
	  if [ -f result_$$p.txt ]; then \
	    diff check_$$p.txt result_$$p.txt > /dev/null || \
	      { echo "The solutions differ from result_$$p.txt"; exit 1; }; \
	  fi; \
	done
	@echo "All solutions match steiner_ref.py"

uart:
	ghdl -a --std=08 uart.vhd uart_tb.vhd
	ghdl -e --std=08 uart_tb
	@for g in $(UART_DIVISORS); do \
	  ghdl -r --std=08 uart_tb -gG_DIVISOR=$$g --assert-level=error || exit 1; \
	done

show:
	gtkwave $(TB).ghw $(TB).gtkw

formal:
	$(MAKE) -C formal


################################################
## Synthesis using Vivado
################################################

vivado: $(TOP).bit

$(TOP).bit: $(TOP).tcl $(SRC) $(TOP).vhd $(TOP).xdc
	bash -c "source $(XILINX_DIR)/settings64.sh ; vivado -mode batch -source $<"

$(TOP).tcl: Makefile
	echo "# This is a tcl command script for the Vivado tool chain" > $@
	echo "read_vhdl -vhdl2008 { $(SRC) $(TOP).vhd }" >> $@
	echo "read_xdc $(TOP).xdc" >> $@
	echo "synth_design -top $(TOP) -part xc7a100tcsg324-1 -flatten_hierarchy rebuilt -assert" >> $@
	echo "write_checkpoint -force post_synth.dcp" >> $@
	echo "opt_design" >> $@
	echo "place_design -directive ExtraTimingOpt" >> $@
	echo "phys_opt_design -directive AggressiveExplore" >> $@
	echo "route_design -directive AggressiveExplore" >> $@
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
	rm -f *.cf *.o *.ghw $(TB) $(TB).txt check_* uart_tb
	rm -rf .Xil
	rm -f $(TOP).tcl $(TOP).bit *.dcp *.rpt *.jou *.log
	rm -f clockInfo.txt tight_setup_hold_pins.txt usage_statistics_webtalk.*
	$(MAKE) -C formal clean
