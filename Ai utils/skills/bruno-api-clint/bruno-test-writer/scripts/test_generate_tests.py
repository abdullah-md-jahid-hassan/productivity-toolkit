"""Tests for generate_tests.py, covering rendering and the hardened guard paths.

Run with:  pytest scripts/test_generate_tests.py
"""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

import pytest

SCRIPT = Path(__file__).with_name("generate_tests.py")


def run(*args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, str(SCRIPT), *args],
        capture_output=True,
        text=True,
    )


def write(tmp_path: Path, name: str, content: str) -> Path:
    path = tmp_path / name
    path.write_text(content)
    return path


# --- happy path -------------------------------------------------------------


def test_object_sample_renders_field_assertions(tmp_path: Path) -> None:
    sample = write(tmp_path, "s.json", '{"id":1,"email":"a@b.com","tags":["x"]}')
    result = run("--sample", str(sample), "--status", "200", "--name", "Get User")
    assert result.returncode == 0
    assert 'expect(res.getStatus()).to.equal(200);' in result.stdout
    assert 'expect(body).to.have.property("id");' in result.stdout
    assert 'expect(body["tags"]).to.be.an("array");' in result.stdout
    assert "Get User should return expected fields" in result.stdout


def test_writes_to_out_file(tmp_path: Path) -> None:
    sample = write(tmp_path, "s.json", "{}")
    out = tmp_path / "tests.js"
    result = run("--sample", str(sample), "--out", str(out))
    assert result.returncode == 0
    assert out.exists()
    assert "res.getStatus()" in out.read_text()


# --- guard paths ------------------------------------------------------------


def test_missing_sample_file_exits_cleanly(tmp_path: Path) -> None:
    result = run("--sample", str(tmp_path / "nope.json"))
    assert result.returncode == 1
    assert "cannot read sample" in result.stderr
    assert "Traceback" not in result.stderr


def test_invalid_json_exits_cleanly(tmp_path: Path) -> None:
    bad = write(tmp_path, "bad.json", "not json")
    result = run("--sample", str(bad))
    assert result.returncode == 1
    assert "not valid JSON" in result.stderr
    assert "Traceback" not in result.stderr


def test_out_of_range_status_rejected(tmp_path: Path) -> None:
    sample = write(tmp_path, "s.json", "{}")
    result = run("--sample", str(sample), "--status", "999")
    assert result.returncode == 1
    assert "not a valid HTTP status code" in result.stderr


def test_refuses_to_overwrite_without_force(tmp_path: Path) -> None:
    sample = write(tmp_path, "s.json", "{}")
    out = write(tmp_path, "existing.js", "// hand-written, do not clobber")
    result = run("--sample", str(sample), "--out", str(out))
    assert result.returncode == 1
    assert "already exists" in result.stderr
    assert out.read_text() == "// hand-written, do not clobber"


def test_force_overwrites(tmp_path: Path) -> None:
    sample = write(tmp_path, "s.json", "{}")
    out = write(tmp_path, "existing.js", "// old")
    result = run("--sample", str(sample), "--out", str(out), "--force")
    assert result.returncode == 0
    assert "res.getStatus()" in out.read_text()


def test_oversized_sample_rejected(tmp_path: Path) -> None:
    big = tmp_path / "big.json"
    # Valid JSON string just over the 5 MB limit.
    big.write_text('"' + "a" * (5 * 1024 * 1024 + 10) + '"')
    result = run("--sample", str(big))
    assert result.returncode == 1
    assert "larger than" in result.stderr


if __name__ == "__main__":
    raise SystemExit(pytest.main([__file__, "-v"]))
