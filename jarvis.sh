#!/usr/bin/env bash
# Amorce de Jarvis partout (demande du 22 octobre) — la SEULE partie publique, sans aucun secret.
#
#   curl -fsSL <adresse publique de ce fichier> | bash
#
# Ce script ne contient ni clé ni donnée : il installe GitHub CLI (gh) si besoin (binaire officiel, empreinte
# vérifiée, sans sudo, dans ~/.local), vous connecte à VOTRE compte GitHub (une seule fois, par le navigateur ou
# un code à saisir sur github.com/login/device), clone le dépôt PRIVÉ de Jarvis, puis passe la main à son
# installeur (partout.sh), qui demandera votre phrase. Sans votre compte GitHub et votre phrase, il ne fait rien.
set -euo pipefail

main() {
  local depot="${JARVIS_DEPOT:-BRILLANT12/jarvis}" dest="${JARVIS_DIR:-$HOME/jarvis}" branche="${JARVIS_BRANCHE:-main}"
  local outils="$HOME/.local/share/jarvis/outils" bin="$HOME/.local/bin"
  [ -t 0 ] || exec </dev/tty                    # « curl … | bash » : les questions vont au terminal
  export PATH="$bin:$PATH:/opt/homebrew/bin:/usr/local/bin"
  echo "Jarvis partout — amorce ($(uname -s) $(uname -m))"

  if ! command -v git >/dev/null || ! command -v curl >/dev/null; then
    echo "✗ git et curl sont nécessaires :"
    if [ "$(uname -s)" = Darwin ]; then echo "    xcode-select --install"
    elif command -v apt-get >/dev/null; then echo "    sudo apt-get install -y git curl"
    elif command -v dnf >/dev/null; then echo "    sudo dnf install -y git curl"
    else echo "    installez git et curl avec le gestionnaire de paquets du système"; fi
    echo "  puis relancez cette commande."
    exit 1
  fi

  if [ -n "${JARVIS_SOURCE:-}" ]; then          # tests et recette : dépôt local, ni GitHub ni gh
    src="$JARVIS_SOURCE"
  else
    if ! command -v gh >/dev/null; then
      echo "→ GitHub CLI (gh), binaire officiel dans $outils (sans sudo)"
      local os arch v nom tmp
      case "$(uname -s)" in Darwin) os=macOS ;; Linux) os=linux ;; *) echo "✗ système non pris en charge"; exit 1 ;; esac
      case "$(uname -m)" in x86_64|amd64) arch=amd64 ;; arm64|aarch64) arch=arm64 ;; armv7l|armv6l) arch=armv6 ;;
        i?86) arch=386 ;; *) echo "✗ processeur non pris en charge : $(uname -m)"; exit 1 ;; esac
      v="$(curl -fsSL https://api.github.com/repos/cli/cli/releases/latest | sed -n 's/.*"tag_name": *"v\([^"]*\)".*/\1/p' | head -1)"
      [ -n "$v" ] || { echo "✗ version de gh introuvable (réseau ?)"; exit 1; }
      if [ "$os" = macOS ]; then nom="gh_${v}_${os}_${arch}.zip"; else nom="gh_${v}_${os}_${arch}.tar.gz"; fi
      tmp="$(mktemp -d)"
      curl -fsSL -o "$tmp/$nom" "https://github.com/cli/cli/releases/download/v$v/$nom"
      curl -fsSL -o "$tmp/sommes.txt" "https://github.com/cli/cli/releases/download/v$v/gh_${v}_checksums.txt"
      local attendu vu
      attendu="$(awk -v n="$nom" '$2 == n {print $1}' "$tmp/sommes.txt")"
      vu="$( (command -v sha256sum >/dev/null && sha256sum "$tmp/$nom" || shasum -a 256 "$tmp/$nom") | awk '{print $1}')"
      [ -n "$attendu" ] && [ "$attendu" = "$vu" ] || { echo "✗ empreinte de gh incorrecte : rien n'est installé"; rm -rf "$tmp"; exit 1; }
      mkdir -p "$outils" "$bin"
      if [ "$os" = macOS ]; then (cd "$tmp" && unzip -q "$nom"); else tar -xzf "$tmp/$nom" -C "$tmp"; fi
      rm -rf "$outils/gh" && mv "$tmp/${nom%.tar.gz}" "$outils/gh" 2>/dev/null || mv "$tmp/${nom%.zip}" "$outils/gh"
      ln -sf "$outils/gh/bin/gh" "$bin/gh"
      rm -rf "$tmp"
      echo "  ✓ gh $v (empreinte sha256 vérifiée)"
    fi
    if ! gh auth status --hostname github.com >/dev/null 2>&1; then
      echo "→ Connexion à VOTRE compte GitHub (une seule fois sur cette machine)"
      gh auth login --hostname github.com --git-protocol https --web
    fi
    gh auth setup-git --hostname github.com          # git utilise la connexion de gh (dépôts privés)
    echo "  ✓ connecté à GitHub ($(gh api user -q .login 2>/dev/null || echo '?'))"
    src="https://github.com/$depot.git"
  fi

  if [ -d "$dest/.git" ]; then
    echo "→ Dépôt déjà là ($dest) : mise à jour"
    git -C "$dest" fetch -q origin "$branche"
    if [ "$(git -C "$dest" rev-parse --abbrev-ref HEAD)" = "$branche" ] && [ -z "$(git -C "$dest" status --porcelain --untracked-files=no)" ]; then
      git -C "$dest" merge -q --ff-only "origin/$branche" || echo "  (mise à jour impossible en avance rapide : dépôt laissé tel quel)"
    else
      echo "  (autre branche ou modifications locales : dépôt laissé tel quel)"
    fi
  elif [ -e "$dest" ]; then
    echo "✗ $dest existe et n'est pas le dépôt de Jarvis : rien n'est touché (JARVIS_DIR=… pour un autre dossier)"
    exit 1
  else
    echo "→ Clone du dépôt privé dans $dest"
    git clone -q --branch "$branche" "$src" "$dest"
  fi
  exec bash "$dest/partout.sh"
}

main "$@"
