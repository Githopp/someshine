/*
  Apollo Nix package.

  Adapted from:
    - nixpkgs' Sunshine package (pkgs/by-name/su/sunshine/package.nix),
      which uses the same LizardByte cmake skeleton as Apollo;
    - the (archived) nil-andreas/apollo-flake for the Apollo-specific
      deltas: no Qt, tray via ayatana-appindicator, and a web UI lockfile
      that has to be maintained here (see nix/README.md).

  The `src` must be a checkout of this repository *including the
  third-party/* git submodules* — fetch this flake with
    apollo.url = "git+https://github.com/Githopp/Apollo.git?submodules=1";
  The source guard below turns a submodule-less fetch into an actionable
  error instead of an obscure cmake failure.
*/
{
  lib,
  stdenv,
  fetchzip,
  buildNpmPackage,
  autoPatchelfHook,
  autoAddDriverRunpath,
  cmake,
  pkg-config,
  makeWrapper,
  python3,
  wayland,
  wayland-scanner,
  shaderc,
  avahi,
  boost,
  curl,
  libevdev,
  libpulseaudio,
  libx11,
  libxcb,
  libxfixes,
  libxrandr,
  libxtst,
  libxi,
  libxdmcp,
  openssl,
  libopus,
  libdrm,
  libffi,
  libcap,
  libgbm,
  pcre2,
  libuuid,
  libselinux,
  libsepol,
  libthai,
  libdatrie,
  libxkbcommon,
  libepoxy,
  libva,
  libvdpau,
  libglvnd,
  numactl,
  amf-headers,
  svt-av1,
  vulkan-loader,
  pipewire,
  libnotify,
  libayatana-appindicator,
  miniupnpc,
  nlohmann_json,
  coreutils,
  udevCheckHook,
  config,
  cudaSupport ? config.cudaSupport or false,
  cudaPackages ? { },
  # injected by flake.nix
  src,
  version,
  commit ? "",
}:

let
  stdenv' = if cudaSupport then cudaPackages.backendStdenv else stdenv;

  # Upstream's cmake links pre-built static FFmpeg libraries from the
  # LizardByte/build-deps release artifacts at configure time; we can't do
  # network I/O in the build sandbox, so fetch the archive with a
  # fixed-output derivation and point cmake at it via FFMPEG_PREPARED_BINARIES.
  # The tag must match the third-party/build-deps submodule pin of the
  # Apollo source being built (see nix/README.md).
  buildDepsTag = "v2026.910.121303";
  ffmpegArch =
    {
      x86_64-linux = "Linux-x86_64";
      aarch64-linux = "Linux-aarch64";
    }
    .${stdenv.hostPlatform.system};

  ffmpegPrebuilt = fetchzip {
    url = "https://github.com/LizardByte/build-deps/releases/download/${buildDepsTag}/${ffmpegArch}-ffmpeg.tar.gz";
    hash =
      {
        x86_64-linux = "sha256-1S57XfkJa+qEYQLmifWyT9ul0SASFhSk1lkk2timnOY=";
        aarch64-linux = "sha256-1HnlNem4AbcJkhZA8x5hC1/4cCqL8bJDjXNkHCI5IYw=";
      }
      .${stdenv.hostPlatform.system};
  };

  # Flakes fetched as tarballs (the `github:` fetcher) do not contain git
  # submodule content; fail early with instructions instead of letting the
  # cmake configure step fail confusingly further down.
  srcWithSubmodules =
    if lib.pathExists (src + "/third-party/moonlight-common-c/enet/CMakeLists.txt") then
      src
    else
      throw ''
        Apollo's third-party/* git submodules are missing from the flake source
        (checked: third-party/moonlight-common-c/enet/CMakeLists.txt).

        Fetch this flake with its submodules, e.g.:
            apollo.url = "git+https://github.com/Githopp/Apollo.git?submodules=1";
        The `github:` tarball fetcher cannot provide submodule content.'';

