drop view if exists public.public_available_slots;

create view public.public_available_slots as
select
  d.public_slug,
  s.slot_date,
  s.slot_time
from public.availability_slots s
join public.doctors d on d.id = s.doctor_id
where d.is_public_booking_enabled = true
  and s.status = 'available'
  and (s.slot_date + s.slot_time) > now();

grant select on public.public_available_slots to anon, authenticated;
