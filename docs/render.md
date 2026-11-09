# Installera på Render

[Render](https://render.com) kör färdiga avbilder som hanterade tjänster.
Installationsguiden (`installera.sh`) och docker compose används inte där.
I stället beskriver `render.yaml` i det här repot hela installationen som en
*Blueprint*: Render skapar tjänsterna, databaserna och diskarna och kopplar ihop
dem.

| Del | På Render |
|---|---|
| `portal-web`, `plattform-web`, `arkitekten` | Web Service – publik adress och TLS från Render |
| `portal-api`, `plattform-api` | Private Service – nås bara på Renders interna nät |
| `portal-db`, `plattform-db` | Render Postgres 16 |
| Ögonblicksbilder, synkprofiler | Disk på `portal-api` (`/var/data`) |
| Arkitektens innehåll | Disk på `arkitekten` (`/data`) |

Caddy behövs inte (Render sköter TLS), och inte heller plattformens Redis.
Arkitektens flödestjänst kör i samma tjänst som Arkitekten
(`ARK_FLODESTJANST_PORT=8200`), eftersom en disk bara kan höra till en tjänst.

Versioner: portalen 0.9.1, plattformen 0.3.1 och Arkitekten 0.4.0 eller
senare. Tidigare versioner går inte att köra på Render.

## Före

1. **Registerinloggning.** Avbilderna i `ghcr.io/arkitektursamverkan` är
   privata. Skapa en GitHub-token (classic) med `read:packages`, och lägg in den
   i Render under *Workspace Settings → Registry Credentials*: registret
   *GitHub*, användarnamnet för token och namnet **`ghcr`**.
2. **Åtkomst till repot.** Blueprinten läses ur det här repot. Ge Render
   åtkomst till det via GitHub (*Account Settings → GitHub*), eller lägg
   `render.yaml` i ett eget repo som Render når.
3. **Domäner.** Bestäm adresserna för portalen, plattformen och Arkitekten.
   Renders egna `*.onrender.com` fungerar också för prov.
4. **Entra ID (valfritt).** Samma appregistrering som för en vanlig
   installation (se README), med redirect-URI:n `https://<portalens adress>/`.

## Skapa

1. I Render: **New → Blueprint**, välj repot. Render läser `render.yaml`.
2. Fyll i värdena som Render frågar efter:

   | Tjänst | Variabel | Värde |
   |---|---|---|
   | portal-api | `CORS_ORIGINS`, `PDF_APP_BASE_URL` | portalens adress, `https://…` |
   | portal-api | `ENTRA_TENANT_ID`, `ENTRA_CLIENT_ID` | tomma = bara lokala konton |
   | portal-api | `ALLOWED_EMAIL_DOMAINS` | e-postdomäner som får logga in |
   | portal-api | `BOOTSTRAP_ADMIN_EMAILS` | de som blir administratörer (Entra) |
   | portal-api | `MODULES` | t.ex. `all`, eller `calendar,governance,arkitekten` |
   | portal-api | `ARKITEKTEN_URL` | Arkitektens adress, `https://…` |
   | portal-web | `ENTRA_TENANT_ID`, `ENTRA_CLIENT_ID` | samma som på portal-api |
   | portal-web | `ARKITEKTEN_URL` | Arkitektens adress, `https://…` |
   | plattform-api | `CORS_ORIGINS` | plattformens adress, `https://…` |
   | arkitekten | `ARK_BAS_URL` | Arkitektens adress, `https://…` |
   | arkitekten | `EA_WEBB_URL` | portalens adress, `https://…` |
   | arkitekten | `ARK_ADMINS` | samma som `BOOTSTRAP_ADMIN_EMAILS` |

   Adresserna får tjänsterna först när de skapats. Lämna dem tomma första
   gången och fyll i dem under respektive tjänst → *Environment* efteråt.

   Hemligheterna (`API_KEY`, `LOCAL_AUTH_SECRET`, plattformens nycklar,
   `ARK_SESSION_SECRET`) skapar Render själv. De tjänster som behöver samma
   nyckel läser den från varandra.
3. **Apply.** Den första starten skapar databaserna och tar några minuter.
4. Lägg till de egna domänerna under varje webbtjänst → *Settings → Custom
   Domains*, och CNAME-posterna i DNS som Render visar.

## Efter första starten

`render/efter-start.py` gör det som installationsguiden annars gör efter
starten. Kör det från vilken dator som helst med Python 3, i repots katalog:

```sh
python3 render/efter-start.py
```

Det frågar efter adresserna och nycklarna (nycklarna syns inte när de klistras
in). Samma värden går också att ge som flaggor, se `--help`.

- `ADMIN_API_KEY` finns under plattform-api → *Environment*, `API_KEY` under
  portal-api → *Environment*.
- Arkitektens interna namn står under arkitekten → *Connect → Internal*
  (bara namnet, utan port).
- `--admin-epost` behövs bara för ett lokalt administratörskonto. Med Entra
  blir de i `BOOTSTRAP_ADMIN_EMAILS` administratörer när de loggar in.

Skriptet skriver ut plattformens läsnyckel för portalen. Lägg in den på
portal-api → *Environment* som **`INTEGRATION_PLATFORM_API_KEY`**. Render
startar då om api:t.

Exempelinnehåll:

- **Arkitekten**: *Inställningar → Exempelinnehåll* i Arkitekten.
- **Portalen**: i portal-api → *Shell*:
  `python -m app.services.content_pack list` och
  `python -m app.services.content_pack import <paket>`.

## Synk till portalen efter körning

En flödes webhook "efter körning" i plattformen går till portalens api över
det interna nätet: `http://<portal-api:s interna host:port>/api/v1/sync/webhook`
(portal-api → *Connect → Internal*).

## Entra ID i Arkitekten

Arkitekten börjar med lokala konton (`ARK_AUTH=lokal`, där första besöket
skapar administratören). För Entra: sätt på arkitekten → *Environment*
`ARK_AUTH=entra`, `ENTRA_TENANT_ID`, `ENTRA_CLIENT_ID` och
`ENTRA_CLIENT_SECRET`, och lägg till redirect-URI:n (Webb)
`https://<Arkitektens adress>/__ark/auth/callback` i appregistreringen. Se
Arkitektens `docs/inloggning.md`.

## Uppgradera

Byt versionerna i `render.yaml` (eller avbildens tagg under respektive tjänst
→ *Settings → Image*) och synka blueprinten. Api:erna kör sina
databasmigreringar själva när de startar.

## Backup

Render Postgres har egna säkerhetskopior (beroende på plan). Diskarna har
dagliga ögonblicksbilder i Render. `backup.sh` och `aterstall.sh` hör till
compose-installationen och används inte här.

## Att känna till

- En tjänst med disk kör en instans, och vid en ny driftsättning blir den
  borta en kort stund.
- Integrationsplattformen når bara källsystem som går att nå från Render, det
  vill säga över internet.
- Byts `ENCRYPTION_KEY` på plattform-api blir sparade inloggningar till
  källsystemen oläsbara.
