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

Future<CommandResult> capacityAlerts(
  DbClient db, {
  int dueWindowDays = 7,
  double minUtilization = 0.8,
}) async {
  final loadRows = await db.query('''
    SELECT r.id,
           r.name,
           r.email,
           r.capacity_per_week,
           COUNT(ra.id) FILTER (WHERE ra.status = 'assigned') AS active_assignments,
           COALESCE(
             COUNT(ra.id) FILTER (WHERE ra.status = 'assigned')::DECIMAL
             / NULLIF(r.capacity_per_week, 0),
             0
           ) AS utilization
      FROM $schemaName.reviewers r
 LEFT JOIN $schemaName.review_assignments ra
        ON ra.reviewer_id = r.id
     WHERE r.active = true
  GROUP BY r.id
    HAVING COALESCE(
             COUNT(ra.id) FILTER (WHERE ra.status = 'assigned')::DECIMAL
             / NULLIF(r.capacity_per_week, 0),
             0
           ) >= @minUtilization
  ORDER BY utilization DESC, active_assignments DESC;
  ''', parameters: {'minUtilization': minUtilization});

  final dueRows = await db.query('''
    SELECT r.name,
           a.application_id,
           ra.due_date,
           ra.status
      FROM $schemaName.review_assignments ra
      JOIN $schemaName.reviewers r ON r.id = ra.reviewer_id
      JOIN $schemaName.applications a ON a.id = ra.application_id
     WHERE ra.status = 'assigned'
       AND ra.due_date <= CURRENT_DATE + (@window || ' days')::INTERVAL
  ORDER BY ra.due_date ASC, r.name;
  ''', parameters: {'window': dueWindowDays});

  stdout.writeln('Review Capacity Alerts');
  stdout.writeln('-----------------------');
  stdout.writeln('Utilization threshold: ${(minUtilization * 100).toStringAsFixed(0)}%');
  if (loadRows.isEmpty) {
    stdout.writeln('No reviewers at or above the utilization threshold.');
  } else {
    stdout.writeln('Reviewer load alerts:');
    for (final row in loadRows) {
      final utilization = (row[5] as num).toDouble() * 100;
      stdout.writeln(
        '${row[0]} | ${row[1]} | ${row[2]} | capacity ${row[3]} | active ${row[4]} | utilization ${utilization.toStringAsFixed(1)}%',
      );
    }
  }

  stdout.writeln('');
  stdout.writeln('Assignments due within $dueWindowDays days:');
  if (dueRows.isEmpty) {
    stdout.writeln('No upcoming assignments in the window.');
  } else {
    for (final row in dueRows) {
      stdout.writeln('${row[0]} | ${row[1]} | due ${_fmtDate(row[2] as DateTime)} | ${row[3]}');
    }
  }

  return CommandResult(0);
}

Future<CommandResult> capacityAlerts(
  DbClient db, {
  int lookaheadDays = 7,
}) async {
  if (lookaheadDays <= 0) {
    throw FormatException('lookahead days must be a positive integer.');
  }

  final rows = await db.query('''
    SELECT r.id,
           r.name,
           r.email,
           r.capacity_per_week,
           r.active,
           COUNT(ra.id) FILTER (WHERE ra.status = 'assigned') AS active_assignments,
           COUNT(ra.id) FILTER (
             WHERE ra.status = 'assigned'
               AND ra.due_date <= CURRENT_DATE + @lookahead::int
           ) AS due_soon
      FROM $schemaName.reviewers r
 LEFT JOIN $schemaName.review_assignments ra
        ON ra.reviewer_id = r.id
     WHERE r.active = true
     GROUP BY r.id
     ORDER BY active_assignments DESC, r.name;
  ''', parameters: {'lookahead': lookaheadDays});

  if (rows.isEmpty) {
    stdout.writeln('No active reviewers found.');
    return CommandResult(0);
  }

  stdout.writeln('Capacity Alerts (next $lookaheadDays days)');
  stdout.writeln('-----------------------------------------');
  for (final row in rows) {
    final activeAssignments = row[5] as int;
    final capacity = row[3] as int;
    final status = capacityStatus(activeAssignments, capacity);
    final dueSoon = row[6] as int;
    stdout.writeln(
      '${row[0]} | ${row[1]} | ${row[2]} | load $activeAssignments/$capacity '
      '| status $status | due soon $dueSoon',
    );
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

String capacityStatus(
  int activeAssignments,
  int capacityPerWeek, {
  double warnThreshold = 0.8,
}) {
  if (capacityPerWeek <= 0) {
    throw ArgumentError.value(
      capacityPerWeek,
      'capacityPerWeek',
      'capacity must be positive',
    );
  }
  if (activeAssignments > capacityPerWeek) {
    return 'over';
  }
  if (activeAssignments == capacityPerWeek) {
    return 'at';
  }
  final ratio = activeAssignments / capacityPerWeek;
  if (ratio >= warnThreshold) {
    return 'near';
  }
  return 'available';
}

int parsePositiveInt(String input, {required String label}) {
  final parsed = int.tryParse(input);
  if (parsed == null || parsed <= 0) {
    throw FormatException('$label must be a positive integer.');
  }
  return parsed;
}

double parseUtilization(String input) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) {
    throw FormatException('min-utilization cannot be empty.');
  }

  String numeric = trimmed;
  if (trimmed.endsWith('%')) {
    numeric = trimmed.substring(0, trimmed.length - 1).trim();
  }
  final parsed = double.tryParse(numeric);
  if (parsed == null) {
    throw FormatException('min-utilization must be a number.');
  }

  final value = trimmed.endsWith('%') ? parsed / 100 : parsed;
  if (value <= 0 || value > 1) {
    throw FormatException('min-utilization must be between 0 and 1, or 0% to 100%.');
  }
  return value;
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
