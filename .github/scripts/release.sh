#!/usr/bin/env bash
# Publishes a GitHub Release from the files the build jobs made.
#
#   release.sh prepare <dist-dir> <out-dir>   versioned file names, SHA256SUMS.txt, notes.md
#   release.sh publish <out-dir>              create (or replace) the release on GitHub
#
# Environment: VERSION (x.y.z), TAG (vX.Y.Z), REPO (owner/name); for publish also
# GH_TOKEN, SHA (commit to tag), EXISTS (true/false), TAG_REF (true when run for a pushed tag).
set -euo pipefail

prepare() {
  local dist="$1" out="$2"
  mkdir -p "$out"
  copy() { if [ -f "$dist/$1" ]; then cp "$dist/$1" "$out/$2"; else echo "::warning::$1 was not built"; fi; }
  copy TuitMate.apk "TuitMate-$VERSION.apk"
  copy TuitMate-Setup.exe "TuitMate-$VERSION-Setup.exe"
  copy TuitMate-windows-portable.zip "TuitMate-$VERSION-windows-portable.zip"
  # Fixed names: the installer downloads releases/latest/download/<name>.
  copy tuitmate-server-linux-x64 tuitmate-server-linux-x64
  copy tuitmate-server-install.sh tuitmate-server-install.sh
  [ -f "$out/TuitMate-$VERSION.apk" ] || { echo "::error::No APK to publish"; exit 1; }
  (cd "$out" && shopt -s nullglob && sha256sum -- *.apk *.exe *.zip tuitmate-server-* > SHA256SUMS.txt)

  # "cert_sha256=…" and "own_key=true|false", written by the android job.
  local cert="" own_key="false"
  if [ -f "$dist/signing.txt" ]; then
    cert=$(sed -n 's/^cert_sha256=//p' "$dist/signing.txt")
    own_key=$(sed -n 's/^own_key=//p' "$dist/signing.txt")
  fi

  # This version's section of CHANGELOG.md (from its "## [x.y.z]" heading to the next "## ").
  local changes
  changes=$(awk -v v="[$VERSION]" '/^## /{p = index($0, v) > 0; next} p' CHANGELOG.md)
  [ -n "${changes//[[:space:]]/}" ] || changes="See CHANGELOG.md."

  local apk="TuitMate-$VERSION.apk" exe="TuitMate-$VERSION-Setup.exe" zip="TuitMate-$VERSION-windows-portable.zip"
  {
    echo "$changes"
    echo
    echo "## Downloads"
    echo
    echo "| File | For |"
    echo "|---|---|"
    echo "| [\`$apk\`](https://github.com/$REPO/releases/download/$TAG/$apk) | **Android** 7.0 or newer: open it on the phone and allow installing apps from this source |"
    [ -f "$out/$exe" ] && echo "| [\`$exe\`](https://github.com/$REPO/releases/download/$TAG/$exe) | **Windows** 10 / 11 (64-bit) installer, no admin rights needed |"
    [ -f "$out/$zip" ] && echo "| [\`$zip\`](https://github.com/$REPO/releases/download/$TAG/$zip) | **Windows** without installing: unzip anywhere and run \`TuitMate.exe\` |"
    [ -f "$out/tuitmate-server-install.sh" ] && echo "| [\`tuitmate-server-install.sh\`](https://github.com/$REPO/releases/download/$TAG/tuitmate-server-install.sh) | **Your own server** (Ubuntu VPS): installs MySQL 8 and the TuitMate server, see [server/README.md](https://github.com/$REPO/blob/main/server/README.md) |"
    [ -f "$out/tuitmate-server-linux-x64" ] && echo "| [\`tuitmate-server-linux-x64\`](https://github.com/$REPO/releases/download/$TAG/tuitmate-server-linux-x64) | The server program (the installer downloads it) |"
    echo "| [\`SHA256SUMS.txt\`](https://github.com/$REPO/releases/download/$TAG/SHA256SUMS.txt) | Checksums of the files above |"
    echo
    echo "## Check your download"
    echo
    echo "Each file's SHA-256 must match the one in \`SHA256SUMS.txt\`:"
    echo
    echo '```'
    sed 's/^/  /' "$out/SHA256SUMS.txt"
    echo '```'
    echo
    local win="$exe"; [ -f "$out/$exe" ] || win="$zip"
    echo "- Windows (PowerShell): \`Get-FileHash .\\$win -Algorithm SHA256\`"
    echo "- Linux / macOS / Termux: \`sha256sum -c SHA256SUMS.txt --ignore-missing\`"
    if [ -n "$cert" ]; then
      echo "- Android signing certificate (SHA-256): \`$cert\`"
    fi
    echo
    if [ "$own_key" != "true" ]; then
      echo "> [!WARNING]"
      echo "> This APK is signed with a **temporary key**, so it cannot update an installed TuitMate (Android would ask"
      echo "> to uninstall first, which deletes the app's data). Add the \`ANDROID_KEYSTORE_BASE64\` secret (see README)"
      echo "> and run **Actions → Build apps → Run workflow** to publish this release again with your key."
      echo
    fi
    echo "> [!NOTE]"
    echo "> Windows may show *\"Windows protected your PC\"* because the app is not code-signed: choose"
    echo "> **More info → Run anyway**. TuitMate is unofficial and not affiliated with TUIT."
  } > "$out/notes.md"
  echo "Prepared release $TAG:"; ls -l "$out"
}

publish() {
  local out="$1"
  local files=()
  for f in "$out"/*; do [ "$(basename "$f")" = notes.md ] || files+=("$f"); done
  if [ "${EXISTS:-false}" = "true" ]; then
    if [ "${TAG_REF:-false}" = "true" ]; then
      # A tag you pushed yourself: keep it, refresh the files and notes.
      gh release upload "$TAG" "${files[@]}" --clobber --repo "$REPO"
      gh release edit "$TAG" --notes-file "$out/notes.md" --repo "$REPO"
      return
    fi
    # Run by hand: build the release again from this commit (e.g. after adding the signing key).
    gh release delete "$TAG" --cleanup-tag --yes --repo "$REPO"
  fi
  gh release create "$TAG" "${files[@]}" --repo "$REPO" --title "TuitMate $TAG" \
    --notes-file "$out/notes.md" --target "$SHA" --latest
}

case "${1:-}" in
  prepare) prepare "$2" "$3" ;;
  publish) publish "$2" ;;
  *) echo "usage: $0 prepare <dist> <out> | publish <out>" >&2; exit 2 ;;
esac
