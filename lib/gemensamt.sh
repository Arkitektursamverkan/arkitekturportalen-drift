# Gemensamt för drift-skripten. Läses in med:  . lib/gemensamt.sh
# (skriptet har redan gjort cd till driftkatalogen).
# shellcheck shell=bash

ENV_FILE=.env

rubrik() { printf '\n\033[1m── %s\033[0m\n' "$1" >&2; }
info() { printf '%s\n' "$*" >&2; }
fel() { printf '\033[31mFel:\033[0m %s\n' "$*" >&2; exit 1; }

# fraga "Fråga" [förslag] → svaret (förslaget om svaret är tomt)
fraga() {
    local svar
    if [ -n "${2:-}" ]; then printf '%s [%s]: ' "$1" "$2" >&2; else printf '%s: ' "$1" >&2; fi
    IFS= read -r svar || true
    printf '%s' "${svar:-${2:-}}"
}

# fraga_maste "Fråga" [förslag] → ett svar som inte är tomt
fraga_maste() {
    local svar
    while :; do
        svar=$(fraga "$1" "${2:-}")
        [ -n "$svar" ] && { printf '%s' "$svar"; return; }
        info "  Ett svar behövs."
    done
}

# ja_nej "Fråga" j|n → status 0 för ja
ja_nej() {
    local svar
    while :; do
        if [ "$2" = j ]; then svar=$(fraga "$1 (J/n)"); else svar=$(fraga "$1 (j/N)"); fi
        svar=${svar:-$2}
        case "${svar,,}" in
            j|ja|y|yes) return 0 ;;
            n|nej|no) return 1 ;;
        esac
        info "  Svara j eller n."
    done
}

# Värdet för KEY i .env (utan citattecken), tomt om det saknas.
env_get() {
    [ -f "$ENV_FILE" ] || return 0
    local rad
    rad=$(grep -E "^$1=" "$ENV_FILE" | tail -n1 || true)
    rad=${rad#*=}
    rad=${rad#\'}; rad=${rad%\'}
    printf '%s' "$rad"
}

# Sätter KEY=VALUE i .env: ersätter raden (även en bortkommenterad "# KEY=")
# eller lägger till den. Värden med blanksteg eller # citeras.
env_set() {
    local key=$1 value=$2
    case "$value" in *"'"*) fel "$key får inte innehålla ' (enkelfnutt)." ;; esac
    case "$value" in *[[:space:]#\"\$]*) value="'$value'" ;; esac
    KEY="$key" VALUE="$value" awk '
        BEGIN { k = ENVIRON["KEY"]; v = ENVIRON["VALUE"]; done = 0 }
        !done && ($0 ~ "^" k "=" || $0 ~ "^# " k "=") { print k "=" v; done = 1; next }
        { print }
        END { if (!done) print k "=" v }
    ' "$ENV_FILE" > "$ENV_FILE.tmp"
    cat "$ENV_FILE.tmp" > "$ENV_FILE"
    rm -f "$ENV_FILE.tmp"
}

# Behåller en befintlig hemlighet, annars en ny.
hemlighet() {
    local nu
    nu=$(env_get "$1")
    if [ -n "$nu" ]; then printf '%s' "$nu"; else openssl rand -hex 32; fi
}

dc() { docker compose "$@"; }

# vanta_pa TJÄNST URL – väntar tills URL svarar inifrån containern. Svarar den
# inte visas loggen och status blir 1.
vanta_pa() {
    for _ in $(seq 1 60); do
        if dc exec -T "$1" python -c "import urllib.request; urllib.request.urlopen('$2', timeout=3)" >/dev/null 2>&1; then
            return 0
        fi
        sleep 3
    done
    dc logs --tail 40 "$1" >&2
    info "$1 svarar inte. Loggen ovan visar varför."
    return 1
}

# Är Integrationsplattformen vald i .env?
plattform_vald() { case ",$(env_get COMPOSE_PROFILES)," in *,plattform,*) return 0 ;; esac; return 1; }

# Är Arkitekten vald i .env?
arkitekten_vald() { case ",$(env_get COMPOSE_PROFILES)," in *,arkitekten,*) return 0 ;; esac; return 1; }

