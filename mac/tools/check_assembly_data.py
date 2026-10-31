#!/usr/bin/env python3
"""Validate the Golden Gate assembly data files.

Checks
------
enzymes.json
  * exactly the six required Type IIS enzymes are present
  * every required field is present and of a sane type
  * recognition sequence / reverse complement agree
  * cut_top  == len(recognition) + spacer
  * cut_bottom == cut_top + overhang_length   (and cut_bottom > cut_top)
  * is_palindromic agrees with the recognition sequence
  * every enzyme carries an http(s) source_url

overhangs_t4.json
  * exactly 256 keys, equal to the 256 canonical 4-mers over A/C/G/T
  * each entry carries palindromic / self_complementary / fidelity_rank / notes
  * palindromic == (reverse_complement(key) == key), and self_complementary == palindromic
  * if data_status == "measured": fidelity in [0, 1], total == correct + mismatch,
    fidelity_rank is a permutation of 1..256 and agrees with the fidelity ordering
  * if data_status == "unavailable": no numeric fidelity may be claimed

Usage
-----
    python3 tools/check_assembly_data.py [--data-dir DIR]

Exit status 0 = all checks passed, 1 = at least one check failed.
"""

from __future__ import annotations

import argparse
import itertools
import json
import statistics
import sys
from pathlib import Path

REQUIRED_ENZYMES = ["AarI", "BbsI", "BsaI", "BspQI", "BsmBI", "SapI"]

ENZYME_FIELDS = [
    "recognition",
    "reverse_complement",
    "spacer",
    "overhang_length",
    "cut_top",
    "cut_bottom",
    "overhang_strand",
    "is_palindromic",
    "source_url",
    "notes",
]

OVERHANG_FIELDS = ["palindromic", "self_complementary", "fidelity_rank", "notes"]

_COMPLEMENT = str.maketrans("ACGT", "TGCA")


def reverse_complement(seq: str) -> str:
    return seq.translate(_COMPLEMENT)[::-1]


def all_kmers(k: int = 4, alphabet: str = "ACGT") -> set[str]:
    return {"".join(p) for p in itertools.product(alphabet, repeat=k)}


class Report:
    def __init__(self) -> None:
        self.failures: list[str] = []
        self.checks = 0

    def check(self, ok: bool, message: str) -> bool:
        self.checks += 1
        if not ok:
            self.failures.append(message)
        return ok

    def section(self, title: str) -> None:
        print()
        print(title)
        print("-" * len(title))


def load_json(path: Path, rep: Report) -> dict | None:
    if not path.is_file():
        rep.check(False, f"missing file: {path}")
        return None
    try:
        with path.open(encoding="utf-8") as fh:
            return json.load(fh)
    except json.JSONDecodeError as exc:
        rep.check(False, f"{path.name} is not valid JSON: {exc}")
        return None


