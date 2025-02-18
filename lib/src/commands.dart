import 'dart:io';

import 'package:postgres/postgres.dart';

import 'db.dart';

class CommandResult {
  CommandResult(this.exitCode);

  final int exitCode;
}

Future<CommandResult> listReviewers(DbClient db) async {
  final rows = await db.query('''
    SELECT r.id,
           r.name,
           r.email,
           r.capacity_per_week,
           r.active,
           COUNT(ra.id) FILTER (WHERE ra.status = 'assigned') AS assigned_count
      FROM $schemaName.reviewers r
 LEFT JOIN $schemaName.review_assignments ra
        ON ra.reviewer_id = r.id
     GROUP BY r.id
     ORDER BY r.name;
  ''');

  if (rows.isEmpty) {
    stdout.writeln('No reviewers found.');
    return CommandResult(0);
  }

  stdout.writeln('Reviewers');
  stdout.writeln('---------');
  for (final row in rows) {
    stdout.writeln(
      '${row[0]} | ${row[1]} | ${row[2]} | capacity ${row[3]} | active ${row[4]} | assigned ${row[5]}',
    );
  }

  return CommandResult(0);
}

Future<CommandResult> summary(DbClient db) async {
  final reviewers = await db.query(
    'SELECT COUNT(*) FROM $schemaName.reviewers WHERE active = true;',
  );
  final assignments = await db.query(
    'SELECT status, COUNT(*) FROM $schemaName.review_assignments GROUP BY status;',
  );
  final upcoming = await db.query('''
    SELECT COUNT(*)
      FROM $schemaName.review_assignments
     WHERE due_date <= CURRENT_DATE + INTERVAL '7 days'
       AND status = 'assigned';
  ''');
  final averageLoad = await db.query('''
    SELECT COALESCE(AVG(active_assignments), 0)
      FROM (
        SELECT r.id,
               COUNT(ra.id) FILTER (WHERE ra.status = 'assigned') AS active_assignments
          FROM $schemaName.reviewers r
     LEFT JOIN $schemaName.review_assignments ra
            ON ra.reviewer_id = r.id
         WHERE r.active = true
         GROUP BY r.id
      ) AS counts;
  ''');

  stdout.writeln('Review Capacity Summary');
  stdout.writeln('-----------------------');
  stdout.writeln('Active reviewers: ${reviewers.first[0]}');
  stdout.writeln('Average active assignments per reviewer: ${averageLoad.first[0]}');
  stdout.writeln('Assignments due in next 7 days: ${upcoming.first[0]}');
  stdout.writeln('Assignments by status:');
  for (final row in assignments) {
    stdout.writeln(' - ${row[0]}: ${row[1]}');
  }

  return CommandResult(0);
}

Future<CommandResult> logAssignment(
  DbClient db, {
  required String reviewerName,
  required String applicationId,
  required DateTime dueDate,
  String? reviewerEmail,
  int capacityPerWeek = 5,
  String applicantName = 'Unknown Applicant',
  String stage = 'review',
  DateTime? submittedDate,
  String status = 'assigned',
}) async {
  final reviewerId = await _findOrCreateReviewer(
    db,
    name: reviewerName,
    email: reviewerEmail,
    capacityPerWeek: capacityPerWeek,
  );

  final applicationRow = await db.query(
    'SELECT id FROM $schemaName.applications WHERE application_id = @appId;',
    parameters: {'appId': applicationId},
  );

  int applicationPk;
  if (applicationRow.isEmpty) {
    final inserted = await db.query('''
      INSERT INTO $schemaName.applications
        (application_id, applicant_name, stage, submitted_at)
      VALUES (@appId, @applicantName, @stage, @submittedAt)
      RETURNING id;
    ''', parameters: {
      'appId': applicationId,
      'applicantName': applicantName,
      'stage': stage,
      'submittedAt': (submittedDate ?? DateTime.now()).toUtc(),
    });
    applicationPk = inserted.first[0] as int;
  } else {
    applicationPk = applicationRow.first[0] as int;
  }

  await db.query('''
    INSERT INTO $schemaName.review_assignments
      (reviewer_id, application_id, assigned_at, due_date, status)
    VALUES (@reviewerId, @applicationId, CURRENT_DATE, @dueDate, @status);
  ''', parameters: {
    'reviewerId': reviewerId,
    'applicationId': applicationPk,
    'dueDate': dueDate,
    'status': status,
  });

  stdout.writeln('Logged assignment for $reviewerName on $applicationId due ${_fmtDate(dueDate)}.');
  return CommandResult(0);
}

Future<int> _findOrCreateReviewer(
  DbClient db, {
  required String name,
  String? email,
  required int capacityPerWeek,
}) async {
  final rows = await db.query(
    'SELECT id FROM $schemaName.reviewers WHERE LOWER(name) = LOWER(@name);',
    parameters: {'name': name},
  );

  if (rows.isNotEmpty) {
    return rows.first[0] as int;
  }

  final inserted = await db.query('''
    INSERT INTO $schemaName.reviewers (name, email, capacity_per_week, active)
    VALUES (@name, @email, @capacity, true)
    RETURNING id;
  ''', parameters: {
    'name': name,
    'email': email ?? "${name.toLowerCase().replaceAll(' ', '.')}@groupscholar.com",
    'capacity': capacityPerWeek,
  });

  return inserted.first[0] as int;
}

String _fmtDate(DateTime date) {
  final year = date.year.toString().padLeft(4, '0');
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '$year-$month-$day';
}

DateTime parseDate(String input) {
  final parsed = DateTime.tryParse(input);
  if (parsed == null) {
    throw FormatException('Invalid date format: $input. Use YYYY-MM-DD.');
  }
  return DateTime(parsed.year, parsed.month, parsed.day);
}

String? normalizeStatus(String? value) {
  if (value == null) {
    return null;
  }
  final normalized = value.toLowerCase();
  const allowed = {'assigned', 'completed', 'overdue', 'withdrawn'};
  if (!allowed.contains(normalized)) {
    throw FormatException('Unsupported status: $value');
  }
  return normalized;
}

String? normalizeStage(String? value) {
  if (value == null) {
    return null;
  }
  final normalized = value.toLowerCase();
  const allowed = {'submitted', 'screening', 'review', 'final'};
  if (!allowed.contains(normalized)) {
    throw FormatException('Unsupported stage: $value');
  }
  return normalized;
}
