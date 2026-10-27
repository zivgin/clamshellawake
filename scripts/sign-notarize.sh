#!/bin/bash
# Shared macOS signing and notarization helper (same file in gumi-glucose,
# SnapMark, Afterlid, Panes and MDPad; keep the copies identical).
#
# With a "Developer ID Application" identity in the keychain it signs for
# distribution: hardened runtime, secure timestamp, inside-out (no --deep),
# per-bundle entitlements, then notarizes (notarytool, keychain profile),
# staples and checks Gatekeeper. Without one it falls back to the caller's
# current identity (a self-signed cert name or "-" for ad hoc) and skips
# notarization, so builds keep working before the paid cert exists.
#
# Nothing here is a secret. Configuration comes from the environment or from
# ${APPLE_SIGNING_CONFIG:-~/.config/apple-signing/config.env} (shell syntax):
#   APPLE_TEAM_ID       paid team id; picks the Developer ID of that team
#   SIGN_IDENTITY       explicit identity (name or SHA-1); overrides the search
#   NOTARY_PROFILE      notarytool keychain profile (default: gumi-notary)
#   NOTARIZE            auto (default) | 0 (never) | required (fail if it cannot)
#
# Commands:
#   identity [fallback]             print the identity that would be used
#   mode [fallback]                 print "developer-id" or "fallback"
#   build-number                    git commit count of the current repo
#   stamp <App.app> [short-version] set CFBundleVersion (and optionally the short version)
#   sign <path> [opts]              sign one item (file or bundle), no recursion
#   sign-app <App.app> [opts]       sign nested code deepest first, then the app
#   notarize <App.app>              submit, wait, staple, assess (devid only)
#   verify <App.app>                codesign --verify --strict, and spctl when devid
# Options for sign / sign-app:
#   --fallback <identity>           identity when no Developer ID (default "-")
#   --entitlements <plist>          entitlements for the item (sign-app: the main app)
#   --nested-entitlements <rel>=<plist>   sign-app: entitlements for a nested item
#   --identifier <id>               sign: explicit code identifier
#   --runtime                       hardened runtime in fallback mode too
set -euo pipefail

CONFIG="${APPLE_SIGNING_CONFIG:-$HOME/.config/apple-signing/config.env}"
# shellcheck disable=SC1090
[ -f "$CONFIG" ] && . "$CONFIG"
NOTARY_PROFILE="${NOTARY_PROFILE:-gumi-notary}"
NOTARIZE="${NOTARIZE:-auto}"

log() { echo "[sign] $*" >&2; }
die() { echo "[sign] ERROR: $*" >&2; exit 1; }

# The Developer ID Application identity (SHA-1), or empty.
devid_identity() {
    if [ -n "${SIGN_IDENTITY:-}" ]; then
        case "$SIGN_IDENTITY" in *"Developer ID Application"*) echo "$SIGN_IDENTITY"; return ;; esac
        # A SHA-1 or a name: devid only if it resolves to a Developer ID cert.
        security find-identity -v -p codesigning 2>/dev/null \
            | grep -F "$SIGN_IDENTITY" | grep -q "Developer ID Application" && echo "$SIGN_IDENTITY"
        return 0
    fi
    local pat="\"Developer ID Application: .*\""
    [ -n "${APPLE_TEAM_ID:-}" ] && pat="\"Developer ID Application: .*\\(${APPLE_TEAM_ID}\\)\""
    security find-identity -v -p codesigning 2>/dev/null | grep -E "$pat" | awk '{print $2; exit}' || true
}

DEVID="$(devid_identity || true)"
is_devid() { [ -n "$DEVID" ]; }

resolve_identity() {  # $1 = fallback
    if is_devid; then echo "$DEVID"
    elif [ -n "${SIGN_IDENTITY:-}" ]; then echo "$SIGN_IDENTITY"
    else echo "${1:--}"; fi
}

build_number() {
    git rev-list --count HEAD 2>/dev/null || echo 1
}

stamp() {
    local app="$1" short="${2:-}" n
    n="$(build_number)"
    plutil -replace CFBundleVersion -string "$n" "$app/Contents/Info.plist"
    [ -n "$short" ] && plutil -replace CFBundleShortVersionString -string "$short" "$app/Contents/Info.plist"
    log "$(basename "$app"): CFBundleVersion $n${short:+, version $short}"
}

# codesign one item. Args: path identity entitlements identifier runtime(0/1)
codesign_one() {
    local path="$1" ident="$2" ent="$3" id="$4" runtime="$5"
    local args=(--force --sign "$ident")
    if is_devid; then
        args+=(--options runtime --timestamp)
    elif [ "$runtime" = 1 ]; then
        args+=(--options runtime)
    fi
    [ -n "$ent" ] && args+=(--entitlements "$ent")
    [ -n "$id" ] && args+=(--identifier "$id")
    codesign "${args[@]}" "$path"
}

is_macho() { file -b "$1" 2>/dev/null | grep -q "Mach-O"; }

# Main executable of a bundle dir, if any.
bundle_exec() {
    local b="$1" e
    e=$(plutil -extract CFBundleExecutable raw "$b/Contents/Info.plist" 2>/dev/null || true)
    [ -n "$e" ] && echo "$b/Contents/MacOS/$e"
    return 0
}

cmd_sign() {
    local path="$1"; shift
    local fallback="-" ent="" id="" runtime=0
    while [ $# -gt 0 ]; do
        case "$1" in
            --fallback) fallback="$2"; shift 2 ;;
            --entitlements) ent="$2"; shift 2 ;;
            --identifier) id="$2"; shift 2 ;;
            --runtime) runtime=1; shift ;;
            *) die "sign: unknown option $1" ;;
        esac
    done
    codesign_one "$path" "$(resolve_identity "$fallback")" "$ent" "$id" "$runtime"
}

