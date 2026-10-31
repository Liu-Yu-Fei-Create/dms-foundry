#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Independent verifier for the frozen DMS sub-library index table.

This script deliberately re-implements every rule from scratch instead of
importing ``make_indices.py``: it is a second opinion, not a mirror.  It
re-checks, for the JSON table on disk:

  * schema: required keys, ``count`` == len(indices), unique/consistent ids
  * per sequence: length 20, ACGT only, GC in [0.40, 0.60] (recomputed and
    compared with the stored ``gc``), no run of 4 identical bases, all
    fifteen 6-mers distinct, no palindrome, no inverted repeat of length >= 4,
    no BsaI/BsmBI/BbsI/SapI site on either strand, no leading G, Tm in
    [55, 65] degC (recomputed nearest-neighbour Tm compared with ``tm``)
  * cross sequence: all 3' terminal 10-mers distinct, pairwise full-length
    Hamming distance >= 6

Exit status is 0 only when every check passes.

Usage
-----
    python3 check_indices.py
    python3 check_indices.py --path some/other.json
"""

from __future__ import annotations

import argparse
import json
import math
import sys
import time
from collections import defaultdict
from itertools import combinations
from pathlib import Path

DEFAULT_JSON = (
    Path(__file__).resolve().parents[1]
    / "Sources/DMSEngine/Resources/Data/indices_1024.json"
)

LENGTH = 20
GC_MIN, GC_MAX = 0.40, 0.60
MAX_HOMOPOLYMER = 3
MIN_HAMMING = 6
THREE_PRIME_LEN = 10
TM_MIN, TM_MAX = 55.0, 65.0
NAV_M = 0.05
CT_M = 0.25e-6
R_CAL = 1.987
FORBIDDEN_MOTIFS = ("GGTCTC", "CGTCTC", "GAAGAC", "GCTCTTC")
REQUIRED_KEYS = {"version", "seed", "count", "length", "constraints",
                 "notes", "indices"}

# SantaLucia 1998 unified NN parameters, written out independently.
NN = {
    "AA": (-7.9, -22.2), "TT": (-7.9, -22.2), "AT": (-7.2, -20.4),
    "TA": (-7.2, -21.3), "CA": (-8.5, -22.7), "TG": (-8.5, -22.7),
    "GT": (-8.4, -22.4), "AC": (-8.4, -22.4), "CT": (-7.8, -21.0),
    "AG": (-7.8, -21.0), "GA": (-8.2, -22.2), "TC": (-8.2, -22.2),
    "CG": (-10.6, -27.2), "GC": (-9.8, -24.4), "GG": (-8.0, -19.9),
    "CC": (-8.0, -19.9),
}
COMPLEMENT = str.maketrans("ACGT", "TGCA")


def revcomp(seq: str) -> str:
    return seq.translate(COMPLEMENT)[::-1]


def tm_of(seq: str) -> float:
    dh = 0.0
    ds = 0.0
    for i in range(len(seq) - 1):
        h, s = NN[seq[i:i + 2]]
        dh += h * 1000.0
        ds += s
    return dh / (ds + R_CAL * math.log(CT_M / 4.0)) - 273.15 + 16.6 * math.log10(NAV_M)


def gc_of(seq: str) -> float:
    return sum(1 for c in seq if c in "GC") / len(seq)


def longest_homopolymer(seq: str) -> int:
    best = run = 1
    for i in range(1, len(seq)):
        run = run + 1 if seq[i] == seq[i - 1] else 1
        best = max(best, run)
    return best


def duplicated_kmers(seq: str, k: int) -> list[str]:
    counts: dict[str, int] = defaultdict(int)
    for i in range(len(seq) - k + 1):
        counts[seq[i:i + k]] += 1
    return [mer for mer, n in counts.items() if n > 1]


def inverted_repeat_hits(seq: str, min_len: int = 4) -> list[tuple[int, str]]:
    """Every self-contained window whose reverse complement occurs in seq.

    Brute force on purpose: for each length k from ``min_len`` up and each
    start position, search the whole sequence for the reverse complement (so
    overlapping / self-palindromic cases are reported too).  Any inverted
    repeat of length >= 4 shows up here.
    """
    hits = []
    for k in range(min_len, len(seq) + 1):
        for i in range(len(seq) - k + 1):
            window = seq[i:i + k]
            if revcomp(window) in seq:
                hits.append((i, window))
    return hits


def site_hits(seq: str) -> list[str]:
    found = []
    for motif in FORBIDDEN_MOTIFS:
        if motif in seq:
            found.append(f"{motif}(+)")
        rc = revcomp(motif)
        if rc in seq and rc != motif:
            found.append(f"{rc}(-)")
    return found


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Verify the DMS index table.")
    parser.add_argument("--path", type=Path, default=DEFAULT_JSON)
    args = parser.parse_args(argv)

    started = time.perf_counter()
    failures: list[str] = []

    if not args.path.is_file():
        print(f"FAIL: {args.path} does not exist", file=sys.stderr)
        return 2
    try:
        doc = json.loads(args.path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        print(f"FAIL: not valid JSON: {exc}", file=sys.stderr)
        return 2

    missing = REQUIRED_KEYS - set(doc)
    if missing:
        failures.append(f"schema: missing keys {sorted(missing)}")
    indices = doc.get("indices", [])
    if not isinstance(indices, list):
        print("FAIL: 'indices' is not a list", file=sys.stderr)
        return 2
    if doc.get("count") != len(indices):
        failures.append(f"schema: count={doc.get('count')} but len(indices)={len(indices)}")
    if doc.get("length") != LENGTH:
        failures.append(f"schema: length={doc.get('length')} != {LENGTH}")
    if not isinstance(doc.get("seed"), int):
        failures.append("schema: seed is not an integer")

    # ------------------------------------------------------------------ #
    # Per-entry and per-sequence checks
    # ------------------------------------------------------------------ #
    seqs: list[str] = []
    ids: list[str] = []
    gc_stored: list[float] = []
    tm_stored: list[float] = []
    gc_calc: list[float] = []
    tm_calc: list[float] = []
    gc_lo, gc_hi, tm_lo, tm_hi = 1.0, 0.0, 1e9, -1e9

    for n, entry in enumerate(indices, start=1):
        tag = f"entry {n}"
        if not isinstance(entry, dict) or not {"id", "seq", "gc", "tm"} <= set(entry):
            failures.append(f"{tag}: missing id/seq/gc/tm")
            continue
        eid, seq = entry["id"], entry["seq"]
        ids.append(eid)
        if not isinstance(seq, str) or len(seq) != LENGTH:
            failures.append(f"{tag} ({eid}): seq length != {LENGTH}")
            continue
        if set(seq) - set("ACGT"):
            failures.append(f"{tag} ({eid}): non-ACGT characters {sorted(set(seq) - set('ACGT'))}")
            continue
        seqs.append(seq)

        gc = gc_of(seq)
        if not (GC_MIN <= gc <= GC_MAX):
            failures.append(f"{tag} ({eid}): GC {gc:.2f} outside [{GC_MIN}, {GC_MAX}]")
        gc_calc.append(gc)
        gc_lo, gc_hi = min(gc_lo, gc), max(gc_hi, gc)
        if isinstance(entry.get("gc"), (int, float)):
            gc_stored.append(float(entry["gc"]))
            if abs(float(entry["gc"]) - gc) > 0.01:
                failures.append(f"{tag} ({eid}): stored gc {entry['gc']} != computed {gc:.2f}")
        else:
            failures.append(f"{tag} ({eid}): gc is not numeric")

        tm = tm_of(seq)
        if not (TM_MIN <= tm <= TM_MAX):
            failures.append(f"{tag} ({eid}): Tm {tm:.1f} outside [{TM_MIN}, {TM_MAX}]")
        tm_calc.append(tm)
        tm_lo, tm_hi = min(tm_lo, tm), max(tm_hi, tm)
        if isinstance(entry.get("tm"), (int, float)):
            tm_stored.append(float(entry["tm"]))
            if abs(float(entry["tm"]) - tm) > 0.05:
                failures.append(f"{tag} ({eid}): stored tm {entry['tm']} != computed {tm:.1f}")
        else:
            failures.append(f"{tag} ({eid}): tm is not numeric")

        run = longest_homopolymer(seq)
        if run > MAX_HOMOPOLYMER:
            failures.append(f"{tag} ({eid}): homopolymer run {run} > {MAX_HOMOPOLYMER}")

        dups = duplicated_kmers(seq, 6)
        if dups:
            failures.append(f"{tag} ({eid}): repeated 6-mer(s) {dups[:3]}")

        if seq == revcomp(seq):
            failures.append(f"{tag} ({eid}): palindromic sequence")

        inv = inverted_repeat_hits(seq, 4)
        if inv:
            k = max(len(w) for _, w in inv)
            failures.append(
                f"{tag} ({eid}): inverted repeat up to {k} nt, e.g. {inv[0][1]} at {inv[0][0]}"
            )

        sites = site_hits(seq)
        if sites:
            failures.append(f"{tag} ({eid}): restriction site(s) {sites}")

        if seq[0] == "G":
            failures.append(f"{tag} ({eid}): starts with G")

    # ------------------------------------------------------------------ #
    # Cross-sequence checks
    # ------------------------------------------------------------------ #
    if len(set(ids)) != len(ids):
        dupes = sorted({i for i in ids if ids.count(i) > 1})
        failures.append(f"schema: duplicate ids {dupes[:5]}")
    for n, eid in enumerate(ids, start=1):
        if eid != f"IDX-{n:04d}":
            failures.append(f"schema: id {eid!r} is not IDX-{n:04d}")
            break

    tails: dict[str, str] = {}
    for seq, eid in zip(seqs, ids):
        tail = seq[-THREE_PRIME_LEN:]
        if tail in tails:
            failures.append(
                f"3' collision: {eid} and {tails[tail]} share the "
                f"{THREE_PRIME_LEN} nt 3' end {tail}"
            )
        else:
            tails[tail] = eid

    min_hamming = LENGTH
    closest_pair = None
    n_pairs = 0
    for i, j in combinations(range(len(seqs)), 2):
        a, b = seqs[i], seqs[j]
        d = sum(1 for x, y in zip(a, b) if x != y)
        n_pairs += 1
        if d < min_hamming:
            min_hamming, closest_pair = d, (ids[i], ids[j])
        if d < MIN_HAMMING:
            failures.append(
                f"Hamming {d} < {MIN_HAMMING}: {ids[i]} {a} vs {ids[j]} {b}"
            )

    # ------------------------------------------------------------------ #
    # Report
    # ------------------------------------------------------------------ #
    elapsed = time.perf_counter() - started
    print("=" * 68)
    print(f"file                : {args.path}")
    print(f"generated / seed    : {doc.get('generated')} / {doc.get('seed')}")
    print(f"entries             : {len(indices)}  (count field: {doc.get('count')}, "
          f"parsed seqs: {len(seqs)})")
    if gc_calc:
        print(f"GC content          : {gc_lo:.2f} - {gc_hi:.2f}  "
              f"(mean {sum(gc_calc)/len(gc_calc):.3f})")
        print(f"Tm (degC)           : {tm_lo:.1f} - {tm_hi:.1f}  "
              f"(mean {sum(tm_calc)/len(tm_calc):.1f})")
    if seqs:
        print(f"min pairwise Hamming: {min_hamming}  "
              f"(closest: {closest_pair[0]} / {closest_pair[1]})" if closest_pair else "")
        print(f"pairs compared      : {n_pairs}")
        print(f"distinct 3' ends     : {len(tails)} of {len(seqs)}")
    print(f"failed checks       : {len(failures)}")
    for msg in failures[:20]:
        print(f"  - {msg}")
    if len(failures) > 20:
        print(f"  ... and {len(failures) - 20} more")
    print(f"elapsed             : {elapsed:.2f} s")
    print("RESULT              : " + ("PASS" if not failures else "FAIL"))
    print("=" * 68)

    return 0 if not failures else 1


if __name__ == "__main__":
    raise SystemExit(main())
