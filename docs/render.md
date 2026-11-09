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

Versioner: portalen 0.12.0, plattformen 0.6.0 och Arkitekten 0.7.0 eller
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
3. **Adresser.** Bestäm adresserna för portalen, plattformen och Arkitekten,
   t.ex. `arkitektur.example.org`, `plattform.example.org` och
   `arkitekten.example.org`. Då kan de fyllas i direkt när blueprinten skapas.
   Renders egna `*.onrender.com` duger för prov, men de syns först när
   tjänsterna finns (se *Skapa*, punkt 4).
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

1. I Render: **New → Blueprint**, välj repot. Render läser `render.yaml`.
2. Fyll i värdena som Render frågar efter. Render frågar **bara nu** – det som
   lämnas tomt måste läggas till för hand under tjänsten → *Environment*.

   | Tjänst | Variabel | Värde |
   |---|---|---|
   | portal-api | `CORS_ORIGINS`, `PDF_APP_BASE_URL` | portalens adress, `https://…` |
   | portal-api | `ARKITEKTEN_URL` | Arkitektens adress, `https://…` |
   | portal-api | `ALLOWED_EMAIL_DOMAINS` | e-postdomäner som får logga in |
   | portal-api | `MODULES` | t.ex. `all`, eller `calendar,governance,arkitekten` |
   | portal-web | `ARKITEKTEN_URL` | Arkitektens adress, `https://…` |
   | plattform-api | `CORS_ORIGINS` | plattformens adress, `https://…` |
   | arkitekten | `ARK_BAS_URL` | Arkitektens adress, `https://…` (tomt = onrender.com-adressen) |
   | arkitekten | `EA_WEBB_URL` | portalens adress, `https://…` |

   Entra – **samma värden på varje rad**, eller tomt överallt för egna konton:

   | Variabel | Tjänster |
   |---|---|
   | `ENTRA_TENANT_ID`, `ENTRA_CLIENT_ID` | portal-api, portal-web, plattform-api, arkitekten |
   | `ENTRA_CLIENT_SECRET` | arkitekten |
   | `BOOTSTRAP_ADMIN_EMAILS` – de som blir administratörer | portal-api, plattform-api, arkitekten |

   Hemligheterna (`API_KEY`, `LOCAL_AUTH_SECRET`, plattformens nycklar,
   `ARK_SESSION_SECRET`, engångskoden `SETUP_CODE`) skapar Render själv. De tjänster som behöver samma
   nyckel läser den från varandra.
3. **Apply.** Den första starten skapar databaserna och tar några minuter.
4. **Domäner.** Lägg till de egna domänerna under varje webbtjänst →
   *Settings → Custom Domains*, och CNAME-posterna i DNS som Render visar.
   Provar du med `*.onrender.com`: fyll nu i adresserna från punkt 2 under
   respektive tjänst → *Environment* (Render startar om tjänsten).
5. **Logga in.** Med Entra: *Logga in med Microsoft* i varje tjänst. Utan
   Entra: första besöket i portalen, plattformen och Arkitekten skapar
   administratörskontot. Det kräver **engångskoden** `SETUP_CODE`, som Render
   har skapat – den står under portal-api → *Environment* och gäller alla tre.
   (Med `BOOTSTRAP_ADMIN_EMAILS` satt får bara de adresserna skapa portalens.)

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
