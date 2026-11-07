import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../core/app_update.dart';
import '../l10n/l10n.dart';
import 'design.dart';

class UpdateBanner extends StatefulWidget {
  const UpdateBanner({super.key});
  @override
  State<UpdateBanner> createState() => _UpdateBannerState();
}

class _UpdateBannerState extends State<UpdateBanner>
    with WidgetsBindingObserver {
  final service = AppUpdateService();
  Timer? timer;
  AppUpdate? update;
  bool checking = false, busy = false, failed = false;
  DateTime? lastCheck;
  @override
  void initState() {
    super.initState();
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    WidgetsBinding.instance.addObserver(this);
    unawaited(check());
    timer = Timer.periodic(const Duration(hours: 4), (_) => check());
  }

  Future<void> check() async {
    if (checking || busy) return;
    checking = true;
    lastCheck = DateTime.now();
    try {
      final next = await service.check();
      if (mounted) setState(() => update = next);
    } catch (_) {
      /* Offline checks are silent. */
    } finally {
      checking = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        (lastCheck == null ||
            DateTime.now().difference(lastCheck!) >
                const Duration(minutes: 15))) {
      unawaited(check());
    }
  }

  Future<void> install() async {
    setState(() {
      busy = true;
      failed = false;
    });
    try {
      await service.install(update!);
    } catch (_) {
      if (mounted) setState(() => failed = true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (update == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Glass(
        radius: 16,
        padding: const EdgeInsets.all(10),
        child: Wrap(
          spacing: 12,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              failed
                  ? context.l10n.updateFailed
                  : context.l10n.updateAvailable(update!.version),
            ),
            if (busy)
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            TextButton(
              onPressed: busy ? null : install,
              child: Text(
                busy
                    ? context.l10n.downloadingUpdate
                    : context.l10n.downloadAndInstall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
