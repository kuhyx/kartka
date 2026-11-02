# Copyright (c) 2026 Krzysztof Rudnicki
"""Collects Kartka's error reports (RTDB ``/kartka/errors``) into a fixme report.

The app pushes every failure the user saw, redacted, to
``/kartka/errors/<device>/<id>`` (``lib/sync/error_upload.dart``). This
package reads them, groups them by signature in a local state file, deletes
what it read, and rewrites ``~/.local/state/kartka-errors/fixme.md`` as a
ready-to-paste prompt.
"""
