#!/usr/bin/env python3
import json
from pathlib import Path


def make_identity_sequence_case():
    dim = 4
    a = []
    b = []
    for r in range(dim):
        for c in range(dim):
            a.append(1024 if r == c else 0)
            b.append(((r * dim) + c + 1) * 256)
    return {
        "name": "square4_identity_seq",
        "dim": dim,
        "notes": "Compatibility-sized 4x4 case for the tiled path.",
        "a_q5_10": a,
        "b_q5_10": b,
    }


def make_pattern_case(name, dim, a_seed, b_seed, a_scale=96, b_scale=80):
    a = []
    b = []
    for r in range(dim):
        for c in range(dim):
            aval = (((r * (a_seed + 2)) + (c * (a_seed + 5)) + 3) % 9) - 4
            bval = (((r * (b_seed + 4)) - (c * (b_seed + 1)) + 11) % 11) - 5
            a.append(aval * a_scale)
            b.append(bval * b_scale)
    return {
        "name": name,
        "dim": dim,
        "notes": f"Deterministic {dim}x{dim} case with small amplitudes to avoid tile-overflow ambiguity.",
        "a_q5_10": a,
        "b_q5_10": b,
    }


def main():
    cases = {
        "cases": [
            make_identity_sequence_case(),
            make_pattern_case("square8_pattern", 8, 1, 2),
            make_pattern_case("square10_edge", 10, 2, 3),
            make_pattern_case("square16_pattern", 16, 3, 4),
            make_pattern_case("square32_pattern", 32, 4, 5),
        ]
    }

    out_path = Path(__file__).with_name("cases_square.json")
    out_path.write_text(json.dumps(cases, indent=2) + "\n", encoding="utf-8")
    print(f"Wrote {out_path}")


if __name__ == "__main__":
    main()
