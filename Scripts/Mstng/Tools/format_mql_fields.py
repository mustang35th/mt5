"""Check/fix field spacing in Include/Mstng* without rewriting nonblank lines.

Run with --check (exit 0: clean, 1: spacing violations, 2: unsupported/error)
or --fix. Repeat --folder PATH to limit work to Include/Mstng* subfolders.
Unknown declarations are reported and the containing file is left untouched.
"""

import argparse
import bisect
import codecs
from dataclasses import dataclass
from pathlib import Path
import re
import sys


TOKEN_PATTERN = re.compile(
    r"(?P<space>\s+)"
    r"|(?P<comment>//[^\r\n]*|/\*[\s\S]*?\*/)"
    r'''|(?P<string>"(?:\\[\s\S]|[^"\\])*"|'(?:\\[\s\S]|[^'\\])*')'''
    r"|(?P<directive>\#(?:[^\r\n\\]|\\[^\r\n]|\\\r?\n)*)"
    r"|(?P<word>[A-Za-z_][A-Za-z_0-9]*)"
    r"|(?P<other>.)",
    re.DOTALL,
)
IDENTIFIER = re.compile(r"[A-Za-z_][A-Za-z_0-9]*\Z")
QUALIFIERS = {"const", "static", "unsigned", "signed"}


@dataclass
class Token:
    value: str
    kind: str
    start: int
    end: int
    line: int
    endLine: int


@dataclass
class Edit:
    startLine: int
    endLine: int
    replacement: list
    reason: str


def decodeSource(fromData):
    """Decode reversibly; preserve the exact original BOM and encoding."""
    for bom, encoding in (
        (codecs.BOM_UTF8, "utf-8"),
        (codecs.BOM_UTF16_LE, "utf-16-le"),
        (codecs.BOM_UTF16_BE, "utf-16-be"),
    ):
        if fromData.startswith(bom):
            text = fromData[len(bom):].decode(encoding)
            return text, encoding, bom
    for encoding in ("utf-8", "cp932"):
        try:
            text = fromData.decode(encoding)
            if text.encode(encoding) == fromData and "\x00" not in text:
                return text, encoding, b""
        except UnicodeError:
            pass
    raise ValueError("unsupported encoding (expected UTF-8, BOM UTF-16, or CP932)")


