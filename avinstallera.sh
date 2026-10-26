#!/bin/sh
# Avinstallerar Arkitekturportalen från servern: tjänsterna, all data i
# Docker (databaserna, portalens filer, Arkitektens innehåll, certifikaten),
# programmet (avbilderna), cron-raderna för backup och installationskatalogen.
#
#   sudo sh arkitekturportalen-avinstallation.run      filen från Releases
#   sudo /opt/arkitekturportalen/avinstallera.sh        samma skript, i installationen
#
# Inget tas bort förrän du har svarat på frågorna och skrivit "avinstallera".
# Först erbjuds en sista backup, och backuperna kan sparas utanför
# installationen så att den går att återskapa (installera, sedan aterstall.sh).
# Docker självt lämnas kvar.
#
# ARKITEKTURPORTALEN_KATALOG=/annan/katalog om portalen inte ligger i
# /opt/arkitekturportalen.
set -eu

rubrik() { printf '\n\033[1m── %s\033[0m\n' "$1" >&2; }
info() { printf '%s\n' "$*" >&2; }
fel() { printf '\033[31mFel:\033[0m %s\n' "$*" >&2; exit 1; }
# fraga "Fråga" [förslag] → svaret (förslaget om svaret är tomt)
fraga() {
    if [ -n "${2:-}" ]; then printf '%s [%s]: ' "$1" "$2" >&2; else printf '%s: ' "$1" >&2; fi
    IFS= read -r svar || svar=""
    printf '%s' "${svar:-${2:-}}"
}
# ja_nej "Fråga" j|n → status 0 för ja
ja_nej() {
    while :; do
        if [ "$2" = j ]; then svar=$(fraga "$1 (J/n)"); else svar=$(fraga "$1 (j/N)"); fi
        case "${svar:-$2}" in
            j|J|ja|Ja|y|Y|yes) return 0 ;;
            n|N|nej|Nej|no) return 1 ;;
        esac
        info "  Svara j eller n."
    done
}
env_varde() { [ -f "$KATALOG/.env" ] && sed -n "s/^$1=//p" "$KATALOG/.env" | tail -n1 | tr -d "'" || true; }

case "${1:-}" in -h|--help) sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;; esac

rubrik "Arkitekturportalen – avinstallation"
[ "$(uname -s)" = Linux ] || fel "Den här filen är för Linux-servrar."

# ── Var finns installationen? ─────────────────────────────────────────────────

# Skriptet i installationskatalogen avinstallerar den katalogen; filen från
# Releases letar i standardkatalogen.
har_skriptet=$(cd "$(dirname "$0")" && pwd)
if [ -n "${ARKITEKTURPORTALEN_KATALOG:-}" ]; then KATALOG=$ARKITEKTURPORTALEN_KATALOG
elif [ -f "$har_skriptet/compose.yml" ] && [ -f "$har_skriptet/lib/gemensamt.sh" ]; then KATALOG=$har_skriptet
else KATALOG=/opt/arkitekturportalen
fi
KATALOG=$(cd "$KATALOG" 2>/dev/null && pwd) || fel "Ingen installation i ${ARKITEKTURPORTALEN_KATALOG:-/opt/arkitekturportalen}. Inget är ändrat."
[ -f "$KATALOG/compose.yml" ] && [ -f "$KATALOG/lib/gemensamt.sh" ] \
    || fel "$KATALOG ser inte ut som en installation av Arkitekturportalen (compose.yml eller lib/ saknas). Inget är ändrat."
[ "$KATALOG" != / ] || fel "Installationen kan inte ligga i /."
PROJEKT=$(sed -n 's/^name: *//p' "$KATALOG/compose.yml" | head -n1)
[ -n "$PROJEKT" ] || fel "$KATALOG/compose.yml saknar projektnamnet (name:). Inget är ändrat."

# ── Förutsättningar ───────────────────────────────────────────────────────────

command -v docker >/dev/null 2>&1 || fel "Docker saknas – då körs inte heller portalen. Ta bort $KATALOG för hand."
docker info >/dev/null 2>&1 || {
    [ "$(id -u)" = 0 ] || fel "Du får inte använda Docker. Kör filen med sudo:  sudo sh $0"
    fel "Docker svarar inte. Starta det (systemctl start docker) och kör filen igen."
}
foralder=$(dirname "$KATALOG")
[ -w "$foralder" ] && [ -w "$KATALOG" ] || fel "Får inte ta bort $KATALOG. Kör filen med sudo:  sudo sh $0"

