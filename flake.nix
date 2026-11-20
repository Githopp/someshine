{
  description = "Apollo — self-hosted game stream host for Moonlight (Sunshine fork); Nix packaging maintained in this fork";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      inherit (nixpkgs) lib;
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];

      # Bump this when merging/rebasing onto a new upstream Apollo release
      # (all upstream tags so far are v0.4.x). The commit suffix keeps
      # provenance in the version string shown by the Web UI.
      versionBase = "v0.4.8-unstable";
      commit = self.sourceInfo.rev or "dirty";
      fullVersion = "${versionBase}-${builtins.substring 0 8 commit}";

      apolloFor =
        pkgs:
        pkgs.callPackage ./nix/package.nix {
          src = self; # submodule sanity check lives in nix/package.nix
          version = fullVersion;
          inherit commit;
        };
    in
    {
      packages = lib.genAttrs systems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        rec {
          apollo = apolloFor pkgs;
          # Apollo is a drop-in Sunshine replacement: same binary name
          # (bin/sunshine), udev rules, tmpfiles and config paths.
          sunshine = apollo;
          default = apollo;
        }
      );

      # Supersede sunshine wherever this overlay is applied: pkgs.sunshine
      # becomes this Apollo build, so nixpkgs' services.sunshine module
      # (and anything else referencing pkgs.sunshine) runs Apollo.
      overlays.default = final: _prev: {
        sunshine = apolloFor final;
        apollo = final.sunshine;
      };
    };
}
