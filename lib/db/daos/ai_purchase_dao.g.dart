// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'ai_purchase_dao.dart';

// ignore_for_file: type=lint
mixin _$AiPurchaseDaoMixin on DatabaseAccessor<AppDatabase> {
  $AiPurchaseLogTable get aiPurchaseLog => attachedDatabase.aiPurchaseLog;
  AiPurchaseDaoManager get managers => AiPurchaseDaoManager(this);
}

class AiPurchaseDaoManager {
  final _$AiPurchaseDaoMixin _db;
  AiPurchaseDaoManager(this._db);
  $$AiPurchaseLogTableTableManager get aiPurchaseLog =>
      $$AiPurchaseLogTableTableManager(_db.attachedDatabase, _db.aiPurchaseLog);
}
