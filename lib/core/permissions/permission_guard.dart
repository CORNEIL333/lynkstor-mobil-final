import '../errors/app_exception.dart';
import 'permissions.dart';

/// Garde d'accès métier — utilisée dans les services ET l'UI.
class PermissionGuard {
  const PermissionGuard(this.role);

  final String role;

  bool allows(AppPermission permission) =>
      RolePermissions.can(role, permission);

  void require(AppPermission permission, {String? message}) {
    if (!allows(permission)) {
      throw PermissionException(
        message ??
            'Accès refusé. Votre rôle (${RolePermissions.label(RolePermissions.parseRole(role))}) '
                'ne permet pas cette action.',
      );
    }
  }

  static PermissionGuard of(String? role) => PermissionGuard(role ?? 'seller');
}

/// Mapping route → permission minimale.
class RoutePermissions {
  RoutePermissions._();

  static final Map<String, AppPermission> map = {
    '/sale/new': AppPermission.salesCreate,
    // Onglet Vente (écran de lancement) : consultation = salesView ; la
    // création d'une vente reste gating salesCreate à l'intérieur de l'écran.
    '/vente': AppPermission.salesView,
    '/sales': AppPermission.salesView,
    '/stock': AppPermission.stockView,
    '/products': AppPermission.stockView,
    '/products/new': AppPermission.productsManage,
    '/customers': AppPermission.customersManage,
    '/debts': AppPermission.debtsView,
    '/expenses': AppPermission.expensesView,
    '/suppliers': AppPermission.suppliersManage,
    '/purchases': AppPermission.purchasesManage,
    '/inventory': AppPermission.inventoryManage,
    '/quotes': AppPermission.quotesManage,
    '/invoices': AppPermission.invoicesManage,
    '/deliveries': AppPermission.deliveriesManage,
    '/employees': AppPermission.employeesManage,
    '/attendance': AppPermission.attendanceManage,
    '/reports': AppPermission.reportsView,
    '/backup': AppPermission.backupManage,
    '/ai': AppPermission.aiUse,
    '/settings': AppPermission.settingsManage,
    '/sale/return': AppPermission.salesReturn,
  };

  static AppPermission? forPath(String path) {
    if (map.containsKey(path)) return map[path];
    // Préfixes dynamiques
    if (path.startsWith('/products/')) return AppPermission.productsManage;
    if (path.startsWith('/customers/')) return AppPermission.customersManage;
    if (path.startsWith('/sale/receipt/')) return AppPermission.salesView;
    if (path.startsWith('/sale/return/')) return AppPermission.salesReturn;
    return null;
  }
}
