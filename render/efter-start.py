#!/usr/bin/env python3
"""Det installationsguiden gör efter starten – för en installation på Render.

Körs EN gång från vilken dator som helst, när tjänsterna i render.yaml är
igång. Talar med tjänsterna via deras publika adresser (plattformens webb
skickar /api vidare till plattformens api). Bara Pythons standardbibliotek.

  python3 render/efter-start.py \\
      --plattform https://plattform.example.org --plattform-nyckel <ADMIN_API_KEY> \\
      --arkitekten-intern arkitekten-abcd \\
      [--portal https://arkitektur.example.org --portal-nyckel <API_KEY> \\
       --admin-namn "Anna Admin" --admin-epost anna@example.org]

Nycklarna finns i Render under respektive tjänst → Environment. Det interna
namnet på Arkitekten står under tjänsten → Connect → Internal (utan port).

Gör, och hoppar över det som redan finns:
1. Plattformens läsnyckel för portalen – skrivs ut, och läggs sedan in som
   INTEGRATION_PLATFORM_API_KEY på portal-api (Render startar om den).
2. Källan i plattformen som hämtar Arkitektens publicerade processbilder
   varannan timme (med --arkitekten-intern).
3. Ett lokalt administratörskonto i portalen (med --admin-epost). Lösenordet
   frågas efter; tomt = ett genereras och skrivs ut.
"""
from __future__ import annotations

import argparse
import getpass
import json
import secrets
import sys
import urllib.error
import urllib.request


def anrop(bas: str, nyckel: str, väg: str, data=None, metod: str = "GET"):
    req = urllib.request.Request(
        bas.rstrip("/") + "/api/v1" + väg,
        method=metod,
        data=json.dumps(data).encode() if data is not None else None,
        headers={"Content-Type": "application/json", "X-API-Key": nyckel},
    )
    with urllib.request.urlopen(req, timeout=60) as svar:
        kropp = svar.read()
    return json.loads(kropp) if kropp else None


def läsnyckel(plattform: str, nyckel: str) -> None:
    befintliga = [k for k in anrop(plattform, nyckel, "/api-keys") if k.get("name") == "Arkitekturportalen"]
    if befintliga:
        print("Plattformen har redan en nyckel som heter Arkitekturportalen – ingen ny skapas.")
        print("  Har portalen inte fått den: ta bort den i plattformen och kör skriptet igen.")
        return
    ny = anrop(plattform, nyckel, "/api-keys", {"name": "Arkitekturportalen", "scopes": ["data:read"]}, "POST")
    print("Portalens läsnyckel i plattformen är skapad. Lägg in den på portal-api i Render:")
    print(f"  INTEGRATION_PLATFORM_API_KEY={ny['key']}")


def arkitekten_källa(plattform: str, nyckel: str, intern: str) -> None:
    ark = {c["id"] for c in anrop(plattform, nyckel, "/connections") if c.get("connector_type") == "arkitekten"}
    if ark:
        print("Arkitektens källa i plattformen finns redan.")
        return
    värd = intern.split("://")[-1].split(":")[0].rstrip("/")
    c = anrop(plattform, nyckel, "/connections", {
        "name": "Arkitekten", "connector_type": "arkitekten",
        "description": "Publicerade processbilder från Arkitekten",
        "config": {"base_url": f"http://{värd}:8200", "familj": "alla",
                   "endast_publicerade": True, "version": "fastslagen"},
    }, "POST")
    f = anrop(plattform, nyckel, "/flows", {"name": "Arkitekten – processbilder till portalen", "connection_id": c["id"]}, "POST")
    anrop(plattform, nyckel, "/schedules", {"flow_id": f["id"], "cron_expression": "0 */2 * * *"}, "POST")
    print(f"Arkitektens källa i plattformen är skapad (http://{värd}:8200, hämtar varannan timme).")


def administratör(portal: str, nyckel: str, namn: str, epost: str) -> None:
    lösen = getpass.getpass("Lösenord för administratören, minst 8 tecken (tomt = ett genereras): ")
    genererat = not lösen
    if genererat:
        lösen = secrets.token_urlsafe(12)
    elif len(lösen) < 8:
        sys.exit("Lösenordet är kortare än 8 tecken.")
    try:
        anrop(portal, nyckel, "/users", {"name": namn, "email": epost, "password": lösen, "role": "admin"}, "POST")
    except urllib.error.HTTPError as e:
        if e.code == 400:
            print(f"Det finns redan ett konto för {epost} – det lämnas orört.")
            return
        raise
    print(f"Administratören {epost} är skapad.")
    if genererat:
        print(f"  Lösenord: {lösen}   (visas bara nu – byt det efter inloggningen)")


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--plattform", help="plattformens publika adress (https://…)")
    p.add_argument("--plattform-nyckel", help="plattformens ADMIN_API_KEY")
    p.add_argument("--arkitekten-intern", help="Arkitektens interna namn i Render (Connect → Internal)")
    p.add_argument("--portal", help="portalens publika adress (https://…)")
    p.add_argument("--portal-nyckel", help="portalens API_KEY")
    p.add_argument("--admin-namn", default="Administratör")
    p.add_argument("--admin-epost", help="skapa ett lokalt administratörskonto med den här adressen")
    a = p.parse_args()

    if not (a.plattform and a.plattform_nyckel) and not a.admin_epost:
        p.error("ange --plattform och --plattform-nyckel, och/eller --admin-epost")
    try:
        if a.plattform and a.plattform_nyckel:
            läsnyckel(a.plattform, a.plattform_nyckel)
            if a.arkitekten_intern:
                arkitekten_källa(a.plattform, a.plattform_nyckel, a.arkitekten_intern)
        if a.admin_epost:
            if not (a.portal and a.portal_nyckel):
                p.error("--admin-epost kräver --portal och --portal-nyckel")
            administratör(a.portal, a.portal_nyckel, a.admin_namn, a.admin_epost)
    except urllib.error.HTTPError as e:
        sys.exit(f"Fel {e.code} från {e.url}: {e.read().decode(errors='replace')[:300]}")
    except urllib.error.URLError as e:
        sys.exit(f"Når inte tjänsten: {e.reason}")


if __name__ == "__main__":
    main()
