# EVM toolchain overlay
# Provides: foundry (forge, cast, anvil, chisel)
#
# Usage: import in flake.nix as overlay

final: prev: {
  # Foundry - Ethereum development toolkit
  # Binary distribution from GitHub releases
  foundry-bin = prev.stdenv.mkDerivation rec {
    pname = "foundry";
    version = "1.5.1";

    src = prev.fetchurl {
      url = if prev.stdenv.isLinux then
        (if prev.stdenv.isAarch64 then
          "https://github.com/foundry-rs/foundry/releases/download/v${version}/foundry_v${version}_linux_arm64.tar.gz"
        else
          "https://github.com/foundry-rs/foundry/releases/download/v${version}/foundry_v${version}_linux_amd64.tar.gz")
      else if prev.stdenv.isDarwin then
        (if prev.stdenv.isAarch64 then
          "https://github.com/foundry-rs/foundry/releases/download/v${version}/foundry_v${version}_darwin_arm64.tar.gz"
        else
          "https://github.com/foundry-rs/foundry/releases/download/v${version}/foundry_v${version}_darwin_amd64.tar.gz")
      else
        throw "Unsupported platform";

      sha256 = if prev.stdenv.isLinux && !prev.stdenv.isAarch64 then
        "127yvk2fyr25ymn0iqn3pvdz130z6ycm023597drzllypl0hnr3k"
      else
        prev.lib.fakeSha256;  # TODO: Get hashes for other platforms
    };

    sourceRoot = ".";

    nativeBuildInputs = prev.lib.optionals prev.stdenv.isLinux [ prev.autoPatchelfHook ];

    buildInputs = prev.lib.optionals prev.stdenv.isLinux [
      prev.stdenv.cc.cc.lib
    ];

    installPhase = ''
      mkdir -p $out/bin
      cp forge cast anvil chisel $out/bin/
      chmod +x $out/bin/*
    '';

    meta = with prev.lib; {
      description = "Foundry - Ethereum development toolkit (forge, cast, anvil, chisel)";
      homepage = "https://github.com/foundry-rs/foundry";
      license = licenses.mit;
      platforms = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
    };
  };
}
