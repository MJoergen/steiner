XILINX_DIR = /opt/Xilinx/Vivado/2021.2
SRC  = valid.vhd
SRC += steiner.vhd
TOP = steiner

TB = steiner_tb

all:
	ghdl -a --std=08 $(SRC) $(TB).vhd
	ghdl -r --std=08 $(TB) --stop-time=10000ms --wave=$(TB).ghw

show:
	gtkwave $(TB).ghw $(TB).gtkw


################################################
## Synthesis using Vivado
################################################

$(TOP).bit: $(TOP).tcl $(SRC) $(TOP).xdc
	bash -c "source $(XILINX_DIR)/settings64.sh ; vivado -mode tcl -source $<"

$(TOP).tcl: Makefile
	echo "# This is a tcl command script for the Vivado tool chain" > $@
	echo "read_vhdl -vhdl2008 { $(SRC) }" >> $@
	echo "read_xdc $(TOP).xdc" >> $@
	echo "synth_design -top $(TOP) -part xc7a100tcsg324-1 -flatten_hierarchy none" >> $@
	echo "write_checkpoint -force post_synth.dcp" >> $@
	echo "opt_design" >> $@
	echo "place_design" >> $@
	echo "phys_opt_design" >> $@
	echo "route_design" >> $@
	echo "write_checkpoint -force post_route.dcp" >> $@
	echo "write_bitstream -force $(TOP).bit" >> $@
	echo "exit" >> $@