class FieldFormatter:
    """Recognize class/struct members using tokens and balanced scopes."""

    def __init__(self, fromText):
        self.text = fromText
        self.lines = fromText.splitlines(keepends=True)
        self.lineStarts = []
        offset = 0
        for line in self.lines:
            self.lineStarts.append(offset)
            offset += len(line)
        self.tokens = []
        self.comments = []
        self.edits = []
        self.issues = []
        self.matches = {}
        self.tokenize()

    def tokenize(self):
        for match in TOKEN_PATTERN.finditer(self.text):
            kind = match.lastgroup
            if kind == "space":
                continue
            value = match.group()
            line = bisect.bisect_right(self.lineStarts, match.start()) - 1
            endLine = bisect.bisect_right(self.lineStarts, match.end() - 1) - 1
            token = Token(value, kind, match.start(), match.end(), line, endLine)
            if kind == "comment":
                self.comments.append(token)
            else:
                if kind == "other" and value in {'"', "'"}:
                    self.issues.append((line, "unterminated string literal"))
                if kind == "other" and self.text[match.start():].startswith("/*"):
                    self.issues.append((line, "unterminated block comment"))
                self.tokens.append(token)
        stack = []
        for index, token in enumerate(self.tokens):
            if token.kind in {"string", "directive"}:
                continue
            if token.value in {"{", "(", "["}:
                stack.append(index)
            elif token.value in {"}", ")", "]"}:
                expected = {"}": "{", ")": "(", "]": "["}[token.value]
                if not stack or self.tokens[stack[-1]].value != expected:
                    self.issues.append((token.line, "unbalanced delimiter"))
                    return
                opening = stack.pop()
                self.matches[opening] = index
        if stack:
            self.issues.append((self.tokens[stack[-1]].line, "unclosed delimiter"))

    def classOpening(self, fromStart, fromEnd):
        """Return a class/struct body opening, excluding forward declarations."""
        if self.tokens[fromStart].value not in {"class", "struct"}:
            return None
        for index in range(fromStart + 1, fromEnd):
            token = self.tokens[index]
            if token.value == "{":
                return index
            if token.value in {";", "(", "="} or token.kind == "directive":
                return None
        return None

    def fieldKind(self, fromStart, fromEnd):
        """Accept simple typed declarations; distinguish method prototypes."""
        values = [token.value for token in self.tokens[fromStart:fromEnd]]
        if not values:
            return "other"
        if values[0] in {"class", "struct", "enum", "typedef"}:
            return "other"
        declaration = values
        if "=" in values:
            declaration = values[:values.index("=")]
        if "(" in declaration:
            opening = declaration.index("(")
            if (opening and IDENTIFIER.fullmatch(declaration[opening - 1])
                    and opening + 1 < len(declaration)
                    and declaration[opening + 1] not in {"*", "&", "("}):
                return "method"
            return "unknown"
        index = 0
        while index < len(declaration) and declaration[index] in QUALIFIERS:
            index += 1
        if index >= len(declaration) or not IDENTIFIER.fullmatch(declaration[index]):
            return "unknown"
        index += 1
        while index < len(declaration) and declaration[index] in {"*", "&", "const"}:
            index += 1
        if index >= len(declaration) or not IDENTIFIER.fullmatch(declaration[index]):
            return "unknown"
        index += 1
        while index < len(declaration):
            if declaration[index] != "[":
                return "unknown"
            index += 1
            depth = 1
            while index < len(declaration) and depth:
                if declaration[index] == "[":
                    depth += 1
                elif declaration[index] == "]":
                    depth -= 1
                index += 1
            if depth:
                return "unknown"
        return "field"

    def blankGap(self, fromStart, fromEnd, fromCount, fromReason):
        gap = self.lines[fromStart:fromEnd]
        if any(line.strip() for line in gap) or len(gap) == fromCount:
            return
        replacement = []
        if fromCount:
            if gap:
                replacement = gap[:1]
            else:
                preceding = self.lines[fromStart - 1]
                if preceding.endswith("\r\n"):
                    replacement = ["\r\n"]
                elif preceding.endswith("\n"):
                    replacement = ["\n"]
                elif preceding.endswith("\r"):
                    replacement = ["\r"]
                else:
                    raise ValueError("cannot insert a blank line after an unterminated line")
        self.edits.append(Edit(fromStart, fromEnd, replacement, fromReason))

    def addField(self, fromStart, fromEnd, fromBoundary, fromPrevious):
        first = self.tokens[fromStart]
        last = self.tokens[fromEnd]
        if ((fromStart and self.tokens[fromStart - 1].endLine == first.line)
                or (fromEnd + 1 < len(self.tokens)
                    and self.tokens[fromEnd + 1].line == last.endLine)):
            self.issues.append((first.line, "member shares a line with another declaration or scope"))
            return None
        groupLine = first.line
        cursor = first.start
        attached = []
        for comment in reversed(self.comments):
            if comment.end > cursor:
                continue
            if comment.start < fromBoundary or self.text[comment.end:cursor].strip():
                break
            prefix = self.text[self.lineStarts[comment.line]:comment.start]
            if prefix.strip():
                break
            attached.append(comment)
            groupLine = comment.line
            cursor = comment.start
        if attached:
            self.blankGap(attached[0].endLine + 1, first.line, 0,
                          "remove blank lines between field comment and declaration")
        if fromPrevious is not None:
            self.blankGap(fromPrevious + 1, groupLine, 1,
                          "separate adjacent field groups with one blank line")
        return last.endLine

    def parseClass(self, fromOpening):
        closing = self.matches[fromOpening]
        index = fromOpening + 1
        boundary = self.tokens[fromOpening].end
        previous = None
        while index < closing:
            first = self.tokens[index]
            if first.kind == "directive":
                self.issues.append((first.line, "preprocessor directive inside class/struct"))
                index += 1
                previous = None
                boundary = first.end
                continue
            if (first.value in {"public", "protected", "private"}
                    and index + 1 < closing and self.tokens[index + 1].value == ":"):
                index += 2
                boundary = self.tokens[index - 1].end
                previous = None
                continue
            start = index
            nested = self.classOpening(start, closing)
            if nested is not None:
                self.parseClass(nested)
            while index < closing:
                token = self.tokens[index]
                if token.kind == "directive":
                    self.issues.append((token.line, "preprocessor directive splits a member"))
                    break
                if token.value in {"(", "["}:
                    index = self.matches[index] + 1
                    continue
                if token.value == "{":
                    prefix = [item.value for item in self.tokens[start:index]]
                    if "=" in prefix and "(" not in prefix:
                        index = self.matches[index] + 1
                        continue
                    index = self.matches[index] + 1
                    if index < closing and self.tokens[index].value == ";":
                        index += 1
                    boundary = self.tokens[index - 1].end
                    previous = None
                    break
                if token.value == ";":
                    kind = self.fieldKind(start, index)
                    if kind == "field":
                        previous = self.addField(start, index, boundary, previous)
                    else:
                        previous = None
                        if kind == "unknown":
                            self.issues.append((first.line, "unsupported member declaration"))
                    boundary = token.end
                    index += 1
                    break
                index += 1
            else:
                self.issues.append((first.line, "unterminated member declaration"))
            if index == start:
                index += 1

    def format(self):
        if self.issues:
            return self.text, [], self.issues
        index = 0
        while index < len(self.tokens):
            opening = self.classOpening(index, len(self.tokens))
            if opening is not None:
                self.parseClass(opening)
                index = self.matches[opening] + 1
            elif self.tokens[index].value == "{":
                index = self.matches[index] + 1
            else:
                index += 1
        if self.issues:
            return self.text, [], self.issues
        output = self.lines[:]
        lastStart = len(output) + 1
        for edit in sorted(self.edits, key=lambda item: item.startLine, reverse=True):
            if edit.endLine > lastStart:
                raise ValueError("overlapping spacing edits")
            output[edit.startLine:edit.endLine] = edit.replacement
            lastStart = edit.startLine
        if [line for line in output if line.strip()] != [line for line in self.lines if line.strip()]:
            raise ValueError("nonblank-line preservation check failed")
        return "".join(output), self.edits, []