etikett="label=com.docker.compose.project=$PROJEKT"
containrar=$(docker ps -aq --filter "$etikett")
volymer=$(docker volume ls -q --filter "$etikett")
natverk=$(docker network ls -q --filter "$etikett")
# Avbilderna: de som containrarna kör, Arkitektursamverkans (även äldre
# versioner som tidigare installationsfiler läst in) och de övriga i compose.yml.
avbilder=$(
    for c in $containrar; do docker inspect --format '{{.Config.Image}}' "$c"; done
    docker images --format '{{.Repository}}:{{.Tag}}' | grep '^ghcr\.io/arkitektursamverkan/' || true
    grep -oE '^\s+image: [a-z0-9]+:[^$ ]+$' "$KATALOG/compose.yml" | awk '{print $2}'
)
avbilder=$(printf '%s\n' "$avbilder" | grep -v '^$' | sort -u || true)
# Backuprader i root:s (eller användarens) crontab som pekar på installationen.
cron_rader=$(crontab -l 2>/dev/null | grep -F "$KATALOG" || true)
backuper=""
[ -d "$KATALOG/backups" ] && backuper=$(find "$KATALOG/backups" -mindepth 2 -maxdepth 2 -name KLAR | sed 's|/KLAR$||' | sort)
antal() { if [ -z "$1" ]; then echo 0; else printf '%s\n' "$1" | wc -l | tr -d ' '; fi; }

# ── Vad som finns ─────────────────────────────────────────────────────────────

rubrik "Installationen"
info "Katalog:     $KATALOG"
info "Version:     portalen $(env_varde PORTAL_VERSION)$(case ",$(env_varde COMPOSE_PROFILES)," in *,plattform,*) echo ", plattformen $(env_varde PLATFORM_VERSION)" ;; esac)$(case ",$(env_varde COMPOSE_PROFILES)," in *,arkitekten,*) echo ", Arkitekten $(env_varde ARKITEKTEN_VERSION)" ;; esac)"
[ -n "$(env_varde PORTAL_HOST)" ] && info "Adress:      https://$(env_varde PORTAL_HOST)/"
info "Docker:      $(antal "$containrar") containrar, $(antal "$volymer") datavolymer, $(antal "$avbilder") avbilder"
info "Backuper:    $(antal "$backuper") i $KATALOG/backups"
[ -n "$cron_rader" ] && info "Cron:        $(antal "$cron_rader") rader som kör installationens skript"

# ── Frågor ────────────────────────────────────────────────────────────────────

rubrik "Före avinstallationen"
SISTA_BACKUP=0
if [ -n "$(docker ps -q --filter "$etikett" --filter label=com.docker.compose.service=api)" ] && [ -f "$KATALOG/.env" ]; then
    ja_nej "Ta en sista backup?" j && SISTA_BACKUP=1
else
    info "Portalen körs inte, så ingen ny backup kan tas."
fi