# vanta_pa_node TJÄNST URL – som vanta_pa, för en container med Node (Arkitekten).
vanta_pa_node() {
    for _ in $(seq 1 60); do
        if dc exec -T "$1" node -e "fetch('$2').then(r=>process.exit(r.ok?0:1),()=>process.exit(1))" </dev/null >/dev/null 2>&1; then
            return 0
        fi
        sleep 3
    done
    dc logs --tail 40 "$1" >&2
    info "$1 svarar inte. Loggen ovan visar varför."
    return 1
}

# vardnamn SVAR → värdnamnet i den form webbläsaren använder: gemener, utan
# https:// och avslutande snedstreck. CORS jämför exakt mot webbläsarens adress.
vardnamn() {
    local namn=${1,,}
    namn=${namn#http://}; namn=${namn#https://}; namn=${namn%%/*}
    printf '%s' "$namn"
}

# kontrollera_namn NAMN TLS_LÄGE – varnar för ett namn som inte kan fungera och
# erbjuder en rad i hosts-filen. Stoppar aldrig: DNS kan vara på väg. Utan det
# här startade portalen felfritt, men webbläsaren hittade den inte.
kontrollera_namn() {
    local namn=$1 tls=$2 hosts=${HOSTS_FIL:-/etc/hosts} forslag=n
    if [ "$tls" = auto ]; then
        case "$namn" in
            *.*) ;;
            *) info "  Varning: Let's Encrypt ger inga certifikat till ett namn utan punkt ($namn)."
               info "  Välj intern eller egen, eller ange ett fullständigt namn." ;;
        esac
    fi
    command -v getent >/dev/null || return 0
    getent hosts "$namn" >/dev/null && return 0
    info "  Varning: namnet $namn går inte att slå upp på den här datorn."
    info "  Portalen startar ändå, men webbläsaren hittar den inte förrän namnet finns i DNS eller i hosts-filen."
    [ "$tls" = intern ] && forslag=j
    if [ -w "$hosts" ]; then
        if ja_nej "  Lägga till \"127.0.0.1 $namn\" i $hosts, så att det fungerar på den här datorn?" "$forslag"; then
            printf '127.0.0.1 %s\n' "$namn" >> "$hosts"
            info "  Tillagt."
        fi
    else
        info "  På den här datorn:  echo \"127.0.0.1 $namn\" | sudo tee -a $hosts"
    fi
    info "  På andra datorer behövs DNS, eller en rad i deras hosts-fil med den här datorns IP-adress."
    return 0
}

# Arkitektens version, ur avbildens package.json (/health visar den inte
# längre för vem som helst).
arkitekten_version() {
    dc exec -T arkitekten node -p "require('/app/package.json').version" </dev/null 2>/dev/null
}

# Versionen som TJÄNSTEN rapporterar i /api/v1/health.
rapporterad_version() {
    dc exec -T "$1" python -c "import json, urllib.request; print(json.load(urllib.request.urlopen('http://localhost:8000/api/v1/health'))['version'])" 2>/dev/null
}

# Docker och Compose v2 måste finnas och svara.
kontrollera_docker() {
    command -v docker >/dev/null || fel "docker saknas."
    docker compose version >/dev/null 2>&1 || fel "Docker Compose v2 (docker compose) saknas."
    docker info >/dev/null 2>&1 || fel "Docker svarar inte – körs tjänsten, och får du använda den (gruppen docker)?"
}

# Releaseanteckningar per del.
RELEASES_PORTAL=https://github.com/Arkitektursamverkan/arkitekturportalen/releases
RELEASES_PLATTFORM=https://github.com/Arkitektursamverkan/integrationsplattformen/releases
RELEASES_ARKITEKTEN=https://github.com/Arkitektursamverkan/arkitekten/releases
