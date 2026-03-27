{
  inputs = {
    git-hooks.url = "github:cachix/git-hooks.nix";
    git-hooks.inputs.nixpkgs.follows = "nixpkgs";
    hs-bindgen.url = "github:well-typed/hs-bindgen/7d864d7af43becc59a0935c6599ad9a3d20bd688";
    hs-bindgen.inputs.nixpkgs.follows = "nixpkgs";
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nix-filter.url = "github:numtide/nix-filter";
    systems.url = "github:nix-systems/default";
  };

  outputs =
    {
      self,
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

      haskellOverlay = final: prev: {
        haskell = prev.haskell // {
          packageOverrides =
            hfinal: hprev:
            prev.haskell.packageOverrides hfinal hprev
            // {
              idunn = hprev.callCabal2nix "idunn" (nix-filter {
                root = ./.;
                include = [
                  "cbits"
                  "demo"
                  "src"
                  "idunn.cabal"
                ];
              }) { SDL3 = final.sdl3; };
            };
        };
      };

      pkgs = import nixpkgs {
        inherit system;
        overlays = [
          hs-bindgen.overlays.default
          haskellOverlay
        ];
      };

      inherit (self.checks.${system}.pre-commit-check) shellHook enabledPackages;

      llvm = pkgs.llvmPackages_21;

    in
    {
      checks = forEachSystem (system: {
        pre-commit-check = git-hooks.lib.${system}.run {
          src = ./.;
          hooks = {
            cabal-gild.enable = true;
            clang-format.enable = true;
            clang-tidy.enable = true;
            clang-tidy.entry = "${pkgs.writeShellScript "clang-tidy-wrapper" ''
              export CPATH="$(pwd)/cbits/include:$CPATH"
              exec ${pkgs.llvmPackages.clang-tools}/bin/clang-tidy --fix "$@"
            ''}";
            skywalking-eyes = {
              name = "SkyWalking Eyes";
              enable = true;
              entry = "${pkgs.skywalking-eyes}/bin/license-eye header fix";
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

      devShells.${system}.default = pkgs.haskellPackages.shellFor {
        packages = hsPkgs: [ hsPkgs.idunn ];
        withHoogle = true;
        buildInputs =
          with pkgs;
          enabledPackages
          ++ [
            bear
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
            sdl3
            skywalking-eyes
          ];
        shellHook = ''
          ${shellHook}
          export CPATH=$(pwd)/cbits/include:$CPATH
        '';
      };
    };
}
