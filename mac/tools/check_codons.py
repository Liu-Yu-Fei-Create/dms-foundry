#!/usr/bin/env python3
"""Validate the Kazusa-derived codon usage tables shipped with DMSEngine.

Reads the two JSON resources and reports, per table:
  * number of codons (must be 64)
  * total frequency (per thousand; should be ~1000 +/- 5)
  * for each amino acid: number of codons and the optimal (most frequent) codon

Also cross-checks the amino-acid assignment against the standard genetic code,
the DNA alphabet (T, never U), the stop-codon convention (aa == "*") and that
every frequency is given to one decimal place.

Usage:
    python3 tools/check_codons.py [path/to/codons_ecoli.json path/to/codons_human.json]
Exit code 0 = all checks passed, 1 = at least one failure.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

RESOURCE_DIR = Path(__file__).resolve().parent.parent / "Sources" / "DMSEngine" / "Resources" / "Data"
DEFAULT_FILES = [RESOURCE_DIR / "codons_ecoli.json", RESOURCE_DIR / "codons_human.json"]

STANDARD_CODE = {
    "TTT": "F", "TTC": "F", "TTA": "L", "TTG": "L",
    "CTT": "L", "CTC": "L", "CTA": "L", "CTG": "L",
    "ATT": "I", "ATC": "I", "ATA": "I", "ATG": "M",
    "GTT": "V", "GTC": "V", "GTA": "V", "GTG": "V",
    "TCT": "S", "TCC": "S", "TCA": "S", "TCG": "S",
    "CCT": "P", "CCC": "P", "CCA": "P", "CCG": "P",
    "ACT": "T", "ACC": "T", "ACA": "T", "ACG": "T",
    "GCT": "A", "GCC": "A", "GCA": "A", "GCG": "A",
    "TAT": "Y", "TAC": "Y", "TAA": "*", "TAG": "*",
    "CAT": "H", "CAC": "H", "CAA": "Q", "CAG": "Q",
    "AAT": "N", "AAC": "N", "AAA": "K", "AAG": "K",
    "GAT": "D", "GAC": "D", "GAA": "E", "GAG": "E",
    "TGT": "C", "TGC": "C", "TGA": "*", "TGG": "W",
    "CGT": "R", "CGC": "R", "CGA": "R", "CGG": "R",
    "AGT": "S", "AGC": "S", "AGA": "R", "AGG": "R",
    "GGT": "G", "GGC": "G", "GGA": "G", "GGG": "G",
}

AA_NAMES = {
    "A": "Ala", "R": "Arg", "N": "Asn", "D": "Asp", "C": "Cys",
    "Q": "Gln", "E": "Glu", "G": "Gly", "H": "His", "I": "Ile",
    "L": "Leu", "K": "Lys", "M": "Met", "F": "Phe", "P": "Pro",
    "S": "Ser", "T": "Thr", "W": "Trp", "Y": "Tyr", "V": "Val",
    "*": "Stop",
}
AA_ORDER = list("ARNDCQEGHILKMFPSTWYV*")


def check_table(path: Path) -> bool:
    """Print a report for one table; return True when every check passes."""
    ok = True
    print("=" * 72)
    print(f"file        : {path}")
    try:
        with open(path, encoding="utf-8") as fh:
            doc = json.load(fh)
    except Exception as exc:  # noqa: BLE001 - report, do not crash
        print(f"  FAIL  cannot parse JSON: {exc}")
        return False

    for key in ("id", "name", "source", "source_url", "retrieved", "unit", "notes", "codons"):
        if key not in doc:
            print(f"  FAIL  missing top-level key '{key}'")
            ok = False
    print(f"id          : {doc.get('id')}")
    print(f"name        : {doc.get('name')}")
    print(f"source      : {doc.get('source')}")
    print(f"source_url  : {doc.get('source_url')}")
    print(f"retrieved   : {doc.get('retrieved')}")
    print(f"unit        : {doc.get('unit')}")

    codons = doc.get("codons", {})
    if len(codons) != 64:
        print(f"  FAIL  expected 64 codons, found {len(codons)}")
        ok = False
    missing = sorted(set(STANDARD_CODE) - set(codons))
    extra = sorted(set(codons) - set(STANDARD_CODE))
    if missing:
        print(f"  FAIL  missing codons: {', '.join(missing)}")
        ok = False
    if extra:
        print(f"  FAIL  unknown codons: {', '.join(extra)}")
        ok = False
    for codon, entry in codons.items():
        if codon != codon.upper():
            print(f"  FAIL  codon not upper-case DNA: {codon}")
            ok = False
        if "U" in codon:
            print(f"  FAIL  RNA base in codon: {codon}")
            ok = False
        if codon in STANDARD_CODE and entry.get("aa") != STANDARD_CODE[codon]:
            print(f"  FAIL  {codon}: aa={entry.get('aa')!r} but standard code says {STANDARD_CODE[codon]!r}")
            ok = False
        if codon in STANDARD_CODE and STANDARD_CODE[codon] == "*" and entry.get("aa") != "*":
            print(f"  FAIL  {codon}: stop codon must use aa='*'")
            ok = False
        freq = entry.get("freq")
        if not isinstance(freq, (int, float)):
            print(f"  FAIL  {codon}: freq is not numeric")
            ok = False
        elif round(float(freq), 1) != float(freq):
            print(f"  FAIL  {codon}: freq {freq} is not rounded to 1 decimal")
            ok = False
        elif float(freq) < 0:
            print(f"  FAIL  {codon}: negative frequency")
            ok = False

    total = round(sum(float(e["freq"]) for e in codons.values()), 2)
    print(f"codons      : {len(codons)}")
    print(f"total freq  : {total:.1f} per thousand  (expected 1000 +/- 5)")
    if not abs(total - 1000.0) <= 5.0:
        print("  FAIL  total frequency is outside the accepted 1000 +/- 5 window")
        ok = False

    print("")
    print(f"{'aa':<4} {'name':<5} {'n':>2}  {'optimal codon':<14} {'freq':>6}   codons (freq)")
    print("-" * 72)
    by_aa: dict[str, list[tuple[str, float]]] = {}
    for codon, entry in codons.items():
        by_aa.setdefault(entry["aa"], []).append((codon, float(entry["freq"])))
    for aa in AA_ORDER:
        rows = by_aa.get(aa)
        if not rows:
            continue
        rows.sort(key=lambda c: (-c[1], c[0]))
        best = rows[0]
        detail = ", ".join(f"{c}:{f:.1f}" for c, f in rows)
        print(f"{aa:<4} {AA_NAMES.get(aa, '?'):<5} {len(rows):>2}  {best[0]:<14} {best[1]:>6.1f}   {detail}")

    covered = set(by_aa)
    if covered != set(STANDARD_CODE.values()):
        print(f"  FAIL  amino-acid coverage mismatch: {sorted(covered)}")
        ok = False
    print(f"result      : {'PASS' if ok else 'FAIL'}")
    return ok


def main(argv: list[str]) -> int:
    paths = [Path(p) for p in argv[1:]] or DEFAULT_FILES
    results = [check_table(p) for p in paths]
    print("=" * 72)
    print(f"summary     : {sum(results)}/{len(results)} tables passed")
    return 0 if all(results) else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
