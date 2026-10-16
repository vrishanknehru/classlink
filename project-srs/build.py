#!/usr/bin/env python3
"""Generate the LaTeX SRS body from docs/srs/index.md so the two never drift.

Usage (from the repo root):  python3 project-srs/build.py
Needs pandoc and pdflatex (for the TikZ figures in project-srs/figures). Then compile:   cd project-srs && latexmk -pdf main.tex
"""

from __future__ import annotations

import re
import subprocess
from pathlib import Path

HERE = Path(__file__).resolve().parent
SOURCE = HERE.parent / "docs" / "srs" / "index.md"


def tune_tables(md: str) -> str:
    """Give each pipe table column a width proportional to its content.

    Pandoc sizes wrapped columns by the dashes in the separator row. The Markdown
    source uses equal dashes, which squeezes long requirement text, so rewrite them.
    """
    lines = md.split("\n")
    out: list[str] = []
    i = 0
    while i < len(lines):
        if (
            lines[i].startswith("|")
            and i + 1 < len(lines)
            and re.fullmatch(r"\|(\s*:?-+:?\s*\|)+", lines[i + 1])
        ):
            j = i
            while j < len(lines) and lines[j].startswith("|"):
                j += 1
            block = lines[i:j]
            rows = [[c.strip() for c in r.strip().strip("|").split("|")] for r in block]
            ncols = len(rows[0])
            weights = []
            for c in range(ncols):
                cells = [r[c] for k, r in enumerate(rows) if k != 1 and c < len(r)]
                avg = sum(len(x) for x in cells) / max(len(cells), 1)
                longest = max((len(x) for x in cells), default=1)
                if longest <= 14:  # short columns (IDs, priority, status) must not wrap
                    weights.append(max(int(longest * 2.2), 9))
                else:
                    weights.append(min(max(int((avg + longest) / 2), 6), 70))
            block[1] = "|" + "|".join("-" * w for w in weights) + "|"
            out.extend(block)
            i = j
        else:
            out.append(lines[i])
            i += 1
    return "\n".join(out)


def strip_numbers(md: str) -> str:
    """LaTeX numbers sections itself, so drop the hand written prefixes."""
    md = re.sub(r"^(#{1,2}) \d+(\.\d+)*\.? ", r"\1 ", md, flags=re.M)
    return re.sub(r"^# Appendix [A-Z]\. ", "# ", md, flags=re.M)


def use_pdf_figures(md: str) -> str:
    """Point figure links at the vector PDFs that sit beside this script."""
    return re.sub(r"\]\(figures/(\w+)\.png\)", lambda m: f"](figures/{m.group(1)}.pdf)", md)


def keep_aspect(tex: str) -> str:
    """Pandoc omits keepaspectratio, which would stretch a figure to fit both bounds."""
    return re.sub(r"\\includegraphics\[([^\]]*)\]", r"\\includegraphics[\1,keepaspectratio]", tex)


def pandoc(md: str) -> str:
    result = subprocess.run(
        ["pandoc", "-f", "markdown+pipe_tables+link_attributes-smart", "-t", "latex",
         "--top-level-division=section", "--wrap=preserve", f"--resource-path={HERE}"],
        input=md, capture_output=True, text=True, check=True,
    )  # fmt: skip
    return result.stdout


def build_figures() -> None:
    """Compile each TikZ figure to PDF and refresh the PNG copies used by the docs site."""
    out = HERE.parent / "docs" / "srs" / "figures"
    out.mkdir(parents=True, exist_ok=True)
    for tex in sorted((HERE / "figures").glob("fig_*.tex")):
        subprocess.run(
            ["pdflatex", "-interaction=nonstopmode", "-halt-on-error", tex.name],
            cwd=tex.parent, check=True, capture_output=True,
        )  # fmt: skip
        subprocess.run(
            ["pdftoppm", "-r", "150", "-png", "-singlefile",
             str(tex.with_suffix(".pdf")), str(out / tex.stem)],
            check=True,
        )  # fmt: skip


def main() -> None:
    text = SOURCE.read_text(encoding="utf-8")
    _, _, rest = text.partition("\n# 1. Introduction")
    body_md = "# 1. Introduction" + rest
    build_figures()
    (HERE / "body.tex").write_text(
        keep_aspect(pandoc(use_pdf_figures(strip_numbers(tune_tables(body_md))))),
        encoding="utf-8",
    )
    print("wrote body.tex and the figures")


if __name__ == "__main__":
    main()
