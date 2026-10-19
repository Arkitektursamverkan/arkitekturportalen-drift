#!/usr/bin/env bash
# Uppgraderar till nya versioner: hämtar avbilderna, tar en backup, byter
# version i .env och startar om. Portalen migrerar databasen när den startar;
# går något fel återställs allt med ./aterstall.sh och backupen.
#
#   ./uppgradera.sh                       frågar efter versionerna
#   ./uppgradera.sh 0.2.0                 portalen till 0.2.0
#   ./uppgradera.sh 0.2.0 0.1.2           portalen och plattformen
#   ./uppgradera.sh --utan-pull …         avbilderna finns redan lokalt
#   ./uppgradera.sh --tvinga …            tillåt en äldre version (nedgradering)
set -euo pipefail
cd "$(dirname "$0")"
# shellcheck source=lib/gemensamt.sh
. lib/gemensamt.sh

PULL=1
TVINGA=0
versioner=()
for arg in "$@"; do
    case "$arg" in
        --utan-pull) PULL=0 ;;
        --tvinga) TVINGA=1 ;;
        -h|--help) sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        -*) fel "Okänt argument: $arg (se --help)" ;;
        *) versioner+=("${arg#v}") ;;
    esac
done
kontrollera_docker
[ -f "$ENV_FILE" ] || fel "Ingen .env – kör ./installera.sh först."

portal_nu=$(env_get PORTAL_VERSION)
plattform_nu=$(env_get PLATFORM_VERSION)
PLATTFORM=0; plattform_vald && PLATTFORM=1

rubrik "Uppgradering"
info "Nu: portalen $portal_nu$([ $PLATTFORM = 1 ] && echo ", plattformen $plattform_nu")"
info "Versioner: $RELEASES_PORTAL$([ $PLATTFORM = 1 ] && echo "  och  $RELEASES_PLATTFORM")"
if [ ${#versioner[@]} -gt 0 ]; then
    portal_ny=${versioner[0]}
    plattform_ny=${versioner[1]:-$plattform_nu}
else
    portal_ny=$(fraga "Portalens nya version" "$portal_nu"); portal_ny=${portal_ny#v}
    plattform_ny=$plattform_nu
    if [ $PLATTFORM = 1 ]; then plattform_ny=$(fraga "Plattformens nya version" "$plattform_nu"); plattform_ny=${plattform_ny#v}; fi
fi

semver='^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)?$'
[[ $portal_ny =~ $semver ]] || fel "Ogiltig version: $portal_ny (t.ex. 0.2.0)"
[[ $plattform_ny =~ $semver ]] || fel "Ogiltig version: $plattform_ny (t.ex. 0.1.2)"

if [ "$portal_ny" = "$portal_nu" ] && { [ $PLATTFORM = 0 ] || [ "$plattform_ny" = "$plattform_nu" ]; }; then
    info "Redan på de versionerna – inget att göra."
    exit 0
fi

# Databasmigreringar går bara framåt: en äldre version kräver en återställning.
aldre() { [ "$1" != "$2" ] && [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -n1)" = "$1" ]; }
if [ $TVINGA = 0 ]; then
    aldre "$portal_ny" "$portal_nu" && fel "$portal_ny är äldre än $portal_nu. Gå tillbaka med ./aterstall.sh och en backup från den versionen."
    aldre "$plattform_ny" "$plattform_nu" && fel "$plattform_ny är äldre än $plattform_nu. Gå tillbaka med ./aterstall.sh och en backup från den versionen."
fi

info "Till: portalen $portal_ny$([ $PLATTFORM = 1 ] && echo ", plattformen $plattform_ny")"
ja_nej "Fortsätta?" j || fel "Avbrutet."

# Hämta först: misslyckas det har inget ändrats.
if [ $PULL = 1 ]; then
    info "Hämtar avbilderna…"
    PORTAL_VERSION=$portal_ny PLATFORM_VERSION=$plattform_ny dc pull --quiet \
        || fel "Avbilderna gick inte att hämta – finns versionen, och är du inloggad (docker login ghcr.io)? Inget är ändrat."
fi

# Backupens namn har versionerna det uppgraderas till, t.ex. fore-0.2.0 eller
# fore-0.2.0_0.1.2 med plattformen.
backup=$(./backup.sh "fore-$portal_ny$([ $PLATTFORM = 1 ] && echo "_$plattform_ny")")

env_set PORTAL_VERSION "$portal_ny"
env_set PLATFORM_VERSION "$plattform_ny"
info "Startar de nya versionerna (portalen migrerar databasen)…"
misslyckat() {
    info ""
    info "Uppgraderingen gick inte igenom: $1"
    info "Gå tillbaka till läget före med:"
    info "  ./aterstall.sh $backup"
    exit 1
}
dc up -d --remove-orphans >/dev/null 2>&1 || misslyckat "docker compose up misslyckades."
vanta_pa api http://localhost:8000/api/v1/health || misslyckat "portalen svarar inte."
[ "$(rapporterad_version api)" = "$portal_ny" ] || misslyckat "portalen rapporterar $(rapporterad_version api), inte $portal_ny."
if [ $PLATTFORM = 1 ]; then
    vanta_pa plattform-api http://localhost:8000/api/v1/health || misslyckat "plattformen svarar inte."
    [ "$(rapporterad_version plattform-api)" = "$plattform_ny" ] || misslyckat "plattformen rapporterar $(rapporterad_version plattform-api), inte $plattform_ny."
fi

rubrik "Klart"
info "Portalen kör $portal_ny$([ $PLATTFORM = 1 ] && echo ", plattformen $plattform_ny")."
info "Backupen från före uppgraderingen: $backup"