cmd_sign_app() {
    local app="${1%/}"; shift
    local fallback="-" ent="" runtime=0 nested=()
    while [ $# -gt 0 ]; do
        case "$1" in
            --fallback) fallback="$2"; shift 2 ;;
            --entitlements) ent="$2"; shift 2 ;;
            --nested-entitlements) nested+=("$2"); shift 2 ;;
            --runtime) runtime=1; shift ;;
            *) die "sign-app: unknown option $1" ;;
        esac
    done
    [ -d "$app/Contents" ] || die "not an app bundle: $app"
    local ident; ident="$(resolve_identity "$fallback")"
    log "$(basename "$app"): signing with $(is_devid && echo "Developer ID" || echo "fallback '$ident'")"

    # Nested bundles and loose Mach-O files, deepest path first. A bundle's own
    # main executable is sealed by signing the bundle, so it is skipped.
    local items=() mains=() p
    while IFS= read -r p; do
        # Code bundles only; a flat resource bundle (SwiftPM) is sealed as a resource.
        local m; m="$(bundle_exec "$p")"
        if [ -n "$m" ] && [ -f "$m" ]; then items+=("$p"); mains+=("$m")
        elif [ "${p##*.}" = framework ]; then items+=("$p"); fi
    done < <(find "$app/Contents" -mindepth 1 -type d \( -name '*.app' -o -name '*.framework' -o -name '*.xpc' -o -name '*.appex' -o -name '*.bundle' -o -name '*.systemextension' \) 2>/dev/null)
    while IFS= read -r p; do
        [ "$p" = "$(bundle_exec "$app")" ] && continue
        local skip=0 m
        for m in "${mains[@]+"${mains[@]}"}"; do [ "$p" = "$m" ] && skip=1; done
        [ "$skip" = 0 ] && is_macho "$p" && items+=("$p")
    done < <(find "$app/Contents" -type f -perm -u+x 2>/dev/null; find "$app/Contents" -type f \( -name '*.dylib' -o -name '*.so' \) 2>/dev/null)

    local sorted=()
    if [ ${#items[@]} -gt 0 ]; then
        while IFS= read -r p; do sorted+=("$p"); done < <(
            printf '%s\n' "${items[@]}" | sort -u | awk -F/ '{print NF "\t" $0}' | sort -rn | cut -f2-)
    fi
    for p in "${sorted[@]+"${sorted[@]}"}"; do
        local rel="${p#"$app"/}" e="" kv
        for kv in "${nested[@]+"${nested[@]}"}"; do [ "${kv%%=*}" = "$rel" ] && e="${kv#*=}"; done
        codesign_one "$p" "$ident" "$e" "" "$runtime"
    done
    codesign_one "$app" "$ident" "$ent" "" "$runtime"
    codesign --verify --strict "$app"
}

profile_ok() { xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; }

cmd_notarize() {
    local app="${1%/}"
    if [ "$NOTARIZE" = 0 ]; then log "notarization off (NOTARIZE=0)"; return 0; fi
    if ! is_devid; then
        [ "$NOTARIZE" = required ] && die "NOTARIZE=required but no Developer ID Application identity"
        log "no Developer ID identity: skipping notarization"; return 0
    fi
    if ! profile_ok; then
        [ "$NOTARIZE" = required ] && die "notary profile '$NOTARY_PROFILE' missing or not working"
        log "notary profile '$NOTARY_PROFILE' not usable: skipping notarization (run xcrun notarytool store-credentials)"
        return 0
    fi
    local tmp; tmp="$(mktemp -d -t notarize)"
    local zip="$tmp/$(basename "$app" .app).zip"
    ditto -c -k --keepParent "$app" "$zip"
    log "submitting $(basename "$app") to the notary service (waits)"
    local out status id
    out="$(xcrun notarytool submit "$zip" --keychain-profile "$NOTARY_PROFILE" --wait --output-format json)" || true
    status="$(echo "$out" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("status",""))' 2>/dev/null || true)"
    id="$(echo "$out" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("id",""))' 2>/dev/null || true)"
    rm -rf "$tmp"
    if [ "$status" != "Accepted" ]; then
        [ -n "$id" ] && xcrun notarytool log "$id" --keychain-profile "$NOTARY_PROFILE" >&2 || true
        die "notarization ${status:-failed} for $(basename "$app")"
    fi
    xcrun stapler staple "$app"
    xcrun stapler validate "$app"
    spctl -a -vv -t exec "$app"
    log "$(basename "$app"): notarized and stapled"
}

cmd_verify() {
    local app="${1%/}"
    codesign --verify --strict --verbose=2 "$app"
    if is_devid; then spctl -a -vv -t exec "$app" || log "spctl: not accepted yet (notarize first)"; fi
}

[ $# -ge 1 ] || { sed -n '2,38p' "$0"; exit 2; }
cmd="$1"; shift
case "$cmd" in
    identity) resolve_identity "${1:--}" ;;
    mode) is_devid && echo developer-id || echo fallback ;;
    build-number) build_number ;;
    stamp) stamp "$@" ;;
    sign) cmd_sign "$@" ;;
    sign-app) cmd_sign_app "$@" ;;
    notarize) cmd_notarize "$@" ;;
    verify) cmd_verify "$@" ;;
    *) die "unknown command $cmd" ;;
esac
