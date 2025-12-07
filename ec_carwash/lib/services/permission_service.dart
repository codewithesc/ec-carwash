import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:ec_carwash/config/permissions_config.dart';

/// Service to manage user permissions and role-based access control
class PermissionService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  static String? _cachedRole;
  static String? _cachedEmail;

  /// Get current user's role - ALWAYS determined by email from config
  static Future<String> getUserRole() async {
    try {
      final User? user = _auth.currentUser;
      if (user == null) return 'guest';

      // Return cached role if available for this email
      if (_cachedRole != null && _cachedEmail == user.email) {
        return _cachedRole!;
      }

      // ALWAYS determine role by email from permissions config (source of truth)
      final emailRole = _getRoleByEmail(user.email);
      _cachedRole = emailRole;
      _cachedEmail = user.email;

      // Update Firestore with the current role (keeps it in sync)
      try {
        await _firestore.collection('Users').doc(user.uid).set({
          'role': emailRole,
          'email': user.email,
          'uid': user.uid,
          'lastRoleUpdate': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } catch (e) {
        // Ignore Firestore errors, email config is the source of truth
      }

      return emailRole;
    } catch (e) {
      return 'customer';
    }
  }

  /// Determine role based on email address
  static String _getRoleByEmail(String? email) {
    if (email == null) return 'customer';

    final normalizedEmail = email.toLowerCase();

    if (PermissionsConfig.superAdminEmails.contains(normalizedEmail)) {
      return 'superadmin';
    } else if (PermissionsConfig.adminEmails.contains(normalizedEmail)) {
      return 'admin';
    } else if (PermissionsConfig.staffEmails.contains(normalizedEmail)) {
      return 'staff';
    }

    return 'customer';
  }

  /// Check if current user has permission for a specific feature
  static Future<bool> hasPermission(String feature) async {
    try {
      final role = await getUserRole();
      final allowedRoles = PermissionsConfig.featurePermissions[feature] ?? [];
      return allowedRoles.contains(role);
    } catch (e) {
      return false;
    }
  }

  /// Check if current user's email is in the allowed list
  static Future<bool> isAuthorizedEmail(List<String> allowedEmails) async {
    try {
      final User? user = _auth.currentUser;
      if (user?.email == null) return false;

      final normalizedAllowed = allowedEmails.map((e) => e.toLowerCase()).toList();
      return normalizedAllowed.contains(user!.email!.toLowerCase());
    } catch (e) {
      return false;
    }
  }

  /// Get current user's email
  static String? getCurrentUserEmail() {
    return _auth.currentUser?.email;
  }

  /// Clear cached role (call on logout)
  static void clearCache() {
    _cachedRole = null;
    _cachedEmail = null;
  }

  /// Check if user has admin or higher privileges
  static Future<bool> isAdmin() async {
    final role = await getUserRole();
    return role == 'superadmin' || role == 'admin';
  }

  /// Check if user is super admin (owner)
  static Future<bool> isSuperAdmin() async {
    final role = await getUserRole();
    return role == 'superadmin';
  }

  /// Initialize user role in Firestore on first login
  static Future<void> initializeUserRole(String uid, String email) async {
    try {
      final role = _getRoleByEmail(email);
      await _firestore.collection('Users').doc(uid).set({
        'role': role,
        'email': email,
        'uid': uid,
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      // Silently handle error
    }
  }
}
