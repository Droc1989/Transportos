# ADR 0014 — Remedieri după analiza fluxurilor

Aprobarea proprietarului: 24 septembrie 2026, toate cele cinci probleme, inclusiv mesajul vizibil și migrația locală pentru limita comună. Nicio autorizare de producție.

- Login fără next trece prin /, unde rolul determină destinația. Destinațiile interne explicite sunt păstrate.
- get_trip_stops folosește numele din rezervare, cu numele fișei ca rezervă; aceeași semnătură, security invoker și aceleași politici RLS.
- Sugestiile vechi nu actualizează starea după schimbare, golire, selecție sau demontare; anulare plus verificare de versiune.
- Calculul și optimizarea refuză traseele incomplete, înainte de apelul extern/scriere, folosind zona de erori existentă. Mesaj nou RO/DE aprobat; fără schimbări de tokenuri sau structură vizuală.
- Pentru adrese, un contor PostgreSQL comun permite 40 de apeluri externe într-o fereastră mobilă de 60 de secunde, pentru toate instanțele împreună. Este mai restrictiv decât vechiul 40/IP/proces. Este un prag conservator de aplicație, nu o garanție pentru cota zilnică contractuală Geoapify. Nu acoperă Routing/Route Planner.
- Cache hits nu consumă bugetul. Fiecare încercare externă rezervă un slot înainte de apel, inclusiv dacă furnizorul eșuează. Nu se recreditează automat.
- Contorul este într-o schemă privată, RLS activ, fără date personale/IP. RPC fără parametri, numai service_role. Blocarea unui singur rând serializează instanțele concurente; păstrează maximum 40 timestamps.
- Configurația serverului folosește clientul service existent. Dacă lipsește cheia, migrația sau conexiunea la DB, răspunsul este 503 și nu se apelează geocoderul; la epuizare 429. Adresa rămâne editabilă ca text liber. Nu am configurat/citit chei reale.
- Înainte de o publicare viitoare autorizată: aplicați migrațiile înaintea aplicației și verificați configurația serverului separat. Acest PR nu aplică nimic în producție.

Teste noi: destinații login; răspunsuri stale; coordonate incomplete; comportament fail-closed; nume și RLS; privilegiile bugetului; 50 de cereri SQL concurente (40 acceptate, 10 refuzate). Testele existente sunt păstrate.
