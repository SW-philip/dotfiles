{ lib, ... }: {
  # Extends the base fastfetch config with desktop-specific disk entries.
  programs.fastfetch.settings.modules = lib.mkAfter [
    {
      type         = "disk";
      key          = "󱘲  srv";
      folders      = "/srv";
      percent.type = 3;
    }
  ];
}
