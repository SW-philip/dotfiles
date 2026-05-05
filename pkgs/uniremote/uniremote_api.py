# pkgs/uniremote/uniremote_api.py
from __future__ import annotations
import tomllib
from pathlib import Path
import socket
import requests
import xml.etree.ElementTree as ET

DEFAULT_CONFIG_PATH = Path.home() / ".config" / "uniremote" / "config.toml"

# NOTE: values are written unescaped — safe for tokens/IDs/IPs (no quotes or backslashes),
# but would produce invalid TOML if a value contained " or \.
def _write_toml(data: dict) -> str:
    lines = []
    for section, values in data.items():
        lines.append(f"[{section}]")
        for key, val in values.items():
            lines.append(f'{key} = "{val}"')
        lines.append("")
    return "\n".join(lines)

class Config:
    def __init__(self, path: Path = DEFAULT_CONFIG_PATH):
        self.path = Path(path)
        self.samsung_token = ""
        self.samsung_device_id = ""
        self.roku_ip = ""
        self._load()

    def _load(self):
        if not self.path.exists():
            return
        with open(self.path, "rb") as f:
            data = tomllib.load(f)
        samsung = data.get("samsung", {})
        roku = data.get("roku", {})
        self.samsung_token = samsung.get("token", "")
        self.samsung_device_id = samsung.get("device_id", "")
        self.roku_ip = roku.get("ip", "")

    def save(self):
        self.path.parent.mkdir(parents=True, exist_ok=True)
        data = {
            "samsung": {"token": self.samsung_token, "device_id": self.samsung_device_id},
            "roku": {"ip": self.roku_ip},
        }
        self.path.write_text(_write_toml(data))


ST_BASE = "https://api.smartthings.com/v1"

class SmartThingsAPI:
    def __init__(self, token: str, device_id: str):
        self.token = token
        self.device_id = device_id
        self._headers = {"Authorization": f"Bearer {token}"}

    def _command(self, capability: str, command: str, arguments: list | None = None):
        cmd = {"component": "main", "capability": capability, "command": command}
        if arguments:
            cmd["arguments"] = arguments
        resp = requests.post(
            f"{ST_BASE}/devices/{self.device_id}/commands",
            headers=self._headers,
            json={"commands": [cmd]},
            timeout=5,
        )
        resp.raise_for_status()

    def send_key(self, key: str):
        self._command("samsungvd.remoteControl", "sendKey", [key])

    def power(self, state: str):  # state: "on" or "off"
        self._command("switch", state)

    def volume_up(self):
        self._command("audioVolume", "volumeUp")

    def volume_down(self):
        self._command("audioVolume", "volumeDown")

    def channel_up(self):
        self._command("tvChannel", "channelUp")

    def channel_down(self):
        self._command("tvChannel", "channelDown")

    @staticmethod
    def fetch_devices(token: str) -> list[tuple[str, str]]:
        resp = requests.get(
            f"{ST_BASE}/devices",
            headers={"Authorization": f"Bearer {token}"},
            timeout=5,
        )
        resp.raise_for_status()
        items = resp.json().get("items", [])
        return [(d["deviceId"], d.get("label", d["deviceId"])) for d in items]


class RokuAPI:
    def __init__(self, ip: str):
        self.base = f"http://{ip}:8060"

    def keypress(self, key: str):
        requests.post(f"{self.base}/keypress/{key}", timeout=3).raise_for_status()

    def list_apps(self) -> list[tuple[str, str]]:
        resp = requests.get(f"{self.base}/query/apps", timeout=5)
        resp.raise_for_status()
        root = ET.fromstring(resp.text)
        return [(app.get("id", ""), app.text or "") for app in root.findall("app")]

    def launch_app(self, app_id: str):
        requests.post(f"{self.base}/launch/{app_id}", timeout=3).raise_for_status()

    def search(self, query: str):
        requests.post(
            f"{self.base}/search/browse",
            params={"keyword": query, "launch": "true"},
            timeout=3,
        ).raise_for_status()


SSDP_ADDR = "239.255.255.250"
SSDP_PORT = 1900
SSDP_MX = 2
SSDP_ST = "roku:ecp"
SSDP_MSG = (
    "M-SEARCH * HTTP/1.1\r\n"
    f"HOST: {SSDP_ADDR}:{SSDP_PORT}\r\n"
    "MAN: \"ssdp:discover\"\r\n"
    f"MX: {SSDP_MX}\r\n"
    f"ST: {SSDP_ST}\r\n"
    "\r\n"
).encode()

def discover_roku(timeout: int = 3) -> str | None:
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM, socket.IPPROTO_UDP)
    try:
        sock.settimeout(timeout)
        sock.sendto(SSDP_MSG, (SSDP_ADDR, SSDP_PORT))
        while True:
            try:
                data, _ = sock.recvfrom(1024)
                response = data.decode(errors="ignore")
                if "roku:ecp" in response.lower():
                    for line in response.splitlines():
                        if line.lower().startswith("location:"):
                            url = line.split(":", 1)[1].strip()
                            # url like http://192.168.1.77:8060/
                            ip = url.split("//")[1].split(":")[0]
                            return ip
            except (TimeoutError, OSError):
                return None
    finally:
        sock.close()
