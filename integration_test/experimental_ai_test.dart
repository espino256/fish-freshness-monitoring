import 'package:integration_test/integration_test.dart';

import 'support/ai_platform_checks.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  registerAiPlatformChecks();
}
