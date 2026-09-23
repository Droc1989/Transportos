# 0010 — Catalogul pachetelor pe firmă și înscrierea în trei pași

Decizie cerută și aprobată de proprietar: catalog editabil numai de Super Admin,
intervale consecutive pornind de la 1, fără suprapuneri; prețurile inițiale sunt
130 EUR pentru 1–3, 200 EUR pentru 4–6 și 300 EUR pentru 7–10 vehicule.

Catalogul este date, nu logică fixă. Limita globală este capătul ultimului interval.
Fiecare firmă păstrează o copie a intervalului, numărului declarat și prețului lunar.
Editarea catalogului nu actualizează aceste copii. Numai RPC-ul administrativ explicit
poate schimba pachetul/prețul unei firme existente. Nu se modifică facturarea Stripe.
La introducerea acestui model, firmele fără copie primesc pachetul corespunzător
numărului actual de vehicule (minimum 1); migrația se oprește dacă flota depășește catalogul.

RLS permite citirea copiei personalului propriei firme și Super Adminului. Catalogul
este citibil de utilizatori autentificați; niciunul nu are scriere SQL directă.
RPC-urile verifică identitatea și rolul. Un lock comun protejează schimbările catalogului,
iar blocarea rândului firmei serializează aprobările și schimbarea copiei pachetului.
Aprobările nu pot depăși limita copiei sau limita globală curentă. Reducerea catalogului
sub o flotă existentă ori un număr declarat este refuzată.

Contul precedă cei trei pași. Pasul 2 selectează pachetul din numărul de vehicule.
La primul acces către completarea unui microbuz se salvează firma ca proiect, după
acceptarea termenilor. Formularul complet existent de vehicul rămâne obligatoriu.
Pasul 3 enumeră lipsurile și legăturile directe. Trimiterea verifică pe server numărul
declarat și completitudinea tuturor vehiculelor adăugate, inclusiv cele suplimentare.
Semnăturile RPC existente, enum-urile și regulile existente de acces nu sunt schimbate.

Capturile aprobate sunt 13–19 în docs/design/ecrane. Panoul administrativ pentru catalog
și copie este un ecran nou, cu componentele existente, care necesită aprobarea vizuală
a proprietarului în PR. Migrația și verificările se execută numai local/CI în această etapă.
