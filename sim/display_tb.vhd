-- Testbench for display.vhd. For each value in C_VALUES, it watches the display for
-- two full rounds of the digits, decodes what is lit, and checks that:
-- * Exactly one digit is lit at a time, and each digit is lit in turn.
-- * Each digit shows the right decimal digit, and the leading zeros are blank.
-- The simulation fails at the first check that fails.

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

entity display_tb is
  generic (
    G_DIGITS  : positive := 8;
    G_REFRESH : positive := 2
  );
end entity display_tb;

architecture simulation of display_tb is

  constant C_PERIOD : time := 10 ns;

  type values_t is array (natural range <>) of natural;

  constant C_VALUES : values_t := (0, 7, 10, 840, 1234567, 10000001, 99999999);

  signal clk     : std_logic := '0';
  signal done    : std_logic := '0';
  signal value   : std_logic_vector(4 * G_DIGITS - 1 downto 0);
  signal an      : std_logic_vector(G_DIGITS - 1 downto 0);
  signal seg     : std_logic_vector(6 downto 0);

  pure function to_bcd(arg : natural) return std_logic_vector is
    variable res : std_logic_vector(4 * G_DIGITS - 1 downto 0);
    variable val : natural := arg;
  begin
    for d in 0 to G_DIGITS - 1 loop
      res(4 * d + 3 downto 4 * d) := std_logic_vector(to_unsigned(val mod 10, 4));
      val                         := val / 10;
    end loop;
    return res;
  end function to_bcd;

  -- The character shown by the segments, "a" in bit 0, or '?' if it isn't a digit
  pure function decode(arg : std_logic_vector(6 downto 0)) return character is
  begin
    case not arg is
      when "0000000" => return ' ';
      when "0111111" => return '0';
      when "0000110" => return '1';
      when "1011011" => return '2';
      when "1001111" => return '3';
      when "1100110" => return '4';
      when "1101101" => return '5';
      when "1111101" => return '6';
      when "0000111" => return '7';
      when "1111111" => return '8';
      when "1101111" => return '9';
      when others    => return '?';
    end case;
  end function decode;

  -- The expected text, right-aligned, with the leftmost digit first
  pure function expected(arg : natural) return string is
    variable res : string(1 to G_DIGITS) := (others => ' ');
    variable val : natural := arg;
  begin
    for i in G_DIGITS downto 1 loop
      res(i) := character'val(character'pos('0') + val mod 10);
      val    := val / 10;
      exit when val = 0;
    end loop;
    return res;
  end function expected;

begin

  clk <= not done and not clk after C_PERIOD / 2;

  display_inst : entity work.display
    generic map (
      G_DIGITS  => G_DIGITS,
      G_REFRESH => G_REFRESH
    )
    port map (
      clk_i   => clk,
      value_i => value,
      an_o    => an,
      seg_o   => seg
    ); -- display_inst

  test_proc : process
    variable shown : string(1 to G_DIGITS);
    variable lit   : natural;
    variable count : natural;
    variable prev  : natural;
  begin
    for v in C_VALUES'range loop
      value <= to_bcd(C_VALUES(v));
      -- Wait for the outputs to show the new value
      wait until rising_edge(clk);
      wait until rising_edge(clk);
      shown := (others => '-');
      prev  := G_DIGITS;
      for c in 1 to 2 * G_DIGITS * 2**G_REFRESH loop
        wait until rising_edge(clk);
        wait for 1 ns;
        lit   := G_DIGITS;
        count := 0;
        for d in 0 to G_DIGITS - 1 loop
          if an(d) = '0' then
            lit   := d;
            count := count + 1;
          end if;
        end loop;
        assert count = 1
          report "Not exactly one digit is lit"
          severity failure;
        assert prev = G_DIGITS or lit = prev or lit = (prev + 1) mod G_DIGITS
          report "The digits are not lit in turn"
          severity failure;
        prev                  := lit;
        shown(G_DIGITS - lit) := decode(seg);
      end loop;
      assert shown = expected(C_VALUES(v))
        report "Showed """ & shown & """ for " & integer'image(C_VALUES(v))
        severity failure;
      report "Showed """ & shown & """";
    end loop;
    report "Test finished";
    done <= '1';
    wait;
  end process test_proc;

end architecture simulation;
