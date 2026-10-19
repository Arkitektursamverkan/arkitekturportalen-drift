#!/usr/bin/env bash
# Återställer installationen från en backup (se backup.sh): databaserna,
# portalens filer, .env och versionerna som körde. Allt som hänt efter
# backupen försvinner. Nuvarande .env sparas som .env.fore-aterstallning.
#
#   ./aterstall.sh backups/20261019-030000
#   ./aterstall.sh --utan-pull backups/…   avbilderna finns redan lokalt
set -euo pipefail
cd "$(dirname "$0")"
# shellcheck source=lib/gemensamt.sh
. lib/gemensamt.sh

PULL=1
dir=""
for arg in "$@"; do
    case "$arg" in
        --utan-pull) PULL=0 ;;
        -h|--help) sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) dir=${arg%/} ;;
    esac
done
[ -n "$dir" ] || fel "Ange backupkatalogen, t.ex. ./aterstall.sh backups/20261019-030000"
[ -f "$dir/KLAR" ] || fel "$dir är ingen fullständig backup (KLAR saknas)."
kontrollera_docker

rubrik "Återställning från $dir"
info "Backupen:  portalen $(grep ^PORTAL_VERSION= "$dir/versioner" | cut -d= -f2), plattformen $(grep ^PLATTFORM= "$dir/versioner" | cut -d= -f2) ($(grep ^PLATFORM_VERSION= "$dir/versioner" | cut -d= -f2)), tagen $(cat "$dir/KLAR")"
info "Nu:        portalen $(env_get PORTAL_VERSION), plattformen $(plattform_vald && echo ja || echo nej) ($(env_get PLATFORM_VERSION))"
info "Allt som ändrats efter backupen försvinner."
printf 'Skriv återställ för att fortsätta: ' >&2
IFS= read -r svar || true
[ "$svar" = "återställ" ] || fel "Avbrutet."

if [ -f "$ENV_FILE" ]; then cp "$ENV_FILE" "$ENV_FILE.fore-aterstallning"; fi
cp "$dir/env" "$ENV_FILE"
chmod 600 "$ENV_FILE" "$ENV_FILE.fore-aterstallning" 2>/dev/null || true
if plattform_vald; then cp caddy/mallar/plattform.caddy caddy/sites/plattform.caddy; else rm -f caddy/sites/plattform.caddy; fi

if [ $PULL = 1 ]; then dc pull --quiet || fel "Avbilderna gick inte att hämta (docker login ghcr.io?)."; fi

info "Stoppar portalen och plattformen…"
dc --profile plattform stop api web plattform-api plattform-web >/dev/null 2>&1 || true
dc up -d db >/dev/null 2>&1
plattform_vald && dc up -d plattform-db >/dev/null 2>&1
vanta_db() {
    for _ in $(seq 1 30); do dc exec -T "$1" pg_isready -q && return 0; sleep 2; done
    fel "$1 startar inte."
}

# aterstall_db TJÄNST ANVÄNDARE DATABAS FIL
aterstall_db() {
    vanta_db "$1"
    dc exec -T "$1" psql -q -U "$2" -d postgres -v ON_ERROR_STOP=1 \
        -c "DROP DATABASE IF EXISTS $3 WITH (FORCE)" -c "CREATE DATABASE $3 OWNER $2" >/dev/null
    gunzip -c "$4" | dc exec -T "$1" psql -q -U "$2" -d "$3" -v ON_ERROR_STOP=1 >/dev/null
}

info "Läser tillbaka portalens databas…"
aterstall_db db ea_user ea_db "$dir/portal_db.sql.gz"
info "Läser tillbaka portalens filer…"
dc run --rm --no-deps -T api sh -c 'rm -rf /app/snapshots/* /app/sync_data/* && tar xzf - -C /app' < "$dir/portal_filer.tar.gz"
if plattform_vald && [ -f "$dir/plattform_db.sql.gz" ]; then
    info "Läser tillbaka plattformens databas…"
    aterstall_db plattform-db integration_user integration_db "$dir/plattform_db.sql.gz"
fi

info "Startar…"
dc up -d --remove-orphans >/dev/null 2>&1
dc exec -T caddy caddy reload --config /etc/caddy/Caddyfile --adapter caddyfile >/dev/null 2>&1 || dc restart caddy >/dev/null 2>&1
vanta_pa api http://localhost:8000/api/v1/health || fel "Avbrutet."
if plattform_vald; then vanta_pa plattform-api http://localhost:8000/api/v1/health || fel "Avbrutet."; fi
rubrik "Återställt"
info "Portalen kör $(rapporterad_version api)$(plattform_vald && echo ", plattformen $(rapporterad_version plattform-api)")."
