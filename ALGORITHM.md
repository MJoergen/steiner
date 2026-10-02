# Search algorithm

This explains the search used in [`steiner.vhd`](steiner.vhd), how it is
implemented so that it runs at 180 MHz, and what limits the clock frequency.

## Rows and conflicts

A row is a set of `k` of the `n` columns, so there are `B(n,k)` rows. They are
numbered in lexicographic order of their columns, so for `n = 9` and `k = 3`,
row 0 is `{0,1,2}`, row 1 is `{0,1,3}`, and row 83 is `{6,7,8}`.

Two rows conflict if they share `t` or more columns. A solution is a set of `b`
rows where no two rows conflict. Every row conflicts with itself, since `k >= t`.

Sets of rows are kept as bit vectors with one bit for each row, so that set
operations are just AND, OR and NOT. [`valid.vhd`](valid.vhd) computes, at
elaboration time, which pairs of rows conflict. Given one row as a one-hot
vector, it outputs the set of rows that don't conflict with it.

## Admissible parameters

In a Steiner system, every set of `t` columns is in exactly one row. Take any
set of `i` columns, for some `i` from 0 to `t-1`. It is part of
`B(n-i,t-i)` sets of `t` columns, and each row that contains it covers
`B(k-i,t-i)` of these. So the number of rows that contain the `i` columns is
exactly

    l_i = B(n-i,t-i) / B(k-i,t-i)

