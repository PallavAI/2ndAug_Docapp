const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

type BookingPayload = {
  appointment_id?: string;
  patient_email?: string;
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {...corsHeaders, "Content-Type": "application/json"},
  });
}

function esc(value: unknown) {
  return String(value ?? "")
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#039;");
}

function displayDate(date: string) {
  return new Date(`${date}T00:00:00`).toLocaleDateString("en-IN", {
    day: "2-digit",
    month: "short",
    year: "numeric",
  });
}

function displayTime(time: string) {
  const [rawHour, minute] = time.split(":").map(Number);
  const suffix = rawHour >= 12 ? "PM" : "AM";
  const hour = rawHour % 12 || 12;
  return `${hour}:${String(minute).padStart(2, "0")} ${suffix}`;
}

function supabaseSecretKey() {
  const legacyKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (legacyKey) return legacyKey;

  const secretKeys = Deno.env.get("SUPABASE_SECRET_KEYS");
  if (!secretKeys) return "";

  try {
    return JSON.parse(secretKeys).default || "";
  } catch {
    return "";
  }
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", {headers: corsHeaders});
  if (req.method !== "POST") return json({error: "Method not allowed"}, 405);

  const resendApiKey = Deno.env.get("RESEND_API_KEY");
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = supabaseSecretKey();
  const fromEmail = Deno.env.get("BOOKING_EMAIL_FROM") || "onboarding@resend.dev";

  if (!resendApiKey || !supabaseUrl || !serviceRoleKey) {
    return json({error: "Email service is not configured"}, 500);
  }

  let payload: BookingPayload;
  try {
    payload = await req.json();
  } catch {
    return json({error: "Invalid request body"}, 400);
  }

  if (!payload.appointment_id || !payload.patient_email) {
    return json({error: "appointment_id and patient_email are required"}, 400);
  }

  const appointmentUrl =
    `${supabaseUrl}/rest/v1/appointments` +
    `?id=eq.${encodeURIComponent(payload.appointment_id)}` +
    "&select=id,slot_date,slot_time,reason,doctors(full_name,specialty,clinic_name,clinic_location,email),patients(full_name,email,mobile)";

  const appointmentRes = await fetch(appointmentUrl, {
    headers: {
      apikey: serviceRoleKey,
      Authorization: `Bearer ${serviceRoleKey}`,
    },
  });

  if (!appointmentRes.ok) return json({error: "Could not load booking"}, 500);

  const rows = await appointmentRes.json();
  const booking = rows[0];
  if (!booking) return json({error: "Booking not found"}, 404);

  const doctor = booking.doctors;
  const patient = booking.patients;
  if (!doctor?.email || !patient?.email) {
    return json({error: "Doctor and patient email are required"}, 400);
  }
  if (patient.email.toLowerCase() !== payload.patient_email.toLowerCase()) {
    return json({error: "Booking email does not match"}, 403);
  }

  const when = `${displayDate(booking.slot_date)} at ${displayTime(booking.slot_time)}`;
  const subject = `Appointment confirmed: ${when}`;
  const html = `
    <div style="font-family:Arial,sans-serif;line-height:1.5;color:#17211f">
      <h2 style="margin:0 0 12px">Appointment confirmed</h2>
      <p><strong>Doctor:</strong> ${esc(doctor.full_name)} · ${esc(doctor.specialty)}</p>
      <p><strong>Patient:</strong> ${esc(patient.full_name)} · ${esc(patient.mobile)}</p>
      <p><strong>Date and time:</strong> ${esc(when)}</p>
      <p><strong>Clinic:</strong> ${esc(doctor.clinic_name)}${doctor.clinic_location ? `, ${esc(doctor.clinic_location)}` : ""}</p>
      <p><strong>Reason:</strong> ${esc(booking.reason)}</p>
    </div>
  `;

  const emailRes = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${resendApiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      from: fromEmail,
      to: [doctor.email, patient.email],
      subject,
      html,
    }),
  });

  const emailBody = await emailRes.json().catch(() => ({}));
  if (!emailRes.ok) return json({error: "Email send failed", detail: emailBody}, 502);

  return json({ok: true, email: emailBody});
});
