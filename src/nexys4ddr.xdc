# This file is specific for the Nexys 4 DDR board.

# Clock and reset
set_property -dict { PACKAGE_PIN E3  IOSTANDARD LVCMOS33 } [get_ports { clk_i    }];    # CLK100MHZ
set_property -dict { PACKAGE_PIN C12 IOSTANDARD LVCMOS33 } [get_ports { rstn_i   }];    # CPU_RESETN

# LEDs
set_property -dict { PACKAGE_PIN H17 IOSTANDARD LVCMOS33 } [get_ports { valid_o  }];    # LED0
set_property -dict { PACKAGE_PIN K15 IOSTANDARD LVCMOS33 } [get_ports { done_o  }];     # LED1

# UART
set_property -dict { PACKAGE_PIN C4  IOSTANDARD LVCMOS33 } [get_ports { uart_txd_i }];  # uart_txd_in
set_property -dict { PACKAGE_PIN D4  IOSTANDARD LVCMOS33 } [get_ports { uart_rxd_o }];  # uart_rxd_out

# Clock definition
create_clock -name sys_clk -period 10.00 [get_ports {clk_i}];

# Keep the search in a small rectangle of 16 x 20 slices, to make the routes short.
# For (9, 3, 2) the search uses about 960 LUTs, which is about three quarters of
# the LUTs in the rectangle. For larger parameters, the rectangle may have to be
# larger. This raises the maximum clock frequency by about 2%, see ALGORITHM.md.
create_pblock pb_steiner
add_cells_to_pblock [get_pblocks pb_steiner] [get_cells steiner_inst]
resize_pblock [get_pblocks pb_steiner] -add SLICE_X36Y125:SLICE_X51Y144

# Configuration Bank Voltage Select
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]

