#!/bin/bash
# Register Kartka's two MyAnimeList API apps (android + web) and store their
# client ids in ~/.config/kartka/oauth.json (never in the repo).
#
# MAL app registration has no API, so this script does everything around the
# form: it opens the create page, puts each text field on the clipboard in
# form order (one Enter apart), reads the issued Client ID back from the
# clipboard, merges it into oauth.json (mode 600, other keys kept) and
# verifies it against the live API. Rerun with --verify-only to check only.
#
# Two apps, not one: MAL matches the redirect URL exactly, and a second
# redirect URL on one app has been reported to break with invalid_client.
#
# Usage: tools/tracking/register_mal.sh [--verify-only] [--only android|web]
set -euo pipefail

readonly CREATE_URL='https://myanimelist.net/apiconfig/create'
readonly VERIFY_URL='https://api.myanimelist.net/v2/manga?q=berserk&limit=1'
readonly CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/kartka"
readonly CONFIG_FILE="${CONFIG_DIR}/oauth.json"
readonly HOMEPAGE='https://github.com/kuhyx/kartka'
# Redirects fixed by contracts §7/§13 (wrapper binds 127.0.0.1:8791).
readonly ANDROID_REDIRECT='kartka://oauth'
readonly WEB_REDIRECT='http://127.0.0.1:8791/oauth'

verify_only=false
only=''
tmp_file=''

cleanup() {
  if [[ -n $tmp_file ]]; then rm -f "$tmp_file"; fi
}
trap cleanup EXIT

usage() {
  sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'
}

die() {
  printf 'register_mal: %s\n' "$*" >&2
  exit 1
}

parse_args() {
  while (($#)); do
    case "$1" in
      --verify-only) verify_only=true ;;
      --only)
        [[ ${2:-} == android || ${2:-} == web ]] || die '--only takes android or web'
        only="$2"
        shift
        ;;
      -h | --help)
        usage
        exit 0
        ;;
      *) die "unknown argument: $1 (see --help)" ;;
    esac
    shift
  done
}

# Installs whatever is missing (pacman; sudo may prompt once).
ensure_tools() {
  local -a missing=()
  local tool
  for tool in jq curl xclip xdg-open; do
    command -v "$tool" >/dev/null 2>&1 || missing+=("$tool")
  done
  ((${#missing[@]} == 0)) && return 0
  local -a pkgs=()
  for tool in "${missing[@]}"; do
    case "$tool" in
      xdg-open) pkgs+=(xdg-utils) ;;
      *) pkgs+=("$tool") ;;
    esac
  done
  printf 'Installing: %s\n' "${pkgs[*]}"
  sudo pacman -S --needed --noconfirm "${pkgs[@]}"
}

wait_enter() {
  local _
  read -r -p "    $1 [Enter] " _
}

# Puts one text field on the clipboard; kuhy pastes it into the labelled box.
paste_field() {
  local label="$1" value="$2"
  printf '%s' "$value" | xclip -selection clipboard
  printf '  [clipboard] %-24s %s\n' "$label" "$value"
  wait_enter 'paste into that field'
}

# A select box or checkbox: nothing to paste, only what to choose.
choose_field() {
  printf '  [choose]    %-24s -> %s\n' "$1" "$2"
  wait_enter 'set it'
}

client_key() {
  printf 'KARTKA_MAL_CLIENT_ID_%s' "${1^^}"
}

redirect_for() {
  if [[ $1 == android ]]; then
    printf '%s' "$ANDROID_REDIRECT"
  else
    printf '%s' "$WEB_REDIRECT"
  fi
}

# Merges KEY=VALUE into oauth.json, keeping every other key (AniList's too).
save_client_id() {
  local key="$1" value="$2"
  mkdir -p "$CONFIG_DIR"
  chmod 700 "$CONFIG_DIR"
  tmp_file="$(mktemp "${CONFIG_DIR}/.oauth.json.XXXXXX")"
  if [[ -s $CONFIG_FILE ]]; then
    jq --arg k "$key" --arg v "$value" '.[$k] = $v' "$CONFIG_FILE" >"$tmp_file"
  else
    jq -n --arg k "$key" --arg v "$value" '{($k): $v}' >"$tmp_file"
  fi
  chmod 600 "$tmp_file"
  mv "$tmp_file" "$CONFIG_FILE"
  tmp_file=''
  printf '  saved %s to %s\n' "$key" "$CONFIG_FILE"
}

register_app() {
  local platform="$1" redirect owner id
  redirect="$(redirect_for "$platform")"
  owner="$(git config user.name || true)"
  [[ -n $owner ]] || owner="$USER"

  printf '\n== MAL app for Kartka %s (redirect %s)\n' "$platform" "$redirect"
  printf '   App Type must be "other": a public client with NO secret.\n'
  printf '   "web" issues a secret the app cannot keep, and MAL never lets you\n'
  printf '   change the type afterwards. Match fields by LABEL, not position.\n'
  xdg-open "$CREATE_URL" >/dev/null 2>&1 &
  wait_enter "log in if asked; the Create ID form is open"

  paste_field 'App Name' "Kartka ${platform}"
  choose_field 'App Type' 'other'
  paste_field 'App Description' \
    "Kartka, a personal manga reader (${platform} build): syncs chapter progress to the user's MAL manga list."
  paste_field 'App Redirect URL' "$redirect"
  paste_field 'Homepage URL' "$HOMEPAGE"
  choose_field 'Commercial / Non-Commercial' 'non-commercial'
  paste_field 'Name / Company Name' "$owner"
  choose_field 'Purpose of Use' 'hobbyist'
  choose_field 'API License + Developer Agreement' 'tick it, then press Submit'

  printf '  Open the new app (myanimelist.net/apiconfig) and copy its Client ID.\n'
  wait_enter 'Client ID is on the clipboard'
  id="$(xclip -o -selection clipboard | tr -d '[:space:]')"
  [[ $id =~ ^[A-Za-z0-9]{16,64}$ ]] ||
    die "clipboard does not look like a client id: '${id:0:20}...' (rerun with --only ${platform})"
  save_client_id "$(client_key "$platform")" "$id"
}

# 200 from a client-id-only call proves MAL accepts the id.
verify_client_id() {
  local platform="$1" key id status
  key="$(client_key "$platform")"
  [[ -s $CONFIG_FILE ]] || die "$CONFIG_FILE missing; run without --verify-only"
  id="$(jq -r --arg k "$key" '.[$k] // empty' "$CONFIG_FILE")"
  [[ -n $id ]] || die "$key not in $CONFIG_FILE; run with --only ${platform}"
  status="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 20 \
    -H "X-MAL-CLIENT-ID: ${id}" "$VERIFY_URL")"
  if [[ $status != 200 ]]; then
    printf 'FAIL %s: MAL answered HTTP %s for %s\n' "$platform" "$status" "$key" >&2
    return 1
  fi
  printf 'OK   %s: MAL accepts %s\n' "$platform" "$key"
}

main() {
  parse_args "$@"
  ensure_tools
  local -a platforms=(android web)
  [[ -n $only ]] && platforms=("$only")
  local platform failed=0
  if ! $verify_only; then
    for platform in "${platforms[@]}"; do
      register_app "$platform"
    done
  fi
  printf '\n== verify\n'
  for platform in "${platforms[@]}"; do
    verify_client_id "$platform" || failed=1
  done
  [[ $(stat -c %a "$CONFIG_FILE") == 600 ]] || die "$CONFIG_FILE is not mode 600"
  ((failed == 0)) || exit 1
  printf 'Both ids are passed to builds by run.sh via --dart-define-from-file.\n'
}

main "$@"
