import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))
from uniremote_api import RokuAPI

IP = "192.168.1.100"

def _api():
    return RokuAPI(IP)

def test_keypress(requests_mock):
    requests_mock.post(f"http://{IP}:8060/keypress/Up", text="")
    _api().keypress("Up")
    assert requests_mock.called

def test_list_apps(requests_mock):
    xml = """<?xml version="1.0" encoding="UTF-8" ?>
    <apps>
      <app id="12" version="4.1">Netflix</app>
      <app id="2285" version="3.0">Hulu</app>
    </apps>"""
    requests_mock.get(f"http://{IP}:8060/query/apps", text=xml)
    apps = _api().list_apps()
    assert apps == [("12", "Netflix"), ("2285", "Hulu")]

def test_launch_app(requests_mock):
    requests_mock.post(f"http://{IP}:8060/launch/12", text="")
    _api().launch_app("12")
    assert requests_mock.called

def test_search(requests_mock):
    requests_mock.post(f"http://{IP}:8060/search/browse", text="")
    _api().search("stranger things")
    assert requests_mock.last_request.qs == {
        "keyword": ["stranger things"], "launch": ["true"]
    }
