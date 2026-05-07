# themes/layout.nix — layout constants shared across all UI surfaces
# Import as `l` in default.nix; pass as `l` arg to config.kdl.nix and style.nix.
{
  gap          = 6;    # niri window gap
  borderW      = 2;    # niri window border width
  radiusSm     = 6;    # small: workspace pills, scrollbars, fuzzel
  radiusMd     = 8;    # medium: bar modules, entry fields, tooltips
  radiusLg     = 12;   # large: pill groups, wleave buttons
  shadowBlur   = 10;   # drop shadow blur (tuned to radiusMd)
  shadowSpread = -1;   # negative spread pulls shadow inside rounded corners
}
