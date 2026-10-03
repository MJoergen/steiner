#!/usr/bin/env python3
"""Reference model: print every Steiner system S(t, k, n).

Usage: steiner_ref.py [--text] N K T

Each solution is printed as the sorted list of its row indices, one solution
per line, in lexicographic order. This is the same format as the results
files and the testbench output, so the outputs can be compared with diff.

With --text, each solution is printed as the text that steiner2uart.vhd sends
instead: one line for each row, with its index and its columns, and an empty
line after each solution, and at the end a line with the number of
solutions, e.g. "840 solutions found.". Lines end with CR LF.

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


def print_text(n, k, solution):
    rows = list(itertools.combinations(range(n), k))
    width = len(str(len(rows) - 1))
    for i in solution:
        columns = ''.join('*' if c in rows[i] else '.' for c in range(n))
        print(f'{i:>{width}} {columns}', end='\r\n')
    print(end='\r\n')


def main():
    args = sys.argv[1:]
    text = args[:1] == ['--text']
    if text:
        args = args[1:]
    if len(args) != 3:
        sys.exit(__doc__)
    n, k, t = map(int, args)
    solutions = steiner_systems(n, k, t)
    for solution in solutions:
        if text:
            print_text(n, k, solution)
        else:
            print('[' + ', '.join(map(str, solution)) + ']')
    if text:
        print(f'{len(solutions)} solutions found.', end='\r\n')


if __name__ == '__main__':
    main()
