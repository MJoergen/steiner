SRC  = steiner.vhd
SRC += steiner_tb.vhd

TOP=steiner_tb

all:
	ghdl -a --std=08 $(SRC)
	ghdl -r --std=08 $(TOP) --stop-time=1ms --wave=$(TOP).ghw

show:
	gtkwave $(TOP).ghw $(TOP).gtkw

