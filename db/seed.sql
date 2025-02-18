INSERT INTO groupscholar_review_capacity_hub.reviewers (name, email, capacity_per_week, active)
VALUES
  ('Avery Clark', 'avery.clark@groupscholar.com', 6, true),
  ('Jordan Lee', 'jordan.lee@groupscholar.com', 4, true),
  ('Morgan Patel', 'morgan.patel@groupscholar.com', 5, true),
  ('Riley Chen', 'riley.chen@groupscholar.com', 3, true)
ON CONFLICT (email) DO NOTHING;

INSERT INTO groupscholar_review_capacity_hub.applications (application_id, applicant_name, stage, submitted_at)
VALUES
  ('APP-101', 'Samira Wallace', 'review', '2026-01-28'),
  ('APP-102', 'Luis Ortega', 'review', '2026-01-30'),
  ('APP-103', 'Keisha Grant', 'screening', '2026-01-24'),
  ('APP-104', 'Noah Pierce', 'final', '2026-01-20')
ON CONFLICT (application_id) DO NOTHING;

INSERT INTO groupscholar_review_capacity_hub.review_assignments (reviewer_id, application_id, assigned_at, due_date, status)
SELECT r.id, a.id, '2026-02-03', '2026-02-12', 'assigned'
  FROM groupscholar_review_capacity_hub.reviewers r
  JOIN groupscholar_review_capacity_hub.applications a ON a.application_id = 'APP-101'
 WHERE r.email = 'avery.clark@groupscholar.com'
ON CONFLICT DO NOTHING;

INSERT INTO groupscholar_review_capacity_hub.review_assignments (reviewer_id, application_id, assigned_at, due_date, status)
SELECT r.id, a.id, '2026-02-04', '2026-02-14', 'assigned'
  FROM groupscholar_review_capacity_hub.reviewers r
  JOIN groupscholar_review_capacity_hub.applications a ON a.application_id = 'APP-102'
 WHERE r.email = 'jordan.lee@groupscholar.com'
ON CONFLICT DO NOTHING;

INSERT INTO groupscholar_review_capacity_hub.review_assignments (reviewer_id, application_id, assigned_at, due_date, status)
SELECT r.id, a.id, '2026-02-01', '2026-02-08', 'completed'
  FROM groupscholar_review_capacity_hub.reviewers r
  JOIN groupscholar_review_capacity_hub.applications a ON a.application_id = 'APP-103'
 WHERE r.email = 'morgan.patel@groupscholar.com'
ON CONFLICT DO NOTHING;

INSERT INTO groupscholar_review_capacity_hub.review_assignments (reviewer_id, application_id, assigned_at, due_date, status)
SELECT r.id, a.id, '2026-01-26', '2026-02-05', 'overdue'
  FROM groupscholar_review_capacity_hub.reviewers r
  JOIN groupscholar_review_capacity_hub.applications a ON a.application_id = 'APP-104'
 WHERE r.email = 'riley.chen@groupscholar.com'
ON CONFLICT DO NOTHING;
