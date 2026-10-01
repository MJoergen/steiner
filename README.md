# steiner

[![formal](https://github.com/MJoergen/steiner/actions/workflows/formal.yml/badge.svg)](https://github.com/MJoergen/steiner/actions/workflows/formal.yml)

An FPGA design, written in VHDL, that finds every
[Steiner system](https://en.wikipedia.org/wiki/Steiner_system) S(t, k, n) for given
parameters by searching all possibilities in hardware.

The project was inspired by [this video](https://www.youtube.com/watch?v=4xnRZqD7rAo).

## The problem

Given numbers `n > k > t`, find every set of rows where:

* each row has length `n`,
* each row contains exactly `k` ones, and
* any two rows AND'ed together contain fewer than `t` ones.

This means that every set of `t` columns is covered by at most one row. A set with
the largest possible number of rows covers every set of `t` columns exactly once,
which makes it a Steiner system. That number of rows is

    b = B(n,t) / B(k,t)

and each column then contains exactly

    r = B(n-1,t-1) / B(k-1,t-1)

ones. Here `B(n,k)` is the binomial coefficient "n choose k".

### Example: S(2, 3, 7)

With `(n, k, t) = (7, 3, 2)` we get `b = 21/3 = 7` rows and `r = 6/2 = 3`. One of
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

Each pair of columns appears together in exactly one row, and each column contains
exactly three `*`s.

The number on the left is the row's index. All `B(n,k)` rows with `k` ones are
numbered in lexicographic order of the column positions of their ones, so index 0 is
`{0,1,2}`, index 1 is `{0,1,3}`, and so on. Column 0 is printed on the left.

### Known results

| (n, k, t) | b  | r | Solutions | File                                     |
|-----------|----|---|-----------|------------------------------------------|
| (7, 3, 2) | 7  | 3 | 30        | [result_7_3_2.txt](result_7_3_2.txt)     |
| (9, 3, 2) | 12 | 4 | 840       | [result_9_3_2.txt](result_9_3_2.txt)     |

Each line in these files is one solution, written as the list of chosen row indices.

## How the search works

The design does a depth-first search with backtracking. It places rows one at a time
in increasing index order and stops when `b` rows have been placed.

* `valid.vhd`: At elaboration time this computes a constant table of all `B(n,k)`
  rows, and of which pairs of rows share `t` or more ones. Given one selected row as
  a one-hot vector, it outputs a bit vector that shows which of the `B(n,k)` rows
  can sit next to it, meaning they share fewer than `t` ones with it. The logic is
  purely combinational, and each output bit is just a small OR.
* `steiner.vhd`: Keeps a register `cand` with one bit for each of the `B(n,k)` rows.
  It holds the rows that can still be tried for the current position: the rows
  after the previously placed row that fit with every row placed so far. Each clock
  cycle the state machine does one of three things:
  * places the first row in `cand`, and ANDs `cand` with the output of `valid` for
    that row,
  * removes the most recently placed row when `cand` is empty, and restores `cand`
    from a stack, or
  * sends a solution, when all `b` rows are placed, and then removes the last row.

  So each clock cycle visits one node of the search tree, and no time is spent
  stepping past rows that don't fit. The stack has one entry for each placed row,
  holding the row index and the rows still left to try in its place.

  When all `b` rows are placed, the solution is sent out on an AXI-style stream
  (`m_valid_o`, `m_ready_i` and `m_data_o`), one solution at a time. If the previous
  solution hasn't been accepted yet, the search waits. When the whole search space
  has been covered and the last solution has been accepted, `done_o` goes high.

The search also prunes branches early. Each column appears in exactly `r` rows, and
rows are placed in increasing order. So the first `r` placed rows must all have
column 0 set. Column 1 has already shared one row with column 0, so the next `r-1`
rows must all have column 1 set. Any branch that breaks this rule is dropped at
once.

### Timing

The search logic is one loop: `cand` → find its first row → look up which rows
fit with it → `cand`. These things keep that loop short:

* The first row in `cand` is found with carry chains, as `x and -x`. The rows are
  split into three segments at the pruning boundaries above, so each carry chain
  is short. Each segment gets its own `valid` lookup, and only afterwards are the
  results combined, using whether the earlier segments are empty.
* The same per-segment "any row left" signals decide whether to place a row or
  backtrack.
* Values derived from the number of placed rows (empty, full, the pruning limits)
  are kept in registers.
* The stack is only read at the top, so it's held in distributed RAM. Writes to it
  are delayed by one clock cycle, with a bypass for when a row is removed right
  after being placed.

## Files

| File               | Description                                              |
|--------------------|----------------------------------------------------------|
| `steiner.vhd`      | Top level: search state machine                          |
| `steiner_pkg.vhd`  | Solution type and binomial coefficient function          |
| `valid.vhd`        | Compatibility lookup for a single selected row           |
| `steiner_tb.vhd`   | Testbench that runs the search to completion             |
| `nexys4ddr.vhd`    | Top level for the Nexys 4 DDR board: clock and reset     |
| `steiner_tb.gtkw`  | GTKWave layout for viewing the simulation waveform       |
| `nexys4ddr.xdc`    | Pin and clock constraints for the Nexys 4 DDR board      |
| `result_*.txt`     | All solutions found for the parameters in the file name  |
| `formal/`          | Formal verification of `steiner.vhd` using SymbiYosys    |

## Usage

Running `make` on its own shows the available targets:

```
make help        Show this help text (default)
make sim         Simulate the design using GHDL, writing steiner_tb.ghw
                 and checking each solution
make show        Show the simulation waveform using GTKWave
make formal      Run formal verification using SymbiYosys
make vivado      Synthesize the design using Vivado, writing nexys4ddr.bit
```

### Simulation

You need [GHDL](https://github.com/ghdl/ghdl) to simulate and
[GTKWave](https://gtkwave.sourceforge.net/) to view the waveform.

```
make sim
```

The testbench prints each solution as a report note, for example:

```
steiner_tb.vhd:148:9:@4175ns:(report note): [0, 13, 22, 27, 35, 41, 47, 53, 55, 59, 71, 76]
```

The testbench holds `m_ready_i` low for random periods, to check that the search
waits for each solution to be accepted.

The clock stops when `done_o` goes high, which ends the simulation. With the
default parameters `(9, 3, 2)` this happens after about 1.4 ms of simulated time,
or roughly 140,000 clock cycles.

The testbench checks each solution as it arrives, using its own table of rows
rather than the one in `valid.vhd`. `make sim` fails if:

* a row index is out of range, or the row indices aren't strictly increasing,
* two rows in a solution share `t` or more ones,
* a solution doesn't come after the previous one in lexicographic order, which
  would mean a solution was sent twice,
* the search hasn't finished after `G_TIMEOUT` (1100 ms of simulated time, set in
  `steiner_tb.vhd`), or
* the number of solutions is wrong for one of the known results.

For other parameters the testbench prints the number of solutions as a warning,
because it doesn't know the expected number. If you find a new result, add it to
`expected_count` in `steiner_tb.vhd`.

The testbench also writes the solutions to `steiner_tb.txt` in the same format as
the results files.

To search for other parameters, set `N`, `K` and `T` on the command line:

```
make sim N=7 K=3 T=2
```

For larger parameters you may also need to raise `G_TIMEOUT`.

### Formal verification

You need [SymbiYosys](https://github.com/YosysHQ/sby), Yosys with the
[GHDL plugin](https://github.com/ghdl/ghdl-yosys-plugin), and an SMT solver. The
[OSS CAD Suite](https://github.com/YosysHQ/oss-cad-suite-build) has all of them.

```
make formal
```

This runs `make -C formal`, which runs SymbiYosys on `formal/steiner.sby`. The
properties are in `formal/steiner.psl`. They check that:

* the output stream holds `m_valid_o` and `m_data_o` stable until the solution is
  accepted,
* `done_o` stays high once set, and is never high while a solution is waiting,
* every solution on `m_data_o` is valid: the row indices are in range and strictly
  increasing, and any two rows are compatible. This uses separate instances of
  `valid.vhd`,
* the search state is consistent: the registers derived from the number of placed
  rows match it, and the placed rows are in range, strictly increasing, pairwise
  compatible and follow the early pruning rules, and
* no rows are lost: `cand` and every stack entry hold exactly the rows that fit
  with the rows placed so far and come after the most recently tried row. This
  also covers the delayed stack write and its bypass.

The properties are proven for all reachable states by k-induction, with the
parameters `(4, 2, 1)` and `(7, 3, 2)`. With `(4, 2, 1)` the whole search takes
about 15 clock cycles, so the `bmc` and `cover` tasks also run it to the end. All
tasks together take about 10 seconds. The formal verification doesn't check
directly that every solution is sent out, but together the properties above show
that the search never skips a row that could be placed.

To run one task and look at a failing trace:

```
cd formal
sby --yosys "yosys -m ghdl" -f steiner.sby prove_421
gtkwave steiner_prove_421/engine_0/trace_induct.vcd
```

The [formal workflow](.github/workflows/formal.yml) runs the formal verification on
GitHub Actions for every push to `main` and every pull request.

### Synthesis

You need Xilinx Vivado. The `Makefile` expects Vivado 2025.1 in
`/opt/Xilinx/2025.1/Vivado`. If yours is somewhere else, override the path:

```
make vivado XILINX_DIR=/path/to/Vivado
```

The build targets the Artix-7 `xc7a100tcsg324-1` on the Nexys 4 DDR board, and
writes the bitstream to `nexys4ddr.bit`. If the routed design doesn't meet timing,
the build stops with an error and writes no bitstream. The timing report is in
`nexys4ddr_timing.rpt`. Synthesis flattens the hierarchy, and placement and
routing use the more aggressive timing directives. The top level `nexys4ddr.vhd`:

* uses an MMCM to make a 180 MHz clock from the 100 MHz board clock, which is the
  fastest clock where the search logic meets timing with some margin (builds start
  to fail at around 187.5 MHz), and
* turns the active-low `CPU_RESETN` button into a synchronous active-high reset.
  The search starts when the MMCM has locked, and starts again whenever you press
  the button.

`m_valid_o` drives LED0 and `done_o` drives LED1. `m_ready_i` is tied high and
`m_data_o` is left unconnected, so the individual solutions are only printed in
simulation. The search parameters for the board are set in the `generic map` in
`nexys4ddr.vhd`.

The amount of logic grows roughly as `b × B(n,k)`, so larger parameter sets quickly
become too big for the FPGA.

## License

See [LICENSE](LICENSE).
