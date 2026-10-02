-- This converts each solution from steiner.vhd into ASCII text, one character at a
-- time, e.g. for the transmitter in uart.vhd. Each row of the solution becomes one
-- line, in the same layout as the example in the header of steiner.vhd:
--
--  0 ***......
-- 13 *..**....
-- ...
--
-- The row index is right-aligned, and as wide as the largest row index. Each line
-- ends with CR LF, and each solution is followed by an empty line.
--
-- The row index isn't part of the solution, so it is calculated from the columns of
-- the row, one column per clock cycle. Rows are numbered in lexicographic order of
-- their columns, so the index of a row is the number of rows that come before it:
-- For each column "j" that is not in the row, while "i" of the row's "k" columns
-- have been seen, there are B(n-1-j, k-1-i) rows that have the same columns before
-- "j", and also have column "j". The index is then converted to decimal by repeated
-- subtraction. This takes a few clock cycles for each row, which is nothing
-- compared to the time it takes to send a line over a UART.

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
library work;
  use work.steiner_pkg.all;

entity steiner2uart is
  generic (
    G_N : natural := 9;
    G_K : natural := 3;
    G_T : natural := 2
  );
  port (
    clk_i     : in  std_logic;
    rst_i     : in  std_logic;
    -- The solutions from steiner.vhd
    s_valid_i : in  std_logic;
    s_ready_o : out std_logic;
    s_data_i  : in  std_logic_vector(0 to binom(G_N, G_T) / binom(G_K, G_T) * G_N - 1);
    -- One ASCII character at a time
    m_valid_o : out std_logic;
    m_ready_i : in  std_logic;
    m_data_o  : out std_logic_vector(7 downto 0)
  );
end entity steiner2uart;

