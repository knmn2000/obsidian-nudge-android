import 'dart:io';
import 'dart:math';
import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import '../data/store.dart';
import 'nudge.dart';

const _channelId = 'nudges';
const _channelName = 'Nudges';

Future<Directory> notesCacheDir() async =>
    Directory('${(await getApplicationDocumentsDirectory()).path}/notes');

class LocalNotificationSink implements NotificationSink {
  final FlutterLocalNotificationsPlugin _plugin;

  LocalNotificationSink._(this._plugin);

  static Future<LocalNotificationSink> create({
    void Function(String payload)? onTap,
  }) async {
    final plugin = FlutterLocalNotificationsPlugin();
    await plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
      onDidReceiveNotificationResponse: onTap == null
          ? null
          : (r) {
              if (r.payload != null) onTap(r.payload!);
            },
    );
    await plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(
          const AndroidNotificationChannel(
            _channelId,
            _channelName,
            importance: Importance.high,
          ),
        );
    return LocalNotificationSink._(plugin);
  }

  @override
  Future<void> show({
    required String title,
    required String body,
    required String payload,
  }) => _plugin.show(
    // ponytail: fixed id, a new nudge replaces the previous one.
    id: 0,
    title: title,
    body: body,
    payload: payload,
    notificationDetails: const NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        importance: Importance.high,
        priority: Priority.high,
      ),
    ),
  );
}

Future<bool> requestNotificationPermission() async =>
    await FlutterLocalNotificationsPlugin()
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission() ??
    false;

Future<String?> launchPayload() async {
  final d = await FlutterLocalNotificationsPlugin()
      .getNotificationAppLaunchDetails();
  return d?.didNotificationLaunchApp == true
      ? d!.notificationResponse?.payload
      : null;
}

@pragma('vm:entry-point')
void callbackDispatcher() {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  Workmanager().executeTask((task, _) async {
    try {
      final store = Store(
        await SharedPreferences.getInstance(),
        const SecureTokenStore(),
      );
      final cacheDir = await notesCacheDir();
      final now = DateTime.now();
      switch (task) {
        case 'nudge':
          await runNudge(
            store: store,
            cacheDir: cacheDir,
            sink: await LocalNotificationSink.create(),
            now: now,
            rng: Random(),
          );
        case 'sync':
          final client = http.Client();
          try {
            await runSync(
              store: store,
              cacheDir: cacheDir,
              client: client,
              now: now,
            );
          } finally {
            client.close();
          }
      }
      return true;
    } catch (_) {
      return false;
    }
  });
}

Future<void> initBackground() => Workmanager().initialize(callbackDispatcher);

Future<void> scheduleWork(Settings s) async {
  await Workmanager().registerPeriodicTask(
    'nudge',
    'nudge',
    frequency: Duration(hours: s.nudgeHours),
    existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
  );
  await Workmanager().registerPeriodicTask(
    'sync',
    'sync',
    frequency: const Duration(hours: 24),
    constraints: Constraints(networkType: NetworkType.connected),
    existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
  );
}
