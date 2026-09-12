#!/usr/bin/env python3
"""
Container-side trigger: sends a restart signal to the host helper via Unix socket.

Run from inside the container. The socket must be mounted at /run/restart-helper.sock.
See restart-helper.py for the host-side setup.
"""
import os
import socket
import sys

SOCKET_PATH = os.environ.get("RESTART_SOCKET", "/run/restart-helper.sock")

try:
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
        s.connect(SOCKET_PATH)
        s.sendall(b"restart")
        response = s.recv(64).decode().strip()
        print(response)
        sys.exit(0 if response == "ok" else 1)
except FileNotFoundError:
    print(f"Socket not found: {SOCKET_PATH} — is restart-helper.py running on the host?", file=sys.stderr)
    sys.exit(1)