architecture synthesis of steiner2uart is

  constant C_NUM_ROWS : natural := binom(G_N, G_K);
  constant C_B        : natural := binom(G_N, G_T) / binom(G_K, G_T);

  -- The number of decimal digits in the largest row index
  pure function calc_digits return natural is
    variable res : natural := 1;
    variable val : natural := (C_NUM_ROWS - 1) / 10;
  begin
    while val > 0 loop
      res := res + 1;
      val := val / 10;
    end loop;
    return res;
  end function calc_digits;

  constant C_DIGITS : natural := calc_digits;

  -- A line is the row index, a space, one character for each column, and CR LF
  constant C_LINE : natural := C_DIGITS + 1 + G_N + 2;

  subtype char_t is std_logic_vector(7 downto 0);
  type chars_t is array (natural range <>) of char_t;

  pure function to_char(c : character) return char_t is
  begin
    return std_logic_vector(to_unsigned(character'pos(c), 8));
  end function to_char;

  constant C_CR : char_t := X"0D";
  constant C_LF : char_t := X"0A";

  -- The characters of a line that are the same for every row
  pure function line_init return chars_t is
    variable res : chars_t(0 to C_LINE-1) := (others => to_char(' '));
  begin
    res(C_LINE-2) := C_CR;
    res(C_LINE-1) := C_LF;
    return res;
  end function line_init;

  constant C_LINE_INIT : chars_t(0 to C_LINE-1) := line_init;

  -- The number of rows that have column "j", and the same columns before "j" as a
  -- row that has "i" columns before "j", but not "j" itself
  type weights_t is array (natural range <>, natural range <>) of natural;

  pure function weights_init return weights_t is
    variable res : weights_t(0 to G_N-1, 0 to G_N) := (others => (others => 0));
  begin
    for j in 0 to G_N-1 loop
      for i in 0 to G_K-1 loop
        res(j, i) := binom(G_N-1-j, G_K-1-i);
      end loop;
    end loop;
    return res;
  end function weights_init;

  constant C_WEIGHTS : weights_t(0 to G_N-1, 0 to G_N) := weights_init;

  type powers_t is array (natural range <>) of natural;

  pure function powers_init return powers_t is
    variable res : powers_t(0 to C_DIGITS-1);
  begin
    res(0) := 1;
    for d in 1 to C_DIGITS-1 loop
      res(d) := res(d-1) * 10;
    end loop;
    return res;
  end function powers_init;

  constant C_POWERS : powers_t(0 to C_DIGITS-1) := powers_init;

  type state_type is (
    IDLE_ST,     -- Wait for a solution
    INDEX_ST,    -- Find the index of the current row, one column per clock cycle
    DECIMAL_ST,  -- Convert the index to decimal, one subtraction per clock cycle
    SEND_ST      -- Send the line, one character at a time
  );

  signal state : state_type := IDLE_ST;

  -- The rows that have not been sent yet, with the current row first
  signal rows   : std_logic_vector(s_data_i'range);
  signal row    : natural range 0 to C_B;
  signal column : natural range 0 to G_N-1;
  signal ones   : natural range 0 to G_N;
  signal index  : natural range 0 to C_NUM_ROWS-1;
  signal pos    : natural range 0 to C_DIGITS-1;
  signal digit  : natural range 0 to 9;

  -- Whether all the digits so far are leading zeros, which are shown as spaces
  signal leading : boolean;

  -- The characters of the line that have not been sent yet, and how many there are
  signal line      : chars_t(0 to C_LINE-1);
  signal remaining : natural range 0 to C_LINE;

begin

  s_ready_o <= '1' when state = IDLE_ST else
               '0';
  m_valid_o <= '1' when state = SEND_ST else
               '0';
  m_data_o  <= line(0);

  fsm_proc : process (clk_i)
  begin
    if rising_edge(clk_i) then

      case state is

        when IDLE_ST =>
          if s_valid_i = '1' then
            rows   <= s_data_i;
            row    <= 0;
            column <= 0;
            ones   <= 0;
            index  <= 0;
            line   <= C_LINE_INIT;
            state  <= INDEX_ST;
          end if;

        when INDEX_ST =>
          if rows(column) = '1' then
            line(C_DIGITS + 1 + column) <= to_char('*');
            ones                        <= ones + 1;
          else
            line(C_DIGITS + 1 + column) <= to_char('.');
            index                       <= index + C_WEIGHTS(column, ones);
          end if;
          if column = G_N-1 then
            pos     <= C_DIGITS-1;
            digit   <= 0;
            leading <= true;
            state   <= DECIMAL_ST;
          else
            column <= column + 1;
          end if;

        when DECIMAL_ST =>
          if index >= C_POWERS(pos) then
            index <= index - C_POWERS(pos);
            digit <= digit + 1;
          else
            if digit = 0 and leading and pos /= 0 then
              line(C_DIGITS-1-pos) <= to_char(' ');
            else
              line(C_DIGITS-1-pos) <= to_char(character'val(character'pos('0') + digit));
              leading              <= false;
            end if;
            digit <= 0;
            if pos = 0 then
              remaining <= C_LINE;
              state     <= SEND_ST;
            else
              pos <= pos - 1;
            end if;
          end if;

        when SEND_ST =>
          if m_ready_i = '1' then
            line      <= line(1 to C_LINE-1) & to_char(' ');
            remaining <= remaining - 1;
            if remaining = 1 then
              if row < C_B-1 then
                -- Go to the next row
                rows   <= rows(G_N to rows'high) & rows(0 to G_N-1);
                row    <= row + 1;
                column <= 0;
                ones   <= 0;
                index  <= 0;
                line   <= C_LINE_INIT;
                state  <= INDEX_ST;
              elsif row = C_B-1 then
                -- Send an empty line after the last row
                row       <= C_B;
                line(0)   <= C_CR;
                line(1)   <= C_LF;
                remaining <= 2;
              else
                state <= IDLE_ST;
              end if;
            end if;
          end if;

      end case;

      if rst_i = '1' then
        state <= IDLE_ST;
      end if;
    end if;
  end process fsm_proc;

end architecture synthesis;
