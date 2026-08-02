-- Minimum Supabase/PostgreSQL schema for the Doctor Practice MVP.
-- Apply this in the Supabase SQL editor or via Supabase CLI after creating a project.

create extension if not exists pgcrypto;

create table public.doctors (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null,
  specialty text not null,
  years_experience integer not null default 0,
  clinic_name text,
  clinic_location text,
  consultation_fee numeric(10,2),
  qualification text,
  registration_number text,
  clinic_address text,
  mobile text,
  email text,
  bio text,
  public_slug text not null unique,
  is_public_booking_enabled boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create or replace function public.enforce_initial_doctor_cap()
returns trigger
language plpgsql
as $$
begin
  if (select count(*) from public.doctors) >= 10 then
    raise exception 'Initial MVP supports a maximum of 10 doctors';
  end if;
  return new;
end;
$$;

create trigger doctors_initial_cap
before insert on public.doctors
for each row
execute function public.enforce_initial_doctor_cap();

create table public.patients (
  id uuid primary key default gen_random_uuid(),
  doctor_id uuid not null references public.doctors(id) on delete cascade,
  patient_number text not null,
  full_name text not null,
  mobile text not null,
  age text,
  dob date,
  gender text,
  email text,
  address text,
  background_note text,
  current_reason text,
  latest_consultation_date date,
  current_assessment text,
  current_plan text,
  next_action text,
  expected_followup_date date,
  status text not null default 'active' check (status in ('active','closed')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (doctor_id, mobile),
  unique (doctor_id, patient_number)
);

create table public.availability_slots (
  id uuid primary key default gen_random_uuid(),
  doctor_id uuid not null references public.doctors(id) on delete cascade,
  slot_date date not null,
  slot_time time not null,
  status text not null default 'available' check (status in ('available','booked','unavailable')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (doctor_id, slot_date, slot_time)
);

create table public.appointments (
  id uuid primary key default gen_random_uuid(),
  doctor_id uuid not null references public.doctors(id) on delete cascade,
  patient_id uuid not null references public.patients(id) on delete restrict,
  slot_date date not null,
  slot_time time not null,
  reason text not null,
  status text not null default 'booked' check (status in ('booked','completed','cancelled')),
  created_source text not null default 'doctor' check (created_source in ('doctor','public_booking')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index appointments_no_double_booking
on public.appointments (doctor_id, slot_date, slot_time)
where status in ('booked','completed');

create table public.consultations (
  id uuid primary key default gen_random_uuid(),
  doctor_id uuid not null references public.doctors(id) on delete cascade,
  patient_id uuid not null references public.patients(id) on delete restrict,
  appointment_id uuid references public.appointments(id) on delete restrict,
  consultation_date date not null default current_date,
  reason text,
  clinical_context text,
  assessment text,
  plan_advice text,
  next_action text,
  expected_followup_date date,
  prescription_file_path text,
  ocr_suggested_text text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (appointment_id)
);

create table public.patient_history_events (
  id uuid primary key default gen_random_uuid(),
  doctor_id uuid not null references public.doctors(id) on delete cascade,
  patient_id uuid not null references public.patients(id) on delete cascade,
  appointment_id uuid references public.appointments(id) on delete set null,
  consultation_id uuid references public.consultations(id) on delete set null,
  event_date date not null default current_date,
  event_type text not null,
  note text,
  plan text,
  next_action text,
  expected_followup_date date,
  created_at timestamptz not null default now()
);

create or replace function public.prevent_locked_appointment_updates()
returns trigger
language plpgsql
as $$
begin
  if old.status in ('completed','cancelled') then
    raise exception 'Completed and cancelled appointments are read-only';
  end if;
  return new;
end;
$$;

create trigger appointments_read_only_when_closed
before update on public.appointments
for each row
execute function public.prevent_locked_appointment_updates();

create or replace view public.public_doctor_profiles as
select
  id,
  public_slug,
  full_name,
  specialty,
  years_experience,
  clinic_name,
  clinic_location,
  consultation_fee
from public.doctors
where is_public_booking_enabled = true;

create or replace view public.public_available_slots as
select
  s.id,
  s.doctor_id,
  d.public_slug,
  s.slot_date,
  s.slot_time
from public.availability_slots s
join public.doctors d on d.id = s.doctor_id
where d.is_public_booking_enabled = true
  and s.status = 'available'
  and (s.slot_date + s.slot_time) > now();

alter table public.doctors enable row level security;
alter table public.patients enable row level security;
alter table public.availability_slots enable row level security;
alter table public.appointments enable row level security;
alter table public.consultations enable row level security;
alter table public.patient_history_events enable row level security;

create policy doctors_own_select on public.doctors
  for select using (id = auth.uid());
create policy doctors_own_insert on public.doctors
  for insert with check (id = auth.uid());
create policy doctors_own_update on public.doctors
  for update using (id = auth.uid()) with check (id = auth.uid());

create policy patients_doctor_all on public.patients
  for all using (doctor_id = auth.uid()) with check (doctor_id = auth.uid());

create policy availability_doctor_all on public.availability_slots
  for all using (doctor_id = auth.uid()) with check (doctor_id = auth.uid());

create policy appointments_doctor_select on public.appointments
  for select using (doctor_id = auth.uid());
create policy appointments_doctor_insert on public.appointments
  for insert with check (doctor_id = auth.uid());
create policy appointments_doctor_update_booked_only on public.appointments
  for update using (doctor_id = auth.uid() and status = 'booked') with check (doctor_id = auth.uid());

create policy consultations_doctor_all on public.consultations
  for all using (doctor_id = auth.uid()) with check (doctor_id = auth.uid());

create policy history_doctor_all on public.patient_history_events
  for all using (doctor_id = auth.uid()) with check (doctor_id = auth.uid());

-- Public-safe read access. These views expose no private doctor fields and no patient data.
grant select on public.public_doctor_profiles to anon, authenticated;
grant select on public.public_available_slots to anon, authenticated;

-- Private prescription storage bucket and policies.
insert into storage.buckets (id, name, public)
values ('prescriptions', 'prescriptions', false)
on conflict (id) do nothing;

create policy prescription_doctor_read on storage.objects
  for select to authenticated
  using (
    bucket_id = 'prescriptions'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy prescription_doctor_insert on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'prescriptions'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy prescription_doctor_update on storage.objects
  for update to authenticated
  using (
    bucket_id = 'prescriptions'
    and (storage.foldername(name))[1] = auth.uid()::text
  )
  with check (
    bucket_id = 'prescriptions'
    and (storage.foldername(name))[1] = auth.uid()::text
  );
