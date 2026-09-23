# Aplicația șoferului (Expo) — de construit

Nu e încă începută. Ce trebuie să conțină în MVP (vezi ADR-0003):

- autentificare cu contul de șofer (Supabase Auth);
- cursa de azi: lista opririlor în ordine, cu adresa, indicațiile și poza locului;
- buton „Navighează”, care deschide Waze sau Google Maps cu următoarea oprire;
- GPS în fundal cât cursa e activă (`expo-location` + `expo-task-manager`),
  trimis prin `rpc('ingest_position', …)`, cu coadă locală când nu e semnal;
- notificare locală la ~2 km și ~200 m de preluare (geofence), buton „Am ajuns”
  (`rpc('mark_stop_arrived', …)`);
- lista de pasageri descărcată pe telefon înainte de plecare, pentru lucru fără internet;
- butoane mari: Pauză, Alimentare, Eveniment pe drum, SOS.

Pentru testare pe telefon ai nevoie de un development build (Expo Go nu rulează
locația în fundal pe iOS).
