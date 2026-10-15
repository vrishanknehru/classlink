-- ClassLink schema for Supabase Postgres.
-- Writes go through the FastAPI backend (service connection, bypasses RLS).
-- Row level security protects the tables if a client reaches them directly
-- through Supabase's auto generated API: clients can only read their own data.

create type user_role as enum ('teacher', 'student');

create table profiles (
  id          uuid primary key references auth.users (id) on delete cascade,
  role        user_role not null,
  full_name   text not null check (length(trim(full_name)) > 0),
  roll_number text,
  email       text,
  created_at  timestamptz not null default now(),
  constraint students_have_roll_number check (role <> 'student' or roll_number is not null)
);

create table classrooms (
  id         uuid primary key default gen_random_uuid(),
  teacher_id uuid not null references profiles (id) on delete restrict,
  name       text not null check (length(trim(name)) > 0),
  join_code  text not null unique,
  created_at timestamptz not null default now()
);

create table enrollments (
  classroom_id uuid not null references classrooms (id) on delete cascade,
  student_id   uuid not null references profiles (id) on delete cascade,
  joined_at    timestamptz not null default now(),
  primary key (classroom_id, student_id)
);

create table devices (
  id         uuid primary key default gen_random_uuid(),
  student_id uuid not null references profiles (id) on delete cascade,
  public_key text not null,
  label      text,
  created_at timestamptz not null default now(),
  revoked_at timestamptz
);
-- One active device per student.
create unique index devices_one_active_per_student on devices (student_id) where revoked_at is null;

create table sessions (
  id                    uuid primary key default gen_random_uuid(),
  classroom_id          uuid not null references classrooms (id) on delete cascade,
  alias                 text not null check (alias ~ '^[0-9a-f]{8}$'),
  rssi_threshold_dbm    integer not null default -75 check (rssi_threshold_dbm between -100 and -30),
  sample_window_seconds integer not null default 4 check (sample_window_seconds between 1 and 30),
  min_samples           integer not null default 3 check (min_samples between 1 and 50),
  started_at            timestamptz not null default now(),
  ended_at              timestamptz
);
create unique index sessions_one_active_per_classroom on sessions (classroom_id) where ended_at is null;
-- The BLE alias must identify exactly one live session.
create unique index sessions_active_alias on sessions (alias) where ended_at is null;

create table challenges (
  id         uuid primary key default gen_random_uuid(),
  session_id uuid not null references sessions (id) on delete cascade,
  student_id uuid not null references profiles (id) on delete cascade,
  token_hex  text not null,
  issued_at  timestamptz not null,
  expires_at timestamptz not null,
  used_at    timestamptz
);
create index challenges_session_student on challenges (session_id, student_id);

create table attendance (
  id                uuid primary key default gen_random_uuid(),
  session_id        uuid not null references sessions (id) on delete cascade,
  student_id        uuid not null references profiles (id) on delete cascade,
  status            text not null check (status in ('present', 'absent')),
  source            text not null check (source in ('ble_claim', 'manual_correction')),
  median_rssi       integer,
  sample_count      integer,
  observed_at       timestamptz,
  device_id         uuid references devices (id),
  challenge_id      uuid references challenges (id),
  created_at        timestamptz not null default now(),
  corrected_by      uuid references profiles (id),
  correction_reason text,
  -- One record per student per session; makes writes idempotent under retry.
  unique (session_id, student_id),
  constraint corrections_need_reason check (
    source <> 'manual_correction'
    or (corrected_by is not null and length(trim(coalesce(correction_reason, ''))) >= 5)
  )
);
create unique index attendance_one_per_challenge on attendance (challenge_id) where challenge_id is not null;

create table audit_events (
  id           bigint generated always as identity primary key,
  actor_id     uuid,
  action       text not null,
  subject_type text,
  subject_id   text,
  details      jsonb not null default '{}'::jsonb,
  created_at   timestamptz not null default now()
);
create index audit_events_subject on audit_events (subject_type, subject_id);

-- ---------------------------------------------------------------------------
-- Row level security
-- ---------------------------------------------------------------------------
-- Helper functions are SECURITY DEFINER so policies on one table can look at
-- another without triggering recursive policy evaluation.

create function app_is_classroom_teacher(cid uuid) returns boolean
  language sql stable security definer set search_path = public as
$$ select exists (select 1 from classrooms where id = cid and teacher_id = auth.uid()) $$;

create function app_is_enrolled(cid uuid) returns boolean
  language sql stable security definer set search_path = public as
$$ select exists (select 1 from enrollments where classroom_id = cid and student_id = auth.uid()) $$;

create function app_teaches_student(sid uuid) returns boolean
  language sql stable security definer set search_path = public as
$$ select exists (
     select 1 from enrollments e join classrooms c on c.id = e.classroom_id
     where e.student_id = sid and c.teacher_id = auth.uid()) $$;

create function app_can_see_session(sess uuid) returns boolean
  language sql stable security definer set search_path = public as
$$ select exists (
     select 1 from sessions s
     where s.id = sess
       and (app_is_classroom_teacher(s.classroom_id) or app_is_enrolled(s.classroom_id))) $$;

alter table profiles     enable row level security;
alter table classrooms   enable row level security;
alter table enrollments  enable row level security;
alter table devices      enable row level security;
alter table sessions     enable row level security;
alter table challenges   enable row level security;
alter table attendance   enable row level security;
alter table audit_events enable row level security;

-- Nothing is writable by clients, and challenges and audit_events are not
-- readable by them at all (no policies means deny).
revoke all on all tables in schema public from anon, authenticated;
grant select on profiles, classrooms, enrollments, devices, sessions, attendance to authenticated;

create policy profiles_read on profiles for select to authenticated
  using (id = auth.uid() or app_teaches_student(id));

create policy classrooms_read on classrooms for select to authenticated
  using (teacher_id = auth.uid() or app_is_enrolled(id));

create policy enrollments_read on enrollments for select to authenticated
  using (student_id = auth.uid() or app_is_classroom_teacher(classroom_id));

-- Public keys are visible only to their owner.
create policy devices_read on devices for select to authenticated
  using (student_id = auth.uid());

create policy sessions_read on sessions for select to authenticated
  using (app_is_classroom_teacher(classroom_id) or app_is_enrolled(classroom_id));

create policy attendance_read on attendance for select to authenticated
  using (
    student_id = auth.uid()
    or exists (select 1 from sessions s where s.id = session_id and app_is_classroom_teacher(s.classroom_id))
  );
