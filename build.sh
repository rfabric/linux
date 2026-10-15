#!/usr/bin/env bash
# Builds the rFabric apt and dnf package repository site into <out-dir> from the GitHub
# Releases of the source repos below: the .deb and .rpm assets of the newest STABLE_KEEP
# stable and RC_KEEP release-candidate releases of each, apt and dnf indexes over them, and
# signatures by the GPG key SIGNING_KEY (a fingerprint already in the keyring).
#
#   BASE_URL=https://linux.rfabric.io SIGNING_KEY=<fingerprint> ./build.sh _site
#
# The site is rebuilt whole on every run, so a deleted GitHub Release leaves the repository
# on the next run. Needs gh (authenticated), apt-ftparchive, createrepo_c, gpg.
set -euo pipefail

out="${1:?usage: build.sh <out-dir>}"
: "${BASE_URL:?BASE_URL is required}" "${SIGNING_KEY:?SIGNING_KEY is required}"

sources=(rfabric/cli rfabric/agent)
channels=(stable rc)
deb_archs=(amd64 arm64)
STABLE_KEEP=3
RC_KEEP=2
# GitHub Pages serves at most 1 GB per site.
MAX_SITE_MB=900

here="$(cd "$(dirname "$0")" && pwd)"
rm -rf "$out"
mkdir -p "$out"
out="$(cd "$out" && pwd)"

sign_clear() { gpg --batch --yes --local-user "$SIGNING_KEY" --clearsign --output "$2" "$1"; }
sign_detached() { gpg --batch --yes --local-user "$SIGNING_KEY" --armor --detach-sign --output "$2" "$1"; }

# releases <repo> <channel>: the tags of that channel to publish, newest first.
releases() {
  local prerelease=false keep=$STABLE_KEEP
  if [ "$2" = rc ]; then prerelease=true keep=$RC_KEEP; fi
  gh release list --repo "$1" --limit 100 --exclude-drafts --json tagName,isPrerelease,publishedAt \
    -q "[.[] | select(.isPrerelease == $prerelease)] | sort_by(.publishedAt) | reverse | .[:$keep][] | .tagName"
}

fail() { echo "build.sh: $*" >&2; exit 1; }

# download <repo> <tag> <ext> <dir>: every asset of that release ending in .<ext>. Every
# published release carries Linux packages, so a release without any is an error.
download() {
  local names name
  names="$(gh release view "$2" --repo "$1" --json assets -q ".assets[].name | select(endswith(\".$3\"))")"
  [ -n "$names" ] || fail "$1 $2 has no .$3 assets"
  for name in $names; do
    gh release download "$2" --repo "$1" --pattern "$name" --dir "$4" --skip-existing
  done
}

gpg --batch --armor --export "$SIGNING_KEY" > "$out/rfabric.asc"
[ -s "$out/rfabric.asc" ] || fail "no public key for $SIGNING_KEY"

for channel in "${channels[@]}"; do
  deb_pool="$out/deb/pool/$channel"
  rpm_dir="$out/rpm/$channel"
  mkdir -p "$deb_pool" "$rpm_dir"
  for repo in "${sources[@]}"; do
    # Assigned first, so a failed GitHub API call stops the build instead of iterating
    # over nothing and publishing an empty repository.
    tags="$(releases "$repo" "$channel")"
    [ -n "$tags" ] || [ "$channel" = rc ] || fail "$repo has no stable release"
    for tag in $tags; do
      echo "$channel: $repo $tag" >&2
      download "$repo" "$tag" deb "$deb_pool"
      download "$repo" "$tag" rpm "$rpm_dir"
    done
  done

  # apt: one suite per channel, component main.
  dists="$out/deb/dists/$channel"
  for arch in "${deb_archs[@]}"; do
    mkdir -p "$dists/main/binary-$arch"
    (cd "$out/deb" && apt-ftparchive --arch "$arch" packages "pool/$channel") > "$dists/main/binary-$arch/Packages"
    gzip -9 -n -k "$dists/main/binary-$arch/Packages"
  done
  release_tmp="$(mktemp)"
  apt-ftparchive \
    -o APT::FTPArchive::Release::Origin=rFabric \
    -o APT::FTPArchive::Release::Label=rFabric \
    -o "APT::FTPArchive::Release::Suite=$channel" \
    -o "APT::FTPArchive::Release::Codename=$channel" \
    -o "APT::FTPArchive::Release::Architectures=${deb_archs[*]}" \
    -o APT::FTPArchive::Release::Components=main \
    release "$dists" > "$release_tmp"
  mv "$release_tmp" "$dists/Release"
  sign_clear "$dists/Release" "$dists/InRelease"
  sign_detached "$dists/Release" "$dists/Release.gpg"

  # dnf: one repository per channel; the signed repomd.xml carries every package checksum.
  createrepo_c --quiet "$rpm_dir"
  sign_detached "$rpm_dir/repodata/repomd.xml" "$rpm_dir/repodata/repomd.xml.asc"
  cat > "$out/rpm/rfabric-$channel.repo" <<EOF
[rfabric]
name=rFabric ($channel)
baseurl=$BASE_URL/rpm/$channel/
enabled=1
gpgcheck=0
repo_gpgcheck=1
gpgkey=$BASE_URL/rfabric.asc
EOF
done

sed "s|@BASE_URL@|$BASE_URL|g" "$here/index.html" > "$out/index.html"

size_mb="$(du -sm "$out" | cut -f1)"
[ "$size_mb" -le "$MAX_SITE_MB" ] || fail "site is ${size_mb} MB, above ${MAX_SITE_MB} MB (GitHub Pages limit 1 GB); lower STABLE_KEEP or RC_KEEP"
echo "build.sh: $out (${size_mb} MB)" >&2
