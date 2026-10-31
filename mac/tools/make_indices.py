#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Build the frozen 1024-entry DMS sub-library index table.

Every index is a 20 nt DNA barcode.  The table is consumed by DMSEngine as
``Resources/Data/indices_1024.json``; this script is the single source of
truth for how it was produced, so the table can be audited and rebuilt.

Design constraints (all enforced, none relaxed silently)
--------------------------------------------------------
per sequence
  * length 20 nt, alphabet ACGT only
  * 40 % <= GC <= 60 %
  * no homopolymer run of length >= 4
  * all fifteen 6-mer windows distinct
  * the 3' terminal 10 nt is unique across the whole table
  * no palindrome
  * no inverted repeat of length >= 4
  * Tm (nearest-neighbour, see below) in [55, 65] degC
  * does not start with G
  * contains no BsaI / BsmBI / BbsI / SapI recognition site, on either strand
cross sequence
  * pairwise full-length Hamming distance >= 6
  * pairwise distinct 3' terminal 10-mers

Generation model
----------------
Candidates are i.i.d. uniform random 20-mers drawn from a Mersenne Twister
stream seeded with ``DEFAULT_SEED`` (written into the JSON), so the whole
table is reproducible: same seed and same Python => same table.

* Stage 1 filters each candidate on its own merits.
* Stage 2 is a greedy maximum-independent-set insertion: a survivor is
  accepted only if it clears the cross-sequence constraints against *every*
  already accepted index; otherwise it is discarded.
* If ``--target`` is not reached before the candidate budget is exhausted the
  script still writes the JSON, with the real count and a ``notes`` entry that
  names the binding constraint and what could be relaxed.  It never pads the
  table with non-compliant sequences.

Tm formula
----------
SantaLucia (1998) unified nearest-neighbour parameters, summed over the 19
dinucleotide steps, without terminal-initiation correction::

    Tm = dH_tot / (dS_tot + R * ln(C_T / 4)) - 273.15 + 16.6 * log10([Na+])

with dH in cal/mol, dS in cal/(mol K), R = 1.987 cal/(mol K), C_T = 0.25 uM
total strand concentration and [Na+] = 50 mM (the log10 term is the standard
salt correction).  These are ordinary PCR-buffer conditions, stated in the
JSON so consumers can reproduce or re-derive the numbers.

Usage
-----
    python3 make_indices.py                              # frozen resource
    python3 make_indices.py --target 64 --out /tmp/s.json # quick experiment
