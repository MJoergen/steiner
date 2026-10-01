library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use ieee.math_real.all;
library std;
  use std.textio.all;
library work;
  use work.steiner_pkg.all;

entity steiner_tb is
  generic (
    G_N       : natural := 9;
    G_K       : natural := 3;
    G_T       : natural := 2;
    G_TIMEOUT : time    := 1100 ms;
    G_OUTPUT  : string  := "steiner_tb.txt"
  );
end entity steiner_tb;

architecture simulation of steiner_tb is

  constant C_B : natural := binom(G_N, G_T) / binom(G_K, G_T);

  signal clk     : std_logic := '0';
  signal rst     : std_logic := '1';
  signal done    : std_logic := '0';
  signal m_valid : std_logic;
  signal m_ready : std_logic := '1';
  signal m_data  : solution_t(0 to C_B-1);
  signal count   : natural;

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
      clk_i     => clk,
      rst_i     => rst,
      m_valid_o => m_valid,
      m_ready_i => m_ready,
      m_data_o  => m_data,
      done_o    => done
    ); -- steiner_inst

  -- Hold m_ready low for random periods averaging 1024 clock cycles. Solutions are
  -- several hundred clock cycles apart, so this makes the search wait sometimes.
  ready_proc : process (clk)
    variable seed1 : positive := 1;
    variable seed2 : positive := 1;
    variable rand  : real;
  begin
    if rising_edge(clk) then
      uniform(seed1, seed2, rand);
      if m_ready = '1' and rand < 1.0 / 4096.0 then
        m_ready <= '0';
      end if;
      if m_ready = '0' and rand < 1.0 / 1024.0 then
        m_ready <= '1';
      end if;
    end if;
  end process ready_proc;

  -- Report each solution, and write it to G_OUTPUT in the format of the results files
  output_proc : process (clk)
    file     output_file : text open write_mode is G_OUTPUT;
    variable l           : line;
  begin
    if rising_edge(clk) then
      if m_valid = '1' and m_ready = '1' then
        write(l, string'("["));
        for i in 0 to C_B-1 loop
          if i /= 0 then
            write(l, string'(", "));
          end if;
          write(l, m_data(i));
        end loop;
        write(l, string'("]"));
        report l.all;
        writeline(output_file, l);
      end if;
    end if;
  end process output_proc;

  count_proc : process (clk)
  begin
    if rising_edge(clk) then
      if m_valid = '1' and m_ready = '1' then
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

