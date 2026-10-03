-- This is the top level file for the Nexys 4 DDR board.
-- * It runs the search on a 190 MHz clock, with a synchronous reset from the reset
--   button, see clk_rst.vhd.
-- * It sends each solution as text over the UART, at 115200 baud with 8N1, see
--   steiner2uart.vhd. The search waits while the solutions are being sent. At the
--   end it sends the number of solutions.

library ieee;
  use ieee.std_logic_1164.all;
library work;
  use work.steiner_pkg.all;

entity nexys4ddr is
  port (
    clk_i      : in  std_logic;   -- 100 MHz
    rstn_i     : in  std_logic;   -- Active low (CPU_RESETN)
    valid_o    : out std_logic;
    done_o     : out std_logic;
    uart_txd_i : in  std_logic;
    uart_rxd_o : out std_logic
  );
end entity nexys4ddr;

architecture synthesis of nexys4ddr is

  constant C_T : natural := 2;
  constant C_K : natural := 3;
  constant C_N : natural := 9;

  -- The frequency of the clock from clk_rst.vhd
  constant C_CLK_SPEED_HZ : positive := 190_000_000;
  constant C_BAUDRATE     : positive := 115_200;

  signal clk : std_logic;   -- 190 MHz
  signal rst : std_logic;

  signal steiner_valid : std_logic;
  signal steiner_ready : std_logic;
  signal steiner_data  : std_logic_vector(0 to binom(C_N, C_T) / binom(C_K, C_T) * C_N - 1);
  signal steiner_done  : std_logic;

  signal uart_tx_valid : std_logic;
  signal uart_tx_ready : std_logic;
  signal uart_tx_data  : std_logic_vector(7 downto 0);

begin

  clk_rst_inst : entity work.clk_rst
    port map (
      clk_i  => clk_i,
      rstn_i => rstn_i,
      clk_o  => clk,
      rst_o  => rst
    ); -- clk_rst_inst

  steiner_inst : entity work.steiner
    generic map (
      G_N => C_N,
      G_K => C_K,
      G_T => C_T
    )
    port map (
      clk_i     => clk,
      rst_i     => rst,
      m_valid_o => steiner_valid,
      m_ready_i => steiner_ready,
      m_data_o  => steiner_data,
      done_o    => steiner_done
    ); -- steiner_inst

  valid_o <= steiner_valid;
  done_o  <= steiner_done;

  steiner2uart_inst : entity work.steiner2uart
    generic map (
      G_N => C_N,
      G_K => C_K,
      G_T => C_T
    )
    port map (
      clk_i     => clk,
      rst_i     => rst,
      s_valid_i => steiner_valid,
      s_ready_o => steiner_ready,
      s_data_i  => steiner_data,
      m_valid_o => uart_tx_valid,
      m_ready_i => uart_tx_ready,
      m_data_o  => uart_tx_data,
      done_i    => steiner_done,
      done_o    => open
    ); -- steiner2uart_inst

  uart_inst : entity work.uart
    generic map (
      G_DIVISOR => C_CLK_SPEED_HZ / C_BAUDRATE
    )
    port map (
      clk_i      => clk,
      rst_i      => rst,
      tx_valid_i => uart_tx_valid,
      tx_ready_o => uart_tx_ready,
      tx_data_i  => uart_tx_data,
      rx_valid_o => open,
      rx_ready_i => '1',
      rx_data_o  => open,
      uart_tx_o  => uart_rxd_o,
      uart_rx_i  => uart_txd_i
    ); -- uart_inst

end architecture synthesis;

