# IC (Internet Computer) toolchain overlay
# Provides: dfx, ic-wasm, didc (candid)
#
# Usage: import in flake.nix as overlay

final: prev: {
  # DFX - DFINITY SDK
  # Binary distribution from DFINITY
  dfx = prev.stdenv.mkDerivation rec {
    pname = "dfx";
    version = "0.24.3";  # Check https://github.com/dfinity/sdk/releases

    src = prev.fetchurl {
      url = if prev.stdenv.isDarwin then
        (if prev.stdenv.isAarch64 then
          "https://github.com/dfinity/sdk/releases/download/${version}/dfx-${version}-aarch64-darwin.tar.gz"
        else
          "https://github.com/dfinity/sdk/releases/download/${version}/dfx-${version}-x86_64-darwin.tar.gz")
      else
        "https://github.com/dfinity/sdk/releases/download/${version}/dfx-${version}-x86_64-linux.tar.gz";

      sha256 = if prev.stdenv.isLinux then
        "0hh846c7l3h68kh3jqpkfby0l3nnr6f081wnmhydaqzpg873247s"
      else
        prev.lib.fakeSha256;  # TODO: Get Darwin hashes
    };

    sourceRoot = ".";

    nativeBuildInputs = with prev; [ autoPatchelfHook ];

    buildInputs = with prev; [
      stdenv.cc.cc.lib
      openssl
      zlib
    ];

    installPhase = ''
      mkdir -p $out/bin
      cp dfx $out/bin/
      chmod +x $out/bin/dfx
    '';

    meta = with prev.lib; {
      description = "DFINITY SDK - Internet Computer development toolkit";
      homepage = "https://github.com/dfinity/sdk";
      license = licenses.asl20;
      platforms = [ "x86_64-linux" "x86_64-darwin" "aarch64-darwin" ];
    };
  };

  # ic-wasm - Using pre-built binary from GitHub releases
  ic-wasm = prev.stdenv.mkDerivation rec {
    pname = "ic-wasm";
    version = "0.9.0";

    src = prev.fetchurl {
      url = "https://github.com/dfinity/ic-wasm/releases/download/${version}/ic-wasm-linux64";
      sha256 = "05sp4mmqwh7wky1y2m3vv2ghzfd4gvbh68gf3vybdaiwgacbs6kh";
    };

    dontUnpack = true;
    nativeBuildInputs = with prev; [ autoPatchelfHook ];
    buildInputs = with prev; [ stdenv.cc.cc.lib ];

    installPhase = ''
      mkdir -p $out/bin
      cp $src $out/bin/ic-wasm
      chmod +x $out/bin/ic-wasm
    '';

    meta = with prev.lib; {
      description = "IC-specific WASM utilities (profiling, optimization)";
      homepage = "https://github.com/dfinity/ic-wasm";
      license = licenses.asl20;
    };
  };

  # didc - Using pre-built binary from GitHub releases
  didc = prev.stdenv.mkDerivation rec {
    pname = "didc";
    version = "2025-12-18";  # Check https://github.com/dfinity/candid/releases

    src = prev.fetchurl {
      url = "https://github.com/dfinity/candid/releases/download/${version}/didc-linux64";
      sha256 = "1k7vv6p0cji6vlbzsnjyj8z3hg5s91zby7ic7wkhzzn6v5v3qs9j";
    };

    dontUnpack = true;
    nativeBuildInputs = with prev; [ autoPatchelfHook ];
    buildInputs = with prev; [ stdenv.cc.cc.lib ];

    installPhase = ''
      mkdir -p $out/bin
      cp $src $out/bin/didc
      chmod +x $out/bin/didc
    '';

    meta = with prev.lib; {
      description = "Candid CLI - encode/decode/check Candid values";
      homepage = "https://github.com/dfinity/candid";
      license = licenses.asl20;
    };
  };
}