def targetFiles(fromRoot, fromFolders):
    include = (fromRoot / "Include").resolve()
    available = {
        folder.name: folder for folder in include.iterdir()
        if folder.is_dir() and folder.name.startswith("Mstng")
    }
    names = sorted(set(fromFolders or available))
    visited = set()
    for name in names:
        parts = name.replace("\\", "/").split("/")
        if (not parts or parts[0] not in available
                or any(part in {"", ".", ".."} for part in parts)):
            raise ValueError(f"expected a relative Include/Mstng* folder: {name}")
        topFolder = available[parts[0]]
        folder = include.joinpath(*parts)
        if (topFolder.resolve().parent != include
                or not topFolder.resolve().name.startswith("Mstng") or not folder.is_dir()
                or not folder.resolve().is_relative_to(topFolder.resolve())):
            raise ValueError(f"folder is missing or resolves outside Include/Mstng*: {name}")
        for path in sorted(folder.rglob("*")):
            if path.is_file() and path.suffix.lower() in {".mqh", ".mq5"}:
                if not path.resolve().is_relative_to(folder.resolve()):
                    raise ValueError(f"file resolves outside selected folder: {path}")
                if path.resolve() not in visited:
                    visited.add(path.resolve())
                    yield path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--check", action="store_true", help="report without writing")
    mode.add_argument("--fix", action="store_true", help="apply blank-line edits")
    parser.add_argument("--folder", action="append",
                        help="relative Include folder, e.g. Mstng/Database/Entity; repeatable")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[3]
    checked = changed = changes = errors = 0
    try:
        paths = list(targetFiles(root, args.folder))
    except (OSError, ValueError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 2
    for path in paths:
        checked += 1
        relative = path.relative_to(root).as_posix()
        try:
            original = path.read_bytes()
            text, encoding, bom = decodeSource(original)
            if bom + text.encode(encoding) != original:
                raise ValueError("encoding round-trip check failed")
            formatted, edits, issues = FieldFormatter(text).format()
            for line, reason in issues:
                print(f"{relative}:{line + 1}: ERROR: {reason}")
            if issues:
                errors += 1
                continue
            if not edits:
                continue
            changed += 1
            changes += len(edits)
            for edit in sorted(edits, key=lambda item: item.startLine):
                print(f"{relative}:{edit.startLine + 1}: {edit.reason}")
            if args.fix:
                if path.read_bytes() != original:
                    raise ValueError("file changed during processing; not overwritten")
                path.write_bytes(bom + formatted.encode(encoding))
        except (OSError, UnicodeError, ValueError) as error:
            errors += 1
            print(f"{relative}: ERROR: {error}", file=sys.stderr)
    verb = "fixed" if args.fix else "would change"
    print(f"Checked {checked} files; {verb} {changed} files, {changes} spacing locations; errors {errors}.")
    if errors:
        return 2
    if args.check and changed:
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
