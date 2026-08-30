#!/bin/sh
# SPDX-License-Identifier: AGPL-3.0-only
set -eu

repository="letsinferlabs/letsinfer"
temporary=""

# Removes the exact private bootstrap directory created by this process.
cleanup() {
    if [ -n "$temporary" ] && [ -d "$temporary" ]; then
        rm -rf "$temporary"
    fi
}

# Stops the bootstrap with one consistent user-facing failure.
fail() {
    printf 'letsinfer: %s\n' "$1" >&2
    exit 1
}

# Downloads one exact HTTPS resource into a private regular file.
download() {
    source_url=$1
    output_path=$2

    curl --fail --location --silent --show-error \
        --proto '=https' --tlsv1.2 \
        --output "$output_path" "$source_url" \
        || fail "download failed: $source_url"
}

# Resolves the newest public release, including release candidates, from bounded metadata.
latest_release_version() {
    metadata=$1
    metadata_bytes=$(wc -c < "$metadata" | tr -d '[:space:]')
    [ "$metadata_bytes" -gt 0 ] && [ "$metadata_bytes" -le 1048576 ] \
        || fail "latest release metadata is invalid"

    tag=$(sed -n \
        's/.*"tag_name":[[:space:]]*"\([^"]*\)".*/\1/p' \
        "$metadata" | sed -n '1p')
    if ! printf '%s\n' "$tag" \
        | grep -Eq '^v[0-9]+\.[0-9]+\.[0-9]+(-rc\.[0-9]+)?$'; then
        fail "latest release metadata is invalid"
    fi

    printf '%s\n' "${tag#v}"
}

# Resolves and hands control to the exact installer from the newest public release.
main() {
    command -v curl >/dev/null 2>&1 || fail "curl is required"
    command -v mktemp >/dev/null 2>&1 || fail "mktemp is required"

    temporary=$(mktemp -d "${TMPDIR:-/tmp}/letsinfer-bootstrap.XXXXXX") \
        || fail "cannot create temporary bootstrap directory"
    metadata="$temporary/releases.json"
    installer="$temporary/install.sh"

    download \
        "https://api.github.com/repos/$repository/releases?per_page=1" \
        "$metadata"
    version=$(latest_release_version "$metadata")
    download \
        "https://github.com/$repository/releases/download/v$version/install.sh" \
        "$installer"

    [ -s "$installer" ] || fail "release installer is empty"
    [ "$(sed -n '1p' "$installer")" = "#!/bin/sh" ] \
        || fail "release installer is invalid"

    /bin/sh "$installer" --version "$version" "$@"
}

trap cleanup 0
trap 'exit 1' HUP INT TERM
main "$@"
