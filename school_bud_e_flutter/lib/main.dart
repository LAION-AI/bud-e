import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/chat_provider.dart';
import 'services/file_storage_service.dart';
import 'services/debug_api_server.dart';
import 'screens/chat_screen.dart';

/// Global key for the RepaintBoundary used by the debug API screenshot endpoint.
final GlobalKey debugRepaintKey = GlobalKey();
/// Global navigator key for debug API navigation.
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final storage = FileStorageService();
  await storage.init();

  runApp(SchoolBudEApp(storage: storage));
}

// Warm ocker/brown seed color
const _seedColor = Color(0xFFB8860B); // dark goldenrod

class SchoolBudEApp extends StatefulWidget {
  final FileStorageService storage;

  const SchoolBudEApp({super.key, required this.storage});

  @override
  State<SchoolBudEApp> createState() => _SchoolBudEAppState();
}

class _SchoolBudEAppState extends State<SchoolBudEApp> {
  DebugApiServer? _debugServer;

  @override
  void dispose() {
    _debugServer?.stop();
    super.dispose();
  }

  void _startDebugServer(ChatProvider chat) {
    if (_debugServer != null) return;
    _debugServer = DebugApiServer(chat, debugRepaintKey, navigatorKey);
    _debugServer!.start();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) {
        final chat = ChatProvider(storage: widget.storage);
        // Start debug API server after provider is created
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _startDebugServer(chat);
        });
        return chat;
      },
      child: MaterialApp(
        navigatorKey: navigatorKey,
        title: 'BUD-E',
        debugShowCheckedModeBanner: false,
        themeMode: ThemeMode.system,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: _seedColor,
            brightness: Brightness.light,
            primary: const Color(0xFF8B6914),
            secondary: const Color(0xFFA0845C),
            tertiary: const Color(0xFFC4956A),
            surface: const Color(0xFFFFF8F0),
            surfaceContainerHighest: const Color(0xFFF5EDE0),
          ),
          useMaterial3: true,
          scaffoldBackgroundColor: const Color(0xFFFFF8F0),
          appBarTheme: const AppBarTheme(
            centerTitle: true,
            elevation: 0,
            scrolledUnderElevation: 1,
            backgroundColor: Color(0xFFFFF8F0),
          ),
          cardTheme: CardThemeData(
            elevation: 0,
            color: const Color(0xFFFFF2E4),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          inputDecorationTheme: InputDecorationTheme(
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none,
            ),
            filled: true,
            fillColor: const Color(0xFFF5EDE0),
          ),
        ),
        darkTheme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: _seedColor,
            brightness: Brightness.dark,
            primary: const Color(0xFFD4A84B),
            secondary: const Color(0xFFBFA07A),
            tertiary: const Color(0xFFD4A870),
            surface: const Color(0xFF1C1710),
            surfaceContainerHighest: const Color(0xFF2D261E),
          ),
          useMaterial3: true,
          scaffoldBackgroundColor: const Color(0xFF1C1710),
          appBarTheme: const AppBarTheme(
            centerTitle: true,
            elevation: 0,
            scrolledUnderElevation: 1,
            backgroundColor: Color(0xFF1C1710),
          ),
          cardTheme: CardThemeData(
            elevation: 0,
            color: const Color(0xFF2D261E),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          inputDecorationTheme: InputDecorationTheme(
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none,
            ),
            filled: true,
            fillColor: const Color(0xFF2D261E),
          ),
        ),
        builder: (context, child) => RepaintBoundary(
          key: debugRepaintKey,
          child: child!,
        ),
        home: const ChatScreen(),
      ),
    );
  }
}