in
stdenv'.mkDerivation (finalAttrs: {
  pname = "apollo";
  inherit version;
  src = srcWithSubmodules;

  __structuredAttrs = true;
  strictDeps = true;

  # Web UI built separately (upstream runs `npm build` from cmake; we build
  # it with buildNpmPackage and drop it into place in preBuild below).
  ui = buildNpmPackage {
    inherit (finalAttrs) src version;
    pname = "apollo-ui";
    npmDepsHash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
    installPhase = ''
      runHook preInstall

      mkdir -p "$out"
      cp -a . "$out"/

      runHook postInstall
    '';
  };

  postPatch =
    # web UI prebuilt separately; drop the cmake npm integration
    ''
      substituteInPlace cmake/targets/common.cmake \
        --replace-fail 'find_program(NPM npm REQUIRED)' ""
    ''
    # use system boost instead of FetchContent (same mechanism as nixpkgs'
    # sunshine package): pin BOOST_VERSION to our boost instead of the exact
    # one pinned upstream, and mark FetchContent boost as already handled so
    # Simple-Web-Server does not try to re-find it.
    + ''
      sed -i -E 's/set\(BOOST_VERSION "[^"]*"\)/set(BOOST_VERSION "${boost.version}")/' \
        cmake/dependencies/Boost_Sunshine.cmake
      echo 'set(FETCH_CONTENT_BOOST_USED TRUE)' >> cmake/dependencies/Boost_Sunshine.cmake
    ''
    # remove upstream dependency on systemd and udev at configure time; the
    # install directories are provided explicitly in cmakeFlags instead
    + ''
      substituteInPlace cmake/packaging/linux.cmake \
        --replace-fail 'find_package(Systemd)' "" \
        --replace-fail 'find_package(Udev)' ""

      substituteInPlace packaging/linux/dev.lizardbyte.app.Sunshine.desktop \
        --replace-fail '/usr/bin/env systemctl start --u sunshine' 'sunshine'

      substituteInPlace packaging/linux/sunshine.service.in \
        --replace-fail '/bin/sleep' '${lib.getExe' coreutils "sleep"}'
    '';

  nativeBuildInputs = [
    cmake
    pkg-config
    # glad's generator needs Jinja2 + setuptools at configure time;
    # GLAD_SKIP_PIP_INSTALL tells cmake not to pip-install them.
    (python3.withPackages (ps: [
      ps.jinja2
      ps.setuptools
    ]))
    makeWrapper
    wayland-scanner
    shaderc # provides glslc, needed at configure time for shader compilation
    # Avoid fighting upstream's usage of vendored ffmpeg libraries
    autoPatchelfHook
  ]
  ++ lib.optionals cudaSupport [
    autoAddDriverRunpath
    cudaPackages.cuda_nvcc
    (lib.getDev cudaPackages.cuda_cudart)
  ];

  buildInputs = [
    boost
    curl
    miniupnpc
    nlohmann_json
    openssl
    libopus
    avahi
    libevdev
    libpulseaudio
    libx11
    libxcb
    libxfixes
    libxrandr
    libxtst
    libxi
    libxdmcp
    libdrm
    wayland
    libffi
    libcap
    pcre2
    libuuid
    libselinux
    libsepol
    libthai
    libdatrie
    libxkbcommon
    libepoxy
    libva
    libvdpau
    libglvnd
    numactl
    libgbm
    amf-headers
    svt-av1
    vulkan-loader
    pipewire
    # tray icon support (cmake prefers ayatana-appindicator3, falls back to
    # appindicator3, and only hard-fails if neither is found and libnotify
    # is absent; provide both so the tray is actually built)
    libayatana-appindicator
    libnotify
  ]
  ++ lib.optionals cudaSupport [
    cudaPackages.cuda_cudart
  ];

  runtimeDependencies = [
    avahi
    libgbm
    libxrandr
    libxcb
    libglvnd
    pipewire
    libayatana-appindicator
  ];

  cmakeFlags = [
    "-Wno-dev"
    (lib.cmakeBool "BUILD_DOCS" false)
    (lib.cmakeBool "BOOST_USE_STATIC" false)
    (lib.cmakeFeature "SUNSHINE_PUBLISHER_NAME" "nix")
    (lib.cmakeFeature "SUNSHINE_PUBLISHER_WEBSITE" "https://github.com/Githopp/Apollo")
    (lib.cmakeFeature "SUNSHINE_PUBLISHER_ISSUE_URL" "https://github.com/Githopp/Apollo/issues")
    # avoid cmake's network download of the LizardByte/build-deps ffmpeg tarball
    (lib.cmakeFeature "FFMPEG_PREPARED_BINARIES" "${ffmpegPrebuilt}")
    # we provide Jinja2/setuptools via python3.withPackages; don't pip-install
    (lib.cmakeBool "GLAD_SKIP_PIP_INSTALL" true)
    # upstream tries to use systemd and udev packages to find these
    # directories in FHS; stub the lookups and set the paths explicitly
    (lib.cmakeBool "UDEV_FOUND" true)
    (lib.cmakeBool "SYSTEMD_FOUND" true)
    (lib.cmakeFeature "UDEV_RULES_INSTALL_DIR" "lib/udev/rules.d")
    (lib.cmakeFeature "SYSTEMD_USER_UNIT_INSTALL_DIR" "lib/systemd/user")
    (lib.cmakeFeature "SYSTEMD_MODULES_LOAD_DIR" "lib/modules-load.d")
    # used in the generated systemd unit's ExecStart= line
    (lib.cmakeFeature "SUNSHINE_EXECUTABLE_PATH" "${placeholder "out"}/bin/sunshine")
  ]
  ++ lib.optionals (!cudaSupport) [
    (lib.cmakeBool "SUNSHINE_ENABLE_CUDA" false)
  ]
  ++ lib.optionals cudaSupport [
    (lib.cmakeBool "SUNSHINE_ENABLE_CUDA" true)
  ];

  env = {
    # BUILD_VERSION + BRANCH together put cmake's version lookup into "CI
    # mode" (cmake/prep/build_version.cmake), skipping `git describe`.
    BUILD_VERSION = version;
    BRANCH = "master";
    COMMIT = commit;
  };

  # copy webui where it can be picked up by the build
  preBuild = ''
    cp -r ${finalAttrs.ui}/build ../
  '';

  buildFlags = [
    "sunshine"
  ];

  # redefine installPhase to avoid attempt to build webui
  installPhase = ''
    runHook preInstall

    cmake --install .

    runHook postInstall
  '';

  postFixup = lib.optionalString cudaSupport ''
    wrapProgram $out/bin/sunshine \
      --set LD_LIBRARY_PATH ${lib.makeLibraryPath [ vulkan-loader ]}
  '';

  doInstallCheck = true;

  nativeInstallCheckInputs = [
    udevCheckHook
  ];

  meta = {
    description = "Self-hosted game stream host for Moonlight (Sunshine fork)";
    homepage = "https://github.com/ClassicOldSong/Apollo";
    license = lib.licenses.gpl3Only;
    mainProgram = "sunshine";
    # ffmpegPrebuilt hashes above only cover linux
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
  };
})
