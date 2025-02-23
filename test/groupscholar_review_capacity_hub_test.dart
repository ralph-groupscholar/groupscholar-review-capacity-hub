import 'package:groupscholar_review_capacity_hub/groupscholar_review_capacity_hub.dart';
import 'package:test/test.dart';

void main() {
  group('parseDate', () {
    test('parses yyyy-mm-dd', () {
      final date = parseDate('2026-02-08');
      expect(date.year, 2026);
      expect(date.month, 2);
      expect(date.day, 8);
    });

    test('rejects invalid date', () {
      expect(() => parseDate('not-a-date'), throwsFormatException);
    });
  });

  group('normalizeStatus', () {
    test('normalizes valid status', () {
      expect(normalizeStatus('Assigned'), 'assigned');
    });

    test('rejects invalid status', () {
      expect(() => normalizeStatus('late'), throwsFormatException);
    });
  });

  group('normalizeStage', () {
    test('normalizes valid stage', () {
      expect(normalizeStage('Screening'), 'screening');
    });

    test('rejects invalid stage', () {
      expect(() => normalizeStage('unknown'), throwsFormatException);
    });
  });

  group('parsePositiveInt', () {
    test('parses positive int', () {
      expect(parsePositiveInt('12', label: 'window'), 12);
    });

    test('rejects non-positive int', () {
      expect(() => parsePositiveInt('0', label: 'window'), throwsFormatException);
    });
  });

  group('parseUtilization', () {
    test('parses decimal', () {
      expect(parseUtilization('0.75'), closeTo(0.75, 0.0001));
    });

    test('parses percentage', () {
      expect(parseUtilization('85%'), closeTo(0.85, 0.0001));
    });

    test('rejects out of range', () {
      expect(() => parseUtilization('1.2'), throwsFormatException);
    });
  });
}
