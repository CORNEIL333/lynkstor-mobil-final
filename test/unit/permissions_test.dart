import 'package:flutter_test/flutter_test.dart';
import 'package:kumba_business/core/errors/app_exception.dart';
import 'package:kumba_business/core/permissions/permission_guard.dart';
import 'package:kumba_business/core/permissions/permissions.dart';

void main() {
  group('RolePermissions', () {
    test('owner has all permissions', () {
      for (final p in AppPermission.values) {
        expect(RolePermissions.can('owner', p), isTrue, reason: p.name);
      }
    });

    test('seller cannot manage backup or reports sensitive', () {
      expect(
        RolePermissions.can('seller', AppPermission.backupManage),
        isFalse,
      );
      expect(
        RolePermissions.can('seller', AppPermission.reportsSensitive),
        isFalse,
      );
      expect(RolePermissions.can('seller', AppPermission.salesCreate), isTrue);
      expect(RolePermissions.can('seller', AppPermission.salesReturn), isFalse);
    });

    test('delivery only deliveries and sales view', () {
      expect(
        RolePermissions.can('delivery', AppPermission.deliveriesManage),
        isTrue,
      );
      expect(
        RolePermissions.can('delivery', AppPermission.salesCreate),
        isFalse,
      );
      expect(
        RolePermissions.can('delivery', AppPermission.expensesCreate),
        isFalse,
      );
    });

    test('PermissionGuard.require throws for denied', () {
      final guard = PermissionGuard.of('seller');
      expect(
        () => guard.require(AppPermission.backupManage),
        throwsA(isA<PermissionException>()),
      );
    });

    test('PermissionGuard.allows for granted', () {
      expect(
        PermissionGuard.of('accountant').allows(AppPermission.reportsView),
        isTrue,
      );
      expect(
        PermissionGuard.of('accountant').allows(AppPermission.salesCreate),
        isFalse,
      );
    });
  });
}
