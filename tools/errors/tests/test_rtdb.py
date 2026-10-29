# Copyright (c) 2026 Krzysztof Rudnicki
from __future__ import annotations

from email.message import Message
import io
import json
from typing import Self
import urllib.error
import urllib.request

import crdt_sync
import pytest

from kartka_errors import rtdb
from kartka_errors.rtdb import NoSessionError, RestRtdb, RtdbError


class FakeResponse(io.BytesIO):
    def __enter__(self) -> Self:
        return self

    def __exit__(self, *_: object) -> None:
        self.close()


def make(
    answer: object = None, fail: Exception | None = None
) -> tuple[RestRtdb, list[urllib.request.Request]]:
    seen: list[urllib.request.Request] = []

    def opener(req: urllib.request.Request, timeout: float) -> FakeResponse:
        seen.append(req)
        assert timeout == rtdb.TIMEOUT
        if fail is not None:
            raise fail
        return FakeResponse(json.dumps(answer).encode())

    return RestRtdb("https://db.test/", lambda: "TOKEN", opener), seen


def test_get_decodes_json_with_the_token() -> None:
    client, seen = make({"a": 1})
    assert client.get("kartka/errors") == {"a": 1}
    assert seen[0].full_url == "https://db.test/kartka/errors.json?auth=TOKEN"
    assert seen[0].get_method() == "GET"


def test_patch_sends_json() -> None:
    client, seen = make(None)
    client.patch("kartka/errors", {"d/1": None})
    assert seen[0].get_method() == "PATCH"
    assert seen[0].data == b'{"d/1": null}'


def test_errors_never_carry_the_url_or_token() -> None:
    err = urllib.error.HTTPError(
        "https://db.test/x.json?auth=TOKEN",
        401,
        "no",
        Message(),
        None,
    )
    client, _ = make(fail=err)
    with pytest.raises(RtdbError) as info:
        client.get("kartka/errors")
    assert str(info.value) == "RTDB GET kartka/errors: HTTP 401"
    client, _ = make(fail=urllib.error.URLError("https://db.test/?auth=TOKEN down"))
    with pytest.raises(RtdbError) as info:
        client.patch("kartka/errors", {})
    assert "TOKEN" not in str(info.value)
    assert str(info.value) == "RTDB PATCH kartka/errors: URLError"


def test_open_rtdb_without_a_session_raises_the_seed_hint(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    class Config:
        api_key = "k"
        database_url = "https://db.test"

    class Auth:
        def __init__(self, *_: object, **__: object) -> None: ...

        def has_session(self) -> bool:
            return False

    monkeypatch.setattr(crdt_sync.FirebaseConfig, "load", Config)
    monkeypatch.setattr(crdt_sync, "credential_store_for", str)
    monkeypatch.setattr(crdt_sync, "FirebaseTokenProvider", Auth)
    with pytest.raises(NoSessionError, match="seed_session --app kartka-source-eval"):
        rtdb.open_rtdb()

    Auth.has_session = lambda self: True  # type: ignore[method-assign]
    Auth.id_token = lambda self: "T"  # type: ignore[attr-defined]
    client = rtdb.open_rtdb()
    assert isinstance(client, RestRtdb)


def test_a_failed_token_refresh_is_an_rtdb_error() -> None:
    def no_token() -> str:
        raise ValueError("https://securetoken.test/?key=K")

    client = RestRtdb("https://db.test", no_token, lambda *_a, **_k: None)
    with pytest.raises(RtdbError, match=r"token refresh failed \(ValueError\)"):
        client.get("kartka/errors")
