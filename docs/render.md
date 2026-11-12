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

Versioner: portalen 0.16.2, plattformen 0.11.0 och Arkitekten 0.12.0 eller
senare. Med dem behövs inget steg efter starten: plattformen skapar själv
källan som hämtar Arkitektens processbilder, anmäler sin adress till portalen,
och portalen läser från plattformen med plattformens admin-nyckel.

Tjänsterna pekar bara åt ett håll – mot portal-api, som inte pekar på någon
annan (plattform-api → portal-api och arkitekten, arkitekten → portal-api,
webbarna → sina api:er). Pekade två tjänster på varandra slutade varje synk
med fel, och tjänsterna efter den skapades inte.

## Före

1. **Åtkomst till repot.** Installera Renders GitHub-app för organisationen
   (*Account Settings → GitHub*) med åtkomst till det här repot, eller lägg
   `render.yaml` i ett eget repo som Render når.
2. **Adresser.** Renders egna `*.onrender.com`-adresser duger för prov. Egna
   domäner (t.ex. `arkitektur.example.org`) läggs till efter skapandet.
3. **Entra ID (valfritt) – en app-registrering för alla tre.** Samma konto
   loggar då in i portalen, plattformen och Arkitekten. I registreringen:
   - *Authentication* – tre redirect-adresser, exakt så här (adresserna står
     överst på respektive tjänsts sida i Render när de skapats; lägg till dem
     då om du inte vet dem i förväg):

     | Tjänst | Typ i Entra | Redirect-URI |
     |---|---|---|
     | portal-web | Single-page application | `https://<portal-web>/` |
     | plattform-web | Single-page application | `https://<plattform-web>/login` – med **`/login`** |
     | arkitekten | **Web** | `https://<arkitekten>/__ark/auth/callback` |

     Det blir **två plattformar** i registreringen: *Add a platform →
     Single-page application* med portalens och plattformens adresser, och
     *Add a platform → Web* med Arkitektens. Arkitekten loggar in med
     klienthemligheten och fungerar inte om dess adress hamnar under
     Single-page application.

     Saknas en ger Microsoft felet AADSTS50011 med den adress som saknas.
   - *Expose an API*: Application ID URI `api://<client-id>` och scopet
     `access_as_user`
   - *Certificates & secrets*: en klienthemlighet (Arkitekten använder den)

   Notera tenant-id, client-id och hemligheten – de fylls i på ett ställe,
   portal-api. Utan Entra används egna konton överallt, och första besöket i
   varje tjänst skapar administratören.

## Skapa

1. **Blueprint.** I Render: **New → Blueprint** och välj repot
   **`Arkitektursamverkan/arkitekturportalen-drift`** (det här repot – det är
   `render.yaml` i dess rot som Render läser). *Blueprint Path* lämnas som
   `render.yaml`.
2. **Frågorna.** Render frågar bara efter Entra-uppgifterna, på **portal-api**,
   och bara nu.
   - **Egna konton:** lämna fälten tomma.
   - **Med Entra:** fyll i tenant-id, client-id, klienthemligheten
     (`ENTRA_CLIENT_SECRET`) och din e-post i `BOOTSTRAP_ADMIN_EMAILS` (de som
     blir administratörer). Plattformen och Arkitekten hämtar uppgifterna från
     portalen – de skrivs inte in någon annanstans.

   Allt annat sköter Render och tjänsterna själva: hemligheterna och
   engångskoderna skapas, de interna adresserna kopplas, portalen lär sig sin
   adress vid första besöket och Arkitekten anmäler sin till portalen. Alla
   moduler är påslagna (stängs av under Administration → Organisation).
3. **Deploy Blueprint.** Den första starten skapar databaserna och tar några
   minuter.
4. **Logga in.** Öppna **portal-web** (adressen står överst på tjänstens sida,
   `https://….onrender.com`). Med Entra: *Logga in med Microsoft* i varje
   tjänst. Utan Entra: första besöket i portalen, plattformen och Arkitekten
   skapar administratörskontot med **engångskoden** – den står under
   portal-api, plattform-api respektive arkitekten → *Environment* →
   `SETUP_CODE`.

Länken till Arkitekten i portalens toppfält och länken tillbaka till portalen
i Arkitektens publiceringsruta dyker upp av sig själva: Arkitekten anmäler sin
adress när den startar, och portalens adress blir känd när någon öppnat
portalen första gången.

**Egna domäner** läggs till under varje webbtjänst → *Settings → Custom
Domains* (och CNAME-posterna i DNS som Render visar). Portalen byter själv
till den egna domänen när den används. Arkitekten behöver sin i `ARK_BAS_URL`
(arkitekten → *Environment*, t.ex. `https://arkitekten.example.org`) –
inloggningen bygger sina adresser av den.

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
- Ändras Entra-uppgifterna på portal-api hämtar plattformen dem inom fem
  minuter; Arkitekten läser dem när den startar – starta om arkitekten.
- Byts `ENCRYPTION_KEY` på plattform-api blir sparade inloggningar till
  källsystemen oläsbara.
