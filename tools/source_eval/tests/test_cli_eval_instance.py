# Copyright (c) 2026 Krzysztof Rudnicki
"""The evaluator must never point at kuhy's live Suwayomi (it installs ~570
extensions); it talks to its own eval instance on 127.0.0.1:4590."""

from __future__ import annotations

import pytest

from source_eval import cli


def test_default_is_the_eval_instance(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.delenv("KARTKA_SUWAYOMI_URL", raising=False)
    args = cli._parser().parse_args(["probe"])
    assert cli._settings(args).suwayomi.url == "http://127.0.0.1:4590"


@pytest.mark.parametrize(
    "url",
    [
        "http://127.0.0.1:4567",
        "http://localhost:4567/",
        "https://suwayomi.kuhy.duckdns.org",
    ],
)
def test_live_server_is_refused(url: str, capsys: pytest.CaptureFixture[str]) -> None:
    args = cli._parser().parse_args(["--suwayomi-url", url, "probe"])
    with pytest.raises(SystemExit) as exc:
        cli._settings(args)
    assert exc.value.code == 2
    assert "live Suwayomi" in capsys.readouterr().err
