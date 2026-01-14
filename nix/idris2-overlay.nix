# Idris2 overlay with PR #3708 WASM32 fix
# Usage: import in flake.nix as overlay

final: prev: {
  # Patch the unwrapped idris2 package directly
  # The support/refc/runtime.c fix is for WASM32 where UINTPTR_WIDTH is undefined
  idris2-wasm32-fixed = prev.idris2.passthru.unwrapped.overrideAttrs (oldAttrs: {
    pname = "idris2-wasm32-fixed";

    postPatch = (oldAttrs.postPatch or "") + ''
      echo "Applying PR #3708: WASM32 integer comparison fix"

      # Fix idris2_extractInt to use shift instead of idris2_vp_to_Int32
      sed -i 's|return (int)idris2_vp_to_Int32(v);|return (int)((uintptr_t)(v) >> idris2_vp_int_shift);|' \
        support/refc/runtime.c

      # Verify the change was applied
      grep -q 'idris2_vp_int_shift' support/refc/runtime.c && \
        echo "PR #3708 fix applied successfully" || \
        (echo "ERROR: PR #3708 fix failed to apply" && exit 1)
    '';
  });

  # Pack package manager (if not in nixpkgs, build from source)
  idris2-pack = prev.stdenv.mkDerivation rec {
    pname = "idris2-pack";
    version = "0.1.0";

    src = prev.fetchFromGitHub {
      owner = "stefan-hoeck";
      repo = "idris2-pack";
      rev = "main";  # TODO: pin to specific commit
      sha256 = prev.lib.fakeSha256;  # Will fail first time, use reported hash
    };

    nativeBuildInputs = [ final.idris2-wasm32-fixed ];

    buildPhase = ''
      # Bootstrap pack with patched idris2
      make bootstrap IDRIS2=${final.idris2-wasm32-fixed}/bin/idris2
    '';

    installPhase = ''
      mkdir -p $out/bin
      cp build/exec/pack $out/bin/
    '';

    meta = with prev.lib; {
      description = "Package manager for Idris2";
      homepage = "https://github.com/stefan-hoeck/idris2-pack";
      license = licenses.bsd3;
    };
  };
}