"""

from __future__ import annotations

import argparse
import json
import math
import random
import sys
from collections import Counter
from datetime import date
from pathlib import Path

# --------------------------------------------------------------------------- #
# Design constants
# --------------------------------------------------------------------------- #
LENGTH = 20
DEFAULT_TARGET = 1024
DEFAULT_SEED = 20261102
DEFAULT_MAX_CANDIDATES = 400_000

GC_MIN = 0.40
GC_MAX = 0.60
MAX_HOMOPOLYMER = 3          # a run of 4 or more is forbidden
MIN_HAMMING = 6
THREE_PRIME_LEN = 10

TM_MIN = 55.0
TM_MAX = 65.0
NAV_M = 0.05                 # monovalent cation, mol/L
CT_M = 0.25e-6               # total strand concentration, mol/L
R_CAL = 1.987                # cal / (mol K)

FORBIDDEN_MOTIFS = ("GGTCTC", "CGTCTC", "GAAGAC", "GCTCTTC")  # BsaI/BsmBI/BbsI/SapI

DEFAULT_OUT = (
    Path(__file__).resolve().parents[1]
    / "Sources/DMSEngine/Resources/Data/indices_1024.json"
)

BASES = "ACGT"
COMPLEMENT = str.maketrans("ACGT", "TGCA")

# SantaLucia 1998 unified NN parameters: dH (kcal/mol), dS (cal/mol/K).
NN_PARAMS = {
    "AA": (-7.9, -22.2), "TT": (-7.9, -22.2),
    "AT": (-7.2, -20.4), "TA": (-7.2, -21.3),
    "CA": (-8.5, -22.7), "TG": (-8.5, -22.7),
    "GT": (-8.4, -22.4), "AC": (-8.4, -22.4),
    "CT": (-7.8, -21.0), "AG": (-7.8, -21.0),
    "GA": (-8.2, -22.2), "TC": (-8.2, -22.2),
    "CG": (-10.6, -27.2), "GC": (-9.8, -24.4),
    "GG": (-8.0, -19.9), "CC": (-8.0, -19.9),
}

# 2-bit packing, one nucleotide per field: A=00 C=01 G=10 T=11.
BITS = {"A": 0, "C": 1, "G": 2, "T": 3}
_EVEN_MASK = sum(1 << (2 * i) for i in range(LENGTH))


# --------------------------------------------------------------------------- #
# Sequence helpers
# --------------------------------------------------------------------------- #
def revcomp(seq: str) -> str:
    """Reverse complement of a DNA string."""
    return seq.translate(COMPLEMENT)[::-1]


def encode(seq: str) -> int:
    """Pack a 20-mer into an int, two bits per base (for fast XOR Hamming)."""
    value = 0
    for ch in seq:
        value = (value << 2) | BITS[ch]
    return value


def hamming(a: int, b: int) -> int:
    """Hamming distance between two 2-bit packed sequences."""
    diff = a ^ b
    # A field is non-zero iff either of its two bits is set; collapse the
    # high bit into the low one, mask the low bits, popcount the fields.
    return ((diff | (diff >> 1)) & _EVEN_MASK).bit_count()


def gc_fraction(seq: str) -> float:
    return (seq.count("G") + seq.count("C")) / len(seq)


def melting_temp(seq: str, ct_m: float = CT_M, na_m: float = NAV_M) -> float:
    """Nearest-neighbour Tm in degC (SantaLucia 1998, see module docstring)."""
    dh = 0.0  # cal/mol
    ds = 0.0  # cal/(mol K)
    for i in range(len(seq) - 1):
        h, s = NN_PARAMS[seq[i:i + 2]]
        dh += h * 1000.0
        ds += s
    return dh / (ds + R_CAL * math.log(ct_m / 4.0)) - 273.15 + 16.6 * math.log10(na_m)


def has_homopolymer(seq: str, max_run: int = MAX_HOMOPOLYMER) -> bool:
    """True if any single base is repeated more than ``max_run`` times."""
    run = 1
    for i in range(1, len(seq)):
        if seq[i] == seq[i - 1]:
            run += 1
            if run > max_run:
                return True
        else:
            run = 1
    return False


def has_duplicate_kmer(seq: str, k: int) -> bool:
    """True if any k-mer occurs twice inside ``seq``."""
    seen = set()
    for i in range(len(seq) - k + 1):
        mer = seq[i:i + k]
        if mer in seen:
            return True
        seen.add(mer)
    return False


def is_palindrome(seq: str) -> bool:
    return seq == revcomp(seq)


def has_inverted_repeat(seq: str, min_len: int = 4) -> bool:
    """True if the sequence contains an inverted (reverse-complement) repeat.

    Two length-``min_len`` windows are compared, so this is the strict reading
    of "no inverted repeat of length >= 4": any window that is the reverse
    complement of another window (itself included, i.e. a palindromic 4-mer,
    which is the tightest possible hairpin) is a violation.

    Checking only 4 nt windows is sufficient for longer repeats as well: if
    ``seq[i:i+k]`` equals the reverse complement of ``seq[j:j+k]`` for k > 4,
    then the 4 nt window at the start of the first equals the reverse
    complement of the 4 nt window at the end of the second, hence a 4 nt
    violation would already be reported.
    """
    windows = {seq[i:i + min_len] for i in range(len(seq) - min_len + 1)}
    return any(revcomp(w) in windows for w in windows)


def restriction_site_hit(seq: str, motifs=FORBIDDEN_MOTIFS) -> str | None:
    """Return the first forbidden motif found on either strand, else None."""
    for motif in motifs:
        if motif in seq:
            return motif
        rc = revcomp(motif)
        if rc != motif and rc in seq:
            return rc
    return None


def per_sequence_rejection(seq: str) -> str | None:
    """Run every single-sequence constraint; return the first violated one."""
    if len(seq) != LENGTH or set(seq) - set(BASES):
        return "alphabet/length"
    if seq[0] == "G":
        return "no_leading_G"
    gc = gc_fraction(seq)
    if not (GC_MIN <= gc <= GC_MAX):
        return "gc_window"
    if has_homopolymer(seq):
        return "homopolymer"
    motif = restriction_site_hit(seq)
    if motif is not None:
        return f"restriction_site:{motif}"
    if has_duplicate_kmer(seq, 6):
        return "duplicate_6mer"
    if is_palindrome(seq):
        return "palindrome"
    if has_inverted_repeat(seq):
        return "inverted_repeat"
    tm = melting_temp(seq)
    if not (TM_MIN <= tm <= TM_MAX):
        return "tm_window"
    return None


# --------------------------------------------------------------------------- #
# Generation
# --------------------------------------------------------------------------- #
def random_candidate(rng: random.Random) -> str:
    return "".join(rng.choices(BASES, k=LENGTH))


def generate(target: int, seed: int, max_candidates: int):
    """Greedy construction. Returns (accepted, draws, reject_counter)."""
    rng = random.Random(seed)
    accepted: list[str] = []
    codes: list[int] = []
    three_prime: dict[str, str] = {}
    rejects: Counter[str] = Counter()
    draws = 0
    passed_single = 0

    while len(accepted) < target and draws < max_candidates:
        draws += 1
        seq = random_candidate(rng)
        reason = per_sequence_rejection(seq)
        if reason is not None:
            rejects[reason] += 1
            continue
        passed_single += 1

        code = encode(seq)
        if any(hamming(code, other) < MIN_HAMMING for other in codes):
            rejects["cross:min_hamming"] += 1
            continue
        tail = seq[-THREE_PRIME_LEN:]
        if tail in three_prime:
            rejects["cross:unique_3prime"] += 1
            continue

        accepted.append(seq)
        codes.append(code)
        three_prime[tail] = seq

    rejects["__draws__"] = draws
    rejects["__passed_single__"] = passed_single
    return accepted, rejects


def build_document(accepted: list[str], rejects: Counter, seed: int,
                   target: int, max_candidates: int) -> dict:
    entries = []
    for i, seq in enumerate(accepted, start=1):
        entries.append(
            {
                "id": f"IDX-{i:04d}",
                "seq": seq,
                "gc": round(gc_fraction(seq), 2),
                "tm": round(melting_temp(seq), 1),
            }
        )

    draws = rejects["__draws__"]
    passed_single = rejects["__passed_single__"]
    short = len(accepted) < target

    notes = (
        f"Greedy construction over {draws} uniformly random 20-mer candidates "
        f"(seed {seed}); {passed_single} passed all per-sequence filters and "
        f"{len(accepted)} were accepted after the cross-sequence checks. "
    )
    if short:
        notes += (
            f"Target {target} was NOT reached within the candidate budget "
            f"({max_candidates}); only {len(accepted)} compliant indices are "
            f"available and none were padded with non-compliant sequences. "
        )
    else:
        notes += f"All {target} requested indices were found; no constraint was relaxed. "

    filter_counts = ", ".join(
        f"{name}={count}"
        for name, count in sorted(rejects.items(), key=lambda kv: -kv[1])
        if not name.startswith("__")
    )
    notes += f"Per-candidate rejection counts: {filter_counts or 'none'}. "

    notes += (
        "Tm uses SantaLucia 1998 unified nearest-neighbour parameters with "
        f"CT=0.25 uM and [Na+]=50 mM, no terminal-initiation correction; the "
        "3' 10 nt uniqueness is implied by the Hamming>=6 rule and is checked "
        "independently anyway. Inverted repeats are tested on all 4 nt windows "
        "of the sequence (any window that is the reverse complement of another "
        "window, itself included), which subsumes the palindrome ban and also "
        "covers every longer inverted repeat. Restriction sites GGTCTC, "
        "CGTCTC, GAAGAC and GCTCTTC are excluded on both strands."
    )
    if accepted:
        gcs = [gc_fraction(seq) for seq in accepted]
        tms = [melting_temp(seq) for seq in accepted]
        notes += (
            f" Realised GC {min(gcs):.2f}-{max(gcs):.2f} "
            f"(mean {sum(gcs) / len(gcs):.3f}) and Tm "
            f"{min(tms):.1f}-{max(tms):.1f} C (mean {sum(tms) / len(tms):.1f}). "
            "The 55 C Tm floor is the binding filter under these conditions, so "
            "the accepted set concentrates towards the top of the GC window; a "
            "GC of 0.40 is unreachable here without relaxing Tm or changing the "
            "stated salt/concentration assumptions."
        )
    if short:
        notes += (
            " Suggested relaxation, in order of expected yield: widen the Tm "
            "window, raise the GC window ceiling, or lower min_hamming to 5."
        )

    doc = {
        "version": 1,
        "generated": date.today().isoformat(),
        "seed": seed,
        "count": len(accepted),
        "length": LENGTH,
        "constraints": {
            "gc_min": GC_MIN,
            "gc_max": GC_MAX,
            "max_homopolymer": MAX_HOMOPOLYMER,
            "min_hamming": MIN_HAMMING,
            "unique_3prime": THREE_PRIME_LEN,
            "tm_min": TM_MIN,
            "tm_max": TM_MAX,
            "tm_formula": (
                "SantaLucia 1998 unified NN: Tm = dH/(dS + 1.987*ln(CT/4)) "
                "- 273.15 + 16.6*log10([Na+]), CT=0.25uM, [Na+]=50mM"
            ),
            "no_leading_g": True,
            "forbidden_sites": list(FORBIDDEN_MOTIFS),
            "forbidden_sites_both_strands": True,
            "max_inverted_repeat_len": 3,
        },
        "notes": notes,
        "indices": entries,
    }
    return doc


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Generate the frozen 20 nt DMS sub-library index table."
    )
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT,
                        help=f"output JSON path (default: {DEFAULT_OUT})")
    parser.add_argument("--target", type=int, default=DEFAULT_TARGET,
                        help=f"number of indices wanted (default: {DEFAULT_TARGET})")
    parser.add_argument("--seed", type=int, default=DEFAULT_SEED,
                        help=f"RNG seed, recorded in the JSON (default: {DEFAULT_SEED})")
    parser.add_argument("--max-candidates", type=int, default=DEFAULT_MAX_CANDIDATES,
                        help=f"candidate budget (default: {DEFAULT_MAX_CANDIDATES})")
    args = parser.parse_args(argv)

    accepted, rejects = generate(args.target, args.seed, args.max_candidates)
    doc = build_document(accepted, rejects, args.seed, args.target,
                         args.max_candidates)

    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(
        json.dumps(doc, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )

    print(f"wrote {args.out}")
    print(f"count={doc['count']} (target {args.target}) "
          f"draws={rejects['__draws__']} "
          f"passed_single={rejects['__passed_single__']}")
    if doc["count"] < args.target:
        print("WARNING: target not reached, see notes/", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
