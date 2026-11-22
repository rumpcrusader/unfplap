"""The shared failure sink and the repo-relative path helper."""
from __future__ import annotations

from pathlib import Path

from .context import ROOT


class Failure:
    def __init__(self) -> None:
        self.messages: list[str] = []

    def add(self, text: str) -> None:
        self.messages.append(text)

    def extend(self, texts: list[str]) -> None:
        self.messages.extend(texts)


def rel(path: Path) -> str:
    return path.relative_to(ROOT).as_posix()
