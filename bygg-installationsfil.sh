#!/usr/bin/env bash
# Bygger installationsfilen som organisationerna laddar ner från GitHub:
# dist/arkitekturportalen-<portal>.run, med drift-skripten och alla avbilder
# (portalen, plattformen, Arkitekten, postgres, redis, caddy). Den som installerar behöver
# alltså varken git eller inloggning mot avbildsregistret.
#
#   ./bygg-installationsfil.sh                    versionerna i .env.example
#   ./bygg-installationsfil.sh 0.3.0 0.2.0 0.2.0  portalen, plattformen och Arkitekten
#   ./bygg-installationsfil.sh … --publicera      och skapar releasen v<portal>
#                                                 på GitHub med filen bifogad
#
# För underhållarna, inte för installationen. Kräver docker (inloggad mot
# ghcr.io med read:packages) och för --publicera gh. Versionerna skrivs in i
# .env.example; checka in den ändringen innan du publicerar.
set -euo pipefail
cd "$(dirname "$0")"
# shellcheck source=lib/gemensamt.sh
. lib/gemensamt.sh

PUBLICERA=0
versioner=()
for arg in "$@"; do
    case "$arg" in
        --publicera) PUBLICERA=1 ;;
        -h|--help) sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        -*) fel "Okänt argument: $arg (se --help)" ;;
        *) versioner+=("${arg#v}") ;;
    esac
done
ENV_FILE=.env.example
PORTAL=${versioner[0]:-$(env_get PORTAL_VERSION)}
PLATTFORM=${versioner[1]:-$(env_get PLATFORM_VERSION)}
ARKITEKTEN=${versioner[2]:-$(env_get ARKITEKTEN_VERSION)}
[ -n "$ARKITEKTEN" ] || fel "Arkitektens version saknas (tredje argumentet eller ARKITEKTEN_VERSION i $ENV_FILE)."
REGISTRY=ghcr.io/arkitektursamverkan
kontrollera_docker

env_set PORTAL_VERSION "$PORTAL"
env_set PLATFORM_VERSION "$PLATTFORM"
env_set ARKITEKTEN_VERSION "$ARKITEKTEN"
if [ $PUBLICERA = 1 ]; then
    command -v gh >/dev/null || fel "gh saknas."
    [ -z "$(git status --porcelain)" ] || fel "Det finns ändringar som inte är incheckade (git status). Checka in dem först."
    git fetch -q origin
    [ "$(git rev-parse HEAD)" = "$(git rev-parse '@{u}')" ] || fel "Pusha först – releasen ska byggas från det som ligger på GitHub."
    ! gh release view "v$PORTAL" >/dev/null 2>&1 || fel "Releasen v$PORTAL finns redan."
fi

AVBILDER=(
    "$REGISTRY/arkitekturportalen-api:$PORTAL"
    "$REGISTRY/arkitekturportalen-web:$PORTAL"
    "$REGISTRY/integrationsplattformen-api:$PLATTFORM"
    "$REGISTRY/integrationsplattformen-web:$PLATTFORM"
    "$REGISTRY/arkitekten:$ARKITEKTEN"
)
# Övriga avbilder läses ur compose.yml, så att listan följer med när de byts.
while IFS= read -r a; do AVBILDER+=("$a"); done < <(grep -oE '^\s+image: [a-z0-9]+:[^$ ]+$' compose.yml | awk '{print $2}' | sort -u)

rubrik "Installationsfil: portalen $PORTAL, plattformen $PLATTFORM, Arkitekten $ARKITEKTEN"
for a in "${AVBILDER[@]}"; do
    info "Hämtar $a"
    docker pull --quiet "$a" >/dev/null || fel "$a gick inte att hämta."
done

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir "$tmp/filer"
# Bara filerna i git – aldrig en .env, certifikat eller backuper.
git ls-files -z | grep -zv '^\.github/' | xargs -0 cp --parents -t "$tmp/filer"
info "Packar avbilderna (tar några minuter)…"
docker save "${AVBILDER[@]}" | gzip -6 > "$tmp/avbilder.tar.gz"

mkdir -p dist
ut=dist/arkitekturportalen-$PORTAL.run
sed -e "s/@PORTAL@/$PORTAL/g" -e "s/@PLATTFORM@/$PLATTFORM/g" -e "s/@ARKITEKTEN@/$ARKITEKTEN/g" lib/installationsfil.sh > "$ut"
tar -c -C "$tmp" filer avbilder.tar.gz >> "$ut"
chmod +x "$ut"
info "Klar: $ut ($(du -h "$ut" | cut -f1))"

if [ $PUBLICERA = 1 ]; then
    anteckningar=$(cat <<EOF
Arkitekturportalen $PORTAL med Integrationsplattformen $PLATTFORM och Arkitekten $ARKITEKTEN.

## Installera eller uppgradera

1. Ladda ner **arkitekturportalen-$PORTAL.run** nedan och kopiera den till servern (Linux).
2. Kör den på servern:

       sudo sh arkitekturportalen-$PORTAL.run

Filen innehåller allt som behövs. Första gången ställer den några frågor och installerar portalen i /opt/arkitekturportalen. På en server där portalen redan finns uppgraderar den, med en backup först.

Nyheter: [portalen]($RELEASES_PORTAL/tag/v$PORTAL), [plattformen]($RELEASES_PLATTFORM/tag/v$PLATTFORM), [Arkitekten]($RELEASES_ARKITEKTEN/tag/v$ARKITEKTEN).
EOF
)
    gh release create "v$PORTAL" "$ut" --title "Arkitekturportalen $PORTAL" --notes "$anteckningar"
fi