which must be a whole number. `l_0 = b` is the number of rows, `l_1 = r` is
the number of rows with any one column, and `l_2` is the number of rows with any
two columns, which the [early pruning](#early-pruning) uses. Parameters where
every `l_i` is a whole number are called admissible. For example:

* `(n, k, 1)` is admissible when `k` divides `n`.
* `(n, 3, 2)` is admissible when `n` is 1 or 3 modulo 6.
* `(n, 4, 3)` is admissible when `n` is 2 or 4 modulo 6.

This is necessary, but not enough, for a Steiner system to exist. For example,
`(43, 7, 2)` is admissible, with `b = 43` and `r = 7`, but there is no such
Steiner system, since there is no projective plane of order 6.

The design only accepts admissible parameters. `steiner.vhd` checks them at
elaboration time, and stops with an error otherwise, in simulation, in the formal
verification, and in synthesis (Vivado needs `synth_design -assert` for this).
Without this check, `b`, `r` and `l_2` would be rounded down. Then a set of `b`
rows with no conflicts covers fewer than all the sets of `t` columns, so it isn't
a Steiner system. And the early pruning, which relies on each column being in
exactly `r` rows, would let only some of these sets through. For example, for
`(9, 2, 1)`, `b` would be 4 (rounded down from 4.5), and the design would output
840 of the 945 sets of 4 disjoint pairs of columns.

## The search

The search is depth-first with backtracking. Each solution is built by placing
rows in increasing order, so each set of rows is visited only once. The state
of the search is:

* `depth`: the number of rows placed so far,
* `positions`: the rows placed so far,
* `cand`: the rows that can still be tried at the current depth, and
* a stack with one entry for each placed row: the rows that were left to try at
  its depth when it was placed.

After reset, `depth` is 0 and `cand` holds every row. Each clock cycle does
exactly one of these steps:

| Condition                         | Step        | What happens                                                                                     |
| --------------------------------- | ----------- | ------------------------------------------------------------------------------------------------ |
| `depth = b`                       | Output      | Send `positions` as a solution, then backtrack (once the previous solution has been accepted).   |
| `cand` has a row                  | Place       | Let `c` be the first row in `cand`. Push `cand` without `c`, set `positions(depth) := c`, set `cand := cand and compat(c)`, and increment `depth`. |
| `cand` has no row, `depth > 0`    | Backtrack   | Pop the stack into `cand`, and decrement `depth`.                                                |
| `cand` has no row, `depth = 0`    | Done        | Set `done_o` (once the last solution has been accepted).                                         |

Here a row that the [early pruning](#early-pruning) forbids counts as no row.

Here `compat(c)` is the set of rows that don't conflict with `c`. It doesn't
contain `c` itself, so `c` is removed from `cand`. It does contain the rows
before `c`, but `cand` has none of these, since `c` is its first row.

So each clock cycle visits one node of the search tree, and no clock cycles are
spent on rows that don't fit. Every place is undone exactly once, by a backtrack
or after an output. For `(9, 3, 2)` the search takes 62,293 places, 61,453
backtracks and 840 outputs, i.e. 124,586 clock cycles.

### Why it works

The search keeps this invariant in every clock cycle:

* `cand` is exactly the set of rows that don't conflict with any placed row,
  and come after the most recently tried row at this depth. That is the row
  just removed at this depth after a backtrack, or else the row placed at the
  depth before.
* Stack entry `d` is exactly the set of rows that don't conflict with
  `positions(0)` to `positions(d-1)`, and come after `positions(d)`.

Place keeps it, because the rows after `c` in `cand` that don't conflict with
`c` are exactly the rows for the next depth. Backtrack keeps it, because the
popped entry is exactly the rows after the removed row. Since rows are always
taken from `cand` in increasing order, no set of rows is visited twice, none is
skipped except by the early pruning, and the solutions come out in
lexicographic order. The formal
verification checks this invariant in every clock cycle, see
[`formal/steiner.psl`](formal/steiner.psl).

### Compared with the original design

The original design only kept `positions`. Each clock cycle it stepped one row
forward, and looked up whether that row fit with every placed row. That meant a
lookup for each of the `b` placed rows, and an AND of their outputs, all in the
same clock cycle. It also spent one clock cycle on every row that didn't fit.

| `(n, k, t)` | Original design | This design | Ratio |
| ----------- | --------------- | ----------- | ----- |
| (7, 3, 2)   | 6,012           | 510         | 11.8  |
| (9, 3, 2)   | 1,026,721       | 124,586     | 8.2   |
| (8, 4, 3)   | 474,896         | 12,510      | 38.0  |

These are clock cycles for the whole search, when every solution is accepted
right away. For `(8, 4, 3)`, the original design is taken with the fix of the
[early pruning](#early-pruning) for `t > 2`. Without it, it found no solutions.

## Early pruning

For admissible parameters, each column is in exactly `r` rows of a solution.
All the rows with column 0 come before all the other rows, so in a solution the
first `r` rows have column 0. Those are the rows before `C_SEG1 = B(n-1,k-1)`.

Columns 0 and 1 are together in exactly `l_2 = B(n-2,t-2) / B(k-2,t-2)` rows of
a solution (`C_L2` in the code), so column 1 is in `r - l_2` rows without
column 0. These rows come right after the rows with column 0, so the next
`r - l_2` rows of a solution have column 1. They are the rows before
`C_SEG2 = B(n-1,k-1) + B(n-2,k-1)`. For `t = 2`, `l_2` is 1, and for
`(8, 4, 3)` it is 3. For `t = 1`, `l_2` isn't defined, and only the first rule
is used.

Both rules only forbid rows from the end of the order, at a given depth. So it
is enough to check the first row in `cand`: if it is forbidden, so is every
other row in `cand`, and the search backtracks at once.

## Implementation

The search is one loop, from the `cand` register back to itself: find the first
row in `cand`, look up which rows don't conflict with it, AND that with `cand`,
and choose between this and the top of the stack. The rest of the design is
built around keeping this loop short.

### Finding the first row

The first row in `cand` is isolated as `x and -x`, i.e. `x and (not x + 1)`.
The `+ 1` carries through the zeros below the first one in `x`, and stops at
the first one, so only that bit is left after the AND. Vivado maps this to a
carry chain, which is fast: about 0.1 ns for every 4 bits. But for all 84 rows
of `(9, 3, 2)` that is 21 CARRY4 cells, about 2.9 ns.

### Segments

The rows are split into three segments at the pruning boundaries `C_SEG1` and
`C_SEG2`, i.e. 28, 21 and 35 rows for `(9, 3, 2)`. Each segment has:

* its own carry chain to find its first row,
* its own "any row left" signal, `any(s)`, and
* its own lookup in `valid.vhd`, `seg_compat(s)`.

The first row of `cand` is in the first segment that isn't empty. So the
results of the segments are combined after the lookup:

```
compat = seg_compat(0)
     and (seg_compat(1) or any(0))
     and (seg_compat(2) or any(0) or any(1))
```

This keeps the combining logic out of the path through the carry chain and the
lookup. The early pruning also becomes simple, since it just ignores the
segments that aren't allowed yet:

```
place = any(0) or (allow1 and any(1)) or (allow2 and any(2))
```

Here `allow1` and `allow2` show whether `depth` is past the two pruning
limits. Like `empty` (`depth = 0`), `full` (`depth = b`) and `depth - 1`, they
are kept in registers, and updated whenever `depth` is.

### The lookup

The lookup takes the row as a one-hot vector, rather than as an index. So output
bit `j` is just the OR of the input bits of the rows that conflict with row `j`,
and no decoding is needed. Only the rows up to `j` are included, since `cand`
has no rows before the row being placed. For `(9, 3, 2)` each row conflicts with
18 other rows, so each output bit is an OR of at most 19 inputs, which is two
levels of LUTs.

### The stack

The stack is only ever read at the top (`depth - 1`), and only written at the
entry of the row being placed, so it fits in distributed RAM: 84 bits wide and
12 entries deep for `(9, 3, 2)`, which takes 56 LUTs. Unlike a stack in flip-flops, it doesn't
add to the fanout of the decision to place or backtrack.

Writing to the stack is delayed by one clock cycle, so that the carry chains
and the encoding of the row index aren't in series with the RAM write. In the
clock cycle after a place, the stack entry and the row index in `positions` are
written from registers that hold the values from the place. These registers
are loaded in every clock cycle, so that they don't need a clock enable that
depends on the decision. Two cases need the pending write:

* A backtrack right after a place reads the stack entry that is being written.
  So a bypass returns the pending value instead.
* When a solution is output in the clock cycle right after its last row was
  placed, the index of that row is taken from the pending write.

## Timing

### Results

Each step below is a change to the design, built with Vivado 2025.1 for the
Artix-7 `xc7a100tcsg324-1`. The maximum clock frequency is estimated from a
single run as `1 / (period - WNS)`, with a 200 MHz constraint (90 MHz for the
original design). It varies by about 4% between runs, because of placement.

| Step                                                         | Clock (MHz) | LUT  | FF   |
| ------------------------------------------------------------ | ----------- | ---- | ---- |
| Original design                                              |  91         | 1583 |  101 |
| `cand` register, place the first row in each clock cycle     | 156         | 1040 | 1102 |
| Values derived from `depth` in registers                     | 157         | 1037 | 1112 |
| Three segments, stack in distributed RAM                     | 167         |  570 |  101 |
| Lookup for each segment, flattened hierarchy                 | 187         |  611 |  101 |
| Delayed stack write                                          | 186         |  669 |  274 |
| More aggressive placement and routing directives             | 196         |  695 |  277 |

The second step is where the number of clock cycles drops, see
[Compared with the original design](#compared-with-the-original-design). The
stack is 1000 flip-flops in that step, and moves to distributed RAM in the
fourth. The delayed stack write made no measurable difference on its own. It
took the RAM writes out of the worst paths, but the decision path is just as
long.

The build (`make vivado`) uses 180 MHz. In repeated runs, the design met timing
at 175, 180 and 185 MHz, and once at 195 MHz, but failed at 187.5 and 190 MHz.
So 180 MHz leaves some margin.

With 124,586 clock cycles at 180 MHz, the whole search for `(9, 3, 2)` takes
0.69 ms, compared with 11.4 ms for the original design at 90 MHz.

### Critical paths

There are two kinds of critical path, both about 5.2 ns, of which 75-80% is
routing:

* The decision: from `cand`, through the OR of a segment (two or three LUT
  levels) to `place`, and then to the multiplexer of every bit of `cand`. This
  net drives about 95 loads, which takes about 1.4 ns of routing.
* The loop: from `cand`, through the carry chain of a segment (7 to 9 CARRY4
  cells), the lookup, and the multiplexer, back into `cand`.

Both are inherent in visiting one node of the search tree in each clock cycle:
the next value of `cand` depends on the first row of the current one, and on
whether there is a first row at all.

### What didn't help

* Shorter segments, of at most 16 rows: The carry chains get shorter, but the
  combining of the segments needs more logic, and the result was no faster.
* A `max_fanout` attribute on `place`, so that Vivado replicates it.
* Taking `place` out of the clock enable of `cand`, by updating `cand` even
  when the search is finished.

To go much faster, the loop would have to be broken, e.g. by interleaving two
independent searches of different subtrees. Each would then get a clock cycle
only every other cycle, and the solutions would no longer come out in order.

## Resources

* The lookup is an OR for each row, over the rows that conflict with it, so it
  grows as `B(n,k)` times the number of conflicting rows.
* The stack is `b` entries of `B(n,k)` bits, in distributed RAM.
* `cand` and the registers for the delayed write are about `3 * B(n,k)`
  flip-flops.

For `(9, 3, 2)` the whole design uses 664 LUTs (56 of them as distributed RAM)
and 274 flip-flops. The original design grew as `b * B(n,k)` LUTs, since it
had a lookup for each placed row.
