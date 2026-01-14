{
  description = "FABI - Failure-Aware Build Infrastructure for Self-Amending Protocols";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";

    # TODO: EVM/IC flakes
    # evm-flake.url = "github:xxx/evm-flake";
    # ic-flake.url = "github:xxx/ic-flake";
  };

  outputs = { self, nixpkgs, flake-utils, ... }:
    flake-utils.lib.eachSystem [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" ] (system:
      let
        # Apply overlays: Idris2 (PR #3708 fix) + IC/EVM/Idris2-EVM toolchain
        pkgs = import nixpkgs {
          inherit system;
          overlays = [
            (import ./nix/idris2-overlay.nix)
            (import ./nix/ic-overlay.nix)
            (import ./nix/evm-overlay.nix)
            (import ./nix/idris2-evm-overlay.nix)
          ];
        };

        # Idris2 ツールチェーン (patched)
        idris2Packages = with pkgs; [
          idris2-wasm32-fixed
          # idris2-pack  # TODO: ビルド確認後に有効化
        ];

        # EVM ツールチェーン (from evm-overlay.nix)
        evmPackages = with pkgs; [
          solc          # Solidity compiler (nixpkgs version)
          foundry-bin   # forge, cast, anvil, chisel
        ];

        # IC/WASM ツールチェーン (from ic-overlay.nix)
        icPackages = with pkgs; [
          dfx
          ic-wasm
          didc
        ];

        # WASM ビルド
        wasmPackages = with pkgs; [
          emscripten
          binaryen      # wasm-opt
          wabt          # wasm2wat, wat2wasm
        ];

        # lazy CLI 依存 (FFI経由で使用)
        lazyPackages = with pkgs; [
          onnxruntime   # ML推論 (STI Parity分析等)
          sqlite        # キャッシュ/インデックス
        ];

        # 共通依存
        commonPackages = with pkgs; [
          gmp
          zlib
          pkg-config
          gnumake
          git
          curl
          jq
        ];

      in {
        devShells.default = pkgs.mkShell {
          name = "fabi-dev";

          buildInputs = commonPackages
            ++ wasmPackages
            ++ evmPackages
            ++ icPackages
            ++ idris2Packages
            ++ lazyPackages;

          shellHook = ''
            echo "══════════════════════════════════════════════"
            echo "  FABI Development Environment"
            echo "  Failure-Aware Build Infrastructure"
            echo "══════════════════════════════════════════════"
            echo ""
            echo "Idris2 (PR #3708 patched):"
            echo "  idris2 --version"
            echo ""
            echo "WASM tools:"
            echo "  emcc, wasm-opt, wasm2wat"
            echo ""
            echo "EVM tools:"
            echo "  solc, forge, cast, anvil, chisel"
            echo ""
            echo "IC tools:"
            echo "  dfx, ic-wasm, didc"
            echo ""
            echo "lazy CLI deps:"
            echo "  onnxruntime, sqlite"
            echo ""

            # Pack cache directory
            export PACK_DIR="$HOME/.pack"

            # Emscripten cache
            export EM_CACHE="$HOME/.emscripten_cache"

            # Idris2 packages path
            export IDRIS2_PACKAGE_PATH="$HOME/.idris2/packages"

            # FFI library paths for lazy CLI
            export ONNXRUNTIME_LIB="${pkgs.onnxruntime}/lib"
            export SQLITE_LIB="${pkgs.sqlite.out}/lib"
          '';
        };

        # Patched Idris2 as package
        packages = {
          idris2 = pkgs.idris2-wasm32-fixed;

          # Idris2 EVM toolchain
          idris2-cdk = pkgs.idris2-cdk;           # ICP CDK (FRMonad)
          idris2-yul = pkgs.idris2-yul;           # Idris2 -> Yul compiler
          idris2-subcontract = pkgs.idris2-subcontract;  # UCS framework

          # 再現可能 OUC WASM ビルド (TODO)
          # ouc-wasm = pkgs.stdenv.mkDerivation { ... };
        };

        # Default package
        packages.default = pkgs.idris2-wasm32-fixed;
      }
    );
}
