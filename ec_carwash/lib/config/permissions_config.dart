/// Configuration for user roles and feature permissions
class PermissionsConfig {
  /// Super Admin emails (full access - owners)
  static const List<String> superAdminEmails = ['ecsmartwash@gmail.com'];

  /// Admin emails (manager-level access)
  static const List<String> adminEmails = [
    'ecsmartwash352@gmail.com',
  ];

  /// Staff emails (limited admin access)
  static const List<String> staffEmails = [
    'eccarwashstaff@gmail.com', // Store all emails in lowercase for consistency
  ];

  /// Feature permissions mapping
  /// Define which roles can access specific features
  static const Map<String, List<String>> featurePermissions = {
    // Analytics features
    'csv_import': ['superadmin'], // Only owner can import CSV
    'analytics_view': [
      'superadmin',
      'admin',
      'staff',
    ], // All admin roles can view
    'ai_insights': ['superadmin', 'admin'], // Owner and managers only
    // Payroll features
    'payroll_view': ['superadmin', 'admin'], // Owner and managers
    'payroll_export': ['superadmin'], // Only owner
    // Expense management
    'expenses_add': ['superadmin', 'admin', 'staff'], // All admin roles
    'expenses_delete': ['superadmin', 'admin'], // Owner and managers only
    // Inventory management
    'inventory_manage': ['superadmin', 'admin', 'staff'], // All admin roles
    'inventory_delete': ['superadmin', 'admin'], // Owner and managers only
    // Service configuration
    'services_edit': ['superadmin', 'admin'], // Owner and managers
    'services_delete': ['superadmin'], // Only owner
    // POS features
    'pos_access': ['superadmin', 'admin', 'staff'], // All admin roles
    'pos_void_transaction': ['superadmin', 'admin'], // Owner and managers
    // Scheduling
    'scheduling_manage': ['superadmin', 'admin', 'staff'], // All admin roles
    // Transactions
    'transactions_view': ['superadmin', 'admin', 'staff'], // All admin roles
    'transactions_delete': ['superadmin'], // Only owner
    // Dangerous operations (if re-added for debugging)
    'delete_all_data': ['superadmin'], // Only owner
    'reset_commissions': ['superadmin'], // Only owner
  };

  /// Get role hierarchy level (higher number = more privileges)
  static int getRoleLevel(String role) {
    switch (role) {
      case 'superadmin':
        return 4;
      case 'admin':
        return 3;
      case 'staff':
        return 2;
      case 'customer':
        return 1;
      default:
        return 0;
    }
  }

  /// Check if roleA has equal or higher privileges than roleB
  static bool hasEqualOrHigherRole(String roleA, String roleB) {
    return getRoleLevel(roleA) >= getRoleLevel(roleB);
  }
}
