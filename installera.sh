#!/usr/bin/env bash
# Installationsguide för Arkitekturportalen.
#
# Frågar efter det som skiljer en installation från en annan, skriver .env,
# skapar hemligheterna, startar allt och gör det första: administratörskonto,
# plattformens nyckel för portalen och exempelinnehåll.
#
# Går att köra igen: värdena i en befintlig .env blir förslag och hemligheter
# som redan finns behålls (en ny databas- eller krypteringsnyckel skulle göra
# befintliga data oläsbara).
#
#   ./installera.sh              hämtar avbilderna från registret
#   ./installera.sh --utan-pull  använder avbilder som redan finns lokalt
set -euo pipefail

cd "$(dirname "$0")"

PULL=1
for arg in "$@"; do
    case "$arg" in
        --utan-pull) PULL=0 ;;
        -h|--help) sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "Okänt argument: $arg (se --help)" >&2; exit 2 ;;
    esac
done

MODULE_KEYS=(calendar collaboration governance glossary surveys)
declare -A MODULE_NAMES=(
    [calendar]="Verksamhetskalender med förändringslogg"
    [collaboration]="Samarbeten: uppdrag och arbetsgrupper"
    [governance]="Arkitekturstyrning: principer, nuläge, målarkitektur, GAP-analys"
    [glossary]="Ordlista"
    [surveys]="Enkäter"
)

# shellcheck source=lib/gemensamt.sh
. lib/gemensamt.sh

# ── Förutsättningar ──────────────────────────────────────────────────────────

for prog in docker openssl awk; do
    command -v "$prog" >/dev/null || fel "$prog saknas."
done
docker compose version >/dev/null 2>&1 || fel "Docker Compose v2 (docker compose) saknas."
docker info >/dev/null 2>&1 || fel "Docker svarar inte – körs tjänsten, och får du använda den (gruppen docker)?"

rubrik "Arkitekturportalen – installation"
if [ -f "$ENV_FILE" ]; then
    FORSTA=0
    info "Det finns redan en .env. Dess värden blir förslag och hemligheterna behålls."
else
    FORSTA=1
    cp .env.example "$ENV_FILE"
fi
chmod 600 "$ENV_FILE"

# ── Webbadress och TLS ────────────────────────────────────────────────────────

rubrik "Webbadress och certifikat"
PORTAL_HOST=$(fraga_maste "Portalens värdnamn (DNS pekar på den här servern)" "$(env_get PORTAL_HOST | sed 's/^arkitektur\.example\.org$//')")
env_set PORTAL_HOST "$PORTAL_HOST"

info "Certifikat:"
info "  auto    Let's Encrypt – servern nås från internet på port 80 och 443"
info "  egen    organisationens eget certifikat, läggs i certs/"
info "  intern  Caddys egen CA – för test och slutna nät (webbläsaren varnar)"
while :; do
    TLS_MODE=$(fraga "TLS-läge" "$(env_get TLS_MODE)")
    case "$TLS_MODE" in auto|egen|intern) break ;; esac
    info "  Välj auto, egen eller intern."
done
env_set TLS_MODE "$TLS_MODE"
case "$TLS_MODE" in
    auto)
        env_set ACME_EMAIL "$(fraga_maste "E-post för varningar om certifikat" "$(env_get ACME_EMAIL)")"
        ;;
    egen)
        cert=$(fraga "Certifikatfil i certs/ (med hela kedjan)" "$(env_get TLS_CERT_FILE || true)")
        cert=${cert:-fullchain.pem}
        key=$(fraga "Nyckelfil i certs/" "$(env_get TLS_KEY_FILE || true)")
        key=${key:-privkey.pem}
        while [ ! -f "certs/$cert" ] || [ ! -f "certs/$key" ]; do
            info "  certs/$cert eller certs/$key saknas. Lägg dit filerna och tryck Enter."
            IFS= read -r _ || fel "Certifikatfilerna saknas."
        done
        env_set TLS_CERT_FILE "$cert"
        env_set TLS_KEY_FILE "$key"
        ;;
esac

