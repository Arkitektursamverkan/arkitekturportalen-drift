#!/bin/sh
# Arkitekturportalen @PORTAL@ – installationsfil.
#
# Allt som behövs finns i den här filen: skripten och programmet (avbilderna
# för portalen, Integrationsplattformen, Arkitekten, databasen och Caddy). Inget hämtas
# från GitHub, och ingen inloggning behövs.
#
#   sudo sh arkitekturportalen-@PORTAL@.run
#
# Samma fil installerar, uppgraderar och avinstallerar. Första gången
# installeras portalen i /opt/arkitekturportalen och guiden ställer sina
# frågor. Finns portalen redan frågar filen vad som ska göras: uppgradera (med
# backup först) eller, med samma version, ändra inställningarna – eller
# avinstallera.
#
#   sudo sh arkitekturportalen-@PORTAL@.run --avinstallera    direkt till avinstallationen
#
# ARKITEKTURPORTALEN_KATALOG=/annan/katalog väljer en annan katalog.
#
# Byggs av bygg-installationsfil.sh; innehållet ligger efter raden
# __INNEHALL__ längst ned.
set -eu

PORTAL=@PORTAL@
PLATTFORM=@PLATTFORM@
ARKITEKTEN=@ARKITEKTEN@
KATALOG=${ARKITEKTURPORTALEN_KATALOG:-/opt/arkitekturportalen}
FIL=$0

rubrik() { printf '\n\033[1m── %s\033[0m\n' "$1" >&2; }
info() { printf '%s\n' "$*" >&2; }
fel() { printf '\033[31mFel:\033[0m %s\n' "$*" >&2; exit 1; }
ja() {
    printf '%s (J/n): ' "$1" >&2
    read -r svar || svar=n
    case "$svar" in ''|j|J|ja|Ja|y|Y) return 0 ;; esac
    return 1
}
# aldre A B – status 0 om version A är äldre än B.
aldre() { [ "$1" != "$2" ] && [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -n1)" = "$1" ]; }
# env_varde NYCKEL – värdet i installationens .env.
env_varde() { sed -n "s/^$1=//p" "$KATALOG/.env" | tail -n1 | tr -d "'"; }
# satt_varde NYCKEL VÄRDE – i installationens .env; raden läggs till om den saknas
# (en .env från en äldre version har inte alla nycklar).
satt_varde() {
    if grep -q "^$1=" "$KATALOG/.env"; then sed -i "s|^$1=.*|$1=$2|" "$KATALOG/.env"
    else printf '%s=%s\n' "$1" "$2" >> "$KATALOG/.env"; fi
}

VAL=""
case "${1:-}" in
    -h|--help) sed -n '2,21p' "$FIL" | sed 's/^# \{0,1\}//'; exit 0 ;;
    --avinstallera) VAL=avinstallera ;;
    '') ;;
    *) fel "Okänt argument: $1 (se --help)" ;;
esac

rubrik "Arkitekturportalen $PORTAL"
[ "$(uname -s)" = Linux ] || fel "Den här filen är för Linux-servrar."

# ── Ny installation, uppgradering eller samma version ─────────────────────────

LAGE=ny
if [ -f "$KATALOG/.env" ]; then
    portal_nu=$(env_varde PORTAL_VERSION)
    plattform_nu=$(env_varde PLATFORM_VERSION)
    ark_nu=$(env_varde ARKITEKTEN_VERSION)
    if aldre "$PORTAL" "$portal_nu"; then
        LAGE=aldre
        info "$KATALOG har version $portal_nu, som är nyare än den här filen ($PORTAL)."
    elif [ "$PORTAL" = "$portal_nu" ] && [ "$PLATTFORM" = "$plattform_nu" ] \
        && { [ -z "$ark_nu" ] || [ "$ARKITEKTEN" = "$ark_nu" ]; }; then
        LAGE=samma
        info "$KATALOG har redan version $PORTAL."
    else
        LAGE=uppgradera
        info "$KATALOG har version $portal_nu."
    fi
fi

# ── Vad ska göras? ────────────────────────────────────────────────────────────

if [ -z "$VAL" ] && [ $LAGE != ny ]; then
    rubrik "Vad vill du göra?"
    case $LAGE in
        uppgradera) info "  1) Uppgradera till $PORTAL (med en backup först)" ;;
        samma) info "  1) Ändra inställningarna" ;;
        aldre) info "  1) – (en äldre version kan inte installeras över en nyare)" ;;
    esac
    info "  2) Avinstallera portalen från servern"
    info "  3) Avbryt"
    forslag=1; [ $LAGE = aldre ] && forslag=3
    while :; do
        printf 'Välj [%s]: ' "$forslag" >&2
        read -r svar || svar=""
        case "${svar:-$forslag}" in
            1) [ $LAGE != aldre ] && break ;;
            2) VAL=avinstallera; break ;;
            3) fel "Avbrutet. Inget är ändrat." ;;
        esac
        info "  Svara $([ $LAGE = aldre ] && echo "2 eller 3" || echo "1, 2 eller 3")."
    done
