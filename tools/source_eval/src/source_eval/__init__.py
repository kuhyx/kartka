# Copyright (c) 2026 Krzysztof Rudnicki
"""Kartka source evaluator."""

import time

#: When this process started (first import of the package): ``--budget`` is
#: counted from here, so a budget covers startup too.
STARTED = time.time()