# ── Organisation och inloggning ───────────────────────────────────────────────

rubrik "Organisation"
env_set PDF_ORG_NAME "$(fraga "Organisationens namn (inloggningssidan och PDF:er)" "$(env_get PDF_ORG_NAME)")"
domaner=$(env_get ALLOWED_EMAIL_DOMAINS)
[ "$domaner" = example.org ] && domaner=""
env_set ALLOWED_EMAIL_DOMAINS "$(fraga_maste "Tillåtna e-postdomäner, kommaseparerade" "$domaner")"

rubrik "Inloggning"
info "Med Microsoft Entra ID loggar medarbetarna in med sina vanliga konton."
info "Utan det finns bara lokala konton som en administratör skapar."
entra_nu=n; [ -n "$(env_get ENTRA_CLIENT_ID)" ] && entra_nu=j
if ja_nej "Använda Entra ID?" "$entra_nu"; then
    ENTRA=1
    env_set ENTRA_TENANT_ID "$(fraga_maste "Katalog-ID (tenant ID)" "$(env_get ENTRA_TENANT_ID)")"
    env_set ENTRA_CLIENT_ID "$(fraga_maste "Program-ID (client ID) för appregistreringen" "$(env_get ENTRA_CLIENT_ID)")"
    env_set BOOTSTRAP_ADMIN_EMAILS "$(fraga_maste "Vem blir administratör när hen loggar in? (e-post, kommaseparerade)" "$(env_get BOOTSTRAP_ADMIN_EMAILS)")"
else
    ENTRA=0
    env_set ENTRA_TENANT_ID ""
    env_set ENTRA_CLIENT_ID ""
fi

