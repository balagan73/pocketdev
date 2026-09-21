"""Shared command definitions for the host/container remote-trigger mechanism.

See restart-helper.py (host side, listens on the Unix socket) and
restart-trigger.py (container side, sends a command name over it).
"""

COMMANDS = {
    "restart": ["docker", "compose", "restart", "openclaw"],
    "rebuild": ["bash", "rebuild.sh"],
}


def resolve_command(name):
    """Return the host-side argv for a command name, or None if unrecognized."""
    return COMMANDS.get(name)


def parse_trigger_args(argv):
    """argv: sys.argv[1:] from restart-trigger.py. Returns the command name to
    send, defaulting to "restart" when no argument is given.

    Raises ValueError for an unrecognized command.
    """
    command = argv[0] if argv else "restart"
    if command not in COMMANDS:
        raise ValueError(
            f"unknown command: {command!r} (expected one of {sorted(COMMANDS)})"
        )
    return command
