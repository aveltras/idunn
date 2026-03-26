{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nix-filter.url = "github:numtide/nix-filter";
    treefmt-nix.url = "github:numtide/treefmt-nix";
    treefmt-nix.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    {
      self,
      nixpkgs,
      nix-filter,
      treefmt-nix,
      ...
    }@inputs:
    let
      system = "x86_64-linux";
      eachSystem =
        f: nixpkgs.lib.genAttrs [ "x86_64-linux" ] (system: f nixpkgs.legacyPackages.${system});
      treefmtEval = eachSystem (pkgs: treefmt-nix.lib.evalModule pkgs ./treefmt.nix);

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
              }) { };
            };
        };
      };

      pkgs = import nixpkgs {
        inherit system;
        overlays = [ haskellOverlay ];
      };

    in
    {
      checks = eachSystem (pkgs: {
        formatting = treefmtEval.${pkgs.stdenv.hostPlatform.system}.config.build.check self;
      });

      formatter = eachSystem (pkgs: treefmtEval.${pkgs.stdenv.hostPlatform.system}.config.build.wrapper);

      devShells.${system}.default = pkgs.haskellPackages.shellFor {
        packages = hsPkgs: [ hsPkgs.idunn ];
        withHoogle = true;
        buildInputs = with pkgs; [
          ghciwatch
          haskellPackages.cabal-install
          haskellPackages.cabal-gild
          haskellPackages.ghc
          haskellPackages.haskell-language-server
          haskellPackages.hoogle
          haskellPackages.ormolu
          just
          mangohud
          skywalking-eyes
        ];
      };
    };
}
