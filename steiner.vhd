-- This finds every Steiner system S(t, k, n) by a depth-first search with
-- backtracking: https://en.wikipedia.org/wiki/Steiner_system
--
-- It is inspired by this video: https://www.youtube.com/watch?v=4xnRZqD7rAo
--
-- Given n > k > t >= 1, a row is a set of k of the n columns, and two rows conflict
-- if they share t or more columns. A solution is a set of b = B(n,t) / B(k,t) rows
-- where no two rows conflict, which makes it a Steiner system. The rows are
-- numbered in lexicographic order of their columns. The solutions come out in
-- lexicographic order of their row indices, and done_o goes high when the search
-- is finished.
--
-- For example, (n, k, t) = (9, 3, 2) gives 840 solutions with b = 12 rows each.
-- Each column is then in r = B(n-1,t-1) / B(k-1,t-1) = 4 rows. One solution is:
--
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
-- The number on the left is the row index, and column 0 is on the left.
--
-- Each solution is sent out on m_data_o as its b rows in increasing order, with
-- n bits for each row and one bit for each column. Row i of the solution is
-- m_data_o(i*n to i*n+n-1), with column 0 first, so m_data_o holds the picture
-- above without the row indices, one row after the other:
-- "111000000" & "100110000" & "100001100" & ... & "000011001".
--
-- See ALGORITHM.md for how the search works, and how it is built to run at a high
-- clock frequency.

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
    -- One solution: b rows of n bits each, see above
    m_data_o  : out std_logic_vector(0 to binom(G_N, G_T) / binom(G_K, G_T) * G_N - 1);
    -- The search is finished and the last solution has been accepted
    done_o    : out std_logic := '0'
  );
end entity steiner;

architecture synthesis of steiner is

  -- A Steiner system can only exist if B(n-i,t-i) / B(k-i,t-i) is a whole number for
  -- every i from 0 to t-1. Other parameters are rejected, because b, r and C_L2 below
  -- would be rounded down, and the search would output sets of rows that aren't
  -- Steiner systems. This is checked once, at elaboration time. Vivado only checks
  -- it with "synth_design -assert".
  pure function check_parameters return boolean is
  begin
    assert G_N > G_K and G_K > G_T and G_T >= 1
      report "The parameters must satisfy n > k > t >= 1"
      severity failure;
    for i in 0 to G_T-1 loop
      assert binom(G_N-i, G_T-i) mod binom(G_K-i, G_T-i) = 0
        report "The parameters (n, k, t) = (" & to_string(G_N) & ", " & to_string(G_K) &
               ", " & to_string(G_T) & ") are not admissible: B(n-" & to_string(i) &
               ",t-" & to_string(i) & ") / B(k-" & to_string(i) & ",t-" & to_string(i) &
               ") is not a whole number"
        severity failure;
    end loop;
    return true;
  end function check_parameters;

  constant C_PARAMETERS_OK : boolean := check_parameters;

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

  -- One bit for each of the n columns of a row, with column 0 first
  subtype columns_t is std_logic_vector(0 to G_N-1);
  type columns_vec_t is array (natural range <>) of columns_t;

  -- The columns of each row. Rows are numbered in lexicographic order of their
  -- columns, so row "i" is found one column at a time: column "j" is in the row
  -- if "i" is less than the number of rows that have it, given the columns before.
  pure function columns_init return columns_vec_t is
    variable res : columns_vec_t(0 to C_NUM_ROWS-1);
    variable kk  : natural;
    variable ii  : natural;
  begin
    for i in res'range loop
      res(i) := (others => '0');
      kk     := G_K;
      ii     := i;
      for j in 0 to G_N-1 loop
        exit when kk = 0;
        if ii < binom(G_N-j-1, kk-1) then
          res(i)(j) := '1';
          kk        := kk - 1;
        else
          ii        := ii - binom(G_N-j-1, kk-1);
        end if;
      end loop;
    end loop;
    return res;
  end function columns_init;

  constant C_COLUMNS : columns_vec_t(0 to C_NUM_ROWS-1) := columns_init;

  -- Convert a one-hot vector to the columns of the row whose bit is set. This is
  -- just an OR for each column, of the rows that have it.
  pure function columns_of(arg : rows_t) return columns_t is
    variable res : columns_t;
  begin
    res := (others => '0');
    for i in 0 to C_NUM_ROWS-1 loop
      if arg(i) = '1' then
        res := res or C_COLUMNS(i);
      end if;
    end loop;
    return res;
  end function columns_of;

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

  -- The rows that fit with the first row of "cand" in each segment. Like the output
  -- of "valid", this only checks the rows from that row and up.
  signal seg_compat : rows_vec_t(0 to 2);

  -- The rows that fit with the first row in "cand"
  signal compat     : rows_t;

  -- Whether to place the first row in "cand"
  signal place      : std_logic;

  -- The number of rows placed so far, and some values derived from it. These are
  -- kept in registers to keep them out of the critical path.
  signal depth      : natural range 0 to C_B;
  signal depth_m1   : natural range 0 to C_B-1; -- depth - 1, or 0 when depth = 0
  signal empty      : std_logic;                -- depth = 0
  signal full       : std_logic;                -- depth = C_B
  signal allow1     : std_logic;                -- depth >= C_R
  signal allow2     : std_logic;                -- depth >= 2*C_R-C_L2

  -- Entry "d" of "positions" is the columns of the row placed when "d" rows had
  -- already been placed, and entry "d" of the stack is the rows that remain to be
  -- tried in its place afterwards. The stack is only ever read at entry "depth-1",
  -- so it fits in distributed RAM.
  signal stack      : rows_vec_t(0 to C_B-1);
  signal positions  : columns_vec_t(0 to C_B-1);

  -- Writing to the stack and to "positions" is delayed by one clock cycle, to keep it
  -- out of the critical path. These registers hold the values needed for the write,
  -- after a row was placed in the previous clock cycle. They are loaded every clock
  -- cycle, so they don't depend on the decision to place a row.
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
  -- * If all rows are placed: Sends the solution and removes the last row, or waits
  --   if the previous solution hasn't been accepted yet.
  -- * Places the first remaining candidate row, if the early pruning allows it.
  -- * Removes the last row, if there are no candidates left.
  -- * Sets done_o, if there are no candidates left and no rows placed, once the last
  --   solution has been accepted.
  main_proc : process (clk_i)
    variable solution : columns_vec_t(0 to C_B-1);

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
      -- When "depth" is C_B, no row is placed, so "placed_depth" is not used
      placed_depth <= minimum(depth, C_B-1);
      placed_cand  <= cand;
      placed_seg   <= seg_lowest;
      placed_any   <= any(0 to 1);
      if placed = '1' then
        stack(placed_depth)     <= placed_rest;
        positions(placed_depth) <= columns_of(placed_row);
      end if;

      if full = '1' then
        -- Wait until the previous solution has been accepted
        if m_valid_o = '0' or m_ready_i = '1' then
          solution := positions;
          if placed = '1' then
            solution(placed_depth) := columns_of(placed_row);
          end if;
          for i in solution'range loop
            m_data_o(i*G_N to i*G_N+G_N-1) <= solution(i);
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

