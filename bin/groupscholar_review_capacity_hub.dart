import 'dart:io';

import 'package:args/args.dart';

import 'package:groupscholar_review_capacity_hub/src/commands.dart';
import 'package:groupscholar_review_capacity_hub/src/config.dart';
import 'package:groupscholar_review_capacity_hub/src/db.dart';

void main(List<String> arguments) async {
  final parser = ArgParser()
    ..addCommand('list-reviewers')
    ..addCommand('summary')
    ..addCommand('log-assignment')
    ..addCommand('capacity-alerts')
    ..addFlag('help', abbr: 'h', negatable: false);

  parser.commands['log-assignment']
    ?..addOption('reviewer', help: 'Reviewer name')
    ..addOption('reviewer-email', help: 'Reviewer email (optional)')
    ..addOption('capacity', help: 'Reviewer weekly capacity', defaultsTo: '5')
    ..addOption('application-id', help: 'Application identifier')
    ..addOption('applicant', help: 'Applicant name (when creating application)')
    ..addOption('stage', help: 'Application stage (submitted|screening|review|final)')
    ..addOption('submitted', help: 'Application submitted date (YYYY-MM-DD)')
    ..addOption('due', help: 'Review due date (YYYY-MM-DD)')
    ..addOption('status', help: 'Assignment status (assigned|completed|overdue|withdrawn)');

  parser.commands['capacity-alerts']
    ?..addOption(
      'due-window',
      help: 'Upcoming due window in days',
      defaultsTo: '7',
    )
    ..addOption(
      'min-utilization',
      help: 'Utilization threshold (0-1 or percentage)',
      defaultsTo: '0.8',
    );

  ArgResults results;
  try {
    results = parser.parse(arguments);
  } catch (error) {
    stderr.writeln(error);
    _printUsage(parser);
    exitCode = 64;
    return;
  }

  if (results['help'] == true || results.command == null) {
    _printUsage(parser);
    return;
  }

  try {
    final config = DbConfig.fromEnv();
    final db = await DbClient.connect(config);
    try {
      final command = results.command!.name;
      switch (command) {
        case 'list-reviewers':
          exitCode = (await listReviewers(db)).exitCode;
          break;
        case 'summary':
          exitCode = (await summary(db)).exitCode;
          break;
        case 'log-assignment':
          exitCode = (await _handleLogAssignment(db, results.command!)).exitCode;
          break;
        case 'capacity-alerts':
          exitCode = (await _handleCapacityAlerts(db, results.command!)).exitCode;
          break;
        default:
          stderr.writeln('Unknown command: $command');
          _printUsage(parser);
          exitCode = 64;
      }
    } finally {
      await db.close();
    }
  } on Exception catch (error) {
    stderr.writeln('Error: $error');
    exitCode = 70;
  }
}

Future<CommandResult> _handleLogAssignment(DbClient db, ArgResults args) async {
  final reviewer = args['reviewer'] as String?;
  final applicationId = args['application-id'] as String?;
  final dueRaw = args['due'] as String?;

  if (reviewer == null || reviewer.trim().isEmpty) {
    throw FormatException('log-assignment requires --reviewer.');
  }
  if (applicationId == null || applicationId.trim().isEmpty) {
    throw FormatException('log-assignment requires --application-id.');
  }
  if (dueRaw == null || dueRaw.trim().isEmpty) {
    throw FormatException('log-assignment requires --due.');
  }

  final capacity = int.tryParse(args['capacity'] as String? ?? '5');
  if (capacity == null || capacity <= 0) {
    throw FormatException('capacity must be a positive integer.');
  }

  final submittedRaw = args['submitted'] as String?;
  final dueDate = parseDate(dueRaw);
  final stage = normalizeStage(args['stage'] as String?);
  final status = normalizeStatus(args['status'] as String?);

  return logAssignment(
    db,
    reviewerName: reviewer.trim(),
    reviewerEmail: (args['reviewer-email'] as String?)?.trim(),
    capacityPerWeek: capacity,
    applicationId: applicationId.trim(),
    applicantName: (args['applicant'] as String?)?.trim() ?? 'Unknown Applicant',
    stage: stage ?? 'review',
    submittedDate: submittedRaw == null || submittedRaw.trim().isEmpty
        ? null
        : parseDate(submittedRaw),
    dueDate: dueDate,
    status: status ?? 'assigned',
  );
}

Future<CommandResult> _handleCapacityAlerts(DbClient db, ArgResults args) async {
  final dueWindowRaw = args['due-window'] as String? ?? '7';
  final minUtilizationRaw = args['min-utilization'] as String? ?? '0.8';

  final dueWindow = parsePositiveInt(dueWindowRaw, label: 'due-window');
  final minUtilization = parseUtilization(minUtilizationRaw);

  return capacityAlerts(
    db,
    dueWindowDays: dueWindow,
    minUtilization: minUtilization,
  );
}

void _printUsage(ArgParser parser) {
  stdout.writeln('Review Capacity Hub CLI');
  stdout.writeln('');
  stdout.writeln('Usage: dart run <command> [options]');
  stdout.writeln('');
  stdout.writeln('Commands:');
  stdout.writeln('  list-reviewers   List reviewer capacity and active assignments');
  stdout.writeln('  summary          Show overall reviewer capacity summary');
  stdout.writeln('  log-assignment   Log a new review assignment');
  stdout.writeln('  capacity-alerts  Show reviewer utilization and upcoming due alerts');
  stdout.writeln('');
  stdout.writeln('Global options:');
  stdout.writeln(parser.usage);
  stdout.writeln('');
  stdout.writeln('Examples:');
  stdout.writeln('  dart run list-reviewers');
  stdout.writeln('  dart run summary');
  stdout.writeln('  dart run log-assignment --reviewer "Avery Clark" --application-id APP-102 --due 2026-02-20');
  stdout.writeln('  dart run capacity-alerts --due-window 10 --min-utilization 85%');
}
