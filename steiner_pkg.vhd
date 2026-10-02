-- Declarations shared by the search (steiner.vhd and valid.vhd) and the testbench.

package steiner_pkg is

  -- One solution: the indices of the chosen rows
  type solution_t is array (natural range <>) of natural;

  -- Calculate the binomial coefficient B(n,k)
  pure function binom(n : natural; k : natural) return natural;

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

end package body steiner_pkg;
