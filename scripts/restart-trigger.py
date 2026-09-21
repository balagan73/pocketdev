#!/usr/bin/env python3
"""
Container-side trigger: sends a restart or rebuild signal to the host helper
via Unix socket.

Run from inside the container. The socket directory must be mounted at
/run/restart-helper (see restart-helper.py for the host-side setup).

Usage:
  python3 restart-trigger.py            # restart (fast, same image)
  python3 restart-trigger.py rebuild    # rebuild (picks up extension/code
                                         # changes, takes a few minutes)
"""
import os
import socket
import sys

from remote_commands import parse_trigger_args

SOCKET_PATH = os.environ.get("RESTART_SOCKET", "/run/restart-helper/helper.sock")

try:
    command = parse_trigger_args(sys.argv[1:])
except ValueError as e:
    print(e, file=sys.stderr)
    sys.exit(1)

try:
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
        s.connect(SOCKET_PATH)
        s.sendall(command.encode())
        response = s.recv(64).decode().strip()
        print(response)
        sys.exit(0 if response == "ok" else 1)
except FileNotFoundError:
    print(f"Socket not found: {SOCKET_PATH} — is restart-helper.py running on the host?", file=sys.stderr)
    sys.exit(1)
