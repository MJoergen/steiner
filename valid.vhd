library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

entity valid is
  generic (
    G_N        : natural;
    G_K        : natural;
    G_T        : natural;
    G_NUM_ROWS : natural
  );
  port (
    pos_i   : in  natural range 0 to G_NUM_ROWS;
    valid_o : out std_logic_vector(G_NUM_ROWS-1 downto 0)
  );
end entity valid;

architecture synthesis of valid is

  -- Calculate the binomial coefficient B(n,k)
  pure function binom(n : natural; k : natural) return natural is
    variable res : natural := 1;
  begin
    for i in 1 to k loop
      res := (res * (n+1-i)) / i;
    end loop;
    return res;
  end function binom;

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

  -- This calculates an array of all possible combinations of N choose K.
  pure function combination_init(n : natural; k : natural) return ram_t is
    variable res : ram_t(G_NUM_ROWS downto 0) := (others => (others => '0'));
    variable kk  : natural := k;
    variable ii  : natural := 0;
  begin
    report "combination_init: n=" & to_string(n) & ", k=" & to_string(k);
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
      assert(count_ones(res(i)) = G_K);
    end loop loop_i;
    report "combination_init done.";
    return res;
  end function combination_init;

  -- Each row contains exactly "k" ones, except the last which is just zero.
  constant C_COMBINATIONS : ram_t(G_NUM_ROWS downto 0) := combination_init(G_N, G_K);

begin

  -- Each pair of rows and'ed together contain less than "t" ones.
  valid_proc : process(all)
  begin
    valid_o <= (others => '1');
    for j in 0 to G_NUM_ROWS-1 loop
      if count_ones(C_COMBINATIONS(pos_i) and C_COMBINATIONS(j)) >= G_T then
        valid_o(j) <= '0';
      end if;
    end loop;
  end process valid_proc;

end architecture synthesis;

