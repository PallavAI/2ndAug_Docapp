create or replace function public.next_patient_number(p_doctor_id uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  n integer;
begin
  select coalesce(max(nullif(regexp_replace(patient_number, '\D', '', 'g'), '')::integer), 1000) + 1
    into n
  from public.patients
  where doctor_id = p_doctor_id;

  return 'PT-' || n::text;
end;
$$;

create or replace function public.book_public_appointment(
  p_public_slug text,
  p_slot_date date,
  p_slot_time time,
  p_patient_name text,
  p_mobile text,
  p_reason text,
  p_age text default null,
  p_gender text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_doctor_id uuid;
  v_patient_id uuid;
  v_patient_number text;
  v_appointment_id uuid;
begin
  if coalesce(trim(p_public_slug), '') = ''
    or coalesce(trim(p_patient_name), '') = ''
    or coalesce(trim(p_mobile), '') = ''
    or coalesce(trim(p_reason), '') = '' then
    raise exception 'Missing required booking information';
  end if;

  select id into v_doctor_id
  from public.doctors
  where public_slug = p_public_slug
    and is_public_booking_enabled = true;

  if v_doctor_id is null then
    raise exception 'Doctor booking page is not available';
  end if;

  perform 1
  from public.availability_slots
  where doctor_id = v_doctor_id
    and slot_date = p_slot_date
    and slot_time = p_slot_time
    and status = 'available'
    and (slot_date + slot_time) > now()
  for update;

  if not found then
    raise exception 'This slot is no longer available';
  end if;

  select id, patient_number
    into v_patient_id, v_patient_number
  from public.patients
  where doctor_id = v_doctor_id
    and mobile = p_mobile;

  if v_patient_id is null then
    v_patient_number := public.next_patient_number(v_doctor_id);
    insert into public.patients (
      doctor_id, patient_number, full_name, mobile, age, gender,
      current_reason, next_action, expected_followup_date, status
    )
    values (
      v_doctor_id, v_patient_number, p_patient_name, p_mobile, p_age, p_gender,
      p_reason, 'Attend scheduled consultation', p_slot_date, 'active'
    )
    returning id into v_patient_id;

    insert into public.patient_history_events (doctor_id, patient_id, event_date, event_type, note, next_action, expected_followup_date)
    values (v_doctor_id, v_patient_id, current_date, 'patient_created', 'Created from public booking.', 'Attend scheduled consultation', p_slot_date);
  else
    update public.patients
    set full_name = p_patient_name,
        age = coalesce(p_age, age),
        gender = coalesce(p_gender, gender),
        current_reason = p_reason,
        next_action = 'Attend scheduled consultation',
        expected_followup_date = p_slot_date,
        status = 'active',
        updated_at = now()
    where id = v_patient_id;
  end if;

  insert into public.appointments (doctor_id, patient_id, slot_date, slot_time, reason, status, created_source)
  values (v_doctor_id, v_patient_id, p_slot_date, p_slot_time, p_reason, 'booked', 'public_booking')
  returning id into v_appointment_id;

  update public.availability_slots
  set status = 'booked',
      updated_at = now()
  where doctor_id = v_doctor_id
    and slot_date = p_slot_date
    and slot_time = p_slot_time;

  insert into public.patient_history_events (doctor_id, patient_id, appointment_id, event_date, event_type, note, next_action, expected_followup_date)
  values (v_doctor_id, v_patient_id, v_appointment_id, current_date, 'appointment_booked', p_reason, 'Attend scheduled consultation', p_slot_date);

  return jsonb_build_object(
    'appointment_id', v_appointment_id,
    'patient_id', v_patient_id,
    'patient_number', v_patient_number,
    'slot_date', p_slot_date,
    'slot_time', p_slot_time
  );
end;
$$;

grant execute on function public.book_public_appointment(text,date,time,text,text,text,text,text) to anon, authenticated;
