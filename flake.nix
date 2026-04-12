{
  inputs = {
    git-hooks.url = "github:cachix/git-hooks.nix";
    git-hooks.inputs.nixpkgs.follows = "nixpkgs";
    hs-bindgen.url = "github:well-typed/hs-bindgen/2211bbc404b5fd0e7e7413809ee0dd6379825700";
    hs-bindgen.inputs.nixpkgs.follows = "nixpkgs";
    JoltPhysics.url = "github:jrouwe/JoltPhysics/v5.5.0";
    JoltPhysics.flake = false;
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nix-filter.url = "github:numtide/nix-filter";
    systems.url = "github:nix-systems/default";
    apecs.url = "github:aveltras/apecs/1dae739f561dda5a7602d10b4e25ec7bdb09907f";
    apecs.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    {
      self,
      apecs,
      git-hooks,
      hs-bindgen,
      nixpkgs,
      nix-filter,
      systems,
      ...
    }@inputs:
    let
      system = "x86_64-linux";
      forEachSystem = nixpkgs.lib.genAttrs (import systems);

      overlay = final: prev: {
        haskell = prev.haskell // {
          packageOverrides =
            hfinal: hprev:
            prev.haskell.packageOverrides hfinal hprev
            // {
              apecs = hprev.callCabal2nix "apecs" "${inputs.apecs}/apecs" { };
              idunn =
                let
                  basePkg =
                    hprev.callCabal2nix "idunn"
                      (nix-filter {
                        root = ./.;
                        include = [
                          "cbits"
                          "demo"
                          "src"
                          "idunn.cabal"
                        ];
                      })
                      {
                        SDL3 = final.sdl3;
                        Jolt = final.JoltPhysics;
                      };
                in
                prev.haskell.lib.compose.overrideCabal (drv: {
                  passthru = (drv.passthru or { }) // {
                    systemLibs =
                      (drv.librarySystemDepends or [ ])
                      ++ (drv.executableSystemDepends or [ ])
                      ++ (drv.pkg-configDepends or [ ]);
                  };
                }) basePkg;
            };
        };

        glm = prev.glm.overrideAttrs (
          finalAttrs: prevAttrs: {
            cmakeFlags = prevAttrs.cmakeFlags ++ [ "-DBUILD_SHARED_LIBS=ON" ];
          }
        );

        JoltPhysics = prev.llvmPackages_21.stdenv.mkDerivation rec {
          name = "JoltPhysics";
          src = inputs.JoltPhysics;
          nativeBuildInputs = with prev; [ cmake ];
          cmakeDir = "../Build";
          # https://github.com/jrouwe/JoltPhysics/blob/v5.5.0/Build/CMakeLists.txt
          cmakeFlags = [
            "-DCMAKE_BUILD_TYPE=Debug"
            "-DBUILD_SHARED_LIBS=ON"
            "-DUSE_ASSERTS=OFF"
            "-DDEBUG_RENDERER_IN_DEBUG_AND_RELEASE=OFF"
            "-DPROFILER_IN_DEBUG_AND_RELEASE=OFF"
            "-DENABLE_OBJECT_STREAM=OFF"
          ];
        };
      };

      pkgs = import nixpkgs {
        inherit system;
        overlays = [
          hs-bindgen.overlays.default
          overlay
        ];
      };

      precommitCheck = self.checks.${system}.pre-commit-check;

      llvm = pkgs.llvmPackages_21;

      # https://github.com/google/sanitizers/wiki/AddressSanitizerLeakSanitizer
      asanSuppress = pkgs.writeText "asan_suppress.txt" ''
        leak:fontconfig
        leak:libasan.so
      '';

    in
    {
      checks = forEachSystem (system: {
        pre-commit-check = git-hooks.lib.${system}.run {
          src = ./.;
          hooks = {
            cabal-gild.enable = true;
            clang-format.enable = true;
            clang-tidy.enable = true;
            skywalking-eyes = {
              name = "SkyWalking Eyes";
              enable = true;
              entry = "${pkgs.skywalking-eyes}/bin/license-eye -v error header fix";
            };
            nixfmt.enable = true;
            ormolu.enable = true;
          };
        };
      });

      formatter = forEachSystem (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          config = self.checks.${system}.pre-commit-check.config;
          inherit (config) package configFile;
          script = ''
            ${pkgs.lib.getExe package} run --all-files --config ${configFile}
          '';
        in
        pkgs.writeShellScriptBin "pre-commit-run" script
      );

      devShells.${system}.default = pkgs.haskellPackages.shellFor rec {
        packages = hsPkgs: [ hsPkgs.idunn ];
        withHoogle = true;
        nativeBuildInputs =
          with pkgs;
          [
            shader-slang
            vulkan-headers
            vulkan-loader
            vulkan-memory-allocator
            vulkan-validation-layers
          ]
          ++ haskellPackages.idunn.systemLibs;
        buildInputs =
          with pkgs;
          precommitCheck.enabledPackages
          ++ [
            bear
            gdb
            ghciwatch
            haskellPackages.cabal-install
            haskellPackages.cabal-gild
            haskellPackages.ghc
            haskellPackages.haskell-language-server
            haskellPackages.hoogle
            haskellPackages.ormolu
            just
            llvm.bintools
            llvm.clang-tools
            llvm.libstdcxxClang # https://discourse.nixos.org/t/get-clangd-to-find-standard-headers-in-nix-shell/11268/17
            mangohud
            renderdoc
            skywalking-eyes
            vulkan-tools
          ];
        shellHook = ''
          ${precommitCheck.shellHook}
          export CPATH="$(pwd)/cbits/include:$(pwd)/vendor/volk:$(pwd)/vendor/SPIRV-Reflect:$(pwd)/vendor/Vulkan-Utility-Libraries/include:$(pwd)/vendor/miniaudio:${pkgs.lib.makeIncludePath nativeBuildInputs}:''${CPATH:-}"
          export LD_LIBRARY_PATH=${pkgs.lib.makeLibraryPath nativeBuildInputs};
          export LIBRARY_PATH="${pkgs.lib.makeLibraryPath nativeBuildInputs}"
          export LSAN_OPTIONS="report_objects=1:suppressions=${asanSuppress}"
        '';
      };
    };
}
