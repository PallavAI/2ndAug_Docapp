# Doctor Practice App MVP

Static HTML/CSS/JavaScript MVP for an independent doctor practice workflow.

## Frontend

- Main app: `outputs/index.html`
- Supabase browser config: `outputs/supabase-config.js`
- Vercel import recommendation: deploy from the repository root. `vercel.json` routes `/` and `/book/<doctor-slug>` to the static app in `outputs`.

## Supabase

Backend resources are defined under:

- `supabase/migrations`
- `supabase/functions/send-booking-confirmation`

Current Supabase responsibilities:

- Doctor authentication
- Doctor profile persistence
- Patients
- Availability slots
- Appointments
- Consultations
- Patient history events
- Private prescription storage
- Booking confirmation email Edge Function

## Edge Function Secrets

Set these in Supabase Dashboard before testing booking emails:

```text
RESEND_API_KEY=your_resend_key
BOOKING_EMAIL_FROM=onboarding@resend.dev
```

Do not commit real API keys.
