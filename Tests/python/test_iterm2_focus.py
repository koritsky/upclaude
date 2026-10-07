"""Tests for iterm2-focus.py."""

import importlib.util
from pathlib import Path

import pytest

FOCUS_PATH = (
    Path(__file__).parent.parent.parent
    / "Sources"
    / "UpclaudeLib"
    / "Resources"
    / "iterm2-focus.py"
)

PS_OUTPUT = """\
 4082 ??       /nix/bin/zellij --server /var/folders/T/zellij-502/contract_version_1/main
 4090 ??       /nix/bin/zellij --server /var/folders/T/zellij-502/contract_version_1/other
27688 ttys008  zellij a main
27700 ttys003  zellij
 5986 ttys001  claude -c
28032 ??       /bin/zsh -c zellij action list-panes
"""


@pytest.fixture()
def focus():
    spec = importlib.util.spec_from_file_location("iterm2_focus", FOCUS_PATH)
    assert spec and spec.loader
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def test_parse_zellij_processes_finds_server_and_clients(focus):
    server_pid, clients = focus.parse_zellij_processes(PS_OUTPUT, "main")
    assert server_pid == 4082
    assert clients == [(27688, "ttys008"), (27700, "ttys003")]


def test_parse_unix_sockets(focus):
    lsof = """\
COMMAND   PID     USER   FD   TYPE             DEVICE SIZE/OFF NODE NAME
zellij  27688 nikitaak    5u  unix 0xaaa      0t0      ->0xbbb
zellij  27688 nikitaak    7u  unix 0xccc      0t0      /tmp/sock
"""
    own, peers = focus.parse_unix_sockets(lsof)
    assert own == {"0xaaa", "0xccc"}
    assert peers == {"0xbbb"}


def test_single_client_is_used(focus, monkeypatch):
    ps = " 4082 ??  zellij --server /x/main\n27688 ttys008  zellij a main\n"
    monkeypatch.setattr(focus, "_run", lambda args: ps if args[0] == "ps" else "")
    assert focus.zellij_client_tty("main") == "/dev/ttys008"


def test_client_connected_to_session_server_wins(focus, monkeypatch):
    header = "COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME\n"
    lsof = {
        "4082": header + "zellij 4082 u 5u unix 0xserver 0t0 ->0xclient2\n",
        "27688": header + "zellij 27688 u 5u unix 0xclient1 0t0 ->0xelsewhere\n",
        "27700": header + "zellij 27700 u 5u unix 0xclient2 0t0 ->0xserver\n",
    }

    def fake_run(args):
        return PS_OUTPUT if args[0] == "ps" else lsof[args[-1]]

    monkeypatch.setattr(focus, "_run", fake_run)
    assert focus.zellij_client_tty("main") == "/dev/ttys003"


def test_no_client_returns_none(focus, monkeypatch):
    monkeypatch.setattr(
        focus, "_run", lambda args: " 4082 ??  zellij --server /x/main\n"
    )
    assert focus.zellij_client_tty("main") is None


LIST_CLIENTS = (
    "CLIENT_ID ZELLIJ_PANE_ID RUNNING_COMMAND\n1         terminal_10    claude -c\n"
)


def _fake_run(current_pane, ps="", clients=LIST_CLIENTS):
    def run(args):
        if args[0] == "osascript":
            return current_pane
        if args[0] == "ps":
            return ps
        if "list-clients" in args:
            return clients
        return ""

    return run


def test_parse_focused_panes(focus):
    assert focus.parse_focused_panes(LIST_CLIENTS) == {"terminal_10"}
    assert focus.parse_focused_panes("") == set()


def test_not_focused_when_iterm2_is_in_background(focus, monkeypatch):
    monkeypatch.setattr(focus, "_run", _fake_run(""))
    assert focus.is_focused("UUID-1", {}) is False


def test_plain_pane_matches_by_id(focus, monkeypatch):
    monkeypatch.setattr(focus, "_run", _fake_run("/dev/ttys001|UUID-1\n"))
    assert focus.is_focused("UUID-1", {}) is True
    assert focus.is_focused("UUID-2", {}) is False


def test_zellij_needs_client_terminal_and_focused_pane(focus, monkeypatch):
    ps = " 4082 ??  zellij --server /x/main\n27688 ttys008  zellij a main\n"
    zellij = {
        "--zellij-session": "main",
        "--zellij-pane": "terminal_10",
        "--zellij-bin": "/bin/zellij",
    }

    monkeypatch.setattr(focus, "_run", _fake_run("/dev/ttys008|ANY\n", ps))
    assert focus.is_focused("STALE", zellij) is True

    # Looking at zellij, but at a different pane.
    assert focus.is_focused("STALE", {**zellij, "--zellij-pane": "terminal_3"}) is False

    # Looking at another iTerm2 pane entirely.
    monkeypatch.setattr(focus, "_run", _fake_run("/dev/ttys001|ANY\n", ps))
    assert focus.is_focused("STALE", zellij) is False


SSH_PS = """\
70566 ttys005  ssh berghain
70600 ttys007  ssh -p 2222 me@berghain
70700 ??       /usr/bin/ssh -o BatchMode=yes berghain python3 -u -c watch
70800 ttys009  ssh otherhost
70900 ttys010  vim berghain
"""


def test_ssh_client_tty_picks_newest_interactive_client(focus, monkeypatch):
    monkeypatch.setattr(focus, "_run", lambda args: SSH_PS)
    assert focus.ssh_client_tty("berghain") == "/dev/ttys007"
    assert focus.ssh_client_tty("otherhost") == "/dev/ttys009"
    assert focus.ssh_client_tty("nowhere") is None


def test_remote_session_is_focused_through_the_ssh_pane(focus, monkeypatch):
    calls = []

    def run(args):
        calls.append(args)
        if args[0] == "osascript":
            return "/dev/ttys007|ANY\n"
        if args[0] == "ps":
            return SSH_PS
        if args[0] == "ssh":
            return LIST_CLIENTS
        return ""

    monkeypatch.setattr(focus, "_run", run)
    options = {
        "--ssh-host": "berghain",
        "--zellij-session": "main",
        "--zellij-pane": "terminal_10",
        "--zellij-bin": "/bin/zellij",
    }
    assert focus.is_focused("-", options) is True
    # zellij is asked on the remote host, not locally.
    remote = [c for c in calls if c[0] == "ssh"][0]
    assert remote[-2:] == ["berghain", "/bin/zellij --session main action list-clients"]

    assert focus.is_focused("-", {**options, "--zellij-pane": "terminal_3"}) is False
    assert focus.is_focused("-", {"--ssh-host": "otherhost"}) is False


def test_focus_fails_without_a_local_ssh_client(focus, monkeypatch, tmp_path):
    monkeypatch.setattr(focus, "LOG_FILE", tmp_path / "focus.log")
    monkeypatch.setattr(focus, "_run", lambda args: "")
    assert focus.focus("-", None, "berghain") == 1
    assert "no local ssh client" in (tmp_path / "focus.log").read_text()
