-- Utilizator nou pentru onboarding.e2e.mjs (după fixtures.sql). În Supabase real, contul se face pe /inregistrare.
insert into auth.users (id, email) values ('00000000-0000-0000-0000-00000000c201', 'patron-e2e@test')
on conflict (id) do nothing;
