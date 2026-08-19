// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'ai_finance_dao.dart';

// ignore_for_file: type=lint
mixin _$AiFinanceDaoMixin on DatabaseAccessor<AppDatabase> {
  $AiFinanceLedgerTable get aiFinanceLedger => attachedDatabase.aiFinanceLedger;
  AiFinanceDaoManager get managers => AiFinanceDaoManager(this);
}

class AiFinanceDaoManager {
  final _$AiFinanceDaoMixin _db;
  AiFinanceDaoManager(this._db);
  $$AiFinanceLedgerTableTableManager get aiFinanceLedger =>
      $$AiFinanceLedgerTableTableManager(
          _db.attachedDatabase, _db.aiFinanceLedger);
}
