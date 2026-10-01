-- This performs exhaustive brute-force search for Steiner Systems.
-- https://en.wikipedia.org/wiki/Steiner_system
--
-- This is inspired by this video: https://www.youtube.com/watch?v=4xnRZqD7rAo
--
-- The task is as follows:
-- Given numbers n > k > t.
-- Generate all maximal sets of rows where in each set:
-- * Each row has length "n".
-- * Each row contains exactly "k" ones.
-- * Each pair of rows and'ed together contain less than "t" ones.
-- The maximum number of such rows is "b", where
-- b = B(n,t)/B(k,t).
--
-- For the parameters (7, 3, 2) we get 30 solutions.
--
-- For the parameters (9, 3, 2) we get 840 solutions, one of which is the following.
-- The number on the left marks which of the C_NUM_ROWS = 84 is chosen.
--
--  6 **......*
-- 11 *.*....*.
-- 15 *..*..*..
-- 18 *...**...
-- 31 .**...*..
-- 35 .*.*.*...
-- 41 .*..*..*.
-- 49 ..***....
-- 60 ..*..*..*
-- 73 ...*...**
-- 78 ....*.*.*
-- 80 .....***.
--
-- Another solution is:
--  0 ***......
-- 13 *..**....
-- 22 *....**..
-- 27 *......**
-- 35 .*.*.*...
-- 41 .*..*..*.
-- 47 .*....*.*
-- 53 ..**....*
-- 55 ..*.*.*..
-- 59 ..*..*.*.
-- 71 ...*..**.
-- 76 ....**..*
--
-- Here we see that b = 36/3 = 12 corresponding to number of rows.
-- And r = B(n-1,t-1)/B(k-1,t-1) = 8/2 = 4 corresponds to the sum of each column.

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
library work;
  use work.steiner_pkg.all;

entity steiner is
  generic (
    G_N : natural := 9;
    G_K : natural := 3;
    G_T : natural := 2
  );
  port (
    clk_i     : in  std_logic;
    rst_i     : in  std_logic;
    -- AXI-style stream with one solution at a time
    m_valid_o : out std_logic := '0';
    m_ready_i : in  std_logic;
    m_data_o  : out solution_t(0 to binom(G_N, G_T) / binom(G_K, G_T) - 1);
    -- The search is finished and the last solution has been accepted
    done_o    : out std_logic := '0'
  );
end entity steiner;

architecture synthesis of steiner is

  constant C_NUM_ROWS : natural := binom(G_N, G_K);
  constant C_B        : natural := binom(G_N, G_T) / binom(G_K, G_T);
  constant C_R        : natural := binom(G_N-1, G_T-1) / binom(G_K-1, G_T-1);

  -- Number of rows that contain both column 0 and column 1. This is only defined
  -- for T >= 2. For T = 1 it returns C_R, which disables the second pruning rule.
  pure function calc_l2 return natural is
  begin
    if G_T >= 2 then
      return binom(G_N-2, G_T-2) / binom(G_K-2, G_T-2);
    else
      return C_R;
    end if;
  end function calc_l2;

  constant C_L2       : natural := calc_l2;

  signal cur_index    : natural range 0 to C_NUM_ROWS;

  signal valid        : std_logic_vector(C_NUM_ROWS-1 downto 0);

  type pos_t is array (natural range <>) of natural range 0 to C_NUM_ROWS;
  signal positions    : pos_t(0 to C_B-1) := (others => C_NUM_ROWS);
  signal num_placed   : natural range 0 to C_B;

  type valid_t is array (natural range <>) of std_logic_vector(C_NUM_ROWS-1 downto 0);
  signal valid_vec    : valid_t(C_B-1 downto 0);

  signal remove       : std_logic;

begin

  valid_vec_gen : for i in 0 to C_B-1 generate
    valid_inst : entity work.valid
      generic map (
        G_N        => G_N,
        G_K        => G_K,
        G_T        => G_T,
        G_NUM_ROWS => C_NUM_ROWS
      )
      port map (
        pos_i   => positions(i),
        valid_o => valid_vec(i)
      );
  end generate valid_vec_gen;

  process (all)
    variable tmp : std_logic_vector(C_NUM_ROWS-1 downto 0);
  begin
    tmp := (others => '1');
    for i in 0 to C_B-1 loop
       tmp := tmp and valid_vec(i);

       -- The following is an optimization that saves a lot of work by doing an "early
       -- pruning" of the search tree.
       if positions(i) < C_NUM_ROWS then
         -- The first C_R rows must have the left-most column set
         if i < C_R then
           if positions(i) >= binom(G_N-1, G_K-1) then
             tmp := (others => '0');
           end if;
         -- The next C_R-C_L2 rows must have the second column set
         elsif i < 2*C_R-C_L2 then
           if positions(i) >= binom(G_N-1, G_K-1) + binom(G_N-2, G_K-1) then
             tmp := (others => '0');
           end if;
         end if;
       end if;
    end loop;
    valid <= tmp;
  end process;

  main_proc : process (clk_i)
  begin
    if rising_edge(clk_i) then
      if m_ready_i = '1' then
        m_valid_o <= '0';
      end if;

      if remove = '1' then
        cur_index <= positions(num_placed) + 1;
        positions(num_placed) <= C_NUM_ROWS;
        remove <= '0';
      elsif num_placed = C_B and m_valid_o = '1' and m_ready_i = '0' then
        -- The previous solution has not been accepted yet, so wait
        null;
      else
        if num_placed = C_B then
          -- Copied element by element, because GHDL synthesis (used for formal
          -- verification) crashes on the array type conversion solution_t(positions).
          for i in positions'range loop
            m_data_o(i) <= positions(i);
          end loop;
          m_valid_o <= '1';
          -- We remove the previous piece
          num_placed <= num_placed - 1;
          remove     <= '1';
        end if;

        if cur_index < C_NUM_ROWS and valid(cur_index) = '1' then
          -- We place the next piece
          num_placed <= num_placed + 1;
          positions(num_placed) <= cur_index;
        else
          if cur_index < C_NUM_ROWS-1 and unsigned(valid) /= 0 then
            -- Go to next potential position
            cur_index <= cur_index + 1;
          else
            if num_placed > 0 then
              -- We remove the previous piece
              num_placed <= num_placed - 1;
              remove     <= '1';
            elsif m_valid_o = '0' then
              done_o <= '1';
            end if;
          end if;
        end if;
      end if;

      if rst_i = '1' then
        positions  <= (others => C_NUM_ROWS);
        num_placed <= 0;
        cur_index  <= 0;
        done_o     <= '0';
        remove     <= '0';
        m_valid_o  <= '0';
      end if;
    end if;
  end process main_proc;

end architecture synthesis;