fi

# ── Avinstallation ────────────────────────────────────────────────────────────

if [ "$VAL" = avinstallera ]; then
    [ $LAGE != ny ] || fel "Portalen är inte installerad i $KATALOG. Inget är ändrat."
    tmp=$(mktemp -d "${TMPDIR:-/var/tmp}/arkitekturportalen.XXXXXX")
    trap 'rm -rf "$tmp"' EXIT INT TERM
    rad=$(awk '/^__INNEHALL__$/ { print NR + 1; exit }' "$FIL")
    tail -n +"$rad" "$FIL" | tar -x -C "$tmp" filer/avinstallera.sh || fel "Filen är skadad – ladda ner den igen."
    # Katalogen anges, annars skulle skriptet tro att den uppackade kopian är installationen.
    ARKITEKTURPORTALEN_KATALOG=$KATALOG ARKITEKTURPORTALEN_FIL=$FIL sh "$tmp/filer/avinstallera.sh"
    exit $?
fi

# ── Förutsättningar ───────────────────────────────────────────────────────────

ar_root=0; [ "$(id -u)" = 0 ] && ar_root=1
kraver_root() { [ $ar_root = 1 ] || fel "$1 Kör filen med sudo:  sudo sh $FIL"; }

if ! command -v docker >/dev/null 2>&1; then
    kraver_root "Docker saknas och behöver installeras."
    info "Docker saknas. Det är programmet som kör portalen."
    ja "Installera Docker nu (från docker.com)?" || fel "Installera Docker och kör filen igen."
    if command -v curl >/dev/null 2>&1; then curl -fsSL https://get.docker.com -o /tmp/get-docker.sh
    elif command -v wget >/dev/null 2>&1; then wget -qO /tmp/get-docker.sh https://get.docker.com
    else fel "Varken curl eller wget finns – installera Docker för hand: https://docs.docker.com/engine/install/"
    fi
    sh /tmp/get-docker.sh || fel "Docker gick inte att installera. Se https://docs.docker.com/engine/install/"
    rm -f /tmp/get-docker.sh
    command -v systemctl >/dev/null 2>&1 && systemctl enable --now docker >/dev/null 2>&1 || true
fi
docker compose version >/dev/null 2>&1 \
    || fel "Docker Compose saknas. Installera paketet docker-compose-plugin och kör filen igen."
docker info >/dev/null 2>&1 || {
    [ $ar_root = 1 ] || fel "Du får inte använda Docker. Kör filen med sudo:  sudo sh $FIL"
    fel "Docker svarar inte. Starta det (systemctl start docker) och kör filen igen."
}
for prog in bash openssl awk tar; do
    command -v "$prog" >/dev/null 2>&1 || fel "$prog saknas – installera det och kör filen igen."
done

[ $LAGE = ny ] && info "Portalen installeras i $KATALOG."
mkdir -p "$KATALOG" 2>/dev/null && [ -w "$KATALOG" ] || kraver_root "Får inte skriva i $KATALOG."

# ── Packa upp ─────────────────────────────────────────────────────────────────

tmp=$(mktemp -d "${TMPDIR:-/var/tmp}/arkitekturportalen.XXXXXX")
trap 'rm -rf "$tmp"' EXIT INT TERM
info "Packar upp…"
rad=$(awk '/^__INNEHALL__$/ { print NR + 1; exit }' "$FIL")
tail -n +"$rad" "$FIL" | tar -x -C "$tmp" || fel "Filen är skadad – ladda ner den igen."
info "Läser in programmet i Docker (tar en stund)…"
docker load -i "$tmp/avbilder.tar.gz" >/dev/null || fel "Avbilderna gick inte att läsa in i Docker."
# Installationens egna filer (.env, certs/, backups/) finns inte i paketet och
# lämnas orörda.
cp -R "$tmp/filer/." "$KATALOG/"
rm -rf "$tmp"

# ── Guiden eller uppgraderingen ───────────────────────────────────────────────

cd "$KATALOG"
case $LAGE in
    uppgradera)
        bash ./uppgradera.sh --utan-pull "$PORTAL" "$PLATTFORM" "$ARKITEKTEN"
        # Utan plattformen eller Arkitekten hoppar uppgraderingen över deras
        # versioner; de ska ändå peka på avbilderna som nu finns, om de slås på
        # senare.
        satt_varde PLATFORM_VERSION "$PLATTFORM"
        satt_varde ARKITEKTEN_VERSION "$ARKITEKTEN"
        ;;
    *)
        # Arkitektens version följer filen, så att guiden inte frågar efter den.
        [ -f .env ] && [ -z "$(env_varde ARKITEKTEN_VERSION)" ] && satt_varde ARKITEKTEN_VERSION "$ARKITEKTEN"
        bash ./installera.sh --utan-pull
        ;;
esac
info ""
info "Installationen finns i $KATALOG. Där finns också backup.sh och README.md."
exit 0
__INNEHALL__
