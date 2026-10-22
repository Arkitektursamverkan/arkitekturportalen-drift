# Arkitekturportalen – drift

Installera och drifta Arkitekturportalen (och, om du vill,
Integrationsplattformen) på en egen server med Docker. Allt körs från färdiga
avbilder; inget byggs på servern.

| Del | Avbild |
|---|---|
| Portalen | `arkitekturportalen-api`, `arkitekturportalen-web` |
| Integrationsplattformen (valfri) | `integrationsplattformen-api`, `integrationsplattformen-web` |
| TLS | `caddy` – Let's Encrypt, eget certifikat eller intern CA |
| Databaser | `postgres:16-alpine`, `redis:7-alpine` |

Bara Caddy publicerar portar (80 och 443). Databaserna och API:erna nås bara
inne i Docker-nätet.

## Krav

- Linux-server med Docker Engine 24+ och Compose v2 (`docker compose`).
- Ett DNS-namn för portalen (och ett för plattformen om den används) som pekar
  på servern.
- Certifikat: antingen når servern internet på port 80 och 443 (Let's
  Encrypt), eller så har organisationen ett eget certifikat.
- Docker installeras av installationsfilen om det saknas (Ubuntu, Debian,
  RHEL och liknande).

## Installera

1. Gå till [Releases](https://github.com/Arkitektursamverkan/arkitekturportalen-drift/releases)
   och ladda ner filen `arkitekturportalen-<version>.run` under den senaste
   versionen.
2. Kopiera filen till servern (till exempel med WinSCP).
3. Kör den på servern:

   ```sh
   sudo sh arkitekturportalen-<version>.run
   ```

Filen innehåller allt: skripten och själva programmet. Inget annat behöver
hämtas och ingen inloggning behövs. Saknar servern Docker erbjuder filen att
installera det. Portalen hamnar i `/opt/arkitekturportalen`.

Samma fil uppgraderar: körs en nyare `.run` på en server där portalen redan
finns tas en backup och den nya versionen startas (se [Uppgradera](#uppgradera)).

Testa på en dator utan DNS-namn: svara `localhost` som värdnamn och `intern`
som TLS-läge, och öppna https://localhost (webbläsaren varnar för
certifikatet).

Guiden frågar efter

- portalens värdnamn och hur certifikatet ordnas (`auto`, `egen`, `intern`),
- organisationens namn och vilka e-postdomäner som får logga in,
- Microsoft Entra ID (valfritt) och vem som blir administratör, och/eller ett
  lokalt administratörskonto,
- om objekten får läsas utan inloggning,
- vilka moduler som ska vara på (standard: bara kärnan),
- om Integrationsplattformen ska ingå,
- vilka exempelpaket som ska läsas in (bara för moduler som är på).

Sedan skapar den alla hemligheter, skriver `.env`, hämtar avbilderna, startar
allt, skapar administratören och plattformens läsnyckel för portalen och läser
in exempelpaketen.

Guiden går att köra igen för att ändra något: värdena i `.env` blir förslag
och befintliga hemligheter behålls. Väljs plattformen bort stoppas den, men
dess data ligger kvar.

**Entra ID:** skapa först en appregistrering (SPA) med redirect-URI
`https://<portalens värdnamn>/` och ett exponerat API-scope `access_as_user`.

**Eget certifikat:** lägg certifikatet (med hela kedjan) och nyckeln i
`certs/` innan du kör guiden.

### För hand

Allt guiden gör går att göra själv: kopiera `.env.example` till `.env`, fyll i
den (hemligheter: `openssl rand -hex 32`) och kör `docker compose up -d`. Med
Integrationsplattformen: `COMPOSE_PROFILES=plattform`,
`INTEGRATION_PLATFORM_URL`, `PLATFORM_HOST` och plattformens hemligheter, och
`cp caddy/mallar/plattform.caddy caddy/sites/`. Ett flödes webhook "efter
körning" till portalen är `http://api:8000/api/v1/sync/webhook`.

Exempelinnehåll:

```sh
docker compose exec api python -m app.services.content_pack list
docker compose exec api python -m app.services.content_pack import <paket>
```

## Uppgradera

Enklast: ladda ner den nya `.run`-filen och kör den som vid installationen.
Den gör samma sak som `uppgradera.sh` nedan.

Med skriptet, om servern själv får hämta avbilderna från ghcr.io:

```sh
./uppgradera.sh 0.2.0          # portalen
./uppgradera.sh 0.2.0 0.1.2    # portalen och plattformen
./uppgradera.sh                # frågar
```

Läs releaseanteckningarna först
([portalen](https://github.com/Arkitektursamverkan/arkitekturportalen/releases),
[plattformen](https://github.com/Arkitektursamverkan/integrationsplattformen/releases)).
Skriptet

1. hämtar de nya avbilderna – går det inte är inget ändrat,
2. tar en backup (`backups/<tid>-fore-<version>`, med plattformen `fore-<portal>_<plattform>`),
3. byter version i `.env` och startar om; portalen migrerar databasen när
   den startar,
4. kontrollerar att portalen (och plattformen) svarar med den nya versionen.

Går något fel skriver det ut hur du kommer tillbaka:
`./aterstall.sh backups/<tid>-fore-<version>`.

Databasmigreringar går bara framåt, så skriptet vägrar en äldre version.
Tillbaka till en äldre version = återställ en backup från den versionen.

## Backup och återställning

```sh
./backup.sh                    # backups/<tid>/
./aterstall.sh backups/<tid>   # tillbaka till det läget
```

En backup innehåller portalens databas och filer (ögonblicksbilder,
synkprofiler), plattformens databas, en kopia av `.env` och versionerna. Den
räknas bara som fullständig när filen `KLAR` finns. `BACKUP_BEHALL` i `.env`
(standard 14) styr hur många som sparas.

Varje natt, med cron (`crontab -e`):

```
0 3 * * * cd /sökväg/till/arkitekturportalen && ./backup.sh >> backups/backup.log 2>&1
```

`backups/` ligger på samma server – kopiera dem regelbundet någon annanstans.
De innehåller hemligheterna (`env`), så förvara dem som lösenord.

`aterstall.sh` frågar innan det skriver över något. Det återställer
databaserna, filerna, `.env` och versionerna som körde (nuvarande `.env`
sparas som `.env.fore-aterstallning`) och startar allt igen. Allt som
ändrats efter backupen försvinner.

## Filer

| Fil | Vad |
|---|---|
| `installera.sh` | Installationsguiden. |
| `uppgradera.sh` | Ny version, med backup först. |
| `backup.sh`, `aterstall.sh` | Backup och återställning. |
| `bygg-installationsfil.sh` | För underhållarna: bygger `.run`-filen och releasen. |
| `lib/installationsfil.sh` | Början av `.run`-filen: packar upp och startar guiden. |
| `compose.yml` | Alla tjänster. Ändras inte per installation. |
| `.env` | Installationens inställningar och hemligheter (inte i git). |
| `caddy/Caddyfile` | TLS-lägena. |
| `caddy/sites/` | Aktiva webbplatser; `caddy/mallar/` har de valfria. |
| `certs/` | Eget certifikat (inte i git). |
| `backups/` | Backuperna (inte i git). |
| `lib/gemensamt.sh` | Det skripten delar. |

Licens: [EUPL-1.2](LICENSE) – European Union Public Licence, finns på alla EU:s
officiella språk, även svenska.
