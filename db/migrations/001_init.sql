CREATE SCHEMA IF NOT EXISTS groupscholar_review_capacity_hub;

CREATE TABLE IF NOT EXISTS groupscholar_review_capacity_hub.reviewers (
  id BIGSERIAL PRIMARY KEY,
  name TEXT NOT NULL,
  email TEXT NOT NULL UNIQUE,
  capacity_per_week INTEGER NOT NULL DEFAULT 5 CHECK (capacity_per_week > 0),
  active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS groupscholar_review_capacity_hub.applications (
  id BIGSERIAL PRIMARY KEY,
  application_id TEXT NOT NULL UNIQUE,
  applicant_name TEXT NOT NULL,
  stage TEXT NOT NULL DEFAULT 'review'
    CHECK (stage IN ('submitted', 'screening', 'review', 'final')),
  submitted_at DATE NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS groupscholar_review_capacity_hub.review_assignments (
  id BIGSERIAL PRIMARY KEY,
  reviewer_id BIGINT NOT NULL REFERENCES groupscholar_review_capacity_hub.reviewers(id),
  application_id BIGINT NOT NULL REFERENCES groupscholar_review_capacity_hub.applications(id),
  assigned_at DATE NOT NULL,
  due_date DATE NOT NULL,
  status TEXT NOT NULL DEFAULT 'assigned'
    CHECK (status IN ('assigned', 'completed', 'overdue', 'withdrawn')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (reviewer_id, application_id, due_date)
);

CREATE INDEX IF NOT EXISTS idx_review_assignments_status
  ON groupscholar_review_capacity_hub.review_assignments(status);

CREATE INDEX IF NOT EXISTS idx_review_assignments_due
  ON groupscholar_review_capacity_hub.review_assignments(due_date);

CREATE OR REPLACE VIEW groupscholar_review_capacity_hub.reviewer_load AS
  SELECT r.id,
         r.name,
         r.email,
         r.capacity_per_week,
         r.active,
         COUNT(ra.id) FILTER (WHERE ra.status = 'assigned') AS active_assignments,
         COUNT(ra.id) FILTER (WHERE ra.status = 'completed') AS completed_assignments
    FROM groupscholar_review_capacity_hub.reviewers r
LEFT JOIN groupscholar_review_capacity_hub.review_assignments ra
      ON ra.reviewer_id = r.id
GROUP BY r.id;
