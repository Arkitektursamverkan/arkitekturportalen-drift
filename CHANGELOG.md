# Ändringslogg

Ändringarna i Arkitekturportalen – drift, nyast först. Versionerna följer
[semantisk versionering](https://semver.org/lang/sv/): en ny huvudversion
när något tas bort eller byter betydelse, en ny mindre version för nya
funktioner, en ny korrigering för rättelser.

## Ej släppt

- (inget än)

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
