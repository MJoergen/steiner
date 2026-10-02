-- Testbench for the search in steiner.vhd. It runs the search to the end, stalls
-- the output stream at random, and checks every solution, independently of
-- valid.vhd. It writes the solutions to G_OUTPUT, in the same format as the results
-- files, and fails if a check fails, if the search takes longer than G_TIMEOUT, or
-- if the number of solutions is wrong for one of the known results.
--
-- GHDL can set the integer and string generics from the command line, e.g.
-- -gG_N=7, but not G_TIMEOUT, since it is a time. To change it, edit its default
-- value below.

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

  constant C_NUM_ROWS : natural := binom(G_N, G_K);
  constant C_B        : natural := binom(G_N, G_T) / binom(G_K, G_T);

  -- Each row has length "n", with column 0 on the left
  subtype row_t is std_logic_vector(0 to G_N-1);
  type rows_t is array (natural range <>) of row_t;

  -- Calculate all sets of "size" columns, as rows with "size" ones, numbered in
  -- lexicographic order of the column positions of their ones. This is done
  -- independently of valid.vhd, by stepping through the combinations one at a time.
  pure function rows_init(size : natural) return rows_t is
    variable res  : rows_t(0 to binom(G_N, size)-1);
    variable cols : integer_vector(0 to size-1);
    variable i    : integer;
  begin
    for j in 0 to size-1 loop
      cols(j) := j;
    end loop;
    for idx in res'range loop
      res(idx) := (others => '0');
      for j in 0 to size-1 loop
        res(idx)(cols(j)) := '1';
      end loop;

      -- Go to the next combination
      i := size-1;
      while i >= 0 and cols(i) = G_N-size+i loop
        i := i-1;
      end loop;
      if i >= 0 then
        cols(i) := cols(i) + 1;
        for j in i+1 to size-1 loop
          cols(j) := cols(j-1) + 1;
        end loop;
      end if;
    end loop;
    return res;
  end function rows_init;

  -- All rows with "k" ones
  constant C_ROWS : rows_t(0 to C_NUM_ROWS-1) := rows_init(G_K);

  -- All sets of "t" columns
  constant C_TSETS : rows_t(0 to binom(G_N, G_T)-1) := rows_init(G_T);

  -- Count number of 1's in a vector
  pure function count_ones(arg : std_logic_vector) return natural is
    variable res : natural := 0;
  begin
    for i in arg'range loop
      if arg(i) = '1' then
        res := res + 1;
      end if;
    end loop;
    return res;
  end function count_ones;

  -- The number of solutions for the known results, or -1 if unknown
  pure function expected_count return integer is
  begin
    if G_N = 7 and G_K = 3 and G_T = 2 then
      return 30;
    elsif G_N = 9 and G_K = 3 and G_T = 2 then
      return 840;
    elsif G_N = 8 and G_K = 4 and G_T = 3 then
      return 30;
    else
      return -1;
    end if;
  end function expected_count;

  signal clk     : std_logic := '0';
  signal rst     : std_logic := '1';
  signal done    : std_logic := '0';
  signal m_valid : std_logic;
  signal m_ready : std_logic := '1';
  signal m_data  : std_logic_vector(0 to C_B*G_N-1);
  signal count   : natural;

  -- The indices of the rows of the solution on m_data, or C_NUM_ROWS for a row that
  -- doesn't have "k" ones
  signal indices : integer_vector(0 to C_B-1);

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

  -- Hold m_ready low for random periods averaging 1024 clock cycles, about once
  -- every 4096 clock cycles. For (9, 3, 2), solutions are about 150 clock cycles
  -- apart on average, so this makes the search wait for some of them.
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

  -- Find the index of each row of the solution in the table of rows
  indices_proc : process (all)
  begin
    for i in 0 to C_B-1 loop
      indices(i) <= C_NUM_ROWS;
      for j in C_ROWS'range loop
        if m_data(i*G_N to i*G_N+G_N-1) = C_ROWS(j) then
          indices(i) <= j;
        end if;
      end loop;
    end loop;
  end process indices_proc;

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
          write(l, indices(i));
        end loop;
        write(l, string'("]"));
        report l.all;
        writeline(output_file, l);
      end if;
    end if;
  end process output_proc;

  -- Check each solution as it is received:
  -- * Each row has "k" ones, and the row indices are strictly increasing.
  -- * Each pair of rows shares fewer than "t" ones.
  -- * Every set of "t" columns is in exactly one row, so it is a Steiner system.
  -- * The solution comes after the previous one in lexicographic order, so no
  --   solution is received twice.
  verify_proc : process (clk)
    variable prev    : integer_vector(0 to C_B-1);
    variable first   : boolean := true;
    variable common  : natural;
    variable covered : natural;
  begin
    if rising_edge(clk) then
      if m_valid = '1' and m_ready = '1' then
        for i in 0 to C_B-1 loop
          assert indices(i) < C_NUM_ROWS
            report "Row " & to_string(i) & " of the solution is " &
                   to_string(m_data(i*G_N to i*G_N+G_N-1)) & ", which doesn't have " &
                   to_string(G_K) & " ones"
            severity failure;
          if i > 0 then
            assert indices(i) > indices(i-1)
              report "Row indices not strictly increasing at position " & to_string(i)
              severity failure;
          end if;
        end loop;

        for i in 0 to C_B-1 loop
          for j in i+1 to C_B-1 loop
            common := count_ones(C_ROWS(indices(i)) and C_ROWS(indices(j)));
            assert common < G_T
              report "Rows " & to_string(indices(i)) & " and " & to_string(indices(j)) &
                     " share " & to_string(common) & " ones"
              severity failure;
          end loop;
        end loop;

        -- It is a Steiner system: every set of "t" columns is in exactly one row
        for s in C_TSETS'range loop
          covered := 0;
          for i in 0 to C_B-1 loop
            if (C_ROWS(indices(i)) and C_TSETS(s)) = C_TSETS(s) then
              covered := covered + 1;
            end if;
          end loop;
          assert covered = 1
            report "Columns " & to_string(C_TSETS(s)) & " are in " &
                   to_string(covered) & " rows rather than one"
            severity failure;
        end loop;

        if not first then
          for i in 0 to C_B-1 loop
            if indices(i) /= prev(i) then
              assert indices(i) > prev(i)
                report "Solution not after the previous one"
                severity failure;
              exit;
            end if;
            assert i < C_B-1
              report "Solution is the same as the previous one"
              severity failure;
          end loop;
        end if;

        prev  := indices;
        first := false;
      end if;
    end if;
  end process verify_proc;

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

  -- Fail the simulation if the search does not finish in time, or if it finds the
  -- wrong number of solutions
  done_proc : process
  begin
    wait until done = '1' for G_TIMEOUT;
    assert done = '1'
      report "Search did not finish within " & time'image(G_TIMEOUT)
      severity failure;

    if expected_count >= 0 then
      assert count = expected_count
        report "Found " & to_string(count) & " solutions, expected " &
               to_string(expected_count)
        severity failure;
      report "PASS: Found all " & to_string(count) & " solutions";
    else
      report "Found " & to_string(count) & " solutions. The expected number is not known."
        severity warning;
    end if;
    wait;
  end process done_proc;

end architecture simulation;

