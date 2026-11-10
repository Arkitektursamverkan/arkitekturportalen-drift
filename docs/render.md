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

Versioner: portalen 0.14.0, plattformen 0.8.0 och Arkitekten 0.9.0 eller
senare. Med dem behövs inget steg efter starten: plattformen skapar själv
källan som hämtar Arkitektens processbilder, och portalen läser från
plattformen med plattformens admin-nyckel.

## Före

1. **Registerinloggning.** Avbilderna i `ghcr.io/arkitektursamverkan` är
   privata. Skapa en GitHub-token (classic) med `read:packages`, och lägg in den
   i Render under *Workspace Settings → Registry Credentials*: registret
   *GitHub*, användarnamnet för token och namnet **`ghcr`**.
2. **Åtkomst till repot.** Installera Renders GitHub-app för organisationen
   (*Account Settings → GitHub*) med åtkomst till det här repot, eller lägg
   `render.yaml` i ett eget repo som Render når.
3. **Adresser.** Renders egna `*.onrender.com`-adresser duger för prov. Egna
   domäner (t.ex. `arkitektur.example.org`) läggs till efter skapandet.
4. **Entra ID (valfritt) – en app-registrering för alla tre.** Samma konto
   loggar då in i portalen, plattformen och Arkitekten. I registreringen:
   - *Authentication → Single-page application*: `https://<portalen>/` och
     `https://<plattformen>/login`
   - *Authentication → Web*: `https://<Arkitekten>/__ark/auth/callback`
   - *Expose an API*: Application ID URI `api://<client-id>` och scopet
     `access_as_user`
   - *Certificates & secrets*: en klienthemlighet (Arkitekten använder den)

   Notera tenant-id, client-id och hemligheten. Utan Entra används egna konton
   överallt, och första besöket i varje tjänst skapar administratören.

## Skapa

1. **Blueprint.** I Render: **New → Blueprint** och välj repot
   **`Arkitektursamverkan/arkitekturportalen-drift`** (det här repot – det är
   `render.yaml` i dess rot som Render läser). *Blueprint Path* lämnas som
   `render.yaml`.
2. **Frågorna.** Render frågar efter några värden, och bara nu.
   - **Egna konton (enklast för ett prov):** lämna ALLA fält tomma.
   - **Med Entra:** fyll i samma tenant-id och client-id på varje rad där de
     frågas efter, `ENTRA_CLIENT_SECRET` på arkitekten och din e-post i
     `BOOTSTRAP_ADMIN_EMAILS` (de som blir administratörer).
   - Adressfälten (`PDF_APP_BASE_URL`, `ARKITEKTEN_URL`, `EA_WEBB_URL`) lämnas
     tomma – de fylls i i punkt 4, när adresserna finns.

   Allt annat sköter Render: hemligheterna och engångskoderna skapas, de
   interna adresserna mellan tjänsterna kopplas, och alla moduler är påslagna
   (stängs av under Administration → Organisation).
3. **Deploy Blueprint.** Den första starten skapar databaserna och tar några
   minuter.
4. **Adresserna.** Öppna **portal-web** och **arkitekten** i Render och
   kopiera deras adresser (överst på tjänstens sida, `https://….onrender.com`).
   Fyll sedan i under respektive tjänst → *Environment* → *Save* (tjänsten
   startar om):

   | Tjänst | Variabel | Värde |
   |---|---|---|
   | portal-api | `PDF_APP_BASE_URL` | portal-webs adress |
   | portal-api | `ARKITEKTEN_URL` | arkitektens adress |
   | portal-web | `ARKITEKTEN_URL` | arkitektens adress |
   | arkitekten | `EA_WEBB_URL` | portal-webs adress |

   Med egna domäner: lägg först till dem under varje webbtjänst → *Settings →
   Custom Domains* (och CNAME-posterna i DNS som Render visar), använd dem i
   tabellen och sätt dessutom `ARK_BAS_URL` (Arkitektens adress) på
   arkitekten.
5. **Logga in.** Med Entra: *Logga in med Microsoft* i varje tjänst. Utan
   Entra: första besöket i portalen, plattformen och Arkitekten skapar
   administratörskontot med **engångskoden** – den står under portal-api,
   plattform-api respektive arkitekten → *Environment* → `SETUP_CODE`.

Exempelinnehåll:

- **Arkitekten**: *Inställningar → Exempelinnehåll* i Arkitekten.
- **Portalen**: i portal-api → *Shell*:
  `python -m app.services.content_pack list` och
  `python -m app.services.content_pack import <paket>`.

## Synk till portalen efter körning

En flödes webhook "efter körning" i plattformen går till portalens api över
det interna nätet: `http://<portal-api:s interna host:port>/api/v1/sync/webhook`
(portal-api → *Connect → Internal*).

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
