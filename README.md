# GroupScholar Review Capacity Hub

A Dart-based CLI that tracks reviewer capacity, assignments, and upcoming due dates for scholarship review operations. The tool reads from a dedicated PostgreSQL schema and provides quick visibility into load and SLA risk.

## Features
- List reviewer capacity and active assignment counts.
- Generate a summary of active reviewers, load averages, and upcoming due dates.
- Log new review assignments with application metadata.
- Alert on reviewer utilization thresholds and upcoming due dates.
- PostgreSQL schema, views, and seed data included.

## Tech Stack
- Dart 3
- PostgreSQL (schema: `groupscholar_review_capacity_hub`)

## Getting Started
1. Install dependencies:
   ```bash
   dart pub get
   ```
2. Configure environment variables (production only):
   - `GS_DB_HOST`
   - `GS_DB_PORT`
   - `GS_DB_NAME`
   - `GS_DB_USER`
   - `GS_DB_PASSWORD`
   - `GS_DB_SSLMODE` (optional, defaults to `require`; use `disable` if SSL is not supported)

## Database Setup
Run migrations and seed data against the production database:
```bash
./scripts/apply_migrations.sh
./scripts/seed_db.sh
```

## Usage
```bash
# List reviewers

dart run list-reviewers

# Summary

dart run summary

# Log a new assignment

dart run log-assignment \
  --reviewer "Avery Clark" \
  --application-id APP-105 \
  --due 2026-02-18 \
  --applicant "Micah Brooks" \
  --stage review

# Review capacity alerts

dart run capacity-alerts --due-window 10 --min-utilization 85%
```

## Tests
```bash
dart test
```

## Notes
- This CLI is designed for production environments only. Do not use the Group Scholar production database for local development.
