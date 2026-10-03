-- This generates the clock and reset for the Nexys 4 DDR board.
-- * It generates a 190 MHz clock from the 100 MHz board clock. This is the fastest
--   clock where the search logic reliably meets timing, see ALGORITHM.md.
-- * It converts the active-low reset button into a synchronous active-high reset.
--   The reset is also active until the MMCM has locked.

library ieee;
  use ieee.std_logic_1164.all;

library unisim;
  use unisim.vcomponents.all;

entity clk_rst is
  port (
    clk_i  : in  std_logic;   -- 100 MHz
    rstn_i : in  std_logic;   -- Active low, asynchronous
    clk_o  : out std_logic;   -- 190 MHz
    rst_o  : out std_logic    -- Active high, synchronous to clk_o
  );
end entity clk_rst;

architecture synthesis of clk_rst is

  signal clkfb    : std_logic;
  signal clk_mmcm : std_logic;
  signal clk      : std_logic;
  signal locked   : std_logic;

  -- Synchronize the asynchronous reset button to the clock
  signal rst_sync : std_logic_vector(1 downto 0) := (others => '1');

  attribute async_reg : string;
  attribute async_reg of rst_sync : signal is "true";

begin

  -- VCO = 100 MHz * 9.5 / 1 = 950 MHz. Output = 950 MHz / 5 = 190 MHz.
  mmcm_inst : component mmcme2_base
    generic map (
      CLKIN1_PERIOD    => 10.0,
      DIVCLK_DIVIDE    => 1,
      CLKFBOUT_MULT_F  => 9.5,
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

  clk_o <= clk;
  rst_o <= rst_sync(1);

end architecture synthesis;
