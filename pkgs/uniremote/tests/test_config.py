# pkgs/uniremote/tests/test_config.py
import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))
from uniremote_api import Config

def test_default_config_created(tmp_path):
    cfg = Config(path=tmp_path / "config.toml")
    assert cfg.samsung_token == ""
    assert cfg.samsung_device_id == ""
    assert cfg.roku_ip == ""

def test_save_and_reload(tmp_path):
    path = tmp_path / "config.toml"
    cfg = Config(path=path)
    cfg.samsung_token = "tok123"
    cfg.samsung_device_id = "dev456"
    cfg.roku_ip = "192.168.1.50"
    cfg.save()

    cfg2 = Config(path=path)
    assert cfg2.samsung_token == "tok123"
    assert cfg2.samsung_device_id == "dev456"
    assert cfg2.roku_ip == "192.168.1.50"

def test_config_file_written(tmp_path):
    path = tmp_path / "config.toml"
    cfg = Config(path=path)
    cfg.samsung_token = "t"
    cfg.save()
    content = path.read_text()
    assert "[samsung]" in content
    assert "[roku]" in content
