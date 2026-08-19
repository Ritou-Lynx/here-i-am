// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'card_dao.dart';

// ignore_for_file: type=lint
mixin _$CardDaoMixin on DatabaseAccessor<AppDatabase> {
  $CardCacheTable get cardCache => attachedDatabase.cardCache;
  CardDaoManager get managers => CardDaoManager(this);
}

class CardDaoManager {
  final _$CardDaoMixin _db;
  CardDaoManager(this._db);
  $$CardCacheTableTableManager get cardCache =>
      $$CardCacheTableTableManager(_db.attachedDatabase, _db.cardCache);
}
