"""Create a reproducible source kit with examples, previews and a SHA-256 manifest."""
import hashlib
from pathlib import Path
import stat
import zipfile

ROOT = Path(__file__).resolve().parents[1]
REQUIRED_NOTICES = {"pattern_hat_rules.lua": "docs/research/licenses/HATVIZ-BSD-3-Clause.txt"}


def package(output=None):
    paths = set()
    for pattern in ("*.lua", "*.sty", "*.def", "*.tex", "*.md"):
        paths.update(ROOT.glob(pattern))
    paths.update(ROOT / name for name in ("LICENSE", "Makefile"))
    for directory, extensions in (("tools", {".py", ".lua"}),
                                  ("examples", {".tex", ".md", ".pdf", ".svg"}),
                                  ("gallery", {".png", ".gif", ".jpg", ".jpeg"}),
                                  ("postscript", {".ps"}),
                                  ("docs", {".md", ".json", ".csv"}),
                                  ("artifacts/receipts", {".json"})):
        paths.update(p for p in (ROOT / directory).rglob("*") if p.suffix in extensions)
    paths.update(ROOT / "tools" / name for name in ("Dockerfile", "in-docker"))
    for module, notice in REQUIRED_NOTICES.items():
        if ROOT / module in paths and (ROOT / module).is_file():
            license_path = ROOT / notice
            if not license_path.is_file() or license_path.is_symlink():
                raise FileNotFoundError(f"Required notice for {module} is missing: {notice}")
            paths.add(license_path)
    paths = sorted(p for p in paths if p.is_file() and not p.is_symlink() and not p.name.endswith("-flo.tex"))
    output = Path(output or ROOT / "build/florilegium-v1.4-source.zip")
    output.parent.mkdir(parents=True, exist_ok=True)
    manifest = []
    with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for path in paths:
            name = path.relative_to(ROOT).as_posix()
            data = path.read_bytes()
            manifest.append(hashlib.sha256(data).hexdigest() + "  " + name)
            info = zipfile.ZipInfo("florilegium/" + name, date_time=(1980, 1, 1, 0, 0, 0))
            info.create_system = 3
            info.external_attr = (stat.S_IFREG | (path.stat().st_mode & 0o777)) << 16
            info.compress_type = zipfile.ZIP_DEFLATED
            archive.writestr(info, data)
        info = zipfile.ZipInfo("florilegium/SHA256SUMS", date_time=(1980, 1, 1, 0, 0, 0))
        info.compress_type = zipfile.ZIP_DEFLATED
        archive.writestr(info, "\n".join(manifest) + "\n")
    return output


if __name__ == "__main__":
    print(package())
