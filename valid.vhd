-- Given one selected row, as a one-hot vector, this outputs the set of rows that
-- don't conflict with it, i.e. that share fewer than "t" columns with it. The table
-- of which rows conflict is calculated at elaboration time, and the logic is purely
-- combinational. The search in steiner.vhd uses one instance for each segment of
-- the rows.

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
library work;
  use work.steiner_pkg.all;

entity valid is
  generic (
    G_N        : natural;
    G_K        : natural;
    G_T        : natural;
    G_NUM_ROWS : natural;
    -- The range of rows that can be selected
    G_FIRST    : natural;
    G_LAST     : natural
  );
  port (
    -- One-hot (or all zero) selection of a single row
    sel_i   : in  std_logic_vector(G_LAST downto G_FIRST);
    -- The rows that can sit next to the selected row. All ones if no row is selected.
    -- Only the selected row and the rows after it are checked. The rows before it are
    -- always shown as valid, because the search never places them after this row.
    valid_o : out std_logic_vector(G_NUM_ROWS-1 downto 0)
  );
end entity valid;

architecture synthesis of valid is

  -- Count number of 1's in a vector
  pure function count_ones(arg : std_logic_vector) return natural is
    variable res : natural := 0;
  begin
    for i in arg'low to arg'high loop
      if arg(i) = '1' then
        res := res + 1;
      end if;
    end loop;
    return res;
  end function count_ones;

  -- Each row has length "n".
  type ram_t is array (natural range <>) of std_logic_vector(G_N-1 downto 0);

  -- This calculates an array of all possible combinations of N choose K, i.e. all
  -- the rows, numbered in lexicographic order of their columns. Bit "j" of a row is
  -- column "j".
  pure function combination_init(n : natural; k : natural) return ram_t is
    variable res : ram_t(G_NUM_ROWS-1 downto 0) := (others => (others => '0'));
    variable kk  : natural := k;
    variable ii  : natural := 0;
  begin
    loop_i : for i in 0 to G_NUM_ROWS-1 loop
      kk := k;
      ii := i;
      loop_j : for j in 0 to G_N-1 loop
        if kk = 0 then
          exit loop_j;
        end if;
        if ii < binom(n-j-1, kk-1) then
          res(i)(j) := '1';
          kk := kk - 1;
        else
          ii := ii - binom(n-j-1, kk-1);
        end if;
      end loop loop_j;
      assert count_ones(res(i)) = G_K
        report "Row " & to_string(i) & " doesn't have " & to_string(G_K) & " ones"
        severity failure;
    end loop loop_i;
    return res;
  end function combination_init;

  -- Each row contains exactly "k" ones.
  constant C_COMBINATIONS : ram_t(G_NUM_ROWS-1 downto 0) := combination_init(G_N, G_K);

  -- Each pair of rows and'ed together contain less than "t" ones. Entry "j" in this
  -- table shows the rows that conflict with row "j", meaning they break this rule.
  type conflict_t is array (natural range <>) of std_logic_vector(G_NUM_ROWS-1 downto 0);

  pure function conflict_init return conflict_t is
    variable res : conflict_t(G_NUM_ROWS-1 downto 0);
  begin
    for j in 0 to G_NUM_ROWS-1 loop
      for i in 0 to G_NUM_ROWS-1 loop
        if count_ones(C_COMBINATIONS(i) and C_COMBINATIONS(j)) >= G_T then
          res(j)(i) := '1';
        else
          res(j)(i) := '0';
        end if;
      end loop;
    end loop;
    return res;
  end function conflict_init;

  constant C_CONFLICT : conflict_t(G_NUM_ROWS-1 downto 0) := conflict_init;

begin

  -- Row j is valid unless the selected row conflicts with it. Since the selection is
  -- one-hot, this is a small OR over just the rows that conflict with row j, rather
  -- than a lookup indexed by a binary row number.
  valid_gen : for j in 0 to G_NUM_ROWS-1 generate
    process (all)
      variable tmp : std_logic;
    begin
      tmp := '0';
      for i in G_FIRST to minimum(j, G_LAST) loop
        if C_CONFLICT(j)(i) = '1' then
          tmp := tmp or sel_i(i);
        end if;
      end loop;
      valid_o(j) <= not tmp;
    end process;
  end generate valid_gen;

end architecture synthesis;

