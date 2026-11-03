"""Reverse Windows-1252 double-encoding (mojibake) in UTF-8 text files.

Corruption chain: UTF-8 bytes -> decoded as CP1252 -> saved as UTF-8.
Inverse: take a run of CP1252-representable characters, encode back to bytes,
decode strictly as UTF-8. Guard rails keep legitimate text untouched:
  * the run must contain a CP1252 marker that never occurs in real Vietnamese
    or English prose ("Ã", "Ä", "Å", "Æ", "º", "»", "€", "™", "œ", "‡", "‰", ...)
  * the decoded result must contain only plausible Unicode ranges
  * the decoded result must not itself still look like mojibake
"""
import re
import sys
import pathlib

B2C, C2B = {}, {}
for b in range(0x80, 0x100):
    try:
        ch = bytes([b]).decode("cp1252")
    except UnicodeDecodeError:
        # Undefined CP1252 slots (0x81, 0x8D, 0x8F, 0x90, 0x9D) surface as the
        # raw control code point when the original tool decoded permissively.
        ch = chr(b)
    B2C[b] = ch
    C2B[ch] = b

CHARSET = "".join(sorted(C2B))
RUN = re.compile("[" + re.escape(CHARSET) + "]{2,}")
MARKERS = set("ÃÄÅÆÌº»€™œ‡‰›“”‘’–—…")

OK_RANGES = [
    (0x00A0, 0x00FF), (0x0100, 0x017F), (0x0180, 0x024F),
    (0x1E00, 0x1EFF), (0x2000, 0x206F), (0x20A0, 0x20CF),
    (0x2190, 0x21FF), (0x2300, 0x23FF), (0x2500, 0x257F),
    (0x2580, 0x259F), (0x25A0, 0x25FF), (0x2600, 0x27BF),
    (0x3000, 0x303F), (0x4E00, 0x9FFF), (0xFF00, 0xFFEF),
]


def plausible(text):
    for ch in text:
        o = ord(ch)
        if o < 0x80:
            continue
        if not any(lo <= o <= hi for lo, hi in OK_RANGES):
            return False
    return True


RELAXED = False


def fix_run(run):
    if not RELAXED and not (set(run) & MARKERS):
        return None
    try:
        raw = bytes(C2B[ch] for ch in run)
    except KeyError:
        return None
    try:
        out = raw.decode("utf-8")
    except UnicodeDecodeError:
        return None
    if out == run or not plausible(out):
        return None
    if not RELAXED and set(out) & {"Ã", "Â", "º", "»", "€", "™", "œ"}:
        return None
    return out


def resolve(run):
    """Fix the largest fixable slices of a run, left to right.

    A run can glue mojibake to a legitimate character (e.g. "Đ" + a real "Ã"),
    so a whole-run decode may fail even though part of it is repairable.
    """
    out = []
    i = 0
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


def process(path, apply):
    p = pathlib.Path(path)
    text = p.read_text(encoding="utf-8", newline="")
    hits = []

    def repl(m):
        fixed = resolve(m.group(0))
        if fixed == m.group(0):
            return m.group(0)
        hits.append((m.group(0), fixed))
        return fixed

    new = RUN.sub(repl, text)
    print(f"{path}: runs={len(hits)} a_tilde_before={text.count(chr(0x00c3))} "
          f"a_tilde_after={new.count(chr(0x00c3))}")
    for a, b in hits[:5]:
        print(f"   {a!r} -> {b!r}")
    if apply and new != text:
        p.write_text(new, encoding="utf-8", newline="")
    return len(hits)


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8", errors="backslashreplace")
    apply = "--apply" in sys.argv
    RELAXED = "--relaxed" in sys.argv
    globals()["RELAXED"] = RELAXED
    targets = [a for a in sys.argv[1:] if not a.startswith("--")]
    total = sum(process(t, apply) for t in targets)
    print(f"TOTAL runs fixed: {total} ({'applied' if apply else 'dry-run'})")
