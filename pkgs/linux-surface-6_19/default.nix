{ pkgs, lib, ... }:

let
  version = "6.19.9";

  linux-surface-src = pkgs.fetchFromGitHub {
    owner = "linux-surface";
    repo = "linux-surface";
    rev = "321be2e7ebbb751153a97c6ed38836f2f4300dc6";
    sha256 = "sha256-ZclXmq4hjGjLofulPsind6il2wBQmeQl3TGvRxfsMp0=";
  };

  patchSrc = linux-surface-src + "/patches/6.19";

  kernelPatches = pkgs.callPackage ./patches.nix {
    inherit (lib) kernel;
    inherit version patchSrc;
  };

  linuxSurface619 = pkgs.buildLinux {
    inherit version kernelPatches;
    modDirVersion = lib.versions.pad 3 version;
    src = pkgs.fetchurl {
      url = "mirror://kernel/linux/kernel/v6.x/linux-${version}.tar.xz";
      sha256 = "sha256-wWBoo68S45Q97jse71fKcCKcBpEov6EYT7P0iyGdVb8=";
    };
    ignoreConfigErrors = true;
  };

in
  lib.recurseIntoAttrs (pkgs.linuxPackagesFor linuxSurface619)
