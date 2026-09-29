import 'package:flutter_test/flutter_test.dart';
import 'package:kumba_business/core/database/app_database.dart';
import 'package:kumba_business/core/errors/app_exception.dart';
import 'package:kumba_business/core/sync/sync_engine.dart';
import 'package:kumba_business/core/utils/id_generator.dart';
import 'package:kumba_business/shared/services/expense_service.dart';

void main() {
  late AppDatabase db;
  late ExpenseService expenses;
  late String businessId;

  setUp(() async {
    db = createTestDatabase();
    expenses = ExpenseService(db: db, sync: SyncEngine(db));
    businessId = IdGenerator.uuid();
    final now = DateTime.now();
    await db.insertBusiness(
      BusinessesCompanion.insert(
        id: businessId,
        name: 'Shop',
        ownerName: 'O',
        phone: '1',
        createdAt: now,
        updatedAt: now,
      ),
    );
  });

  tearDown(() async => db.close());

  test('owner can create expense', () async {
    final e = await expenses.create(
      businessId,
      ExpenseInput(amount: 2500, categoryName: 'Transport'),
      userRole: 'owner',
    );
    expect(e.amount, 2500);
  });

  test('delivery cannot create expense', () async {
    expect(
      () => expenses.create(
        businessId,
        ExpenseInput(amount: 1000),
        userRole: 'delivery',
      ),
      throwsA(isA<PermissionException>()),
    );
  });

  test('zero amount rejected', () async {
    expect(
      () => expenses.create(businessId, ExpenseInput(amount: 0)),
      throwsA(isA<ValidationException>()),
    );
  });
}
