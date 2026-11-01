import 'package:flutter_test/flutter_test.dart';
import 'package:govor_mobile/features/messenger_controller.dart';
import 'package:govor_mobile/core/storage.dart';
import 'package:package_info_plus/package_info_plus.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'version label comes from installed package metadata including build number',
    () async {
      PackageInfo.setMockInitialValues(
        appName: 'Говор',
        packageName: 'app.govor.client',
        version: '2.7.4',
        buildNumber: '81',
        buildSignature: 'test',
      );
      final controller = MessengerController(store: MemorySecretStore());
      addTearDown(controller.dispose);
      await controller.loadAppInfo();
      expect(controller.appInfo!.packageName, 'app.govor.client');
      expect(controller.versionLabel, 'Govor Flutter • 2.7.4+81');
    },
  );
}
