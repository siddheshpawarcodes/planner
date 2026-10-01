import 'package:flutter_test/flutter_test.dart';

import 'journey.dart';

void main() {
  testWidgets('acceptance: onboard → voice → Move Flutter → done early → missed → weekend → review',
      acceptanceJourney);
}
