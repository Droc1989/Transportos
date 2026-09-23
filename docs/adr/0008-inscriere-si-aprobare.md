# ADR-0008 — Înscrierea firmelor și aprobarea de către platformă

**Stare:** acceptată · 23 septembrie 2026

## Decizie

- **Firma se înscrie singură** (`/inregistrare-firma`): își alege emailul și parola, completează
  datele firmei (nume, CUI, licență, telefon, țară) și acceptă termenii, inclusiv răspunderea
  pentru șoferi și microbuze. Acceptarea se salvează cu data și cu cine a acceptat.
- **Stare „în verificare”**: firma își adaugă microbuzele, dar nu poate crea curse, rezervări,
  rute, șoferi sau site până la aprobare (`company_can_manage_fleet` vs. `company_can_write`).
- **Microbuz complet** = an de fabricație, cel puțin o poză exterior și una interior, condiții din
  lista fixă (`VEHICLE_FEATURES`), bagaj inclus, declarațiile RCA și asigurare de pasageri cu
  data de expirare (salvate cu data și cine a declarat). Cererea se trimite doar cu cel puțin un
  microbuz complet (`get_registration_checklist`, `submit_company_for_review`).
- **Super Admin decide**: vede firma, flota și pozele în `/admin/aprobari`; microbuzele mai vechi
  decât anul minim (setare de platformă, implicit 2012) apar marcate, fără blocare automată.
  Aprobă sau respinge fiecare microbuz (respingerea cere motiv) și firma (aprobarea cere cel
  puțin un microbuz aprobat). Patronul primește email cu decizia.
- **Și microbuzele adăugate după aprobarea firmei** trec prin aprobare. Schimbarea anului sau a
  numărului de înmatriculare trimite microbuzul din nou la verificare. Firma nu își poate
  aproba singură microbuzele (`vehicles_guard`).
- **Pe curse** intră doar microbuze aprobate, iar plecarea trebuie să fie înainte de expirarea
  asigurărilor declarate (`trips_vehicle_check`).
- **Clientul vede** pozele, condițiile și anul microbuzului care face cursa (link de urmărire,
  site-ul firmei). Numărul de înmatriculare nu apare în datele publice ale microbuzului. Dacă
  firma schimbă microbuzul pe o cursă cu rezervări, clienții sunt anunțați (`VEHICLE_CHANGED`).
- **Profilul șoferului**: șoferul și-l completează singur (`/sofer`, apoi aplicația mobilă) și
  își dă singur acordul pentru afișare; firma îl aprobă. Pe site apare doar profilul aprobat,
  cu acord. Retragerea acordului îl scoate imediat de pe site.
- **Regula de protecție** pentru câmpurile gestionate de platformă (stare firmă, aprobări): se
  aplică scrierilor directe ale utilizatorilor (`current_user = authenticated`); funcțiile
  platformei, care își verifică singure drepturile, pot modifica aceste câmpuri.

## Consecințe

- Declarațiile de asigurare sunt ale firmei, nu o verificare a platformei. Încărcarea polițelor
  și alertele înainte de expirare sunt pasul următor.
- Emailurile către firme cer un furnizor de email configurat în worker (Resend); fără el apar în log.
