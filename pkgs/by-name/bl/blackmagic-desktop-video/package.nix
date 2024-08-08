{ stdenv
, cacert
, curl
, runCommandLocal
, lib
, autoPatchelfHook
, libcxx
, libGL
, gcc7
}:
stdenv.mkDerivation (finalAttrs: {
  pname = "blackmagic-desktop-video";
  version = "14.1a1";

  buildInputs = [
    autoPatchelfHook
    libcxx
    libGL
    gcc7.cc.lib
  ];

  # yes, the below download function is an absolute mess.
  # blame blackmagicdesign.
  src =
    let
      # from the URL the download page where you click the "only download" button is at
      REFERID = "93b33ad64a244cd5b95ec9d373e8d2e1";
      # from the URL that the POST happens to, see browser console
      DOWNLOADID = "0f544a89ce204df6818079a2f18c76a7";
    in
    runCommandLocal "${finalAttrs.pname}-${lib.versions.majorMinor finalAttrs.version}-src.tar.gz"
      {
        outputHashMode = "recursive";
        outputHashAlgo = "sha256";
        outputHash = "sha256-1Cv7VQHhHcM53DKa15lJJVJmdiGUHNTYPTbX+VghQOc=";

        impureEnvVars = lib.fetchers.proxyImpureEnvVars;

        nativeBuildInputs = [ curl ];

        # ENV VARS
        SSL_CERT_FILE = "${cacert}/etc/ssl/certs/ca-bundle.crt";

        inherit REFERID;
        SITEURL = "https://www.blackmagicdesign.com/api/register/us/download/${DOWNLOADID}";

        USERAGENT = builtins.concatStringsSep " " [
          "User-Agent: Mozilla/5.0 (X11; Linux ${stdenv.hostPlatform.linuxArch})"
          "AppleWebKit/537.36 (KHTML, like Gecko)"
          "Chrome/77.0.3865.75"
          "Safari/537.36"
        ];

        REQJSON = builtins.toJSON {
          "country" = "nl";
          "downloadOnly" = true;
          "platform" = "Linux";
          "policy" = true;
        };

      } ''
      RESOLVEURL=$(curl \
        -s \
        -H "$USERAGENT" \
        -H 'Content-Type: application/json;charset=UTF-8' \
        -H "Referer: https://www.blackmagicdesign.com/support/download/$REFERID/Linux" \
        --data-ascii "$REQJSON" \
        --compressed \
        "$SITEURL")
      curl \
        --retry 3 --retry-delay 3 \
        --compressed \
        "$RESOLVEURL" \
        > $out
    '';

  postUnpack =
    let
      arch = stdenv.hostPlatform.uname.processor;
    in
    ''
      tar xf Blackmagic_Desktop_Video_Linux_${lib.head (lib.splitString "a" finalAttrs.version)}/other/${arch}/desktopvideo-${finalAttrs.version}-${arch}.tar.gz
      unpacked=$NIX_BUILD_TOP/desktopvideo-${finalAttrs.version}-${stdenv.hostPlatform.uname.processor}
    '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/{bin,share/doc,lib/systemd/system}
    cp -r $unpacked/usr/share/doc/desktopvideo $out/share/doc
    cp $unpacked/usr/lib/*.so $out/lib
    cp $unpacked/usr/lib/systemd/system/DesktopVideoHelper.service $out/lib/systemd/system
    cp $unpacked/usr/lib/blackmagic/DesktopVideo/DesktopVideoHelper $out/bin/
    substituteInPlace $out/lib/systemd/system/DesktopVideoHelper.service \
      --replace-fail "/usr/lib/blackmagic/DesktopVideo/DesktopVideoHelper" "$out/bin/DesktopVideoHelper"
    runHook postInstall
  '';

  # need to tell the DesktopVideoHelper where to find its own library
  appendRunpaths = [ "${placeholder "out"}/lib" ];

  meta = with lib; {
    homepage = "https://www.blackmagicdesign.com/support/family/capture-and-playback";
    maintainers = [ maintainers.naxdy ];
    license = licenses.unfree;
    description = "Supporting applications for Blackmagic Decklink. Doesn't include the desktop applications, only the helper required to make the driver work";
    platforms = platforms.linux;
  };
})
