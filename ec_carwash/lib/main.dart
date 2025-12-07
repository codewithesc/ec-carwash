import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'firebase_options.dart';
import 'theme.dart';
import 'screens/login_page.dart';
import 'screens/Admin/admin_staff_home.dart';
import 'screens/Customer/customer_home.dart';
import 'data_models/inventory_data.dart';
import 'data_models/services_data.dart';
import 'services/local_notification_service.dart';
import 'services/firebase_messaging_service.dart';
import 'services/fcm_token_manager.dart';
import 'services/permission_service.dart';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase with timeout to prevent hanging
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    ).timeout(const Duration(seconds: 30));
  } catch (e) {
    // If Firebase fails to initialize, the app cannot run
    // This should not happen in production, but we handle it gracefully
    runApp(MaterialApp(
      home: Scaffold(
        body: Center(
          child: Text('Failed to initialize app. Please check your internet connection.'),
        ),
      ),
    ));
    return;
  }

  // Initialize Crashlytics (mobile only)
  if (!kIsWeb) {
    // Pass all uncaught Flutter errors to Crashlytics
    FlutterError.onError = (errorDetails) {
      FirebaseCrashlytics.instance.recordFlutterFatalError(errorDetails);
    };

    // Pass all uncaught asynchronous errors to Crashlytics
    PlatformDispatcher.instance.onError = (error, stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      return true;
    };
  }

  // Initialize inventory data if Firestore collection is empty (with timeout)
  try {
    await InventoryManager.initializeWithSampleData()
        .timeout(const Duration(seconds: 10));
  } catch (e) {
    // Continue even if initialization fails or times out
  }

  // Initialize services data if Firestore collection is empty (with timeout)
  try {
    await ServicesManager.initializeWithSampleData()
        .timeout(const Duration(seconds: 10));
  } catch (e) {
    // Continue even if initialization fails or times out
  }

  // Initialize notification services (only for mobile platforms)
  if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
    try {
      await LocalNotificationService.initialize()
          .timeout(const Duration(seconds: 5));
      await FirebaseMessagingService.initialize()
          .timeout(const Duration(seconds: 5));
      await FCMTokenManager.initializeToken()
          .timeout(const Duration(seconds: 5));
    } catch (e) {
      // Continue even if notification services fail to initialize
    }
  }

  runApp(const ECCarwashApp());
}

class ECCarwashApp extends StatelessWidget {
  const ECCarwashApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'EC Carwash',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: const AuthWrapper(),
    );
  }
}

/// Wrapper that checks authentication state and redirects accordingly
class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        // Show loading indicator while checking auth state
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(),
            ),
          );
        }

        // If user is logged in, verify role and redirect
        if (snapshot.hasData && snapshot.data != null) {
          if (kIsWeb) {
            // Web users need to be verified for admin access
            return FutureBuilder<String>(
              future: PermissionService.getUserRole(),
              builder: (context, roleSnapshot) {
                if (roleSnapshot.connectionState == ConnectionState.waiting) {
                  return const Scaffold(
                    body: Center(
                      child: CircularProgressIndicator(),
                    ),
                  );
                }

                final role = roleSnapshot.data ?? 'customer';
                final email = snapshot.data?.email ?? 'unknown';

                // Only allow admin roles to access web admin panel
                if (role == 'superadmin' || role == 'admin' || role == 'staff') {
                  return AdminStaffHome(key: ValueKey('admin_$email'));
                } else {
                  return UnauthorizedAccessScreen(key: ValueKey('blocked_$email'));
                }
              },
            );
          } else {
            // Android/iOS users → Customer Home
            return const CustomerHome();
          }
        }

        // If not logged in, show login page
        return const LoginPage();
      },
    );
  }
}

/// Screen shown when user doesn't have admin permissions
class UnauthorizedAccessScreen extends StatelessWidget {
  const UnauthorizedAccessScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade900,
      body: Center(
        child: Container(
          margin: const EdgeInsets.all(24),
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.lock_outline,
                size: 64,
                color: Colors.red.shade400,
              ),
              const SizedBox(height: 16),
              const Text(
                'Access Denied',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Your account does not have permission to access the admin panel.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Please contact the system administrator if you believe this is an error.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey.shade500,
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () async {
                  await FirebaseAuth.instance.signOut();
                  if (context.mounted) {
                    Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute(builder: (context) => const ECCarwashApp()),
                      (route) => false,
                    );
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black87,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
                icon: const Icon(Icons.logout),
                label: const Text('Sign Out'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Simplified role-based navigation
void navigateToRole(BuildContext context) {
  if (kIsWeb) {
    // Web users = Admin
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const AdminStaffHome()),
    );
  } else if (Platform.isAndroid) {
    // Android users = Customer
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const CustomerHome()),
    );
  } else {
    // Default fallback (iOS/Desktop) = Staff
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const AdminStaffHome()),
    );
  }
}
