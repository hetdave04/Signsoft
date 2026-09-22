-- ============================================================
-- SignSoft — Supabase Database Schema
-- Run this in: Supabase Dashboard → SQL Editor → New Query
-- ============================================================

-- Enable necessary extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ============================================================
-- PROFILES (extends Supabase auth.users)
-- ============================================================
CREATE TABLE IF NOT EXISTS profiles (
  id              UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  name            TEXT NOT NULL,
  email           TEXT NOT NULL,
  role            TEXT NOT NULL DEFAULT 'user'
                    CHECK (role IN ('super_admin','org_admin','manager','user','read_only')),
  dept            TEXT,
  status          TEXT NOT NULL DEFAULT 'active'
                    CHECK (status IN ('active','inactive','suspended')),
  mfa_enabled     BOOLEAN DEFAULT FALSE,
  profile_photo   TEXT,
  saved_signature TEXT,      -- base64 of last-used signature
  notif_prefs     JSONB NOT NULL DEFAULT '{
    "signing_invite":true,"doc_signed":true,
    "reminder":true,"completed":true,"declined":true
  }'::jsonb,
  joined_at       TIMESTAMPTZ DEFAULT NOW(),
  updated_at      TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- DOCUMENTS
-- ============================================================
CREATE TABLE IF NOT EXISTS documents (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name            TEXT NOT NULL,
  type            TEXT DEFAULT 'pdf',
  status          TEXT NOT NULL DEFAULT 'draft'
                    CHECK (status IN ('draft','pending','signed','completed','declined','expired','voided','deleted')),
  uploaded_by     UUID REFERENCES profiles(id),
  file_path       TEXT,          -- Supabase Storage path
  pages           INT DEFAULT 1,
  file_size       TEXT,
  category        TEXT DEFAULT 'General',
  signing_order   TEXT DEFAULT 'sequential' CHECK (signing_order IN ('sequential','parallel')),
  envelope_msg    TEXT,
  envelope_subj   TEXT,
  expires_at      TIMESTAMPTZ,
  voided_at       TIMESTAMPTZ,
  voided_by       UUID REFERENCES profiles(id),
  deleted_at      TIMESTAMPTZ,
  signing_fields  JSONB DEFAULT '[]'::jsonb,  -- array of field objects
  uploaded_at     TIMESTAMPTZ DEFAULT NOW(),
  updated_at      TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- SIGNING RECIPIENTS
-- ============================================================
CREATE TABLE IF NOT EXISTS signing_recipients (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  document_id     UUID NOT NULL REFERENCES documents(id) ON DELETE CASCADE,
  user_id         UUID REFERENCES profiles(id),   -- NULL for external
  name            TEXT NOT NULL,
  email           TEXT NOT NULL,
  role            TEXT DEFAULT 'signer'
                    CHECK (role IN ('signer','viewer','approver','cc')),
  verify_method   TEXT DEFAULT 'otp'
                    CHECK (verify_method IN ('none','otp','otp_ocr')),
  status          TEXT DEFAULT 'pending'
                    CHECK (status IN ('pending','viewed','signed','declined')),
  order_index     INT DEFAULT 0,
  recipient_idx   INT DEFAULT 0,
  color           TEXT DEFAULT '#2563EB',
  otp_code        TEXT,
  otp_expires_at  TIMESTAMPTZ,
  otp_attempts    INT DEFAULT 0,
  signing_token   TEXT UNIQUE DEFAULT encode(gen_random_bytes(32), 'hex'),
  ocr_passed      BOOLEAN,
  ocr_confidence  FLOAT,
  signed_at       TIMESTAMPTZ,
  decline_reason  TEXT,
  created_at      TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- AUDIT LOG  (append-only — no UPDATE/DELETE RLS)
-- ============================================================
CREATE TABLE IF NOT EXISTS audit_log (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  document_id     UUID REFERENCES documents(id) ON DELETE SET NULL,
  action          TEXT NOT NULL,
  actor_name      TEXT NOT NULL,
  actor_id        UUID REFERENCES profiles(id) ON DELETE SET NULL,
  ip_address      TEXT DEFAULT 'client',
  device          TEXT,
  metadata        JSONB DEFAULT '{}'::jsonb,
  created_at      TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- NOTIFICATIONS
-- ============================================================
CREATE TABLE IF NOT EXISTS notifications (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  title           TEXT NOT NULL,
  message         TEXT NOT NULL,
  type            TEXT DEFAULT 'info' CHECK (type IN ('info','success','warning','error')),
  read            BOOLEAN DEFAULT FALSE,
  document_id     UUID REFERENCES documents(id) ON DELETE SET NULL,
  link            TEXT,
  created_at      TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- DELEGATIONS (Substitute Signing)
-- ============================================================
CREATE TABLE IF NOT EXISTS delegations (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  delegator_id        UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  delegate_id         UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  start_date          TIMESTAMPTZ NOT NULL,
  end_date            TIMESTAMPTZ NOT NULL,
  status              TEXT DEFAULT 'pending_approval'
                        CHECK (status IN ('pending_approval','active','revoked','expired')),
  doc_type_restriction TEXT,
  requires_approval   BOOLEAN DEFAULT FALSE,
  approved_by         UUID REFERENCES profiles(id),
  approved_at         TIMESTAMPTZ,
  notes               TEXT,
  created_at          TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- DOCUMENT TEMPLATES
-- ============================================================
CREATE TABLE IF NOT EXISTS templates (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name            TEXT NOT NULL,
  description     TEXT,
  category        TEXT DEFAULT 'General',
  file_path       TEXT NOT NULL,
  allowed_roles   TEXT[] DEFAULT ARRAY['user','manager','org_admin','super_admin'],
  created_by      UUID REFERENCES profiles(id),
  archived        BOOLEAN DEFAULT FALSE,
  created_at      TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- STORAGE BUCKET (run separately in Supabase Storage)
-- ============================================================
-- NOTE: Create bucket named "documents" in Supabase Storage
-- Set it as PRIVATE (not public)

-- ============================================================
-- ROW LEVEL SECURITY POLICIES
-- ============================================================
ALTER TABLE profiles           ENABLE ROW LEVEL SECURITY;
ALTER TABLE documents          ENABLE ROW LEVEL SECURITY;
ALTER TABLE signing_recipients ENABLE ROW LEVEL SECURITY;
ALTER TABLE audit_log          ENABLE ROW LEVEL SECURITY;
ALTER TABLE notifications      ENABLE ROW LEVEL SECURITY;
ALTER TABLE delegations        ENABLE ROW LEVEL SECURITY;
ALTER TABLE templates          ENABLE ROW LEVEL SECURITY;

-- PROFILES
CREATE POLICY "Profiles visible to authenticated users"
  ON profiles FOR SELECT TO authenticated USING (true);
CREATE POLICY "Users can update own profile"
  ON profiles FOR UPDATE TO authenticated USING (auth.uid() = id);
CREATE POLICY "Users can insert own profile"
  ON profiles FOR INSERT TO authenticated WITH CHECK (auth.uid() = id);

-- DOCUMENTS - users see docs they uploaded or are recipients of
CREATE POLICY "Users see own and recipient docs"
  ON documents FOR SELECT TO authenticated
  USING (
    uploaded_by = auth.uid()
    OR id IN (SELECT document_id FROM signing_recipients WHERE user_id = auth.uid())
    OR EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role IN ('super_admin','org_admin'))
  );
CREATE POLICY "Users can create documents" ON documents FOR INSERT TO authenticated WITH CHECK (uploaded_by = auth.uid());
CREATE POLICY "Uploaders can update docs" ON documents FOR UPDATE TO authenticated USING (
  uploaded_by = auth.uid()
  OR EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role IN ('super_admin','org_admin'))
);

-- SIGNING RECIPIENTS - visible to doc owner and the recipient themselves
CREATE POLICY "Recipients visible to doc owner and recipient"
  ON signing_recipients FOR SELECT TO authenticated
  USING (
    user_id = auth.uid()
    OR document_id IN (SELECT id FROM documents WHERE uploaded_by = auth.uid())
    OR EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role IN ('super_admin','org_admin'))
  );
CREATE POLICY "Doc owner can create recipients" ON signing_recipients FOR INSERT TO authenticated
  WITH CHECK (document_id IN (SELECT id FROM documents WHERE uploaded_by = auth.uid()));
CREATE POLICY "Doc owner and recipient can update" ON signing_recipients FOR UPDATE TO authenticated
  USING (
    user_id = auth.uid()
    OR document_id IN (SELECT id FROM documents WHERE uploaded_by = auth.uid())
  );

-- Allow anon access to signing_recipients by token (for external signers)
CREATE POLICY "External signers can view by token"
  ON signing_recipients FOR SELECT TO anon
  USING (signing_token IS NOT NULL);
CREATE POLICY "External signers can update by token"
  ON signing_recipients FOR UPDATE TO anon
  USING (signing_token IS NOT NULL);

-- Documents accessible by token (external signers)
CREATE POLICY "External signers can view doc by token"
  ON documents FOR SELECT TO anon
  USING (id IN (SELECT document_id FROM signing_recipients WHERE signing_token IS NOT NULL));

-- AUDIT LOG - append only, no deletes
CREATE POLICY "Authenticated users can insert audit"
  ON audit_log FOR INSERT TO authenticated WITH CHECK (true);
CREATE POLICY "Users see audit for their docs"
  ON audit_log FOR SELECT TO authenticated
  USING (
    document_id IN (
      SELECT id FROM documents WHERE uploaded_by = auth.uid()
      UNION
      SELECT document_id FROM signing_recipients WHERE user_id = auth.uid()
    )
    OR EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role IN ('super_admin','org_admin'))
  );
CREATE POLICY "Anon can insert audit for signing" ON audit_log FOR INSERT TO anon WITH CHECK (true);

-- NOTIFICATIONS
CREATE POLICY "Users see own notifications"
  ON notifications FOR SELECT TO authenticated USING (user_id = auth.uid());
CREATE POLICY "System can create notifications"
  ON notifications FOR INSERT TO authenticated WITH CHECK (true);
CREATE POLICY "Users can mark own as read"
  ON notifications FOR UPDATE TO authenticated USING (user_id = auth.uid());

-- DELEGATIONS
CREATE POLICY "Users see own delegations"
  ON delegations FOR SELECT TO authenticated
  USING (
    delegator_id = auth.uid() OR delegate_id = auth.uid()
    OR EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role IN ('super_admin','org_admin'))
  );
CREATE POLICY "Users can create delegations" ON delegations FOR INSERT TO authenticated WITH CHECK (delegator_id = auth.uid());
CREATE POLICY "Users can update own delegations" ON delegations FOR UPDATE TO authenticated
  USING (delegator_id = auth.uid() OR EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role IN ('super_admin','org_admin')));

