import 'package:esp_service/esp_service.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

// Per-app values from the ESP dashboard, passed at build time:
// flutter run --dart-define=ESP_PUBLIC_KEY=pk_live_... --dart-define=ESP_BASE_URL=https://...
const espPublicKey = String.fromEnvironment('ESP_PUBLIC_KEY');
const espBaseUrl = String.fromEnvironment('ESP_BASE_URL');

final navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  await EspPush.instance.initialize(
    const EspConfig(
      publicKey: espPublicKey,
      baseUrl: espBaseUrl,
      androidChannelId: 'app_notifications',
      androidChannelName: 'Notifications',
      debug: kDebugMode,
    ),
  );

  runApp(const ExampleApp());

  // Taps on pushes, including the one that launched the app.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    EspPush.instance.setNotificationOpenedHandler((push) {
      navigatorKey.currentState?.push(MaterialPageRoute<void>(builder: (_) => PushDetailsPage(push: push)));
    });
  });
}

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(navigatorKey: navigatorKey, home: const HomePage());
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  @override
  void initState() {
    super.initState();
    // Android 13+ shows the system dialog; the result goes to ESP.
    EspPush.instance.requestPermission();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ESP push example')),
      body: Center(
        child: ValueListenableBuilder<String?>(
          valueListenable: EspPush.instance.subscriberId,
          builder: (context, id, _) => Text(id == null ? 'Not registered yet' : 'Subscriber: $id'),
        ),
      ),
    );
  }
}

class PushDetailsPage extends StatelessWidget {
  const PushDetailsPage({super.key, required this.push});

  final EspNotification push;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(push.title ?? 'Push')),
      body: Padding(padding: const EdgeInsets.all(16), child: Text('${push.body ?? ''}\n\n${push.data}')),
    );
  }
}
