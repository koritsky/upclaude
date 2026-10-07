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
