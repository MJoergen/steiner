-- This performs exhaustive brute-force search for Steiner Systems.
-- https://en.wikipedia.org/wiki/Steiner_system

-- The task is as follows:
-- Given numbers n > k > t.
-- Generate all maximal sets of rows where in each set:
-- * Each row has length "n".
-- * Each row contains exactly "k" ones.
-- * Each pair of rows and'ed together contain less than "t" ones.
-- The maximum number of such rows is "b", where
-- b = B(n,t)/B(k,t).

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

entity steiner is
  generic (
    G_N : natural := 7;
    G_K : natural := 3;
    G_T : natural := 2
  );
  port (
    clk_i   : in  std_logic;
    rst_i   : in  std_logic;
    valid_o : out std_logic := '0';
    done_o  : out std_logic := '0'
  );
end entity steiner;

architecture synthesis of steiner is

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

  constant C_NUM_ROWS : natural := binom(G_N, G_K);
  constant C_B        : natural := binom(G_N, G_T) / binom(G_K, G_T);
  constant C_R        : natural := binom(G_N-1, G_T-1) / binom(G_K-1, G_T-1);

  -- Each row has length "n".
  type ram_t is array (natural range <>) of std_logic_vector(G_N-1 downto 0);

  -- This calculates an array of all possible combinations of N choose K.
  pure function combination_init(n : natural; k : natural) return ram_t is
    variable res : ram_t(C_NUM_ROWS-1 downto 0) := (others => (others => '0'));
    variable kk  : natural := k;
    variable ii  : natural := 0;
  begin
    report "combination_init: n=" & to_string(n) & ", k=" & to_string(k);
    loop_i : for i in 0 to C_NUM_ROWS-1 loop
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

  -- Each row contains exactly "k" ones.
  constant C_COMBINATIONS : ram_t(C_NUM_ROWS-1 downto 0) := combination_init(G_N, G_K);

  signal cur_index   : natural range 0 to C_NUM_ROWS;

  signal valid       : std_logic_vector(C_NUM_ROWS-1 downto 0);

  type pos_t is array (natural range <>) of natural range 0 to C_NUM_ROWS-1;
  signal positions   : pos_t(0 to C_B-1);
  signal positions_d : pos_t(0 to C_B-1);
  signal num_placed  : natural range 0 to C_B;

begin

  -- Each pair of rows and'ed together contain less than "t" ones.
  valid_proc : process(all)
  begin
    valid <= (others => '1');
    for j in 0 to C_NUM_ROWS-1 loop
      for i in 0 to C_B-1 loop
        if i < num_placed then
          if count_ones(C_COMBINATIONS(positions(i)) and C_COMBINATIONS(j)) >= G_T then
            valid(j) <= '0';
          end if;
        end if;
      end loop;
    end loop;
  end process valid_proc;

  main_proc : process (clk_i)
  begin
    if rising_edge(clk_i) then
      valid_o <= '0';
      if num_placed = C_B then
        positions_d <= positions;
        valid_o     <= '1';

        -- We remove the previous piece
        cur_index  <= positions(num_placed - 1) + 1;
        positions(num_placed - 1) <= 0; -- Just for debug
        num_placed <= num_placed-1;
      end if;

      if cur_index < C_NUM_ROWS and valid(cur_index) = '1' then
        -- We place the next piece
        positions(num_placed) <= cur_index;
        num_placed <= num_placed + 1;
      else
        if cur_index < C_NUM_ROWS-1 and unsigned(valid) /= 0 then
          -- Go to next potential position
          cur_index <= cur_index + 1;
        else
          if num_placed > 0 then
            -- We remove the previous piece
            cur_index  <= positions(num_placed - 1) + 1;
            positions(num_placed - 1) <= 0; -- Just for debug
            num_placed <= num_placed-1;
          else
            done_o <= '1';
          end if;
        end if;
      end if;

      if rst_i = '1' then
        positions  <= (others => 0);
        num_placed <= 0;
        cur_index  <= 0;
        done_o     <= '0';
      end if;
    end if;
  end process main_proc;

end architecture synthesis;

