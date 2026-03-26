{ pkgs, ... }:

{
  projectRootFile = "flake.nix";
  programs.nixfmt.enable = true;
  programs.ormolu.enable = true;
}
