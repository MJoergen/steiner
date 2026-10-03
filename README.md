# steiner

[![sim](https://github.com/MJoergen/steiner/actions/workflows/sim.yml/badge.svg)](https://github.com/MJoergen/steiner/actions/workflows/sim.yml)
[![formal](https://github.com/MJoergen/steiner/actions/workflows/formal.yml/badge.svg)](https://github.com/MJoergen/steiner/actions/workflows/formal.yml)

An FPGA design, written in VHDL, that finds every
[Steiner system](https://en.wikipedia.org/wiki/Steiner_system) S(t, k, n) for given
parameters by searching all possibilities in hardware. The project was inspired by
[this video](https://www.youtube.com/watch?v=4xnRZqD7rAo).

On the Nexys 4 DDR board it runs at 180 MHz, and finds all 840 solutions for
`(n, k, t) = (9, 3, 2)` in 0.69 ms.

## The problem

Given numbers `n > k > t >= 1`, find every set of rows where:

* each row has length `n`,
* each row contains exactly `k` ones, and
* any two rows AND'ed together contain fewer than `t` ones.

So every set of `t` columns is covered by at most one row. A set with the largest
possible number of rows, `b = B(n,t) / B(k,t)`, covers every set of `t` columns
exactly once, which makes it a Steiner system. Each column then contains exactly
`r = B(n-1,t-1) / B(k-1,t-1)` ones. Here `B(n,k)` is the binomial coefficient
"n choose k".

A Steiner system can only exist if `b`, `r`, and in general `B(n-i,t-i) / B(k-i,t-i)`
for every `i` from 0 to `t-1`, are whole numbers. Parameters that meet these
conditions are called admissible. For example, `(n, 3, 2)` is admissible when `n` is
1 or 3 modulo 6, and `(n, k, 1)` when `k` divides `n`. The design only accepts
admissible parameters, and stops with an error otherwise, see
[Admissible parameters](ALGORITHM.md#admissible-parameters).

For example, with `(n, k, t) = (7, 3, 2)` there are `b = 7` rows and `r = 3`. One of
the solutions is the [Fano plane](https://en.wikipedia.org/wiki/Fano_plane):

```
 0 ***....
 9 *..**..
14 *....**
20 .*.*.*.
23 .*..*.*
27 ..**..*
28 ..*.**.
```

The number on the left is the row's index. All `B(n,k)` rows with `k` ones are
numbered in lexicographic order of their columns, so index 0 is `{0,1,2}`, index 1 is
`{0,1,3}`, and so on. Column 0 is printed on the left.

The known results are:

| (n, k, t) | b  | r | Solutions | File                                 |
|-----------|----|---|-----------|--------------------------------------|
| (7, 3, 2) | 7  | 3 | 30        | [result_7_3_2.txt](result_7_3_2.txt) |
| (9, 3, 2) | 12 | 4 | 840       | [result_9_3_2.txt](result_9_3_2.txt) |
| (8, 4, 3) | 14 | 7 | 30        | [result_8_4_3.txt](result_8_4_3.txt) |

Each line in these files is one solution, as the list of its row indices.

## The algorithm

The design does a depth-first search with backtracking, placing rows in increasing
order. It keeps the rows that can still be tried as a bit vector, with one bit for
each row. Each clock cycle it either places the first of these rows, removing the
rows that conflict with it, or it backtracks. So each clock cycle visits one node
of the search tree: 124,586 clock cycles for `(9, 3, 2)`. The search also prunes
early, using the fact that the first `r` rows of a solution must have column 0,
and the next rows must have column 1.

[ALGORITHM.md](ALGORITHM.md) explains the algorithm in detail: the search and why it
works, the early pruning, how the design is built to run at 180 MHz, and what limits
the clock frequency.

## Files

| File                                       | Description                                              |
|--------------------------------------------|----------------------------------------------------------|
| [`steiner.vhd`](steiner.vhd)               | The search.                                              |
| [`valid.vhd`](valid.vhd)                   | The rows that don't conflict with a given row.           |
| [`steiner_pkg.vhd`](steiner_pkg.vhd)       | Binomial coefficient function.                           |
| [`steiner2uart.vhd`](steiner2uart.vhd)     | Converts each solution to text, see [Synthesis](#synthesis). |
| [`uart.vhd`](uart.vhd)                     | UART that sends the text.                                |
| [`steiner2uart_tb.vhd`](steiner2uart_tb.vhd) | Testbench for `steiner2uart.vhd`, see [Simulation](#simulation). |
| [`uart_tb.vhd`](uart_tb.vhd)               | Testbench for `uart.vhd`, run by `make uart`.            |
| [`steiner_tb.vhd`](steiner_tb.vhd)         | Testbench, see [Simulation](#simulation).                |
| [`steiner_tb.gtkw`](steiner_tb.gtkw)       | GTKWave setup for viewing the waveform from `make sim`.  |
| [`steiner_ref.py`](steiner_ref.py)         | Reference model in Python, see [Simulation](#simulation). |
| [`formal/`](formal)                        | Formal verification, see [Formal verification](#formal-verification). |
| [`nexys4ddr.vhd`](nexys4ddr.vhd), [`nexys4ddr.xdc`](nexys4ddr.xdc) | Top level and constraints for the Nexys 4 DDR board, see [Synthesis](#synthesis). |
| [`clk_rst.vhd`](clk_rst.vhd)               | Clock and reset for the Nexys 4 DDR board.               |
| `result_*.txt`                             | All solutions for the parameters in the file name.       |
| [`ALGORITHM.md`](ALGORITHM.md)             | Detailed explanation of the algorithm and its timing.    |
| [`Makefile`](Makefile)                     | Runs the simulation, the formal verification, and the synthesis, see [Running](#running). |
| [`.github/workflows/`](.github/workflows)  | The CI, see [Running](#running).                         |
| [`LICENSE`](LICENSE)                       | The MIT license.                                         |

## Interface

The generics `G_N`, `G_K` and `G_T` are the parameters `n`, `k` and `t`.

| Port                    | Direction | Description                                                        |
|-------------------------|-----------|--------------------------------------------------------------------|
| `clk_i`                 | in        | Clock.                                                             |
| `rst_i`                 | in        | Synchronous reset, active high. The search starts after the reset. |
| `m_valid_o`, `m_ready_i`| out, in   | AXI-style handshake of the solutions.                              |
| `m_data_o`              | out       | One solution: its `b` rows of `n` bits each, see below.            |
| `done_o`                | out       | The search is finished, and the last solution has been accepted.   |

`m_data_o` has `b * n` bits, `n` bits for each row of the solution, with one bit for
each column. The rows come in increasing order of their index. Row `i` of the
solution is `m_data_o(i*n to i*n+n-1)`, with column 0 first. So for the Fano plane
above, `m_data_o` is the picture without the row indices, one row after the other:

```
"1110000" & "1001100" & "1000011" & "0101010" & "0100101" & "0011001" & "0010110"
```

The solutions come out in lexicographic order of their row indices. While a
solution is waiting to be accepted, the search pauses.

## Running

Type `make` to list the supported targets:

* `make sim` runs the testbench, see [Simulation](#simulation). This requires
  [GHDL](https://github.com/ghdl/ghdl). It takes about 10 seconds.
  `make sim N=7 K=3 T=2` selects other parameters.
* `make check` runs the testbench for each parameter set in `CHECK` in the
  `Makefile`, and compares the solutions, and the text from `steiner2uart.vhd`, with
  the reference model, see
  [Simulation](#simulation). This also requires Python 3. It takes about 20 seconds.
* `make uart` runs the testbench of the UART, for each clock divisor in
  `UART_DIVISORS` in the `Makefile`. This requires GHDL.
* `make show` shows the waveform from `make sim` in
  [GTKWave](https://gtkwave.sourceforge.net/).
* `make formal` runs the formal verification, see
  [Formal verification](#formal-verification). This requires
  [SymbiYosys](https://github.com/YosysHQ/sby), Yosys with the
  [GHDL plugin](https://github.com/ghdl/ghdl-yosys-plugin), and an SMT solver. The
  [OSS CAD Suite](https://github.com/YosysHQ/oss-cad-suite-build) has all of them.
  It takes about 1 minute.
* `make vivado` builds the bitstream for the board, see [Synthesis](#synthesis). It
  expects Vivado 2025.1 in `/opt/Xilinx/2025.1/Vivado` (the variable `XILINX_DIR`),
  and takes about 2 minutes.
* `make clean` removes the generated files.

The CI runs `make check` ([`sim.yml`](.github/workflows/sim.yml)) and `make formal`
([`formal.yml`](.github/workflows/formal.yml)) for every push to `main` and every
pull request.

## Simulation

The testbench runs the search to the end, finds the index of each row of
`m_data_o`, and writes the solutions to `steiner_tb.txt` in the same format as the
results files. It holds `m_ready_i` low
for random periods, so that the search has to wait. It checks each solution with
its own table of rows, independently of `valid.vhd`, and fails if:

* a row doesn't have `k` ones, or the row indices aren't strictly increasing,
* two rows in a solution conflict,
* a set of `t` columns isn't in exactly one row of a solution, i.e. it isn't a
  Steiner system,
* a solution doesn't come after the previous one in lexicographic order,
* the search hasn't finished after `G_TIMEOUT` (1100 ms of simulated time), or
* the number of solutions is wrong for one of the known results.

For other parameters it prints the number of solutions as a warning. If you find a
new result, add it to `expected_count` in `steiner_tb.vhd`. For larger parameters
you may need to raise `G_TIMEOUT`. GHDL can't set it from the command line, so edit
its default value in `steiner_tb.vhd`.

These checks can't tell whether a solution is missing. So `make check` also
compares the solutions with those of [`steiner_ref.py`](steiner_ref.py), and with
the results file if there is one. The reference model works completely differently
from the design: It finds the Steiner systems as an exact cover, where every set of
`t` columns must be in exactly one row, and doesn't use any early pruning. `CHECK`
holds every admissible parameter set with `n <= 10`, except `(10, 4, 3)`, which takes
over an hour to simulate. (It has 2520 solutions, and they match too.)

For each parameter set, `make check` also runs
[`steiner2uart_tb.vhd`](steiner2uart_tb.vhd), which converts every solution to text
with `steiner2uart.vhd`, and compares the text with that of
`steiner_ref.py --text`. It accepts the characters at random, so the search has to
wait, and fails if a character changes while it is waiting to be accepted.

## Formal verification

The properties in [`formal/steiner.psl`](formal/steiner.psl) are proven for all
reachable states by k-induction, with the parameters `(4, 2, 1)`, `(7, 3, 2)` and
`(8, 4, 3)`:

* The output holds `m_valid_o` and `m_data_o` until the solution is accepted.
* `done_o` stays high once set, and is never high while a solution is waiting.
* Every solution is valid: every row has `k` ones, the row indices are strictly
  increasing, and no two rows conflict.
* The state of the search is consistent, and no rows are lost: the candidates and
  every stack entry hold exactly the rows they should, see
  [Why it works](ALGORITHM.md#why-it-works).

With `(4, 2, 1)` the whole search takes about 15 clock cycles, so the `bmc` and
`cover` tasks also run it to the end. To run one task and look at a failing trace:

```
cd formal
sby --yosys "yosys -m ghdl" -f steiner.sby prove_421
gtkwave steiner_prove_421/engine_0/trace_induct.vcd
```

## Synthesis

`make vivado` builds `nexys4ddr.bit` for the Artix-7 `xc7a100tcsg324-1` on the
Nexys 4 DDR board. It stops with an error if the parameters aren't admissible, or if
the design doesn't meet timing. The timing report is in `nexys4ddr_timing.rpt`.

In the top level `nexys4ddr.vhd`, `clk_rst.vhd` makes a 180 MHz clock from the
100 MHz board clock with an MMCM, and turns the `CPU_RESETN` button into a
synchronous reset. The
search starts when the MMCM has locked, and again whenever you press the button.
LED0 shows `m_valid_o` and LED1 shows `done_o`. The parameters are set by the
constants `C_N`, `C_K` and `C_T` in `nexys4ddr.vhd`.

Each solution is sent as text over the board's USB-UART, at 115200 baud with 8N1,
in the same layout as the example above: one line for each row, with its index, and
an empty line after each solution. Lines end with CR LF. The search waits while a
solution is being sent, so on the board it takes about 12 seconds to send all 840
solutions for `(9, 3, 2)`, rather than 0.69 ms.

## License

See [LICENSE](LICENSE).
