# Ändringslogg

Ändringarna i Arkitekturportalen – drift, nyast först. Versionerna följer
[semantisk versionering](https://semver.org/lang/sv/): en ny huvudversion
när något tas bort eller byter betydelse, en ny mindre version för nya
funktioner, en ny korrigering för rättelser.

## Ej släppt

- **Manualerna**: ny installationsmanual för Render (`docs/render-manual.html`), och installationsmanualen och broschyren uppdaterade till 0.16.1 (engångskoden, hur den första administratören blir till, `CONNECTOR_ALLOWED_HOSTS`, sex moduler). `bygg-installationsfil.sh` bygger PDF:erna och bifogar dem releasen med fasta namn; README länkar till dem under *Dokumentation*.
- `uppgradera.sh` skapar `SETUP_CODE` och (med Arkitekten) `ARKITEKTEN_FLODESTJANST_NYCKEL` när de saknas i en äldre installation.
- **Avbilderna är publika**: ingen registerinloggning behövs längre. `render.yaml` har inte längre `fromRegistryCreds: ghcr` (Renders *Registry Credential* kan tas bort), och `docs/render.md`, `installera.sh` och `uppgradera.sh` ber inte längre om `docker login ghcr.io`.
- **Render**: `render.yaml` (Blueprint) installerar portalen, Integrationsplattformen och Arkitekten på Render med samma avbilder – Render Postgres, diskar och Renders TLS i stället för Caddy. Inget steg efter starten: plattformen skapar Arkitektens källa själv, portalen läser med plattformens admin-nyckel och första besöket skapar administratören. En gemensam Entra-registrering för alla tre (frågas per tjänst; tomt = egna konton). Guide: `docs/render.md`. Kräver portalen 0.12.0, plattformen 0.6.0 och Arkitekten 0.7.0.
- **Engångskod för första administratören** (`SETUP_CODE`): installationsguiden skapar den och skriver ut den, och compose ger den till portalen, plattformen och Arkitekten. På Render skapar Render den på portal-api och de andra hämtar den därifrån. Utan den går inget första konto att skapa i en ny installation.
- **Nyckel mellan Arkitektens flödestjänst och plattformen** (`ARK_FLODESTJANST_NYCKEL`): installationsguiden skapar den, compose ger den till båda; på Render skapas den på arkitekten och plattformen hämtar den. Render-blueprinten sätter också `ARK_BETRODD_PROXY` och `TRUST_PROXY_HEADERS`, så spärrarna mot lösenordsgissning ser klientens adress.
- **Säkerhetsversionerna**: compose (`.env.example`) och `render.yaml` på portalen 0.13.0, Integrationsplattformen 0.7.0 och Arkitekten 0.8.0. **Uppgradera portalen före plattformen** – plattformen 0.7.0 signerar webhooken och en äldre portal avvisar den.
- **Plattformens kopplingar når inte interna adresser** utan `CONNECTOR_ALLOWED_HOSTS` (värdnamn, `*.domän`, IP eller CIDR). Hämtar plattformen från interna källsystem: sätt den i `.env` före uppgraderingen. Flödestjänstens adress (`PLATFORM_ARKITEKTEN_URL`, `http://arkitekten-flodestjanst:8200`) sätts av guiden och av `uppgradera.sh`; Arkitektens nyckel skickas bara dit.
- **Klientens adress bakom Caddy**: compose sätter `TRUSTED_PROXY` på båda webbarna (Docker-näten), `TRUST_PROXY_HEADERS` på plattformens API och `ARK_BETRODD_PROXY=1` på Arkitekten, så att gränserna för inloggningsförsök gäller per klient och inte för alla på en gång. På Render sätts `TRUSTED_PROXY` (Renders interna nät) på portal-web och plattform-web.
- **Render: egen engångskod per tjänst** (`SETUP_CODE` på portal-api, plattform-api och arkitekten).
- Nya valfria inställningar: `INTEGRATION_PLATFORM_ALLOWED_URLS` (portalen), `CONNECTOR_BLOCK_INTERNAL` (plattformen).
- **Render: synken slutade alltid med fel.** `databaseName` och `user` är borttagna ur `render.yaml`: Render ger databasen ett eget suffix (`ea_db_46gd`), namnet går inte att ändra, och varje synk misslyckades och avbröt det som återstod. Guiden visar redirect-adresserna i en tabell (plattformens slutar på `/login`).
- **Render: rättningar efter första provet** – `PORT=8000` på portal-api och plattform-api (annars fick de andra tjänsterna port 10000 i den interna adressen när allt skapades samtidigt) och portalen 0.15.1 (lär sig inte längre den privata tjänstens namn ur Renders kontroll).
- **Render utan inmatning**: `render.yaml` frågar bara efter Entra-uppgifterna, på portal-api (tomma = egna konton). Plattformen och Arkitekten hämtar dem från portalen, portalen lär sig sin adress och Arkitekten anmäler sin – `PDF_APP_BASE_URL`, `ARKITEKTEN_URL` och `EA_WEBB_URL` fylls inte längre i. Guiden `docs/render.md` är förkortad därefter. Portalen 0.15.0, Integrationsplattformen 0.9.0 och Arkitekten 0.10.0 (också i compose, där allt är som förut).
- **Säkerhetsomgång 4**: compose och `render.yaml` på portalen 0.14.0, Integrationsplattformen 0.8.0 och Arkitekten 0.9.0 – återkallbara inloggningar, spärrade konton, Entra-gäster nekas, inga standardlösenord för databaserna. Installationer gjorda med guiden har redan egna lösenord.
- **Arkitektens ärendetyper** (`ARKITEKTEN_ARENDETYPER`): Arkitekten 0.9.0 har ingen inbyggd indelning av processmenyn längre. Sätt listan i `.env` för att dela in menyn efter ärendetyp.
- `uppgradera.sh` läser Arkitektens version ur avbildens `package.json` i stället för `/health`.
- Arkitektens exempelprocesser läggs in som användaren `node` (`exec -u node`), så att filerna ägs av den som Arkitekten kör som.

## 0.6.0 – 2026-11-02

- Installationsfilen med portalen 0.6.0, Integrationsplattformen 0.2.3 och Arkitekten 0.3.2: portalens namn går att ändra, listor går att stänga av och egna listor går att lägga till, under Administration.
- Installationsmanualen: avsnittet Anpassa portalen till organisationen.
- Installationsmanualen och broschyren: version 0.6.0.

## 0.5.2 – 2026-11-02

- Installationsfilen med portalen 0.5.2, Integrationsplattformen 0.2.3 och Arkitekten 0.3.2: *Ladda demodata* fungerar i en portal utan objekt.
- Installationsmanualen och broschyren: version 0.5.2.

## 0.5.1, tillägg – 2026-11-02

Samma version av portalen och samma avbilder; installationsfilen i releasen v0.5.1 är ombyggd:

- Guiden kontrollerar värdnamnen. Går ett namn inte att slå upp varnar den och erbjuder en rad i `/etc/hosts`, i läget `auto` varnar den också för ett namn utan punkt. Namnet skrivs med gemener och utan `https://`.
- Sista sidan säger att hela adressen ska användas, och att webbläsaren varnar för certifikatet i läget `intern`.
- Installationsmanualen och README: test utan DNS-namn.

## 0.5.1 – 2026-11-02

- Installationsfilen med portalen 0.5.1, Integrationsplattformen 0.2.3 och Arkitekten 0.3.2: Python 3.14 och Node 26, ny Anthropic-SDK i Arkitekten och en tömd bana som står kvar under redigeringen.
- Installationsmanualen och broschyren: version 0.5.1.

## 0.5.0 – 2026-11-02

- Installationsfilen med portalen 0.5.0, Integrationsplattformen 0.2.2 och Arkitekten 0.3.1: PDF-visare i portalen, rättad Neo4j-skrivning och uppdaterade beroenden.
- En fil för allt: installationsfilen installerar, uppgraderar och avinstallerar. Finns portalen redan på servern frågar den vad som ska göras – uppgradera (eller, med samma version, ändra inställningarna), avinstallera eller avbryta. `--avinstallera` går direkt till avinstallationen. Den separata `arkitekturportalen-avinstallation.run` byggs inte längre. Den är borttagen från releasen v0.4.0 (2026-10-27).
- Installationsmanualen: den valfria Graph-behörigheten `Files.Read.All` för portalens PDF-visare.
- En installationsfil som är äldre än den installerade versionen avslutas inte längre direkt, utan kan användas för att avinstallera.
- Installationsmanualen och broschyren: version 0.5.0.

## 0.4.0, tillägg – 2026-10-26

Samma installationsfil; releasen v0.4.0 har fått:

- Avinstallation: `arkitekturportalen-avinstallation.run` bifogas releasen (och `avinstallera.sh` finns i installationen). Den visar vad som finns, erbjuder en sista backup och att spara backuperna utanför installationen, och tar sedan bort tjänsterna, datan, avbilderna, cron-raderna för backup och `/opt/arkitekturportalen` – först när man skrivit `avinstallera`. Docker lämnas kvar.
- Installationsmanualen och README: avsnittet Avinstallera.

## 0.4.0 – 2026-10-26

- Installationsfilen med portalen 0.4.0, Integrationsplattformen 0.2.1 och Arkitekten 0.3.1.
- Ny valbar modul Förändringsstatistik (`changes`): installationsguiden frågar efter den, och manualen och broschyren beskriver den.
- Installationsmanualen och broschyren: version 0.4.0.

## 0.3.2 – 2026-10-26

- Installationsfilen med portalen 0.3.2, Integrationsplattformen 0.2.1 och Arkitekten 0.3.1: rättad MSAL-inloggning (MSAL 5) och uppdaterade beroenden, bland annat Vite 8, react-router 7 och SQLAlchemy 2.1.
- Installationsmanualen och broschyren: version 0.3.2.

## 0.3.1 – 2026-10-23

- Installationsfilen med portalen 0.3.1, Integrationsplattformen 0.2.1 och Arkitekten 0.3.0: uppdaterade beroenden (bland annat React 19 och MUI 9) och organisationens namn, logotyp och profilfärg i Arkitekten, hämtade ur portalens organisationsinställningar.
- Installationsmanualen och broschyren: version 0.3.1.

## 0.3.0 – 2026-10-23

- Arkitekten som valbar del i installationen (profilen `arkitekten`, bara med plattformen): eget värdnamn, inloggning, valfri AI-nyckel, modulen och källan i plattformen samt exempelprocesserna. Uppgradering, backup och återställning tar med Arkitekten.
- Installationsfilen innehåller Arkitektens avbild (`bygg-installationsfil.sh <portal> <plattform> <arkitekten>`); en ny installation frågar inte efter dess version.
- Installationsmanualen och broschyren: Arkitekten som modul (fråga 10 i installationen), version 0.3.0.

## 0.2.1 – 2026-10-22

- Första versionen: installationsguiden, uppgradering, backup och återställning, Integrationsplattformen som valbar profil och en installationsfil att ladda ner.
