#!/usr/bin/env node
/**
 * Encoding guard: refuses to pass when source text contains UTF-8 bytes that
 * were decoded through CP437 or Windows-1252 and saved again ("mojibake").
 *
 * For every run of characters that exist in those code pages, the guard tries
 * the inverse transform (re-encode -> strict UTF-8 decode). A successful decode
 * means the text is corrupted, because ordinary prose never round-trips like
 * that. Box drawing such as the README tree does not trip it.
 */
import { readFileSync, readdirSync, statSync } from "node:fs";
import { join, relative } from "node:path";

const CP437 = ["\u00c7", "\u00fc", "\u00e9", "\u00e2", "\u00e4", "\u00e0", "\u00e5", "\u00e7", "\u00ea", "\u00eb", "\u00e8", "\u00ef", "\u00ee", "\u00ec", "\u00c4", "\u00c5", "\u00c9", "\u00e6", "\u00c6", "\u00f4", "\u00f6", "\u00f2", "\u00fb", "\u00f9", "\u00ff", "\u00d6", "\u00dc", "\u00a2", "\u00a3", "\u00a5", "\u20a7", "\u0192", "\u00e1", "\u00ed", "\u00f3", "\u00fa", "\u00f1", "\u00d1", "\u00aa", "\u00ba", "\u00bf", "\u2310", "\u00ac", "\u00bd", "\u00bc", "\u00a1", "\u00ab", "\u00bb", "\u2591", "\u2592", "\u2593", "\u2502", "\u2524", "\u2561", "\u2562", "\u2556", "\u2555", "\u2563", "\u2551", "\u2557", "\u255d", "\u255c", "\u255b", "\u2510", "\u2514", "\u2534", "\u252c", "\u251c", "\u2500", "\u253c", "\u255e", "\u255f", "\u255a", "\u2554", "\u2569", "\u2566", "\u2560", "\u2550", "\u256c", "\u2567", "\u2568", "\u2564", "\u2565", "\u2559", "\u2558", "\u2552", "\u2553", "\u256b", "\u256a", "\u2518", "\u250c", "\u2588", "\u2584", "\u258c", "\u2590", "\u2580", "\u03b1", "\u00df", "\u0393", "\u03c0", "\u03a3", "\u03c3", "\u00b5", "\u03c4", "\u03a6", "\u0398", "\u03a9", "\u03b4", "\u221e", "\u03c6", "\u03b5", "\u2229", "\u2261", "\u00b1", "\u2265", "\u2264", "\u2320", "\u2321", "\u00f7", "\u2248", "\u00b0", "\u2219", "\u00b7", "\u221a", "\u207f", "\u00b2", "\u25a0", "\u00a0"];
const CP1252 = ["\u20ac", null, "\u201a", "\u0192", "\u201e", "\u2026", "\u2020", "\u2021", "\u02c6", "\u2030", "\u0160", "\u2039", "\u0152", null, "\u017d", null, null, "\u2018", "\u2019", "\u201c", "\u201d", "\u2022", "\u2013", "\u2014", "\u02dc", "\u2122", "\u0161", "\u203a", "\u0153", null, "\u017e", "\u0178", "\u00a0", "\u00a1", "\u00a2", "\u00a3", "\u00a4", "\u00a5", "\u00a6", "\u00a7", "\u00a8", "\u00a9", "\u00aa", "\u00ab", "\u00ac", "\u00ad", "\u00ae", "\u00af", "\u00b0", "\u00b1", "\u00b2", "\u00b3", "\u00b4", "\u00b5", "\u00b6", "\u00b7", "\u00b8", "\u00b9", "\u00ba", "\u00bb", "\u00bc", "\u00bd", "\u00be", "\u00bf", "\u00c0", "\u00c1", "\u00c2", "\u00c3", "\u00c4", "\u00c5", "\u00c6", "\u00c7", "\u00c8", "\u00c9", "\u00ca", "\u00cb", "\u00cc", "\u00cd", "\u00ce", "\u00cf", "\u00d0", "\u00d1", "\u00d2", "\u00d3", "\u00d4", "\u00d5", "\u00d6", "\u00d7", "\u00d8", "\u00d9", "\u00da", "\u00db", "\u00dc", "\u00dd", "\u00de", "\u00df", "\u00e0", "\u00e1", "\u00e2", "\u00e3", "\u00e4", "\u00e5", "\u00e6", "\u00e7", "\u00e8", "\u00e9", "\u00ea", "\u00eb", "\u00ec", "\u00ed", "\u00ee", "\u00ef", "\u00f0", "\u00f1", "\u00f2", "\u00f3", "\u00f4", "\u00f5", "\u00f6", "\u00f7", "\u00f8", "\u00f9", "\u00fa", "\u00fb", "\u00fc", "\u00fd", "\u00fe", "\u00ff"];

const CODECS = [CP437, CP1252];
const SKIP_DIRS = new Set(["node_modules", "dist", ".git"]);
const EXTENSIONS = new Set([".ts", ".tsx", ".js", ".mjs", ".cjs", ".json", ".md", ".csv", ".sql", ".css", ".html", ".yml", ".yaml"]);

const toByte = new Map();
for (const table of CODECS) {
  table.forEach((char, index) => {
    if (char && !toByte.has(char)) toByte.set(char, index + 0x80);
  });
}

const charset = [...toByte.keys()].join("");
const escape = (value) => value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
const RUN = new RegExp(`[${escape(charset)}]{2,}`, "g");

function decodeRun(run) {
  const bytes = [];
  for (const char of run) {
    const byte = toByte.get(char);
    if (byte === undefined) return null;
    bytes.push(byte);
  }
  try {
    const decoded = new TextDecoder("utf-8", { fatal: true }).decode(Uint8Array.from(bytes));
    if (decoded === run) return null;
    if ([...decoded].some((char) => char.codePointAt(0) < 0x20 && char !== "\t")) return null;
    return decoded;
  } catch {
    return null;
  }
}

const files = [];
function walk(dir) {
  for (const entry of readdirSync(dir)) {
    if (SKIP_DIRS.has(entry)) continue;
    const path = join(dir, entry);
    const stats = statSync(path);
    if (stats.isDirectory()) walk(path);
    else if (EXTENSIONS.has(entry.slice(entry.lastIndexOf(".")))) files.push(path);
  }
}

walk(".");
const violations = [];
for (const file of files) {
  const text = readFileSync(file, "utf8");
  for (const match of text.matchAll(RUN)) {
    const decoded = decodeRun(match[0]);
    if (!decoded) continue;
    const line = text.slice(0, match.index).split("\n").length;
    violations.push({ file: relative(".", file), line, found: match[0], looksLike: decoded });
  }
}

if (violations.length === 0) {
  console.log(`Encoding check passed (${files.length} files).`);
  process.exit(0);
}

console.error(`Found ${violations.length} corrupted text run(s):`);
for (const item of violations.slice(0, 30)) {
  console.error(`  ${item.file}:${item.line}  "${item.found}" -> "${item.looksLike}"`);
}
if (violations.length > 30) console.error(`  ... and ${violations.length - 30} more`);
console.error("Fix with: python scripts/fix_mojibake_cp1252.py --apply <files> / python scripts/fix_mojibake_cp437.py --apply <files>");
process.exit(1);
