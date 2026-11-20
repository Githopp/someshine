# Nix packaging for this fork

This directory (`flake.nix`, `nix/package.nix`, `nix/README.md`) — plus a
generated `package-lock.json` at the repository root — is the fork-maintained
addition that upstream Apollo does not ship. Upstream files are never touched,
so merges from `ClassicOldSong/Apollo` stay conflict-free.

## Using this flake

**Important:** the build needs the `third-party/*` git submodules, so the
flake must be fetched with them:

```nix
apollo = {
  # The `github:` tarball fetcher cannot provide submodule content;
  # git+https with ?submodules=1 can.
  url = "git+https://github.com/Githopp/Apollo.git?submodules=1";
  inputs.nixpkgs.follows = "nixpkgs"; # optional
};
```

If it is fetched without submodules, `nix/package.nix` fails evaluation with a
descriptive error instead of a broken cmake configure step.

### Superseding Sunshine with Apollo

Apollo is a drop-in Sunshine replacement: the executable is still
`bin/sunshine`, udev rules are still `60-sunshine.rules`, tmpfiles are still
`60-sunshine.conf`, and configuration still lives in
`~/.config/sunshine/sunshine.conf`. The cleanest way to replace Sunshine
system-wide is the overlay, which makes nixpkgs' `services.sunshine` module
use Apollo automatically:

```nix
nixpkgs.overlays = [ inputs.apollo.overlays.default ];
# keep the regular module:
services.sunshine = {
  enable = true;
  autoStart = true;
  capSysAdmin = true;
  openFirewall = true;
};
```

Alternatively, without an overlay:

```nix
services.sunshine.package =
  inputs.apollo.packages.${pkgs.system}.apollo;
```

## Maintenance notes

### `package-lock.json` (repository root)

Apollo upstream does not commit an npm lockfile, but `buildNpmPackage` needs
one for a reproducible Web UI build. It is committed in this fork. Regenerate
it whenever upstream `package.json` changes:

```console
$ npm install --package-lock-only --ignore-scripts
$ git add -f package-lock.json   # upstream .gitignore discards it; keep it
```

If the lockfile changed, the Web UI build fails with the expected vs. got
hash of its npm dependencies — take the `got: sha256-...` value from the
error and put it into `nix/package.nix` as `npmDepsHash`.

### Prebuilt FFmpeg (`buildDepsTag` in `nix/package.nix`)

Apollo links static FFmpeg libraries from
[LizardByte/build-deps](https://github.com/LizardByte/build-deps) release
artifacts at configure time. The download is done by a fixed-output
derivation using `buildDepsTag`, which must correspond to the
`third-party/build-deps` submodule pin of the source being built:

```console
$ git submodule update --init third-party/build-deps
$ git -C third-party/build-deps log -1   # the pinned commit
```

The download is wired the way upstream expects it: `nix/package.nix`
symlinks the fixed-output derivation into
`third-party/build-deps/dist/<system>-<arch>` in `postPatch` — that is
where the *default* ffmpeg logic of `cmake/dependencies/common.cmake`
looks for it, and that default branch is the one that links the full
static set (`libx264`/`libx265`/`libSvtAv1Enc`/`hdr10plus`). The
`FFMPEG_PREPARED_BINARIES` cmake option is deliberately *not* set: that
branch drops the codec libraries from the link line.

The bundle's bundled `ffnvcodec` headers (newer NVENC API than Apollo's
NVENC code asserts) are repointed at the source tree's own pinned
`third-party/nv-codec-headers` headers.

The hashes currently mirror nixpkgs' `sunshine` package (same
`v2026.910.121303` tag). When bumping: check which tag matches the new
submodule pin, update `buildDepsTag`, and do the same
fake-hash/failure/got-hash dance for `ffmpegPrebuilt.hash` per platform.
If the new bundle's NVENC API diverges from Apollo's pinned
nv-codec-headers, the build asserts it at compile time (that is the
correct place to catch it — bump the submodule pin in the source tree
first).

### Version

`flake.nix` composes the version as `versionBase` + commit_SHORT_SHA.
Bump `versionBase` when merging/rebasing onto a new upstream Apollo release;
the commit suffix is derived automatically from the flake source revision.

### CUDA

Pass `cudaSupport = true` via nixpkgs config (`config.cudaSupport`), same as
nixpkgs' own sunshine package.
