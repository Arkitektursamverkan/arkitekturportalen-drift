#!/usr/bin/env bash
# Backup av installationen till backups/<tid>[-<anledning>]/:
#   portal_db.sql.gz      portalens databas
#   portal_filer.tar.gz   ögonblicksbilder och synkprofiler
#   plattform_db.sql.gz   plattformens databas (om den är vald)
#   arkitekten.tar.gz     Arkitektens innehåll: processer, visualiseringar,
#                         stilar och konton (om Arkitekten är vald)
#   env                   kopia av .env – nycklarna som krävs för att läsa datan
#   versioner             versionerna som körde
#   KLAR                  skrivs sist; utan den är backupen ofullständig
#
#   ./backup.sh                 t.ex. varje natt från cron
#   ./backup.sh fore-ändring    med en anledning i katalognamnet
#
# BACKUP_BEHALL (standard 14) i .env: så många backuper sparas, äldst tas bort.
# Katalogen innehåller hemligheter – flytta kopior till en säker plats.
set -euo pipefail
cd "$(dirname "$0")"
# shellcheck source=lib/gemensamt.sh
. lib/gemensamt.sh

case "${1:-}" in -h|--help) sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;; esac
kontrollera_docker
[ -f "$ENV_FILE" ] || fel "Ingen .env – kör ./installera.sh först."

anledning=${1:-}
namn=$(date +%Y%m%d-%H%M%S)${anledning:+-$anledning}
umask 077
mkdir -p backups
dir=backups/$namn
mkdir "$dir"

info "Backup till $dir"
dc exec -T db pg_dump -U ea_user -d ea_db | gzip > "$dir/portal_db.sql.gz"
dc exec -T api tar czf - -C /app snapshots sync_data > "$dir/portal_filer.tar.gz"
if plattform_vald; then
    dc exec -T plattform-db pg_dump -U integration_user -d integration_db | gzip > "$dir/plattform_db.sql.gz"
fi
if arkitekten_vald; then
    dc exec -T arkitekten tar czf - -C /data . > "$dir/arkitekten.tar.gz"
fi
cp "$ENV_FILE" "$dir/env"
{
    echo "PORTAL_VERSION=$(env_get PORTAL_VERSION)"
    echo "PLATFORM_VERSION=$(env_get PLATFORM_VERSION)"
    echo "PLATTFORM=$(plattform_vald && echo ja || echo nej)"
    echo "ARKITEKTEN_VERSION=$(env_get ARKITEKTEN_VERSION)"
    echo "ARKITEKTEN=$(arkitekten_vald && echo ja || echo nej)"
} > "$dir/versioner"
date -Iseconds > "$dir/KLAR"

behall=$(env_get BACKUP_BEHALL); behall=${behall:-14}
# Äldst först; bara fullständiga backuper räknas och tas bort.
mapfile -t alla < <(find backups -mindepth 2 -maxdepth 2 -name KLAR | sed 's|/KLAR$||' | sort)
if [ "${#alla[@]}" -gt "$behall" ]; then
    for gammal in "${alla[@]:0:${#alla[@]}-behall}"; do
        rm -rf "$gammal"
        info "Tog bort $gammal"
    done
fi
info "Klar: $dir ($(du -sh "$dir" | cut -f1))"
printf '%s\n' "$dir"
