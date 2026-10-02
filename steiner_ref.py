#!/usr/bin/env python3
"""Reference model: print every Steiner system S(t, k, n).

Usage: steiner_ref.py N K T

Each solution is printed as the sorted list of its row indices, one solution
per line, in lexicographic order. This is the same format as the results
files and the testbench output, so the outputs can be compared with diff.

This works completely differently from the search in steiner.vhd, so that
they can check each other. It finds the Steiner systems as an exact cover:
every set of t columns must be in exactly one row. So it always takes the
first set of t columns that isn't covered yet, and tries each row that
contains it and covers no set of t columns twice. There is no early pruning.
"""

import itertools
import sys


def steiner_systems(n, k, t):
    # The rows, numbered in lexicographic order of their columns
    rows = list(itertools.combinations(range(n), k))

    # The sets of t columns, numbered in the same way
    tsets = list(itertools.combinations(range(n), t))
    tset_index = {s: i for i, s in enumerate(tsets)}

    # The sets of t columns in each row, as a bit mask
    covers = [sum(1 << tset_index[s] for s in itertools.combinations(row, t))
              for row in rows]

    # The rows that contain each set of t columns
    rows_with = [[i for i, row in enumerate(rows) if set(s) <= set(row)]
                 for s in tsets]

    all_covered = (1 << len(tsets)) - 1
    solutions = []

    def search(covered, chosen):
        if covered == all_covered:
            solutions.append(sorted(chosen))
            return
        # The first set of t columns that isn't covered yet
        first = (~covered & (covered + 1)).bit_length() - 1
        for i in rows_with[first]:
            if covers[i] & covered == 0:
                chosen.append(i)
                search(covered | covers[i], chosen)
                chosen.pop()

    search(0, [])
    return sorted(solutions)


def main():
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    n, k, t = map(int, sys.argv[1:])
    for solution in steiner_systems(n, k, t):
        print('[' + ', '.join(map(str, solution)) + ']')


if __name__ == '__main__':
    main()
