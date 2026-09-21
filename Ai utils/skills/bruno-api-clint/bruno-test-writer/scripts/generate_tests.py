#!/usr/bin/env python3
"""Generate a starter Bruno test script from a sample JSON response."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any, List

# Refuse pathologically large samples so failure is predictable rather than OOM.
MAX_SAMPLE_BYTES = 5 * 1024 * 1024


def js_string(value: str) -> str:
    return json.dumps(value)


def infer_required_fields(sample: Any, prefix: str = "body", max_depth: int = 2) -> List[str]:
    lines: List[str] = []
    if max_depth < 0:
        return lines
    if isinstance(sample, dict):
        for key, value in sample.items():
            key_literal = js_string(key)
            lines.append(f"  expect({prefix}).to.have.property({key_literal});")
            child = f"{prefix}[{key_literal}]"
            if isinstance(value, dict) and max_depth > 0:
                lines.append(f"  expect({child}).to.be.an(\"object\");")
                lines.extend(infer_required_fields(value, child, max_depth - 1))
            elif isinstance(value, list):
                lines.append(f"  expect({child}).to.be.an(\"array\");")
    elif isinstance(sample, list):
        lines.append(f"  expect({prefix}).to.be.an(\"array\");")
        if sample and isinstance(sample[0], dict):
            lines.append(f"  if ({prefix}.length > 0) {{")
            nested = infer_required_fields(sample[0], f"{prefix}[0]", max_depth - 1)
            lines.extend("  " + line for line in nested)
            lines.append("  }")
    return lines


def render_tests(sample: Any, status: int, name: str) -> str:
    title = name.strip() or "request"
    lines: List[str] = []
    lines.append(f"test({js_string(title + ' should return expected status')}, function () {{")
    lines.append(f"  expect(res.getStatus()).to.equal({status});")
    lines.append("});")
    lines.append("")

    if isinstance(sample, dict):
        lines.append(f"test({js_string(title + ' should return expected fields')}, function () {{")
        lines.append("  const body = res.getBody();")
        lines.append("  expect(body).to.be.an(\"object\");")
        lines.extend(infer_required_fields(sample))
        lines.append("});")
    elif isinstance(sample, list):
        lines.append(f"test({js_string(title + ' should return expected array shape')}, function () {{")
        lines.append("  const body = res.getBody();")
        lines.extend(infer_required_fields(sample))
        lines.append("});")
    else:
        lines.append(f"test({js_string(title + ' should return a response body')}, function () {{")
        lines.append("  expect(res.getBody()).to.not.equal(undefined);")
        lines.append("});")

    lines.append("")
    lines.append("// TODO: Add business-specific edge-case tests once the API contract is known.")
    return "\n".join(lines) + "\n"


def load_sample(path_str: str) -> Any:
    path = Path(path_str)
    try:
        size = path.stat().st_size
    except OSError as exc:
        raise SystemExit(f"error: cannot read sample {path}: {exc}")
    if size > MAX_SAMPLE_BYTES:
        raise SystemExit(
            f"error: sample {path} is {size} bytes, larger than the "
            f"{MAX_SAMPLE_BYTES}-byte limit"
        )
    try:
        text = path.read_text()
    except OSError as exc:
        raise SystemExit(f"error: cannot read sample {path}: {exc}")
    try:
        return json.loads(text)
    except json.JSONDecodeError as exc:
        raise SystemExit(f"error: sample {path} is not valid JSON: {exc}")


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate Bruno tests from a sample JSON response")
    parser.add_argument("--sample", required=True, help="Path to sample JSON response")
    parser.add_argument("--status", type=int, default=200, help="Expected HTTP status code")
    parser.add_argument("--name", default="Request", help="Request name used in test names")
    parser.add_argument("--out", help="Optional output path. Prints to stdout if omitted")
    parser.add_argument("--force", action="store_true", help="Overwrite --out if it already exists")
    args = parser.parse_args()

    if not 100 <= args.status <= 599:
        raise SystemExit(f"error: --status {args.status} is not a valid HTTP status code (100-599)")

    sample = load_sample(args.sample)
    tests = render_tests(sample, args.status, args.name)
    if args.out:
        out_path = Path(args.out)
        if out_path.exists() and not args.force:
            raise SystemExit(
                f"error: {out_path} already exists; pass --force to overwrite"
            )
        out_path.write_text(tests)
        print(f"Wrote {out_path}")
    else:
        print(tests, end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
