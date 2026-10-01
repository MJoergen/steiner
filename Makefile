XILINX_DIR = /opt/Xilinx/2025.1/Vivado
SRC  = steiner_pkg.vhd
SRC += valid.vhd
SRC += steiner.vhd
TOP = nexys4ddr

TB = steiner_tb

# Search parameters for simulation
N = 9
K = 3
T = 2

.PHONY: help sim show formal vivado

help:
	@echo "Supported targets:"
	@echo "  make help        Show this help text (default)"
	@echo "  make sim         Simulate the design using GHDL, writing $(TB).ghw"
	@echo "                   and checking each solution"
	@echo "  make show        Show the simulation waveform using GTKWave"
	@echo "  make formal      Run formal verification using SymbiYosys"
	@echo "  make vivado      Synthesize the design using Vivado, writing $(TOP).bit"

sim:
	ghdl -a --std=08 $(SRC) $(TB).vhd
	ghdl -e --std=08 $(TB)
	ghdl -r --std=08 $(TB) -gG_N=$(N) -gG_K=$(K) -gG_T=$(T) \
		--assert-level=error --wave=$(TB).ghw

show:
	gtkwave $(TB).ghw $(TB).gtkw

formal:
	$(MAKE) -C formal


################################################
## Synthesis using Vivado
################################################

vivado: $(TOP).bit

$(TOP).bit: $(TOP).tcl $(SRC) $(TOP).vhd $(TOP).xdc
	bash -c "source $(XILINX_DIR)/settings64.sh ; vivado -mode tcl -source $<"

$(TOP).tcl: Makefile
	echo "# This is a tcl command script for the Vivado tool chain" > $@
	echo "read_vhdl -vhdl2008 { $(SRC) $(TOP).vhd }" >> $@
	echo "read_xdc $(TOP).xdc" >> $@
	echo "synth_design -top $(TOP) -part xc7a100tcsg324-1 -flatten_hierarchy rebuilt" >> $@
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

