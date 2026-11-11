#!/usr/bin/env bash
# Installationsguide för Arkitekturportalen.
#
# Frågar efter det som skiljer en installation från en annan, skriver .env,
# skapar hemligheterna, startar allt och gör det första: administratörskonto,
# plattformens nyckel för portalen, Arkitektens källa i plattformen och
# exempelinnehåll.
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

MODULE_KEYS=(calendar collaboration governance glossary surveys changes)
declare -A MODULE_NAMES=(
    [calendar]="Verksamhetskalender med förändringslogg"
    [collaboration]="Samarbeten: uppdrag och arbetsgrupper"
    [governance]="Arkitekturstyrning: principer, nuläge, målarkitektur, GAP-analys"
    [glossary]="Ordlista"
    [surveys]="Enkäter"
    [changes]="Förändringsstatistik: tillagda, ändrade och borttagna objekt över tid"
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
PORTAL_HOST=$(vardnamn "$(fraga_maste "Portalens värdnamn (DNS pekar på den här servern)" "$(env_get PORTAL_HOST | sed 's/^arkitektur\.example\.org$//')")")
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
kontrollera_namn "$PORTAL_HOST" "$TLS_MODE"
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
plattform_nu=n; plattform_vald && plattform_nu=j
if ja_nej "Installera Integrationsplattformen?" "$plattform_nu"; then
    PLATTFORM=1
    PLATFORM_HOST=$(vardnamn "$(fraga_maste "Plattformens värdnamn" "$(env_get PLATFORM_HOST)")")
    env_set PLATFORM_HOST "$PLATFORM_HOST"
    kontrollera_namn "$PLATFORM_HOST" "$TLS_MODE"
    env_set INTEGRATION_PLATFORM_URL "http://plattform-api:8000/api/v1"
    for k in PLATFORM_ENCRYPTION_KEY PLATFORM_ADMIN_API_KEY PLATFORM_JWT_SECRET PLATFORM_POSTGRES_PASSWORD SYNC_WEBHOOK_SECRET; do
        env_set "$k" "$(hemlighet "$k")"
    done
    cp caddy/mallar/plattform.caddy caddy/sites/plattform.caddy
else
    PLATTFORM=0
    env_set INTEGRATION_PLATFORM_URL ""
    rm -f caddy/sites/plattform.caddy
fi

# ── Arkitekten (processritaren) ──────────────────────────────────────────────

rubrik "Arkitekten (processritaren)"
info "Ritar affärsprocesser och systemprocesser; de som publiceras visas i portalen."
ARKITEKTEN=0
ark_nu=n; arkitekten_vald && ark_nu=j
if [ $PLATTFORM = 0 ]; then
    # Beslut B1: bilderna når portalen bara genom plattformen.
    info "Arkitekten kräver Integrationsplattformen – processbilderna når portalen"
    info "bara genom den. Välj plattformen ovan för att kunna installera Arkitekten."
    [ $ark_nu = j ] && info "Arkitekten stängs av (dess innehåll ligger kvar i volymen)."
elif ja_nej "Installera Arkitekten?" "$ark_nu"; then
    ARKITEKTEN=1
    ARKITEKTEN_HOST=$(vardnamn "$(fraga_maste "Arkitektens värdnamn" "$(env_get ARKITEKTEN_HOST)")")
    env_set ARKITEKTEN_HOST "$ARKITEKTEN_HOST"
    kontrollera_namn "$ARKITEKTEN_HOST" "$TLS_MODE"
    env_set ARKITEKTEN_URL "https://$ARKITEKTEN_HOST"
    [ -n "$(env_get ARKITEKTEN_VERSION)" ] \
        || env_set ARKITEKTEN_VERSION "$(fraga_maste "Arkitektens version (se $RELEASES_ARKITEKTEN)")"
    env_set ARKITEKTEN_SESSION_SECRET "$(hemlighet ARKITEKTEN_SESSION_SECRET)"
    # Nyckeln mellan Arkitektens flödestjänst och plattformen.
    env_set ARKITEKTEN_FLODESTJANST_NYCKEL "$(hemlighet ARKITEKTEN_FLODESTJANST_NYCKEL)"

    ark_entra=n; [ "$(env_get ARKITEKTEN_AUTH)" = entra ] && ark_entra=j
    [ $ENTRA = 1 ] && [ $FORSTA = 1 ] && ark_entra=j
    if ja_nej "Logga in med Entra ID i Arkitekten? (annars egna konton – första besöket skapar administratören)" "$ark_entra"; then
        env_set ARKITEKTEN_AUTH entra
        samma=n; [ $ENTRA = 1 ] && samma=j
        if [ $ENTRA = 1 ] && ja_nej "  Samma appregistrering som portalen?" "$samma"; then
            env_set ARKITEKTEN_ENTRA_TENANT_ID "$(env_get ENTRA_TENANT_ID)"
            env_set ARKITEKTEN_ENTRA_CLIENT_ID "$(env_get ENTRA_CLIENT_ID)"
        else
            env_set ARKITEKTEN_ENTRA_TENANT_ID "$(fraga_maste "  Katalog-ID (tenant ID)" "$(env_get ARKITEKTEN_ENTRA_TENANT_ID)")"
            env_set ARKITEKTEN_ENTRA_CLIENT_ID "$(fraga_maste "  Program-ID (client ID)" "$(env_get ARKITEKTEN_ENTRA_CLIENT_ID)")"
        fi
        if [ -z "$(env_get ARKITEKTEN_ENTRA_CLIENT_SECRET)" ]; then
            printf '  Klienthemlighet (värdet, inte id:t): ' >&2
            IFS= read -rs hemlig || true
            printf '\n' >&2
            [ -n "$hemlig" ] || fel "Entra ID kräver en klienthemlighet."
            env_set ARKITEKTEN_ENTRA_CLIENT_SECRET "$hemlig"
        fi
        env_set ARKITEKTEN_ENTRA_ADMIN_ROLLER "$(fraga "  Approller som ger administratör" "$(env_get ARKITEKTEN_ENTRA_ADMIN_ROLLER)")"
    else
        env_set ARKITEKTEN_AUTH lokal
    fi

    if [ -z "$(env_get ARKITEKTEN_ANTHROPIC_API_KEY)" ]; then
        printf 'Nyckel för AI-stödet (Anthropic), tomt = AI-stödet är av: ' >&2
        IFS= read -rs ai || true
        printf '\n' >&2
        [ -n "$ai" ] && env_set ARKITEKTEN_ANTHROPIC_API_KEY "$ai"
    fi
    cp caddy/mallar/arkitekten.caddy caddy/sites/arkitekten.caddy
else
    info "Arkitekten installeras inte."
fi
[ $ARKITEKTEN = 1 ] || { env_set ARKITEKTEN_URL ""; rm -f caddy/sites/arkitekten.caddy; }
# Plattformen hämtar processbilderna från flödestjänsten och skapar själv
# källan, flödet och schemat första gången.
if [ $PLATTFORM = 1 ] && [ $ARKITEKTEN = 1 ]; then
    env_set PLATFORM_ARKITEKTEN_URL "http://arkitekten-flodestjanst:8200"
else
    env_set PLATFORM_ARKITEKTEN_URL ""
fi

# Profilerna och modulen följer valen.
profiler=()
[ $PLATTFORM = 1 ] && profiler+=(plattform)
[ $ARKITEKTEN = 1 ] && profiler+=(arkitekten)
env_set COMPOSE_PROFILES "$(IFS=,; printf '%s' "${profiler[*]:-}")"
if [ $ARKITEKTEN = 1 ]; then
    case ",$MODULES," in *,arkitekten,*) ;; *) MODULES=${MODULES:+$MODULES,}arkitekten ;; esac
