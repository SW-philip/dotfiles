# pkgs/uniremote/tests/test_smartthings.py
import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))
from uniremote_api import SmartThingsAPI

TOKEN = "mytoken"
DEVICE_ID = "device-abc"

def _api():
    return SmartThingsAPI(TOKEN, DEVICE_ID)

def test_send_key(requests_mock):
    url = f"https://api.smartthings.com/v1/devices/{DEVICE_ID}/commands"
    requests_mock.post(url, json={"results": [{"status": "ACCEPTED"}]})
    api = _api()
    api.send_key("KEY_UP")
    assert requests_mock.last_request.json() == {
        "commands": [{
            "component": "main",
            "capability": "samsungvd.remoteControl",
            "command": "sendKey",
            "arguments": ["KEY_UP"],
        }]
    }

def test_power_on(requests_mock):
    url = f"https://api.smartthings.com/v1/devices/{DEVICE_ID}/commands"
    requests_mock.post(url, json={})
    _api().power("on")
    body = requests_mock.last_request.json()
    assert body["commands"][0]["capability"] == "switch"
    assert body["commands"][0]["command"] == "on"

def test_volume_up(requests_mock):
    url = f"https://api.smartthings.com/v1/devices/{DEVICE_ID}/commands"
    requests_mock.post(url, json={})
    _api().volume_up()
    body = requests_mock.last_request.json()
    assert body["commands"][0]["capability"] == "audioVolume"
    assert body["commands"][0]["command"] == "volumeUp"

def test_channel_up(requests_mock):
    url = f"https://api.smartthings.com/v1/devices/{DEVICE_ID}/commands"
    requests_mock.post(url, json={})
    _api().channel_up()
    body = requests_mock.last_request.json()
    assert body["commands"][0]["capability"] == "tvChannel"
    assert body["commands"][0]["command"] == "channelUp"

def test_fetch_devices(requests_mock):
    requests_mock.get(
        "https://api.smartthings.com/v1/devices",
        json={"items": [
            {"deviceId": "d1", "label": "Living Room TV", "deviceTypeName": "Samsung TV"},
            {"deviceId": "d2", "label": "Phone", "deviceTypeName": "Mobile"},
        ]}
    )
    devs = SmartThingsAPI.fetch_devices(TOKEN)
    assert len(devs) == 2
    assert devs[0] == ("d1", "Living Room TV")
