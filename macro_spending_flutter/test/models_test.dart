import 'package:flutter_test/flutter_test.dart';
import 'package:macro_spending_analyzer/models.dart';
import 'package:macro_spending_analyzer/receipt_scanner.dart';

void main() {
  test('money input uses exact cents and rejects invalid amounts', () {
    expect(parseCents('12.34'), 1234);
    expect(parseCents('12,3'), 1230);
    expect(parseCents('0.01'), 1);
    for (final value in ['0', '-2', 'NaN', '12.345', 'abc', '']) {
      expect(parseCents(value), isNull);
    }
  });
  test('month-end recurrence keeps original due day', () {
    expect(
      monthlyDates(DateTime(2024, 1, 31), DateTime(2024, 3, 31)).map(dateKey),
      ['2024-01-31', '2024-02-29', '2024-03-31'],
    );
    expect(monthlyDates(DateTime(2024, 4, 15), DateTime(2024, 4, 14)), isEmpty);
  });
  test('OCR prefers total over subtotal and accepts next-line amounts', () {
    final draft = parseReceipt(
      'Market\nSubtotal 12.00\nTax 1.00\nTOTAL\n13.00',
    );
    expect(draft.business, 'Market');
    expect(draft.amount, '13.00');
    expect(parseReceipt('Market\nTOTAL 1,234.56').amount, '1234.56');
    expect(parseReceipt('Market\nSubtotal 12.00').amount, isNull);
  });
}
