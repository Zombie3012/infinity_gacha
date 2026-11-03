"""Reverse UTF-8 -> CP437 double-encoding in text files.

The affected CSVs were saved by a tool that decoded UTF-8 bytes through the
OEM/DOS code page (CP437), producing sequences like "N├óng cß║Ñp" for
"Nâng cấp". Encoding the run back to CP437 bytes and decoding strictly as UTF-8
recovers the original text.
"""
import re
import sys
import pathlib

B2C, C2B = {}, {}
for b in range(0x80, 0x100):
    ch = bytes([b]).decode("cp437")
    B2C[b] = ch
    C2B[ch] = b

CHARSET = "".join(sorted(C2B))
RUN = re.compile("[" + re.escape(CHARSET) + "]{2,}")

# Characters that only appear in CP437 mojibake of Vietnamese/Latin text.
MARKERS = set("├┤┬┼╞╫╬─│└┌┐┘Γ╠╡╢╖╕╣║╗╝╜╛┴╤╥╙╘╒╓╪┘┌")


def fix_run(run: str):
    if not (set(run) & MARKERS):
        return None
    try:
        raw = bytes(C2B[ch] for ch in run)
        out = raw.decode("utf-8")
    except (KeyError, UnicodeDecodeError):
        return None
    if out == run:
        return None
    if "\ufffd" in out or any(ord(c) < 0x20 for c in out):
        return None
    return out


def resolve(run: str) -> str:
    out, i = [], 0
    while i < len(run):
        for n in range(len(run) - i, 1, -1):
            fixed = fix_run(run[i:i + n])
            if fixed is not None:
                out.append(fixed)
                i += n
                break
        else:
            out.append(run[i])
            i += 1
    return "".join(out)


def process(path: pathlib.Path, apply: bool) -> int:
    text = path.read_text(encoding="utf-8")
    hits = []

    def repl(m):
        fixed = resolve(m.group(0))
        if fixed != m.group(0):
            hits.append((m.group(0), fixed))
        return fixed

    new = RUN.sub(repl, text)
    print(f"{path.name}: runs={len(hits)}")
    for a, b in hits[:8]:
        print(f"   {a!r} -> {b!r}")
    if apply and new != text:
        path.write_text(new, encoding="utf-8", newline="")
    return len(hits)


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8", errors="backslashreplace")
    apply = "--apply" in sys.argv
    targets = [pathlib.Path(a) for a in sys.argv[1:] if not a.startswith("--")]
    total = sum(process(t, apply) for t in targets)
    print(f"TOTAL runs fixed: {total} ({'applied' if apply else 'dry-run'})")
