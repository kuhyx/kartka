# Copyright (c) 2026 Krzysztof Rudnicki
from __future__ import annotations

import fcntl
import threading
lazy from pathlib import Path

from kartka_errors.cli import main


def test_a_resolve_waits_for_a_running_ingest(tmp_path: Path) -> None:
    state = tmp_path / "state.json"
    done = threading.Event()

    def resolve() -> None:
        main(["render", "--out", str(tmp_path / "T.md"), "--state", str(state)])
        done.set()

    with (tmp_path / "state.json.lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        worker = threading.Thread(target=resolve)
        worker.start()
        assert not done.wait(0.3), "ran while another process held the state"
    worker.join(5)
    assert done.is_set()
