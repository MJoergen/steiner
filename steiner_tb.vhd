library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

entity steiner_tb is
  generic (
    G_N       : natural := 9;
    G_K       : natural := 3;
    G_T       : natural := 2;
    G_TIMEOUT : time    := 1100 ms
  );
end entity steiner_tb;

architecture simulation of steiner_tb is

  signal clk   : std_logic := '0';
  signal rst   : std_logic := '1';
  signal done  : std_logic := '0';
  signal valid : std_logic := '0';
  signal count : natural;

begin

  clk <= not done and not clk after 5 ns;
  rst <= '1', '0' after 100 ns;

  steiner_inst : entity work.steiner
    generic map (
      G_N => G_N,
      G_K => G_K,
      G_T => G_T
    )
    port map (
      clk_i   => clk,
      rst_i   => rst,
      valid_o => valid,
      done_o  => done
    ); -- steiner_inst

  count_proc : process (clk)
  begin
    if rising_edge(clk) then
      if valid = '1' then
        count <= count + 1;
      end if;
      if rst = '1' then
        count <= 0;
      end if;
    end if;
  end process count_proc;

  -- Fail the simulation if the search does not finish in time
  timeout_proc : process
  begin
    wait until done = '1' for G_TIMEOUT;
    assert done = '1'
      report "Search did not finish within " & time'image(G_TIMEOUT)
      severity failure;
    wait;
  end process timeout_proc;

end architecture simulation;

