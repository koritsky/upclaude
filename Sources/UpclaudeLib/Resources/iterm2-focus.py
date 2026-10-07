#!/usr/bin/env python3
"""Focus an iTerm2 pane by its session UUID using AppleScript.

Usage: python3 iterm2-focus.py <iterm2_session_uuid> [--zellij-session <name>]
       python3 iterm2-focus.py <iterm2_session_uuid> --check
           [--zellij-session <name> --zellij-pane <pane_id> --zellij-bin <path>]

With --check nothing is focused: the exit status says whether the user is already looking
at the pane (0) or not (1).

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


CURRENT_PANE_SCRIPT = """
tell application "iTerm2"
    if not frontmost then return ""
    tell current session of current window to return tty & "|" & unique id
end tell
"""


def parse_focused_panes(list_clients_output: str) -> set[str]:
    """Return the pane ids focused by attached clients, from `zellij action list-clients`."""
    panes: set[str] = set()
    for line in list_clients_output.splitlines()[1:]:
        fields = line.split()
        if len(fields) >= 2:
            panes.add(fields[1])
    return panes


def is_focused(uuid: str, zellij: dict[str, str]) -> bool:
    """Whether iTerm2 is frontmost and showing the given pane (and zellij pane, if any)."""
    current = _run(["osascript", "-e", CURRENT_PANE_SCRIPT]).strip()
    if "|" not in current:
        return False
    current_tty, current_id = current.split("|", 1)

    session = zellij.get("--zellij-session")
    if not session:
        return current_id == uuid
    if zellij_client_tty(session) != current_tty:
        return False
    pane, binary = zellij.get("--zellij-pane"), zellij.get("--zellij-bin")
    if not (pane and binary):
        return True
    clients = _run([binary, "--session", session, "action", "list-clients"])
    return pane in parse_focused_panes(clients)


def focus(uuid: str, zellij_session: str | None) -> int:
    tty = zellij_client_tty(zellij_session) if zellij_session else None
    if tty:
        script = APPLESCRIPT_TEMPLATE.format(prop="tty", value=tty)
    else:
        script = APPLESCRIPT_TEMPLATE.format(prop="unique id", value=uuid)

    target = f"tty {tty}" if tty else f"id {uuid}"
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


def main() -> int:
    args = sys.argv[1:]
    check = "--check" in args
    if check:
        args.remove("--check")

    zellij: dict[str, str] = {}
    for option in ("--zellij-session", "--zellij-pane", "--zellij-bin"):
        if option not in args:
            continue
        index = args.index(option)
        if index + 1 >= len(args):
            print(f"{option} needs a value", file=sys.stderr)
            return 1
        zellij[option] = args[index + 1]
        del args[index : index + 2]

    if len(args) != 1:
        print(
            f"Usage: {sys.argv[0]} <iterm2_session_uuid> [--zellij-session <name>] [--check]",
            file=sys.stderr,
        )
        return 1

    if check:
        return 0 if is_focused(args[0], zellij) else 1
    return focus(args[0], zellij.get("--zellij-session"))


if __name__ == "__main__":
    sys.exit(main())