# --------------------------------------------------------------------------- #
# enzymes.json
# --------------------------------------------------------------------------- #
def check_enzymes(doc: dict, rep: Report) -> None:
    rep.section("enzymes.json")
    rep.check(isinstance(doc.get("version"), int), "top-level 'version' must be an int")
    rep.check(bool(doc.get("source")), "top-level 'source' is required")
    rep.check(bool(doc.get("retrieved")), "top-level 'retrieved' is required")
    rep.check(isinstance(doc.get("notes"), str) and doc["notes"].strip() != "",
              "top-level 'notes' must document the cut_top/cut_bottom convention")

    enzymes = doc.get("enzymes")
    if not rep.check(isinstance(enzymes, dict), "'enzymes' must be an object"):
        return

    rep.check(len(enzymes) == 6, f"expected 6 enzymes, found {len(enzymes)}")
    actual = set(enzymes)
    rep.check(actual == set(REQUIRED_ENZYMES),
              f"enzyme set mismatch: missing={sorted(set(REQUIRED_ENZYMES) - actual)} "
              f"unexpected={sorted(actual - set(REQUIRED_ENZYMES))}")

    header = f"{'enzyme':<7} {'site':<8} {'spacer':>6} {'cut_top':>7} {'cut_bottom':>10} " \
             f"{'OH':>3} {'strand':>6} {'palindrome':>10}"
    print(header)
    print("-" * len(header))
    for name in REQUIRED_ENZYMES:
        entry = enzymes.get(name)
        if not rep.check(isinstance(entry, dict), f"{name}: entry missing or not an object"):
            continue

        for field in ENZYME_FIELDS:
            rep.check(field in entry, f"{name}: missing field '{field}'")
        if any(f not in entry for f in ENZYME_FIELDS):
            continue

        rec = entry["recognition"]
        rcs = entry["reverse_complement"]
        spacer = entry["spacer"]
        oh_len = entry["overhang_length"]
        cut_top = entry["cut_top"]
        cut_bottom = entry["cut_bottom"]
        strand = entry["overhang_strand"]

        rep.check(isinstance(rec, str) and rec and set(rec) <= set("ACGT"),
                  f"{name}: recognition must be a non-empty ACGT string")
        rep.check(rcs == reverse_complement(rec),
                  f"{name}: reverse_complement {rcs!r} != revcomp({rec!r}) = {reverse_complement(rec)!r}")
        rep.check(isinstance(spacer, int) and spacer >= 0, f"{name}: spacer must be an int >= 0")
        rep.check(isinstance(oh_len, int) and oh_len in (3, 4),
                  f"{name}: overhang_length must be 3 or 4 (Type IIS geometry), got {oh_len!r}")
        rep.check(isinstance(cut_top, int) and isinstance(cut_bottom, int),
                  f"{name}: cut_top/cut_bottom must be ints")
        rep.check(cut_top == len(rec) + spacer,
                  f"{name}: cut_top {cut_top} != len(recognition) {len(rec)} + spacer {spacer}")
        rep.check(cut_bottom == cut_top + oh_len,
                  f"{name}: cut_bottom {cut_bottom} != cut_top {cut_top} + overhang_length {oh_len}")
        rep.check(cut_bottom > cut_top, f"{name}: cut_bottom must be greater than cut_top")
        rep.check(strand in ("5'", "3'"), f"{name}: overhang_strand must be \"5'\" or \"3'\"")
        rep.check(entry["is_palindromic"] == (rec == reverse_complement(rec)),
                  f"{name}: is_palindromic disagrees with the recognition sequence")
        rep.check(isinstance(entry["source_url"], str)
                  and entry["source_url"].startswith(("http://", "https://")),
                  f"{name}: source_url must be an http(s) URL")

        print(f"{name:<7} {rec:<8} {spacer:>6} {cut_top:>7} {cut_bottom:>10} "
              f"{oh_len:>3} {strand:>6} {str(entry['is_palindromic']):>10}")

    lengths = [e["overhang_length"] for e in enzymes.values() if "overhang_length" in e]
    if lengths:
        print(f"\noverhang length distribution: "
              f"{ {n: lengths.count(n) for n in sorted(set(lengths))} }")
        print(f"enzymes leaving 4-nt overhangs: "
              f"{sorted(n for n, e in enzymes.items() if e.get('overhang_length') == 4)}")
        print(f"enzymes leaving 3-nt overhangs: "
              f"{sorted(n for n, e in enzymes.items() if e.get('overhang_length') == 3)}")


