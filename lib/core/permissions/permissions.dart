/// Matrice des rôles et permissions KUMBA.
enum AppRole {
  owner,
  manager,
  seller,
  stockManager,
  commercial,
  delivery,
  accountant,
}

enum AppPermission {
  salesCreate,
  salesView,
  salesCancel,
  salesReturn,
  productsManage,
  stockView,
  stockAdjust,
  inventoryManage,
  customersManage,
  debtsCollect,
  debtsView,
  expensesCreate,
  expensesView,
  expensesApprove,
  suppliersManage,
  purchasesManage,
  quotesManage,
  invoicesManage,
  deliveriesManage,
  employeesManage,
  attendanceManage,
  reportsView,
  reportsSensitive,
  settingsManage,
  backupManage,
  syncManage,
  aiUse,
}

class RolePermissions {
  RolePermissions._();

  static const Map<AppRole, Set<AppPermission>> matrix = {
    AppRole.owner: {...AppPermission.values},
    AppRole.manager: {
      AppPermission.salesCreate,
      AppPermission.salesView,
      AppPermission.salesCancel,
      AppPermission.salesReturn,
      AppPermission.productsManage,
      AppPermission.stockView,
      AppPermission.stockAdjust,
      AppPermission.inventoryManage,
      AppPermission.customersManage,
      AppPermission.debtsCollect,
      AppPermission.debtsView,
      AppPermission.expensesCreate,
      AppPermission.expensesView,
      AppPermission.expensesApprove,
      AppPermission.suppliersManage,
      AppPermission.purchasesManage,
      AppPermission.quotesManage,
      AppPermission.invoicesManage,
      AppPermission.deliveriesManage,
      AppPermission.employeesManage,
      AppPermission.attendanceManage,
      AppPermission.reportsView,
      AppPermission.reportsSensitive,
      AppPermission.backupManage,
      AppPermission.settingsManage,
      AppPermission.aiUse,
    },
    AppRole.seller: {
      AppPermission.salesCreate,
      AppPermission.salesView,
      AppPermission.stockView,
      AppPermission.customersManage,
      AppPermission.debtsCollect,
      AppPermission.debtsView,
      AppPermission.quotesManage,
      AppPermission.attendanceManage,
      AppPermission.aiUse,
    },
    AppRole.stockManager: {
      AppPermission.stockView,
      AppPermission.stockAdjust,
      AppPermission.inventoryManage,
      AppPermission.productsManage,
      AppPermission.purchasesManage,
      AppPermission.suppliersManage,
      AppPermission.aiUse,
    },
    AppRole.commercial: {
      AppPermission.customersManage,
      AppPermission.quotesManage,
      AppPermission.salesCreate,
      AppPermission.salesView,
      AppPermission.deliveriesManage,
      AppPermission.aiUse,
    },
    AppRole.delivery: {AppPermission.deliveriesManage, AppPermission.salesView},
    AppRole.accountant: {
      AppPermission.salesView,
      AppPermission.expensesView,
      AppPermission.expensesApprove,
      AppPermission.debtsView,
      AppPermission.reportsView,
      AppPermission.reportsSensitive,
      AppPermission.invoicesManage,
      AppPermission.aiUse,
    },
  };

  static AppRole parseRole(String role) {
    return AppRole.values.firstWhere(
      (r) => r.name == role,
      orElse: () => AppRole.seller,
    );
  }

  static bool can(String role, AppPermission permission) {
    final r = parseRole(role);
    return matrix[r]?.contains(permission) ?? false;
  }

  static String label(AppRole role) {
    switch (role) {
      case AppRole.owner:
        return 'Propriétaire';
      case AppRole.manager:
        return 'Gérant';
      case AppRole.seller:
        return 'Vendeur';
      case AppRole.stockManager:
        return 'Responsable stock';
      case AppRole.commercial:
        return 'Commercial';
      case AppRole.delivery:
        return 'Livreur';
      case AppRole.accountant:
        return 'Comptable';
    }
  }
}
