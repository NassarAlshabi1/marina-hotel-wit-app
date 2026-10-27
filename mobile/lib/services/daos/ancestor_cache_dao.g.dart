// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'ancestor_cache_dao.dart';

// ignore_for_file: type=lint
mixin _$AncestorCacheDaoMixin on DatabaseAccessor<AppDatabase> {
  $AncestorCacheTable get ancestorCache => attachedDatabase.ancestorCache;
  AncestorCacheDaoManager get managers => AncestorCacheDaoManager(this);
}

class AncestorCacheDaoManager {
  final _$AncestorCacheDaoMixin _db;
  AncestorCacheDaoManager(this._db);
  $$AncestorCacheTableTableManager get ancestorCache =>
      $$AncestorCacheTableTableManager(_db.attachedDatabase, _db.ancestorCache);
}