else
    MODULES=$(printf '%s' ",$MODULES," | sed 's/,arkitekten,/,/; s/^,//; s/,$//')
fi
env_set MODULES "$MODULES"

# ── Hemligheter ───────────────────────────────────────────────────────────────

# SETUP_CODE: engångskoden för det första kontot i portalen, plattformen och
# Arkitekten (utan den kan den som först hittar en ny installation ta den).
for k in API_KEY LOCAL_AUTH_SECRET POSTGRES_PASSWORD SETUP_CODE; do
    env_set "$k" "$(hemlighet "$k")"
done

# ── Avbilder ──────────────────────────────────────────────────────────────────

rubrik "Avbilder"
if [ $PULL = 1 ]; then
    if ! dc pull --quiet; then
        info "Avbilderna gick inte att hämta. Når servern ghcr.io (brandvägg, proxy)?"
        fel "docker compose pull misslyckades."
    fi
fi
info "Portalen $(env_get PORTAL_VERSION)$([ $PLATTFORM = 1 ] && echo ", plattformen $(env_get PLATFORM_VERSION)")$([ $ARKITEKTEN = 1 ] && echo ", Arkitekten $(env_get ARKITEKTEN_VERSION)")."

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
if [ $ARKITEKTEN = 0 ] && [ -n "$(dc --profile arkitekten ps -q arkitekten 2>/dev/null)" ]; then
    info "Stoppar Arkitekten (dess innehåll ligger kvar i volymen)."
    dc --profile arkitekten rm -sf arkitekten arkitekten-flodestjanst >&2
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