LOKAL_ADMIN=0
lokal_forslag=j; [ $ENTRA = 1 ] && lokal_forslag=n
[ $FORSTA = 0 ] && lokal_forslag=n
if ja_nej "Skapa ett lokalt administratörskonto?" "$lokal_forslag"; then
    LOKAL_ADMIN=1
    ADMIN_NAMN=$(fraga_maste "  Namn")
    ADMIN_EPOST=$(fraga_maste "  E-post (används som inloggning)")
    printf '  Lösenord, minst 8 tecken (tomt = ett genereras): ' >&2
    IFS= read -rs ADMIN_LOSEN || true
    printf '\n' >&2
    if [ -z "$ADMIN_LOSEN" ]; then
        ADMIN_LOSEN=$(openssl rand -base64 18 | tr -d '/+=' | cut -c1-16)
        ADMIN_LOSEN_GENERERAT=1
    else
        [ ${#ADMIN_LOSEN} -ge 8 ] || fel "Lösenordet är kortare än 8 tecken."
        ADMIN_LOSEN_GENERERAT=0
    fi
fi

if ja_nej "Får man läsa arkitekturobjekten utan att logga in?" "$([ "$(env_get ANONYMOUS_READ)" = true ] && echo j || echo n)"; then
    env_set ANONYMOUS_READ true
else
    env_set ANONYMOUS_READ false
fi

# ── Moduler ───────────────────────────────────────────────────────────────────

rubrik "Moduler"
info "Kärnan (arkitekturobjekt, vyer, rapporter, lösningsskisser, administration)"
info "ingår alltid. En administratör kan slå på och av moduler senare."
nu_moduler=",$(env_get MODULES),"
valda=()
for m in "${MODULE_KEYS[@]}"; do
    forslag=n
    case "$nu_moduler" in *",all,"*|*",$m,"*) forslag=j ;; esac
    if ja_nej "  ${MODULE_NAMES[$m]}?" "$forslag"; then valda+=("$m"); fi
done
MODULES=$(IFS=,; printf '%s' "${valda[*]:-}")
env_set MODULES "$MODULES"

# ── Integrationsplattformen ──────────────────────────────────────────────────

rubrik "Integrationsplattformen"
info "Hämtar data från andra system (t.ex. HR, ekonomi, CMDB) in i portalen."
plattform_nu=n; [ "$(env_get COMPOSE_PROFILES)" = plattform ] && plattform_nu=j
if ja_nej "Installera Integrationsplattformen?" "$plattform_nu"; then
    PLATTFORM=1
    env_set PLATFORM_HOST "$(fraga_maste "Plattformens värdnamn" "$(env_get PLATFORM_HOST)")"
    env_set COMPOSE_PROFILES plattform
    env_set INTEGRATION_PLATFORM_URL "http://plattform-api:8000/api/v1"
    for k in PLATFORM_ENCRYPTION_KEY PLATFORM_ADMIN_API_KEY PLATFORM_JWT_SECRET PLATFORM_POSTGRES_PASSWORD SYNC_WEBHOOK_SECRET; do
        env_set "$k" "$(hemlighet "$k")"
    done
    cp caddy/mallar/plattform.caddy caddy/sites/plattform.caddy
else
    PLATTFORM=0
    env_set COMPOSE_PROFILES ""
    env_set INTEGRATION_PLATFORM_URL ""
    rm -f caddy/sites/plattform.caddy
fi

# ── Hemligheter ───────────────────────────────────────────────────────────────

for k in API_KEY LOCAL_AUTH_SECRET POSTGRES_PASSWORD; do
    env_set "$k" "$(hemlighet "$k")"
done

# ── Avbilder ──────────────────────────────────────────────────────────────────

rubrik "Avbilder"
if [ $PULL = 1 ]; then
    if ! dc pull --quiet; then
        info "Avbilderna gick inte att hämta. Är de privata behövs först:"
        info "  docker login ghcr.io   (användarnamn + GitHub-token med read:packages)"
        fel "docker compose pull misslyckades."
    fi
fi
info "Portalen $(env_get PORTAL_VERSION)$([ $PLATTFORM = 1 ] && echo ", plattformen $(env_get PLATFORM_VERSION)")."

# ── Exempelinnehåll ───────────────────────────────────────────────────────────

# Exempelpaketen som följer med avbilden: namn|moduler|beskrivning
PAKET=$(dc run --rm --no-deps -T api python -c '
import json, pathlib
for p in sorted(pathlib.Path("content_packs").glob("*/pack.json")):
    m = json.loads(p.read_text())
    print("|".join([m["name"], ",".join(m.get("modules", [])), m.get("description", "")]))
' 2>/dev/null || true)

valda_paket=()
if [ -n "$PAKET" ]; then
    rubrik "Exempelinnehåll"
    info "Neutrala exempel att skriva om till organisationens egna. Läses de in"
    info "igen skrivs ändringar i samma poster över, så svara nej vid omkörning."
    # Listan läses från fd 3 så att frågorna kan läsa svaren från stdin.
    while IFS='|' read -r namn mods beskr <&3; do
        mod_pa=1
        IFS=, read -ra behov <<< "$mods"
        for b in "${behov[@]}"; do
            case ",$MODULES," in *",$b,"*) ;; *) mod_pa=0 ;; esac
        done
        [ $mod_pa = 1 ] || continue
        info "  $namn: $beskr"
        if ja_nej "  Läsa in $namn?" "$([ $FORSTA = 1 ] && echo j || echo n)"; then valda_paket+=("$namn"); fi
    done 3<<< "$PAKET"
    [ ${#valda_paket[@]} -gt 0 ] || [ -n "$MODULES" ] || info "  (Inga moduler valda – exempelpaketen hör till moduler.)"
fi

# ── Start ─────────────────────────────────────────────────────────────────────

rubrik "Startar"
if [ $PLATTFORM = 0 ] && [ -n "$(dc --profile plattform ps -q plattform-api 2>/dev/null)" ]; then
    info "Stoppar Integrationsplattformen (dess data ligger kvar i volymerna)."
    dc --profile plattform rm -sf plattform-web plattform-api plattform-redis plattform-db >&2
fi
dc up -d --remove-orphans
# Caddy läser om webbplatserna (plattformen kan ha slagits på eller av).
dc exec -T caddy caddy reload --config /etc/caddy/Caddyfile --adapter caddyfile >/dev/null 2>&1 \
    || dc restart caddy >&2
info "Väntar på portalen (första starten skapar databasen)…"
vanta_pa api http://localhost:8000/api/v1/health || fel "Avbrutet."

if [ $LOKAL_ADMIN = 1 ]; then
    svar=$(dc exec -T -e NY_NAMN="$ADMIN_NAMN" -e NY_EPOST="$ADMIN_EPOST" -e NY_LOSEN="$ADMIN_LOSEN" api python -c '
import json, os, urllib.error, urllib.request
body = json.dumps({"name": os.environ["NY_NAMN"], "email": os.environ["NY_EPOST"],
                   "password": os.environ["NY_LOSEN"], "role": "admin"}).encode()
req = urllib.request.Request("http://localhost:8000/api/v1/users", data=body, method="POST",
                             headers={"Content-Type": "application/json", "X-API-Key": os.environ["API_KEY"]})
try:
    urllib.request.urlopen(req)
    print("skapat")
except urllib.error.HTTPError as e:
    print("finns" if e.code == 400 else f"fel {e.code}: {e.read().decode()}")
')
    case "$svar" in
        skapat) info "Administratören $ADMIN_EPOST är skapad." ;;
        finns) info "Det finns redan ett konto för $ADMIN_EPOST – det lämnas orört."; ADMIN_LOSEN_GENERERAT=0 ;;
        *) fel "Administratören kunde inte skapas: $svar" ;;
    esac
