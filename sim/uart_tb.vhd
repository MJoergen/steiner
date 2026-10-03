-- Testbench for uart.vhd. It checks that:
-- * Every byte value is received correctly, when the transmitter is connected to
--   the receiver.
-- * Every edge in a transmitted frame is a whole number of bit periods after the
--   start bit.
-- * When the receiver is stalled, the byte on rx_data_o is held, and the next byte
--   is dropped.
-- * A glitch shorter than half a bit is ignored.
-- * A frame whose stop bit is low is dropped.
-- * The receiver still works after a glitch and after a framing error.
-- The simulation fails at the first check that fails.

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

entity uart_tb is
  generic (
    G_DIVISOR : natural := 16
  );
end entity uart_tb;

architecture simulation of uart_tb is

  constant C_PERIOD : time := 10 ns;
  constant C_BIT    : time := G_DIVISOR * C_PERIOD;

  -- The longest low pulse on the receive line that must be ignored
  constant C_GLITCH : time := maximum(1, G_DIVISOR / 4) * C_PERIOD;

  signal clk      : std_logic := '0';
  signal rst      : std_logic := '1';
  signal done     : std_logic := '0';
  signal tx_valid : std_logic := '0';
  signal tx_ready : std_logic;
  signal tx_data  : std_logic_vector(7 downto 0);
  signal rx_valid : std_logic;
  signal rx_ready : std_logic := '0';
  signal rx_data  : std_logic_vector(7 downto 0);

  -- The receive line is either the transmit line, or driven directly by the test
  signal loopback : boolean   := true;
  signal tx_line  : std_logic;
  signal rx_line  : std_logic;
  signal rx_drive : std_logic := '1';

begin

  clk <= not done and not clk after C_PERIOD / 2;
  rst <= '1', '0' after 100 ns;

  rx_line <= tx_line when loopback else
             rx_drive;

  uart_inst : entity work.uart
    generic map (
      G_DIVISOR => G_DIVISOR
    )
    port map (
      clk_i      => clk,
      rst_i      => rst,
      tx_valid_i => tx_valid,
      tx_ready_o => tx_ready,
      tx_data_i  => tx_data,
      rx_valid_o => rx_valid,
      rx_ready_i => rx_ready,
      rx_data_o  => rx_data,
      uart_tx_o  => tx_line,
      uart_rx_i  => rx_line
    ); -- uart_inst

  -- A frame lasts 10 bits, with its last edge at most 9 bits after the start bit, so
  -- a falling edge at least 10 bits after the start bit is the next start bit
  tx_timing_proc : process
    variable start : time := -10 * C_BIT;
  begin
    wait on tx_line;
    if tx_line = '0' and now - start >= 10 * C_BIT then
      start := now;
    end if;
    assert ((now - start) / C_PERIOD) mod G_DIVISOR = 0
      report "Transmit edge " & to_string((now - start) / C_PERIOD) &
             " clock cycles after the start bit"
      severity failure;
  end process tx_timing_proc;

  test_proc : process

    procedure send (byte : std_logic_vector(7 downto 0)) is
    begin
      tx_data  <= byte;
      tx_valid <= '1';
      wait until rising_edge(clk) and tx_ready = '1' for 20 * C_BIT;
      assert tx_ready = '1'
        report "Transmitter did not accept " & to_hstring(byte)
        severity failure;
      tx_valid <= '0';
    end procedure send;

    -- Drive a frame, LSB first, onto the receive line
    procedure drive (frame : std_logic_vector(9 downto 0)) is
    begin
      for i in 0 to 9 loop
        rx_drive <= frame(i);
        wait for C_BIT;
      end loop;
      rx_drive <= '1';
    end procedure drive;

    procedure expect (byte : std_logic_vector(7 downto 0)) is
    begin
      rx_ready <= '1';
      wait until rising_edge(clk) and rx_valid = '1' for 20 * C_BIT;
      assert rx_valid = '1'
        report "Received nothing, expected " & to_hstring(byte)
        severity failure;
      assert rx_data = byte
        report "Received " & to_hstring(rx_data) & ", expected " & to_hstring(byte)
        severity failure;
      wait until rising_edge(clk);
      rx_ready <= '0';
    end procedure expect;

    procedure expect_nothing is
    begin
      rx_ready <= '1';
      wait until rising_edge(clk) and rx_valid = '1' for 15 * C_BIT;
      assert rx_valid = '0'
        report "Received " & to_hstring(rx_data) & ", expected nothing"
        severity failure;
      rx_ready <= '0';
    end procedure expect_nothing;

  begin
    wait until rst = '0';
    wait until rising_edge(clk);

    for i in 0 to 255 loop
      send(std_logic_vector(to_unsigned(i, 8)));
      expect(std_logic_vector(to_unsigned(i, 8)));
    end loop;

    -- Send two bytes while the receiver is stalled
    send(x"A5");
    send(x"5A");
    wait for 25 * C_BIT;
    assert rx_valid = '1' and rx_data = x"A5"
      report "First byte not held while the receiver is stalled"
      severity failure;
    wait until rising_edge(clk);
    expect(x"A5");
    expect_nothing;

    loopback <= false;
    wait for C_PERIOD;

    rx_drive <= '0';
    wait for C_GLITCH;
    rx_drive <= '1';
    expect_nothing;
    drive("1" & x"C3" & "0");
    expect(x"C3");

    drive("0" & x"81" & "0");
    wait for 3 * C_BIT;
    expect_nothing;
    drive("1" & x"FF" & "0");
    expect(x"FF");

    report "PASS: G_DIVISOR = " & to_string(G_DIVISOR);
    done <= '1';
    wait;
  end process test_proc;

end architecture simulation;
