# pkgs/uniremote/tests/test_ssdp.py
import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))
from unittest.mock import patch, MagicMock
from uniremote_api import discover_roku

SSDP_RESPONSE = (
    b"HTTP/1.1 200 OK\r\n"
    b"ST: roku:ecp\r\n"
    b"Location: http://192.168.1.77:8060/\r\n"
    b"\r\n"
)

def test_discover_finds_roku():
    mock_sock = MagicMock()
    mock_sock.recvfrom.side_effect = [
        (SSDP_RESPONSE, ("192.168.1.77", 1900)),
        TimeoutError(),
    ]
    with patch("socket.socket", return_value=mock_sock):
        result = discover_roku(timeout=1)
    assert result == "192.168.1.77"

def test_discover_returns_none_on_timeout():
    mock_sock = MagicMock()
    mock_sock.recvfrom.side_effect = TimeoutError()
    with patch("socket.socket", return_value=mock_sock):
        result = discover_roku(timeout=1)
    assert result is None
