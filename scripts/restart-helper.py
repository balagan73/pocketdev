#!/usr/bin/env python3
"""
Host-side helper: listens on a Unix socket and restarts the openclaw container.

Run this on the HOST machine (not inside the container).
Mount the socket into the container via docker-compose.yml, e.g.:

  volumes:
    - /tmp/openclaw-restart.sock:/run/restart-helper.sock

Then from inside the container, trigger a restart with:
  python3 /workspace/scripts/restart-trigger.py
"""
import os
import socket
import subprocess

SOCKET_PATH = os.environ.get("RESTART_SOCKET", "/tmp/openclaw-restart.sock")
COMPOSE_DIR = os.path.dirname(os.path.dirname(os.path.realpath(__file__)))


def main():
    if os.path.exists(SOCKET_PATH):
        os.unlink(SOCKET_PATH)

    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as srv:
        srv.bind(SOCKET_PATH)
        os.chmod(SOCKET_PATH, 0o600)
        srv.listen(1)
        print(f"Listening on {SOCKET_PATH} (compose dir: {COMPOSE_DIR})", flush=True)

        while True:
            conn, _ = srv.accept()
            with conn:
                data = conn.recv(64).strip()
                if data == b"restart":
                    print("Restart signal received — running docker compose restart openclaw ...", flush=True)
                    result = subprocess.run(
                        ["docker", "compose", "restart", "openclaw"],
                        cwd=COMPOSE_DIR,
                        capture_output=True,
                        text=True,
                    )
                    if result.returncode == 0:
                        conn.sendall(b"ok\n")
                        print("Restart successful.", flush=True)
                    else:
                        conn.sendall(b"error\n")
                        print(f"Restart failed: {result.stderr}", flush=True)
                else:
                    conn.sendall(b"unknown command\n")


if __name__ == "__main__":
    main()