SPARA=""
if [ $SISTA_BACKUP = 1 ] || [ -n "$backuper" ]; then
    info "Backuperna ligger i installationen och försvinner med den om de inte flyttas."
    info "De innehåller installationens nycklar – förvara dem som lösenord."
    if ja_nej "Spara backuperna utanför installationen?" j; then
        if [ "$(id -u)" = 0 ]; then forslag=/var/backups; else forslag=$HOME; fi
        forslag=$forslag/arkitekturportalen-$(date +%Y%m%d-%H%M%S)
        while :; do
            SPARA=$(fraga "  Katalog" "$forslag")
            case "$SPARA" in
                /*) ;;
                *) info "  Ange en hel sökväg (som börjar med /)."; continue ;;
            esac
            case "$SPARA/" in
                "$KATALOG"/*) info "  Katalogen får inte ligga i installationen."; continue ;;
            esac
            [ -e "$SPARA" ] && { info "  $SPARA finns redan – välj en ny katalog."; continue; }
            mkdir -p "$(dirname "$SPARA")" 2>/dev/null && [ -w "$(dirname "$SPARA")" ] && break
            info "  Får inte skriva i $(dirname "$SPARA")."
        done
    fi
fi

TA_BORT_AVBILDER=0
if [ -n "$avbilder" ]; then
    info "Avbilderna är själva programmet. En avbild som något annat på servern använder lämnas kvar."
    ja_nej "Ta bort avbilderna ur Docker?" j && TA_BORT_AVBILDER=1
fi

rubrik "Det här tas bort"
info "- tjänsterna: $(antal "$containrar") containrar"
info "- all data: $(antal "$volymer") volymer (databaserna, portalens filer, Arkitektens innehåll, certifikaten)"
[ $TA_BORT_AVBILDER = 1 ] && info "- avbilderna: $(antal "$avbilder")"
[ -n "$cron_rader" ] && info "- raderna i crontab som kör installationens skript"
info "- $KATALOG, med .env och nycklarna$([ -z "$SPARA" ] && [ -n "$backuper" ] && echo " och backuperna")"
[ -n "$SPARA" ] && info "Backuperna sparas i $SPARA."
[ -z "$SPARA" ] && info "Utan en sparad backup går datan inte att få tillbaka."
printf 'Skriv avinstallera för att fortsätta: ' >&2
IFS= read -r svar || svar=""
[ "$svar" = avinstallera ] || fel "Avbrutet. Inget är ändrat."

# ── Avinstallation ────────────────────────────────────────────────────────────

cd "$KATALOG"
if [ $SISTA_BACKUP = 1 ]; then
    rubrik "Sista backup"
    bash ./backup.sh fore-avinstallation >/dev/null || fel "Backupen misslyckades. Inget är borttaget."
    backuper=$(find "$KATALOG/backups" -mindepth 2 -maxdepth 2 -name KLAR | sed 's|/KLAR$||' | sort)
fi
if [ -n "$SPARA" ]; then
    mkdir -p "$SPARA"
    chmod 700 "$SPARA"
    for b in $backuper; do cp -a "$b" "$SPARA/"; done
    # Tillsammans med installationsfilen räcker det för att återskapa portalen.
    cp .env "$SPARA/env" 2>/dev/null || true
    chmod 600 "$SPARA/env" 2>/dev/null || true
    info "Backuperna är sparade i $SPARA."
fi
cd /

rubrik "Tar bort"
if [ -n "$containrar" ]; then
    info "Stoppar tjänsterna…"
    # shellcheck disable=SC2086 # en container per ord
    docker stop -t 30 $containrar >/dev/null 2>&1 || true
    # shellcheck disable=SC2086
    docker rm -f $containrar >/dev/null
fi
if [ -n "$volymer" ]; then
    info "Tar bort datan…"
    # shellcheck disable=SC2086
    docker volume rm $volymer >/dev/null
fi
# shellcheck disable=SC2086
[ -n "$natverk" ] && docker network rm $natverk >/dev/null 2>&1 || true
if [ $TA_BORT_AVBILDER = 1 ]; then
    info "Tar bort avbilderna…"
    kvar=""
    for a in $avbilder; do
        docker image inspect "$a" >/dev/null 2>&1 || continue
        docker rmi "$a" >/dev/null 2>&1 || kvar="$kvar $a"
    done
    [ -n "$kvar" ] && info "  Används av annat på servern och lämnas kvar:$kvar"
fi
if [ -n "$cron_rader" ]; then
    crontab -l 2>/dev/null | grep -vF "$KATALOG" | crontab - && info "Raderna i crontab är borttagna."
fi
rm -rf "$KATALOG"
info "$KATALOG är borttagen."

# ── Klart ─────────────────────────────────────────────────────────────────────

rubrik "Klart"
info "Arkitekturportalen är avinstallerad. Docker finns kvar."
[ -n "$SPARA" ] && info "Backuperna: $SPARA (återskapa: installera, sedan ./aterstall.sh med en av dem)."
info ""
info "Kvar att göra utanför servern, om portalen inte ska användas mer:"
info "- DNS-namnen som pekar på servern"
info "- appregistreringarna i Microsoft Entra ID"
info "- brandväggsöppningarna för port 80 och 443"
info "- kopior av backuperna på andra platser (de innehåller nycklarna)"
