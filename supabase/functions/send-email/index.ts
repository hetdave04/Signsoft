// ============================================================
// SignSoft — Supabase Edge Function: send-email
// Deploy: supabase functions deploy send-email
// Set secret: supabase secrets set RESEND_API_KEY=re_xxxx
//             supabase secrets set FROM_EMAIL=noreply@yourdomain.com
// ============================================================
import { serve } from "https://deno.land/std@0.177.0/http/server.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  try {
    const { to, subject, html, text, type } = await req.json();
    if (!to || !subject) throw new Error("Missing required fields: to, subject");

    const RESEND_KEY = Deno.env.get("RESEND_API_KEY");
    const FROM_EMAIL = Deno.env.get("FROM_EMAIL") || "noreply@signsoft.io";
    const FROM_NAME  = "SignSoft";

    if (!RESEND_KEY) throw new Error("RESEND_API_KEY not configured");

    const emailHtml = html || buildDefaultTemplate(subject, text || "", type || "info");

    const res = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: { "Authorization": `Bearer ${RESEND_KEY}`, "Content-Type": "application/json" },
      body: JSON.stringify({ from: `${FROM_NAME} <${FROM_EMAIL}>`, to: Array.isArray(to) ? to : [to], subject, html: emailHtml }),
    });

    const data = await res.json();
    if (!res.ok) throw new Error(data.message || "Resend API error");

    return new Response(JSON.stringify({ success: true, id: data.id }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 200,
    });
  } catch (err) {
    return new Response(JSON.stringify({ success: false, error: err.message }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 400,
    });
  }
});

function buildDefaultTemplate(subject: string, body: string, type: string): string {
  const colors: Record<string, string> = {
    info: "#2563EB", success: "#059669", warning: "#D97706", otp: "#7C3AED", signing: "#0D1F3C",
  };
  const accent = colors[type] || colors.info;
  return `<!DOCTYPE html><html><head><meta charset="UTF-8">
  <style>body{margin:0;padding:0;background:#F1F5F9;font-family:'Helvetica Neue',Arial,sans-serif;}
  .wrap{max-width:560px;margin:40px auto;background:#fff;border-radius:12px;overflow:hidden;box-shadow:0 4px 24px rgba(0,0,0,.08);}
  .hd{background:${accent};padding:28px 32px;color:#fff;}
  .hd h1{margin:0;font-size:22px;font-weight:700;letter-spacing:-0.5px;}
  .hd p{margin:6px 0 0;opacity:.85;font-size:13px;}
  .bd{padding:32px;}
  .bd p{color:#374151;font-size:15px;line-height:1.7;margin:0 0 16px;}
  .otp-box{background:#F1F5F9;border-radius:8px;padding:20px;text-align:center;margin:20px 0;}
  .otp-code{font-size:36px;font-weight:800;letter-spacing:10px;color:${accent};}
  .otp-note{font-size:12px;color:#6B7280;margin-top:8px;}
  .btn{display:inline-block;background:${accent};color:#fff;padding:12px 28px;border-radius:8px;
       text-decoration:none;font-weight:600;font-size:15px;margin:8px 0;}
  .ft{padding:20px 32px;border-top:1px solid #E5E7EB;font-size:11.5px;color:#9CA3AF;text-align:center;}
  </style></head><body>
  <div class="wrap">
    <div class="hd"><h1>SignSoft</h1><p>Digital Document Signing</p></div>
    <div class="bd">${body}</div>
    <div class="ft">This email was sent by SignSoft. Do not reply to this email.<br>
    © ${new Date().getFullYear()} SignSoft. All rights reserved.</div>
  </div></body></html>`;
}
