drop view if exists public.public_doctor_profiles;

create view public.public_doctor_profiles as
select
  public_slug,
  full_name,
  specialty,
  years_experience,
  clinic_name,
  clinic_location,
  consultation_fee
from public.doctors
where is_public_booking_enabled = true;

grant select on public.public_doctor_profiles to anon, authenticated;
