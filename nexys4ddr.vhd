-- This is the top level file for the Nexys 4 DDR board.
-- * It generates a 180 MHz clock from the 100 MHz board clock. This is the fastest
--   clock where the search logic meets timing with some margin.
-- * It converts the active-low reset button into a synchronous active-high reset.

library ieee;
  use ieee.std_logic_1164.all;

library unisim;
  use unisim.vcomponents.all;

entity nexys4ddr is
  port (
    clk_i   : in  std_logic;   -- 100 MHz
    rstn_i  : in  std_logic;   -- Active low (CPU_RESETN)
    valid_o : out std_logic;
    done_o  : out std_logic
  );
end entity nexys4ddr;

architecture synthesis of nexys4ddr is

  signal clkfb    : std_logic;
  signal clk_mmcm : std_logic;
  signal clk      : std_logic;   -- 180 MHz
  signal locked   : std_logic;

  -- Synchronize the asynchronous reset button to the clock
  signal rst_sync : std_logic_vector(1 downto 0) := (others => '1');

  attribute async_reg : string;
  attribute async_reg of rst_sync : signal is "true";

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

  steiner_inst : entity work.steiner
    generic map (
      G_N => 9,
      G_K => 3,
      G_T => 2
    )
    port map (
      clk_i     => clk,
      rst_i     => rst_sync(1),
      m_valid_o => valid_o,
      m_ready_i => '1',
      m_data_o  => open,
      done_o    => done_o
    ); -- steiner_inst

end architecture synthesis;

