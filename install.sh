#!/usr/bin/env bash
# Installe Lucraft Launcher sur ce Mac depuis les versions publiées, sans rien compiler. À coller
# dans le Terminal :
#
#   curl -fsSL https://raw.githubusercontent.com/axsomette/lucraft-releases/main/install.sh | bash
#
# Le launcher installe ensuite les apps d'un clic et se met à jour tout seul. Téléchargé par curl
# (et non par un navigateur), il s'ouvre sans l'avertissement « développeur non identifié ».
# LUCRAFT_FEED : un autre catalogue (celui d'une édition, Kaneva par exemple) ; LUCRAFT_AUTH :
# l'en-tête d'une source privée (« Authorization: Basic … ») ; LUCRAFT_LAUNCHER_NAME : le nom du launcher
# de l'édition. lucraft-release.sh --edition les écrit dans l'installeur qu'il publie.
set -euo pipefail

# Tout est dans une fonction : bash lit le script en entier avant d'en lancer la moindre ligne
# (avec « curl | bash », une commande qui lit l'entrée ne peut pas en avaler la suite).
main() {
  FEED="${LUCRAFT_FEED:-https://github.com/axsomette/lucraft-releases/releases/latest/download/release_info.json}"
  NAME="${LUCRAFT_LAUNCHER_NAME:-Lucraft Launcher}"
  AUTH="${LUCRAFT_AUTH:-}"
  get() { if [ -n "$AUTH" ]; then curl -H "$AUTH" "$@"; else curl "$@"; fi; }

  ok() { printf '  \033[32m✓\033[0m %s\n' "$*"; }
  fail() { printf '\n\033[31m✗ %s\033[0m\n\n' "$*" >&2; exit 1; }

  printf '\033[1m%s — installation\033[0m\n' "${NAME% Launcher}"
  [ "$(uname -s)" = Darwin ] || fail "Lucraft s'installe sur un Mac (macOS)."
  major="$(sw_vers -productVersion | cut -d. -f1)"
  [ "$major" -ge 13 ] 2>/dev/null || fail "Il faut macOS 13 (Ventura) ou plus récent. Ce Mac a macOS $(sw_vers -productVersion)."
  case "$(uname -m)" in arm64) ARCH=aarch64 ;; *) ARCH=x86_64 ;; esac

  work="$(mktemp -d)"
  mount="$work/mount"
  trap 'hdiutil detach -quiet "$mount" 2>/dev/null || true; rm -rf "$work"' EXIT

  get -fsSL --retry 3 -o "$work/feed.json" "$FEED" || fail "Le catalogue Lucraft ne répond pas. Vérifiez la connexion Internet, puis réessayez."
  # Le DMG du launcher pour ce Mac (universel, sinon son processeur) : adresse, taille, empreinte.
  # JavaScript d'Apple (osascript) : présent sur tous les Mac, sans rien installer.
  # (Écrit dans un fichier d'abord : le bash 3.2 de macOS lit mal un heredoc dans « $( ) ».)
  cat >"$work/pick.js" <<'JS'
ObjC.import("Foundation");
function run(argv) {
  const text = $.NSString.stringWithContentsOfFileEncodingError(argv[0], $.NSUTF8StringEncoding, null).js;
  const app = (JSON.parse(text).release_info.apps || {})["lucraft-launcher"];
  const assets = (app && app.latest_release && app.latest_release.assets) || [];
  for (const token of ["macos-universal", "macos-" + argv[1]]) {
    const a = assets.find(a => a.name.endsWith("-" + token + ".dmg"));
    if (a) return [a.download_url, a.sha256, a.name].join(" ");
  }
  return "";
}
JS
  asset="$(osascript -l JavaScript "$work/pick.js" "$work/feed.json" "$ARCH")"
  [ -n "$asset" ] || fail "Le catalogue ne propose pas Lucraft Launcher pour ce Mac ($ARCH)."
  read -r url sha file <<<"$asset"
  ok "$file"

  echo "  Téléchargement…"
  get -fL --retry 3 --progress-bar -o "$work/$file" "$url" || fail "Le téléchargement a échoué. Réessayez."
  [ "$(shasum -a 256 "$work/$file" | cut -d' ' -f1)" = "$sha" ] || fail "Le fichier téléchargé n'est pas celui publié : rien n'est installé. Réessayez."
  ok "téléchargé et vérifié"

  mkdir -p "$mount"
  hdiutil attach -quiet -nobrowse -readonly -mountpoint "$mount" "$work/$file" || fail "Le DMG ne s'ouvre pas."
  dest=/Applications
  [ -w "$dest" ] || { dest="$HOME/Applications"; mkdir -p "$dest"; }
  pkill -f "$NAME.app/Contents/MacOS/" 2>/dev/null || true
  rm -rf "${dest:?}/$NAME.app"
  ditto --norsrc --noextattr --noacl "$mount/$NAME.app" "$dest/$NAME.app"
  codesign --verify --deep --strict "$dest/$NAME.app" || fail "La signature de $NAME n'est pas intacte : il n'a pas été ouvert."
  ok "$NAME est dans $dest"

  open "$dest/$NAME.app"
  printf '\n\033[1m🎉 %s est installé.\033[0m Cliquez « Installer » sur les apps que vous voulez.\n\n' "$NAME"
}

main "$@"
