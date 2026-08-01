drop policy if exists patients_doctor_all on public.patients;
drop policy if exists availability_doctor_all on public.availability_slots;
drop policy if exists consultations_doctor_all on public.consultations;
drop policy if exists history_doctor_all on public.patient_history_events;

create policy patients_doctor_select on public.patients
  for select using (doctor_id = auth.uid());
create policy patients_doctor_insert on public.patients
  for insert with check (doctor_id = auth.uid());
create policy patients_doctor_update on public.patients
  for update using (doctor_id = auth.uid()) with check (doctor_id = auth.uid());

create policy availability_doctor_select on public.availability_slots
  for select using (doctor_id = auth.uid());
create policy availability_doctor_insert on public.availability_slots
  for insert with check (doctor_id = auth.uid());
create policy availability_doctor_update on public.availability_slots
  for update using (doctor_id = auth.uid()) with check (doctor_id = auth.uid());

create policy consultations_doctor_select on public.consultations
  for select using (doctor_id = auth.uid());
create policy consultations_doctor_insert on public.consultations
  for insert with check (doctor_id = auth.uid());
create policy consultations_doctor_update on public.consultations
  for update using (doctor_id = auth.uid()) with check (doctor_id = auth.uid());

create policy history_doctor_select on public.patient_history_events
  for select using (doctor_id = auth.uid());
create policy history_doctor_insert on public.patient_history_events
  for insert with check (doctor_id = auth.uid());
create policy history_doctor_update on public.patient_history_events
  for update using (doctor_id = auth.uid()) with check (doctor_id = auth.uid());
