#!/bin/bash
# ============================================================================
# Shared helpers for the tracker client-registration scripts
# (register_anilist.sh, register_mal.sh). Source it; do not run it.
#
# Client ids live in ONE file outside the repo, $KARTKA_OAUTH_FILE
# (default ~/.config/kartka/oauth.json), which run.sh and the APK build pass
# to Flutter as --dart-define-from-file. Every writer jq-merges its own keys.
# Requires: jq, xclip, xdg-open, curl.
# ============================================================================

KARTKA_CONFIG_DIR="${KARTKA_CONFIG_DIR:-$HOME/.config/kartka}"
KARTKA_OAUTH_FILE="${KARTKA_OAUTH_FILE:-$KARTKA_CONFIG_DIR/oauth.json}"

die() {
    echo "error: $*" >&2
    exit 1
}

# Installs any missing tool via pacman (sudo -n: never prompts; on failure it
# tells kuhy the one command to run instead of hanging).
ensure_tools() {
    local tool pkg missing=()
    for tool in "$@"; do
        command -v "$tool" >/dev/null 2>&1 && continue
        case "$tool" in
            xdg-open) pkg=xdg-utils ;;
            *) pkg="$tool" ;;
        esac
        missing+=("$pkg")
    done
    [[ ${#missing[@]} -eq 0 ]] && return 0
    echo "installing: ${missing[*]}"
    sudo -n pacman -S --needed --noconfirm "${missing[@]}" ||
        die "run: sudo pacman -S --needed ${missing[*]}"
}

clip_put() {
    printf '%s' "$1" | xclip -selection clipboard -in
}

clip_get() {
    xclip -selection clipboard -out
}

# Puts $2 on the clipboard and waits until kuhy pressed Enter after pasting.
paste_step() {
    local what="$1" value="$2"
    clip_put "$value"
    read -r -p "  clipboard = ${what} (${value}). Paste it, then press Enter. " _
}

# Prints the value stored under key $1, or nothing.
config_get() {
    [[ -f "$KARTKA_OAUTH_FILE" ]] || return 0
    jq -r --arg k "$1" '.[$k] // empty' "$KARTKA_OAUTH_FILE"
}

# Merges key $1 = $2 into the config file atomically, mode 600.
config_set() {
    local key="$1" value="$2" tmp
    mkdir -p "$KARTKA_CONFIG_DIR"
    chmod 700 "$KARTKA_CONFIG_DIR"
    [[ -f "$KARTKA_OAUTH_FILE" ]] || printf '{}\n' >"$KARTKA_OAUTH_FILE"
    tmp="$(mktemp "$KARTKA_CONFIG_DIR/.oauth.XXXXXX")"
    jq --arg k "$key" --arg v "$value" '.[$k] = $v' "$KARTKA_OAUTH_FILE" >"$tmp"
    chmod 600 "$tmp"
    mv "$tmp" "$KARTKA_OAUTH_FILE"
}

# Fails unless the config file is private (mode 600).
config_check_mode() {
    local mode
    [[ -f "$KARTKA_OAUTH_FILE" ]] || die "missing $KARTKA_OAUTH_FILE"
    mode="$(stat -c '%a' "$KARTKA_OAUTH_FILE")"
    [[ "$mode" == "600" ]] || die "$KARTKA_OAUTH_FILE has mode $mode, want 600"
}
