{ lib, ... }:

{
  hardware.graphics = {
    enable = true;
    enable32Bit = true;
  };

  boot.kernelParams = lib.mkAfter [
    "i915.enable_psr=1"
    "i915.enable_fbc=1"
    "i915.enable_dc=2"
  ];

  environment.sessionVariables = {
    VK_ICD_FILENAMES = "/run/opengl-driver/share/vulkan/icd.d/intel_icd.x86_64.json";
    WLR_RENDERER_ALLOW_SOFTWARE = "0";
  };
}
