-- This is the top level file for the Nexys 4 DDR board.
-- * It generates a 180 MHz clock from the 100 MHz board clock. This is the fastest
--   clock where the search logic meets timing with some margin.
-- * It converts the active-low reset button into a synchronous active-high reset.
-- * It sends each solution as text over the UART, at 115200 baud with 8N1, see
--   steiner2uart.vhd. The search waits while the solutions are being sent.

library ieee;
  use ieee.std_logic_1164.all;
library work;
  use work.steiner_pkg.all;

library unisim;
  use unisim.vcomponents.all;

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

  constant C_N : natural := 9;
  constant C_K : natural := 3;
  constant C_T : natural := 2;

  constant C_CLK_SPEED_HZ : positive := 180_000_000;
  constant C_BAUDRATE     : positive := 115_200;

  signal clkfb    : std_logic;
  signal clk_mmcm : std_logic;
  signal clk      : std_logic;   -- 180 MHz
  signal rst      : std_logic;
  signal locked   : std_logic;

  -- Synchronize the asynchronous reset button to the clock
  signal rst_sync : std_logic_vector(1 downto 0) := (others => '1');

  attribute async_reg : string;
  attribute async_reg of rst_sync : signal is "true";

  signal steiner_valid : std_logic;
  signal steiner_ready : std_logic;
  signal steiner_data  : std_logic_vector(0 to binom(C_N, C_T) / binom(C_K, C_T) * C_N - 1);

  signal uart_tx_valid : std_logic;
  signal uart_tx_ready : std_logic;
  signal uart_tx_data  : std_logic_vector(7 downto 0);

begin

  -- VCO = 100 MHz * 9 / 1 = 900 MHz. Output = 900 MHz / 5 = 180 MHz.
  mmcm_inst : component mmcme2_base
    generic map (
      CLKIN1_PERIOD    => 10.0,
      DIVCLK_DIVIDE    => 1,
      CLKFBOUT_MULT_F  => 9.0,
      CLKOUT0_DIVIDE_F => 5.0
    )
    port map (
      clkin1   => clk_i,
      clkfbin  => clkfb,
      clkfbout => clkfb,
      clkout0  => clk_mmcm,
      locked   => locked,
      pwrdwn   => '0',
      rst      => '0'
    ); -- mmcm_inst

  bufg_inst : component bufg
    port map (
      i => clk_mmcm,
      o => clk
    ); -- bufg_inst

  rst_proc : process (clk)
  begin
    if rising_edge(clk) then
      rst_sync <= rst_sync(0) & (not rstn_i or not locked);
    end if;
  end process rst_proc;

  rst <= rst_sync(1);

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
      done_o    => done_o
    ); -- steiner_inst

  valid_o <= steiner_valid;

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
      m_data_o  => uart_tx_data
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