if [ $ARKITEKTEN = 1 ]; then
    info "Väntar på Arkitekten…"
    vanta_pa_node arkitekten http://localhost:5173/health || fel "Avbrutet."
    # Källan i plattformen som hämtar de publicerade processbilderna från
    # Arkitektens flödestjänst varannan timme. Portalen hittar den själv.
    svar=$(dc exec -T plattform-api python -c '
import json, os, urllib.request
H = {"Content-Type": "application/json", "X-API-Key": os.environ["ADMIN_API_KEY"]}
def anrop(väg, data=None, metod="GET"):
    req = urllib.request.Request("http://localhost:8000/api/v1" + väg, method=metod, headers=H,
                                 data=json.dumps(data).encode() if data is not None else None)
    return json.load(urllib.request.urlopen(req))
ark = {c["id"] for c in anrop("/connections") if c.get("connector_type") == "arkitekten"}
if ark:
    # Slås på igen om Arkitekten varit avvald.
    for f in anrop("/flows"):
        if f.get("connection_id") in ark and not f.get("enabled"):
            anrop("/flows/" + f["id"], {"enabled": True}, "PUT")
    print("finns")
else:
    c = anrop("/connections", {"name": "Arkitekten", "connector_type": "arkitekten",
        "description": "Publicerade processbilder från Arkitekten",
        "config": {"base_url": "http://arkitekten-flodestjanst:8200", "familj": "alla",
                   "endast_publicerade": True, "version": "fastslagen"}}, "POST")
    f = anrop("/flows", {"name": "Arkitekten – processbilder till portalen", "connection_id": c["id"]}, "POST")
    anrop("/schedules", {"flow_id": f["id"], "cron_expression": "0 */2 * * *"}, "POST")
    print("skapad")
' </dev/null) || fel "Arkitektens källa i plattformen kunde inte skapas."
    case "$svar" in
        skapad) info "Arkitektens källa i plattformen är skapad (hämtar varannan timme)." ;;
        finns) info "Arkitektens källa i plattformen finns redan (påslagen)." ;;
    esac
    if ja_nej "Lägga in Arkitektens exempelprocesser?" "$([ $FORSTA = 1 ] && echo j || echo n)"; then
        # Skriver aldrig över – det som finns står kvar.
        dc exec -T -u node arkitekten node_modules/.bin/tsx server/innehallspaket.mts import exempel </dev/null >&2 || true
    fi
fi

if [ $ARKITEKTEN = 0 ] && [ $PLATTFORM = 1 ]; then
    # Avvald: plattformens källa ska inte försöka nå en Arkitekten som inte körs.
    dc exec -T plattform-api python -c '
import json, os, urllib.request
H = {"Content-Type": "application/json", "X-API-Key": os.environ["ADMIN_API_KEY"]}
def anrop(väg, data=None, metod="GET"):
    req = urllib.request.Request("http://localhost:8000/api/v1" + väg, method=metod, headers=H,
                                 data=json.dumps(data).encode() if data is not None else None)
    return json.load(urllib.request.urlopen(req))
ark = {c["id"] for c in anrop("/connections") if c.get("connector_type") == "arkitekten"}
for f in anrop("/flows"):
    if f.get("connection_id") in ark and f.get("enabled"):
        anrop("/flows/" + f["id"], {"enabled": False}, "PUT")
        print("Arkitektens källa i plattformen är avstängd.")
' </dev/null >&2 || info "Arkitektens källa i plattformen kunde inte stängas av – gör det i plattformen."
fi

for p in "${valda_paket[@]}"; do
    info "Läser in $p…"
    # Bara sammanfattningen per slag, inte loggraden för varje post.
    dc exec -T api python -m app.services.content_pack import "$p" 2>&1 | grep -v ' \[info ' >&2 || true
done

# ── Klart ─────────────────────────────────────────────────────────────────────

rubrik "Klart"
info "Skriv hela adressen i webbläsaren, med https:// och namnet, inte IP-adressen."
info "Portalen:      https://$PORTAL_HOST/"
[ $PLATTFORM = 1 ] && info "Plattformen:   https://$(env_get PLATFORM_HOST)/  (första besöket skapar dess administratör, med engångskoden)"
if [ $ARKITEKTEN = 1 ]; then
    info "Arkitekten:    https://$(env_get ARKITEKTEN_HOST)/$([ "$(env_get ARKITEKTEN_AUTH)" = lokal ] && echo "  (första besöket skapar dess administratör, med engångskoden)")"
    [ "$(env_get ARKITEKTEN_AUTH)" = entra ] && info "               Entra ID: redirect-URI (Web) https://$(env_get ARKITEKTEN_HOST)/__ark/auth/callback"
fi
if [ $LOKAL_ADMIN = 1 ]; then
    info "Logga in som:  $ADMIN_EPOST"
    [ "${ADMIN_LOSEN_GENERERAT:-0}" = 1 ] && info "Lösenord:      $ADMIN_LOSEN   (visas bara nu – byt det efter inloggningen)"
fi
[ $ENTRA = 1 ] && info "Entra ID:      appregistreringen behöver redirect-URI https://$PORTAL_HOST/"
info "Engångskod:    $(env_get SETUP_CODE)   (för första administratörskontot; står också i .env som SETUP_CODE)"
[ "$TLS_MODE" = intern ] && info "Webbläsaren varnar för certifikatet. Det är väntat i läget intern: välj Avancerat och fortsätt."
[ "$TLS_MODE" = auto ] && info "Certifikatet hämtas från Let's Encrypt vid första besöket; det kräver port 80 och 443 från internet."
[ $PLATTFORM = 1 ] && info "Synk efter körning: ge flödet webhooken http://api:8000/api/v1/sync/webhook"
info ""
info "Backup: ./backup.sh – lägg det i cron för varje natt (se README)."
info ""
info ".env innehåller installationens hemligheter. Spara en kopia säkert – utan"
info "den går databaserna och plattformens sparade inloggningar inte att läsa."
