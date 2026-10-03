-- This is a simple UART with the frame format 8N1: One start bit, eight data bits
-- sent LSB first, no parity bit, and one stop bit.
-- * G_DIVISOR is the number of clock cycles per bit, i.e. the clock frequency divided
--   by the baud rate. It must be at least 2.
-- * The transmitter accepts a byte when tx_valid_i and tx_ready_o are both high.
--   tx_ready_o is low while the byte is being sent.
-- * The receiver samples each bit once, in the middle of the bit. If the start bit is
--   no longer low in the middle, it is ignored as a glitch. If the stop bit is low,
--   the byte is dropped as a framing error.
-- * The receiver holds each byte on rx_data_o with rx_valid_o high until rx_ready_i
--   is high. A UART can not be stalled, so if the previous byte has not been
--   accepted when a new byte is complete, the new byte is dropped.
-- * uart_rx_i is synchronized to the clock here, so it can come directly from a pin.
-- * rst_i is synchronous and active high.

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

entity uart is
  generic (
    G_DIVISOR : natural range 2 to natural'high
  );
  port (
    clk_i      : in  std_logic;
    rst_i      : in  std_logic;
    tx_valid_i : in  std_logic;
    tx_ready_o : out std_logic;
    tx_data_i  : in  std_logic_vector(7 downto 0);
    rx_valid_o : out std_logic;
    rx_ready_i : in  std_logic;
    rx_data_o  : out std_logic_vector(7 downto 0);
    uart_tx_o  : out std_logic := '1';   -- Transmit line, idle high
    uart_rx_i  : in  std_logic           -- Receive line, idle high, asynchronous
  );
end entity uart;

architecture synthesis of uart is

  type state_type is (
    IDLE_ST,
    BUSY_ST
  );

  -- The frame being sent, LSB first. Zeros are shifted in, so the frame is done
  -- when only the stop bit is left.
  signal tx_data    : std_logic_vector(9 downto 0) := (others => '1');
  signal tx_state   : state_type := IDLE_ST;
  signal tx_counter : natural range 0 to G_DIVISOR - 1;

  signal uart_tx : std_logic;

  -- Synchronize the asynchronous receive line to the clock
  signal rx_sync : std_logic_vector(1 downto 0) := (others => '1');

  attribute async_reg : string;
  attribute async_reg of rx_sync : signal is "true";

  signal uart_rx : std_logic;

  -- rx_bit is the bit that is sampled next: 0 is the start bit, 1 to 8 are the
  -- data bits, and 9 is the stop bit
  signal rx_data    : std_logic_vector(7 downto 0);
  signal rx_state   : state_type := IDLE_ST;
  signal rx_counter : natural range 0 to G_DIVISOR - 1;
  signal rx_bit     : natural range 0 to 9;

begin

  tx_ready_o <= '1' when tx_state = IDLE_ST else
                '0';

  uart_tx    <= tx_data(0);

  tx_proc : process (clk_i)
  begin
    if rising_edge(clk_i) then
      uart_tx_o <= uart_tx;

      case tx_state is

        when IDLE_ST =>
          if tx_valid_i = '1' then
            tx_data    <= "1" & tx_data_i & "0";
            tx_counter <= G_DIVISOR - 1;
            tx_state   <= BUSY_ST;
          end if;

        when BUSY_ST =>
          if tx_counter > 0 then
            tx_counter <= tx_counter - 1;
          else
            if or (tx_data(9 downto 1)) = '1' then
              tx_counter <= G_DIVISOR - 1;
              tx_data    <= "0" & tx_data(9 downto 1);
            else
              tx_data  <= (others => '1');
              tx_state <= IDLE_ST;
            end if;
          end if;

      end case;

      if rst_i = '1' then
        tx_data    <= (others => '1');
        tx_state   <= IDLE_ST;
        tx_counter <= 0;
        uart_tx_o  <= '1';
      end if;
    end if;
  end process tx_proc;

  rx_sync_proc : process (clk_i)
  begin
    if rising_edge(clk_i) then
      rx_sync <= rx_sync(0) & uart_rx_i;
    end if;
  end process rx_sync_proc;

  uart_rx <= rx_sync(1);

  rx_proc : process (clk_i)
  begin
    if rising_edge(clk_i) then
      if rx_ready_i = '1' then
        rx_valid_o <= '0';
      end if;

      case rx_state is

        when IDLE_ST =>
          -- Wait until the middle of the start bit
          if uart_rx = '0' then
            rx_counter <= G_DIVISOR / 2 - 1;
            rx_bit     <= 0;
            rx_state   <= BUSY_ST;
          end if;

        when BUSY_ST =>
          if rx_counter > 0 then
            rx_counter <= rx_counter - 1;
          else
            rx_counter <= G_DIVISOR - 1;

            case rx_bit is

              when 0 =>
                if uart_rx = '1' then
                  rx_state <= IDLE_ST;
                end if;
                rx_bit <= 1;

              when 9 =>
                if uart_rx = '1' and (rx_valid_o = '0' or rx_ready_i = '1') then
                  rx_data_o  <= rx_data;
                  rx_valid_o <= '1';
                end if;
                rx_state <= IDLE_ST;

              when others =>
                rx_data <= uart_rx & rx_data(7 downto 1);
                rx_bit  <= rx_bit + 1;

            end case;

          end if;

      end case;

      if rst_i = '1' then
        rx_valid_o <= '0';
        rx_state   <= IDLE_ST;
        rx_counter <= 0;
        rx_bit     <= 0;
      end if;
    end if;
  end process rx_proc;

end architecture synthesis;
