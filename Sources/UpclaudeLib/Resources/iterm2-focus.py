#!/usr/bin/env python3
"""Focus an iTerm2 pane by its session UUID using AppleScript.

Usage: python3 iterm2-focus.py <iterm2_session_uuid> [--zellij-session <name>]

Uses osascript for instant (<100ms) one-shot execution rather than
the iTerm2 Python API which requires a persistent connection.

With --zellij-session, the pane is found through the terminal of the zellij client
currently attached to that session. The UUID recorded when the Claude session started
goes stale as soon as that iTerm2 tab is closed and zellij is re-attached elsewhere.
"""

from __future__ import annotations

import subprocess
import sys
import time
from pathlib import Path

LOG_FILE = Path.home() / ".upclaude" / "focus.log"

APPLESCRIPT_TEMPLATE = """
tell application "iTerm2"
    set targetValue to "{value}"
    repeat with w in windows
        tell w
            repeat with t in tabs
                tell t
                    repeat with s in sessions
                        tell s
                            if {prop} is targetValue then
                                select
                                tell t to select
                                set index of w to 1
                                activate
                                return "focused"
                            end if
                        end tell
                    end repeat
                end tell
            end repeat
        end tell
    end repeat
end tell
"""


def _log(message: str) -> None:
    """Record a failed focus attempt; the app discards this script's output."""
    try:
        with LOG_FILE.open("a") as f:
            f.write(f"{time.strftime('%Y-%m-%dT%H:%M:%S')} {message}\n")
    except OSError:
        pass


def _run(args: list[str]) -> str:
    try:
        return subprocess.run(args, capture_output=True, text=True, timeout=3).stdout
    except (subprocess.TimeoutExpired, OSError):
        return ""


def parse_zellij_processes(
    ps_output: str, session: str
) -> tuple[int | None, list[tuple[int, str]]]:
    """Split `ps -axo pid=,tty=,command=` output into the session's server pid and all clients.

    Clients are (pid, tty) for every zellij process attached to a terminal.
    """
    server_pid: int | None = None
    clients: list[tuple[int, str]] = []
    for line in ps_output.splitlines():
        parts = line.split(None, 2)
        if len(parts) < 3 or not parts[0].isdigit():
            continue
        pid, tty, command = int(parts[0]), parts[1], parts[2]
        argv = command.split()
        if not argv or argv[0].rsplit("/", 1)[-1] != "zellij":
            continue
        if "--server" in argv:
            if command.rstrip().endswith("/" + session):
                server_pid = pid
        elif tty not in ("??", "-"):
            clients.append((pid, tty))
    return server_pid, clients


def parse_unix_sockets(lsof_output: str) -> tuple[set[str], set[str]]:
    """Return (own socket addresses, peer addresses) from `lsof -a -U -p <pid>` output."""
    own: set[str] = set()
    peers: set[str] = set()
    for line in lsof_output.splitlines()[1:]:
        fields = line.split()
        if len(fields) < 6:
            continue
        own.add(fields[5])
        if fields[-1].startswith("->"):
            peers.add(fields[-1][2:])
    return own, peers


def zellij_client_tty(session: str) -> str | None:
    """Return the device path of the terminal attached to the given zellij session."""
    server_pid, clients = parse_zellij_processes(
        _run(["ps", "-axo", "pid=,tty=,command="]), session
    )
    if not clients:
        return None
    if len(clients) > 1 and server_pid is not None:
        # Several zellij clients: keep the one whose socket is connected to our server.
        server_sockets, _ = parse_unix_sockets(
            _run(["lsof", "-a", "-U", "-p", str(server_pid)])
        )
        for pid, tty in clients:
            _, peers = parse_unix_sockets(_run(["lsof", "-a", "-U", "-p", str(pid)]))
            if peers & server_sockets:
                return f"/dev/{tty}"
    return f"/dev/{clients[0][1]}"


def main() -> int:
    args = sys.argv[1:]
    zellij_session: str | None = None
    if "--zellij-session" in args:
        index = args.index("--zellij-session")
        if index + 1 >= len(args):
            print("--zellij-session needs a session name", file=sys.stderr)
            return 1
        zellij_session = args[index + 1]
        del args[index : index + 2]

    if len(args) != 1:
        print(
            f"Usage: {sys.argv[0]} <iterm2_session_uuid> [--zellij-session <name>]",
            file=sys.stderr,
        )
        return 1

    tty = zellij_client_tty(zellij_session) if zellij_session else None
    if tty:
        script = APPLESCRIPT_TEMPLATE.format(prop="tty", value=tty)
    else:
        script = APPLESCRIPT_TEMPLATE.format(prop="unique id", value=args[0])

    target = f"tty {tty}" if tty else f"id {args[0]}"
    try:
        result = subprocess.run(
            ["osascript", "-e", script],
            capture_output=True,
            text=True,
            timeout=5,
        )
    except subprocess.TimeoutExpired:
        _log(f"{target}: timed out waiting for AppleScript")
        return 1
    except OSError as exc:
        _log(f"{target}: failed to run osascript: {exc}")
        return 1

    if result.returncode != 0:
        _log(f"{target}: osascript failed: {result.stderr.strip()}")
        return 1
    if not result.stdout.strip():
        _log(f"{target}: no matching iTerm2 pane")
    return 0


if __name__ == "__main__":
    sys.exit(main())
