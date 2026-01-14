# Idris2 EVM toolchain overlay
# Provides: idris2-cdk, idris2-yul, idris2-subcontract, buildEvmContract
#
# Usage: import in flake.nix as overlay
#
# For reproducible EVM contract builds from Idris2 source
#
# Dependency order (based on ipkg files):
#   - idris2-cdk: Standalone (ICP-specific, FRMonad)
#   - idris2-yul: Standalone compiler (Idris2 -> Yul -> EVM)
#   - idris2-subcontract: Depends on idris2-yul (UCS framework)

final: prev:
let
  # Pinned commits for reproducibility
  idris2-cdk-src = prev.fetchFromGitHub {
    owner = "shogochiai";
    repo = "idris2-cdk";
    rev = "225c8035a966e6f4d017f49b006ec15d1d51856a";
    sha256 = "15k1v9x86q6dignnykicmnlqn9sds629rgbi53p025afrn7g9l0w";
  };

  idris2-subcontract-src = prev.fetchFromGitHub {
    owner = "shogochiai";
    repo = "idris2-subcontract";
    rev = "e11875f89ef1f70b64a857600945f920bd8bb151";
    sha256 = "17fkgdb1zap0slykc3gcqva64svxhn2sv1v5r9p719rj8ds5kibh";
  };

  idris2-yul-src = prev.fetchFromGitHub {
    owner = "shogochiai";
    repo = "idris2-yul";
    rev = "0ec96ff0b402097a81e49d23ee48c9b10ac450ab";
    sha256 = "1q2f236g2a83dq4k6m36kqwziw78c0zxsy9vxb5dhhjkvpjlsm75";
  };

  # Use standard idris2 (wrapped, includes prelude)
  # PR #3708 patch is for RefC/WASM backend, not needed for EVM codegen
  idris2 = prev.idris2;

  # idris2Api provides the 'idris2' compiler library package
  # Required by idris2-yul to access Core, TTImp, Parser modules
  idris2Api = prev.idris2Packages.idris2Api;

in {
  # Build idris2-cdk library (ICP-specific, provides FRMonad)
  idris2-cdk = prev.stdenv.mkDerivation {
    pname = "idris2-cdk";
    version = "0.1.0";
    src = idris2-cdk-src;

    nativeBuildInputs = [ idris2 ];

    buildPhase = ''
      export IDRIS2_PREFIX=$out
      idris2 --build idris2-cdk.ipkg
    '';

    installPhase = ''
      mkdir -p $out/lib/idris2
      cp -r build/ttc/* $out/lib/idris2/
    '';
  };

  # Build idris2-yul compiler
  # Requires 'idris2' compiler library package (from idris2Api)
  # Compiles Idris2 source to Yul intermediate representation
  idris2-yul = prev.stdenv.mkDerivation {
    pname = "idris2-yul";
    version = "0.1.0";
    src = idris2-yul-src;

    nativeBuildInputs = [ idris2 ];
    buildInputs = [ idris2Api ];

    buildPhase = ''
      # Add idris2Api to package path (provides 'idris2' compiler library)
      export IDRIS2_PACKAGE_PATH="${idris2Api}/lib/idris2-0.8.0"
      idris2 --build idris2-yul.ipkg
    '';

    installPhase = ''
      mkdir -p $out/bin $out/lib/idris2-0.8.0/idris2-yul-0.1.0
      # Copy wrapper script and app directory (contains .so)
      cp build/exec/idris2-yul $out/bin/
      cp -r build/exec/idris2-yul_app $out/bin/
      # Copy TTC files with proper package structure for Idris2
      # Structure: idris2-0.8.0/idris2-yul-0.1.0/<ttc-version>/...
      cp -r build/ttc/* $out/lib/idris2-0.8.0/idris2-yul-0.1.0/ 2>/dev/null || true
      # Create ipkg marker
      echo "package idris2-yul" > $out/lib/idris2-0.8.0/idris2-yul-0.1.0/idris2-yul.ipkg
    '';
  };

  # Build idris2-subcontract library
  # UCS (Upgradeable Clone for Scalable) framework
  # Depends on idris2-yul for EVM primitives
  idris2-subcontract = prev.stdenv.mkDerivation {
    pname = "idris2-subcontract";
    version = "0.1.0";
    src = idris2-subcontract-src;

    nativeBuildInputs = [ idris2 ];
    buildInputs = [ final.idris2-yul ];

    buildPhase = ''
      # Add idris2-yul to package path
      export IDRIS2_PACKAGE_PATH="${final.idris2-yul}/lib/idris2-0.8.0"
      idris2 --build idris2-subcontract.ipkg
    '';

    installPhase = ''
      mkdir -p $out/lib/idris2-0.8.0/idris2-subcontract-0.1.0
      cp -r build/ttc/* $out/lib/idris2-0.8.0/idris2-subcontract-0.1.0/ 2>/dev/null || true
      echo "package idris2-subcontract" > $out/lib/idris2-0.8.0/idris2-subcontract-0.1.0/idris2-subcontract.ipkg
    '';
  };

  # Function to build EVM contract from Idris2 source
  # Usage: buildEvmContract { name = "MyContract"; src = ./.; evmVersion = "cancun"; }
  #
  # Pipeline: Idris2 source -> idris2-yul -> Yul IR -> solc -> EVM bytecode
  # Output: ${name}.yul, ${name}.bin, ${name}.bin-runtime, sha256 hashes
  buildEvmContract = { name, src, evmVersion ? "cancun" }:
    prev.stdenv.mkDerivation {
      pname = "evm-contract-${name}";
      version = "0.1.0";
      inherit src;

      nativeBuildInputs = [
        idris2
        final.idris2-yul
        prev.solc
      ];

      buildPhase = ''
        # Set up package paths for idris2-yul library
        export IDRIS2_PACKAGE_PATH="${final.idris2-yul}/lib/idris2"

        # Step 1: Idris2 -> Yul
        echo "Compiling Idris2 to Yul..."
        idris2-yul ${name}.idr -o ${name}.yul

        # Step 2: Yul -> EVM bytecode
        echo "Compiling Yul to EVM bytecode (--evm-version ${evmVersion})..."
        solc --strict-assembly --evm-version ${evmVersion} --bin ${name}.yul.yul > ${name}.bin.tmp
        tail -1 ${name}.bin.tmp > ${name}.bin

        # Runtime bytecode
        solc --strict-assembly --evm-version ${evmVersion} --bin-runtime ${name}.yul.yul > ${name}.bin-runtime.tmp
        tail -1 ${name}.bin-runtime.tmp > ${name}.bin-runtime
      '';

      installPhase = ''
        mkdir -p $out
        cp ${name}.yul.yul $out/${name}.yul
        cp ${name}.bin $out/${name}.bin
        cp ${name}.bin-runtime $out/${name}.bin-runtime

        # Generate hash for verification (reproducible build attestation)
        sha256sum $out/${name}.bin > $out/${name}.bin.sha256
        sha256sum $out/${name}.bin-runtime > $out/${name}.bin-runtime.sha256

        echo "=== Build complete ==="
        echo "Bytecode hashes (for Auditor verification):"
        cat $out/${name}.bin.sha256
        cat $out/${name}.bin-runtime.sha256
      '';

      # Ensure deterministic output
      outputHashMode = "recursive";
    };
}
