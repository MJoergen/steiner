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

  -- The following is an optimization that saves a lot of work by doing an "early
  -- pruning" of the search tree:
  -- * The first C_R rows must have the left-most column set. These are the rows
  --   before C_SEG1.
  -- * The next C_R-C_L2 rows must have the second column set. These are the rows
  --   before C_SEG2.
  constant C_SEG1 : natural := binom(G_N-1, G_K-1);
  constant C_SEG2 : natural := binom(G_N-1, G_K-1) + binom(G_N-2, G_K-1);

  -- One bit for each of the C_NUM_ROWS rows
  subtype rows_t is std_logic_vector(C_NUM_ROWS-1 downto 0);
  type rows_vec_t is array (natural range <>) of rows_t;

  subtype index_t is natural range 0 to C_NUM_ROWS-1;
  type index_vec_t is array (natural range <>) of index_t;

  -- Convert a one-hot vector to the index of the bit that is set. This is just an OR
  -- for each bit of the index, rather than a priority encoder.
  pure function index_of(arg : rows_t) return index_t is
    variable res : natural;
    variable bit : natural;
  begin
    res := 0;
    bit := 1;
    while bit < C_NUM_ROWS loop
      for i in 0 to C_NUM_ROWS-1 loop
        if (i / bit) mod 2 = 1 and arg(i) = '1' then
          res := res + bit;
          exit;
        end if;
      end loop;
      bit := bit * 2;
    end loop;
    return res;
  end function index_of;

  -- Isolate the lowest set bit. This maps onto a carry chain.
  pure function lowest_of(arg : std_logic_vector) return std_logic_vector is
  begin
    return arg and std_logic_vector(unsigned(not arg) + 1);
  end function lowest_of;

  -- The rows are split into three segments by C_SEG1 and C_SEG2. To keep the carry
  -- chains short, the first row is found in each segment separately.
  constant C_FIRST : integer_vector(0 to 2) := (0, C_SEG1, C_SEG2);
  constant C_LAST  : integer_vector(0 to 2) := (C_SEG1-1, C_SEG2-1, C_NUM_ROWS-1);

  -- The rows that can still be tried for the current position. They all come after
  -- the row placed before it, and fit with every row placed so far.
  signal cand       : rows_t;

  -- Whether "cand" has any rows in each segment
  signal any        : std_logic_vector(0 to 2);

  -- The first (i.e. lowest numbered) row of "cand" in each segment, as a one-hot
  -- vector
  signal seg_lowest : rows_t;

  -- The rows that fit with each bit of "seg_lowest"
  signal seg_compat : rows_vec_t(0 to 2);

  -- The rows that fit with the first row in "cand"
  signal compat     : rows_t;

  -- Whether to place the first row in "cand"
  signal place      : std_logic;

  -- The number of rows placed so far, and some values derived from it. These are
  -- kept in registers to keep them out of the critical path.
  signal depth      : natural range 0 to C_B;
  signal depth_m1   : natural range 0 to C_B-1; -- depth - 1
  signal empty      : std_logic;                -- depth = 0
  signal full       : std_logic;                -- depth = C_B
  signal allow1     : std_logic;                -- depth >= C_R
  signal allow2     : std_logic;                -- depth >= 2*C_R-C_L2

  -- Entry "d" is the row placed when "d" rows had already been placed, and the rows
  -- that remain to be tried in its place afterwards. The stack is only ever read
  -- at entry "depth-1", so it fits in distributed RAM.
  signal stack      : rows_vec_t(0 to C_B-1);
  signal positions  : index_vec_t(0 to C_B-1);

  -- Writing to the stack is delayed by one clock cycle, to keep it out of the
  -- critical path. These registers hold the values needed for the write, after a row
  -- was placed in the previous clock cycle. They are loaded every clock cycle, so
  -- they don't depend on the decision to place a row.
  signal placed       : std_logic;
  signal placed_depth : natural range 0 to C_B-1;
  signal placed_cand  : rows_t;
  signal placed_seg   : rows_t;    -- seg_lowest
  signal placed_any   : std_logic_vector(0 to 1);

  -- The row that was placed in the previous clock cycle, as a one-hot vector, and
  -- the rows that remain to be tried in its place afterwards
  signal placed_row   : rows_t;
  signal placed_rest  : rows_t;

  -- The candidates to continue with after removing the most recently placed row
  signal top_cand     : rows_t;

