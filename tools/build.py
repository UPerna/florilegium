"""Build a florilegium document with LuaLaTeX or XeLaTeX, without shell escape.

python3 tools/build.py book-demo.tex --engine xe --output-dir build/xe
"""
import argparse
import hashlib
import os
from pathlib import Path
import re
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
AUXILIARY_SUFFIXES = {".aux", ".toc", ".out", ".lof", ".lot", ".nav", ".snm"}


def state(folder, name, engine):
    files = {folder / (name + ext) for ext in AUXILIARY_SUFFIXES}
    if engine == "xe":
        files.add(folder / (name + ".flo"))
    recorder = folder / (name + ".fls")
    if recorder.is_file():
        for line in recorder.read_text(errors="replace").splitlines():
            if line.startswith("OUTPUT "):
                path = Path(line[7:])
                if not path.is_absolute():
                    path = folder / path
                if path.suffix in AUXILIARY_SUFFIXES:
                    files.add(path.resolve())
    return tuple((str(path), hashlib.sha256(path.read_bytes()).hexdigest() if path.is_file() else None)
                 for path in sorted(files))


def complete_pdf(path, logfile):
    # A successful compiler exit does not establish that its output is complete.
    # Full parsing/rendering belongs to the integration checks, not this cheap guard.
    if path.is_file():
        with path.open("rb") as file:
            header = file.read(8)
            file.seek(max(0, path.stat().st_size - 1024))
            tail = file.read()
        if header.startswith(b"%PDF-") and tail.rstrip().endswith(b"%%EOF"):
            return
    raise RuntimeError(f"Compiler reported success but its PDF is missing or incomplete: {path}; see {logfile}")


def build(source, engine="lua", output_dir=None, job_name=None, max_passes=6, botanical_contracts=False):
    source = Path(source).resolve()
    if not source.is_file():
        raise ValueError(f"Source not found: {source}")
    executable = {"lua": "lualatex", "xe": "xelatex"}[engine]
    for command in [executable] + (["texlua"] if engine == "xe" else []):
        if not shutil.which(command):
            raise RuntimeError(f"{command} is required")
    folder = Path(output_dir or ROOT / "build" / engine).resolve()
    folder.mkdir(parents=True, exist_ok=True)
    name = job_name or re.sub(r"[^A-Za-z0-9_.-]", "_", source.stem)
    if not re.fullmatch(r"[A-Za-z0-9_-][A-Za-z0-9_.-]*", name):
        raise ValueError("Job name must use letters, digits, underscore, hyphen or dot")
    if any(c in source.as_posix() for c in '\\{}%#\n"'):
        raise ValueError("Source path contains characters that cannot be passed literally to TeX")
    env = os.environ.copy()
    # Running in the output directory lets xdvipdfmx find generated PDFs, even
    # when that directory contains spaces. Source and installed packages remain
    # available through their normal TeX/Lua search mechanisms.
    env["TEXINPUTS"] = os.pathsep.join([str(source.parent), str(ROOT), env.get("TEXINPUTS", "")])
    env["LUAINPUTS"] = os.pathsep.join([str(ROOT), env.get("LUAINPUTS", "")])
    previous = rendered = None
    pdf = folder / (name + ".pdf")
    for run in range(1, max_passes + 1):
        pdf.unlink(missing_ok=True)
        prelude = (r"\AtBeginDocument{\directlua{require('pattern_botanical_legacy').install(function(x,d) texio.write_nl('botanical-contract: validated '..d.id) end)}}"
                   if botanical_contracts and engine == "lua" else "")
        result = subprocess.run([executable, "-no-shell-escape", "-halt-on-error", "-interaction=nonstopmode", "-recorder",
                                 f"-jobname={name}", prelude + r"\input{" + source.as_posix() + "}"],
                                cwd=folder, env=env, capture_output=True, text=True)
        logfile = folder / f"{name}.pass-{run}.log"
        logfile.write_text(result.stdout + result.stderr)
        if result.returncode:
            tail = "\n".join((result.stdout + result.stderr).splitlines()[-24:])
            raise RuntimeError(f"{executable} failed; see {logfile}\n{tail}")
        complete_pdf(pdf, logfile)
        current = state(folder, name, engine)
        if engine == "xe":
            record = folder / (name + ".flo")
            if not record.exists():
                raise RuntimeError("XeLaTeX produced no florilegium records")
            digest = hashlib.sha256(record.read_bytes()).hexdigest()
            if digest == rendered and current == previous:
                return folder / (name + ".pdf")
            if digest != rendered:
                draw_command = ["texlua", str(ROOT / "florilegium-xe.lua"), str(folder / name)]
                if botanical_contracts:
                    draw_command.append("--botanical-contracts")
                draw = subprocess.run(draw_command,
                                      cwd=folder, env=env, capture_output=True, text=True)
                drawlog = folder / f"{name}.render-{run}.log"
                drawlog.write_text(draw.stdout + draw.stderr)
                if draw.returncode:
                    tail = "\n".join((draw.stdout + draw.stderr).splitlines()[-24:])
                    raise RuntimeError(f"Vector rendering failed; see {drawlog}\n{tail}")
                rendered = digest
        elif current == previous:
            return folder / (name + ".pdf")
        previous = current
    raise RuntimeError(f"Document did not converge in {max_passes} passes; see {folder}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("--engine", choices=("lua", "xe"), default="lua")
    parser.add_argument("--output-dir", type=Path)
    parser.add_argument("--job-name")
    parser.add_argument("--botanical-contracts", action="store_true", help="observe and validate the existing composition through common contracts")
    args = parser.parse_args()
    try:
        print(build(args.source, args.engine, args.output_dir, args.job_name, botanical_contracts=args.botanical_contracts))
    except (RuntimeError, ValueError) as error:
        raise SystemExit(str(error)) from error


if __name__ == "__main__":
    main()
