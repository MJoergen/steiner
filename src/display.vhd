-- This drives the eight-digit 7-segment display on the Nexys 4 DDR board. It shows a
-- decimal number given in BCD, with the leading zeros blank, so 0 is shown as a
-- single "0".
--
-- The digits share the segment lines, so they are lit one at a time, each for
-- 2**G_REFRESH clock cycles. With the default, at 190 MHz, each digit is lit about
-- 1450 times per second, which is fast enough not to flicker. The anodes and the
-- segments are active low, and the outputs are registered.
--
-- The segments are named as on the board:
--
--    -a-
--   f   b
--    -g-
--   e   c
--    -d-

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

entity display is
  generic (
    G_DIGITS  : positive := 8;
    G_REFRESH : positive := 17
  );
  port (
    clk_i   : in  std_logic;
    -- The number to show, with the least significant digit in bits 3 downto 0
    value_i : in  std_logic_vector(4 * G_DIGITS - 1 downto 0);
    -- One bit for each digit, with the rightmost digit in bit 0. Active low.
    an_o    : out std_logic_vector(G_DIGITS - 1 downto 0);
    -- Segments "a" to "g" in bits 0 to 6. Active low.
    seg_o   : out std_logic_vector(6 downto 0)
  );
end entity display;

architecture synthesis of display is

  -- The segments that are lit for each digit, "a" in bit 0
  type segments_t is array (0 to 15) of std_logic_vector(6 downto 0);

  constant C_SEGMENTS : segments_t := (
    0      => "0111111",
    1      => "0000110",
    2      => "1011011",
    3      => "1001111",
    4      => "1100110",
    5      => "1101101",
    6      => "1111101",
    7      => "0000111",
    8      => "1111111",
    9      => "1101111",
    others => "0000000"
  );

  -- Counts the clock cycles that the current digit has been lit
  signal refresh : unsigned(G_REFRESH - 1 downto 0) := (others => '0');
  signal digit   : natural range 0 to G_DIGITS - 1 := 0;

begin

  display_proc : process (clk_i)
    variable bcd   : natural range 0 to 15;
    variable blank : boolean;
  begin
    if rising_edge(clk_i) then
      refresh <= refresh + 1;
      if refresh = (refresh'range => '1') then
        if digit = G_DIGITS - 1 then
          digit <= 0;
        else
          digit <= digit + 1;
        end if;
      end if;

      bcd := to_integer(unsigned(value_i(4 * digit + 3 downto 4 * digit)));

      -- A digit is a leading zero if it and all the digits to its left are zero.
      -- The rightmost digit is always shown.
      blank := digit /= 0;
      for d in 1 to G_DIGITS - 1 loop
        if d >= digit and value_i(4 * d + 3 downto 4 * d) /= "0000" then
          blank := false;
        end if;
      end loop;

      an_o        <= (others => '1');
      an_o(digit) <= '0';
      if blank then
        seg_o <= (others => '1');
      else
        seg_o <= not C_SEGMENTS(bcd);
      end if;
    end if;
  end process display_proc;

end architecture synthesis;