fi

if [ $PLATTFORM = 1 ]; then
    info "Väntar på plattformen…"
    vanta_pa plattform-api http://localhost:8000/api/v1/health || fel "Avbrutet."
    if [ -z "$(env_get INTEGRATION_PLATFORM_API_KEY)" ]; then
        nyckel=$(dc exec -T plattform-api python -c '
import json, os, urllib.request
req = urllib.request.Request("http://localhost:8000/api/v1/api-keys", method="POST",
                             data=json.dumps({"name": "Arkitekturportalen", "scopes": ["data:read"]}).encode(),
                             headers={"Content-Type": "application/json", "X-API-Key": os.environ["ADMIN_API_KEY"]})
print(json.load(urllib.request.urlopen(req))["key"])
') || fel "Plattformens nyckel för portalen kunde inte skapas."
        env_set INTEGRATION_PLATFORM_API_KEY "$nyckel"
        info "Portalens läsnyckel i plattformen är skapad."
        dc up -d api
        vanta_pa api http://localhost:8000/api/v1/health || fel "Avbrutet."
    fi
fi

for p in "${valda_paket[@]}"; do
    info "Läser in $p…"
    # Bara sammanfattningen per slag, inte loggraden för varje post.
    dc exec -T api python -m app.services.content_pack import "$p" 2>&1 | grep -v ' \[info ' >&2 || true
done

# ── Klart ─────────────────────────────────────────────────────────────────────

rubrik "Klart"
info "Portalen:      https://$PORTAL_HOST/"
[ $PLATTFORM = 1 ] && info "Plattformen:   https://$(env_get PLATFORM_HOST)/  (första besöket skapar dess administratör)"
if [ $LOKAL_ADMIN = 1 ]; then
    info "Logga in som:  $ADMIN_EPOST"
    [ "${ADMIN_LOSEN_GENERERAT:-0}" = 1 ] && info "Lösenord:      $ADMIN_LOSEN   (visas bara nu – byt det efter inloggningen)"
fi
[ $ENTRA = 1 ] && info "Entra ID:      appregistreringen behöver redirect-URI https://$PORTAL_HOST/"
[ "$TLS_MODE" = auto ] && info "Certifikatet hämtas från Let's Encrypt vid första besöket; det kräver port 80 och 443 från internet."
[ $PLATTFORM = 1 ] && info "Synk efter körning: ge flödet webhooken http://api:8000/api/v1/sync/webhook"
info ""
info "Backup: ./backup.sh – lägg det i cron för varje natt (se README)."
info ""
info ".env innehåller installationens hemligheter. Spara en kopia säkert – utan"
info "den går databaserna och plattformens sparade inloggningar inte att läsa."
