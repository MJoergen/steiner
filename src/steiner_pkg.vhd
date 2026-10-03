-- Declarations shared by the search (steiner.vhd and valid.vhd), the text output
-- (steiner2uart.vhd) and the testbenches.

library ieee;
  use ieee.std_logic_1164.all;

package steiner_pkg is

  -- Calculate the binomial coefficient B(n,k)
  pure function binom(n : natural; k : natural) return natural;

  -- The number of rows in a Steiner system S(t, k, n), B(n,t) / B(k,t). This is
  -- only exact for admissible parameters.
  pure function num_blocks(t : natural; k : natural; n : natural) return natural;

  -- The number of ones in a vector
  pure function count_ones(arg : std_logic_vector) return natural;

  -- The columns of row "i", as a vector with column 0 first. The rows are all the
  -- B(n,k) sets of "k" of the "n" columns, numbered in lexicographic order of their
  -- columns, so index 0 is {0,1,2} for k = 3, index 1 is {0,1,3}, and so on.
  pure function row_columns(i : natural; k : natural; n : natural) return std_logic_vector;

end package steiner_pkg;

package body steiner_pkg is

  pure function binom(n : natural; k : natural) return natural is
    variable res : natural := 1;
  begin
    for i in 1 to k loop
      res := (res * (n+1-i)) / i;
    end loop;
    return res;
  end function binom;

  pure function num_blocks(t : natural; k : natural; n : natural) return natural is
  begin
    return binom(n, t) / binom(k, t);
  end function num_blocks;

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

  -- Column "j" is in the row if "i" is less than the number of rows that have it,
  -- given the columns before.
  pure function row_columns(i : natural; k : natural; n : natural) return std_logic_vector is
    variable res : std_logic_vector(0 to n-1) := (others => '0');
    variable kk  : natural := k;
    variable ii  : natural := i;
  begin
    for j in 0 to n-1 loop
      exit when kk = 0;
      if ii < binom(n-j-1, kk-1) then
        res(j) := '1';
        kk     := kk - 1;
      else
        ii     := ii - binom(n-j-1, kk-1);
      end if;
    end loop;
    return res;
  end function row_columns;

end package body steiner_pkg;
