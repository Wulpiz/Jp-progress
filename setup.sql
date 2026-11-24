-- =====================================================================
-- Japanese Focus: setup database (jalankan di Supabase > SQL Editor)
-- Aman dijalankan berulang kali (idempotent).
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1) Tabel arsip goal gagal
-- ---------------------------------------------------------------------
create table if not exists public.goal_archive (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null default auth.uid() references auth.users(id) on delete cascade,
  text            text not null,
  type            text not null,
  deadline        text,
  goal_created_at timestamptz,
  archived_at     timestamptz not null default now()
);
create index if not exists goal_archive_user_idx on public.goal_archive (user_id, archived_at desc);

-- ---------------------------------------------------------------------
-- 2) Row Level Security: tiap user hanya bisa akses barisnya sendiri
--    Asumsi: kolom user_id bertipe uuid (sama seperti auth.users.id).
--    Kalau tipenya text, ganti kondisi jadi: user_id = auth.uid()::text
-- ---------------------------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array['goals', 'user_profiles', 'daily_log', 'user_reminders', 'goal_archive'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists %I on public.%I', t || '_owner_all', t);
    execute format(
      'create policy %I on public.%I for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid())',
      t || '_owner_all', t
    );
  end loop;
end $$;

-- Cek hasilnya. Semua tabel harus rowsecurity = true, dan JANGAN ada policy lain
-- yang membuka akses untuk role anon / using (true): policy digabung dengan OR.
-- select tablename, rowsecurity from pg_tables where schemaname = 'public';
-- select tablename, policyname, roles, cmd, qual from pg_policies where schemaname = 'public' order by 1, 2;

-- CATATAN: job yang me-reset goal harian harus jalan sebagai postgres (pg_cron)
-- atau memakai service_role key (Edge Function). Keduanya melewati RLS.
-- Kalau job itu memakai anon key, setelah RLS aktif dia akan berhenti bekerja.

-- ---------------------------------------------------------------------
-- 3) Kolom baru
-- ---------------------------------------------------------------------
-- Tanggal JLPT yang bisa diatur dari aplikasi
alter table public.user_profiles add column if not exists jlpt_date date;
-- Menit belajar dari timer Pomodoro
alter table public.daily_log add column if not exists study_minutes integer not null default 0;

-- ---------------------------------------------------------------------
-- 4) Realtime: HP dan laptop saling sinkron
-- ---------------------------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array['goals', 'user_profiles', 'daily_log'] loop
    begin
      execute format('alter publication supabase_realtime add table public.%I', t);
    exception when duplicate_object then null;  -- sudah terdaftar
    end;
  end loop;
end $$;

-- ---------------------------------------------------------------------
-- 5) Zona waktu reset harian (WITA = UTC+8)
--    pg_cron berjalan dalam UTC. Tengah malam WITA = 16:00 UTC.
--    Lihat jadwal yang ada, lalu ubah ke '0 16 * * *'.
-- ---------------------------------------------------------------------
-- select jobid, jobname, schedule, command from cron.job;
-- select cron.alter_job(<jobid>, schedule => '0 16 * * *');
