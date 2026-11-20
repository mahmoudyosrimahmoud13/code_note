import 'package:code_note/core/services/update_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('compares versions as numbers, not text', () {
    expect(UpdateService.isNewer('1.10.0', '1.9.2'), isTrue);
    expect(UpdateService.isNewer('1.4.0', '1.3.9'), isTrue);
    expect(UpdateService.isNewer('2.0.0', '1.99.99'), isTrue);
    expect(UpdateService.isNewer('1.3.0', '1.3.0'), isFalse);
    expect(UpdateService.isNewer('1.2.9', '1.3.0'), isFalse);
    expect(UpdateService.isNewer('1.4', '1.3.5'), isTrue);
  });
}