# --------------------------------------------------------------------------- #
# overhangs_t4.json
# --------------------------------------------------------------------------- #
def check_overhangs(doc: dict, rep: Report) -> None:
    rep.section("overhangs_t4.json")
    rep.check(isinstance(doc.get("version"), int), "top-level 'version' must be an int")
    rep.check(bool(doc.get("source")), "top-level 'source' is required")
    rep.check(bool(doc.get("source_url")), "top-level 'source_url' is required")
    rep.check(bool(doc.get("retrieved")), "top-level 'retrieved' is required")

    status = doc.get("data_status")
    rep.check(status in ("measured", "unavailable"),
              f"data_status must be 'measured' or 'unavailable', got {status!r}")

    overhangs = doc.get("overhangs")
    if not rep.check(isinstance(overhangs, dict), "'overhangs' must be an object"):
        return

    rep.check(len(overhangs) == 256, f"expected 256 overhangs, found {len(overhangs)}")
    expected = all_kmers(4)
    actual = set(overhangs)
    rep.check(actual == expected,
              f"overhang key set differs from the 256 ACGT 4-mers: "
              f"missing={sorted(expected - actual)[:10]} extra={sorted(actual - expected)[:10]}")

    palindromes: list[str] = []
    totals_correct: list[float] = []
    rank_seen: dict[int, str] = {}
    ranking_ok = True
    counts_ok = True

    for key in sorted(overhangs):
        entry = overhangs[key]
        if not rep.check(isinstance(entry, dict), f"{key}: entry must be an object"):
            continue
        for field in OVERHANG_FIELDS:
            if not rep.check(field in entry, f"{key}: missing field '{field}'"):
                ranking_ok = False
                continue
        if any(f not in entry for f in OVERHANG_FIELDS):
            continue

        is_pal = reverse_complement(key) == key
        if is_pal:
            palindromes.append(key)
        rep.check(entry["palindromic"] == is_pal,
                  f"{key}: palindromic={entry['palindromic']} but revcomp({key})=={key} is {is_pal}")
        rep.check(entry["self_complementary"] == entry["palindromic"],
                  f"{key}: self_complementary must equal palindromic for a 4-nt overhang")
        rep.check(isinstance(entry["notes"], str), f"{key}: notes must be a string")

        if status == "measured":
            fidelity = entry.get("fidelity")
            total = entry.get("total_ligations")
            correct = entry.get("correct_ligations")
            mismatch = entry.get("mismatch_ligations")
            rep.check(isinstance(fidelity, (int, float)) and 0.0 <= fidelity <= 1.0,
                      f"{key}: measured data requires fidelity in [0, 1]")
            if isinstance(fidelity, (int, float)):
                totals_correct.append(float(fidelity))
            if isinstance(total, int) and isinstance(correct, int) and isinstance(mismatch, int):
                counts_ok &= (total == correct + mismatch)
            else:
                counts_ok = False
                rep.check(False, f"{key}: measured data requires integer total/correct/mismatch counts")
            rank = entry.get("fidelity_rank")
            if isinstance(rank, int):
                if rank in rank_seen:
                    ranking_ok = False
                    rep.check(False, f"{key}: duplicate fidelity_rank {rank} (also {rank_seen[rank]})")
                rank_seen[rank] = key
        elif status == "unavailable":
            rep.check(entry.get("fidelity_rank") is None,
                      f"{key}: data_status is 'unavailable' but a fidelity_rank is claimed")
            rep.check(entry.get("fidelity") is None,
                      f"{key}: data_status is 'unavailable' but a numeric fidelity is claimed")
            rep.check(entry.get("confidence") in (None, "rule_based"),
                      f"{key}: unexpected confidence value {entry.get('confidence')!r}")

    rep.check(len(palindromes) == 16,
              f"expected exactly 16 palindromic 4-mers, found {len(palindromes)}")
    rep.check(not any(reverse_complement(p) != p for p in palindromes),
              "a palindromic overhang failed its own reverse-complement test")

    if status == "measured":
        rep.check(counts_ok, "total_ligations != correct_ligations + mismatch_ligations for some overhang")
        rep.check(ranking_ok and sorted(rank_seen) == list(range(1, 257)),
                  f"fidelity_rank must be a permutation of 1..256 (found {len(rank_seen)} distinct ranks)")
        if sorted(rank_seen) == list(range(1, 257)):
            by_rank = [overhangs[rank_seen[r]]["fidelity"] for r in range(1, 257)]
            rep.check(all(a >= b for a, b in zip(by_rank, by_rank[1:])),
                      "fidelity_rank ordering does not match descending fidelity")

    print(f"data_status      : {status}")
    print(f"overhang keys    : {len(overhangs)}")
    print(f"palindromic      : {len(palindromes)} -> {sorted(palindromes)}")
    if status == "measured" and totals_correct:
        fid = sorted(totals_correct, reverse=True)
        print(f"fidelity range   : {min(fid):.4f} .. {max(fid):.4f}")
        print(f"fidelity mean    : {statistics.mean(fid):.4f}")
        print(f"fidelity median  : {statistics.median(fid):.4f}")
        print(f"overhangs >= 0.90: {sum(1 for f in fid if f >= 0.90)}")
        print(f"overhangs >= 0.95: {sum(1 for f in fid if f >= 0.95)}")
        top = sorted(overhangs.items(), key=lambda kv: -kv[1]["fidelity"])[:5]
        bottom = sorted(overhangs.items(), key=lambda kv: kv[1]["fidelity"])[:5]
        print("best 5           : " + ", ".join(f"{k} {v['fidelity']:.4f}" for k, v in top))
        print("worst 5          : " + ", ".join(f"{k} {v['fidelity']:.4f}" for k, v in bottom))
    else:
        print("fidelity         : not measured (rule-based structural data only)")


def main() -> int:
    default_dir = Path(__file__).resolve().parent.parent / "Sources/DMSEngine/Resources/Data"
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--data-dir", type=Path, default=default_dir,
                        help=f"directory holding enzymes.json and overhangs_t4.json (default: {default_dir})")
    args = parser.parse_args()

    print(f"data directory: {args.data_dir}")
    rep = Report()

    enzymes_doc = load_json(args.data_dir / "enzymes.json", rep)
    if enzymes_doc is not None:
        check_enzymes(enzymes_doc, rep)

    overhangs_doc = load_json(args.data_dir / "overhangs_t4.json", rep)
    if overhangs_doc is not None:
        check_overhangs(overhangs_doc, rep)

    print()
    print(f"checks run: {rep.checks}")
    if rep.failures:
        print(f"FAILED ({len(rep.failures)} problem(s)):")
        for failure in rep.failures:
            print(f"  - {failure}")
        return 1
    print("PASS: all assembly data checks succeeded")
    return 0


if __name__ == "__main__":
    sys.exit(main())