begin

  seg_gen : for s in 0 to 2 generate
    any(s) <= or cand(C_LAST(s) downto C_FIRST(s));

    seg_lowest(C_LAST(s) downto C_FIRST(s)) <= lowest_of(cand(C_LAST(s) downto C_FIRST(s)));

    valid_inst : entity work.valid
      generic map (
        G_N        => G_N,
        G_K        => G_K,
        G_T        => G_T,
        G_NUM_ROWS => C_NUM_ROWS,
        G_FIRST    => C_FIRST(s),
        G_LAST     => C_LAST(s)
      )
      port map (
        sel_i   => seg_lowest(C_LAST(s) downto C_FIRST(s)),
        valid_o => seg_compat(s)
      ); -- valid_inst
  end generate seg_gen;

  -- Only the first non-empty segment counts. This is done after the lookup in
  -- "valid", to keep it out of the critical path.
  compat <= seg_compat(0) and
            (seg_compat(1) or any(0)) and
            (seg_compat(2) or any(0) or any(1));

  -- The first row in "cand" may be placed, unless the early pruning forbids it
  place <= any(0) or (allow1 and any(1)) or (allow2 and any(2));

  -- As with "compat", only the first non-empty segment counts
  placed_row(C_LAST(0) downto C_FIRST(0)) <= placed_seg(C_LAST(0) downto C_FIRST(0));
  placed_row(C_LAST(1) downto C_FIRST(1)) <= placed_seg(C_LAST(1) downto C_FIRST(1))
                                             when placed_any(0) = '0' else (others => '0');
  placed_row(C_LAST(2) downto C_FIRST(2)) <= placed_seg(C_LAST(2) downto C_FIRST(2))
                                             when placed_any = "00" else (others => '0');

  placed_rest <= placed_cand and not placed_row;

  -- If a row was placed in the previous clock cycle, its stack entry has not been
  -- written yet
  top_cand <= placed_rest when placed = '1' else stack(depth_m1);

  -- Each clock cycle the search does one of these things:
  -- * Sends a solution, if all rows are placed, and then removes the last row.
  -- * Places the first remaining candidate row.
  -- * Removes the last row, if there are no candidates left.
  main_proc : process (clk_i)
    variable solution : index_vec_t(0 to C_B-1);

    procedure set_depth (d : natural) is
    begin
      depth    <= d;
      depth_m1 <= maximum(d, 1) - 1;
      empty    <= '1' when d = 0 else '0';
      full     <= '1' when d = C_B else '0';
      allow1   <= '1' when d >= C_R else '0';
      allow2   <= '1' when d >= 2*C_R-C_L2 else '0';
    end procedure set_depth;

    -- Remove the most recently placed row, and continue with the rows after it
    procedure pop is
    begin
      cand <= top_cand;
      set_depth(depth - 1);
    end procedure pop;

  begin
    if rising_edge(clk_i) then
      if m_ready_i = '1' then
        m_valid_o <= '0';
      end if;

      -- Complete the write to the stack, if a row was placed in the previous clock
      -- cycle
      placed       <= '0';
      placed_depth <= minimum(depth, C_B-1);
      placed_cand  <= cand;
      placed_seg   <= seg_lowest;
      placed_any   <= any(0 to 1);
      if placed = '1' then
        stack(placed_depth)     <= placed_rest;
        positions(placed_depth) <= index_of(placed_row);
      end if;

      if full = '1' then
        -- Wait until the previous solution has been accepted
        if m_valid_o = '0' or m_ready_i = '1' then
          solution := positions;
          if placed = '1' then
            solution(placed_depth) := index_of(placed_row);
          end if;
          -- Copied element by element, because GHDL synthesis (used for formal
          -- verification) gets the array type conversion solution_t(solution) wrong.
          for i in solution'range loop
            m_data_o(i) <= solution(i);
          end loop;
          m_valid_o <= '1';
          pop;
        end if;
      elsif place = '1' then
        -- Place the first candidate row
        cand   <= cand and compat;
        placed <= '1';
        set_depth(depth + 1);
      elsif empty = '0' then
        -- No candidates left, so go back
        pop;
      elsif m_valid_o = '0' then
        done_o <= '1';
      end if;

      if rst_i = '1' then
        cand      <= (others => '1');
        set_depth(0);
        placed    <= '0';
        done_o    <= '0';
        m_valid_o <= '0';
      end if;
    end if;
  end process main_proc;

end architecture synthesis;

