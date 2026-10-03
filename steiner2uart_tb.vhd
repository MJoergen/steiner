-- Testbench for steiner2uart.vhd. It runs the search in steiner.vhd to the end,
-- converts every solution to text with steiner2uart.vhd, and writes the text to
-- G_OUTPUT. It stalls the characters at random, so the search has to wait for
-- steiner2uart.vhd. "make check" compares G_OUTPUT with "steiner_ref.py --text".
--
-- It fails if a character changes while it is waiting to be accepted, or if the
-- text isn't finished after G_TIMEOUT. GHDL can't set G_TIMEOUT from the command
-- line, since it is a time. To change it, edit its default value below.

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use ieee.math_real.all;
library std;
  use std.textio.all;
library work;
  use work.steiner_pkg.all;

entity steiner2uart_tb is
  generic (
    G_T       : natural := 2;
    G_K       : natural := 3;
    G_N       : natural := 9;
    G_TIMEOUT : time    := 1100 ms;
    G_OUTPUT  : string  := "steiner2uart_tb.txt"
  );
end entity steiner2uart_tb;

architecture simulation of steiner2uart_tb is

  constant C_B : natural := binom(G_N, G_T) / binom(G_K, G_T);

  signal clk           : std_logic := '0';
  signal rst           : std_logic := '1';
  signal finished      : std_logic := '0';
  signal done          : std_logic;
  signal steiner_valid : std_logic;
  signal steiner_ready : std_logic;
  signal steiner_data  : std_logic_vector(0 to C_B*G_N-1);
  signal char_valid    : std_logic;
  signal char_ready    : std_logic := '0';
  signal char_data     : std_logic_vector(7 downto 0);

begin

  clk <= not finished and not clk after 5 ns;
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
      m_valid_o => steiner_valid,
      m_ready_i => steiner_ready,
      m_data_o  => steiner_data,
      done_o    => done
    ); -- steiner_inst

  steiner2uart_inst : entity work.steiner2uart
    generic map (
      G_N => G_N,
      G_K => G_K,
      G_T => G_T
    )
    port map (
      clk_i     => clk,
      rst_i     => rst,
      s_valid_i => steiner_valid,
      s_ready_o => steiner_ready,
      s_data_i  => steiner_data,
      m_valid_o => char_valid,
      m_ready_i => char_ready,
      m_data_o  => char_data
    ); -- steiner2uart_inst

  -- Accept each character with a probability of 30 %
  ready_proc : process (clk)
    variable seed1 : positive := 1;
    variable seed2 : positive := 1;
    variable rand  : real;
  begin
    if rising_edge(clk) then
      uniform(seed1, seed2, rand);
      char_ready <= '1' when rand < 0.3 else
                    '0';
    end if;
  end process ready_proc;

  -- Write the text to G_OUTPUT, one line at a time. The CR at the end of each line
  -- is kept, and the LF becomes the end of the line in the file.
  output_proc : process (clk)
    file     output_file : text open write_mode is G_OUTPUT;
    variable l           : line;
    variable c           : character;
  begin
    if rising_edge(clk) then
      if char_valid = '1' and char_ready = '1' then
        c := character'val(to_integer(unsigned(char_data)));
        if c = LF then
          writeline(output_file, l);
        else
          write(l, c);
        end if;
      end if;
    end if;
  end process output_proc;

  -- A character that is waiting to be accepted must not change
  handshake_proc : process (clk)
    variable waiting : boolean := false;
    variable prev    : std_logic_vector(7 downto 0);
  begin
    if rising_edge(clk) then
      if waiting then
        assert char_valid = '1' and char_data = prev
          report "The character changed while it was waiting to be accepted"
          severity failure;
      end if;
      waiting := char_valid = '1' and char_ready = '0';
      prev    := char_data;
    end if;
  end process handshake_proc;

  -- The text is finished when the search is done, and steiner2uart.vhd is waiting
  -- for the next solution. done goes high one clock cycle after the last solution
  -- is accepted, when steiner2uart.vhd is busy with it.
  finish_proc : process
  begin
    wait until done = '1' and steiner_ready = '1' for G_TIMEOUT;
    assert done = '1' and steiner_ready = '1'
      report "Text not finished within " & time'image(G_TIMEOUT)
      severity failure;
    finished <= '1';
    wait;
  end process finish_proc;

end architecture simulation;
