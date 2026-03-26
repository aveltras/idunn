{ pkgs, ... }:

{
  projectRootFile = "flake.nix";
  programs.cabal-gild.enable = true;
  programs.clang-format.enable = true;
  programs.nixfmt.enable = true;
  programs.ormolu.enable = true;
}
