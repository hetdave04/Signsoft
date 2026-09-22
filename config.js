// ============================================================
// SignSoft — Configuration File
// ============================================================
// Fill in your credentials below, then deploy.
// Get these from: https://supabase.com → Your Project → Settings → API
//
// IMPORTANT: This file is public. Only put the ANON key here,
// never the service_role key. The anon key is safe to expose.
// ============================================================

window.SIGNSOFT_CONFIG = {

  // Your Supabase project URL
  // Example: 'https://abcdefghijklm.supabase.co'
  supabaseUrl: 'postgresql://postgres.sorijxpbowiptflpdzzj:HetD123404==@aws-0-ap-southeast-1.pooler.supabase.com:5432/postgres',

  // Your Supabase anon/public key (safe to be public)
  // Looks like: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
  supabaseKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InNvcmlqeHBib3dpcHRmbHBkenpqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTAwNTU1OTUsImV4cCI6MjEwNTYzMTU5NX0.P_dURMCezEdyzzFQ0nHAwCUw3XrdWdE21WZi5IocwOg',

  // Your Resend API key (optional — for sending real emails)
  // Get free key at: https://resend.com (3,000 emails/month free)
  // If left empty, signing links are shown on-screen instead of emailed
  resendKey: '',

};
