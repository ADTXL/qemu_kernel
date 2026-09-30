#!/usr/bin/env bash
#
# setup-kernel.sh - fetch a Linux kernel tree into kernel/<version>
#
# The kernel source trees are NOT stored in this git repository. This script
# clones (or links) the requested kernel version so that the build system can
# use it.
#
# Usage:
#   scripts/setup-kernel.sh v7.2
#   scripts/setup-kernel.sh v7.2 --link /path/to/existing/linux/tree
#   scripts/setup-kernel.sh v7.3 --remote https://github.com/torvalds/linux.git
#
# What it does:
#   * clones torvalds/linux (partial blob-less clone) into a temp dir
#   * fetches exactly the '<version>' tag
#   * checks it out and moves the tree to kernel/<version>
#   * (or) symlinks an existing tree when --link is given
#
# After it succeeds you can build with:
#   make qemu-juno KERNEL_VERSION=v7.2
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KERNEL_BASE="${REPO_ROOT}/kernel"
DEFAULT_REMOTE="https://github.com/torvalds/linux.git"

usage() {
	sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//'
	exit 1
}

VERSION=""
LINK_SRC=""
REMOTE="${DEFAULT_REMOTE}"

while [ $# -gt 0 ]; do
	case "$1" in
		--link)   LINK_SRC="$2"; shift 2 ;;
		--remote) REMOTE="$2"; shift 2 ;;
		-h|--help) usage ;;
		-*) echo "unknown option: $1" >&2; usage ;;
		*) VERSION="$1"; shift ;;
	esac
done

[ -n "$VERSION" ] || usage
[ "$VERSION" != "v4.19" ] || { echo "v4.19 is vendored in kernel/common; nothing to do."; exit 0; }

DEST="${KERNEL_BASE}/${VERSION}"

if [ -n "$LINK_SRC" ]; then
	[ -d "$LINK_SRC" ] || { echo "link source not found: $LINK_SRC" >&2; exit 1; }
	[ -d "$LINK_SRC/.git" ] || { echo "link source is not a git tree: $LINK_SRC" >&2; exit 1; }
	if [ -e "$DEST" ] || [ -L "$DEST" ]; then
		echo "kernel/${VERSION} already exists; leaving it untouched."
		exit 0
	fi
	mkdir -p "$KERNEL_BASE"
	ln -s "$LINK_SRC" "$DEST"
	echo "linked kernel/${VERSION} -> $LINK_SRC"
	echo "build with: make qemu-juno KERNEL_VERSION=${VERSION}"
	exit 0
fi

if [ -e "$DEST" ]; then
	echo "kernel/${VERSION} already exists; leaving it untouched."
	echo "build with: make qemu-juno KERNEL_VERSION=${VERSION}"
	exit 0
fi

TMP="$(mktemp -d "${TMPDIR:-/tmp}/kernel-${VERSION}.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

echo "==> cloning ${REMOTE} (partial, blob-less) into $TMP"
git clone --filter=blob:none --no-checkout "$REMOTE" "$TMP/linux"

echo "==> fetching tag ${VERSION}"
git -C "$TMP/linux" fetch --depth 1 origin "tag" "${VERSION}"

echo "==> checking out ${VERSION}"
git -C "$TMP/linux" checkout --detach "${VERSION}"

mkdir -p "$KERNEL_BASE"
mv "$TMP/linux" "$DEST"
echo "==> kernel/${VERSION} ready ($(git -C "$DEST" describe --tags 2>/dev/null || echo "$VERSION"))"
echo "build with: make qemu-juno KERNEL_VERSION=${VERSION}"