-- TEMPLATES
CREATE POLICY "Authenticated users can view templates"
  ON templates FOR SELECT TO authenticated USING (archived = FALSE OR EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role IN ('super_admin','org_admin')));
CREATE POLICY "Admins can manage templates" ON templates FOR ALL TO authenticated
  USING (EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role IN ('super_admin','org_admin')));

-- ============================================================
-- FUNCTIONS & TRIGGERS
-- ============================================================

-- Auto-create profile on signup
CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO profiles (id, name, email, role)
  VALUES (
    NEW.id,
    COALESCE(NEW.raw_user_meta_data->>'name', split_part(NEW.email, '@', 1)),
    NEW.email,
    COALESCE(NEW.raw_user_meta_data->>'role', 'user')
  )
  ON CONFLICT (id) DO NOTHING;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION handle_new_user();

-- Auto-expire documents past deadline
CREATE OR REPLACE FUNCTION expire_overdue_documents()
RETURNS void AS $$
BEGIN
  UPDATE documents
  SET status = 'expired', updated_at = NOW()
  WHERE status = 'pending'
    AND expires_at IS NOT NULL
    AND expires_at < NOW();
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Updated_at trigger
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$ BEGIN NEW.updated_at = NOW(); RETURN NEW; END; $$ LANGUAGE plpgsql;
CREATE TRIGGER docs_updated_at BEFORE UPDATE ON documents FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER profiles_updated_at BEFORE UPDATE ON profiles FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- ============================================================
-- STORAGE POLICY (run after creating "documents" bucket)
-- ============================================================
-- In Supabase Storage → Policies, add:
-- Bucket: documents
-- Allow authenticated users to upload: storage.foldername(name)[1] = auth.uid()::text
-- Allow authenticated users to read their own files
-- (The app handles this via signed URLs)

SELECT 'Schema created successfully!' as result;
