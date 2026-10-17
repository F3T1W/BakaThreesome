"""Reject Cyrillic text in maintained files, file names, and local commit messages."""

from pathlib import Path
import subprocess
import sys
import unicodedata


root = Path(__file__).resolve().parent.parent


def git(*arguments: str) -> subprocess.CompletedProcess:
    return subprocess.run(
        ["git", "-C", str(root), *arguments],
        capture_output=True, check=True,
    )


def contains_cyrillic(text: str) -> bool:
    return any("CYRILLIC" in unicodedata.name(character, "") for character in text)


failures = []
paths = git("ls-files", "--cached", "--others", "--exclude-standard", "-z")
for relative in sorted(set(paths.stdout.decode("utf-8").split("\0")) - {""}):
    if contains_cyrillic(relative):
        failures.append(f"File name contains Cyrillic characters: {relative!a}")
    path = root / relative
    if not path.is_file() or path.is_symlink():
        continue
    try:
        content = path.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        continue
    for number, line in enumerate(content.splitlines(), start=1):
        if contains_cyrillic(line):
            failures.append(f"{relative}:{number}: Cyrillic characters are not allowed.")

head = subprocess.run(
    ["git", "-C", str(root), "rev-parse", "--verify", "HEAD"],
    capture_output=True,
)
if head.returncode == 0:
    commits = git("log", "--all", "--format=%H%x00%B%x00")
    fields = commits.stdout.decode("utf-8").split("\0")
    for index in range(0, len(fields) - 1, 2):
        if contains_cyrillic(fields[index + 1]):
            failures.append(f"Commit {fields[index].strip()}: message contains Cyrillic characters.")

if failures:
    print("English-only project check failed:", file=sys.stderr)
    print("\n".join(failures), file=sys.stderr)
    sys.exit(1)

print("English-only project check passed: no Cyrillic in maintained files or commit messages.")
