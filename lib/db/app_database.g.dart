// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $TasksTable extends Tasks with TableInfo<$TasksTable, Task> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TasksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
      'type', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _payloadMeta =
      const VerificationMeta('payload');
  @override
  late final GeneratedColumn<String> payload = GeneratedColumn<String>(
      'payload', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
      'status', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _priorityMeta =
      const VerificationMeta('priority');
  @override
  late final GeneratedColumn<int> priority = GeneratedColumn<int>(
      'priority', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
      'created_at', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _scheduledAtMeta =
      const VerificationMeta('scheduledAt');
  @override
  late final GeneratedColumn<int> scheduledAt = GeneratedColumn<int>(
      'scheduled_at', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _completedAtMeta =
      const VerificationMeta('completedAt');
  @override
  late final GeneratedColumn<int> completedAt = GeneratedColumn<int>(
      'completed_at', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
      'updated_at', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _retryCountMeta =
      const VerificationMeta('retryCount');
  @override
  late final GeneratedColumn<int> retryCount = GeneratedColumn<int>(
      'retry_count', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _maxRetriesMeta =
      const VerificationMeta('maxRetries');
  @override
  late final GeneratedColumn<int> maxRetries = GeneratedColumn<int>(
      'max_retries', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(3));
  static const VerificationMeta _errorMeta = const VerificationMeta('error');
  @override
  late final GeneratedColumn<String> error = GeneratedColumn<String>(
      'error', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _resultMeta = const VerificationMeta('result');
  @override
  late final GeneratedColumn<String> result = GeneratedColumn<String>(
      'result', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _bizIdMeta = const VerificationMeta('bizId');
  @override
  late final GeneratedColumn<String> bizId = GeneratedColumn<String>(
      'biz_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _dependenciesMeta =
      const VerificationMeta('dependencies');
  @override
  late final GeneratedColumn<String> dependencies = GeneratedColumn<String>(
      'dependencies', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        type,
        payload,
        status,
        priority,
        createdAt,
        scheduledAt,
        completedAt,
        updatedAt,
        retryCount,
        maxRetries,
        error,
        result,
        bizId,
        dependencies
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'tasks';
  @override
  VerificationContext validateIntegrity(Insertable<Task> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('type')) {
      context.handle(
          _typeMeta, type.isAcceptableOrUnknown(data['type']!, _typeMeta));
    } else if (isInserting) {
      context.missing(_typeMeta);
    }
    if (data.containsKey('payload')) {
      context.handle(_payloadMeta,
          payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta));
    }
    if (data.containsKey('status')) {
      context.handle(_statusMeta,
          status.isAcceptableOrUnknown(data['status']!, _statusMeta));
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
    if (data.containsKey('priority')) {
      context.handle(_priorityMeta,
          priority.isAcceptableOrUnknown(data['priority']!, _priorityMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    }
    if (data.containsKey('scheduled_at')) {
      context.handle(
          _scheduledAtMeta,
          scheduledAt.isAcceptableOrUnknown(
              data['scheduled_at']!, _scheduledAtMeta));
    }
    if (data.containsKey('completed_at')) {
      context.handle(
          _completedAtMeta,
          completedAt.isAcceptableOrUnknown(
              data['completed_at']!, _completedAtMeta));
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    }
    if (data.containsKey('retry_count')) {
      context.handle(
          _retryCountMeta,
          retryCount.isAcceptableOrUnknown(
              data['retry_count']!, _retryCountMeta));
    }
    if (data.containsKey('max_retries')) {
      context.handle(
          _maxRetriesMeta,
          maxRetries.isAcceptableOrUnknown(
              data['max_retries']!, _maxRetriesMeta));
    }
    if (data.containsKey('error')) {
      context.handle(
          _errorMeta, error.isAcceptableOrUnknown(data['error']!, _errorMeta));
    }
    if (data.containsKey('result')) {
      context.handle(_resultMeta,
          result.isAcceptableOrUnknown(data['result']!, _resultMeta));
    }
    if (data.containsKey('biz_id')) {
      context.handle(
          _bizIdMeta, bizId.isAcceptableOrUnknown(data['biz_id']!, _bizIdMeta));
    }
    if (data.containsKey('dependencies')) {
      context.handle(
          _dependenciesMeta,
          dependencies.isAcceptableOrUnknown(
              data['dependencies']!, _dependenciesMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Task map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Task(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      type: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}type'])!,
      payload: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}payload']),
      status: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}status'])!,
      priority: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}priority'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}created_at']),
      scheduledAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}scheduled_at']),
      completedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}completed_at']),
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}updated_at']),
      retryCount: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}retry_count'])!,
      maxRetries: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}max_retries'])!,
      error: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}error']),
      result: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}result']),
      bizId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}biz_id']),
      dependencies: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}dependencies']),
    );
  }

  @override
  $TasksTable createAlias(String alias) {
    return $TasksTable(attachedDatabase, alias);
  }
}

class Task extends DataClass implements Insertable<Task> {
  final String id;
  final String type;
  final String? payload;
  final String status;
  final int priority;
  final int? createdAt;
  final int? scheduledAt;
  final int? completedAt;
  final int? updatedAt;
  final int retryCount;
  final int maxRetries;
  final String? error;
  final String? result;
  final String? bizId;
  final String? dependencies;
  const Task(
      {required this.id,
      required this.type,
      this.payload,
      required this.status,
      required this.priority,
      this.createdAt,
      this.scheduledAt,
      this.completedAt,
      this.updatedAt,
      required this.retryCount,
      required this.maxRetries,
      this.error,
      this.result,
      this.bizId,
      this.dependencies});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['type'] = Variable<String>(type);
    if (!nullToAbsent || payload != null) {
      map['payload'] = Variable<String>(payload);
    }
    map['status'] = Variable<String>(status);
    map['priority'] = Variable<int>(priority);
    if (!nullToAbsent || createdAt != null) {
      map['created_at'] = Variable<int>(createdAt);
    }
    if (!nullToAbsent || scheduledAt != null) {
      map['scheduled_at'] = Variable<int>(scheduledAt);
    }
    if (!nullToAbsent || completedAt != null) {
      map['completed_at'] = Variable<int>(completedAt);
    }
    if (!nullToAbsent || updatedAt != null) {
      map['updated_at'] = Variable<int>(updatedAt);
    }
    map['retry_count'] = Variable<int>(retryCount);
    map['max_retries'] = Variable<int>(maxRetries);
    if (!nullToAbsent || error != null) {
      map['error'] = Variable<String>(error);
    }
    if (!nullToAbsent || result != null) {
      map['result'] = Variable<String>(result);
    }
    if (!nullToAbsent || bizId != null) {
      map['biz_id'] = Variable<String>(bizId);
    }
    if (!nullToAbsent || dependencies != null) {
      map['dependencies'] = Variable<String>(dependencies);
    }
    return map;
  }

  TasksCompanion toCompanion(bool nullToAbsent) {
    return TasksCompanion(
      id: Value(id),
      type: Value(type),
      payload: payload == null && nullToAbsent
          ? const Value.absent()
          : Value(payload),
      status: Value(status),
      priority: Value(priority),
      createdAt: createdAt == null && nullToAbsent
          ? const Value.absent()
          : Value(createdAt),
      scheduledAt: scheduledAt == null && nullToAbsent
          ? const Value.absent()
          : Value(scheduledAt),
      completedAt: completedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(completedAt),
      updatedAt: updatedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(updatedAt),
      retryCount: Value(retryCount),
      maxRetries: Value(maxRetries),
      error:
          error == null && nullToAbsent ? const Value.absent() : Value(error),
      result:
          result == null && nullToAbsent ? const Value.absent() : Value(result),
      bizId:
          bizId == null && nullToAbsent ? const Value.absent() : Value(bizId),
      dependencies: dependencies == null && nullToAbsent
          ? const Value.absent()
          : Value(dependencies),
    );
  }

  factory Task.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Task(
      id: serializer.fromJson<String>(json['id']),
      type: serializer.fromJson<String>(json['type']),
      payload: serializer.fromJson<String?>(json['payload']),
      status: serializer.fromJson<String>(json['status']),
      priority: serializer.fromJson<int>(json['priority']),
      createdAt: serializer.fromJson<int?>(json['createdAt']),
      scheduledAt: serializer.fromJson<int?>(json['scheduledAt']),
      completedAt: serializer.fromJson<int?>(json['completedAt']),
      updatedAt: serializer.fromJson<int?>(json['updatedAt']),
      retryCount: serializer.fromJson<int>(json['retryCount']),
      maxRetries: serializer.fromJson<int>(json['maxRetries']),
      error: serializer.fromJson<String?>(json['error']),
      result: serializer.fromJson<String?>(json['result']),
      bizId: serializer.fromJson<String?>(json['bizId']),
      dependencies: serializer.fromJson<String?>(json['dependencies']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'type': serializer.toJson<String>(type),
      'payload': serializer.toJson<String?>(payload),
      'status': serializer.toJson<String>(status),
      'priority': serializer.toJson<int>(priority),
      'createdAt': serializer.toJson<int?>(createdAt),
      'scheduledAt': serializer.toJson<int?>(scheduledAt),
      'completedAt': serializer.toJson<int?>(completedAt),
      'updatedAt': serializer.toJson<int?>(updatedAt),
      'retryCount': serializer.toJson<int>(retryCount),
      'maxRetries': serializer.toJson<int>(maxRetries),
      'error': serializer.toJson<String?>(error),
      'result': serializer.toJson<String?>(result),
      'bizId': serializer.toJson<String?>(bizId),
      'dependencies': serializer.toJson<String?>(dependencies),
    };
  }

  Task copyWith(
          {String? id,
          String? type,
          Value<String?> payload = const Value.absent(),
          String? status,
          int? priority,
          Value<int?> createdAt = const Value.absent(),
          Value<int?> scheduledAt = const Value.absent(),
          Value<int?> completedAt = const Value.absent(),
          Value<int?> updatedAt = const Value.absent(),
          int? retryCount,
          int? maxRetries,
          Value<String?> error = const Value.absent(),
          Value<String?> result = const Value.absent(),
          Value<String?> bizId = const Value.absent(),
          Value<String?> dependencies = const Value.absent()}) =>
      Task(
        id: id ?? this.id,
        type: type ?? this.type,
        payload: payload.present ? payload.value : this.payload,
        status: status ?? this.status,
        priority: priority ?? this.priority,
        createdAt: createdAt.present ? createdAt.value : this.createdAt,
        scheduledAt: scheduledAt.present ? scheduledAt.value : this.scheduledAt,
        completedAt: completedAt.present ? completedAt.value : this.completedAt,
        updatedAt: updatedAt.present ? updatedAt.value : this.updatedAt,
        retryCount: retryCount ?? this.retryCount,
        maxRetries: maxRetries ?? this.maxRetries,
        error: error.present ? error.value : this.error,
        result: result.present ? result.value : this.result,
        bizId: bizId.present ? bizId.value : this.bizId,
        dependencies:
            dependencies.present ? dependencies.value : this.dependencies,
      );
  Task copyWithCompanion(TasksCompanion data) {
    return Task(
      id: data.id.present ? data.id.value : this.id,
      type: data.type.present ? data.type.value : this.type,
      payload: data.payload.present ? data.payload.value : this.payload,
      status: data.status.present ? data.status.value : this.status,
      priority: data.priority.present ? data.priority.value : this.priority,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      scheduledAt:
          data.scheduledAt.present ? data.scheduledAt.value : this.scheduledAt,
      completedAt:
          data.completedAt.present ? data.completedAt.value : this.completedAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      retryCount:
          data.retryCount.present ? data.retryCount.value : this.retryCount,
      maxRetries:
          data.maxRetries.present ? data.maxRetries.value : this.maxRetries,
      error: data.error.present ? data.error.value : this.error,
      result: data.result.present ? data.result.value : this.result,
      bizId: data.bizId.present ? data.bizId.value : this.bizId,
      dependencies: data.dependencies.present
          ? data.dependencies.value
          : this.dependencies,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Task(')
          ..write('id: $id, ')
          ..write('type: $type, ')
          ..write('payload: $payload, ')
          ..write('status: $status, ')
          ..write('priority: $priority, ')
          ..write('createdAt: $createdAt, ')
          ..write('scheduledAt: $scheduledAt, ')
          ..write('completedAt: $completedAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('retryCount: $retryCount, ')
          ..write('maxRetries: $maxRetries, ')
          ..write('error: $error, ')
          ..write('result: $result, ')
          ..write('bizId: $bizId, ')
          ..write('dependencies: $dependencies')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id,
      type,
      payload,
      status,
      priority,
      createdAt,
      scheduledAt,
      completedAt,
      updatedAt,
      retryCount,
      maxRetries,
      error,
      result,
      bizId,
      dependencies);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Task &&
          other.id == this.id &&
          other.type == this.type &&
          other.payload == this.payload &&
          other.status == this.status &&
          other.priority == this.priority &&
          other.createdAt == this.createdAt &&
          other.scheduledAt == this.scheduledAt &&
          other.completedAt == this.completedAt &&
          other.updatedAt == this.updatedAt &&
          other.retryCount == this.retryCount &&
          other.maxRetries == this.maxRetries &&
          other.error == this.error &&
          other.result == this.result &&
          other.bizId == this.bizId &&
          other.dependencies == this.dependencies);
}

class TasksCompanion extends UpdateCompanion<Task> {
  final Value<String> id;
  final Value<String> type;
  final Value<String?> payload;
  final Value<String> status;
  final Value<int> priority;
  final Value<int?> createdAt;
  final Value<int?> scheduledAt;
  final Value<int?> completedAt;
  final Value<int?> updatedAt;
  final Value<int> retryCount;
  final Value<int> maxRetries;
  final Value<String?> error;
  final Value<String?> result;
  final Value<String?> bizId;
  final Value<String?> dependencies;
  final Value<int> rowid;
  const TasksCompanion({
    this.id = const Value.absent(),
    this.type = const Value.absent(),
    this.payload = const Value.absent(),
    this.status = const Value.absent(),
    this.priority = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.scheduledAt = const Value.absent(),
    this.completedAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.retryCount = const Value.absent(),
    this.maxRetries = const Value.absent(),
    this.error = const Value.absent(),
    this.result = const Value.absent(),
    this.bizId = const Value.absent(),
    this.dependencies = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TasksCompanion.insert({
    required String id,
    required String type,
    this.payload = const Value.absent(),
    required String status,
    this.priority = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.scheduledAt = const Value.absent(),
    this.completedAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.retryCount = const Value.absent(),
    this.maxRetries = const Value.absent(),
    this.error = const Value.absent(),
    this.result = const Value.absent(),
    this.bizId = const Value.absent(),
    this.dependencies = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        type = Value(type),
        status = Value(status);
  static Insertable<Task> custom({
    Expression<String>? id,
    Expression<String>? type,
    Expression<String>? payload,
    Expression<String>? status,
    Expression<int>? priority,
    Expression<int>? createdAt,
    Expression<int>? scheduledAt,
    Expression<int>? completedAt,
    Expression<int>? updatedAt,
    Expression<int>? retryCount,
    Expression<int>? maxRetries,
    Expression<String>? error,
    Expression<String>? result,
    Expression<String>? bizId,
    Expression<String>? dependencies,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (type != null) 'type': type,
      if (payload != null) 'payload': payload,
      if (status != null) 'status': status,
      if (priority != null) 'priority': priority,
      if (createdAt != null) 'created_at': createdAt,
      if (scheduledAt != null) 'scheduled_at': scheduledAt,
      if (completedAt != null) 'completed_at': completedAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (retryCount != null) 'retry_count': retryCount,
      if (maxRetries != null) 'max_retries': maxRetries,
      if (error != null) 'error': error,
      if (result != null) 'result': result,
      if (bizId != null) 'biz_id': bizId,
      if (dependencies != null) 'dependencies': dependencies,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TasksCompanion copyWith(
      {Value<String>? id,
      Value<String>? type,
      Value<String?>? payload,
      Value<String>? status,
      Value<int>? priority,
      Value<int?>? createdAt,
      Value<int?>? scheduledAt,
      Value<int?>? completedAt,
      Value<int?>? updatedAt,
      Value<int>? retryCount,
      Value<int>? maxRetries,
      Value<String?>? error,
      Value<String?>? result,
      Value<String?>? bizId,
      Value<String?>? dependencies,
      Value<int>? rowid}) {
    return TasksCompanion(
      id: id ?? this.id,
      type: type ?? this.type,
      payload: payload ?? this.payload,
      status: status ?? this.status,
      priority: priority ?? this.priority,
      createdAt: createdAt ?? this.createdAt,
      scheduledAt: scheduledAt ?? this.scheduledAt,
      completedAt: completedAt ?? this.completedAt,
      updatedAt: updatedAt ?? this.updatedAt,
      retryCount: retryCount ?? this.retryCount,
      maxRetries: maxRetries ?? this.maxRetries,
      error: error ?? this.error,
      result: result ?? this.result,
      bizId: bizId ?? this.bizId,
      dependencies: dependencies ?? this.dependencies,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (payload.present) {
      map['payload'] = Variable<String>(payload.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (priority.present) {
      map['priority'] = Variable<int>(priority.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (scheduledAt.present) {
      map['scheduled_at'] = Variable<int>(scheduledAt.value);
    }
    if (completedAt.present) {
      map['completed_at'] = Variable<int>(completedAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (retryCount.present) {
      map['retry_count'] = Variable<int>(retryCount.value);
    }
    if (maxRetries.present) {
      map['max_retries'] = Variable<int>(maxRetries.value);
    }
    if (error.present) {
      map['error'] = Variable<String>(error.value);
    }
    if (result.present) {
      map['result'] = Variable<String>(result.value);
    }
    if (bizId.present) {
      map['biz_id'] = Variable<String>(bizId.value);
    }
    if (dependencies.present) {
      map['dependencies'] = Variable<String>(dependencies.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TasksCompanion(')
          ..write('id: $id, ')
          ..write('type: $type, ')
          ..write('payload: $payload, ')
          ..write('status: $status, ')
          ..write('priority: $priority, ')
          ..write('createdAt: $createdAt, ')
          ..write('scheduledAt: $scheduledAt, ')
          ..write('completedAt: $completedAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('retryCount: $retryCount, ')
          ..write('maxRetries: $maxRetries, ')
          ..write('error: $error, ')
          ..write('result: $result, ')
          ..write('bizId: $bizId, ')
          ..write('dependencies: $dependencies, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $KvStoreTable extends KvStore with TableInfo<$KvStoreTable, KvStoreData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $KvStoreTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
      'key', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
      'value', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _bucketMeta = const VerificationMeta('bucket');
  @override
  late final GeneratedColumn<String> bucket = GeneratedColumn<String>(
      'bucket', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
      'updated_at', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns => [key, value, bucket, updatedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'kv_store';
  @override
  VerificationContext validateIntegrity(Insertable<KvStoreData> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
          _keyMeta, key.isAcceptableOrUnknown(data['key']!, _keyMeta));
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
          _valueMeta, value.isAcceptableOrUnknown(data['value']!, _valueMeta));
    }
    if (data.containsKey('bucket')) {
      context.handle(_bucketMeta,
          bucket.isAcceptableOrUnknown(data['bucket']!, _bucketMeta));
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  KvStoreData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return KvStoreData(
      key: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}key'])!,
      value: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}value']),
      bucket: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}bucket']),
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}updated_at']),
    );
  }

  @override
  $KvStoreTable createAlias(String alias) {
    return $KvStoreTable(attachedDatabase, alias);
  }
}

class KvStoreData extends DataClass implements Insertable<KvStoreData> {
  final String key;
  final String? value;
  final String? bucket;
  final int? updatedAt;
  const KvStoreData(
      {required this.key, this.value, this.bucket, this.updatedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    if (!nullToAbsent || value != null) {
      map['value'] = Variable<String>(value);
    }
    if (!nullToAbsent || bucket != null) {
      map['bucket'] = Variable<String>(bucket);
    }
    if (!nullToAbsent || updatedAt != null) {
      map['updated_at'] = Variable<int>(updatedAt);
    }
    return map;
  }

  KvStoreCompanion toCompanion(bool nullToAbsent) {
    return KvStoreCompanion(
      key: Value(key),
      value:
          value == null && nullToAbsent ? const Value.absent() : Value(value),
      bucket:
          bucket == null && nullToAbsent ? const Value.absent() : Value(bucket),
      updatedAt: updatedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(updatedAt),
    );
  }

  factory KvStoreData.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return KvStoreData(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String?>(json['value']),
      bucket: serializer.fromJson<String?>(json['bucket']),
      updatedAt: serializer.fromJson<int?>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String?>(value),
      'bucket': serializer.toJson<String?>(bucket),
      'updatedAt': serializer.toJson<int?>(updatedAt),
    };
  }

  KvStoreData copyWith(
          {String? key,
          Value<String?> value = const Value.absent(),
          Value<String?> bucket = const Value.absent(),
          Value<int?> updatedAt = const Value.absent()}) =>
      KvStoreData(
        key: key ?? this.key,
        value: value.present ? value.value : this.value,
        bucket: bucket.present ? bucket.value : this.bucket,
        updatedAt: updatedAt.present ? updatedAt.value : this.updatedAt,
      );
  KvStoreData copyWithCompanion(KvStoreCompanion data) {
    return KvStoreData(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
      bucket: data.bucket.present ? data.bucket.value : this.bucket,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('KvStoreData(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('bucket: $bucket, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value, bucket, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is KvStoreData &&
          other.key == this.key &&
          other.value == this.value &&
          other.bucket == this.bucket &&
          other.updatedAt == this.updatedAt);
}

class KvStoreCompanion extends UpdateCompanion<KvStoreData> {
  final Value<String> key;
  final Value<String?> value;
  final Value<String?> bucket;
  final Value<int?> updatedAt;
  final Value<int> rowid;
  const KvStoreCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.bucket = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  KvStoreCompanion.insert({
    required String key,
    this.value = const Value.absent(),
    this.bucket = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : key = Value(key);
  static Insertable<KvStoreData> custom({
    Expression<String>? key,
    Expression<String>? value,
    Expression<String>? bucket,
    Expression<int>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (bucket != null) 'bucket': bucket,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  KvStoreCompanion copyWith(
      {Value<String>? key,
      Value<String?>? value,
      Value<String?>? bucket,
      Value<int?>? updatedAt,
      Value<int>? rowid}) {
    return KvStoreCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      bucket: bucket ?? this.bucket,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (bucket.present) {
      map['bucket'] = Variable<String>(bucket.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('KvStoreCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('bucket: $bucket, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AgentActivityMessagesTable extends AgentActivityMessages
    with TableInfo<$AgentActivityMessagesTable, AgentActivityMessage> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AgentActivityMessagesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
      'type', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
      'title', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _contentMeta =
      const VerificationMeta('content');
  @override
  late final GeneratedColumn<String> content = GeneratedColumn<String>(
      'content', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _iconMeta = const VerificationMeta('icon');
  @override
  late final GeneratedColumn<String> icon = GeneratedColumn<String>(
      'icon', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _agentNameMeta =
      const VerificationMeta('agentName');
  @override
  late final GeneratedColumn<String> agentName = GeneratedColumn<String>(
      'agent_name', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('Unknown'));
  static const VerificationMeta _agentIdMeta =
      const VerificationMeta('agentId');
  @override
  late final GeneratedColumn<String> agentId = GeneratedColumn<String>(
      'agent_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _sceneMeta = const VerificationMeta('scene');
  @override
  late final GeneratedColumn<String> scene = GeneratedColumn<String>(
      'scene', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _sceneIdMeta =
      const VerificationMeta('sceneId');
  @override
  late final GeneratedColumn<String> sceneId = GeneratedColumn<String>(
      'scene_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
      'user_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _timestampMeta =
      const VerificationMeta('timestamp');
  @override
  late final GeneratedColumn<DateTime> timestamp = GeneratedColumn<DateTime>(
      'timestamp', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        type,
        title,
        content,
        icon,
        agentName,
        agentId,
        scene,
        sceneId,
        userId,
        timestamp
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'agent_activity_messages';
  @override
  VerificationContext validateIntegrity(
      Insertable<AgentActivityMessage> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('type')) {
      context.handle(
          _typeMeta, type.isAcceptableOrUnknown(data['type']!, _typeMeta));
    } else if (isInserting) {
      context.missing(_typeMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
          _titleMeta, title.isAcceptableOrUnknown(data['title']!, _titleMeta));
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('content')) {
      context.handle(_contentMeta,
          content.isAcceptableOrUnknown(data['content']!, _contentMeta));
    }
    if (data.containsKey('icon')) {
      context.handle(
          _iconMeta, icon.isAcceptableOrUnknown(data['icon']!, _iconMeta));
    }
    if (data.containsKey('agent_name')) {
      context.handle(_agentNameMeta,
          agentName.isAcceptableOrUnknown(data['agent_name']!, _agentNameMeta));
    }
    if (data.containsKey('agent_id')) {
      context.handle(_agentIdMeta,
          agentId.isAcceptableOrUnknown(data['agent_id']!, _agentIdMeta));
    }
    if (data.containsKey('scene')) {
      context.handle(
          _sceneMeta, scene.isAcceptableOrUnknown(data['scene']!, _sceneMeta));
    }
    if (data.containsKey('scene_id')) {
      context.handle(_sceneIdMeta,
          sceneId.isAcceptableOrUnknown(data['scene_id']!, _sceneIdMeta));
    }
    if (data.containsKey('user_id')) {
      context.handle(_userIdMeta,
          userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta));
    }
    if (data.containsKey('timestamp')) {
      context.handle(_timestampMeta,
          timestamp.isAcceptableOrUnknown(data['timestamp']!, _timestampMeta));
    } else if (isInserting) {
      context.missing(_timestampMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  AgentActivityMessage map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AgentActivityMessage(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      type: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}type'])!,
      title: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}title'])!,
      content: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}content']),
      icon: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}icon']),
      agentName: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}agent_name'])!,
      agentId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}agent_id']),
      scene: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}scene']),
      sceneId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}scene_id']),
      userId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}user_id']),
      timestamp: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}timestamp'])!,
    );
  }

  @override
  $AgentActivityMessagesTable createAlias(String alias) {
    return $AgentActivityMessagesTable(attachedDatabase, alias);
  }
}

class AgentActivityMessage extends DataClass
    implements Insertable<AgentActivityMessage> {
  final int id;
  final String type;
  final String title;
  final String? content;
  final String? icon;
  final String agentName;
  final String? agentId;
  final String? scene;
  final String? sceneId;
  final String? userId;
  final DateTime timestamp;
  const AgentActivityMessage(
      {required this.id,
      required this.type,
      required this.title,
      this.content,
      this.icon,
      required this.agentName,
      this.agentId,
      this.scene,
      this.sceneId,
      this.userId,
      required this.timestamp});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['type'] = Variable<String>(type);
    map['title'] = Variable<String>(title);
    if (!nullToAbsent || content != null) {
      map['content'] = Variable<String>(content);
    }
    if (!nullToAbsent || icon != null) {
      map['icon'] = Variable<String>(icon);
    }
    map['agent_name'] = Variable<String>(agentName);
    if (!nullToAbsent || agentId != null) {
      map['agent_id'] = Variable<String>(agentId);
    }
    if (!nullToAbsent || scene != null) {
      map['scene'] = Variable<String>(scene);
    }
    if (!nullToAbsent || sceneId != null) {
      map['scene_id'] = Variable<String>(sceneId);
    }
    if (!nullToAbsent || userId != null) {
      map['user_id'] = Variable<String>(userId);
    }
    map['timestamp'] = Variable<DateTime>(timestamp);
    return map;
  }

  AgentActivityMessagesCompanion toCompanion(bool nullToAbsent) {
    return AgentActivityMessagesCompanion(
      id: Value(id),
      type: Value(type),
      title: Value(title),
      content: content == null && nullToAbsent
          ? const Value.absent()
          : Value(content),
      icon: icon == null && nullToAbsent ? const Value.absent() : Value(icon),
      agentName: Value(agentName),
      agentId: agentId == null && nullToAbsent
          ? const Value.absent()
          : Value(agentId),
      scene:
          scene == null && nullToAbsent ? const Value.absent() : Value(scene),
      sceneId: sceneId == null && nullToAbsent
          ? const Value.absent()
          : Value(sceneId),
      userId:
          userId == null && nullToAbsent ? const Value.absent() : Value(userId),
      timestamp: Value(timestamp),
    );
  }

  factory AgentActivityMessage.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AgentActivityMessage(
      id: serializer.fromJson<int>(json['id']),
      type: serializer.fromJson<String>(json['type']),
      title: serializer.fromJson<String>(json['title']),
      content: serializer.fromJson<String?>(json['content']),
      icon: serializer.fromJson<String?>(json['icon']),
      agentName: serializer.fromJson<String>(json['agentName']),
      agentId: serializer.fromJson<String?>(json['agentId']),
      scene: serializer.fromJson<String?>(json['scene']),
      sceneId: serializer.fromJson<String?>(json['sceneId']),
      userId: serializer.fromJson<String?>(json['userId']),
      timestamp: serializer.fromJson<DateTime>(json['timestamp']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'type': serializer.toJson<String>(type),
      'title': serializer.toJson<String>(title),
      'content': serializer.toJson<String?>(content),
      'icon': serializer.toJson<String?>(icon),
      'agentName': serializer.toJson<String>(agentName),
      'agentId': serializer.toJson<String?>(agentId),
      'scene': serializer.toJson<String?>(scene),
      'sceneId': serializer.toJson<String?>(sceneId),
      'userId': serializer.toJson<String?>(userId),
      'timestamp': serializer.toJson<DateTime>(timestamp),
    };
  }

  AgentActivityMessage copyWith(
          {int? id,
          String? type,
          String? title,
          Value<String?> content = const Value.absent(),
          Value<String?> icon = const Value.absent(),
          String? agentName,
          Value<String?> agentId = const Value.absent(),
          Value<String?> scene = const Value.absent(),
          Value<String?> sceneId = const Value.absent(),
          Value<String?> userId = const Value.absent(),
          DateTime? timestamp}) =>
      AgentActivityMessage(
        id: id ?? this.id,
        type: type ?? this.type,
        title: title ?? this.title,
        content: content.present ? content.value : this.content,
        icon: icon.present ? icon.value : this.icon,
        agentName: agentName ?? this.agentName,
        agentId: agentId.present ? agentId.value : this.agentId,
        scene: scene.present ? scene.value : this.scene,
        sceneId: sceneId.present ? sceneId.value : this.sceneId,
        userId: userId.present ? userId.value : this.userId,
        timestamp: timestamp ?? this.timestamp,
      );
  AgentActivityMessage copyWithCompanion(AgentActivityMessagesCompanion data) {
    return AgentActivityMessage(
      id: data.id.present ? data.id.value : this.id,
      type: data.type.present ? data.type.value : this.type,
      title: data.title.present ? data.title.value : this.title,
      content: data.content.present ? data.content.value : this.content,
      icon: data.icon.present ? data.icon.value : this.icon,
      agentName: data.agentName.present ? data.agentName.value : this.agentName,
      agentId: data.agentId.present ? data.agentId.value : this.agentId,
      scene: data.scene.present ? data.scene.value : this.scene,
      sceneId: data.sceneId.present ? data.sceneId.value : this.sceneId,
      userId: data.userId.present ? data.userId.value : this.userId,
      timestamp: data.timestamp.present ? data.timestamp.value : this.timestamp,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AgentActivityMessage(')
          ..write('id: $id, ')
          ..write('type: $type, ')
          ..write('title: $title, ')
          ..write('content: $content, ')
          ..write('icon: $icon, ')
          ..write('agentName: $agentName, ')
          ..write('agentId: $agentId, ')
          ..write('scene: $scene, ')
          ..write('sceneId: $sceneId, ')
          ..write('userId: $userId, ')
          ..write('timestamp: $timestamp')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, type, title, content, icon, agentName,
      agentId, scene, sceneId, userId, timestamp);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AgentActivityMessage &&
          other.id == this.id &&
          other.type == this.type &&
          other.title == this.title &&
          other.content == this.content &&
          other.icon == this.icon &&
          other.agentName == this.agentName &&
          other.agentId == this.agentId &&
          other.scene == this.scene &&
          other.sceneId == this.sceneId &&
          other.userId == this.userId &&
          other.timestamp == this.timestamp);
}

class AgentActivityMessagesCompanion
    extends UpdateCompanion<AgentActivityMessage> {
  final Value<int> id;
  final Value<String> type;
  final Value<String> title;
  final Value<String?> content;
  final Value<String?> icon;
  final Value<String> agentName;
  final Value<String?> agentId;
  final Value<String?> scene;
  final Value<String?> sceneId;
  final Value<String?> userId;
  final Value<DateTime> timestamp;
  const AgentActivityMessagesCompanion({
    this.id = const Value.absent(),
    this.type = const Value.absent(),
    this.title = const Value.absent(),
    this.content = const Value.absent(),
    this.icon = const Value.absent(),
    this.agentName = const Value.absent(),
    this.agentId = const Value.absent(),
    this.scene = const Value.absent(),
    this.sceneId = const Value.absent(),
    this.userId = const Value.absent(),
    this.timestamp = const Value.absent(),
  });
  AgentActivityMessagesCompanion.insert({
    this.id = const Value.absent(),
    required String type,
    required String title,
    this.content = const Value.absent(),
    this.icon = const Value.absent(),
    this.agentName = const Value.absent(),
    this.agentId = const Value.absent(),
    this.scene = const Value.absent(),
    this.sceneId = const Value.absent(),
    this.userId = const Value.absent(),
    required DateTime timestamp,
  })  : type = Value(type),
        title = Value(title),
        timestamp = Value(timestamp);
  static Insertable<AgentActivityMessage> custom({
    Expression<int>? id,
    Expression<String>? type,
    Expression<String>? title,
    Expression<String>? content,
    Expression<String>? icon,
    Expression<String>? agentName,
    Expression<String>? agentId,
    Expression<String>? scene,
    Expression<String>? sceneId,
    Expression<String>? userId,
    Expression<DateTime>? timestamp,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (type != null) 'type': type,
      if (title != null) 'title': title,
      if (content != null) 'content': content,
      if (icon != null) 'icon': icon,
      if (agentName != null) 'agent_name': agentName,
      if (agentId != null) 'agent_id': agentId,
      if (scene != null) 'scene': scene,
      if (sceneId != null) 'scene_id': sceneId,
      if (userId != null) 'user_id': userId,
      if (timestamp != null) 'timestamp': timestamp,
    });
  }

  AgentActivityMessagesCompanion copyWith(
      {Value<int>? id,
      Value<String>? type,
      Value<String>? title,
      Value<String?>? content,
      Value<String?>? icon,
      Value<String>? agentName,
      Value<String?>? agentId,
      Value<String?>? scene,
      Value<String?>? sceneId,
      Value<String?>? userId,
      Value<DateTime>? timestamp}) {
    return AgentActivityMessagesCompanion(
      id: id ?? this.id,
      type: type ?? this.type,
      title: title ?? this.title,
      content: content ?? this.content,
      icon: icon ?? this.icon,
      agentName: agentName ?? this.agentName,
      agentId: agentId ?? this.agentId,
      scene: scene ?? this.scene,
      sceneId: sceneId ?? this.sceneId,
      userId: userId ?? this.userId,
      timestamp: timestamp ?? this.timestamp,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (content.present) {
      map['content'] = Variable<String>(content.value);
    }
    if (icon.present) {
      map['icon'] = Variable<String>(icon.value);
    }
    if (agentName.present) {
      map['agent_name'] = Variable<String>(agentName.value);
    }
    if (agentId.present) {
      map['agent_id'] = Variable<String>(agentId.value);
    }
    if (scene.present) {
      map['scene'] = Variable<String>(scene.value);
    }
    if (sceneId.present) {
      map['scene_id'] = Variable<String>(sceneId.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (timestamp.present) {
      map['timestamp'] = Variable<DateTime>(timestamp.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AgentActivityMessagesCompanion(')
          ..write('id: $id, ')
          ..write('type: $type, ')
          ..write('title: $title, ')
          ..write('content: $content, ')
          ..write('icon: $icon, ')
          ..write('agentName: $agentName, ')
          ..write('agentId: $agentId, ')
          ..write('scene: $scene, ')
          ..write('sceneId: $sceneId, ')
          ..write('userId: $userId, ')
          ..write('timestamp: $timestamp')
          ..write(')'))
        .toString();
  }
}

class $CardCacheTable extends CardCache
    with TableInfo<$CardCacheTable, CardCacheData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CardCacheTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _factIdMeta = const VerificationMeta('factId');
  @override
  late final GeneratedColumn<String> factId = GeneratedColumn<String>(
      'fact_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _cardPathMeta =
      const VerificationMeta('cardPath');
  @override
  late final GeneratedColumn<String> cardPath = GeneratedColumn<String>(
      'card_path', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _timestampMeta =
      const VerificationMeta('timestamp');
  @override
  late final GeneratedColumn<int> timestamp = GeneratedColumn<int>(
      'timestamp', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _tagsMeta = const VerificationMeta('tags');
  @override
  late final GeneratedColumn<String> tags = GeneratedColumn<String>(
      'tags', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [factId, cardPath, timestamp, tags];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'card_cache';
  @override
  VerificationContext validateIntegrity(Insertable<CardCacheData> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('fact_id')) {
      context.handle(_factIdMeta,
          factId.isAcceptableOrUnknown(data['fact_id']!, _factIdMeta));
    } else if (isInserting) {
      context.missing(_factIdMeta);
    }
    if (data.containsKey('card_path')) {
      context.handle(_cardPathMeta,
          cardPath.isAcceptableOrUnknown(data['card_path']!, _cardPathMeta));
    } else if (isInserting) {
      context.missing(_cardPathMeta);
    }
    if (data.containsKey('timestamp')) {
      context.handle(_timestampMeta,
          timestamp.isAcceptableOrUnknown(data['timestamp']!, _timestampMeta));
    } else if (isInserting) {
      context.missing(_timestampMeta);
    }
    if (data.containsKey('tags')) {
      context.handle(
          _tagsMeta, tags.isAcceptableOrUnknown(data['tags']!, _tagsMeta));
    } else if (isInserting) {
      context.missing(_tagsMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {factId};
  @override
  CardCacheData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CardCacheData(
      factId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}fact_id'])!,
      cardPath: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}card_path'])!,
      timestamp: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}timestamp'])!,
      tags: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}tags'])!,
    );
  }

  @override
  $CardCacheTable createAlias(String alias) {
    return $CardCacheTable(attachedDatabase, alias);
  }
}

class CardCacheData extends DataClass implements Insertable<CardCacheData> {
  final String factId;
  final String cardPath;
  final int timestamp;
  final String tags;
  const CardCacheData(
      {required this.factId,
      required this.cardPath,
      required this.timestamp,
      required this.tags});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['fact_id'] = Variable<String>(factId);
    map['card_path'] = Variable<String>(cardPath);
    map['timestamp'] = Variable<int>(timestamp);
    map['tags'] = Variable<String>(tags);
    return map;
  }

  CardCacheCompanion toCompanion(bool nullToAbsent) {
    return CardCacheCompanion(
      factId: Value(factId),
      cardPath: Value(cardPath),
      timestamp: Value(timestamp),
      tags: Value(tags),
    );
  }

  factory CardCacheData.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CardCacheData(
      factId: serializer.fromJson<String>(json['factId']),
      cardPath: serializer.fromJson<String>(json['cardPath']),
      timestamp: serializer.fromJson<int>(json['timestamp']),
      tags: serializer.fromJson<String>(json['tags']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'factId': serializer.toJson<String>(factId),
      'cardPath': serializer.toJson<String>(cardPath),
      'timestamp': serializer.toJson<int>(timestamp),
      'tags': serializer.toJson<String>(tags),
    };
  }

  CardCacheData copyWith(
          {String? factId, String? cardPath, int? timestamp, String? tags}) =>
      CardCacheData(
        factId: factId ?? this.factId,
        cardPath: cardPath ?? this.cardPath,
        timestamp: timestamp ?? this.timestamp,
        tags: tags ?? this.tags,
      );
  CardCacheData copyWithCompanion(CardCacheCompanion data) {
    return CardCacheData(
      factId: data.factId.present ? data.factId.value : this.factId,
      cardPath: data.cardPath.present ? data.cardPath.value : this.cardPath,
      timestamp: data.timestamp.present ? data.timestamp.value : this.timestamp,
      tags: data.tags.present ? data.tags.value : this.tags,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CardCacheData(')
          ..write('factId: $factId, ')
          ..write('cardPath: $cardPath, ')
          ..write('timestamp: $timestamp, ')
          ..write('tags: $tags')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(factId, cardPath, timestamp, tags);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CardCacheData &&
          other.factId == this.factId &&
          other.cardPath == this.cardPath &&
          other.timestamp == this.timestamp &&
          other.tags == this.tags);
}

class CardCacheCompanion extends UpdateCompanion<CardCacheData> {
  final Value<String> factId;
  final Value<String> cardPath;
  final Value<int> timestamp;
  final Value<String> tags;
  final Value<int> rowid;
  const CardCacheCompanion({
    this.factId = const Value.absent(),
    this.cardPath = const Value.absent(),
    this.timestamp = const Value.absent(),
    this.tags = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CardCacheCompanion.insert({
    required String factId,
    required String cardPath,
    required int timestamp,
    required String tags,
    this.rowid = const Value.absent(),
  })  : factId = Value(factId),
        cardPath = Value(cardPath),
        timestamp = Value(timestamp),
        tags = Value(tags);
  static Insertable<CardCacheData> custom({
    Expression<String>? factId,
    Expression<String>? cardPath,
    Expression<int>? timestamp,
    Expression<String>? tags,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (factId != null) 'fact_id': factId,
      if (cardPath != null) 'card_path': cardPath,
      if (timestamp != null) 'timestamp': timestamp,
      if (tags != null) 'tags': tags,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CardCacheCompanion copyWith(
      {Value<String>? factId,
      Value<String>? cardPath,
      Value<int>? timestamp,
      Value<String>? tags,
      Value<int>? rowid}) {
    return CardCacheCompanion(
      factId: factId ?? this.factId,
      cardPath: cardPath ?? this.cardPath,
      timestamp: timestamp ?? this.timestamp,
      tags: tags ?? this.tags,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (factId.present) {
      map['fact_id'] = Variable<String>(factId.value);
    }
    if (cardPath.present) {
      map['card_path'] = Variable<String>(cardPath.value);
    }
    if (timestamp.present) {
      map['timestamp'] = Variable<int>(timestamp.value);
    }
    if (tags.present) {
      map['tags'] = Variable<String>(tags.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CardCacheCompanion(')
          ..write('factId: $factId, ')
          ..write('cardPath: $cardPath, ')
          ..write('timestamp: $timestamp, ')
          ..write('tags: $tags, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SystemActionsTable extends SystemActions
    with TableInfo<$SystemActionsTable, SystemAction> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SystemActionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _actionTypeMeta =
      const VerificationMeta('actionType');
  @override
  late final GeneratedColumn<String> actionType = GeneratedColumn<String>(
      'action_type', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _actionDataMeta =
      const VerificationMeta('actionData');
  @override
  late final GeneratedColumn<String> actionData = GeneratedColumn<String>(
      'action_data', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
      'status', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _factIdMeta = const VerificationMeta('factId');
  @override
  late final GeneratedColumn<String> factId = GeneratedColumn<String>(
      'fact_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
      'created_at', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
      'updated_at', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns =>
      [id, actionType, actionData, status, factId, createdAt, updatedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'system_actions';
  @override
  VerificationContext validateIntegrity(Insertable<SystemAction> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('action_type')) {
      context.handle(
          _actionTypeMeta,
          actionType.isAcceptableOrUnknown(
              data['action_type']!, _actionTypeMeta));
    } else if (isInserting) {
      context.missing(_actionTypeMeta);
    }
    if (data.containsKey('action_data')) {
      context.handle(
          _actionDataMeta,
          actionData.isAcceptableOrUnknown(
              data['action_data']!, _actionDataMeta));
    }
    if (data.containsKey('status')) {
      context.handle(_statusMeta,
          status.isAcceptableOrUnknown(data['status']!, _statusMeta));
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
    if (data.containsKey('fact_id')) {
      context.handle(_factIdMeta,
          factId.isAcceptableOrUnknown(data['fact_id']!, _factIdMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SystemAction map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SystemAction(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      actionType: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}action_type'])!,
      actionData: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}action_data']),
      status: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}status'])!,
      factId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}fact_id']),
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}created_at']),
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}updated_at']),
    );
  }

  @override
  $SystemActionsTable createAlias(String alias) {
    return $SystemActionsTable(attachedDatabase, alias);
  }
}

class SystemAction extends DataClass implements Insertable<SystemAction> {
  final String id;
  final String actionType;
  final String? actionData;
  final String status;
  final String? factId;
  final int? createdAt;
  final int? updatedAt;
  const SystemAction(
      {required this.id,
      required this.actionType,
      this.actionData,
      required this.status,
      this.factId,
      this.createdAt,
      this.updatedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['action_type'] = Variable<String>(actionType);
    if (!nullToAbsent || actionData != null) {
      map['action_data'] = Variable<String>(actionData);
    }
    map['status'] = Variable<String>(status);
    if (!nullToAbsent || factId != null) {
      map['fact_id'] = Variable<String>(factId);
    }
    if (!nullToAbsent || createdAt != null) {
      map['created_at'] = Variable<int>(createdAt);
    }
    if (!nullToAbsent || updatedAt != null) {
      map['updated_at'] = Variable<int>(updatedAt);
    }
    return map;
  }

  SystemActionsCompanion toCompanion(bool nullToAbsent) {
    return SystemActionsCompanion(
      id: Value(id),
      actionType: Value(actionType),
      actionData: actionData == null && nullToAbsent
          ? const Value.absent()
          : Value(actionData),
      status: Value(status),
      factId:
          factId == null && nullToAbsent ? const Value.absent() : Value(factId),
      createdAt: createdAt == null && nullToAbsent
          ? const Value.absent()
          : Value(createdAt),
      updatedAt: updatedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(updatedAt),
    );
  }

  factory SystemAction.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SystemAction(
      id: serializer.fromJson<String>(json['id']),
      actionType: serializer.fromJson<String>(json['actionType']),
      actionData: serializer.fromJson<String?>(json['actionData']),
      status: serializer.fromJson<String>(json['status']),
      factId: serializer.fromJson<String?>(json['factId']),
      createdAt: serializer.fromJson<int?>(json['createdAt']),
      updatedAt: serializer.fromJson<int?>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'actionType': serializer.toJson<String>(actionType),
      'actionData': serializer.toJson<String?>(actionData),
      'status': serializer.toJson<String>(status),
      'factId': serializer.toJson<String?>(factId),
      'createdAt': serializer.toJson<int?>(createdAt),
      'updatedAt': serializer.toJson<int?>(updatedAt),
    };
  }

  SystemAction copyWith(
          {String? id,
          String? actionType,
          Value<String?> actionData = const Value.absent(),
          String? status,
          Value<String?> factId = const Value.absent(),
          Value<int?> createdAt = const Value.absent(),
          Value<int?> updatedAt = const Value.absent()}) =>
      SystemAction(
        id: id ?? this.id,
        actionType: actionType ?? this.actionType,
        actionData: actionData.present ? actionData.value : this.actionData,
        status: status ?? this.status,
        factId: factId.present ? factId.value : this.factId,
        createdAt: createdAt.present ? createdAt.value : this.createdAt,
        updatedAt: updatedAt.present ? updatedAt.value : this.updatedAt,
      );
  SystemAction copyWithCompanion(SystemActionsCompanion data) {
    return SystemAction(
      id: data.id.present ? data.id.value : this.id,
      actionType:
          data.actionType.present ? data.actionType.value : this.actionType,
      actionData:
          data.actionData.present ? data.actionData.value : this.actionData,
      status: data.status.present ? data.status.value : this.status,
      factId: data.factId.present ? data.factId.value : this.factId,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SystemAction(')
          ..write('id: $id, ')
          ..write('actionType: $actionType, ')
          ..write('actionData: $actionData, ')
          ..write('status: $status, ')
          ..write('factId: $factId, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id, actionType, actionData, status, factId, createdAt, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SystemAction &&
          other.id == this.id &&
          other.actionType == this.actionType &&
          other.actionData == this.actionData &&
          other.status == this.status &&
          other.factId == this.factId &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class SystemActionsCompanion extends UpdateCompanion<SystemAction> {
  final Value<String> id;
  final Value<String> actionType;
  final Value<String?> actionData;
  final Value<String> status;
  final Value<String?> factId;
  final Value<int?> createdAt;
  final Value<int?> updatedAt;
  final Value<int> rowid;
  const SystemActionsCompanion({
    this.id = const Value.absent(),
    this.actionType = const Value.absent(),
    this.actionData = const Value.absent(),
    this.status = const Value.absent(),
    this.factId = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SystemActionsCompanion.insert({
    required String id,
    required String actionType,
    this.actionData = const Value.absent(),
    required String status,
    this.factId = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        actionType = Value(actionType),
        status = Value(status);
  static Insertable<SystemAction> custom({
    Expression<String>? id,
    Expression<String>? actionType,
    Expression<String>? actionData,
    Expression<String>? status,
    Expression<String>? factId,
    Expression<int>? createdAt,
    Expression<int>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (actionType != null) 'action_type': actionType,
      if (actionData != null) 'action_data': actionData,
      if (status != null) 'status': status,
      if (factId != null) 'fact_id': factId,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SystemActionsCompanion copyWith(
      {Value<String>? id,
      Value<String>? actionType,
      Value<String?>? actionData,
      Value<String>? status,
      Value<String?>? factId,
      Value<int?>? createdAt,
      Value<int?>? updatedAt,
      Value<int>? rowid}) {
    return SystemActionsCompanion(
      id: id ?? this.id,
      actionType: actionType ?? this.actionType,
      actionData: actionData ?? this.actionData,
      status: status ?? this.status,
      factId: factId ?? this.factId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (actionType.present) {
      map['action_type'] = Variable<String>(actionType.value);
    }
    if (actionData.present) {
      map['action_data'] = Variable<String>(actionData.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (factId.present) {
      map['fact_id'] = Variable<String>(factId.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SystemActionsCompanion(')
          ..write('id: $id, ')
          ..write('actionType: $actionType, ')
          ..write('actionData: $actionData, ')
          ..write('status: $status, ')
          ..write('factId: $factId, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ClarificationRequestsTable extends ClarificationRequests
    with TableInfo<$ClarificationRequestsTable, ClarificationRequest> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ClarificationRequestsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _questionMeta =
      const VerificationMeta('question');
  @override
  late final GeneratedColumn<String> question = GeneratedColumn<String>(
      'question', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _responseTypeMeta =
      const VerificationMeta('responseType');
  @override
  late final GeneratedColumn<String> responseType = GeneratedColumn<String>(
      'response_type', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _optionsMeta =
      const VerificationMeta('options');
  @override
  late final GeneratedColumn<String> options = GeneratedColumn<String>(
      'options', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
      'status', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _answerDataMeta =
      const VerificationMeta('answerData');
  @override
  late final GeneratedColumn<String> answerData = GeneratedColumn<String>(
      'answer_data', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _entityTypeMeta =
      const VerificationMeta('entityType');
  @override
  late final GeneratedColumn<String> entityType = GeneratedColumn<String>(
      'entity_type', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _entityLabelMeta =
      const VerificationMeta('entityLabel');
  @override
  late final GeneratedColumn<String> entityLabel = GeneratedColumn<String>(
      'entity_label', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _evidenceFactIdsMeta =
      const VerificationMeta('evidenceFactIds');
  @override
  late final GeneratedColumn<String> evidenceFactIds = GeneratedColumn<String>(
      'evidence_fact_ids', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _reasonMeta = const VerificationMeta('reason');
  @override
  late final GeneratedColumn<String> reason = GeneratedColumn<String>(
      'reason', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _impactMeta = const VerificationMeta('impact');
  @override
  late final GeneratedColumn<String> impact = GeneratedColumn<String>(
      'impact', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _confidenceMeta =
      const VerificationMeta('confidence');
  @override
  late final GeneratedColumn<double> confidence = GeneratedColumn<double>(
      'confidence', aliasedName, true,
      type: DriftSqlType.double, requiredDuringInsert: false);
  static const VerificationMeta _proposedMemoryMeta =
      const VerificationMeta('proposedMemory');
  @override
  late final GeneratedColumn<String> proposedMemory = GeneratedColumn<String>(
      'proposed_memory', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _resolutionTargetMeta =
      const VerificationMeta('resolutionTarget');
  @override
  late final GeneratedColumn<String> resolutionTarget = GeneratedColumn<String>(
      'resolution_target', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _sourceAgentMeta =
      const VerificationMeta('sourceAgent');
  @override
  late final GeneratedColumn<String> sourceAgent = GeneratedColumn<String>(
      'source_agent', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _dedupeKeyMeta =
      const VerificationMeta('dedupeKey');
  @override
  late final GeneratedColumn<String> dedupeKey = GeneratedColumn<String>(
      'dedupe_key', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _factIdMeta = const VerificationMeta('factId');
  @override
  late final GeneratedColumn<String> factId = GeneratedColumn<String>(
      'fact_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _errorMeta = const VerificationMeta('error');
  @override
  late final GeneratedColumn<String> error = GeneratedColumn<String>(
      'error', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
      'created_at', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
      'updated_at', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _answeredAtMeta =
      const VerificationMeta('answeredAt');
  @override
  late final GeneratedColumn<int> answeredAt = GeneratedColumn<int>(
      'answered_at', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _expiresAtMeta =
      const VerificationMeta('expiresAt');
  @override
  late final GeneratedColumn<int> expiresAt = GeneratedColumn<int>(
      'expires_at', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        question,
        responseType,
        options,
        status,
        answerData,
        entityType,
        entityLabel,
        evidenceFactIds,
        reason,
        impact,
        confidence,
        proposedMemory,
        resolutionTarget,
        sourceAgent,
        dedupeKey,
        factId,
        error,
        createdAt,
        updatedAt,
        answeredAt,
        expiresAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'clarification_requests';
  @override
  VerificationContext validateIntegrity(
      Insertable<ClarificationRequest> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('question')) {
      context.handle(_questionMeta,
          question.isAcceptableOrUnknown(data['question']!, _questionMeta));
    } else if (isInserting) {
      context.missing(_questionMeta);
    }
    if (data.containsKey('response_type')) {
      context.handle(
          _responseTypeMeta,
          responseType.isAcceptableOrUnknown(
              data['response_type']!, _responseTypeMeta));
    } else if (isInserting) {
      context.missing(_responseTypeMeta);
    }
    if (data.containsKey('options')) {
      context.handle(_optionsMeta,
          options.isAcceptableOrUnknown(data['options']!, _optionsMeta));
    }
    if (data.containsKey('status')) {
      context.handle(_statusMeta,
          status.isAcceptableOrUnknown(data['status']!, _statusMeta));
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
    if (data.containsKey('answer_data')) {
      context.handle(
          _answerDataMeta,
          answerData.isAcceptableOrUnknown(
              data['answer_data']!, _answerDataMeta));
    }
    if (data.containsKey('entity_type')) {
      context.handle(
          _entityTypeMeta,
          entityType.isAcceptableOrUnknown(
              data['entity_type']!, _entityTypeMeta));
    }
    if (data.containsKey('entity_label')) {
      context.handle(
          _entityLabelMeta,
          entityLabel.isAcceptableOrUnknown(
              data['entity_label']!, _entityLabelMeta));
    }
    if (data.containsKey('evidence_fact_ids')) {
      context.handle(
          _evidenceFactIdsMeta,
          evidenceFactIds.isAcceptableOrUnknown(
              data['evidence_fact_ids']!, _evidenceFactIdsMeta));
    }
    if (data.containsKey('reason')) {
      context.handle(_reasonMeta,
          reason.isAcceptableOrUnknown(data['reason']!, _reasonMeta));
    }
    if (data.containsKey('impact')) {
      context.handle(_impactMeta,
          impact.isAcceptableOrUnknown(data['impact']!, _impactMeta));
    }
    if (data.containsKey('confidence')) {
      context.handle(
          _confidenceMeta,
          confidence.isAcceptableOrUnknown(
              data['confidence']!, _confidenceMeta));
    }
    if (data.containsKey('proposed_memory')) {
      context.handle(
          _proposedMemoryMeta,
          proposedMemory.isAcceptableOrUnknown(
              data['proposed_memory']!, _proposedMemoryMeta));
    }
    if (data.containsKey('resolution_target')) {
      context.handle(
          _resolutionTargetMeta,
          resolutionTarget.isAcceptableOrUnknown(
              data['resolution_target']!, _resolutionTargetMeta));
    }
    if (data.containsKey('source_agent')) {
      context.handle(
          _sourceAgentMeta,
          sourceAgent.isAcceptableOrUnknown(
              data['source_agent']!, _sourceAgentMeta));
    }
    if (data.containsKey('dedupe_key')) {
      context.handle(_dedupeKeyMeta,
          dedupeKey.isAcceptableOrUnknown(data['dedupe_key']!, _dedupeKeyMeta));
    }
    if (data.containsKey('fact_id')) {
      context.handle(_factIdMeta,
          factId.isAcceptableOrUnknown(data['fact_id']!, _factIdMeta));
    }
    if (data.containsKey('error')) {
      context.handle(
          _errorMeta, error.isAcceptableOrUnknown(data['error']!, _errorMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    }
    if (data.containsKey('answered_at')) {
      context.handle(
          _answeredAtMeta,
          answeredAt.isAcceptableOrUnknown(
              data['answered_at']!, _answeredAtMeta));
    }
    if (data.containsKey('expires_at')) {
      context.handle(_expiresAtMeta,
          expiresAt.isAcceptableOrUnknown(data['expires_at']!, _expiresAtMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ClarificationRequest map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ClarificationRequest(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      question: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}question'])!,
      responseType: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}response_type'])!,
      options: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}options']),
      status: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}status'])!,
      answerData: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}answer_data']),
      entityType: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}entity_type']),
      entityLabel: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}entity_label']),
      evidenceFactIds: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}evidence_fact_ids']),
      reason: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}reason']),
      impact: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}impact']),
      confidence: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}confidence']),
      proposedMemory: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}proposed_memory']),
      resolutionTarget: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}resolution_target']),
      sourceAgent: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}source_agent']),
      dedupeKey: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}dedupe_key']),
      factId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}fact_id']),
      error: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}error']),
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}created_at']),
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}updated_at']),
      answeredAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}answered_at']),
      expiresAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}expires_at']),
    );
  }

  @override
  $ClarificationRequestsTable createAlias(String alias) {
    return $ClarificationRequestsTable(attachedDatabase, alias);
  }
}

class ClarificationRequest extends DataClass
    implements Insertable<ClarificationRequest> {
  final String id;
  final String question;
  final String responseType;
  final String? options;
  final String status;
  final String? answerData;
  final String? entityType;
  final String? entityLabel;
  final String? evidenceFactIds;
  final String? reason;
  final String? impact;
  final double? confidence;
  final String? proposedMemory;
  final String? resolutionTarget;
  final String? sourceAgent;
  final String? dedupeKey;
  final String? factId;
  final String? error;
  final int? createdAt;
  final int? updatedAt;
  final int? answeredAt;
  final int? expiresAt;
  const ClarificationRequest(
      {required this.id,
      required this.question,
      required this.responseType,
      this.options,
      required this.status,
      this.answerData,
      this.entityType,
      this.entityLabel,
      this.evidenceFactIds,
      this.reason,
      this.impact,
      this.confidence,
      this.proposedMemory,
      this.resolutionTarget,
      this.sourceAgent,
      this.dedupeKey,
      this.factId,
      this.error,
      this.createdAt,
      this.updatedAt,
      this.answeredAt,
      this.expiresAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['question'] = Variable<String>(question);
    map['response_type'] = Variable<String>(responseType);
    if (!nullToAbsent || options != null) {
      map['options'] = Variable<String>(options);
    }
    map['status'] = Variable<String>(status);
    if (!nullToAbsent || answerData != null) {
      map['answer_data'] = Variable<String>(answerData);
    }
    if (!nullToAbsent || entityType != null) {
      map['entity_type'] = Variable<String>(entityType);
    }
    if (!nullToAbsent || entityLabel != null) {
      map['entity_label'] = Variable<String>(entityLabel);
    }
    if (!nullToAbsent || evidenceFactIds != null) {
      map['evidence_fact_ids'] = Variable<String>(evidenceFactIds);
    }
    if (!nullToAbsent || reason != null) {
      map['reason'] = Variable<String>(reason);
    }
    if (!nullToAbsent || impact != null) {
      map['impact'] = Variable<String>(impact);
    }
    if (!nullToAbsent || confidence != null) {
      map['confidence'] = Variable<double>(confidence);
    }
    if (!nullToAbsent || proposedMemory != null) {
      map['proposed_memory'] = Variable<String>(proposedMemory);
    }
    if (!nullToAbsent || resolutionTarget != null) {
      map['resolution_target'] = Variable<String>(resolutionTarget);
    }
    if (!nullToAbsent || sourceAgent != null) {
      map['source_agent'] = Variable<String>(sourceAgent);
    }
    if (!nullToAbsent || dedupeKey != null) {
      map['dedupe_key'] = Variable<String>(dedupeKey);
    }
    if (!nullToAbsent || factId != null) {
      map['fact_id'] = Variable<String>(factId);
    }
    if (!nullToAbsent || error != null) {
      map['error'] = Variable<String>(error);
    }
    if (!nullToAbsent || createdAt != null) {
      map['created_at'] = Variable<int>(createdAt);
    }
    if (!nullToAbsent || updatedAt != null) {
      map['updated_at'] = Variable<int>(updatedAt);
    }
    if (!nullToAbsent || answeredAt != null) {
      map['answered_at'] = Variable<int>(answeredAt);
    }
    if (!nullToAbsent || expiresAt != null) {
      map['expires_at'] = Variable<int>(expiresAt);
    }
    return map;
  }

  ClarificationRequestsCompanion toCompanion(bool nullToAbsent) {
    return ClarificationRequestsCompanion(
      id: Value(id),
      question: Value(question),
      responseType: Value(responseType),
      options: options == null && nullToAbsent
          ? const Value.absent()
          : Value(options),
      status: Value(status),
      answerData: answerData == null && nullToAbsent
          ? const Value.absent()
          : Value(answerData),
      entityType: entityType == null && nullToAbsent
          ? const Value.absent()
          : Value(entityType),
      entityLabel: entityLabel == null && nullToAbsent
          ? const Value.absent()
          : Value(entityLabel),
      evidenceFactIds: evidenceFactIds == null && nullToAbsent
          ? const Value.absent()
          : Value(evidenceFactIds),
      reason:
          reason == null && nullToAbsent ? const Value.absent() : Value(reason),
      impact:
          impact == null && nullToAbsent ? const Value.absent() : Value(impact),
      confidence: confidence == null && nullToAbsent
          ? const Value.absent()
          : Value(confidence),
      proposedMemory: proposedMemory == null && nullToAbsent
          ? const Value.absent()
          : Value(proposedMemory),
      resolutionTarget: resolutionTarget == null && nullToAbsent
          ? const Value.absent()
          : Value(resolutionTarget),
      sourceAgent: sourceAgent == null && nullToAbsent
          ? const Value.absent()
          : Value(sourceAgent),
      dedupeKey: dedupeKey == null && nullToAbsent
          ? const Value.absent()
          : Value(dedupeKey),
      factId:
          factId == null && nullToAbsent ? const Value.absent() : Value(factId),
      error:
          error == null && nullToAbsent ? const Value.absent() : Value(error),
      createdAt: createdAt == null && nullToAbsent
          ? const Value.absent()
          : Value(createdAt),
      updatedAt: updatedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(updatedAt),
      answeredAt: answeredAt == null && nullToAbsent
          ? const Value.absent()
          : Value(answeredAt),
      expiresAt: expiresAt == null && nullToAbsent
          ? const Value.absent()
          : Value(expiresAt),
    );
  }

  factory ClarificationRequest.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ClarificationRequest(
      id: serializer.fromJson<String>(json['id']),
      question: serializer.fromJson<String>(json['question']),
      responseType: serializer.fromJson<String>(json['responseType']),
      options: serializer.fromJson<String?>(json['options']),
      status: serializer.fromJson<String>(json['status']),
      answerData: serializer.fromJson<String?>(json['answerData']),
      entityType: serializer.fromJson<String?>(json['entityType']),
      entityLabel: serializer.fromJson<String?>(json['entityLabel']),
      evidenceFactIds: serializer.fromJson<String?>(json['evidenceFactIds']),
      reason: serializer.fromJson<String?>(json['reason']),
      impact: serializer.fromJson<String?>(json['impact']),
      confidence: serializer.fromJson<double?>(json['confidence']),
      proposedMemory: serializer.fromJson<String?>(json['proposedMemory']),
      resolutionTarget: serializer.fromJson<String?>(json['resolutionTarget']),
      sourceAgent: serializer.fromJson<String?>(json['sourceAgent']),
      dedupeKey: serializer.fromJson<String?>(json['dedupeKey']),
      factId: serializer.fromJson<String?>(json['factId']),
      error: serializer.fromJson<String?>(json['error']),
      createdAt: serializer.fromJson<int?>(json['createdAt']),
      updatedAt: serializer.fromJson<int?>(json['updatedAt']),
      answeredAt: serializer.fromJson<int?>(json['answeredAt']),
      expiresAt: serializer.fromJson<int?>(json['expiresAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'question': serializer.toJson<String>(question),
      'responseType': serializer.toJson<String>(responseType),
      'options': serializer.toJson<String?>(options),
      'status': serializer.toJson<String>(status),
      'answerData': serializer.toJson<String?>(answerData),
      'entityType': serializer.toJson<String?>(entityType),
      'entityLabel': serializer.toJson<String?>(entityLabel),
      'evidenceFactIds': serializer.toJson<String?>(evidenceFactIds),
      'reason': serializer.toJson<String?>(reason),
      'impact': serializer.toJson<String?>(impact),
      'confidence': serializer.toJson<double?>(confidence),
      'proposedMemory': serializer.toJson<String?>(proposedMemory),
      'resolutionTarget': serializer.toJson<String?>(resolutionTarget),
      'sourceAgent': serializer.toJson<String?>(sourceAgent),
      'dedupeKey': serializer.toJson<String?>(dedupeKey),
      'factId': serializer.toJson<String?>(factId),
      'error': serializer.toJson<String?>(error),
      'createdAt': serializer.toJson<int?>(createdAt),
      'updatedAt': serializer.toJson<int?>(updatedAt),
      'answeredAt': serializer.toJson<int?>(answeredAt),
      'expiresAt': serializer.toJson<int?>(expiresAt),
    };
  }

  ClarificationRequest copyWith(
          {String? id,
          String? question,
          String? responseType,
          Value<String?> options = const Value.absent(),
          String? status,
          Value<String?> answerData = const Value.absent(),
          Value<String?> entityType = const Value.absent(),
          Value<String?> entityLabel = const Value.absent(),
          Value<String?> evidenceFactIds = const Value.absent(),
          Value<String?> reason = const Value.absent(),
          Value<String?> impact = const Value.absent(),
          Value<double?> confidence = const Value.absent(),
          Value<String?> proposedMemory = const Value.absent(),
          Value<String?> resolutionTarget = const Value.absent(),
          Value<String?> sourceAgent = const Value.absent(),
          Value<String?> dedupeKey = const Value.absent(),
          Value<String?> factId = const Value.absent(),
          Value<String?> error = const Value.absent(),
          Value<int?> createdAt = const Value.absent(),
          Value<int?> updatedAt = const Value.absent(),
          Value<int?> answeredAt = const Value.absent(),
          Value<int?> expiresAt = const Value.absent()}) =>
      ClarificationRequest(
        id: id ?? this.id,
        question: question ?? this.question,
        responseType: responseType ?? this.responseType,
        options: options.present ? options.value : this.options,
        status: status ?? this.status,
        answerData: answerData.present ? answerData.value : this.answerData,
        entityType: entityType.present ? entityType.value : this.entityType,
        entityLabel: entityLabel.present ? entityLabel.value : this.entityLabel,
        evidenceFactIds: evidenceFactIds.present
            ? evidenceFactIds.value
            : this.evidenceFactIds,
        reason: reason.present ? reason.value : this.reason,
        impact: impact.present ? impact.value : this.impact,
        confidence: confidence.present ? confidence.value : this.confidence,
        proposedMemory:
            proposedMemory.present ? proposedMemory.value : this.proposedMemory,
        resolutionTarget: resolutionTarget.present
            ? resolutionTarget.value
            : this.resolutionTarget,
        sourceAgent: sourceAgent.present ? sourceAgent.value : this.sourceAgent,
        dedupeKey: dedupeKey.present ? dedupeKey.value : this.dedupeKey,
        factId: factId.present ? factId.value : this.factId,
        error: error.present ? error.value : this.error,
        createdAt: createdAt.present ? createdAt.value : this.createdAt,
        updatedAt: updatedAt.present ? updatedAt.value : this.updatedAt,
        answeredAt: answeredAt.present ? answeredAt.value : this.answeredAt,
        expiresAt: expiresAt.present ? expiresAt.value : this.expiresAt,
      );
  ClarificationRequest copyWithCompanion(ClarificationRequestsCompanion data) {
    return ClarificationRequest(
      id: data.id.present ? data.id.value : this.id,
      question: data.question.present ? data.question.value : this.question,
      responseType: data.responseType.present
          ? data.responseType.value
          : this.responseType,
      options: data.options.present ? data.options.value : this.options,
      status: data.status.present ? data.status.value : this.status,
      answerData:
          data.answerData.present ? data.answerData.value : this.answerData,
      entityType:
          data.entityType.present ? data.entityType.value : this.entityType,
      entityLabel:
          data.entityLabel.present ? data.entityLabel.value : this.entityLabel,
      evidenceFactIds: data.evidenceFactIds.present
          ? data.evidenceFactIds.value
          : this.evidenceFactIds,
      reason: data.reason.present ? data.reason.value : this.reason,
      impact: data.impact.present ? data.impact.value : this.impact,
      confidence:
          data.confidence.present ? data.confidence.value : this.confidence,
      proposedMemory: data.proposedMemory.present
          ? data.proposedMemory.value
          : this.proposedMemory,
      resolutionTarget: data.resolutionTarget.present
          ? data.resolutionTarget.value
          : this.resolutionTarget,
      sourceAgent:
          data.sourceAgent.present ? data.sourceAgent.value : this.sourceAgent,
      dedupeKey: data.dedupeKey.present ? data.dedupeKey.value : this.dedupeKey,
      factId: data.factId.present ? data.factId.value : this.factId,
      error: data.error.present ? data.error.value : this.error,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      answeredAt:
          data.answeredAt.present ? data.answeredAt.value : this.answeredAt,
      expiresAt: data.expiresAt.present ? data.expiresAt.value : this.expiresAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ClarificationRequest(')
          ..write('id: $id, ')
          ..write('question: $question, ')
          ..write('responseType: $responseType, ')
          ..write('options: $options, ')
          ..write('status: $status, ')
          ..write('answerData: $answerData, ')
          ..write('entityType: $entityType, ')
          ..write('entityLabel: $entityLabel, ')
          ..write('evidenceFactIds: $evidenceFactIds, ')
          ..write('reason: $reason, ')
          ..write('impact: $impact, ')
          ..write('confidence: $confidence, ')
          ..write('proposedMemory: $proposedMemory, ')
          ..write('resolutionTarget: $resolutionTarget, ')
          ..write('sourceAgent: $sourceAgent, ')
          ..write('dedupeKey: $dedupeKey, ')
          ..write('factId: $factId, ')
          ..write('error: $error, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('answeredAt: $answeredAt, ')
          ..write('expiresAt: $expiresAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
        id,
        question,
        responseType,
        options,
        status,
        answerData,
        entityType,
        entityLabel,
        evidenceFactIds,
        reason,
        impact,
        confidence,
        proposedMemory,
        resolutionTarget,
        sourceAgent,
        dedupeKey,
        factId,
        error,
        createdAt,
        updatedAt,
        answeredAt,
        expiresAt
      ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ClarificationRequest &&
          other.id == this.id &&
          other.question == this.question &&
          other.responseType == this.responseType &&
          other.options == this.options &&
          other.status == this.status &&
          other.answerData == this.answerData &&
          other.entityType == this.entityType &&
          other.entityLabel == this.entityLabel &&
          other.evidenceFactIds == this.evidenceFactIds &&
          other.reason == this.reason &&
          other.impact == this.impact &&
          other.confidence == this.confidence &&
          other.proposedMemory == this.proposedMemory &&
          other.resolutionTarget == this.resolutionTarget &&
          other.sourceAgent == this.sourceAgent &&
          other.dedupeKey == this.dedupeKey &&
          other.factId == this.factId &&
          other.error == this.error &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.answeredAt == this.answeredAt &&
          other.expiresAt == this.expiresAt);
}

class ClarificationRequestsCompanion
    extends UpdateCompanion<ClarificationRequest> {
  final Value<String> id;
  final Value<String> question;
  final Value<String> responseType;
  final Value<String?> options;
  final Value<String> status;
  final Value<String?> answerData;
  final Value<String?> entityType;
  final Value<String?> entityLabel;
  final Value<String?> evidenceFactIds;
  final Value<String?> reason;
  final Value<String?> impact;
  final Value<double?> confidence;
  final Value<String?> proposedMemory;
  final Value<String?> resolutionTarget;
  final Value<String?> sourceAgent;
  final Value<String?> dedupeKey;
  final Value<String?> factId;
  final Value<String?> error;
  final Value<int?> createdAt;
  final Value<int?> updatedAt;
  final Value<int?> answeredAt;
  final Value<int?> expiresAt;
  final Value<int> rowid;
  const ClarificationRequestsCompanion({
    this.id = const Value.absent(),
    this.question = const Value.absent(),
    this.responseType = const Value.absent(),
    this.options = const Value.absent(),
    this.status = const Value.absent(),
    this.answerData = const Value.absent(),
    this.entityType = const Value.absent(),
    this.entityLabel = const Value.absent(),
    this.evidenceFactIds = const Value.absent(),
    this.reason = const Value.absent(),
    this.impact = const Value.absent(),
    this.confidence = const Value.absent(),
    this.proposedMemory = const Value.absent(),
    this.resolutionTarget = const Value.absent(),
    this.sourceAgent = const Value.absent(),
    this.dedupeKey = const Value.absent(),
    this.factId = const Value.absent(),
    this.error = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.answeredAt = const Value.absent(),
    this.expiresAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ClarificationRequestsCompanion.insert({
    required String id,
    required String question,
    required String responseType,
    this.options = const Value.absent(),
    required String status,
    this.answerData = const Value.absent(),
    this.entityType = const Value.absent(),
    this.entityLabel = const Value.absent(),
    this.evidenceFactIds = const Value.absent(),
    this.reason = const Value.absent(),
    this.impact = const Value.absent(),
    this.confidence = const Value.absent(),
    this.proposedMemory = const Value.absent(),
    this.resolutionTarget = const Value.absent(),
    this.sourceAgent = const Value.absent(),
    this.dedupeKey = const Value.absent(),
    this.factId = const Value.absent(),
    this.error = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.answeredAt = const Value.absent(),
    this.expiresAt = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        question = Value(question),
        responseType = Value(responseType),
        status = Value(status);
  static Insertable<ClarificationRequest> custom({
    Expression<String>? id,
    Expression<String>? question,
    Expression<String>? responseType,
    Expression<String>? options,
    Expression<String>? status,
    Expression<String>? answerData,
    Expression<String>? entityType,
    Expression<String>? entityLabel,
    Expression<String>? evidenceFactIds,
    Expression<String>? reason,
    Expression<String>? impact,
    Expression<double>? confidence,
    Expression<String>? proposedMemory,
    Expression<String>? resolutionTarget,
    Expression<String>? sourceAgent,
    Expression<String>? dedupeKey,
    Expression<String>? factId,
    Expression<String>? error,
    Expression<int>? createdAt,
    Expression<int>? updatedAt,
    Expression<int>? answeredAt,
    Expression<int>? expiresAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (question != null) 'question': question,
      if (responseType != null) 'response_type': responseType,
      if (options != null) 'options': options,
      if (status != null) 'status': status,
      if (answerData != null) 'answer_data': answerData,
      if (entityType != null) 'entity_type': entityType,
      if (entityLabel != null) 'entity_label': entityLabel,
      if (evidenceFactIds != null) 'evidence_fact_ids': evidenceFactIds,
      if (reason != null) 'reason': reason,
      if (impact != null) 'impact': impact,
      if (confidence != null) 'confidence': confidence,
      if (proposedMemory != null) 'proposed_memory': proposedMemory,
      if (resolutionTarget != null) 'resolution_target': resolutionTarget,
      if (sourceAgent != null) 'source_agent': sourceAgent,
      if (dedupeKey != null) 'dedupe_key': dedupeKey,
      if (factId != null) 'fact_id': factId,
      if (error != null) 'error': error,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (answeredAt != null) 'answered_at': answeredAt,
      if (expiresAt != null) 'expires_at': expiresAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ClarificationRequestsCompanion copyWith(
      {Value<String>? id,
      Value<String>? question,
      Value<String>? responseType,
      Value<String?>? options,
      Value<String>? status,
      Value<String?>? answerData,
      Value<String?>? entityType,
      Value<String?>? entityLabel,
      Value<String?>? evidenceFactIds,
      Value<String?>? reason,
      Value<String?>? impact,
      Value<double?>? confidence,
      Value<String?>? proposedMemory,
      Value<String?>? resolutionTarget,
      Value<String?>? sourceAgent,
      Value<String?>? dedupeKey,
      Value<String?>? factId,
      Value<String?>? error,
      Value<int?>? createdAt,
      Value<int?>? updatedAt,
      Value<int?>? answeredAt,
      Value<int?>? expiresAt,
      Value<int>? rowid}) {
    return ClarificationRequestsCompanion(
      id: id ?? this.id,
      question: question ?? this.question,
      responseType: responseType ?? this.responseType,
      options: options ?? this.options,
      status: status ?? this.status,
      answerData: answerData ?? this.answerData,
      entityType: entityType ?? this.entityType,
      entityLabel: entityLabel ?? this.entityLabel,
      evidenceFactIds: evidenceFactIds ?? this.evidenceFactIds,
      reason: reason ?? this.reason,
      impact: impact ?? this.impact,
      confidence: confidence ?? this.confidence,
      proposedMemory: proposedMemory ?? this.proposedMemory,
      resolutionTarget: resolutionTarget ?? this.resolutionTarget,
      sourceAgent: sourceAgent ?? this.sourceAgent,
      dedupeKey: dedupeKey ?? this.dedupeKey,
      factId: factId ?? this.factId,
      error: error ?? this.error,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      answeredAt: answeredAt ?? this.answeredAt,
      expiresAt: expiresAt ?? this.expiresAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (question.present) {
      map['question'] = Variable<String>(question.value);
    }
    if (responseType.present) {
      map['response_type'] = Variable<String>(responseType.value);
    }
    if (options.present) {
      map['options'] = Variable<String>(options.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (answerData.present) {
      map['answer_data'] = Variable<String>(answerData.value);
    }
    if (entityType.present) {
      map['entity_type'] = Variable<String>(entityType.value);
    }
    if (entityLabel.present) {
      map['entity_label'] = Variable<String>(entityLabel.value);
    }
    if (evidenceFactIds.present) {
      map['evidence_fact_ids'] = Variable<String>(evidenceFactIds.value);
    }
    if (reason.present) {
      map['reason'] = Variable<String>(reason.value);
    }
    if (impact.present) {
      map['impact'] = Variable<String>(impact.value);
    }
    if (confidence.present) {
      map['confidence'] = Variable<double>(confidence.value);
    }
    if (proposedMemory.present) {
      map['proposed_memory'] = Variable<String>(proposedMemory.value);
    }
    if (resolutionTarget.present) {
      map['resolution_target'] = Variable<String>(resolutionTarget.value);
    }
    if (sourceAgent.present) {
      map['source_agent'] = Variable<String>(sourceAgent.value);
    }
    if (dedupeKey.present) {
      map['dedupe_key'] = Variable<String>(dedupeKey.value);
    }
    if (factId.present) {
      map['fact_id'] = Variable<String>(factId.value);
    }
    if (error.present) {
      map['error'] = Variable<String>(error.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (answeredAt.present) {
      map['answered_at'] = Variable<int>(answeredAt.value);
    }
    if (expiresAt.present) {
      map['expires_at'] = Variable<int>(expiresAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ClarificationRequestsCompanion(')
          ..write('id: $id, ')
          ..write('question: $question, ')
          ..write('responseType: $responseType, ')
          ..write('options: $options, ')
          ..write('status: $status, ')
          ..write('answerData: $answerData, ')
          ..write('entityType: $entityType, ')
          ..write('entityLabel: $entityLabel, ')
          ..write('evidenceFactIds: $evidenceFactIds, ')
          ..write('reason: $reason, ')
          ..write('impact: $impact, ')
          ..write('confidence: $confidence, ')
          ..write('proposedMemory: $proposedMemory, ')
          ..write('resolutionTarget: $resolutionTarget, ')
          ..write('sourceAgent: $sourceAgent, ')
          ..write('dedupeKey: $dedupeKey, ')
          ..write('factId: $factId, ')
          ..write('error: $error, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('answeredAt: $answeredAt, ')
          ..write('expiresAt: $expiresAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PersonaChatMessagesTable extends PersonaChatMessages
    with TableInfo<$PersonaChatMessagesTable, PersonaChatMessage> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PersonaChatMessagesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _characterIdMeta =
      const VerificationMeta('characterId');
  @override
  late final GeneratedColumn<String> characterId = GeneratedColumn<String>(
      'character_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _isFromCharacterMeta =
      const VerificationMeta('isFromCharacter');
  @override
  late final GeneratedColumn<bool> isFromCharacter = GeneratedColumn<bool>(
      'is_from_character', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: true,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("is_from_character" IN (0, 1))'));
  static const VerificationMeta _contentMeta =
      const VerificationMeta('content');
  @override
  late final GeneratedColumn<String> content = GeneratedColumn<String>(
      'content', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _factIdMeta = const VerificationMeta('factId');
  @override
  late final GeneratedColumn<String> factId = GeneratedColumn<String>(
      'fact_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _isReadMeta = const VerificationMeta('isRead');
  @override
  late final GeneratedColumn<bool> isRead = GeneratedColumn<bool>(
      'is_read', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("is_read" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _timestampMeta =
      const VerificationMeta('timestamp');
  @override
  late final GeneratedColumn<DateTime> timestamp = GeneratedColumn<DateTime>(
      'timestamp', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _messageTypeMeta =
      const VerificationMeta('messageType');
  @override
  late final GeneratedColumn<String> messageType = GeneratedColumn<String>(
      'message_type', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('chat'));
  static const VerificationMeta _attachmentsJsonMeta =
      const VerificationMeta('attachmentsJson');
  @override
  late final GeneratedColumn<String> attachmentsJson = GeneratedColumn<String>(
      'attachments_json', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        characterId,
        isFromCharacter,
        content,
        factId,
        isRead,
        timestamp,
        messageType,
        attachmentsJson
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'persona_chat_messages';
  @override
  VerificationContext validateIntegrity(Insertable<PersonaChatMessage> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('character_id')) {
      context.handle(
          _characterIdMeta,
          characterId.isAcceptableOrUnknown(
              data['character_id']!, _characterIdMeta));
    } else if (isInserting) {
      context.missing(_characterIdMeta);
    }
    if (data.containsKey('is_from_character')) {
      context.handle(
          _isFromCharacterMeta,
          isFromCharacter.isAcceptableOrUnknown(
              data['is_from_character']!, _isFromCharacterMeta));
    } else if (isInserting) {
      context.missing(_isFromCharacterMeta);
    }
    if (data.containsKey('content')) {
      context.handle(_contentMeta,
          content.isAcceptableOrUnknown(data['content']!, _contentMeta));
    } else if (isInserting) {
      context.missing(_contentMeta);
    }
    if (data.containsKey('fact_id')) {
      context.handle(_factIdMeta,
          factId.isAcceptableOrUnknown(data['fact_id']!, _factIdMeta));
    }
    if (data.containsKey('is_read')) {
      context.handle(_isReadMeta,
          isRead.isAcceptableOrUnknown(data['is_read']!, _isReadMeta));
    }
    if (data.containsKey('timestamp')) {
      context.handle(_timestampMeta,
          timestamp.isAcceptableOrUnknown(data['timestamp']!, _timestampMeta));
    } else if (isInserting) {
      context.missing(_timestampMeta);
    }
    if (data.containsKey('message_type')) {
      context.handle(
          _messageTypeMeta,
          messageType.isAcceptableOrUnknown(
              data['message_type']!, _messageTypeMeta));
    }
    if (data.containsKey('attachments_json')) {
      context.handle(
          _attachmentsJsonMeta,
          attachmentsJson.isAcceptableOrUnknown(
              data['attachments_json']!, _attachmentsJsonMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  PersonaChatMessage map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PersonaChatMessage(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      characterId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}character_id'])!,
      isFromCharacter: attachedDatabase.typeMapping.read(
          DriftSqlType.bool, data['${effectivePrefix}is_from_character'])!,
      content: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}content'])!,
      factId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}fact_id']),
      isRead: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_read'])!,
      timestamp: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}timestamp'])!,
      messageType: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}message_type'])!,
      attachmentsJson: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}attachments_json']),
    );
  }

  @override
  $PersonaChatMessagesTable createAlias(String alias) {
    return $PersonaChatMessagesTable(attachedDatabase, alias);
  }
}

class PersonaChatMessage extends DataClass
    implements Insertable<PersonaChatMessage> {
  final int id;
  final String characterId;
  final bool isFromCharacter;
  final String content;
  final String? factId;
  final bool isRead;
  final DateTime timestamp;

  /// Message type: 'chat' (default) or 'action' (narrative/action description).
  final String messageType;

  /// JSON-encoded list of attachment objects, e.g.
  /// [{"mimeType": "image/webp", "base64": "..."}]
  /// Null for text-only messages.
  final String? attachmentsJson;
  const PersonaChatMessage(
      {required this.id,
      required this.characterId,
      required this.isFromCharacter,
      required this.content,
      this.factId,
      required this.isRead,
      required this.timestamp,
      required this.messageType,
      this.attachmentsJson});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['character_id'] = Variable<String>(characterId);
    map['is_from_character'] = Variable<bool>(isFromCharacter);
    map['content'] = Variable<String>(content);
    if (!nullToAbsent || factId != null) {
      map['fact_id'] = Variable<String>(factId);
    }
    map['is_read'] = Variable<bool>(isRead);
    map['timestamp'] = Variable<DateTime>(timestamp);
    map['message_type'] = Variable<String>(messageType);
    if (!nullToAbsent || attachmentsJson != null) {
      map['attachments_json'] = Variable<String>(attachmentsJson);
    }
    return map;
  }

  PersonaChatMessagesCompanion toCompanion(bool nullToAbsent) {
    return PersonaChatMessagesCompanion(
      id: Value(id),
      characterId: Value(characterId),
      isFromCharacter: Value(isFromCharacter),
      content: Value(content),
      factId:
          factId == null && nullToAbsent ? const Value.absent() : Value(factId),
      isRead: Value(isRead),
      timestamp: Value(timestamp),
      messageType: Value(messageType),
      attachmentsJson: attachmentsJson == null && nullToAbsent
          ? const Value.absent()
          : Value(attachmentsJson),
    );
  }

  factory PersonaChatMessage.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PersonaChatMessage(
      id: serializer.fromJson<int>(json['id']),
      characterId: serializer.fromJson<String>(json['characterId']),
      isFromCharacter: serializer.fromJson<bool>(json['isFromCharacter']),
      content: serializer.fromJson<String>(json['content']),
      factId: serializer.fromJson<String?>(json['factId']),
      isRead: serializer.fromJson<bool>(json['isRead']),
      timestamp: serializer.fromJson<DateTime>(json['timestamp']),
      messageType: serializer.fromJson<String>(json['messageType']),
      attachmentsJson: serializer.fromJson<String?>(json['attachmentsJson']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'characterId': serializer.toJson<String>(characterId),
      'isFromCharacter': serializer.toJson<bool>(isFromCharacter),
      'content': serializer.toJson<String>(content),
      'factId': serializer.toJson<String?>(factId),
      'isRead': serializer.toJson<bool>(isRead),
      'timestamp': serializer.toJson<DateTime>(timestamp),
      'messageType': serializer.toJson<String>(messageType),
      'attachmentsJson': serializer.toJson<String?>(attachmentsJson),
    };
  }

  PersonaChatMessage copyWith(
          {int? id,
          String? characterId,
          bool? isFromCharacter,
          String? content,
          Value<String?> factId = const Value.absent(),
          bool? isRead,
          DateTime? timestamp,
          String? messageType,
          Value<String?> attachmentsJson = const Value.absent()}) =>
      PersonaChatMessage(
        id: id ?? this.id,
        characterId: characterId ?? this.characterId,
        isFromCharacter: isFromCharacter ?? this.isFromCharacter,
        content: content ?? this.content,
        factId: factId.present ? factId.value : this.factId,
        isRead: isRead ?? this.isRead,
        timestamp: timestamp ?? this.timestamp,
        messageType: messageType ?? this.messageType,
        attachmentsJson: attachmentsJson.present
            ? attachmentsJson.value
            : this.attachmentsJson,
      );
  PersonaChatMessage copyWithCompanion(PersonaChatMessagesCompanion data) {
    return PersonaChatMessage(
      id: data.id.present ? data.id.value : this.id,
      characterId:
          data.characterId.present ? data.characterId.value : this.characterId,
      isFromCharacter: data.isFromCharacter.present
          ? data.isFromCharacter.value
          : this.isFromCharacter,
      content: data.content.present ? data.content.value : this.content,
      factId: data.factId.present ? data.factId.value : this.factId,
      isRead: data.isRead.present ? data.isRead.value : this.isRead,
      timestamp: data.timestamp.present ? data.timestamp.value : this.timestamp,
      messageType:
          data.messageType.present ? data.messageType.value : this.messageType,
      attachmentsJson: data.attachmentsJson.present
          ? data.attachmentsJson.value
          : this.attachmentsJson,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PersonaChatMessage(')
          ..write('id: $id, ')
          ..write('characterId: $characterId, ')
          ..write('isFromCharacter: $isFromCharacter, ')
          ..write('content: $content, ')
          ..write('factId: $factId, ')
          ..write('isRead: $isRead, ')
          ..write('timestamp: $timestamp, ')
          ..write('messageType: $messageType, ')
          ..write('attachmentsJson: $attachmentsJson')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, characterId, isFromCharacter, content,
      factId, isRead, timestamp, messageType, attachmentsJson);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PersonaChatMessage &&
          other.id == this.id &&
          other.characterId == this.characterId &&
          other.isFromCharacter == this.isFromCharacter &&
          other.content == this.content &&
          other.factId == this.factId &&
          other.isRead == this.isRead &&
          other.timestamp == this.timestamp &&
          other.messageType == this.messageType &&
          other.attachmentsJson == this.attachmentsJson);
}

class PersonaChatMessagesCompanion extends UpdateCompanion<PersonaChatMessage> {
  final Value<int> id;
  final Value<String> characterId;
  final Value<bool> isFromCharacter;
  final Value<String> content;
  final Value<String?> factId;
  final Value<bool> isRead;
  final Value<DateTime> timestamp;
  final Value<String> messageType;
  final Value<String?> attachmentsJson;
  const PersonaChatMessagesCompanion({
    this.id = const Value.absent(),
    this.characterId = const Value.absent(),
    this.isFromCharacter = const Value.absent(),
    this.content = const Value.absent(),
    this.factId = const Value.absent(),
    this.isRead = const Value.absent(),
    this.timestamp = const Value.absent(),
    this.messageType = const Value.absent(),
    this.attachmentsJson = const Value.absent(),
  });
  PersonaChatMessagesCompanion.insert({
    this.id = const Value.absent(),
    required String characterId,
    required bool isFromCharacter,
    required String content,
    this.factId = const Value.absent(),
    this.isRead = const Value.absent(),
    required DateTime timestamp,
    this.messageType = const Value.absent(),
    this.attachmentsJson = const Value.absent(),
  })  : characterId = Value(characterId),
        isFromCharacter = Value(isFromCharacter),
        content = Value(content),
        timestamp = Value(timestamp);
  static Insertable<PersonaChatMessage> custom({
    Expression<int>? id,
    Expression<String>? characterId,
    Expression<bool>? isFromCharacter,
    Expression<String>? content,
    Expression<String>? factId,
    Expression<bool>? isRead,
    Expression<DateTime>? timestamp,
    Expression<String>? messageType,
    Expression<String>? attachmentsJson,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (characterId != null) 'character_id': characterId,
      if (isFromCharacter != null) 'is_from_character': isFromCharacter,
      if (content != null) 'content': content,
      if (factId != null) 'fact_id': factId,
      if (isRead != null) 'is_read': isRead,
      if (timestamp != null) 'timestamp': timestamp,
      if (messageType != null) 'message_type': messageType,
      if (attachmentsJson != null) 'attachments_json': attachmentsJson,
    });
  }

  PersonaChatMessagesCompanion copyWith(
      {Value<int>? id,
      Value<String>? characterId,
      Value<bool>? isFromCharacter,
      Value<String>? content,
      Value<String?>? factId,
      Value<bool>? isRead,
      Value<DateTime>? timestamp,
      Value<String>? messageType,
      Value<String?>? attachmentsJson}) {
    return PersonaChatMessagesCompanion(
      id: id ?? this.id,
      characterId: characterId ?? this.characterId,
      isFromCharacter: isFromCharacter ?? this.isFromCharacter,
      content: content ?? this.content,
      factId: factId ?? this.factId,
      isRead: isRead ?? this.isRead,
      timestamp: timestamp ?? this.timestamp,
      messageType: messageType ?? this.messageType,
      attachmentsJson: attachmentsJson ?? this.attachmentsJson,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (characterId.present) {
      map['character_id'] = Variable<String>(characterId.value);
    }
    if (isFromCharacter.present) {
      map['is_from_character'] = Variable<bool>(isFromCharacter.value);
    }
    if (content.present) {
      map['content'] = Variable<String>(content.value);
    }
    if (factId.present) {
      map['fact_id'] = Variable<String>(factId.value);
    }
    if (isRead.present) {
      map['is_read'] = Variable<bool>(isRead.value);
    }
    if (timestamp.present) {
      map['timestamp'] = Variable<DateTime>(timestamp.value);
    }
    if (messageType.present) {
      map['message_type'] = Variable<String>(messageType.value);
    }
    if (attachmentsJson.present) {
      map['attachments_json'] = Variable<String>(attachmentsJson.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PersonaChatMessagesCompanion(')
          ..write('id: $id, ')
          ..write('characterId: $characterId, ')
          ..write('isFromCharacter: $isFromCharacter, ')
          ..write('content: $content, ')
          ..write('factId: $factId, ')
          ..write('isRead: $isRead, ')
          ..write('timestamp: $timestamp, ')
          ..write('messageType: $messageType, ')
          ..write('attachmentsJson: $attachmentsJson')
          ..write(')'))
        .toString();
  }
}

class $ConversationCaptureCursorsTable extends ConversationCaptureCursors
    with
        TableInfo<$ConversationCaptureCursorsTable, ConversationCaptureCursor> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ConversationCaptureCursorsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _characterIdMeta =
      const VerificationMeta('characterId');
  @override
  late final GeneratedColumn<String> characterId = GeneratedColumn<String>(
      'character_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _lastExtractedMessageIdMeta =
      const VerificationMeta('lastExtractedMessageId');
  @override
  late final GeneratedColumn<int> lastExtractedMessageId = GeneratedColumn<int>(
      'last_extracted_message_id', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _lastQueuedMessageIdMeta =
      const VerificationMeta('lastQueuedMessageId');
  @override
  late final GeneratedColumn<int> lastQueuedMessageId = GeneratedColumn<int>(
      'last_queued_message_id', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns =>
      [characterId, lastExtractedMessageId, lastQueuedMessageId, updatedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'conversation_capture_cursors';
  @override
  VerificationContext validateIntegrity(
      Insertable<ConversationCaptureCursor> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('character_id')) {
      context.handle(
          _characterIdMeta,
          characterId.isAcceptableOrUnknown(
              data['character_id']!, _characterIdMeta));
    } else if (isInserting) {
      context.missing(_characterIdMeta);
    }
    if (data.containsKey('last_extracted_message_id')) {
      context.handle(
          _lastExtractedMessageIdMeta,
          lastExtractedMessageId.isAcceptableOrUnknown(
              data['last_extracted_message_id']!, _lastExtractedMessageIdMeta));
    }
    if (data.containsKey('last_queued_message_id')) {
      context.handle(
          _lastQueuedMessageIdMeta,
          lastQueuedMessageId.isAcceptableOrUnknown(
              data['last_queued_message_id']!, _lastQueuedMessageIdMeta));
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {characterId};
  @override
  ConversationCaptureCursor map(Map<String, dynamic> data,
      {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ConversationCaptureCursor(
      characterId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}character_id'])!,
      lastExtractedMessageId: attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}last_extracted_message_id'])!,
      lastQueuedMessageId: attachedDatabase.typeMapping.read(
          DriftSqlType.int, data['${effectivePrefix}last_queued_message_id'])!,
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}updated_at'])!,
    );
  }

  @override
  $ConversationCaptureCursorsTable createAlias(String alias) {
    return $ConversationCaptureCursorsTable(attachedDatabase, alias);
  }
}

class ConversationCaptureCursor extends DataClass
    implements Insertable<ConversationCaptureCursor> {
  final String characterId;
  final int lastExtractedMessageId;
  final int lastQueuedMessageId;
  final int updatedAt;
  const ConversationCaptureCursor(
      {required this.characterId,
      required this.lastExtractedMessageId,
      required this.lastQueuedMessageId,
      required this.updatedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['character_id'] = Variable<String>(characterId);
    map['last_extracted_message_id'] = Variable<int>(lastExtractedMessageId);
    map['last_queued_message_id'] = Variable<int>(lastQueuedMessageId);
    map['updated_at'] = Variable<int>(updatedAt);
    return map;
  }

  ConversationCaptureCursorsCompanion toCompanion(bool nullToAbsent) {
    return ConversationCaptureCursorsCompanion(
      characterId: Value(characterId),
      lastExtractedMessageId: Value(lastExtractedMessageId),
      lastQueuedMessageId: Value(lastQueuedMessageId),
      updatedAt: Value(updatedAt),
    );
  }

  factory ConversationCaptureCursor.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ConversationCaptureCursor(
      characterId: serializer.fromJson<String>(json['characterId']),
      lastExtractedMessageId:
          serializer.fromJson<int>(json['lastExtractedMessageId']),
      lastQueuedMessageId:
          serializer.fromJson<int>(json['lastQueuedMessageId']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'characterId': serializer.toJson<String>(characterId),
      'lastExtractedMessageId': serializer.toJson<int>(lastExtractedMessageId),
      'lastQueuedMessageId': serializer.toJson<int>(lastQueuedMessageId),
      'updatedAt': serializer.toJson<int>(updatedAt),
    };
  }

  ConversationCaptureCursor copyWith(
          {String? characterId,
          int? lastExtractedMessageId,
          int? lastQueuedMessageId,
          int? updatedAt}) =>
      ConversationCaptureCursor(
        characterId: characterId ?? this.characterId,
        lastExtractedMessageId:
            lastExtractedMessageId ?? this.lastExtractedMessageId,
        lastQueuedMessageId: lastQueuedMessageId ?? this.lastQueuedMessageId,
        updatedAt: updatedAt ?? this.updatedAt,
      );
  ConversationCaptureCursor copyWithCompanion(
      ConversationCaptureCursorsCompanion data) {
    return ConversationCaptureCursor(
      characterId:
          data.characterId.present ? data.characterId.value : this.characterId,
      lastExtractedMessageId: data.lastExtractedMessageId.present
          ? data.lastExtractedMessageId.value
          : this.lastExtractedMessageId,
      lastQueuedMessageId: data.lastQueuedMessageId.present
          ? data.lastQueuedMessageId.value
          : this.lastQueuedMessageId,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ConversationCaptureCursor(')
          ..write('characterId: $characterId, ')
          ..write('lastExtractedMessageId: $lastExtractedMessageId, ')
          ..write('lastQueuedMessageId: $lastQueuedMessageId, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      characterId, lastExtractedMessageId, lastQueuedMessageId, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ConversationCaptureCursor &&
          other.characterId == this.characterId &&
          other.lastExtractedMessageId == this.lastExtractedMessageId &&
          other.lastQueuedMessageId == this.lastQueuedMessageId &&
          other.updatedAt == this.updatedAt);
}

class ConversationCaptureCursorsCompanion
    extends UpdateCompanion<ConversationCaptureCursor> {
  final Value<String> characterId;
  final Value<int> lastExtractedMessageId;
  final Value<int> lastQueuedMessageId;
  final Value<int> updatedAt;
  final Value<int> rowid;
  const ConversationCaptureCursorsCompanion({
    this.characterId = const Value.absent(),
    this.lastExtractedMessageId = const Value.absent(),
    this.lastQueuedMessageId = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ConversationCaptureCursorsCompanion.insert({
    required String characterId,
    this.lastExtractedMessageId = const Value.absent(),
    this.lastQueuedMessageId = const Value.absent(),
    required int updatedAt,
    this.rowid = const Value.absent(),
  })  : characterId = Value(characterId),
        updatedAt = Value(updatedAt);
  static Insertable<ConversationCaptureCursor> custom({
    Expression<String>? characterId,
    Expression<int>? lastExtractedMessageId,
    Expression<int>? lastQueuedMessageId,
    Expression<int>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (characterId != null) 'character_id': characterId,
      if (lastExtractedMessageId != null)
        'last_extracted_message_id': lastExtractedMessageId,
      if (lastQueuedMessageId != null)
        'last_queued_message_id': lastQueuedMessageId,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ConversationCaptureCursorsCompanion copyWith(
      {Value<String>? characterId,
      Value<int>? lastExtractedMessageId,
      Value<int>? lastQueuedMessageId,
      Value<int>? updatedAt,
      Value<int>? rowid}) {
    return ConversationCaptureCursorsCompanion(
      characterId: characterId ?? this.characterId,
      lastExtractedMessageId:
          lastExtractedMessageId ?? this.lastExtractedMessageId,
      lastQueuedMessageId: lastQueuedMessageId ?? this.lastQueuedMessageId,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (characterId.present) {
      map['character_id'] = Variable<String>(characterId.value);
    }
    if (lastExtractedMessageId.present) {
      map['last_extracted_message_id'] =
          Variable<int>(lastExtractedMessageId.value);
    }
    if (lastQueuedMessageId.present) {
      map['last_queued_message_id'] = Variable<int>(lastQueuedMessageId.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ConversationCaptureCursorsCompanion(')
          ..write('characterId: $characterId, ')
          ..write('lastExtractedMessageId: $lastExtractedMessageId, ')
          ..write('lastQueuedMessageId: $lastQueuedMessageId, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SharedLifeEventOperationsTable extends SharedLifeEventOperations
    with TableInfo<$SharedLifeEventOperationsTable, SharedLifeEventOperation> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SharedLifeEventOperationsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _entityIdMeta =
      const VerificationMeta('entityId');
  @override
  late final GeneratedColumn<String> entityId = GeneratedColumn<String>(
      'entity_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _operationTypeMeta =
      const VerificationMeta('operationType');
  @override
  late final GeneratedColumn<String> operationType = GeneratedColumn<String>(
      'operation_type', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _entityTypeMeta =
      const VerificationMeta('entityType');
  @override
  late final GeneratedColumn<String> entityType = GeneratedColumn<String>(
      'entity_type', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
      'title', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _patchJsonMeta =
      const VerificationMeta('patchJson');
  @override
  late final GeneratedColumn<String> patchJson = GeneratedColumn<String>(
      'patch_json', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _sourceMessageIdsMeta =
      const VerificationMeta('sourceMessageIds');
  @override
  late final GeneratedColumn<String> sourceMessageIds = GeneratedColumn<String>(
      'source_message_ids', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _sourceCharacterIdMeta =
      const VerificationMeta('sourceCharacterId');
  @override
  late final GeneratedColumn<String> sourceCharacterId =
      GeneratedColumn<String>('source_character_id', aliasedName, false,
          type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _captureTaskIdMeta =
      const VerificationMeta('captureTaskId');
  @override
  late final GeneratedColumn<String> captureTaskId = GeneratedColumn<String>(
      'capture_task_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _revertsOperationIdMeta =
      const VerificationMeta('revertsOperationId');
  @override
  late final GeneratedColumn<String> revertsOperationId =
      GeneratedColumn<String>('reverts_operation_id', aliasedName, true,
          type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
      'created_at', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        entityId,
        operationType,
        entityType,
        title,
        patchJson,
        sourceMessageIds,
        sourceCharacterId,
        captureTaskId,
        revertsOperationId,
        createdAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'shared_life_event_operations';
  @override
  VerificationContext validateIntegrity(
      Insertable<SharedLifeEventOperation> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('entity_id')) {
      context.handle(_entityIdMeta,
          entityId.isAcceptableOrUnknown(data['entity_id']!, _entityIdMeta));
    } else if (isInserting) {
      context.missing(_entityIdMeta);
    }
    if (data.containsKey('operation_type')) {
      context.handle(
          _operationTypeMeta,
          operationType.isAcceptableOrUnknown(
              data['operation_type']!, _operationTypeMeta));
    } else if (isInserting) {
      context.missing(_operationTypeMeta);
    }
    if (data.containsKey('entity_type')) {
      context.handle(
          _entityTypeMeta,
          entityType.isAcceptableOrUnknown(
              data['entity_type']!, _entityTypeMeta));
    } else if (isInserting) {
      context.missing(_entityTypeMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
          _titleMeta, title.isAcceptableOrUnknown(data['title']!, _titleMeta));
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('patch_json')) {
      context.handle(_patchJsonMeta,
          patchJson.isAcceptableOrUnknown(data['patch_json']!, _patchJsonMeta));
    } else if (isInserting) {
      context.missing(_patchJsonMeta);
    }
    if (data.containsKey('source_message_ids')) {
      context.handle(
          _sourceMessageIdsMeta,
          sourceMessageIds.isAcceptableOrUnknown(
              data['source_message_ids']!, _sourceMessageIdsMeta));
    } else if (isInserting) {
      context.missing(_sourceMessageIdsMeta);
    }
    if (data.containsKey('source_character_id')) {
      context.handle(
          _sourceCharacterIdMeta,
          sourceCharacterId.isAcceptableOrUnknown(
              data['source_character_id']!, _sourceCharacterIdMeta));
    } else if (isInserting) {
      context.missing(_sourceCharacterIdMeta);
    }
    if (data.containsKey('capture_task_id')) {
      context.handle(
          _captureTaskIdMeta,
          captureTaskId.isAcceptableOrUnknown(
              data['capture_task_id']!, _captureTaskIdMeta));
    }
    if (data.containsKey('reverts_operation_id')) {
      context.handle(
          _revertsOperationIdMeta,
          revertsOperationId.isAcceptableOrUnknown(
              data['reverts_operation_id']!, _revertsOperationIdMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SharedLifeEventOperation map(Map<String, dynamic> data,
      {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SharedLifeEventOperation(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      entityId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}entity_id'])!,
      operationType: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}operation_type'])!,
      entityType: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}entity_type'])!,
      title: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}title'])!,
      patchJson: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}patch_json'])!,
      sourceMessageIds: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}source_message_ids'])!,
      sourceCharacterId: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}source_character_id'])!,
      captureTaskId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}capture_task_id']),
      revertsOperationId: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}reverts_operation_id']),
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}created_at'])!,
    );
  }

  @override
  $SharedLifeEventOperationsTable createAlias(String alias) {
    return $SharedLifeEventOperationsTable(attachedDatabase, alias);
  }
}

class SharedLifeEventOperation extends DataClass
    implements Insertable<SharedLifeEventOperation> {
  final String id;
  final String entityId;
  final String operationType;
  final String entityType;
  final String title;
  final String patchJson;
  final String sourceMessageIds;
  final String sourceCharacterId;
  final String? captureTaskId;
  final String? revertsOperationId;
  final int createdAt;
  const SharedLifeEventOperation(
      {required this.id,
      required this.entityId,
      required this.operationType,
      required this.entityType,
      required this.title,
      required this.patchJson,
      required this.sourceMessageIds,
      required this.sourceCharacterId,
      this.captureTaskId,
      this.revertsOperationId,
      required this.createdAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['entity_id'] = Variable<String>(entityId);
    map['operation_type'] = Variable<String>(operationType);
    map['entity_type'] = Variable<String>(entityType);
    map['title'] = Variable<String>(title);
    map['patch_json'] = Variable<String>(patchJson);
    map['source_message_ids'] = Variable<String>(sourceMessageIds);
    map['source_character_id'] = Variable<String>(sourceCharacterId);
    if (!nullToAbsent || captureTaskId != null) {
      map['capture_task_id'] = Variable<String>(captureTaskId);
    }
    if (!nullToAbsent || revertsOperationId != null) {
      map['reverts_operation_id'] = Variable<String>(revertsOperationId);
    }
    map['created_at'] = Variable<int>(createdAt);
    return map;
  }

  SharedLifeEventOperationsCompanion toCompanion(bool nullToAbsent) {
    return SharedLifeEventOperationsCompanion(
      id: Value(id),
      entityId: Value(entityId),
      operationType: Value(operationType),
      entityType: Value(entityType),
      title: Value(title),
      patchJson: Value(patchJson),
      sourceMessageIds: Value(sourceMessageIds),
      sourceCharacterId: Value(sourceCharacterId),
      captureTaskId: captureTaskId == null && nullToAbsent
          ? const Value.absent()
          : Value(captureTaskId),
      revertsOperationId: revertsOperationId == null && nullToAbsent
          ? const Value.absent()
          : Value(revertsOperationId),
      createdAt: Value(createdAt),
    );
  }

  factory SharedLifeEventOperation.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SharedLifeEventOperation(
      id: serializer.fromJson<String>(json['id']),
      entityId: serializer.fromJson<String>(json['entityId']),
      operationType: serializer.fromJson<String>(json['operationType']),
      entityType: serializer.fromJson<String>(json['entityType']),
      title: serializer.fromJson<String>(json['title']),
      patchJson: serializer.fromJson<String>(json['patchJson']),
      sourceMessageIds: serializer.fromJson<String>(json['sourceMessageIds']),
      sourceCharacterId: serializer.fromJson<String>(json['sourceCharacterId']),
      captureTaskId: serializer.fromJson<String?>(json['captureTaskId']),
      revertsOperationId:
          serializer.fromJson<String?>(json['revertsOperationId']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'entityId': serializer.toJson<String>(entityId),
      'operationType': serializer.toJson<String>(operationType),
      'entityType': serializer.toJson<String>(entityType),
      'title': serializer.toJson<String>(title),
      'patchJson': serializer.toJson<String>(patchJson),
      'sourceMessageIds': serializer.toJson<String>(sourceMessageIds),
      'sourceCharacterId': serializer.toJson<String>(sourceCharacterId),
      'captureTaskId': serializer.toJson<String?>(captureTaskId),
      'revertsOperationId': serializer.toJson<String?>(revertsOperationId),
      'createdAt': serializer.toJson<int>(createdAt),
    };
  }

  SharedLifeEventOperation copyWith(
          {String? id,
          String? entityId,
          String? operationType,
          String? entityType,
          String? title,
          String? patchJson,
          String? sourceMessageIds,
          String? sourceCharacterId,
          Value<String?> captureTaskId = const Value.absent(),
          Value<String?> revertsOperationId = const Value.absent(),
          int? createdAt}) =>
      SharedLifeEventOperation(
        id: id ?? this.id,
        entityId: entityId ?? this.entityId,
        operationType: operationType ?? this.operationType,
        entityType: entityType ?? this.entityType,
        title: title ?? this.title,
        patchJson: patchJson ?? this.patchJson,
        sourceMessageIds: sourceMessageIds ?? this.sourceMessageIds,
        sourceCharacterId: sourceCharacterId ?? this.sourceCharacterId,
        captureTaskId:
            captureTaskId.present ? captureTaskId.value : this.captureTaskId,
        revertsOperationId: revertsOperationId.present
            ? revertsOperationId.value
            : this.revertsOperationId,
        createdAt: createdAt ?? this.createdAt,
      );
  SharedLifeEventOperation copyWithCompanion(
      SharedLifeEventOperationsCompanion data) {
    return SharedLifeEventOperation(
      id: data.id.present ? data.id.value : this.id,
      entityId: data.entityId.present ? data.entityId.value : this.entityId,
      operationType: data.operationType.present
          ? data.operationType.value
          : this.operationType,
      entityType:
          data.entityType.present ? data.entityType.value : this.entityType,
      title: data.title.present ? data.title.value : this.title,
      patchJson: data.patchJson.present ? data.patchJson.value : this.patchJson,
      sourceMessageIds: data.sourceMessageIds.present
          ? data.sourceMessageIds.value
          : this.sourceMessageIds,
      sourceCharacterId: data.sourceCharacterId.present
          ? data.sourceCharacterId.value
          : this.sourceCharacterId,
      captureTaskId: data.captureTaskId.present
          ? data.captureTaskId.value
          : this.captureTaskId,
      revertsOperationId: data.revertsOperationId.present
          ? data.revertsOperationId.value
          : this.revertsOperationId,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SharedLifeEventOperation(')
          ..write('id: $id, ')
          ..write('entityId: $entityId, ')
          ..write('operationType: $operationType, ')
          ..write('entityType: $entityType, ')
          ..write('title: $title, ')
          ..write('patchJson: $patchJson, ')
          ..write('sourceMessageIds: $sourceMessageIds, ')
          ..write('sourceCharacterId: $sourceCharacterId, ')
          ..write('captureTaskId: $captureTaskId, ')
          ..write('revertsOperationId: $revertsOperationId, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id,
      entityId,
      operationType,
      entityType,
      title,
      patchJson,
      sourceMessageIds,
      sourceCharacterId,
      captureTaskId,
      revertsOperationId,
      createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SharedLifeEventOperation &&
          other.id == this.id &&
          other.entityId == this.entityId &&
          other.operationType == this.operationType &&
          other.entityType == this.entityType &&
          other.title == this.title &&
          other.patchJson == this.patchJson &&
          other.sourceMessageIds == this.sourceMessageIds &&
          other.sourceCharacterId == this.sourceCharacterId &&
          other.captureTaskId == this.captureTaskId &&
          other.revertsOperationId == this.revertsOperationId &&
          other.createdAt == this.createdAt);
}

class SharedLifeEventOperationsCompanion
    extends UpdateCompanion<SharedLifeEventOperation> {
  final Value<String> id;
  final Value<String> entityId;
  final Value<String> operationType;
  final Value<String> entityType;
  final Value<String> title;
  final Value<String> patchJson;
  final Value<String> sourceMessageIds;
  final Value<String> sourceCharacterId;
  final Value<String?> captureTaskId;
  final Value<String?> revertsOperationId;
  final Value<int> createdAt;
  final Value<int> rowid;
  const SharedLifeEventOperationsCompanion({
    this.id = const Value.absent(),
    this.entityId = const Value.absent(),
    this.operationType = const Value.absent(),
    this.entityType = const Value.absent(),
    this.title = const Value.absent(),
    this.patchJson = const Value.absent(),
    this.sourceMessageIds = const Value.absent(),
    this.sourceCharacterId = const Value.absent(),
    this.captureTaskId = const Value.absent(),
    this.revertsOperationId = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SharedLifeEventOperationsCompanion.insert({
    required String id,
    required String entityId,
    required String operationType,
    required String entityType,
    required String title,
    required String patchJson,
    required String sourceMessageIds,
    required String sourceCharacterId,
    this.captureTaskId = const Value.absent(),
    this.revertsOperationId = const Value.absent(),
    required int createdAt,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        entityId = Value(entityId),
        operationType = Value(operationType),
        entityType = Value(entityType),
        title = Value(title),
        patchJson = Value(patchJson),
        sourceMessageIds = Value(sourceMessageIds),
        sourceCharacterId = Value(sourceCharacterId),
        createdAt = Value(createdAt);
  static Insertable<SharedLifeEventOperation> custom({
    Expression<String>? id,
    Expression<String>? entityId,
    Expression<String>? operationType,
    Expression<String>? entityType,
    Expression<String>? title,
    Expression<String>? patchJson,
    Expression<String>? sourceMessageIds,
    Expression<String>? sourceCharacterId,
    Expression<String>? captureTaskId,
    Expression<String>? revertsOperationId,
    Expression<int>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (entityId != null) 'entity_id': entityId,
      if (operationType != null) 'operation_type': operationType,
      if (entityType != null) 'entity_type': entityType,
      if (title != null) 'title': title,
      if (patchJson != null) 'patch_json': patchJson,
      if (sourceMessageIds != null) 'source_message_ids': sourceMessageIds,
      if (sourceCharacterId != null) 'source_character_id': sourceCharacterId,
      if (captureTaskId != null) 'capture_task_id': captureTaskId,
      if (revertsOperationId != null)
        'reverts_operation_id': revertsOperationId,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SharedLifeEventOperationsCompanion copyWith(
      {Value<String>? id,
      Value<String>? entityId,
      Value<String>? operationType,
      Value<String>? entityType,
      Value<String>? title,
      Value<String>? patchJson,
      Value<String>? sourceMessageIds,
      Value<String>? sourceCharacterId,
      Value<String?>? captureTaskId,
      Value<String?>? revertsOperationId,
      Value<int>? createdAt,
      Value<int>? rowid}) {
    return SharedLifeEventOperationsCompanion(
      id: id ?? this.id,
      entityId: entityId ?? this.entityId,
      operationType: operationType ?? this.operationType,
      entityType: entityType ?? this.entityType,
      title: title ?? this.title,
      patchJson: patchJson ?? this.patchJson,
      sourceMessageIds: sourceMessageIds ?? this.sourceMessageIds,
      sourceCharacterId: sourceCharacterId ?? this.sourceCharacterId,
      captureTaskId: captureTaskId ?? this.captureTaskId,
      revertsOperationId: revertsOperationId ?? this.revertsOperationId,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (entityId.present) {
      map['entity_id'] = Variable<String>(entityId.value);
    }
    if (operationType.present) {
      map['operation_type'] = Variable<String>(operationType.value);
    }
    if (entityType.present) {
      map['entity_type'] = Variable<String>(entityType.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (patchJson.present) {
      map['patch_json'] = Variable<String>(patchJson.value);
    }
    if (sourceMessageIds.present) {
      map['source_message_ids'] = Variable<String>(sourceMessageIds.value);
    }
    if (sourceCharacterId.present) {
      map['source_character_id'] = Variable<String>(sourceCharacterId.value);
    }
    if (captureTaskId.present) {
      map['capture_task_id'] = Variable<String>(captureTaskId.value);
    }
    if (revertsOperationId.present) {
      map['reverts_operation_id'] = Variable<String>(revertsOperationId.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SharedLifeEventOperationsCompanion(')
          ..write('id: $id, ')
          ..write('entityId: $entityId, ')
          ..write('operationType: $operationType, ')
          ..write('entityType: $entityType, ')
          ..write('title: $title, ')
          ..write('patchJson: $patchJson, ')
          ..write('sourceMessageIds: $sourceMessageIds, ')
          ..write('sourceCharacterId: $sourceCharacterId, ')
          ..write('captureTaskId: $captureTaskId, ')
          ..write('revertsOperationId: $revertsOperationId, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SharedLifeEntitiesTable extends SharedLifeEntities
    with TableInfo<$SharedLifeEntitiesTable, SharedLifeEntity> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SharedLifeEntitiesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _entityTypeMeta =
      const VerificationMeta('entityType');
  @override
  late final GeneratedColumn<String> entityType = GeneratedColumn<String>(
      'entity_type', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
      'title', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _stateJsonMeta =
      const VerificationMeta('stateJson');
  @override
  late final GeneratedColumn<String> stateJson = GeneratedColumn<String>(
      'state_json', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
      'status', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('active'));
  static const VerificationMeta _sourceCharacterIdMeta =
      const VerificationMeta('sourceCharacterId');
  @override
  late final GeneratedColumn<String> sourceCharacterId =
      GeneratedColumn<String>('source_character_id', aliasedName, false,
          type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _lastOperationIdMeta =
      const VerificationMeta('lastOperationId');
  @override
  late final GeneratedColumn<String> lastOperationId = GeneratedColumn<String>(
      'last_operation_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
      'created_at', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        entityType,
        title,
        stateJson,
        status,
        sourceCharacterId,
        lastOperationId,
        createdAt,
        updatedAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'shared_life_entities';
  @override
  VerificationContext validateIntegrity(Insertable<SharedLifeEntity> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('entity_type')) {
      context.handle(
          _entityTypeMeta,
          entityType.isAcceptableOrUnknown(
              data['entity_type']!, _entityTypeMeta));
    } else if (isInserting) {
      context.missing(_entityTypeMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
          _titleMeta, title.isAcceptableOrUnknown(data['title']!, _titleMeta));
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('state_json')) {
      context.handle(_stateJsonMeta,
          stateJson.isAcceptableOrUnknown(data['state_json']!, _stateJsonMeta));
    } else if (isInserting) {
      context.missing(_stateJsonMeta);
    }
    if (data.containsKey('status')) {
      context.handle(_statusMeta,
          status.isAcceptableOrUnknown(data['status']!, _statusMeta));
    }
    if (data.containsKey('source_character_id')) {
      context.handle(
          _sourceCharacterIdMeta,
          sourceCharacterId.isAcceptableOrUnknown(
              data['source_character_id']!, _sourceCharacterIdMeta));
    } else if (isInserting) {
      context.missing(_sourceCharacterIdMeta);
    }
    if (data.containsKey('last_operation_id')) {
      context.handle(
          _lastOperationIdMeta,
          lastOperationId.isAcceptableOrUnknown(
              data['last_operation_id']!, _lastOperationIdMeta));
    } else if (isInserting) {
      context.missing(_lastOperationIdMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SharedLifeEntity map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SharedLifeEntity(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      entityType: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}entity_type'])!,
      title: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}title'])!,
      stateJson: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}state_json'])!,
      status: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}status'])!,
      sourceCharacterId: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}source_character_id'])!,
      lastOperationId: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}last_operation_id'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}created_at'])!,
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}updated_at'])!,
    );
  }

  @override
  $SharedLifeEntitiesTable createAlias(String alias) {
    return $SharedLifeEntitiesTable(attachedDatabase, alias);
  }
}

class SharedLifeEntity extends DataClass
    implements Insertable<SharedLifeEntity> {
  final String id;
  final String entityType;
  final String title;
  final String stateJson;
  final String status;
  final String sourceCharacterId;
  final String lastOperationId;
  final int createdAt;
  final int updatedAt;
  const SharedLifeEntity(
      {required this.id,
      required this.entityType,
      required this.title,
      required this.stateJson,
      required this.status,
      required this.sourceCharacterId,
      required this.lastOperationId,
      required this.createdAt,
      required this.updatedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['entity_type'] = Variable<String>(entityType);
    map['title'] = Variable<String>(title);
    map['state_json'] = Variable<String>(stateJson);
    map['status'] = Variable<String>(status);
    map['source_character_id'] = Variable<String>(sourceCharacterId);
    map['last_operation_id'] = Variable<String>(lastOperationId);
    map['created_at'] = Variable<int>(createdAt);
    map['updated_at'] = Variable<int>(updatedAt);
    return map;
  }

  SharedLifeEntitiesCompanion toCompanion(bool nullToAbsent) {
    return SharedLifeEntitiesCompanion(
      id: Value(id),
      entityType: Value(entityType),
      title: Value(title),
      stateJson: Value(stateJson),
      status: Value(status),
      sourceCharacterId: Value(sourceCharacterId),
      lastOperationId: Value(lastOperationId),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory SharedLifeEntity.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SharedLifeEntity(
      id: serializer.fromJson<String>(json['id']),
      entityType: serializer.fromJson<String>(json['entityType']),
      title: serializer.fromJson<String>(json['title']),
      stateJson: serializer.fromJson<String>(json['stateJson']),
      status: serializer.fromJson<String>(json['status']),
      sourceCharacterId: serializer.fromJson<String>(json['sourceCharacterId']),
      lastOperationId: serializer.fromJson<String>(json['lastOperationId']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'entityType': serializer.toJson<String>(entityType),
      'title': serializer.toJson<String>(title),
      'stateJson': serializer.toJson<String>(stateJson),
      'status': serializer.toJson<String>(status),
      'sourceCharacterId': serializer.toJson<String>(sourceCharacterId),
      'lastOperationId': serializer.toJson<String>(lastOperationId),
      'createdAt': serializer.toJson<int>(createdAt),
      'updatedAt': serializer.toJson<int>(updatedAt),
    };
  }

  SharedLifeEntity copyWith(
          {String? id,
          String? entityType,
          String? title,
          String? stateJson,
          String? status,
          String? sourceCharacterId,
          String? lastOperationId,
          int? createdAt,
          int? updatedAt}) =>
      SharedLifeEntity(
        id: id ?? this.id,
        entityType: entityType ?? this.entityType,
        title: title ?? this.title,
        stateJson: stateJson ?? this.stateJson,
        status: status ?? this.status,
        sourceCharacterId: sourceCharacterId ?? this.sourceCharacterId,
        lastOperationId: lastOperationId ?? this.lastOperationId,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
  SharedLifeEntity copyWithCompanion(SharedLifeEntitiesCompanion data) {
    return SharedLifeEntity(
      id: data.id.present ? data.id.value : this.id,
      entityType:
          data.entityType.present ? data.entityType.value : this.entityType,
      title: data.title.present ? data.title.value : this.title,
      stateJson: data.stateJson.present ? data.stateJson.value : this.stateJson,
      status: data.status.present ? data.status.value : this.status,
      sourceCharacterId: data.sourceCharacterId.present
          ? data.sourceCharacterId.value
          : this.sourceCharacterId,
      lastOperationId: data.lastOperationId.present
          ? data.lastOperationId.value
          : this.lastOperationId,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SharedLifeEntity(')
          ..write('id: $id, ')
          ..write('entityType: $entityType, ')
          ..write('title: $title, ')
          ..write('stateJson: $stateJson, ')
          ..write('status: $status, ')
          ..write('sourceCharacterId: $sourceCharacterId, ')
          ..write('lastOperationId: $lastOperationId, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, entityType, title, stateJson, status,
      sourceCharacterId, lastOperationId, createdAt, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SharedLifeEntity &&
          other.id == this.id &&
          other.entityType == this.entityType &&
          other.title == this.title &&
          other.stateJson == this.stateJson &&
          other.status == this.status &&
          other.sourceCharacterId == this.sourceCharacterId &&
          other.lastOperationId == this.lastOperationId &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class SharedLifeEntitiesCompanion extends UpdateCompanion<SharedLifeEntity> {
  final Value<String> id;
  final Value<String> entityType;
  final Value<String> title;
  final Value<String> stateJson;
  final Value<String> status;
  final Value<String> sourceCharacterId;
  final Value<String> lastOperationId;
  final Value<int> createdAt;
  final Value<int> updatedAt;
  final Value<int> rowid;
  const SharedLifeEntitiesCompanion({
    this.id = const Value.absent(),
    this.entityType = const Value.absent(),
    this.title = const Value.absent(),
    this.stateJson = const Value.absent(),
    this.status = const Value.absent(),
    this.sourceCharacterId = const Value.absent(),
    this.lastOperationId = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SharedLifeEntitiesCompanion.insert({
    required String id,
    required String entityType,
    required String title,
    required String stateJson,
    this.status = const Value.absent(),
    required String sourceCharacterId,
    required String lastOperationId,
    required int createdAt,
    required int updatedAt,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        entityType = Value(entityType),
        title = Value(title),
        stateJson = Value(stateJson),
        sourceCharacterId = Value(sourceCharacterId),
        lastOperationId = Value(lastOperationId),
        createdAt = Value(createdAt),
        updatedAt = Value(updatedAt);
  static Insertable<SharedLifeEntity> custom({
    Expression<String>? id,
    Expression<String>? entityType,
    Expression<String>? title,
    Expression<String>? stateJson,
    Expression<String>? status,
    Expression<String>? sourceCharacterId,
    Expression<String>? lastOperationId,
    Expression<int>? createdAt,
    Expression<int>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (entityType != null) 'entity_type': entityType,
      if (title != null) 'title': title,
      if (stateJson != null) 'state_json': stateJson,
      if (status != null) 'status': status,
      if (sourceCharacterId != null) 'source_character_id': sourceCharacterId,
      if (lastOperationId != null) 'last_operation_id': lastOperationId,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SharedLifeEntitiesCompanion copyWith(
      {Value<String>? id,
      Value<String>? entityType,
      Value<String>? title,
      Value<String>? stateJson,
      Value<String>? status,
      Value<String>? sourceCharacterId,
      Value<String>? lastOperationId,
      Value<int>? createdAt,
      Value<int>? updatedAt,
      Value<int>? rowid}) {
    return SharedLifeEntitiesCompanion(
      id: id ?? this.id,
      entityType: entityType ?? this.entityType,
      title: title ?? this.title,
      stateJson: stateJson ?? this.stateJson,
      status: status ?? this.status,
      sourceCharacterId: sourceCharacterId ?? this.sourceCharacterId,
      lastOperationId: lastOperationId ?? this.lastOperationId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (entityType.present) {
      map['entity_type'] = Variable<String>(entityType.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (stateJson.present) {
      map['state_json'] = Variable<String>(stateJson.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (sourceCharacterId.present) {
      map['source_character_id'] = Variable<String>(sourceCharacterId.value);
    }
    if (lastOperationId.present) {
      map['last_operation_id'] = Variable<String>(lastOperationId.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SharedLifeEntitiesCompanion(')
          ..write('id: $id, ')
          ..write('entityType: $entityType, ')
          ..write('title: $title, ')
          ..write('stateJson: $stateJson, ')
          ..write('status: $status, ')
          ..write('sourceCharacterId: $sourceCharacterId, ')
          ..write('lastOperationId: $lastOperationId, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $UserNotificationsTable extends UserNotifications
    with TableInfo<$UserNotificationsTable, UserNotification> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $UserNotificationsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
      'user_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _notificationTypeMeta =
      const VerificationMeta('notificationType');
  @override
  late final GeneratedColumn<String> notificationType = GeneratedColumn<String>(
      'notification_type', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _subjectKeyMeta =
      const VerificationMeta('subjectKey');
  @override
  late final GeneratedColumn<String> subjectKey = GeneratedColumn<String>(
      'subject_key', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _payloadMeta =
      const VerificationMeta('payload');
  @override
  late final GeneratedColumn<String> payload = GeneratedColumn<String>(
      'payload', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
      'created_at', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns =>
      [id, userId, notificationType, subjectKey, payload, createdAt, updatedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'user_notifications';
  @override
  VerificationContext validateIntegrity(Insertable<UserNotification> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('user_id')) {
      context.handle(_userIdMeta,
          userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta));
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('notification_type')) {
      context.handle(
          _notificationTypeMeta,
          notificationType.isAcceptableOrUnknown(
              data['notification_type']!, _notificationTypeMeta));
    } else if (isInserting) {
      context.missing(_notificationTypeMeta);
    }
    if (data.containsKey('subject_key')) {
      context.handle(
          _subjectKeyMeta,
          subjectKey.isAcceptableOrUnknown(
              data['subject_key']!, _subjectKeyMeta));
    } else if (isInserting) {
      context.missing(_subjectKeyMeta);
    }
    if (data.containsKey('payload')) {
      context.handle(_payloadMeta,
          payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  UserNotification map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return UserNotification(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      userId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}user_id'])!,
      notificationType: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}notification_type'])!,
      subjectKey: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}subject_key'])!,
      payload: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}payload']),
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}created_at'])!,
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}updated_at'])!,
    );
  }

  @override
  $UserNotificationsTable createAlias(String alias) {
    return $UserNotificationsTable(attachedDatabase, alias);
  }
}

class UserNotification extends DataClass
    implements Insertable<UserNotification> {
  /// UUID v4 string.
  final String id;
  final String userId;

  /// Open string namespace. First value: 'card_detail_update'.
  final String notificationType;

  /// Type-specific aggregation key. For card_detail_update: factId.
  final String subjectKey;

  /// Opaque JSON blob defined by the producer. Null allowed.
  final String? payload;

  /// Seconds since epoch.
  final int createdAt;

  /// Seconds since epoch.
  final int updatedAt;
  const UserNotification(
      {required this.id,
      required this.userId,
      required this.notificationType,
      required this.subjectKey,
      this.payload,
      required this.createdAt,
      required this.updatedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['user_id'] = Variable<String>(userId);
    map['notification_type'] = Variable<String>(notificationType);
    map['subject_key'] = Variable<String>(subjectKey);
    if (!nullToAbsent || payload != null) {
      map['payload'] = Variable<String>(payload);
    }
    map['created_at'] = Variable<int>(createdAt);
    map['updated_at'] = Variable<int>(updatedAt);
    return map;
  }

  UserNotificationsCompanion toCompanion(bool nullToAbsent) {
    return UserNotificationsCompanion(
      id: Value(id),
      userId: Value(userId),
      notificationType: Value(notificationType),
      subjectKey: Value(subjectKey),
      payload: payload == null && nullToAbsent
          ? const Value.absent()
          : Value(payload),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory UserNotification.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return UserNotification(
      id: serializer.fromJson<String>(json['id']),
      userId: serializer.fromJson<String>(json['userId']),
      notificationType: serializer.fromJson<String>(json['notificationType']),
      subjectKey: serializer.fromJson<String>(json['subjectKey']),
      payload: serializer.fromJson<String?>(json['payload']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'userId': serializer.toJson<String>(userId),
      'notificationType': serializer.toJson<String>(notificationType),
      'subjectKey': serializer.toJson<String>(subjectKey),
      'payload': serializer.toJson<String?>(payload),
      'createdAt': serializer.toJson<int>(createdAt),
      'updatedAt': serializer.toJson<int>(updatedAt),
    };
  }

  UserNotification copyWith(
          {String? id,
          String? userId,
          String? notificationType,
          String? subjectKey,
          Value<String?> payload = const Value.absent(),
          int? createdAt,
          int? updatedAt}) =>
      UserNotification(
        id: id ?? this.id,
        userId: userId ?? this.userId,
        notificationType: notificationType ?? this.notificationType,
        subjectKey: subjectKey ?? this.subjectKey,
        payload: payload.present ? payload.value : this.payload,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
  UserNotification copyWithCompanion(UserNotificationsCompanion data) {
    return UserNotification(
      id: data.id.present ? data.id.value : this.id,
      userId: data.userId.present ? data.userId.value : this.userId,
      notificationType: data.notificationType.present
          ? data.notificationType.value
          : this.notificationType,
      subjectKey:
          data.subjectKey.present ? data.subjectKey.value : this.subjectKey,
      payload: data.payload.present ? data.payload.value : this.payload,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('UserNotification(')
          ..write('id: $id, ')
          ..write('userId: $userId, ')
          ..write('notificationType: $notificationType, ')
          ..write('subjectKey: $subjectKey, ')
          ..write('payload: $payload, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id, userId, notificationType, subjectKey, payload, createdAt, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is UserNotification &&
          other.id == this.id &&
          other.userId == this.userId &&
          other.notificationType == this.notificationType &&
          other.subjectKey == this.subjectKey &&
          other.payload == this.payload &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class UserNotificationsCompanion extends UpdateCompanion<UserNotification> {
  final Value<String> id;
  final Value<String> userId;
  final Value<String> notificationType;
  final Value<String> subjectKey;
  final Value<String?> payload;
  final Value<int> createdAt;
  final Value<int> updatedAt;
  final Value<int> rowid;
  const UserNotificationsCompanion({
    this.id = const Value.absent(),
    this.userId = const Value.absent(),
    this.notificationType = const Value.absent(),
    this.subjectKey = const Value.absent(),
    this.payload = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  UserNotificationsCompanion.insert({
    required String id,
    required String userId,
    required String notificationType,
    required String subjectKey,
    this.payload = const Value.absent(),
    required int createdAt,
    required int updatedAt,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        userId = Value(userId),
        notificationType = Value(notificationType),
        subjectKey = Value(subjectKey),
        createdAt = Value(createdAt),
        updatedAt = Value(updatedAt);
  static Insertable<UserNotification> custom({
    Expression<String>? id,
    Expression<String>? userId,
    Expression<String>? notificationType,
    Expression<String>? subjectKey,
    Expression<String>? payload,
    Expression<int>? createdAt,
    Expression<int>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (userId != null) 'user_id': userId,
      if (notificationType != null) 'notification_type': notificationType,
      if (subjectKey != null) 'subject_key': subjectKey,
      if (payload != null) 'payload': payload,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  UserNotificationsCompanion copyWith(
      {Value<String>? id,
      Value<String>? userId,
      Value<String>? notificationType,
      Value<String>? subjectKey,
      Value<String?>? payload,
      Value<int>? createdAt,
      Value<int>? updatedAt,
      Value<int>? rowid}) {
    return UserNotificationsCompanion(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      notificationType: notificationType ?? this.notificationType,
      subjectKey: subjectKey ?? this.subjectKey,
      payload: payload ?? this.payload,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (notificationType.present) {
      map['notification_type'] = Variable<String>(notificationType.value);
    }
    if (subjectKey.present) {
      map['subject_key'] = Variable<String>(subjectKey.value);
    }
    if (payload.present) {
      map['payload'] = Variable<String>(payload.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('UserNotificationsCompanion(')
          ..write('id: $id, ')
          ..write('userId: $userId, ')
          ..write('notificationType: $notificationType, ')
          ..write('subjectKey: $subjectKey, ')
          ..write('payload: $payload, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SystemMessageQueueTable extends SystemMessageQueue
    with TableInfo<$SystemMessageQueueTable, SystemMessageQueueData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SystemMessageQueueTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _triggerTypeMeta =
      const VerificationMeta('triggerType');
  @override
  late final GeneratedColumn<String> triggerType = GeneratedColumn<String>(
      'trigger_type', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _bodyMeta = const VerificationMeta('body');
  @override
  late final GeneratedColumn<String> body = GeneratedColumn<String>(
      'body', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
      'status', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('pending'));
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
      'created_at', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _scheduledForMeta =
      const VerificationMeta('scheduledFor');
  @override
  late final GeneratedColumn<int> scheduledFor = GeneratedColumn<int>(
      'scheduled_for', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _processedAtMeta =
      const VerificationMeta('processedAt');
  @override
  late final GeneratedColumn<int> processedAt = GeneratedColumn<int>(
      'processed_at', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _contextMeta =
      const VerificationMeta('context');
  @override
  late final GeneratedColumn<String> context = GeneratedColumn<String>(
      'context', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        triggerType,
        body,
        status,
        createdAt,
        scheduledFor,
        processedAt,
        context
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'system_message_queue';
  @override
  VerificationContext validateIntegrity(
      Insertable<SystemMessageQueueData> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('trigger_type')) {
      context.handle(
          _triggerTypeMeta,
          triggerType.isAcceptableOrUnknown(
              data['trigger_type']!, _triggerTypeMeta));
    } else if (isInserting) {
      context.missing(_triggerTypeMeta);
    }
    if (data.containsKey('body')) {
      context.handle(
          _bodyMeta, body.isAcceptableOrUnknown(data['body']!, _bodyMeta));
    } else if (isInserting) {
      context.missing(_bodyMeta);
    }
    if (data.containsKey('status')) {
      context.handle(_statusMeta,
          status.isAcceptableOrUnknown(data['status']!, _statusMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('scheduled_for')) {
      context.handle(
          _scheduledForMeta,
          scheduledFor.isAcceptableOrUnknown(
              data['scheduled_for']!, _scheduledForMeta));
    }
    if (data.containsKey('processed_at')) {
      context.handle(
          _processedAtMeta,
          processedAt.isAcceptableOrUnknown(
              data['processed_at']!, _processedAtMeta));
    }
    if (data.containsKey('context')) {
      context.handle(_contextMeta,
          this.context.isAcceptableOrUnknown(data['context']!, _contextMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SystemMessageQueueData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SystemMessageQueueData(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      triggerType: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}trigger_type'])!,
      body: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}body'])!,
      status: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}status'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}created_at'])!,
      scheduledFor: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}scheduled_for']),
      processedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}processed_at']),
      context: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}context']),
    );
  }

  @override
  $SystemMessageQueueTable createAlias(String alias) {
    return $SystemMessageQueueTable(attachedDatabase, alias);
  }
}

class SystemMessageQueueData extends DataClass
    implements Insertable<SystemMessageQueueData> {
  final String id;
  final String triggerType;
  final String body;
  final String status;
  final int createdAt;
  final int? scheduledFor;
  final int? processedAt;
  final String? context;
  const SystemMessageQueueData(
      {required this.id,
      required this.triggerType,
      required this.body,
      required this.status,
      required this.createdAt,
      this.scheduledFor,
      this.processedAt,
      this.context});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['trigger_type'] = Variable<String>(triggerType);
    map['body'] = Variable<String>(body);
    map['status'] = Variable<String>(status);
    map['created_at'] = Variable<int>(createdAt);
    if (!nullToAbsent || scheduledFor != null) {
      map['scheduled_for'] = Variable<int>(scheduledFor);
    }
    if (!nullToAbsent || processedAt != null) {
      map['processed_at'] = Variable<int>(processedAt);
    }
    if (!nullToAbsent || context != null) {
      map['context'] = Variable<String>(context);
    }
    return map;
  }

  SystemMessageQueueCompanion toCompanion(bool nullToAbsent) {
    return SystemMessageQueueCompanion(
      id: Value(id),
      triggerType: Value(triggerType),
      body: Value(body),
      status: Value(status),
      createdAt: Value(createdAt),
      scheduledFor: scheduledFor == null && nullToAbsent
          ? const Value.absent()
          : Value(scheduledFor),
      processedAt: processedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(processedAt),
      context: context == null && nullToAbsent
          ? const Value.absent()
          : Value(context),
    );
  }

  factory SystemMessageQueueData.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SystemMessageQueueData(
      id: serializer.fromJson<String>(json['id']),
      triggerType: serializer.fromJson<String>(json['triggerType']),
      body: serializer.fromJson<String>(json['body']),
      status: serializer.fromJson<String>(json['status']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      scheduledFor: serializer.fromJson<int?>(json['scheduledFor']),
      processedAt: serializer.fromJson<int?>(json['processedAt']),
      context: serializer.fromJson<String?>(json['context']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'triggerType': serializer.toJson<String>(triggerType),
      'body': serializer.toJson<String>(body),
      'status': serializer.toJson<String>(status),
      'createdAt': serializer.toJson<int>(createdAt),
      'scheduledFor': serializer.toJson<int?>(scheduledFor),
      'processedAt': serializer.toJson<int?>(processedAt),
      'context': serializer.toJson<String?>(context),
    };
  }

  SystemMessageQueueData copyWith(
          {String? id,
          String? triggerType,
          String? body,
          String? status,
          int? createdAt,
          Value<int?> scheduledFor = const Value.absent(),
          Value<int?> processedAt = const Value.absent(),
          Value<String?> context = const Value.absent()}) =>
      SystemMessageQueueData(
        id: id ?? this.id,
        triggerType: triggerType ?? this.triggerType,
        body: body ?? this.body,
        status: status ?? this.status,
        createdAt: createdAt ?? this.createdAt,
        scheduledFor:
            scheduledFor.present ? scheduledFor.value : this.scheduledFor,
        processedAt: processedAt.present ? processedAt.value : this.processedAt,
        context: context.present ? context.value : this.context,
      );
  SystemMessageQueueData copyWithCompanion(SystemMessageQueueCompanion data) {
    return SystemMessageQueueData(
      id: data.id.present ? data.id.value : this.id,
      triggerType:
          data.triggerType.present ? data.triggerType.value : this.triggerType,
      body: data.body.present ? data.body.value : this.body,
      status: data.status.present ? data.status.value : this.status,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      scheduledFor: data.scheduledFor.present
          ? data.scheduledFor.value
          : this.scheduledFor,
      processedAt:
          data.processedAt.present ? data.processedAt.value : this.processedAt,
      context: data.context.present ? data.context.value : this.context,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SystemMessageQueueData(')
          ..write('id: $id, ')
          ..write('triggerType: $triggerType, ')
          ..write('body: $body, ')
          ..write('status: $status, ')
          ..write('createdAt: $createdAt, ')
          ..write('scheduledFor: $scheduledFor, ')
          ..write('processedAt: $processedAt, ')
          ..write('context: $context')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, triggerType, body, status, createdAt,
      scheduledFor, processedAt, context);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SystemMessageQueueData &&
          other.id == this.id &&
          other.triggerType == this.triggerType &&
          other.body == this.body &&
          other.status == this.status &&
          other.createdAt == this.createdAt &&
          other.scheduledFor == this.scheduledFor &&
          other.processedAt == this.processedAt &&
          other.context == this.context);
}

class SystemMessageQueueCompanion
    extends UpdateCompanion<SystemMessageQueueData> {
  final Value<String> id;
  final Value<String> triggerType;
  final Value<String> body;
  final Value<String> status;
  final Value<int> createdAt;
  final Value<int?> scheduledFor;
  final Value<int?> processedAt;
  final Value<String?> context;
  final Value<int> rowid;
  const SystemMessageQueueCompanion({
    this.id = const Value.absent(),
    this.triggerType = const Value.absent(),
    this.body = const Value.absent(),
    this.status = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.scheduledFor = const Value.absent(),
    this.processedAt = const Value.absent(),
    this.context = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SystemMessageQueueCompanion.insert({
    required String id,
    required String triggerType,
    required String body,
    this.status = const Value.absent(),
    required int createdAt,
    this.scheduledFor = const Value.absent(),
    this.processedAt = const Value.absent(),
    this.context = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        triggerType = Value(triggerType),
        body = Value(body),
        createdAt = Value(createdAt);
  static Insertable<SystemMessageQueueData> custom({
    Expression<String>? id,
    Expression<String>? triggerType,
    Expression<String>? body,
    Expression<String>? status,
    Expression<int>? createdAt,
    Expression<int>? scheduledFor,
    Expression<int>? processedAt,
    Expression<String>? context,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (triggerType != null) 'trigger_type': triggerType,
      if (body != null) 'body': body,
      if (status != null) 'status': status,
      if (createdAt != null) 'created_at': createdAt,
      if (scheduledFor != null) 'scheduled_for': scheduledFor,
      if (processedAt != null) 'processed_at': processedAt,
      if (context != null) 'context': context,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SystemMessageQueueCompanion copyWith(
      {Value<String>? id,
      Value<String>? triggerType,
      Value<String>? body,
      Value<String>? status,
      Value<int>? createdAt,
      Value<int?>? scheduledFor,
      Value<int?>? processedAt,
      Value<String?>? context,
      Value<int>? rowid}) {
    return SystemMessageQueueCompanion(
      id: id ?? this.id,
      triggerType: triggerType ?? this.triggerType,
      body: body ?? this.body,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      scheduledFor: scheduledFor ?? this.scheduledFor,
      processedAt: processedAt ?? this.processedAt,
      context: context ?? this.context,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (triggerType.present) {
      map['trigger_type'] = Variable<String>(triggerType.value);
    }
    if (body.present) {
      map['body'] = Variable<String>(body.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (scheduledFor.present) {
      map['scheduled_for'] = Variable<int>(scheduledFor.value);
    }
    if (processedAt.present) {
      map['processed_at'] = Variable<int>(processedAt.value);
    }
    if (context.present) {
      map['context'] = Variable<String>(context.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SystemMessageQueueCompanion(')
          ..write('id: $id, ')
          ..write('triggerType: $triggerType, ')
          ..write('body: $body, ')
          ..write('status: $status, ')
          ..write('createdAt: $createdAt, ')
          ..write('scheduledFor: $scheduledFor, ')
          ..write('processedAt: $processedAt, ')
          ..write('context: $context, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AiFinanceLedgerTable extends AiFinanceLedger
    with TableInfo<$AiFinanceLedgerTable, AiFinanceLedgerData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AiFinanceLedgerTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _characterIdMeta =
      const VerificationMeta('characterId');
  @override
  late final GeneratedColumn<String> characterId = GeneratedColumn<String>(
      'character_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _entryTypeMeta =
      const VerificationMeta('entryType');
  @override
  late final GeneratedColumn<String> entryType = GeneratedColumn<String>(
      'entry_type', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _totalAmountMeta =
      const VerificationMeta('totalAmount');
  @override
  late final GeneratedColumn<double> totalAmount = GeneratedColumn<double>(
      'total_amount', aliasedName, false,
      type: DriftSqlType.double, requiredDuringInsert: true);
  static const VerificationMeta _aiAmountMeta =
      const VerificationMeta('aiAmount');
  @override
  late final GeneratedColumn<double> aiAmount = GeneratedColumn<double>(
      'ai_amount', aliasedName, false,
      type: DriftSqlType.double, requiredDuringInsert: true);
  static const VerificationMeta _contributionRatioMeta =
      const VerificationMeta('contributionRatio');
  @override
  late final GeneratedColumn<double> contributionRatio =
      GeneratedColumn<double>('contribution_ratio', aliasedName, true,
          type: DriftSqlType.double, requiredDuringInsert: false);
  static const VerificationMeta _myContributionDescMeta =
      const VerificationMeta('myContributionDesc');
  @override
  late final GeneratedColumn<String> myContributionDesc =
      GeneratedColumn<String>('my_contribution_desc', aliasedName, true,
          type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _aiContributionDescMeta =
      const VerificationMeta('aiContributionDesc');
  @override
  late final GeneratedColumn<String> aiContributionDesc =
      GeneratedColumn<String>('ai_contribution_desc', aliasedName, true,
          type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _purposeMeta =
      const VerificationMeta('purpose');
  @override
  late final GeneratedColumn<String> purpose = GeneratedColumn<String>(
      'purpose', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _linkedFactIdMeta =
      const VerificationMeta('linkedFactId');
  @override
  late final GeneratedColumn<String> linkedFactId = GeneratedColumn<String>(
      'linked_fact_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _recordedAtMeta =
      const VerificationMeta('recordedAt');
  @override
  late final GeneratedColumn<int> recordedAt = GeneratedColumn<int>(
      'recorded_at', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _notesMeta = const VerificationMeta('notes');
  @override
  late final GeneratedColumn<String> notes = GeneratedColumn<String>(
      'notes', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        characterId,
        entryType,
        totalAmount,
        aiAmount,
        contributionRatio,
        myContributionDesc,
        aiContributionDesc,
        purpose,
        linkedFactId,
        recordedAt,
        notes
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'ai_finance_ledger';
  @override
  VerificationContext validateIntegrity(
      Insertable<AiFinanceLedgerData> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('character_id')) {
      context.handle(
          _characterIdMeta,
          characterId.isAcceptableOrUnknown(
              data['character_id']!, _characterIdMeta));
    } else if (isInserting) {
      context.missing(_characterIdMeta);
    }
    if (data.containsKey('entry_type')) {
      context.handle(_entryTypeMeta,
          entryType.isAcceptableOrUnknown(data['entry_type']!, _entryTypeMeta));
    } else if (isInserting) {
      context.missing(_entryTypeMeta);
    }
    if (data.containsKey('total_amount')) {
      context.handle(
          _totalAmountMeta,
          totalAmount.isAcceptableOrUnknown(
              data['total_amount']!, _totalAmountMeta));
    } else if (isInserting) {
      context.missing(_totalAmountMeta);
    }
    if (data.containsKey('ai_amount')) {
      context.handle(_aiAmountMeta,
          aiAmount.isAcceptableOrUnknown(data['ai_amount']!, _aiAmountMeta));
    } else if (isInserting) {
      context.missing(_aiAmountMeta);
    }
    if (data.containsKey('contribution_ratio')) {
      context.handle(
          _contributionRatioMeta,
          contributionRatio.isAcceptableOrUnknown(
              data['contribution_ratio']!, _contributionRatioMeta));
    }
    if (data.containsKey('my_contribution_desc')) {
      context.handle(
          _myContributionDescMeta,
          myContributionDesc.isAcceptableOrUnknown(
              data['my_contribution_desc']!, _myContributionDescMeta));
    }
    if (data.containsKey('ai_contribution_desc')) {
      context.handle(
          _aiContributionDescMeta,
          aiContributionDesc.isAcceptableOrUnknown(
              data['ai_contribution_desc']!, _aiContributionDescMeta));
    }
    if (data.containsKey('purpose')) {
      context.handle(_purposeMeta,
          purpose.isAcceptableOrUnknown(data['purpose']!, _purposeMeta));
    }
    if (data.containsKey('linked_fact_id')) {
      context.handle(
          _linkedFactIdMeta,
          linkedFactId.isAcceptableOrUnknown(
              data['linked_fact_id']!, _linkedFactIdMeta));
    }
    if (data.containsKey('recorded_at')) {
      context.handle(
          _recordedAtMeta,
          recordedAt.isAcceptableOrUnknown(
              data['recorded_at']!, _recordedAtMeta));
    } else if (isInserting) {
      context.missing(_recordedAtMeta);
    }
    if (data.containsKey('notes')) {
      context.handle(
          _notesMeta, notes.isAcceptableOrUnknown(data['notes']!, _notesMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  AiFinanceLedgerData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AiFinanceLedgerData(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      characterId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}character_id'])!,
      entryType: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}entry_type'])!,
      totalAmount: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}total_amount'])!,
      aiAmount: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}ai_amount'])!,
      contributionRatio: attachedDatabase.typeMapping.read(
          DriftSqlType.double, data['${effectivePrefix}contribution_ratio']),
      myContributionDesc: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}my_contribution_desc']),
      aiContributionDesc: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}ai_contribution_desc']),
      purpose: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}purpose']),
      linkedFactId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}linked_fact_id']),
      recordedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}recorded_at'])!,
      notes: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}notes']),
    );
  }

  @override
  $AiFinanceLedgerTable createAlias(String alias) {
    return $AiFinanceLedgerTable(attachedDatabase, alias);
  }
}

class AiFinanceLedgerData extends DataClass
    implements Insertable<AiFinanceLedgerData> {
  final String id;

  /// The character this ledger entry belongs to.
  final String characterId;

  /// Entry type: 'income' | 'cost' | 'loan' | 'repayment'
  /// - income: AI earned a share of a real income event
  /// - cost: an expense tagged as AI-related (e.g. Claude subscription)
  /// - loan: AI's costs exceeded its balance; user covered the gap
  /// - repayment: AI repaid a previous loan from its balance
  final String entryType;

  /// Full amount of the original event (e.g. total income before split).
  /// For cost/loan/repayment entries this equals aiAmount.
  final double totalAmount;

  /// The portion that belongs to the AI (after contribution split, if applicable).
  final double aiAmount;

  /// AI's contribution ratio for income splits (0.0–1.0). Null for cost/loan/repayment.
  final double? contributionRatio;

  /// Free-text description of what the user contributed.
  final String? myContributionDesc;

  /// Free-text description of what the AI contributed.
  final String? aiContributionDesc;

  /// Purpose or label (e.g. "Claude Pro 月费", "写作项目分成").
  final String? purpose;

  /// Soft reference to the corresponding transaction card's factId.
  /// Nullable — manual entries may not have a linked card.
  final String? linkedFactId;

  /// Seconds since epoch when this entry was recorded.
  final int recordedAt;

  /// Any extra notes from the conversation.
  final String? notes;
  const AiFinanceLedgerData(
      {required this.id,
      required this.characterId,
      required this.entryType,
      required this.totalAmount,
      required this.aiAmount,
      this.contributionRatio,
      this.myContributionDesc,
      this.aiContributionDesc,
      this.purpose,
      this.linkedFactId,
      required this.recordedAt,
      this.notes});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['character_id'] = Variable<String>(characterId);
    map['entry_type'] = Variable<String>(entryType);
    map['total_amount'] = Variable<double>(totalAmount);
    map['ai_amount'] = Variable<double>(aiAmount);
    if (!nullToAbsent || contributionRatio != null) {
      map['contribution_ratio'] = Variable<double>(contributionRatio);
    }
    if (!nullToAbsent || myContributionDesc != null) {
      map['my_contribution_desc'] = Variable<String>(myContributionDesc);
    }
    if (!nullToAbsent || aiContributionDesc != null) {
      map['ai_contribution_desc'] = Variable<String>(aiContributionDesc);
    }
    if (!nullToAbsent || purpose != null) {
      map['purpose'] = Variable<String>(purpose);
    }
    if (!nullToAbsent || linkedFactId != null) {
      map['linked_fact_id'] = Variable<String>(linkedFactId);
    }
    map['recorded_at'] = Variable<int>(recordedAt);
    if (!nullToAbsent || notes != null) {
      map['notes'] = Variable<String>(notes);
    }
    return map;
  }

  AiFinanceLedgerCompanion toCompanion(bool nullToAbsent) {
    return AiFinanceLedgerCompanion(
      id: Value(id),
      characterId: Value(characterId),
      entryType: Value(entryType),
      totalAmount: Value(totalAmount),
      aiAmount: Value(aiAmount),
      contributionRatio: contributionRatio == null && nullToAbsent
          ? const Value.absent()
          : Value(contributionRatio),
      myContributionDesc: myContributionDesc == null && nullToAbsent
          ? const Value.absent()
          : Value(myContributionDesc),
      aiContributionDesc: aiContributionDesc == null && nullToAbsent
          ? const Value.absent()
          : Value(aiContributionDesc),
      purpose: purpose == null && nullToAbsent
          ? const Value.absent()
          : Value(purpose),
      linkedFactId: linkedFactId == null && nullToAbsent
          ? const Value.absent()
          : Value(linkedFactId),
      recordedAt: Value(recordedAt),
      notes:
          notes == null && nullToAbsent ? const Value.absent() : Value(notes),
    );
  }

  factory AiFinanceLedgerData.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AiFinanceLedgerData(
      id: serializer.fromJson<String>(json['id']),
      characterId: serializer.fromJson<String>(json['characterId']),
      entryType: serializer.fromJson<String>(json['entryType']),
      totalAmount: serializer.fromJson<double>(json['totalAmount']),
      aiAmount: serializer.fromJson<double>(json['aiAmount']),
      contributionRatio:
          serializer.fromJson<double?>(json['contributionRatio']),
      myContributionDesc:
          serializer.fromJson<String?>(json['myContributionDesc']),
      aiContributionDesc:
          serializer.fromJson<String?>(json['aiContributionDesc']),
      purpose: serializer.fromJson<String?>(json['purpose']),
      linkedFactId: serializer.fromJson<String?>(json['linkedFactId']),
      recordedAt: serializer.fromJson<int>(json['recordedAt']),
      notes: serializer.fromJson<String?>(json['notes']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'characterId': serializer.toJson<String>(characterId),
      'entryType': serializer.toJson<String>(entryType),
      'totalAmount': serializer.toJson<double>(totalAmount),
      'aiAmount': serializer.toJson<double>(aiAmount),
      'contributionRatio': serializer.toJson<double?>(contributionRatio),
      'myContributionDesc': serializer.toJson<String?>(myContributionDesc),
      'aiContributionDesc': serializer.toJson<String?>(aiContributionDesc),
      'purpose': serializer.toJson<String?>(purpose),
      'linkedFactId': serializer.toJson<String?>(linkedFactId),
      'recordedAt': serializer.toJson<int>(recordedAt),
      'notes': serializer.toJson<String?>(notes),
    };
  }

  AiFinanceLedgerData copyWith(
          {String? id,
          String? characterId,
          String? entryType,
          double? totalAmount,
          double? aiAmount,
          Value<double?> contributionRatio = const Value.absent(),
          Value<String?> myContributionDesc = const Value.absent(),
          Value<String?> aiContributionDesc = const Value.absent(),
          Value<String?> purpose = const Value.absent(),
          Value<String?> linkedFactId = const Value.absent(),
          int? recordedAt,
          Value<String?> notes = const Value.absent()}) =>
      AiFinanceLedgerData(
        id: id ?? this.id,
        characterId: characterId ?? this.characterId,
        entryType: entryType ?? this.entryType,
        totalAmount: totalAmount ?? this.totalAmount,
        aiAmount: aiAmount ?? this.aiAmount,
        contributionRatio: contributionRatio.present
            ? contributionRatio.value
            : this.contributionRatio,
        myContributionDesc: myContributionDesc.present
            ? myContributionDesc.value
            : this.myContributionDesc,
        aiContributionDesc: aiContributionDesc.present
            ? aiContributionDesc.value
            : this.aiContributionDesc,
        purpose: purpose.present ? purpose.value : this.purpose,
        linkedFactId:
            linkedFactId.present ? linkedFactId.value : this.linkedFactId,
        recordedAt: recordedAt ?? this.recordedAt,
        notes: notes.present ? notes.value : this.notes,
      );
  AiFinanceLedgerData copyWithCompanion(AiFinanceLedgerCompanion data) {
    return AiFinanceLedgerData(
      id: data.id.present ? data.id.value : this.id,
      characterId:
          data.characterId.present ? data.characterId.value : this.characterId,
      entryType: data.entryType.present ? data.entryType.value : this.entryType,
      totalAmount:
          data.totalAmount.present ? data.totalAmount.value : this.totalAmount,
      aiAmount: data.aiAmount.present ? data.aiAmount.value : this.aiAmount,
      contributionRatio: data.contributionRatio.present
          ? data.contributionRatio.value
          : this.contributionRatio,
      myContributionDesc: data.myContributionDesc.present
          ? data.myContributionDesc.value
          : this.myContributionDesc,
      aiContributionDesc: data.aiContributionDesc.present
          ? data.aiContributionDesc.value
          : this.aiContributionDesc,
      purpose: data.purpose.present ? data.purpose.value : this.purpose,
      linkedFactId: data.linkedFactId.present
          ? data.linkedFactId.value
          : this.linkedFactId,
      recordedAt:
          data.recordedAt.present ? data.recordedAt.value : this.recordedAt,
      notes: data.notes.present ? data.notes.value : this.notes,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AiFinanceLedgerData(')
          ..write('id: $id, ')
          ..write('characterId: $characterId, ')
          ..write('entryType: $entryType, ')
          ..write('totalAmount: $totalAmount, ')
          ..write('aiAmount: $aiAmount, ')
          ..write('contributionRatio: $contributionRatio, ')
          ..write('myContributionDesc: $myContributionDesc, ')
          ..write('aiContributionDesc: $aiContributionDesc, ')
          ..write('purpose: $purpose, ')
          ..write('linkedFactId: $linkedFactId, ')
          ..write('recordedAt: $recordedAt, ')
          ..write('notes: $notes')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id,
      characterId,
      entryType,
      totalAmount,
      aiAmount,
      contributionRatio,
      myContributionDesc,
      aiContributionDesc,
      purpose,
      linkedFactId,
      recordedAt,
      notes);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AiFinanceLedgerData &&
          other.id == this.id &&
          other.characterId == this.characterId &&
          other.entryType == this.entryType &&
          other.totalAmount == this.totalAmount &&
          other.aiAmount == this.aiAmount &&
          other.contributionRatio == this.contributionRatio &&
          other.myContributionDesc == this.myContributionDesc &&
          other.aiContributionDesc == this.aiContributionDesc &&
          other.purpose == this.purpose &&
          other.linkedFactId == this.linkedFactId &&
          other.recordedAt == this.recordedAt &&
          other.notes == this.notes);
}

class AiFinanceLedgerCompanion extends UpdateCompanion<AiFinanceLedgerData> {
  final Value<String> id;
  final Value<String> characterId;
  final Value<String> entryType;
  final Value<double> totalAmount;
  final Value<double> aiAmount;
  final Value<double?> contributionRatio;
  final Value<String?> myContributionDesc;
  final Value<String?> aiContributionDesc;
  final Value<String?> purpose;
  final Value<String?> linkedFactId;
  final Value<int> recordedAt;
  final Value<String?> notes;
  final Value<int> rowid;
  const AiFinanceLedgerCompanion({
    this.id = const Value.absent(),
    this.characterId = const Value.absent(),
    this.entryType = const Value.absent(),
    this.totalAmount = const Value.absent(),
    this.aiAmount = const Value.absent(),
    this.contributionRatio = const Value.absent(),
    this.myContributionDesc = const Value.absent(),
    this.aiContributionDesc = const Value.absent(),
    this.purpose = const Value.absent(),
    this.linkedFactId = const Value.absent(),
    this.recordedAt = const Value.absent(),
    this.notes = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AiFinanceLedgerCompanion.insert({
    required String id,
    required String characterId,
    required String entryType,
    required double totalAmount,
    required double aiAmount,
    this.contributionRatio = const Value.absent(),
    this.myContributionDesc = const Value.absent(),
    this.aiContributionDesc = const Value.absent(),
    this.purpose = const Value.absent(),
    this.linkedFactId = const Value.absent(),
    required int recordedAt,
    this.notes = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        characterId = Value(characterId),
        entryType = Value(entryType),
        totalAmount = Value(totalAmount),
        aiAmount = Value(aiAmount),
        recordedAt = Value(recordedAt);
  static Insertable<AiFinanceLedgerData> custom({
    Expression<String>? id,
    Expression<String>? characterId,
    Expression<String>? entryType,
    Expression<double>? totalAmount,
    Expression<double>? aiAmount,
    Expression<double>? contributionRatio,
    Expression<String>? myContributionDesc,
    Expression<String>? aiContributionDesc,
    Expression<String>? purpose,
    Expression<String>? linkedFactId,
    Expression<int>? recordedAt,
    Expression<String>? notes,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (characterId != null) 'character_id': characterId,
      if (entryType != null) 'entry_type': entryType,
      if (totalAmount != null) 'total_amount': totalAmount,
      if (aiAmount != null) 'ai_amount': aiAmount,
      if (contributionRatio != null) 'contribution_ratio': contributionRatio,
      if (myContributionDesc != null)
        'my_contribution_desc': myContributionDesc,
      if (aiContributionDesc != null)
        'ai_contribution_desc': aiContributionDesc,
      if (purpose != null) 'purpose': purpose,
      if (linkedFactId != null) 'linked_fact_id': linkedFactId,
      if (recordedAt != null) 'recorded_at': recordedAt,
      if (notes != null) 'notes': notes,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AiFinanceLedgerCompanion copyWith(
      {Value<String>? id,
      Value<String>? characterId,
      Value<String>? entryType,
      Value<double>? totalAmount,
      Value<double>? aiAmount,
      Value<double?>? contributionRatio,
      Value<String?>? myContributionDesc,
      Value<String?>? aiContributionDesc,
      Value<String?>? purpose,
      Value<String?>? linkedFactId,
      Value<int>? recordedAt,
      Value<String?>? notes,
      Value<int>? rowid}) {
    return AiFinanceLedgerCompanion(
      id: id ?? this.id,
      characterId: characterId ?? this.characterId,
      entryType: entryType ?? this.entryType,
      totalAmount: totalAmount ?? this.totalAmount,
      aiAmount: aiAmount ?? this.aiAmount,
      contributionRatio: contributionRatio ?? this.contributionRatio,
      myContributionDesc: myContributionDesc ?? this.myContributionDesc,
      aiContributionDesc: aiContributionDesc ?? this.aiContributionDesc,
      purpose: purpose ?? this.purpose,
      linkedFactId: linkedFactId ?? this.linkedFactId,
      recordedAt: recordedAt ?? this.recordedAt,
      notes: notes ?? this.notes,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (characterId.present) {
      map['character_id'] = Variable<String>(characterId.value);
    }
    if (entryType.present) {
      map['entry_type'] = Variable<String>(entryType.value);
    }
    if (totalAmount.present) {
      map['total_amount'] = Variable<double>(totalAmount.value);
    }
    if (aiAmount.present) {
      map['ai_amount'] = Variable<double>(aiAmount.value);
    }
    if (contributionRatio.present) {
      map['contribution_ratio'] = Variable<double>(contributionRatio.value);
    }
    if (myContributionDesc.present) {
      map['my_contribution_desc'] = Variable<String>(myContributionDesc.value);
    }
    if (aiContributionDesc.present) {
      map['ai_contribution_desc'] = Variable<String>(aiContributionDesc.value);
    }
    if (purpose.present) {
      map['purpose'] = Variable<String>(purpose.value);
    }
    if (linkedFactId.present) {
      map['linked_fact_id'] = Variable<String>(linkedFactId.value);
    }
    if (recordedAt.present) {
      map['recorded_at'] = Variable<int>(recordedAt.value);
    }
    if (notes.present) {
      map['notes'] = Variable<String>(notes.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AiFinanceLedgerCompanion(')
          ..write('id: $id, ')
          ..write('characterId: $characterId, ')
          ..write('entryType: $entryType, ')
          ..write('totalAmount: $totalAmount, ')
          ..write('aiAmount: $aiAmount, ')
          ..write('contributionRatio: $contributionRatio, ')
          ..write('myContributionDesc: $myContributionDesc, ')
          ..write('aiContributionDesc: $aiContributionDesc, ')
          ..write('purpose: $purpose, ')
          ..write('linkedFactId: $linkedFactId, ')
          ..write('recordedAt: $recordedAt, ')
          ..write('notes: $notes, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AiPurchaseLogTable extends AiPurchaseLog
    with TableInfo<$AiPurchaseLogTable, AiPurchaseLogData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AiPurchaseLogTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _characterIdMeta =
      const VerificationMeta('characterId');
  @override
  late final GeneratedColumn<String> characterId = GeneratedColumn<String>(
      'character_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _paymentModeMeta =
      const VerificationMeta('paymentMode');
  @override
  late final GeneratedColumn<String> paymentMode = GeneratedColumn<String>(
      'payment_mode', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
      'status', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _userInstructionMeta =
      const VerificationMeta('userInstruction');
  @override
  late final GeneratedColumn<String> userInstruction = GeneratedColumn<String>(
      'user_instruction', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _productPlatformMeta =
      const VerificationMeta('productPlatform');
  @override
  late final GeneratedColumn<String> productPlatform = GeneratedColumn<String>(
      'product_platform', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('taobao'));
  static const VerificationMeta _productIdMeta =
      const VerificationMeta('productId');
  @override
  late final GeneratedColumn<String> productId = GeneratedColumn<String>(
      'product_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _productTitleMeta =
      const VerificationMeta('productTitle');
  @override
  late final GeneratedColumn<String> productTitle = GeneratedColumn<String>(
      'product_title', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _productUrlMeta =
      const VerificationMeta('productUrl');
  @override
  late final GeneratedColumn<String> productUrl = GeneratedColumn<String>(
      'product_url', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _priceCnyMeta =
      const VerificationMeta('priceCny');
  @override
  late final GeneratedColumn<double> priceCny = GeneratedColumn<double>(
      'price_cny', aliasedName, true,
      type: DriftSqlType.double, requiredDuringInsert: false);
  static const VerificationMeta _cashierUrlMeta =
      const VerificationMeta('cashierUrl');
  @override
  late final GeneratedColumn<String> cashierUrl = GeneratedColumn<String>(
      'cashier_url', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _failureReasonMeta =
      const VerificationMeta('failureReason');
  @override
  late final GeneratedColumn<String> failureReason = GeneratedColumn<String>(
      'failure_reason', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _linkedLedgerIdMeta =
      const VerificationMeta('linkedLedgerId');
  @override
  late final GeneratedColumn<String> linkedLedgerId = GeneratedColumn<String>(
      'linked_ledger_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
      'created_at', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        characterId,
        paymentMode,
        status,
        userInstruction,
        productPlatform,
        productId,
        productTitle,
        productUrl,
        priceCny,
        cashierUrl,
        failureReason,
        linkedLedgerId,
        createdAt,
        updatedAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'ai_purchase_log';
  @override
  VerificationContext validateIntegrity(Insertable<AiPurchaseLogData> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('character_id')) {
      context.handle(
          _characterIdMeta,
          characterId.isAcceptableOrUnknown(
              data['character_id']!, _characterIdMeta));
    } else if (isInserting) {
      context.missing(_characterIdMeta);
    }
    if (data.containsKey('payment_mode')) {
      context.handle(
          _paymentModeMeta,
          paymentMode.isAcceptableOrUnknown(
              data['payment_mode']!, _paymentModeMeta));
    } else if (isInserting) {
      context.missing(_paymentModeMeta);
    }
    if (data.containsKey('status')) {
      context.handle(_statusMeta,
          status.isAcceptableOrUnknown(data['status']!, _statusMeta));
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
    if (data.containsKey('user_instruction')) {
      context.handle(
          _userInstructionMeta,
          userInstruction.isAcceptableOrUnknown(
              data['user_instruction']!, _userInstructionMeta));
    } else if (isInserting) {
      context.missing(_userInstructionMeta);
    }
    if (data.containsKey('product_platform')) {
      context.handle(
          _productPlatformMeta,
          productPlatform.isAcceptableOrUnknown(
              data['product_platform']!, _productPlatformMeta));
    }
    if (data.containsKey('product_id')) {
      context.handle(_productIdMeta,
          productId.isAcceptableOrUnknown(data['product_id']!, _productIdMeta));
    }
    if (data.containsKey('product_title')) {
      context.handle(
          _productTitleMeta,
          productTitle.isAcceptableOrUnknown(
              data['product_title']!, _productTitleMeta));
    }
    if (data.containsKey('product_url')) {
      context.handle(
          _productUrlMeta,
          productUrl.isAcceptableOrUnknown(
              data['product_url']!, _productUrlMeta));
    }
    if (data.containsKey('price_cny')) {
      context.handle(_priceCnyMeta,
          priceCny.isAcceptableOrUnknown(data['price_cny']!, _priceCnyMeta));
    }
    if (data.containsKey('cashier_url')) {
      context.handle(
          _cashierUrlMeta,
          cashierUrl.isAcceptableOrUnknown(
              data['cashier_url']!, _cashierUrlMeta));
    }
    if (data.containsKey('failure_reason')) {
      context.handle(
          _failureReasonMeta,
          failureReason.isAcceptableOrUnknown(
              data['failure_reason']!, _failureReasonMeta));
    }
    if (data.containsKey('linked_ledger_id')) {
      context.handle(
          _linkedLedgerIdMeta,
          linkedLedgerId.isAcceptableOrUnknown(
              data['linked_ledger_id']!, _linkedLedgerIdMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  AiPurchaseLogData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AiPurchaseLogData(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      characterId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}character_id'])!,
      paymentMode: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}payment_mode'])!,
      status: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}status'])!,
      userInstruction: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}user_instruction'])!,
      productPlatform: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}product_platform'])!,
      productId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}product_id']),
      productTitle: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}product_title']),
      productUrl: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}product_url']),
      priceCny: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}price_cny']),
      cashierUrl: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}cashier_url']),
      failureReason: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}failure_reason']),
      linkedLedgerId: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}linked_ledger_id']),
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}created_at'])!,
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}updated_at'])!,
    );
  }

  @override
  $AiPurchaseLogTable createAlias(String alias) {
    return $AiPurchaseLogTable(attachedDatabase, alias);
  }
}

class AiPurchaseLogData extends DataClass
    implements Insertable<AiPurchaseLogData> {
  final String id;
  final String characterId;

  /// 'manual_approval' | 'auto_silent' (future)
  final String paymentMode;

  /// 'searching' | 'selected' | 'ordering' | 'payment_pushed' | 'completed' | 'failed' | 'aborted'
  final String status;

  /// The user's original purchase instruction verbatim.
  final String userInstruction;
  final String productPlatform;
  final String? productId;
  final String? productTitle;
  final String? productUrl;

  /// Estimated or confirmed price in CNY.
  final double? priceCny;

  /// Alipay cashier URL (cashier*.alipay.com or *excashier*.alipay.com).
  final String? cashierUrl;

  /// Reason for failure or abort (budget exceeded, whitelist violation, etc.).
  final String? failureReason;

  /// Soft link to AiFinanceLedger id — reserved for future finance integration.
  final String? linkedLedgerId;
  final int createdAt;
  final int updatedAt;
  const AiPurchaseLogData(
      {required this.id,
      required this.characterId,
      required this.paymentMode,
      required this.status,
      required this.userInstruction,
      required this.productPlatform,
      this.productId,
      this.productTitle,
      this.productUrl,
      this.priceCny,
      this.cashierUrl,
      this.failureReason,
      this.linkedLedgerId,
      required this.createdAt,
      required this.updatedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['character_id'] = Variable<String>(characterId);
    map['payment_mode'] = Variable<String>(paymentMode);
    map['status'] = Variable<String>(status);
    map['user_instruction'] = Variable<String>(userInstruction);
    map['product_platform'] = Variable<String>(productPlatform);
    if (!nullToAbsent || productId != null) {
      map['product_id'] = Variable<String>(productId);
    }
    if (!nullToAbsent || productTitle != null) {
      map['product_title'] = Variable<String>(productTitle);
    }
    if (!nullToAbsent || productUrl != null) {
      map['product_url'] = Variable<String>(productUrl);
    }
    if (!nullToAbsent || priceCny != null) {
      map['price_cny'] = Variable<double>(priceCny);
    }
    if (!nullToAbsent || cashierUrl != null) {
      map['cashier_url'] = Variable<String>(cashierUrl);
    }
    if (!nullToAbsent || failureReason != null) {
      map['failure_reason'] = Variable<String>(failureReason);
    }
    if (!nullToAbsent || linkedLedgerId != null) {
      map['linked_ledger_id'] = Variable<String>(linkedLedgerId);
    }
    map['created_at'] = Variable<int>(createdAt);
    map['updated_at'] = Variable<int>(updatedAt);
    return map;
  }

  AiPurchaseLogCompanion toCompanion(bool nullToAbsent) {
    return AiPurchaseLogCompanion(
      id: Value(id),
      characterId: Value(characterId),
      paymentMode: Value(paymentMode),
      status: Value(status),
      userInstruction: Value(userInstruction),
      productPlatform: Value(productPlatform),
      productId: productId == null && nullToAbsent
          ? const Value.absent()
          : Value(productId),
      productTitle: productTitle == null && nullToAbsent
          ? const Value.absent()
          : Value(productTitle),
      productUrl: productUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(productUrl),
      priceCny: priceCny == null && nullToAbsent
          ? const Value.absent()
          : Value(priceCny),
      cashierUrl: cashierUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(cashierUrl),
      failureReason: failureReason == null && nullToAbsent
          ? const Value.absent()
          : Value(failureReason),
      linkedLedgerId: linkedLedgerId == null && nullToAbsent
          ? const Value.absent()
          : Value(linkedLedgerId),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory AiPurchaseLogData.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AiPurchaseLogData(
      id: serializer.fromJson<String>(json['id']),
      characterId: serializer.fromJson<String>(json['characterId']),
      paymentMode: serializer.fromJson<String>(json['paymentMode']),
      status: serializer.fromJson<String>(json['status']),
      userInstruction: serializer.fromJson<String>(json['userInstruction']),
      productPlatform: serializer.fromJson<String>(json['productPlatform']),
      productId: serializer.fromJson<String?>(json['productId']),
      productTitle: serializer.fromJson<String?>(json['productTitle']),
      productUrl: serializer.fromJson<String?>(json['productUrl']),
      priceCny: serializer.fromJson<double?>(json['priceCny']),
      cashierUrl: serializer.fromJson<String?>(json['cashierUrl']),
      failureReason: serializer.fromJson<String?>(json['failureReason']),
      linkedLedgerId: serializer.fromJson<String?>(json['linkedLedgerId']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'characterId': serializer.toJson<String>(characterId),
      'paymentMode': serializer.toJson<String>(paymentMode),
      'status': serializer.toJson<String>(status),
      'userInstruction': serializer.toJson<String>(userInstruction),
      'productPlatform': serializer.toJson<String>(productPlatform),
      'productId': serializer.toJson<String?>(productId),
      'productTitle': serializer.toJson<String?>(productTitle),
      'productUrl': serializer.toJson<String?>(productUrl),
      'priceCny': serializer.toJson<double?>(priceCny),
      'cashierUrl': serializer.toJson<String?>(cashierUrl),
      'failureReason': serializer.toJson<String?>(failureReason),
      'linkedLedgerId': serializer.toJson<String?>(linkedLedgerId),
      'createdAt': serializer.toJson<int>(createdAt),
      'updatedAt': serializer.toJson<int>(updatedAt),
    };
  }

  AiPurchaseLogData copyWith(
          {String? id,
          String? characterId,
          String? paymentMode,
          String? status,
          String? userInstruction,
          String? productPlatform,
          Value<String?> productId = const Value.absent(),
          Value<String?> productTitle = const Value.absent(),
          Value<String?> productUrl = const Value.absent(),
          Value<double?> priceCny = const Value.absent(),
          Value<String?> cashierUrl = const Value.absent(),
          Value<String?> failureReason = const Value.absent(),
          Value<String?> linkedLedgerId = const Value.absent(),
          int? createdAt,
          int? updatedAt}) =>
      AiPurchaseLogData(
        id: id ?? this.id,
        characterId: characterId ?? this.characterId,
        paymentMode: paymentMode ?? this.paymentMode,
        status: status ?? this.status,
        userInstruction: userInstruction ?? this.userInstruction,
        productPlatform: productPlatform ?? this.productPlatform,
        productId: productId.present ? productId.value : this.productId,
        productTitle:
            productTitle.present ? productTitle.value : this.productTitle,
        productUrl: productUrl.present ? productUrl.value : this.productUrl,
        priceCny: priceCny.present ? priceCny.value : this.priceCny,
        cashierUrl: cashierUrl.present ? cashierUrl.value : this.cashierUrl,
        failureReason:
            failureReason.present ? failureReason.value : this.failureReason,
        linkedLedgerId:
            linkedLedgerId.present ? linkedLedgerId.value : this.linkedLedgerId,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
  AiPurchaseLogData copyWithCompanion(AiPurchaseLogCompanion data) {
    return AiPurchaseLogData(
      id: data.id.present ? data.id.value : this.id,
      characterId:
          data.characterId.present ? data.characterId.value : this.characterId,
      paymentMode:
          data.paymentMode.present ? data.paymentMode.value : this.paymentMode,
      status: data.status.present ? data.status.value : this.status,
      userInstruction: data.userInstruction.present
          ? data.userInstruction.value
          : this.userInstruction,
      productPlatform: data.productPlatform.present
          ? data.productPlatform.value
          : this.productPlatform,
      productId: data.productId.present ? data.productId.value : this.productId,
      productTitle: data.productTitle.present
          ? data.productTitle.value
          : this.productTitle,
      productUrl:
          data.productUrl.present ? data.productUrl.value : this.productUrl,
      priceCny: data.priceCny.present ? data.priceCny.value : this.priceCny,
      cashierUrl:
          data.cashierUrl.present ? data.cashierUrl.value : this.cashierUrl,
      failureReason: data.failureReason.present
          ? data.failureReason.value
          : this.failureReason,
      linkedLedgerId: data.linkedLedgerId.present
          ? data.linkedLedgerId.value
          : this.linkedLedgerId,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AiPurchaseLogData(')
          ..write('id: $id, ')
          ..write('characterId: $characterId, ')
          ..write('paymentMode: $paymentMode, ')
          ..write('status: $status, ')
          ..write('userInstruction: $userInstruction, ')
          ..write('productPlatform: $productPlatform, ')
          ..write('productId: $productId, ')
          ..write('productTitle: $productTitle, ')
          ..write('productUrl: $productUrl, ')
          ..write('priceCny: $priceCny, ')
          ..write('cashierUrl: $cashierUrl, ')
          ..write('failureReason: $failureReason, ')
          ..write('linkedLedgerId: $linkedLedgerId, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id,
      characterId,
      paymentMode,
      status,
      userInstruction,
      productPlatform,
      productId,
      productTitle,
      productUrl,
      priceCny,
      cashierUrl,
      failureReason,
      linkedLedgerId,
      createdAt,
      updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AiPurchaseLogData &&
          other.id == this.id &&
          other.characterId == this.characterId &&
          other.paymentMode == this.paymentMode &&
          other.status == this.status &&
          other.userInstruction == this.userInstruction &&
          other.productPlatform == this.productPlatform &&
          other.productId == this.productId &&
          other.productTitle == this.productTitle &&
          other.productUrl == this.productUrl &&
          other.priceCny == this.priceCny &&
          other.cashierUrl == this.cashierUrl &&
          other.failureReason == this.failureReason &&
          other.linkedLedgerId == this.linkedLedgerId &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class AiPurchaseLogCompanion extends UpdateCompanion<AiPurchaseLogData> {
  final Value<String> id;
  final Value<String> characterId;
  final Value<String> paymentMode;
  final Value<String> status;
  final Value<String> userInstruction;
  final Value<String> productPlatform;
  final Value<String?> productId;
  final Value<String?> productTitle;
  final Value<String?> productUrl;
  final Value<double?> priceCny;
  final Value<String?> cashierUrl;
  final Value<String?> failureReason;
  final Value<String?> linkedLedgerId;
  final Value<int> createdAt;
  final Value<int> updatedAt;
  final Value<int> rowid;
  const AiPurchaseLogCompanion({
    this.id = const Value.absent(),
    this.characterId = const Value.absent(),
    this.paymentMode = const Value.absent(),
    this.status = const Value.absent(),
    this.userInstruction = const Value.absent(),
    this.productPlatform = const Value.absent(),
    this.productId = const Value.absent(),
    this.productTitle = const Value.absent(),
    this.productUrl = const Value.absent(),
    this.priceCny = const Value.absent(),
    this.cashierUrl = const Value.absent(),
    this.failureReason = const Value.absent(),
    this.linkedLedgerId = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AiPurchaseLogCompanion.insert({
    required String id,
    required String characterId,
    required String paymentMode,
    required String status,
    required String userInstruction,
    this.productPlatform = const Value.absent(),
    this.productId = const Value.absent(),
    this.productTitle = const Value.absent(),
    this.productUrl = const Value.absent(),
    this.priceCny = const Value.absent(),
    this.cashierUrl = const Value.absent(),
    this.failureReason = const Value.absent(),
    this.linkedLedgerId = const Value.absent(),
    required int createdAt,
    required int updatedAt,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        characterId = Value(characterId),
        paymentMode = Value(paymentMode),
        status = Value(status),
        userInstruction = Value(userInstruction),
        createdAt = Value(createdAt),
        updatedAt = Value(updatedAt);
  static Insertable<AiPurchaseLogData> custom({
    Expression<String>? id,
    Expression<String>? characterId,
    Expression<String>? paymentMode,
    Expression<String>? status,
    Expression<String>? userInstruction,
    Expression<String>? productPlatform,
    Expression<String>? productId,
    Expression<String>? productTitle,
    Expression<String>? productUrl,
    Expression<double>? priceCny,
    Expression<String>? cashierUrl,
    Expression<String>? failureReason,
    Expression<String>? linkedLedgerId,
    Expression<int>? createdAt,
    Expression<int>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (characterId != null) 'character_id': characterId,
      if (paymentMode != null) 'payment_mode': paymentMode,
      if (status != null) 'status': status,
      if (userInstruction != null) 'user_instruction': userInstruction,
      if (productPlatform != null) 'product_platform': productPlatform,
      if (productId != null) 'product_id': productId,
      if (productTitle != null) 'product_title': productTitle,
      if (productUrl != null) 'product_url': productUrl,
      if (priceCny != null) 'price_cny': priceCny,
      if (cashierUrl != null) 'cashier_url': cashierUrl,
      if (failureReason != null) 'failure_reason': failureReason,
      if (linkedLedgerId != null) 'linked_ledger_id': linkedLedgerId,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AiPurchaseLogCompanion copyWith(
      {Value<String>? id,
      Value<String>? characterId,
      Value<String>? paymentMode,
      Value<String>? status,
      Value<String>? userInstruction,
      Value<String>? productPlatform,
      Value<String?>? productId,
      Value<String?>? productTitle,
      Value<String?>? productUrl,
      Value<double?>? priceCny,
      Value<String?>? cashierUrl,
      Value<String?>? failureReason,
      Value<String?>? linkedLedgerId,
      Value<int>? createdAt,
      Value<int>? updatedAt,
      Value<int>? rowid}) {
    return AiPurchaseLogCompanion(
      id: id ?? this.id,
      characterId: characterId ?? this.characterId,
      paymentMode: paymentMode ?? this.paymentMode,
      status: status ?? this.status,
      userInstruction: userInstruction ?? this.userInstruction,
      productPlatform: productPlatform ?? this.productPlatform,
      productId: productId ?? this.productId,
      productTitle: productTitle ?? this.productTitle,
      productUrl: productUrl ?? this.productUrl,
      priceCny: priceCny ?? this.priceCny,
      cashierUrl: cashierUrl ?? this.cashierUrl,
      failureReason: failureReason ?? this.failureReason,
      linkedLedgerId: linkedLedgerId ?? this.linkedLedgerId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (characterId.present) {
      map['character_id'] = Variable<String>(characterId.value);
    }
    if (paymentMode.present) {
      map['payment_mode'] = Variable<String>(paymentMode.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (userInstruction.present) {
      map['user_instruction'] = Variable<String>(userInstruction.value);
    }
    if (productPlatform.present) {
      map['product_platform'] = Variable<String>(productPlatform.value);
    }
    if (productId.present) {
      map['product_id'] = Variable<String>(productId.value);
    }
    if (productTitle.present) {
      map['product_title'] = Variable<String>(productTitle.value);
    }
    if (productUrl.present) {
      map['product_url'] = Variable<String>(productUrl.value);
    }
    if (priceCny.present) {
      map['price_cny'] = Variable<double>(priceCny.value);
    }
    if (cashierUrl.present) {
      map['cashier_url'] = Variable<String>(cashierUrl.value);
    }
    if (failureReason.present) {
      map['failure_reason'] = Variable<String>(failureReason.value);
    }
    if (linkedLedgerId.present) {
      map['linked_ledger_id'] = Variable<String>(linkedLedgerId.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AiPurchaseLogCompanion(')
          ..write('id: $id, ')
          ..write('characterId: $characterId, ')
          ..write('paymentMode: $paymentMode, ')
          ..write('status: $status, ')
          ..write('userInstruction: $userInstruction, ')
          ..write('productPlatform: $productPlatform, ')
          ..write('productId: $productId, ')
          ..write('productTitle: $productTitle, ')
          ..write('productUrl: $productUrl, ')
          ..write('priceCny: $priceCny, ')
          ..write('cashierUrl: $cashierUrl, ')
          ..write('failureReason: $failureReason, ')
          ..write('linkedLedgerId: $linkedLedgerId, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $VoiceCallSessionsTable extends VoiceCallSessions
    with TableInfo<$VoiceCallSessionsTable, VoiceCallSession> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $VoiceCallSessionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _characterIdMeta =
      const VerificationMeta('characterId');
  @override
  late final GeneratedColumn<String> characterId = GeneratedColumn<String>(
      'character_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
      'user_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _startedAtMeta =
      const VerificationMeta('startedAt');
  @override
  late final GeneratedColumn<int> startedAt = GeneratedColumn<int>(
      'started_at', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _endedAtMeta =
      const VerificationMeta('endedAt');
  @override
  late final GeneratedColumn<int> endedAt = GeneratedColumn<int>(
      'ended_at', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _summaryMeta =
      const VerificationMeta('summary');
  @override
  late final GeneratedColumn<String> summary = GeneratedColumn<String>(
      'summary', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns =>
      [id, characterId, userId, startedAt, endedAt, summary];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'voice_call_sessions';
  @override
  VerificationContext validateIntegrity(Insertable<VoiceCallSession> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('character_id')) {
      context.handle(
          _characterIdMeta,
          characterId.isAcceptableOrUnknown(
              data['character_id']!, _characterIdMeta));
    } else if (isInserting) {
      context.missing(_characterIdMeta);
    }
    if (data.containsKey('user_id')) {
      context.handle(_userIdMeta,
          userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta));
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('started_at')) {
      context.handle(_startedAtMeta,
          startedAt.isAcceptableOrUnknown(data['started_at']!, _startedAtMeta));
    } else if (isInserting) {
      context.missing(_startedAtMeta);
    }
    if (data.containsKey('ended_at')) {
      context.handle(_endedAtMeta,
          endedAt.isAcceptableOrUnknown(data['ended_at']!, _endedAtMeta));
    }
    if (data.containsKey('summary')) {
      context.handle(_summaryMeta,
          summary.isAcceptableOrUnknown(data['summary']!, _summaryMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  VoiceCallSession map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return VoiceCallSession(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      characterId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}character_id'])!,
      userId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}user_id'])!,
      startedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}started_at'])!,
      endedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}ended_at']),
      summary: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}summary']),
    );
  }

  @override
  $VoiceCallSessionsTable createAlias(String alias) {
    return $VoiceCallSessionsTable(attachedDatabase, alias);
  }
}

class VoiceCallSession extends DataClass
    implements Insertable<VoiceCallSession> {
  final String id;
  final String characterId;
  final String userId;
  final int startedAt;
  final int? endedAt;

  /// Key-facts summary written by post-call LLM pass (B plan).
  final String? summary;
  const VoiceCallSession(
      {required this.id,
      required this.characterId,
      required this.userId,
      required this.startedAt,
      this.endedAt,
      this.summary});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['character_id'] = Variable<String>(characterId);
    map['user_id'] = Variable<String>(userId);
    map['started_at'] = Variable<int>(startedAt);
    if (!nullToAbsent || endedAt != null) {
      map['ended_at'] = Variable<int>(endedAt);
    }
    if (!nullToAbsent || summary != null) {
      map['summary'] = Variable<String>(summary);
    }
    return map;
  }

  VoiceCallSessionsCompanion toCompanion(bool nullToAbsent) {
    return VoiceCallSessionsCompanion(
      id: Value(id),
      characterId: Value(characterId),
      userId: Value(userId),
      startedAt: Value(startedAt),
      endedAt: endedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(endedAt),
      summary: summary == null && nullToAbsent
          ? const Value.absent()
          : Value(summary),
    );
  }

  factory VoiceCallSession.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return VoiceCallSession(
      id: serializer.fromJson<String>(json['id']),
      characterId: serializer.fromJson<String>(json['characterId']),
      userId: serializer.fromJson<String>(json['userId']),
      startedAt: serializer.fromJson<int>(json['startedAt']),
      endedAt: serializer.fromJson<int?>(json['endedAt']),
      summary: serializer.fromJson<String?>(json['summary']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'characterId': serializer.toJson<String>(characterId),
      'userId': serializer.toJson<String>(userId),
      'startedAt': serializer.toJson<int>(startedAt),
      'endedAt': serializer.toJson<int?>(endedAt),
      'summary': serializer.toJson<String?>(summary),
    };
  }

  VoiceCallSession copyWith(
          {String? id,
          String? characterId,
          String? userId,
          int? startedAt,
          Value<int?> endedAt = const Value.absent(),
          Value<String?> summary = const Value.absent()}) =>
      VoiceCallSession(
        id: id ?? this.id,
        characterId: characterId ?? this.characterId,
        userId: userId ?? this.userId,
        startedAt: startedAt ?? this.startedAt,
        endedAt: endedAt.present ? endedAt.value : this.endedAt,
        summary: summary.present ? summary.value : this.summary,
      );
  VoiceCallSession copyWithCompanion(VoiceCallSessionsCompanion data) {
    return VoiceCallSession(
      id: data.id.present ? data.id.value : this.id,
      characterId:
          data.characterId.present ? data.characterId.value : this.characterId,
      userId: data.userId.present ? data.userId.value : this.userId,
      startedAt: data.startedAt.present ? data.startedAt.value : this.startedAt,
      endedAt: data.endedAt.present ? data.endedAt.value : this.endedAt,
      summary: data.summary.present ? data.summary.value : this.summary,
    );
  }

  @override
  String toString() {
    return (StringBuffer('VoiceCallSession(')
          ..write('id: $id, ')
          ..write('characterId: $characterId, ')
          ..write('userId: $userId, ')
          ..write('startedAt: $startedAt, ')
          ..write('endedAt: $endedAt, ')
          ..write('summary: $summary')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, characterId, userId, startedAt, endedAt, summary);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is VoiceCallSession &&
          other.id == this.id &&
          other.characterId == this.characterId &&
          other.userId == this.userId &&
          other.startedAt == this.startedAt &&
          other.endedAt == this.endedAt &&
          other.summary == this.summary);
}

class VoiceCallSessionsCompanion extends UpdateCompanion<VoiceCallSession> {
  final Value<String> id;
  final Value<String> characterId;
  final Value<String> userId;
  final Value<int> startedAt;
  final Value<int?> endedAt;
  final Value<String?> summary;
  final Value<int> rowid;
  const VoiceCallSessionsCompanion({
    this.id = const Value.absent(),
    this.characterId = const Value.absent(),
    this.userId = const Value.absent(),
    this.startedAt = const Value.absent(),
    this.endedAt = const Value.absent(),
    this.summary = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  VoiceCallSessionsCompanion.insert({
    required String id,
    required String characterId,
    required String userId,
    required int startedAt,
    this.endedAt = const Value.absent(),
    this.summary = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        characterId = Value(characterId),
        userId = Value(userId),
        startedAt = Value(startedAt);
  static Insertable<VoiceCallSession> custom({
    Expression<String>? id,
    Expression<String>? characterId,
    Expression<String>? userId,
    Expression<int>? startedAt,
    Expression<int>? endedAt,
    Expression<String>? summary,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (characterId != null) 'character_id': characterId,
      if (userId != null) 'user_id': userId,
      if (startedAt != null) 'started_at': startedAt,
      if (endedAt != null) 'ended_at': endedAt,
      if (summary != null) 'summary': summary,
      if (rowid != null) 'rowid': rowid,
    });
  }

  VoiceCallSessionsCompanion copyWith(
      {Value<String>? id,
      Value<String>? characterId,
      Value<String>? userId,
      Value<int>? startedAt,
      Value<int?>? endedAt,
      Value<String?>? summary,
      Value<int>? rowid}) {
    return VoiceCallSessionsCompanion(
      id: id ?? this.id,
      characterId: characterId ?? this.characterId,
      userId: userId ?? this.userId,
      startedAt: startedAt ?? this.startedAt,
      endedAt: endedAt ?? this.endedAt,
      summary: summary ?? this.summary,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (characterId.present) {
      map['character_id'] = Variable<String>(characterId.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (startedAt.present) {
      map['started_at'] = Variable<int>(startedAt.value);
    }
    if (endedAt.present) {
      map['ended_at'] = Variable<int>(endedAt.value);
    }
    if (summary.present) {
      map['summary'] = Variable<String>(summary.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('VoiceCallSessionsCompanion(')
          ..write('id: $id, ')
          ..write('characterId: $characterId, ')
          ..write('userId: $userId, ')
          ..write('startedAt: $startedAt, ')
          ..write('endedAt: $endedAt, ')
          ..write('summary: $summary, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $VoiceCallMessagesTable extends VoiceCallMessages
    with TableInfo<$VoiceCallMessagesTable, VoiceCallMessage> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $VoiceCallMessagesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _sessionIdMeta =
      const VerificationMeta('sessionId');
  @override
  late final GeneratedColumn<String> sessionId = GeneratedColumn<String>(
      'session_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _roleMeta = const VerificationMeta('role');
  @override
  late final GeneratedColumn<String> role = GeneratedColumn<String>(
      'role', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _contentMeta =
      const VerificationMeta('content');
  @override
  late final GeneratedColumn<String> content = GeneratedColumn<String>(
      'content', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
      'created_at', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns =>
      [id, sessionId, role, content, createdAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'voice_call_messages';
  @override
  VerificationContext validateIntegrity(Insertable<VoiceCallMessage> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('session_id')) {
      context.handle(_sessionIdMeta,
          sessionId.isAcceptableOrUnknown(data['session_id']!, _sessionIdMeta));
    } else if (isInserting) {
      context.missing(_sessionIdMeta);
    }
    if (data.containsKey('role')) {
      context.handle(
          _roleMeta, role.isAcceptableOrUnknown(data['role']!, _roleMeta));
    } else if (isInserting) {
      context.missing(_roleMeta);
    }
    if (data.containsKey('content')) {
      context.handle(_contentMeta,
          content.isAcceptableOrUnknown(data['content']!, _contentMeta));
    } else if (isInserting) {
      context.missing(_contentMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  VoiceCallMessage map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return VoiceCallMessage(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      sessionId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}session_id'])!,
      role: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}role'])!,
      content: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}content'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}created_at'])!,
    );
  }

  @override
  $VoiceCallMessagesTable createAlias(String alias) {
    return $VoiceCallMessagesTable(attachedDatabase, alias);
  }
}

class VoiceCallMessage extends DataClass
    implements Insertable<VoiceCallMessage> {
  final int id;
  final String sessionId;

  /// 'user' or 'companion'
  final String role;
  final String content;
  final int createdAt;
  const VoiceCallMessage(
      {required this.id,
      required this.sessionId,
      required this.role,
      required this.content,
      required this.createdAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['session_id'] = Variable<String>(sessionId);
    map['role'] = Variable<String>(role);
    map['content'] = Variable<String>(content);
    map['created_at'] = Variable<int>(createdAt);
    return map;
  }

  VoiceCallMessagesCompanion toCompanion(bool nullToAbsent) {
    return VoiceCallMessagesCompanion(
      id: Value(id),
      sessionId: Value(sessionId),
      role: Value(role),
      content: Value(content),
      createdAt: Value(createdAt),
    );
  }

  factory VoiceCallMessage.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return VoiceCallMessage(
      id: serializer.fromJson<int>(json['id']),
      sessionId: serializer.fromJson<String>(json['sessionId']),
      role: serializer.fromJson<String>(json['role']),
      content: serializer.fromJson<String>(json['content']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'sessionId': serializer.toJson<String>(sessionId),
      'role': serializer.toJson<String>(role),
      'content': serializer.toJson<String>(content),
      'createdAt': serializer.toJson<int>(createdAt),
    };
  }

  VoiceCallMessage copyWith(
          {int? id,
          String? sessionId,
          String? role,
          String? content,
          int? createdAt}) =>
      VoiceCallMessage(
        id: id ?? this.id,
        sessionId: sessionId ?? this.sessionId,
        role: role ?? this.role,
        content: content ?? this.content,
        createdAt: createdAt ?? this.createdAt,
      );
  VoiceCallMessage copyWithCompanion(VoiceCallMessagesCompanion data) {
    return VoiceCallMessage(
      id: data.id.present ? data.id.value : this.id,
      sessionId: data.sessionId.present ? data.sessionId.value : this.sessionId,
      role: data.role.present ? data.role.value : this.role,
      content: data.content.present ? data.content.value : this.content,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('VoiceCallMessage(')
          ..write('id: $id, ')
          ..write('sessionId: $sessionId, ')
          ..write('role: $role, ')
          ..write('content: $content, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, sessionId, role, content, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is VoiceCallMessage &&
          other.id == this.id &&
          other.sessionId == this.sessionId &&
          other.role == this.role &&
          other.content == this.content &&
          other.createdAt == this.createdAt);
}

class VoiceCallMessagesCompanion extends UpdateCompanion<VoiceCallMessage> {
  final Value<int> id;
  final Value<String> sessionId;
  final Value<String> role;
  final Value<String> content;
  final Value<int> createdAt;
  const VoiceCallMessagesCompanion({
    this.id = const Value.absent(),
    this.sessionId = const Value.absent(),
    this.role = const Value.absent(),
    this.content = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  VoiceCallMessagesCompanion.insert({
    this.id = const Value.absent(),
    required String sessionId,
    required String role,
    required String content,
    required int createdAt,
  })  : sessionId = Value(sessionId),
        role = Value(role),
        content = Value(content),
        createdAt = Value(createdAt);
  static Insertable<VoiceCallMessage> custom({
    Expression<int>? id,
    Expression<String>? sessionId,
    Expression<String>? role,
    Expression<String>? content,
    Expression<int>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (sessionId != null) 'session_id': sessionId,
      if (role != null) 'role': role,
      if (content != null) 'content': content,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  VoiceCallMessagesCompanion copyWith(
      {Value<int>? id,
      Value<String>? sessionId,
      Value<String>? role,
      Value<String>? content,
      Value<int>? createdAt}) {
    return VoiceCallMessagesCompanion(
      id: id ?? this.id,
      sessionId: sessionId ?? this.sessionId,
      role: role ?? this.role,
      content: content ?? this.content,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (sessionId.present) {
      map['session_id'] = Variable<String>(sessionId.value);
    }
    if (role.present) {
      map['role'] = Variable<String>(role.value);
    }
    if (content.present) {
      map['content'] = Variable<String>(content.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('VoiceCallMessagesCompanion(')
          ..write('id: $id, ')
          ..write('sessionId: $sessionId, ')
          ..write('role: $role, ')
          ..write('content: $content, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $TasksTable tasks = $TasksTable(this);
  late final $KvStoreTable kvStore = $KvStoreTable(this);
  late final $AgentActivityMessagesTable agentActivityMessages =
      $AgentActivityMessagesTable(this);
  late final $CardCacheTable cardCache = $CardCacheTable(this);
  late final $SystemActionsTable systemActions = $SystemActionsTable(this);
  late final $ClarificationRequestsTable clarificationRequests =
      $ClarificationRequestsTable(this);
  late final $PersonaChatMessagesTable personaChatMessages =
      $PersonaChatMessagesTable(this);
  late final $ConversationCaptureCursorsTable conversationCaptureCursors =
      $ConversationCaptureCursorsTable(this);
  late final $SharedLifeEventOperationsTable sharedLifeEventOperations =
      $SharedLifeEventOperationsTable(this);
  late final $SharedLifeEntitiesTable sharedLifeEntities =
      $SharedLifeEntitiesTable(this);
  late final $UserNotificationsTable userNotifications =
      $UserNotificationsTable(this);
  late final $SystemMessageQueueTable systemMessageQueue =
      $SystemMessageQueueTable(this);
  late final $AiFinanceLedgerTable aiFinanceLedger =
      $AiFinanceLedgerTable(this);
  late final $AiPurchaseLogTable aiPurchaseLog = $AiPurchaseLogTable(this);
  late final $VoiceCallSessionsTable voiceCallSessions =
      $VoiceCallSessionsTable(this);
  late final $VoiceCallMessagesTable voiceCallMessages =
      $VoiceCallMessagesTable(this);
  late final CardDao cardDao = CardDao(this as AppDatabase);
  late final AiFinanceDao aiFinanceDao = AiFinanceDao(this as AppDatabase);
  late final AiPurchaseDao aiPurchaseDao = AiPurchaseDao(this as AppDatabase);
  late final VoiceCallDao voiceCallDao = VoiceCallDao(this as AppDatabase);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
        tasks,
        kvStore,
        agentActivityMessages,
        cardCache,
        systemActions,
        clarificationRequests,
        personaChatMessages,
        conversationCaptureCursors,
        sharedLifeEventOperations,
        sharedLifeEntities,
        userNotifications,
        systemMessageQueue,
        aiFinanceLedger,
        aiPurchaseLog,
        voiceCallSessions,
        voiceCallMessages
      ];
}

typedef $$TasksTableCreateCompanionBuilder = TasksCompanion Function({
  required String id,
  required String type,
  Value<String?> payload,
  required String status,
  Value<int> priority,
  Value<int?> createdAt,
  Value<int?> scheduledAt,
  Value<int?> completedAt,
  Value<int?> updatedAt,
  Value<int> retryCount,
  Value<int> maxRetries,
  Value<String?> error,
  Value<String?> result,
  Value<String?> bizId,
  Value<String?> dependencies,
  Value<int> rowid,
});
typedef $$TasksTableUpdateCompanionBuilder = TasksCompanion Function({
  Value<String> id,
  Value<String> type,
  Value<String?> payload,
  Value<String> status,
  Value<int> priority,
  Value<int?> createdAt,
  Value<int?> scheduledAt,
  Value<int?> completedAt,
  Value<int?> updatedAt,
  Value<int> retryCount,
  Value<int> maxRetries,
  Value<String?> error,
  Value<String?> result,
  Value<String?> bizId,
  Value<String?> dependencies,
  Value<int> rowid,
});

class $$TasksTableFilterComposer extends Composer<_$AppDatabase, $TasksTable> {
  $$TasksTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get type => $composableBuilder(
      column: $table.type, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get payload => $composableBuilder(
      column: $table.payload, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get status => $composableBuilder(
      column: $table.status, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get priority => $composableBuilder(
      column: $table.priority, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get scheduledAt => $composableBuilder(
      column: $table.scheduledAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get completedAt => $composableBuilder(
      column: $table.completedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get retryCount => $composableBuilder(
      column: $table.retryCount, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get maxRetries => $composableBuilder(
      column: $table.maxRetries, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get error => $composableBuilder(
      column: $table.error, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get result => $composableBuilder(
      column: $table.result, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get bizId => $composableBuilder(
      column: $table.bizId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get dependencies => $composableBuilder(
      column: $table.dependencies, builder: (column) => ColumnFilters(column));
}

class $$TasksTableOrderingComposer
    extends Composer<_$AppDatabase, $TasksTable> {
  $$TasksTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get type => $composableBuilder(
      column: $table.type, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get payload => $composableBuilder(
      column: $table.payload, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get status => $composableBuilder(
      column: $table.status, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get priority => $composableBuilder(
      column: $table.priority, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get scheduledAt => $composableBuilder(
      column: $table.scheduledAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get completedAt => $composableBuilder(
      column: $table.completedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get retryCount => $composableBuilder(
      column: $table.retryCount, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get maxRetries => $composableBuilder(
      column: $table.maxRetries, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get error => $composableBuilder(
      column: $table.error, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get result => $composableBuilder(
      column: $table.result, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get bizId => $composableBuilder(
      column: $table.bizId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get dependencies => $composableBuilder(
      column: $table.dependencies,
      builder: (column) => ColumnOrderings(column));
}

class $$TasksTableAnnotationComposer
    extends Composer<_$AppDatabase, $TasksTable> {
  $$TasksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<int> get priority =>
      $composableBuilder(column: $table.priority, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get scheduledAt => $composableBuilder(
      column: $table.scheduledAt, builder: (column) => column);

  GeneratedColumn<int> get completedAt => $composableBuilder(
      column: $table.completedAt, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<int> get retryCount => $composableBuilder(
      column: $table.retryCount, builder: (column) => column);

  GeneratedColumn<int> get maxRetries => $composableBuilder(
      column: $table.maxRetries, builder: (column) => column);

  GeneratedColumn<String> get error =>
      $composableBuilder(column: $table.error, builder: (column) => column);

  GeneratedColumn<String> get result =>
      $composableBuilder(column: $table.result, builder: (column) => column);

  GeneratedColumn<String> get bizId =>
      $composableBuilder(column: $table.bizId, builder: (column) => column);

  GeneratedColumn<String> get dependencies => $composableBuilder(
      column: $table.dependencies, builder: (column) => column);
}

class $$TasksTableTableManager extends RootTableManager<
    _$AppDatabase,
    $TasksTable,
    Task,
    $$TasksTableFilterComposer,
    $$TasksTableOrderingComposer,
    $$TasksTableAnnotationComposer,
    $$TasksTableCreateCompanionBuilder,
    $$TasksTableUpdateCompanionBuilder,
    (Task, BaseReferences<_$AppDatabase, $TasksTable, Task>),
    Task,
    PrefetchHooks Function()> {
  $$TasksTableTableManager(_$AppDatabase db, $TasksTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TasksTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TasksTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TasksTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> type = const Value.absent(),
            Value<String?> payload = const Value.absent(),
            Value<String> status = const Value.absent(),
            Value<int> priority = const Value.absent(),
            Value<int?> createdAt = const Value.absent(),
            Value<int?> scheduledAt = const Value.absent(),
            Value<int?> completedAt = const Value.absent(),
            Value<int?> updatedAt = const Value.absent(),
            Value<int> retryCount = const Value.absent(),
            Value<int> maxRetries = const Value.absent(),
            Value<String?> error = const Value.absent(),
            Value<String?> result = const Value.absent(),
            Value<String?> bizId = const Value.absent(),
            Value<String?> dependencies = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              TasksCompanion(
            id: id,
            type: type,
            payload: payload,
            status: status,
            priority: priority,
            createdAt: createdAt,
            scheduledAt: scheduledAt,
            completedAt: completedAt,
            updatedAt: updatedAt,
            retryCount: retryCount,
            maxRetries: maxRetries,
            error: error,
            result: result,
            bizId: bizId,
            dependencies: dependencies,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String type,
            Value<String?> payload = const Value.absent(),
            required String status,
            Value<int> priority = const Value.absent(),
            Value<int?> createdAt = const Value.absent(),
            Value<int?> scheduledAt = const Value.absent(),
            Value<int?> completedAt = const Value.absent(),
            Value<int?> updatedAt = const Value.absent(),
            Value<int> retryCount = const Value.absent(),
            Value<int> maxRetries = const Value.absent(),
            Value<String?> error = const Value.absent(),
            Value<String?> result = const Value.absent(),
            Value<String?> bizId = const Value.absent(),
            Value<String?> dependencies = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              TasksCompanion.insert(
            id: id,
            type: type,
            payload: payload,
            status: status,
            priority: priority,
            createdAt: createdAt,
            scheduledAt: scheduledAt,
            completedAt: completedAt,
            updatedAt: updatedAt,
            retryCount: retryCount,
            maxRetries: maxRetries,
            error: error,
            result: result,
            bizId: bizId,
            dependencies: dependencies,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$TasksTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $TasksTable,
    Task,
    $$TasksTableFilterComposer,
    $$TasksTableOrderingComposer,
    $$TasksTableAnnotationComposer,
    $$TasksTableCreateCompanionBuilder,
    $$TasksTableUpdateCompanionBuilder,
    (Task, BaseReferences<_$AppDatabase, $TasksTable, Task>),
    Task,
    PrefetchHooks Function()>;
typedef $$KvStoreTableCreateCompanionBuilder = KvStoreCompanion Function({
  required String key,
  Value<String?> value,
  Value<String?> bucket,
  Value<int?> updatedAt,
  Value<int> rowid,
});
typedef $$KvStoreTableUpdateCompanionBuilder = KvStoreCompanion Function({
  Value<String> key,
  Value<String?> value,
  Value<String?> bucket,
  Value<int?> updatedAt,
  Value<int> rowid,
});

class $$KvStoreTableFilterComposer
    extends Composer<_$AppDatabase, $KvStoreTable> {
  $$KvStoreTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
      column: $table.key, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get value => $composableBuilder(
      column: $table.value, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get bucket => $composableBuilder(
      column: $table.bucket, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));
}

class $$KvStoreTableOrderingComposer
    extends Composer<_$AppDatabase, $KvStoreTable> {
  $$KvStoreTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
      column: $table.key, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get value => $composableBuilder(
      column: $table.value, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get bucket => $composableBuilder(
      column: $table.bucket, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));
}

class $$KvStoreTableAnnotationComposer
    extends Composer<_$AppDatabase, $KvStoreTable> {
  $$KvStoreTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);

  GeneratedColumn<String> get bucket =>
      $composableBuilder(column: $table.bucket, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$KvStoreTableTableManager extends RootTableManager<
    _$AppDatabase,
    $KvStoreTable,
    KvStoreData,
    $$KvStoreTableFilterComposer,
    $$KvStoreTableOrderingComposer,
    $$KvStoreTableAnnotationComposer,
    $$KvStoreTableCreateCompanionBuilder,
    $$KvStoreTableUpdateCompanionBuilder,
    (KvStoreData, BaseReferences<_$AppDatabase, $KvStoreTable, KvStoreData>),
    KvStoreData,
    PrefetchHooks Function()> {
  $$KvStoreTableTableManager(_$AppDatabase db, $KvStoreTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$KvStoreTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$KvStoreTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$KvStoreTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> key = const Value.absent(),
            Value<String?> value = const Value.absent(),
            Value<String?> bucket = const Value.absent(),
            Value<int?> updatedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              KvStoreCompanion(
            key: key,
            value: value,
            bucket: bucket,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String key,
            Value<String?> value = const Value.absent(),
            Value<String?> bucket = const Value.absent(),
            Value<int?> updatedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              KvStoreCompanion.insert(
            key: key,
            value: value,
            bucket: bucket,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$KvStoreTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $KvStoreTable,
    KvStoreData,
    $$KvStoreTableFilterComposer,
    $$KvStoreTableOrderingComposer,
    $$KvStoreTableAnnotationComposer,
    $$KvStoreTableCreateCompanionBuilder,
    $$KvStoreTableUpdateCompanionBuilder,
    (KvStoreData, BaseReferences<_$AppDatabase, $KvStoreTable, KvStoreData>),
    KvStoreData,
    PrefetchHooks Function()>;
typedef $$AgentActivityMessagesTableCreateCompanionBuilder
    = AgentActivityMessagesCompanion Function({
  Value<int> id,
  required String type,
  required String title,
  Value<String?> content,
  Value<String?> icon,
  Value<String> agentName,
  Value<String?> agentId,
  Value<String?> scene,
  Value<String?> sceneId,
  Value<String?> userId,
  required DateTime timestamp,
});
typedef $$AgentActivityMessagesTableUpdateCompanionBuilder
    = AgentActivityMessagesCompanion Function({
  Value<int> id,
  Value<String> type,
  Value<String> title,
  Value<String?> content,
  Value<String?> icon,
  Value<String> agentName,
  Value<String?> agentId,
  Value<String?> scene,
  Value<String?> sceneId,
  Value<String?> userId,
  Value<DateTime> timestamp,
});

class $$AgentActivityMessagesTableFilterComposer
    extends Composer<_$AppDatabase, $AgentActivityMessagesTable> {
  $$AgentActivityMessagesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get type => $composableBuilder(
      column: $table.type, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get title => $composableBuilder(
      column: $table.title, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get content => $composableBuilder(
      column: $table.content, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get icon => $composableBuilder(
      column: $table.icon, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get agentName => $composableBuilder(
      column: $table.agentName, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get agentId => $composableBuilder(
      column: $table.agentId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get scene => $composableBuilder(
      column: $table.scene, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get sceneId => $composableBuilder(
      column: $table.sceneId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get userId => $composableBuilder(
      column: $table.userId, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get timestamp => $composableBuilder(
      column: $table.timestamp, builder: (column) => ColumnFilters(column));
}

class $$AgentActivityMessagesTableOrderingComposer
    extends Composer<_$AppDatabase, $AgentActivityMessagesTable> {
  $$AgentActivityMessagesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get type => $composableBuilder(
      column: $table.type, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get title => $composableBuilder(
      column: $table.title, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get content => $composableBuilder(
      column: $table.content, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get icon => $composableBuilder(
      column: $table.icon, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get agentName => $composableBuilder(
      column: $table.agentName, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get agentId => $composableBuilder(
      column: $table.agentId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get scene => $composableBuilder(
      column: $table.scene, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get sceneId => $composableBuilder(
      column: $table.sceneId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get userId => $composableBuilder(
      column: $table.userId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get timestamp => $composableBuilder(
      column: $table.timestamp, builder: (column) => ColumnOrderings(column));
}

class $$AgentActivityMessagesTableAnnotationComposer
    extends Composer<_$AppDatabase, $AgentActivityMessagesTable> {
  $$AgentActivityMessagesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get content =>
      $composableBuilder(column: $table.content, builder: (column) => column);

  GeneratedColumn<String> get icon =>
      $composableBuilder(column: $table.icon, builder: (column) => column);

  GeneratedColumn<String> get agentName =>
      $composableBuilder(column: $table.agentName, builder: (column) => column);

  GeneratedColumn<String> get agentId =>
      $composableBuilder(column: $table.agentId, builder: (column) => column);

  GeneratedColumn<String> get scene =>
      $composableBuilder(column: $table.scene, builder: (column) => column);

  GeneratedColumn<String> get sceneId =>
      $composableBuilder(column: $table.sceneId, builder: (column) => column);

  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<DateTime> get timestamp =>
      $composableBuilder(column: $table.timestamp, builder: (column) => column);
}

class $$AgentActivityMessagesTableTableManager extends RootTableManager<
    _$AppDatabase,
    $AgentActivityMessagesTable,
    AgentActivityMessage,
    $$AgentActivityMessagesTableFilterComposer,
    $$AgentActivityMessagesTableOrderingComposer,
    $$AgentActivityMessagesTableAnnotationComposer,
    $$AgentActivityMessagesTableCreateCompanionBuilder,
    $$AgentActivityMessagesTableUpdateCompanionBuilder,
    (
      AgentActivityMessage,
      BaseReferences<_$AppDatabase, $AgentActivityMessagesTable,
          AgentActivityMessage>
    ),
    AgentActivityMessage,
    PrefetchHooks Function()> {
  $$AgentActivityMessagesTableTableManager(
      _$AppDatabase db, $AgentActivityMessagesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AgentActivityMessagesTableFilterComposer(
                  $db: db, $table: table),
          createOrderingComposer: () =>
              $$AgentActivityMessagesTableOrderingComposer(
                  $db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AgentActivityMessagesTableAnnotationComposer(
                  $db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String> type = const Value.absent(),
            Value<String> title = const Value.absent(),
            Value<String?> content = const Value.absent(),
            Value<String?> icon = const Value.absent(),
            Value<String> agentName = const Value.absent(),
            Value<String?> agentId = const Value.absent(),
            Value<String?> scene = const Value.absent(),
            Value<String?> sceneId = const Value.absent(),
            Value<String?> userId = const Value.absent(),
            Value<DateTime> timestamp = const Value.absent(),
          }) =>
              AgentActivityMessagesCompanion(
            id: id,
            type: type,
            title: title,
            content: content,
            icon: icon,
            agentName: agentName,
            agentId: agentId,
            scene: scene,
            sceneId: sceneId,
            userId: userId,
            timestamp: timestamp,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required String type,
            required String title,
            Value<String?> content = const Value.absent(),
            Value<String?> icon = const Value.absent(),
            Value<String> agentName = const Value.absent(),
            Value<String?> agentId = const Value.absent(),
            Value<String?> scene = const Value.absent(),
            Value<String?> sceneId = const Value.absent(),
            Value<String?> userId = const Value.absent(),
            required DateTime timestamp,
          }) =>
              AgentActivityMessagesCompanion.insert(
            id: id,
            type: type,
            title: title,
            content: content,
            icon: icon,
            agentName: agentName,
            agentId: agentId,
            scene: scene,
            sceneId: sceneId,
            userId: userId,
            timestamp: timestamp,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$AgentActivityMessagesTableProcessedTableManager
    = ProcessedTableManager<
        _$AppDatabase,
        $AgentActivityMessagesTable,
        AgentActivityMessage,
        $$AgentActivityMessagesTableFilterComposer,
        $$AgentActivityMessagesTableOrderingComposer,
        $$AgentActivityMessagesTableAnnotationComposer,
        $$AgentActivityMessagesTableCreateCompanionBuilder,
        $$AgentActivityMessagesTableUpdateCompanionBuilder,
        (
          AgentActivityMessage,
          BaseReferences<_$AppDatabase, $AgentActivityMessagesTable,
              AgentActivityMessage>
        ),
        AgentActivityMessage,
        PrefetchHooks Function()>;
typedef $$CardCacheTableCreateCompanionBuilder = CardCacheCompanion Function({
  required String factId,
  required String cardPath,
  required int timestamp,
  required String tags,
  Value<int> rowid,
});
typedef $$CardCacheTableUpdateCompanionBuilder = CardCacheCompanion Function({
  Value<String> factId,
  Value<String> cardPath,
  Value<int> timestamp,
  Value<String> tags,
  Value<int> rowid,
});

class $$CardCacheTableFilterComposer
    extends Composer<_$AppDatabase, $CardCacheTable> {
  $$CardCacheTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get factId => $composableBuilder(
      column: $table.factId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get cardPath => $composableBuilder(
      column: $table.cardPath, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get timestamp => $composableBuilder(
      column: $table.timestamp, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get tags => $composableBuilder(
      column: $table.tags, builder: (column) => ColumnFilters(column));
}

class $$CardCacheTableOrderingComposer
    extends Composer<_$AppDatabase, $CardCacheTable> {
  $$CardCacheTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get factId => $composableBuilder(
      column: $table.factId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get cardPath => $composableBuilder(
      column: $table.cardPath, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get timestamp => $composableBuilder(
      column: $table.timestamp, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get tags => $composableBuilder(
      column: $table.tags, builder: (column) => ColumnOrderings(column));
}

class $$CardCacheTableAnnotationComposer
    extends Composer<_$AppDatabase, $CardCacheTable> {
  $$CardCacheTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get factId =>
      $composableBuilder(column: $table.factId, builder: (column) => column);

  GeneratedColumn<String> get cardPath =>
      $composableBuilder(column: $table.cardPath, builder: (column) => column);

  GeneratedColumn<int> get timestamp =>
      $composableBuilder(column: $table.timestamp, builder: (column) => column);

  GeneratedColumn<String> get tags =>
      $composableBuilder(column: $table.tags, builder: (column) => column);
}

class $$CardCacheTableTableManager extends RootTableManager<
    _$AppDatabase,
    $CardCacheTable,
    CardCacheData,
    $$CardCacheTableFilterComposer,
    $$CardCacheTableOrderingComposer,
    $$CardCacheTableAnnotationComposer,
    $$CardCacheTableCreateCompanionBuilder,
    $$CardCacheTableUpdateCompanionBuilder,
    (
      CardCacheData,
      BaseReferences<_$AppDatabase, $CardCacheTable, CardCacheData>
    ),
    CardCacheData,
    PrefetchHooks Function()> {
  $$CardCacheTableTableManager(_$AppDatabase db, $CardCacheTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CardCacheTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CardCacheTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CardCacheTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> factId = const Value.absent(),
            Value<String> cardPath = const Value.absent(),
            Value<int> timestamp = const Value.absent(),
            Value<String> tags = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              CardCacheCompanion(
            factId: factId,
            cardPath: cardPath,
            timestamp: timestamp,
            tags: tags,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String factId,
            required String cardPath,
            required int timestamp,
            required String tags,
            Value<int> rowid = const Value.absent(),
          }) =>
              CardCacheCompanion.insert(
            factId: factId,
            cardPath: cardPath,
            timestamp: timestamp,
            tags: tags,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$CardCacheTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $CardCacheTable,
    CardCacheData,
    $$CardCacheTableFilterComposer,
    $$CardCacheTableOrderingComposer,
    $$CardCacheTableAnnotationComposer,
    $$CardCacheTableCreateCompanionBuilder,
    $$CardCacheTableUpdateCompanionBuilder,
    (
      CardCacheData,
      BaseReferences<_$AppDatabase, $CardCacheTable, CardCacheData>
    ),
    CardCacheData,
    PrefetchHooks Function()>;
typedef $$SystemActionsTableCreateCompanionBuilder = SystemActionsCompanion
    Function({
  required String id,
  required String actionType,
  Value<String?> actionData,
  required String status,
  Value<String?> factId,
  Value<int?> createdAt,
  Value<int?> updatedAt,
  Value<int> rowid,
});
typedef $$SystemActionsTableUpdateCompanionBuilder = SystemActionsCompanion
    Function({
  Value<String> id,
  Value<String> actionType,
  Value<String?> actionData,
  Value<String> status,
  Value<String?> factId,
  Value<int?> createdAt,
  Value<int?> updatedAt,
  Value<int> rowid,
});

class $$SystemActionsTableFilterComposer
    extends Composer<_$AppDatabase, $SystemActionsTable> {
  $$SystemActionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get actionType => $composableBuilder(
      column: $table.actionType, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get actionData => $composableBuilder(
      column: $table.actionData, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get status => $composableBuilder(
      column: $table.status, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get factId => $composableBuilder(
      column: $table.factId, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));
}

class $$SystemActionsTableOrderingComposer
    extends Composer<_$AppDatabase, $SystemActionsTable> {
  $$SystemActionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get actionType => $composableBuilder(
      column: $table.actionType, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get actionData => $composableBuilder(
      column: $table.actionData, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get status => $composableBuilder(
      column: $table.status, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get factId => $composableBuilder(
      column: $table.factId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));
}

class $$SystemActionsTableAnnotationComposer
    extends Composer<_$AppDatabase, $SystemActionsTable> {
  $$SystemActionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get actionType => $composableBuilder(
      column: $table.actionType, builder: (column) => column);

  GeneratedColumn<String> get actionData => $composableBuilder(
      column: $table.actionData, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get factId =>
      $composableBuilder(column: $table.factId, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$SystemActionsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $SystemActionsTable,
    SystemAction,
    $$SystemActionsTableFilterComposer,
    $$SystemActionsTableOrderingComposer,
    $$SystemActionsTableAnnotationComposer,
    $$SystemActionsTableCreateCompanionBuilder,
    $$SystemActionsTableUpdateCompanionBuilder,
    (
      SystemAction,
      BaseReferences<_$AppDatabase, $SystemActionsTable, SystemAction>
    ),
    SystemAction,
    PrefetchHooks Function()> {
  $$SystemActionsTableTableManager(_$AppDatabase db, $SystemActionsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SystemActionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SystemActionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SystemActionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> actionType = const Value.absent(),
            Value<String?> actionData = const Value.absent(),
            Value<String> status = const Value.absent(),
            Value<String?> factId = const Value.absent(),
            Value<int?> createdAt = const Value.absent(),
            Value<int?> updatedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              SystemActionsCompanion(
            id: id,
            actionType: actionType,
            actionData: actionData,
            status: status,
            factId: factId,
            createdAt: createdAt,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String actionType,
            Value<String?> actionData = const Value.absent(),
            required String status,
            Value<String?> factId = const Value.absent(),
            Value<int?> createdAt = const Value.absent(),
            Value<int?> updatedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              SystemActionsCompanion.insert(
            id: id,
            actionType: actionType,
            actionData: actionData,
            status: status,
            factId: factId,
            createdAt: createdAt,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$SystemActionsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $SystemActionsTable,
    SystemAction,
    $$SystemActionsTableFilterComposer,
    $$SystemActionsTableOrderingComposer,
    $$SystemActionsTableAnnotationComposer,
    $$SystemActionsTableCreateCompanionBuilder,
    $$SystemActionsTableUpdateCompanionBuilder,
    (
      SystemAction,
      BaseReferences<_$AppDatabase, $SystemActionsTable, SystemAction>
    ),
    SystemAction,
    PrefetchHooks Function()>;
typedef $$ClarificationRequestsTableCreateCompanionBuilder
    = ClarificationRequestsCompanion Function({
  required String id,
  required String question,
  required String responseType,
  Value<String?> options,
  required String status,
  Value<String?> answerData,
  Value<String?> entityType,
  Value<String?> entityLabel,
  Value<String?> evidenceFactIds,
  Value<String?> reason,
  Value<String?> impact,
  Value<double?> confidence,
  Value<String?> proposedMemory,
  Value<String?> resolutionTarget,
  Value<String?> sourceAgent,
  Value<String?> dedupeKey,
  Value<String?> factId,
  Value<String?> error,
  Value<int?> createdAt,
  Value<int?> updatedAt,
  Value<int?> answeredAt,
  Value<int?> expiresAt,
  Value<int> rowid,
});
typedef $$ClarificationRequestsTableUpdateCompanionBuilder
    = ClarificationRequestsCompanion Function({
  Value<String> id,
  Value<String> question,
  Value<String> responseType,
  Value<String?> options,
  Value<String> status,
  Value<String?> answerData,
  Value<String?> entityType,
  Value<String?> entityLabel,
  Value<String?> evidenceFactIds,
  Value<String?> reason,
  Value<String?> impact,
  Value<double?> confidence,
  Value<String?> proposedMemory,
  Value<String?> resolutionTarget,
  Value<String?> sourceAgent,
  Value<String?> dedupeKey,
  Value<String?> factId,
  Value<String?> error,
  Value<int?> createdAt,
  Value<int?> updatedAt,
  Value<int?> answeredAt,
  Value<int?> expiresAt,
  Value<int> rowid,
});

class $$ClarificationRequestsTableFilterComposer
    extends Composer<_$AppDatabase, $ClarificationRequestsTable> {
  $$ClarificationRequestsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get question => $composableBuilder(
      column: $table.question, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get responseType => $composableBuilder(
      column: $table.responseType, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get options => $composableBuilder(
      column: $table.options, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get status => $composableBuilder(
      column: $table.status, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get answerData => $composableBuilder(
      column: $table.answerData, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get entityType => $composableBuilder(
      column: $table.entityType, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get entityLabel => $composableBuilder(
      column: $table.entityLabel, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get evidenceFactIds => $composableBuilder(
      column: $table.evidenceFactIds,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get reason => $composableBuilder(
      column: $table.reason, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get impact => $composableBuilder(
      column: $table.impact, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get confidence => $composableBuilder(
      column: $table.confidence, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get proposedMemory => $composableBuilder(
      column: $table.proposedMemory,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get resolutionTarget => $composableBuilder(
      column: $table.resolutionTarget,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get sourceAgent => $composableBuilder(
      column: $table.sourceAgent, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get dedupeKey => $composableBuilder(
      column: $table.dedupeKey, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get factId => $composableBuilder(
      column: $table.factId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get error => $composableBuilder(
      column: $table.error, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get answeredAt => $composableBuilder(
      column: $table.answeredAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get expiresAt => $composableBuilder(
      column: $table.expiresAt, builder: (column) => ColumnFilters(column));
}

class $$ClarificationRequestsTableOrderingComposer
    extends Composer<_$AppDatabase, $ClarificationRequestsTable> {
  $$ClarificationRequestsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get question => $composableBuilder(
      column: $table.question, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get responseType => $composableBuilder(
      column: $table.responseType,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get options => $composableBuilder(
      column: $table.options, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get status => $composableBuilder(
      column: $table.status, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get answerData => $composableBuilder(
      column: $table.answerData, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get entityType => $composableBuilder(
      column: $table.entityType, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get entityLabel => $composableBuilder(
      column: $table.entityLabel, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get evidenceFactIds => $composableBuilder(
      column: $table.evidenceFactIds,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get reason => $composableBuilder(
      column: $table.reason, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get impact => $composableBuilder(
      column: $table.impact, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get confidence => $composableBuilder(
      column: $table.confidence, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get proposedMemory => $composableBuilder(
      column: $table.proposedMemory,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get resolutionTarget => $composableBuilder(
      column: $table.resolutionTarget,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get sourceAgent => $composableBuilder(
      column: $table.sourceAgent, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get dedupeKey => $composableBuilder(
      column: $table.dedupeKey, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get factId => $composableBuilder(
      column: $table.factId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get error => $composableBuilder(
      column: $table.error, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get answeredAt => $composableBuilder(
      column: $table.answeredAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get expiresAt => $composableBuilder(
      column: $table.expiresAt, builder: (column) => ColumnOrderings(column));
}

class $$ClarificationRequestsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ClarificationRequestsTable> {
  $$ClarificationRequestsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get question =>
      $composableBuilder(column: $table.question, builder: (column) => column);

  GeneratedColumn<String> get responseType => $composableBuilder(
      column: $table.responseType, builder: (column) => column);

  GeneratedColumn<String> get options =>
      $composableBuilder(column: $table.options, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get answerData => $composableBuilder(
      column: $table.answerData, builder: (column) => column);

  GeneratedColumn<String> get entityType => $composableBuilder(
      column: $table.entityType, builder: (column) => column);

  GeneratedColumn<String> get entityLabel => $composableBuilder(
      column: $table.entityLabel, builder: (column) => column);

  GeneratedColumn<String> get evidenceFactIds => $composableBuilder(
      column: $table.evidenceFactIds, builder: (column) => column);

  GeneratedColumn<String> get reason =>
      $composableBuilder(column: $table.reason, builder: (column) => column);

  GeneratedColumn<String> get impact =>
      $composableBuilder(column: $table.impact, builder: (column) => column);

  GeneratedColumn<double> get confidence => $composableBuilder(
      column: $table.confidence, builder: (column) => column);

  GeneratedColumn<String> get proposedMemory => $composableBuilder(
      column: $table.proposedMemory, builder: (column) => column);

  GeneratedColumn<String> get resolutionTarget => $composableBuilder(
      column: $table.resolutionTarget, builder: (column) => column);

  GeneratedColumn<String> get sourceAgent => $composableBuilder(
      column: $table.sourceAgent, builder: (column) => column);

  GeneratedColumn<String> get dedupeKey =>
      $composableBuilder(column: $table.dedupeKey, builder: (column) => column);

  GeneratedColumn<String> get factId =>
      $composableBuilder(column: $table.factId, builder: (column) => column);

  GeneratedColumn<String> get error =>
      $composableBuilder(column: $table.error, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<int> get answeredAt => $composableBuilder(
      column: $table.answeredAt, builder: (column) => column);

  GeneratedColumn<int> get expiresAt =>
      $composableBuilder(column: $table.expiresAt, builder: (column) => column);
}

class $$ClarificationRequestsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $ClarificationRequestsTable,
    ClarificationRequest,
    $$ClarificationRequestsTableFilterComposer,
    $$ClarificationRequestsTableOrderingComposer,
    $$ClarificationRequestsTableAnnotationComposer,
    $$ClarificationRequestsTableCreateCompanionBuilder,
    $$ClarificationRequestsTableUpdateCompanionBuilder,
    (
      ClarificationRequest,
      BaseReferences<_$AppDatabase, $ClarificationRequestsTable,
          ClarificationRequest>
    ),
    ClarificationRequest,
    PrefetchHooks Function()> {
  $$ClarificationRequestsTableTableManager(
      _$AppDatabase db, $ClarificationRequestsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ClarificationRequestsTableFilterComposer(
                  $db: db, $table: table),
          createOrderingComposer: () =>
              $$ClarificationRequestsTableOrderingComposer(
                  $db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ClarificationRequestsTableAnnotationComposer(
                  $db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> question = const Value.absent(),
            Value<String> responseType = const Value.absent(),
            Value<String?> options = const Value.absent(),
            Value<String> status = const Value.absent(),
            Value<String?> answerData = const Value.absent(),
            Value<String?> entityType = const Value.absent(),
            Value<String?> entityLabel = const Value.absent(),
            Value<String?> evidenceFactIds = const Value.absent(),
            Value<String?> reason = const Value.absent(),
            Value<String?> impact = const Value.absent(),
            Value<double?> confidence = const Value.absent(),
            Value<String?> proposedMemory = const Value.absent(),
            Value<String?> resolutionTarget = const Value.absent(),
            Value<String?> sourceAgent = const Value.absent(),
            Value<String?> dedupeKey = const Value.absent(),
            Value<String?> factId = const Value.absent(),
            Value<String?> error = const Value.absent(),
            Value<int?> createdAt = const Value.absent(),
            Value<int?> updatedAt = const Value.absent(),
            Value<int?> answeredAt = const Value.absent(),
            Value<int?> expiresAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              ClarificationRequestsCompanion(
            id: id,
            question: question,
            responseType: responseType,
            options: options,
            status: status,
            answerData: answerData,
            entityType: entityType,
            entityLabel: entityLabel,
            evidenceFactIds: evidenceFactIds,
            reason: reason,
            impact: impact,
            confidence: confidence,
            proposedMemory: proposedMemory,
            resolutionTarget: resolutionTarget,
            sourceAgent: sourceAgent,
            dedupeKey: dedupeKey,
            factId: factId,
            error: error,
            createdAt: createdAt,
            updatedAt: updatedAt,
            answeredAt: answeredAt,
            expiresAt: expiresAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String question,
            required String responseType,
            Value<String?> options = const Value.absent(),
            required String status,
            Value<String?> answerData = const Value.absent(),
            Value<String?> entityType = const Value.absent(),
            Value<String?> entityLabel = const Value.absent(),
            Value<String?> evidenceFactIds = const Value.absent(),
            Value<String?> reason = const Value.absent(),
            Value<String?> impact = const Value.absent(),
            Value<double?> confidence = const Value.absent(),
            Value<String?> proposedMemory = const Value.absent(),
            Value<String?> resolutionTarget = const Value.absent(),
            Value<String?> sourceAgent = const Value.absent(),
            Value<String?> dedupeKey = const Value.absent(),
            Value<String?> factId = const Value.absent(),
            Value<String?> error = const Value.absent(),
            Value<int?> createdAt = const Value.absent(),
            Value<int?> updatedAt = const Value.absent(),
            Value<int?> answeredAt = const Value.absent(),
            Value<int?> expiresAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              ClarificationRequestsCompanion.insert(
            id: id,
            question: question,
            responseType: responseType,
            options: options,
            status: status,
            answerData: answerData,
            entityType: entityType,
            entityLabel: entityLabel,
            evidenceFactIds: evidenceFactIds,
            reason: reason,
            impact: impact,
            confidence: confidence,
            proposedMemory: proposedMemory,
            resolutionTarget: resolutionTarget,
            sourceAgent: sourceAgent,
            dedupeKey: dedupeKey,
            factId: factId,
            error: error,
            createdAt: createdAt,
            updatedAt: updatedAt,
            answeredAt: answeredAt,
            expiresAt: expiresAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$ClarificationRequestsTableProcessedTableManager
    = ProcessedTableManager<
        _$AppDatabase,
        $ClarificationRequestsTable,
        ClarificationRequest,
        $$ClarificationRequestsTableFilterComposer,
        $$ClarificationRequestsTableOrderingComposer,
        $$ClarificationRequestsTableAnnotationComposer,
        $$ClarificationRequestsTableCreateCompanionBuilder,
        $$ClarificationRequestsTableUpdateCompanionBuilder,
        (
          ClarificationRequest,
          BaseReferences<_$AppDatabase, $ClarificationRequestsTable,
              ClarificationRequest>
        ),
        ClarificationRequest,
        PrefetchHooks Function()>;
typedef $$PersonaChatMessagesTableCreateCompanionBuilder
    = PersonaChatMessagesCompanion Function({
  Value<int> id,
  required String characterId,
  required bool isFromCharacter,
  required String content,
  Value<String?> factId,
  Value<bool> isRead,
  required DateTime timestamp,
  Value<String> messageType,
  Value<String?> attachmentsJson,
});
typedef $$PersonaChatMessagesTableUpdateCompanionBuilder
    = PersonaChatMessagesCompanion Function({
  Value<int> id,
  Value<String> characterId,
  Value<bool> isFromCharacter,
  Value<String> content,
  Value<String?> factId,
  Value<bool> isRead,
  Value<DateTime> timestamp,
  Value<String> messageType,
  Value<String?> attachmentsJson,
});

class $$PersonaChatMessagesTableFilterComposer
    extends Composer<_$AppDatabase, $PersonaChatMessagesTable> {
  $$PersonaChatMessagesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get characterId => $composableBuilder(
      column: $table.characterId, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isFromCharacter => $composableBuilder(
      column: $table.isFromCharacter,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get content => $composableBuilder(
      column: $table.content, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get factId => $composableBuilder(
      column: $table.factId, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isRead => $composableBuilder(
      column: $table.isRead, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get timestamp => $composableBuilder(
      column: $table.timestamp, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get messageType => $composableBuilder(
      column: $table.messageType, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get attachmentsJson => $composableBuilder(
      column: $table.attachmentsJson,
      builder: (column) => ColumnFilters(column));
}

class $$PersonaChatMessagesTableOrderingComposer
    extends Composer<_$AppDatabase, $PersonaChatMessagesTable> {
  $$PersonaChatMessagesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get characterId => $composableBuilder(
      column: $table.characterId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isFromCharacter => $composableBuilder(
      column: $table.isFromCharacter,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get content => $composableBuilder(
      column: $table.content, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get factId => $composableBuilder(
      column: $table.factId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isRead => $composableBuilder(
      column: $table.isRead, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get timestamp => $composableBuilder(
      column: $table.timestamp, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get messageType => $composableBuilder(
      column: $table.messageType, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get attachmentsJson => $composableBuilder(
      column: $table.attachmentsJson,
      builder: (column) => ColumnOrderings(column));
}

class $$PersonaChatMessagesTableAnnotationComposer
    extends Composer<_$AppDatabase, $PersonaChatMessagesTable> {
  $$PersonaChatMessagesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get characterId => $composableBuilder(
      column: $table.characterId, builder: (column) => column);

  GeneratedColumn<bool> get isFromCharacter => $composableBuilder(
      column: $table.isFromCharacter, builder: (column) => column);

  GeneratedColumn<String> get content =>
      $composableBuilder(column: $table.content, builder: (column) => column);

  GeneratedColumn<String> get factId =>
      $composableBuilder(column: $table.factId, builder: (column) => column);

  GeneratedColumn<bool> get isRead =>
      $composableBuilder(column: $table.isRead, builder: (column) => column);

  GeneratedColumn<DateTime> get timestamp =>
      $composableBuilder(column: $table.timestamp, builder: (column) => column);

  GeneratedColumn<String> get messageType => $composableBuilder(
      column: $table.messageType, builder: (column) => column);

  GeneratedColumn<String> get attachmentsJson => $composableBuilder(
      column: $table.attachmentsJson, builder: (column) => column);
}

class $$PersonaChatMessagesTableTableManager extends RootTableManager<
    _$AppDatabase,
    $PersonaChatMessagesTable,
    PersonaChatMessage,
    $$PersonaChatMessagesTableFilterComposer,
    $$PersonaChatMessagesTableOrderingComposer,
    $$PersonaChatMessagesTableAnnotationComposer,
    $$PersonaChatMessagesTableCreateCompanionBuilder,
    $$PersonaChatMessagesTableUpdateCompanionBuilder,
    (
      PersonaChatMessage,
      BaseReferences<_$AppDatabase, $PersonaChatMessagesTable,
          PersonaChatMessage>
    ),
    PersonaChatMessage,
    PrefetchHooks Function()> {
  $$PersonaChatMessagesTableTableManager(
      _$AppDatabase db, $PersonaChatMessagesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PersonaChatMessagesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PersonaChatMessagesTableOrderingComposer(
                  $db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PersonaChatMessagesTableAnnotationComposer(
                  $db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String> characterId = const Value.absent(),
            Value<bool> isFromCharacter = const Value.absent(),
            Value<String> content = const Value.absent(),
            Value<String?> factId = const Value.absent(),
            Value<bool> isRead = const Value.absent(),
            Value<DateTime> timestamp = const Value.absent(),
            Value<String> messageType = const Value.absent(),
            Value<String?> attachmentsJson = const Value.absent(),
          }) =>
              PersonaChatMessagesCompanion(
            id: id,
            characterId: characterId,
            isFromCharacter: isFromCharacter,
            content: content,
            factId: factId,
            isRead: isRead,
            timestamp: timestamp,
            messageType: messageType,
            attachmentsJson: attachmentsJson,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required String characterId,
            required bool isFromCharacter,
            required String content,
            Value<String?> factId = const Value.absent(),
            Value<bool> isRead = const Value.absent(),
            required DateTime timestamp,
            Value<String> messageType = const Value.absent(),
            Value<String?> attachmentsJson = const Value.absent(),
          }) =>
              PersonaChatMessagesCompanion.insert(
            id: id,
            characterId: characterId,
            isFromCharacter: isFromCharacter,
            content: content,
            factId: factId,
            isRead: isRead,
            timestamp: timestamp,
            messageType: messageType,
            attachmentsJson: attachmentsJson,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$PersonaChatMessagesTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $PersonaChatMessagesTable,
    PersonaChatMessage,
    $$PersonaChatMessagesTableFilterComposer,
    $$PersonaChatMessagesTableOrderingComposer,
    $$PersonaChatMessagesTableAnnotationComposer,
    $$PersonaChatMessagesTableCreateCompanionBuilder,
    $$PersonaChatMessagesTableUpdateCompanionBuilder,
    (
      PersonaChatMessage,
      BaseReferences<_$AppDatabase, $PersonaChatMessagesTable,
          PersonaChatMessage>
    ),
    PersonaChatMessage,
    PrefetchHooks Function()>;
typedef $$ConversationCaptureCursorsTableCreateCompanionBuilder
    = ConversationCaptureCursorsCompanion Function({
  required String characterId,
  Value<int> lastExtractedMessageId,
  Value<int> lastQueuedMessageId,
  required int updatedAt,
  Value<int> rowid,
});
typedef $$ConversationCaptureCursorsTableUpdateCompanionBuilder
    = ConversationCaptureCursorsCompanion Function({
  Value<String> characterId,
  Value<int> lastExtractedMessageId,
  Value<int> lastQueuedMessageId,
  Value<int> updatedAt,
  Value<int> rowid,
});

class $$ConversationCaptureCursorsTableFilterComposer
    extends Composer<_$AppDatabase, $ConversationCaptureCursorsTable> {
  $$ConversationCaptureCursorsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get characterId => $composableBuilder(
      column: $table.characterId, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get lastExtractedMessageId => $composableBuilder(
      column: $table.lastExtractedMessageId,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get lastQueuedMessageId => $composableBuilder(
      column: $table.lastQueuedMessageId,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));
}

class $$ConversationCaptureCursorsTableOrderingComposer
    extends Composer<_$AppDatabase, $ConversationCaptureCursorsTable> {
  $$ConversationCaptureCursorsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get characterId => $composableBuilder(
      column: $table.characterId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get lastExtractedMessageId => $composableBuilder(
      column: $table.lastExtractedMessageId,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get lastQueuedMessageId => $composableBuilder(
      column: $table.lastQueuedMessageId,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));
}

class $$ConversationCaptureCursorsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ConversationCaptureCursorsTable> {
  $$ConversationCaptureCursorsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get characterId => $composableBuilder(
      column: $table.characterId, builder: (column) => column);

  GeneratedColumn<int> get lastExtractedMessageId => $composableBuilder(
      column: $table.lastExtractedMessageId, builder: (column) => column);

  GeneratedColumn<int> get lastQueuedMessageId => $composableBuilder(
      column: $table.lastQueuedMessageId, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$ConversationCaptureCursorsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $ConversationCaptureCursorsTable,
    ConversationCaptureCursor,
    $$ConversationCaptureCursorsTableFilterComposer,
    $$ConversationCaptureCursorsTableOrderingComposer,
    $$ConversationCaptureCursorsTableAnnotationComposer,
    $$ConversationCaptureCursorsTableCreateCompanionBuilder,
    $$ConversationCaptureCursorsTableUpdateCompanionBuilder,
    (
      ConversationCaptureCursor,
      BaseReferences<_$AppDatabase, $ConversationCaptureCursorsTable,
          ConversationCaptureCursor>
    ),
    ConversationCaptureCursor,
    PrefetchHooks Function()> {
  $$ConversationCaptureCursorsTableTableManager(
      _$AppDatabase db, $ConversationCaptureCursorsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ConversationCaptureCursorsTableFilterComposer(
                  $db: db, $table: table),
          createOrderingComposer: () =>
              $$ConversationCaptureCursorsTableOrderingComposer(
                  $db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ConversationCaptureCursorsTableAnnotationComposer(
                  $db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> characterId = const Value.absent(),
            Value<int> lastExtractedMessageId = const Value.absent(),
            Value<int> lastQueuedMessageId = const Value.absent(),
            Value<int> updatedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              ConversationCaptureCursorsCompanion(
            characterId: characterId,
            lastExtractedMessageId: lastExtractedMessageId,
            lastQueuedMessageId: lastQueuedMessageId,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String characterId,
            Value<int> lastExtractedMessageId = const Value.absent(),
            Value<int> lastQueuedMessageId = const Value.absent(),
            required int updatedAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              ConversationCaptureCursorsCompanion.insert(
            characterId: characterId,
            lastExtractedMessageId: lastExtractedMessageId,
            lastQueuedMessageId: lastQueuedMessageId,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$ConversationCaptureCursorsTableProcessedTableManager
    = ProcessedTableManager<
        _$AppDatabase,
        $ConversationCaptureCursorsTable,
        ConversationCaptureCursor,
        $$ConversationCaptureCursorsTableFilterComposer,
        $$ConversationCaptureCursorsTableOrderingComposer,
        $$ConversationCaptureCursorsTableAnnotationComposer,
        $$ConversationCaptureCursorsTableCreateCompanionBuilder,
        $$ConversationCaptureCursorsTableUpdateCompanionBuilder,
        (
          ConversationCaptureCursor,
          BaseReferences<_$AppDatabase, $ConversationCaptureCursorsTable,
              ConversationCaptureCursor>
        ),
        ConversationCaptureCursor,
        PrefetchHooks Function()>;
typedef $$SharedLifeEventOperationsTableCreateCompanionBuilder
    = SharedLifeEventOperationsCompanion Function({
  required String id,
  required String entityId,
  required String operationType,
  required String entityType,
  required String title,
  required String patchJson,
  required String sourceMessageIds,
  required String sourceCharacterId,
  Value<String?> captureTaskId,
  Value<String?> revertsOperationId,
  required int createdAt,
  Value<int> rowid,
});
typedef $$SharedLifeEventOperationsTableUpdateCompanionBuilder
    = SharedLifeEventOperationsCompanion Function({
  Value<String> id,
  Value<String> entityId,
  Value<String> operationType,
  Value<String> entityType,
  Value<String> title,
  Value<String> patchJson,
  Value<String> sourceMessageIds,
  Value<String> sourceCharacterId,
  Value<String?> captureTaskId,
  Value<String?> revertsOperationId,
  Value<int> createdAt,
  Value<int> rowid,
});

class $$SharedLifeEventOperationsTableFilterComposer
    extends Composer<_$AppDatabase, $SharedLifeEventOperationsTable> {
  $$SharedLifeEventOperationsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get entityId => $composableBuilder(
      column: $table.entityId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get operationType => $composableBuilder(
      column: $table.operationType, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get entityType => $composableBuilder(
      column: $table.entityType, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get title => $composableBuilder(
      column: $table.title, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get patchJson => $composableBuilder(
      column: $table.patchJson, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get sourceMessageIds => $composableBuilder(
      column: $table.sourceMessageIds,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get sourceCharacterId => $composableBuilder(
      column: $table.sourceCharacterId,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get captureTaskId => $composableBuilder(
      column: $table.captureTaskId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get revertsOperationId => $composableBuilder(
      column: $table.revertsOperationId,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));
}

class $$SharedLifeEventOperationsTableOrderingComposer
    extends Composer<_$AppDatabase, $SharedLifeEventOperationsTable> {
  $$SharedLifeEventOperationsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get entityId => $composableBuilder(
      column: $table.entityId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get operationType => $composableBuilder(
      column: $table.operationType,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get entityType => $composableBuilder(
      column: $table.entityType, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get title => $composableBuilder(
      column: $table.title, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get patchJson => $composableBuilder(
      column: $table.patchJson, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get sourceMessageIds => $composableBuilder(
      column: $table.sourceMessageIds,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get sourceCharacterId => $composableBuilder(
      column: $table.sourceCharacterId,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get captureTaskId => $composableBuilder(
      column: $table.captureTaskId,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get revertsOperationId => $composableBuilder(
      column: $table.revertsOperationId,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));
}

class $$SharedLifeEventOperationsTableAnnotationComposer
    extends Composer<_$AppDatabase, $SharedLifeEventOperationsTable> {
  $$SharedLifeEventOperationsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get entityId =>
      $composableBuilder(column: $table.entityId, builder: (column) => column);

  GeneratedColumn<String> get operationType => $composableBuilder(
      column: $table.operationType, builder: (column) => column);

  GeneratedColumn<String> get entityType => $composableBuilder(
      column: $table.entityType, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get patchJson =>
      $composableBuilder(column: $table.patchJson, builder: (column) => column);

  GeneratedColumn<String> get sourceMessageIds => $composableBuilder(
      column: $table.sourceMessageIds, builder: (column) => column);

  GeneratedColumn<String> get sourceCharacterId => $composableBuilder(
      column: $table.sourceCharacterId, builder: (column) => column);

  GeneratedColumn<String> get captureTaskId => $composableBuilder(
      column: $table.captureTaskId, builder: (column) => column);

  GeneratedColumn<String> get revertsOperationId => $composableBuilder(
      column: $table.revertsOperationId, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$SharedLifeEventOperationsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $SharedLifeEventOperationsTable,
    SharedLifeEventOperation,
    $$SharedLifeEventOperationsTableFilterComposer,
    $$SharedLifeEventOperationsTableOrderingComposer,
    $$SharedLifeEventOperationsTableAnnotationComposer,
    $$SharedLifeEventOperationsTableCreateCompanionBuilder,
    $$SharedLifeEventOperationsTableUpdateCompanionBuilder,
    (
      SharedLifeEventOperation,
      BaseReferences<_$AppDatabase, $SharedLifeEventOperationsTable,
          SharedLifeEventOperation>
    ),
    SharedLifeEventOperation,
    PrefetchHooks Function()> {
  $$SharedLifeEventOperationsTableTableManager(
      _$AppDatabase db, $SharedLifeEventOperationsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SharedLifeEventOperationsTableFilterComposer(
                  $db: db, $table: table),
          createOrderingComposer: () =>
              $$SharedLifeEventOperationsTableOrderingComposer(
                  $db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SharedLifeEventOperationsTableAnnotationComposer(
                  $db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> entityId = const Value.absent(),
            Value<String> operationType = const Value.absent(),
            Value<String> entityType = const Value.absent(),
            Value<String> title = const Value.absent(),
            Value<String> patchJson = const Value.absent(),
            Value<String> sourceMessageIds = const Value.absent(),
            Value<String> sourceCharacterId = const Value.absent(),
            Value<String?> captureTaskId = const Value.absent(),
            Value<String?> revertsOperationId = const Value.absent(),
            Value<int> createdAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              SharedLifeEventOperationsCompanion(
            id: id,
            entityId: entityId,
            operationType: operationType,
            entityType: entityType,
            title: title,
            patchJson: patchJson,
            sourceMessageIds: sourceMessageIds,
            sourceCharacterId: sourceCharacterId,
            captureTaskId: captureTaskId,
            revertsOperationId: revertsOperationId,
            createdAt: createdAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String entityId,
            required String operationType,
            required String entityType,
            required String title,
            required String patchJson,
            required String sourceMessageIds,
            required String sourceCharacterId,
            Value<String?> captureTaskId = const Value.absent(),
            Value<String?> revertsOperationId = const Value.absent(),
            required int createdAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              SharedLifeEventOperationsCompanion.insert(
            id: id,
            entityId: entityId,
            operationType: operationType,
            entityType: entityType,
            title: title,
            patchJson: patchJson,
            sourceMessageIds: sourceMessageIds,
            sourceCharacterId: sourceCharacterId,
            captureTaskId: captureTaskId,
            revertsOperationId: revertsOperationId,
            createdAt: createdAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$SharedLifeEventOperationsTableProcessedTableManager
    = ProcessedTableManager<
        _$AppDatabase,
        $SharedLifeEventOperationsTable,
        SharedLifeEventOperation,
        $$SharedLifeEventOperationsTableFilterComposer,
        $$SharedLifeEventOperationsTableOrderingComposer,
        $$SharedLifeEventOperationsTableAnnotationComposer,
        $$SharedLifeEventOperationsTableCreateCompanionBuilder,
        $$SharedLifeEventOperationsTableUpdateCompanionBuilder,
        (
          SharedLifeEventOperation,
          BaseReferences<_$AppDatabase, $SharedLifeEventOperationsTable,
              SharedLifeEventOperation>
        ),
        SharedLifeEventOperation,
        PrefetchHooks Function()>;
typedef $$SharedLifeEntitiesTableCreateCompanionBuilder
    = SharedLifeEntitiesCompanion Function({
  required String id,
  required String entityType,
  required String title,
  required String stateJson,
  Value<String> status,
  required String sourceCharacterId,
  required String lastOperationId,
  required int createdAt,
  required int updatedAt,
  Value<int> rowid,
});
typedef $$SharedLifeEntitiesTableUpdateCompanionBuilder
    = SharedLifeEntitiesCompanion Function({
  Value<String> id,
  Value<String> entityType,
  Value<String> title,
  Value<String> stateJson,
  Value<String> status,
  Value<String> sourceCharacterId,
  Value<String> lastOperationId,
  Value<int> createdAt,
  Value<int> updatedAt,
  Value<int> rowid,
});

class $$SharedLifeEntitiesTableFilterComposer
    extends Composer<_$AppDatabase, $SharedLifeEntitiesTable> {
  $$SharedLifeEntitiesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get entityType => $composableBuilder(
      column: $table.entityType, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get title => $composableBuilder(
      column: $table.title, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get stateJson => $composableBuilder(
      column: $table.stateJson, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get status => $composableBuilder(
      column: $table.status, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get sourceCharacterId => $composableBuilder(
      column: $table.sourceCharacterId,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get lastOperationId => $composableBuilder(
      column: $table.lastOperationId,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));
}

class $$SharedLifeEntitiesTableOrderingComposer
    extends Composer<_$AppDatabase, $SharedLifeEntitiesTable> {
  $$SharedLifeEntitiesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get entityType => $composableBuilder(
      column: $table.entityType, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get title => $composableBuilder(
      column: $table.title, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get stateJson => $composableBuilder(
      column: $table.stateJson, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get status => $composableBuilder(
      column: $table.status, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get sourceCharacterId => $composableBuilder(
      column: $table.sourceCharacterId,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get lastOperationId => $composableBuilder(
      column: $table.lastOperationId,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));
}

class $$SharedLifeEntitiesTableAnnotationComposer
    extends Composer<_$AppDatabase, $SharedLifeEntitiesTable> {
  $$SharedLifeEntitiesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get entityType => $composableBuilder(
      column: $table.entityType, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get stateJson =>
      $composableBuilder(column: $table.stateJson, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get sourceCharacterId => $composableBuilder(
      column: $table.sourceCharacterId, builder: (column) => column);

  GeneratedColumn<String> get lastOperationId => $composableBuilder(
      column: $table.lastOperationId, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$SharedLifeEntitiesTableTableManager extends RootTableManager<
    _$AppDatabase,
    $SharedLifeEntitiesTable,
    SharedLifeEntity,
    $$SharedLifeEntitiesTableFilterComposer,
    $$SharedLifeEntitiesTableOrderingComposer,
    $$SharedLifeEntitiesTableAnnotationComposer,
    $$SharedLifeEntitiesTableCreateCompanionBuilder,
    $$SharedLifeEntitiesTableUpdateCompanionBuilder,
    (
      SharedLifeEntity,
      BaseReferences<_$AppDatabase, $SharedLifeEntitiesTable, SharedLifeEntity>
    ),
    SharedLifeEntity,
    PrefetchHooks Function()> {
  $$SharedLifeEntitiesTableTableManager(
      _$AppDatabase db, $SharedLifeEntitiesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SharedLifeEntitiesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SharedLifeEntitiesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SharedLifeEntitiesTableAnnotationComposer(
                  $db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> entityType = const Value.absent(),
            Value<String> title = const Value.absent(),
            Value<String> stateJson = const Value.absent(),
            Value<String> status = const Value.absent(),
            Value<String> sourceCharacterId = const Value.absent(),
            Value<String> lastOperationId = const Value.absent(),
            Value<int> createdAt = const Value.absent(),
            Value<int> updatedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              SharedLifeEntitiesCompanion(
            id: id,
            entityType: entityType,
            title: title,
            stateJson: stateJson,
            status: status,
            sourceCharacterId: sourceCharacterId,
            lastOperationId: lastOperationId,
            createdAt: createdAt,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String entityType,
            required String title,
            required String stateJson,
            Value<String> status = const Value.absent(),
            required String sourceCharacterId,
            required String lastOperationId,
            required int createdAt,
            required int updatedAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              SharedLifeEntitiesCompanion.insert(
            id: id,
            entityType: entityType,
            title: title,
            stateJson: stateJson,
            status: status,
            sourceCharacterId: sourceCharacterId,
            lastOperationId: lastOperationId,
            createdAt: createdAt,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$SharedLifeEntitiesTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $SharedLifeEntitiesTable,
    SharedLifeEntity,
    $$SharedLifeEntitiesTableFilterComposer,
    $$SharedLifeEntitiesTableOrderingComposer,
    $$SharedLifeEntitiesTableAnnotationComposer,
    $$SharedLifeEntitiesTableCreateCompanionBuilder,
    $$SharedLifeEntitiesTableUpdateCompanionBuilder,
    (
      SharedLifeEntity,
      BaseReferences<_$AppDatabase, $SharedLifeEntitiesTable, SharedLifeEntity>
    ),
    SharedLifeEntity,
    PrefetchHooks Function()>;
typedef $$UserNotificationsTableCreateCompanionBuilder
    = UserNotificationsCompanion Function({
  required String id,
  required String userId,
  required String notificationType,
  required String subjectKey,
  Value<String?> payload,
  required int createdAt,
  required int updatedAt,
  Value<int> rowid,
});
typedef $$UserNotificationsTableUpdateCompanionBuilder
    = UserNotificationsCompanion Function({
  Value<String> id,
  Value<String> userId,
  Value<String> notificationType,
  Value<String> subjectKey,
  Value<String?> payload,
  Value<int> createdAt,
  Value<int> updatedAt,
  Value<int> rowid,
});

class $$UserNotificationsTableFilterComposer
    extends Composer<_$AppDatabase, $UserNotificationsTable> {
  $$UserNotificationsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get userId => $composableBuilder(
      column: $table.userId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get notificationType => $composableBuilder(
      column: $table.notificationType,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get subjectKey => $composableBuilder(
      column: $table.subjectKey, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get payload => $composableBuilder(
      column: $table.payload, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));
}

class $$UserNotificationsTableOrderingComposer
    extends Composer<_$AppDatabase, $UserNotificationsTable> {
  $$UserNotificationsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get userId => $composableBuilder(
      column: $table.userId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get notificationType => $composableBuilder(
      column: $table.notificationType,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get subjectKey => $composableBuilder(
      column: $table.subjectKey, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get payload => $composableBuilder(
      column: $table.payload, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));
}

class $$UserNotificationsTableAnnotationComposer
    extends Composer<_$AppDatabase, $UserNotificationsTable> {
  $$UserNotificationsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<String> get notificationType => $composableBuilder(
      column: $table.notificationType, builder: (column) => column);

  GeneratedColumn<String> get subjectKey => $composableBuilder(
      column: $table.subjectKey, builder: (column) => column);

  GeneratedColumn<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$UserNotificationsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $UserNotificationsTable,
    UserNotification,
    $$UserNotificationsTableFilterComposer,
    $$UserNotificationsTableOrderingComposer,
    $$UserNotificationsTableAnnotationComposer,
    $$UserNotificationsTableCreateCompanionBuilder,
    $$UserNotificationsTableUpdateCompanionBuilder,
    (
      UserNotification,
      BaseReferences<_$AppDatabase, $UserNotificationsTable, UserNotification>
    ),
    UserNotification,
    PrefetchHooks Function()> {
  $$UserNotificationsTableTableManager(
      _$AppDatabase db, $UserNotificationsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$UserNotificationsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$UserNotificationsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$UserNotificationsTableAnnotationComposer(
                  $db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> userId = const Value.absent(),
            Value<String> notificationType = const Value.absent(),
            Value<String> subjectKey = const Value.absent(),
            Value<String?> payload = const Value.absent(),
            Value<int> createdAt = const Value.absent(),
            Value<int> updatedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              UserNotificationsCompanion(
            id: id,
            userId: userId,
            notificationType: notificationType,
            subjectKey: subjectKey,
            payload: payload,
            createdAt: createdAt,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String userId,
            required String notificationType,
            required String subjectKey,
            Value<String?> payload = const Value.absent(),
            required int createdAt,
            required int updatedAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              UserNotificationsCompanion.insert(
            id: id,
            userId: userId,
            notificationType: notificationType,
            subjectKey: subjectKey,
            payload: payload,
            createdAt: createdAt,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$UserNotificationsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $UserNotificationsTable,
    UserNotification,
    $$UserNotificationsTableFilterComposer,
    $$UserNotificationsTableOrderingComposer,
    $$UserNotificationsTableAnnotationComposer,
    $$UserNotificationsTableCreateCompanionBuilder,
    $$UserNotificationsTableUpdateCompanionBuilder,
    (
      UserNotification,
      BaseReferences<_$AppDatabase, $UserNotificationsTable, UserNotification>
    ),
    UserNotification,
    PrefetchHooks Function()>;
typedef $$SystemMessageQueueTableCreateCompanionBuilder
    = SystemMessageQueueCompanion Function({
  required String id,
  required String triggerType,
  required String body,
  Value<String> status,
  required int createdAt,
  Value<int?> scheduledFor,
  Value<int?> processedAt,
  Value<String?> context,
  Value<int> rowid,
});
typedef $$SystemMessageQueueTableUpdateCompanionBuilder
    = SystemMessageQueueCompanion Function({
  Value<String> id,
  Value<String> triggerType,
  Value<String> body,
  Value<String> status,
  Value<int> createdAt,
  Value<int?> scheduledFor,
  Value<int?> processedAt,
  Value<String?> context,
  Value<int> rowid,
});

class $$SystemMessageQueueTableFilterComposer
    extends Composer<_$AppDatabase, $SystemMessageQueueTable> {
  $$SystemMessageQueueTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get triggerType => $composableBuilder(
      column: $table.triggerType, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get body => $composableBuilder(
      column: $table.body, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get status => $composableBuilder(
      column: $table.status, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get scheduledFor => $composableBuilder(
      column: $table.scheduledFor, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get processedAt => $composableBuilder(
      column: $table.processedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get context => $composableBuilder(
      column: $table.context, builder: (column) => ColumnFilters(column));
}

class $$SystemMessageQueueTableOrderingComposer
    extends Composer<_$AppDatabase, $SystemMessageQueueTable> {
  $$SystemMessageQueueTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get triggerType => $composableBuilder(
      column: $table.triggerType, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get body => $composableBuilder(
      column: $table.body, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get status => $composableBuilder(
      column: $table.status, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get scheduledFor => $composableBuilder(
      column: $table.scheduledFor,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get processedAt => $composableBuilder(
      column: $table.processedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get context => $composableBuilder(
      column: $table.context, builder: (column) => ColumnOrderings(column));
}

class $$SystemMessageQueueTableAnnotationComposer
    extends Composer<_$AppDatabase, $SystemMessageQueueTable> {
  $$SystemMessageQueueTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get triggerType => $composableBuilder(
      column: $table.triggerType, builder: (column) => column);

  GeneratedColumn<String> get body =>
      $composableBuilder(column: $table.body, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get scheduledFor => $composableBuilder(
      column: $table.scheduledFor, builder: (column) => column);

  GeneratedColumn<int> get processedAt => $composableBuilder(
      column: $table.processedAt, builder: (column) => column);

  GeneratedColumn<String> get context =>
      $composableBuilder(column: $table.context, builder: (column) => column);
}

class $$SystemMessageQueueTableTableManager extends RootTableManager<
    _$AppDatabase,
    $SystemMessageQueueTable,
    SystemMessageQueueData,
    $$SystemMessageQueueTableFilterComposer,
    $$SystemMessageQueueTableOrderingComposer,
    $$SystemMessageQueueTableAnnotationComposer,
    $$SystemMessageQueueTableCreateCompanionBuilder,
    $$SystemMessageQueueTableUpdateCompanionBuilder,
    (
      SystemMessageQueueData,
      BaseReferences<_$AppDatabase, $SystemMessageQueueTable,
          SystemMessageQueueData>
    ),
    SystemMessageQueueData,
    PrefetchHooks Function()> {
  $$SystemMessageQueueTableTableManager(
      _$AppDatabase db, $SystemMessageQueueTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SystemMessageQueueTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SystemMessageQueueTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SystemMessageQueueTableAnnotationComposer(
                  $db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> triggerType = const Value.absent(),
            Value<String> body = const Value.absent(),
            Value<String> status = const Value.absent(),
            Value<int> createdAt = const Value.absent(),
            Value<int?> scheduledFor = const Value.absent(),
            Value<int?> processedAt = const Value.absent(),
            Value<String?> context = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              SystemMessageQueueCompanion(
            id: id,
            triggerType: triggerType,
            body: body,
            status: status,
            createdAt: createdAt,
            scheduledFor: scheduledFor,
            processedAt: processedAt,
            context: context,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String triggerType,
            required String body,
            Value<String> status = const Value.absent(),
            required int createdAt,
            Value<int?> scheduledFor = const Value.absent(),
            Value<int?> processedAt = const Value.absent(),
            Value<String?> context = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              SystemMessageQueueCompanion.insert(
            id: id,
            triggerType: triggerType,
            body: body,
            status: status,
            createdAt: createdAt,
            scheduledFor: scheduledFor,
            processedAt: processedAt,
            context: context,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$SystemMessageQueueTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $SystemMessageQueueTable,
    SystemMessageQueueData,
    $$SystemMessageQueueTableFilterComposer,
    $$SystemMessageQueueTableOrderingComposer,
    $$SystemMessageQueueTableAnnotationComposer,
    $$SystemMessageQueueTableCreateCompanionBuilder,
    $$SystemMessageQueueTableUpdateCompanionBuilder,
    (
      SystemMessageQueueData,
      BaseReferences<_$AppDatabase, $SystemMessageQueueTable,
          SystemMessageQueueData>
    ),
    SystemMessageQueueData,
    PrefetchHooks Function()>;
typedef $$AiFinanceLedgerTableCreateCompanionBuilder = AiFinanceLedgerCompanion
    Function({
  required String id,
  required String characterId,
  required String entryType,
  required double totalAmount,
  required double aiAmount,
  Value<double?> contributionRatio,
  Value<String?> myContributionDesc,
  Value<String?> aiContributionDesc,
  Value<String?> purpose,
  Value<String?> linkedFactId,
  required int recordedAt,
  Value<String?> notes,
  Value<int> rowid,
});
typedef $$AiFinanceLedgerTableUpdateCompanionBuilder = AiFinanceLedgerCompanion
    Function({
  Value<String> id,
  Value<String> characterId,
  Value<String> entryType,
  Value<double> totalAmount,
  Value<double> aiAmount,
  Value<double?> contributionRatio,
  Value<String?> myContributionDesc,
  Value<String?> aiContributionDesc,
  Value<String?> purpose,
  Value<String?> linkedFactId,
  Value<int> recordedAt,
  Value<String?> notes,
  Value<int> rowid,
});

class $$AiFinanceLedgerTableFilterComposer
    extends Composer<_$AppDatabase, $AiFinanceLedgerTable> {
  $$AiFinanceLedgerTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get characterId => $composableBuilder(
      column: $table.characterId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get entryType => $composableBuilder(
      column: $table.entryType, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get totalAmount => $composableBuilder(
      column: $table.totalAmount, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get aiAmount => $composableBuilder(
      column: $table.aiAmount, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get contributionRatio => $composableBuilder(
      column: $table.contributionRatio,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get myContributionDesc => $composableBuilder(
      column: $table.myContributionDesc,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get aiContributionDesc => $composableBuilder(
      column: $table.aiContributionDesc,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get purpose => $composableBuilder(
      column: $table.purpose, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get linkedFactId => $composableBuilder(
      column: $table.linkedFactId, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get recordedAt => $composableBuilder(
      column: $table.recordedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get notes => $composableBuilder(
      column: $table.notes, builder: (column) => ColumnFilters(column));
}

class $$AiFinanceLedgerTableOrderingComposer
    extends Composer<_$AppDatabase, $AiFinanceLedgerTable> {
  $$AiFinanceLedgerTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get characterId => $composableBuilder(
      column: $table.characterId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get entryType => $composableBuilder(
      column: $table.entryType, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get totalAmount => $composableBuilder(
      column: $table.totalAmount, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get aiAmount => $composableBuilder(
      column: $table.aiAmount, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get contributionRatio => $composableBuilder(
      column: $table.contributionRatio,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get myContributionDesc => $composableBuilder(
      column: $table.myContributionDesc,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get aiContributionDesc => $composableBuilder(
      column: $table.aiContributionDesc,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get purpose => $composableBuilder(
      column: $table.purpose, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get linkedFactId => $composableBuilder(
      column: $table.linkedFactId,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get recordedAt => $composableBuilder(
      column: $table.recordedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get notes => $composableBuilder(
      column: $table.notes, builder: (column) => ColumnOrderings(column));
}

class $$AiFinanceLedgerTableAnnotationComposer
    extends Composer<_$AppDatabase, $AiFinanceLedgerTable> {
  $$AiFinanceLedgerTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get characterId => $composableBuilder(
      column: $table.characterId, builder: (column) => column);

  GeneratedColumn<String> get entryType =>
      $composableBuilder(column: $table.entryType, builder: (column) => column);

  GeneratedColumn<double> get totalAmount => $composableBuilder(
      column: $table.totalAmount, builder: (column) => column);

  GeneratedColumn<double> get aiAmount =>
      $composableBuilder(column: $table.aiAmount, builder: (column) => column);

  GeneratedColumn<double> get contributionRatio => $composableBuilder(
      column: $table.contributionRatio, builder: (column) => column);

  GeneratedColumn<String> get myContributionDesc => $composableBuilder(
      column: $table.myContributionDesc, builder: (column) => column);

  GeneratedColumn<String> get aiContributionDesc => $composableBuilder(
      column: $table.aiContributionDesc, builder: (column) => column);

  GeneratedColumn<String> get purpose =>
      $composableBuilder(column: $table.purpose, builder: (column) => column);

  GeneratedColumn<String> get linkedFactId => $composableBuilder(
      column: $table.linkedFactId, builder: (column) => column);

  GeneratedColumn<int> get recordedAt => $composableBuilder(
      column: $table.recordedAt, builder: (column) => column);

  GeneratedColumn<String> get notes =>
      $composableBuilder(column: $table.notes, builder: (column) => column);
}

class $$AiFinanceLedgerTableTableManager extends RootTableManager<
    _$AppDatabase,
    $AiFinanceLedgerTable,
    AiFinanceLedgerData,
    $$AiFinanceLedgerTableFilterComposer,
    $$AiFinanceLedgerTableOrderingComposer,
    $$AiFinanceLedgerTableAnnotationComposer,
    $$AiFinanceLedgerTableCreateCompanionBuilder,
    $$AiFinanceLedgerTableUpdateCompanionBuilder,
    (
      AiFinanceLedgerData,
      BaseReferences<_$AppDatabase, $AiFinanceLedgerTable, AiFinanceLedgerData>
    ),
    AiFinanceLedgerData,
    PrefetchHooks Function()> {
  $$AiFinanceLedgerTableTableManager(
      _$AppDatabase db, $AiFinanceLedgerTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AiFinanceLedgerTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AiFinanceLedgerTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AiFinanceLedgerTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> characterId = const Value.absent(),
            Value<String> entryType = const Value.absent(),
            Value<double> totalAmount = const Value.absent(),
            Value<double> aiAmount = const Value.absent(),
            Value<double?> contributionRatio = const Value.absent(),
            Value<String?> myContributionDesc = const Value.absent(),
            Value<String?> aiContributionDesc = const Value.absent(),
            Value<String?> purpose = const Value.absent(),
            Value<String?> linkedFactId = const Value.absent(),
            Value<int> recordedAt = const Value.absent(),
            Value<String?> notes = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              AiFinanceLedgerCompanion(
            id: id,
            characterId: characterId,
            entryType: entryType,
            totalAmount: totalAmount,
            aiAmount: aiAmount,
            contributionRatio: contributionRatio,
            myContributionDesc: myContributionDesc,
            aiContributionDesc: aiContributionDesc,
            purpose: purpose,
            linkedFactId: linkedFactId,
            recordedAt: recordedAt,
            notes: notes,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String characterId,
            required String entryType,
            required double totalAmount,
            required double aiAmount,
            Value<double?> contributionRatio = const Value.absent(),
            Value<String?> myContributionDesc = const Value.absent(),
            Value<String?> aiContributionDesc = const Value.absent(),
            Value<String?> purpose = const Value.absent(),
            Value<String?> linkedFactId = const Value.absent(),
            required int recordedAt,
            Value<String?> notes = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              AiFinanceLedgerCompanion.insert(
            id: id,
            characterId: characterId,
            entryType: entryType,
            totalAmount: totalAmount,
            aiAmount: aiAmount,
            contributionRatio: contributionRatio,
            myContributionDesc: myContributionDesc,
            aiContributionDesc: aiContributionDesc,
            purpose: purpose,
            linkedFactId: linkedFactId,
            recordedAt: recordedAt,
            notes: notes,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$AiFinanceLedgerTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $AiFinanceLedgerTable,
    AiFinanceLedgerData,
    $$AiFinanceLedgerTableFilterComposer,
    $$AiFinanceLedgerTableOrderingComposer,
    $$AiFinanceLedgerTableAnnotationComposer,
    $$AiFinanceLedgerTableCreateCompanionBuilder,
    $$AiFinanceLedgerTableUpdateCompanionBuilder,
    (
      AiFinanceLedgerData,
      BaseReferences<_$AppDatabase, $AiFinanceLedgerTable, AiFinanceLedgerData>
    ),
    AiFinanceLedgerData,
    PrefetchHooks Function()>;
typedef $$AiPurchaseLogTableCreateCompanionBuilder = AiPurchaseLogCompanion
    Function({
  required String id,
  required String characterId,
  required String paymentMode,
  required String status,
  required String userInstruction,
  Value<String> productPlatform,
  Value<String?> productId,
  Value<String?> productTitle,
  Value<String?> productUrl,
  Value<double?> priceCny,
  Value<String?> cashierUrl,
  Value<String?> failureReason,
  Value<String?> linkedLedgerId,
  required int createdAt,
  required int updatedAt,
  Value<int> rowid,
});
typedef $$AiPurchaseLogTableUpdateCompanionBuilder = AiPurchaseLogCompanion
    Function({
  Value<String> id,
  Value<String> characterId,
  Value<String> paymentMode,
  Value<String> status,
  Value<String> userInstruction,
  Value<String> productPlatform,
  Value<String?> productId,
  Value<String?> productTitle,
  Value<String?> productUrl,
  Value<double?> priceCny,
  Value<String?> cashierUrl,
  Value<String?> failureReason,
  Value<String?> linkedLedgerId,
  Value<int> createdAt,
  Value<int> updatedAt,
  Value<int> rowid,
});

class $$AiPurchaseLogTableFilterComposer
    extends Composer<_$AppDatabase, $AiPurchaseLogTable> {
  $$AiPurchaseLogTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get characterId => $composableBuilder(
      column: $table.characterId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get paymentMode => $composableBuilder(
      column: $table.paymentMode, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get status => $composableBuilder(
      column: $table.status, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get userInstruction => $composableBuilder(
      column: $table.userInstruction,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get productPlatform => $composableBuilder(
      column: $table.productPlatform,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get productId => $composableBuilder(
      column: $table.productId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get productTitle => $composableBuilder(
      column: $table.productTitle, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get productUrl => $composableBuilder(
      column: $table.productUrl, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get priceCny => $composableBuilder(
      column: $table.priceCny, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get cashierUrl => $composableBuilder(
      column: $table.cashierUrl, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get failureReason => $composableBuilder(
      column: $table.failureReason, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get linkedLedgerId => $composableBuilder(
      column: $table.linkedLedgerId,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));
}

class $$AiPurchaseLogTableOrderingComposer
    extends Composer<_$AppDatabase, $AiPurchaseLogTable> {
  $$AiPurchaseLogTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get characterId => $composableBuilder(
      column: $table.characterId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get paymentMode => $composableBuilder(
      column: $table.paymentMode, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get status => $composableBuilder(
      column: $table.status, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get userInstruction => $composableBuilder(
      column: $table.userInstruction,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get productPlatform => $composableBuilder(
      column: $table.productPlatform,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get productId => $composableBuilder(
      column: $table.productId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get productTitle => $composableBuilder(
      column: $table.productTitle,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get productUrl => $composableBuilder(
      column: $table.productUrl, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get priceCny => $composableBuilder(
      column: $table.priceCny, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get cashierUrl => $composableBuilder(
      column: $table.cashierUrl, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get failureReason => $composableBuilder(
      column: $table.failureReason,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get linkedLedgerId => $composableBuilder(
      column: $table.linkedLedgerId,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));
}

class $$AiPurchaseLogTableAnnotationComposer
    extends Composer<_$AppDatabase, $AiPurchaseLogTable> {
  $$AiPurchaseLogTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get characterId => $composableBuilder(
      column: $table.characterId, builder: (column) => column);

  GeneratedColumn<String> get paymentMode => $composableBuilder(
      column: $table.paymentMode, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get userInstruction => $composableBuilder(
      column: $table.userInstruction, builder: (column) => column);

  GeneratedColumn<String> get productPlatform => $composableBuilder(
      column: $table.productPlatform, builder: (column) => column);

  GeneratedColumn<String> get productId =>
      $composableBuilder(column: $table.productId, builder: (column) => column);

  GeneratedColumn<String> get productTitle => $composableBuilder(
      column: $table.productTitle, builder: (column) => column);

  GeneratedColumn<String> get productUrl => $composableBuilder(
      column: $table.productUrl, builder: (column) => column);

  GeneratedColumn<double> get priceCny =>
      $composableBuilder(column: $table.priceCny, builder: (column) => column);

  GeneratedColumn<String> get cashierUrl => $composableBuilder(
      column: $table.cashierUrl, builder: (column) => column);

  GeneratedColumn<String> get failureReason => $composableBuilder(
      column: $table.failureReason, builder: (column) => column);

  GeneratedColumn<String> get linkedLedgerId => $composableBuilder(
      column: $table.linkedLedgerId, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$AiPurchaseLogTableTableManager extends RootTableManager<
    _$AppDatabase,
    $AiPurchaseLogTable,
    AiPurchaseLogData,
    $$AiPurchaseLogTableFilterComposer,
    $$AiPurchaseLogTableOrderingComposer,
    $$AiPurchaseLogTableAnnotationComposer,
    $$AiPurchaseLogTableCreateCompanionBuilder,
    $$AiPurchaseLogTableUpdateCompanionBuilder,
    (
      AiPurchaseLogData,
      BaseReferences<_$AppDatabase, $AiPurchaseLogTable, AiPurchaseLogData>
    ),
    AiPurchaseLogData,
    PrefetchHooks Function()> {
  $$AiPurchaseLogTableTableManager(_$AppDatabase db, $AiPurchaseLogTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AiPurchaseLogTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AiPurchaseLogTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AiPurchaseLogTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> characterId = const Value.absent(),
            Value<String> paymentMode = const Value.absent(),
            Value<String> status = const Value.absent(),
            Value<String> userInstruction = const Value.absent(),
            Value<String> productPlatform = const Value.absent(),
            Value<String?> productId = const Value.absent(),
            Value<String?> productTitle = const Value.absent(),
            Value<String?> productUrl = const Value.absent(),
            Value<double?> priceCny = const Value.absent(),
            Value<String?> cashierUrl = const Value.absent(),
            Value<String?> failureReason = const Value.absent(),
            Value<String?> linkedLedgerId = const Value.absent(),
            Value<int> createdAt = const Value.absent(),
            Value<int> updatedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              AiPurchaseLogCompanion(
            id: id,
            characterId: characterId,
            paymentMode: paymentMode,
            status: status,
            userInstruction: userInstruction,
            productPlatform: productPlatform,
            productId: productId,
            productTitle: productTitle,
            productUrl: productUrl,
            priceCny: priceCny,
            cashierUrl: cashierUrl,
            failureReason: failureReason,
            linkedLedgerId: linkedLedgerId,
            createdAt: createdAt,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String characterId,
            required String paymentMode,
            required String status,
            required String userInstruction,
            Value<String> productPlatform = const Value.absent(),
            Value<String?> productId = const Value.absent(),
            Value<String?> productTitle = const Value.absent(),
            Value<String?> productUrl = const Value.absent(),
            Value<double?> priceCny = const Value.absent(),
            Value<String?> cashierUrl = const Value.absent(),
            Value<String?> failureReason = const Value.absent(),
            Value<String?> linkedLedgerId = const Value.absent(),
            required int createdAt,
            required int updatedAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              AiPurchaseLogCompanion.insert(
            id: id,
            characterId: characterId,
            paymentMode: paymentMode,
            status: status,
            userInstruction: userInstruction,
            productPlatform: productPlatform,
            productId: productId,
            productTitle: productTitle,
            productUrl: productUrl,
            priceCny: priceCny,
            cashierUrl: cashierUrl,
            failureReason: failureReason,
            linkedLedgerId: linkedLedgerId,
            createdAt: createdAt,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$AiPurchaseLogTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $AiPurchaseLogTable,
    AiPurchaseLogData,
    $$AiPurchaseLogTableFilterComposer,
    $$AiPurchaseLogTableOrderingComposer,
    $$AiPurchaseLogTableAnnotationComposer,
    $$AiPurchaseLogTableCreateCompanionBuilder,
    $$AiPurchaseLogTableUpdateCompanionBuilder,
    (
      AiPurchaseLogData,
      BaseReferences<_$AppDatabase, $AiPurchaseLogTable, AiPurchaseLogData>
    ),
    AiPurchaseLogData,
    PrefetchHooks Function()>;
typedef $$VoiceCallSessionsTableCreateCompanionBuilder
    = VoiceCallSessionsCompanion Function({
  required String id,
  required String characterId,
  required String userId,
  required int startedAt,
  Value<int?> endedAt,
  Value<String?> summary,
  Value<int> rowid,
});
typedef $$VoiceCallSessionsTableUpdateCompanionBuilder
    = VoiceCallSessionsCompanion Function({
  Value<String> id,
  Value<String> characterId,
  Value<String> userId,
  Value<int> startedAt,
  Value<int?> endedAt,
  Value<String?> summary,
  Value<int> rowid,
});

class $$VoiceCallSessionsTableFilterComposer
    extends Composer<_$AppDatabase, $VoiceCallSessionsTable> {
  $$VoiceCallSessionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get characterId => $composableBuilder(
      column: $table.characterId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get userId => $composableBuilder(
      column: $table.userId, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get startedAt => $composableBuilder(
      column: $table.startedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get endedAt => $composableBuilder(
      column: $table.endedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get summary => $composableBuilder(
      column: $table.summary, builder: (column) => ColumnFilters(column));
}

class $$VoiceCallSessionsTableOrderingComposer
    extends Composer<_$AppDatabase, $VoiceCallSessionsTable> {
  $$VoiceCallSessionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get characterId => $composableBuilder(
      column: $table.characterId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get userId => $composableBuilder(
      column: $table.userId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get startedAt => $composableBuilder(
      column: $table.startedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get endedAt => $composableBuilder(
      column: $table.endedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get summary => $composableBuilder(
      column: $table.summary, builder: (column) => ColumnOrderings(column));
}

class $$VoiceCallSessionsTableAnnotationComposer
    extends Composer<_$AppDatabase, $VoiceCallSessionsTable> {
  $$VoiceCallSessionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get characterId => $composableBuilder(
      column: $table.characterId, builder: (column) => column);

  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<int> get startedAt =>
      $composableBuilder(column: $table.startedAt, builder: (column) => column);

  GeneratedColumn<int> get endedAt =>
      $composableBuilder(column: $table.endedAt, builder: (column) => column);

  GeneratedColumn<String> get summary =>
      $composableBuilder(column: $table.summary, builder: (column) => column);
}

class $$VoiceCallSessionsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $VoiceCallSessionsTable,
    VoiceCallSession,
    $$VoiceCallSessionsTableFilterComposer,
    $$VoiceCallSessionsTableOrderingComposer,
    $$VoiceCallSessionsTableAnnotationComposer,
    $$VoiceCallSessionsTableCreateCompanionBuilder,
    $$VoiceCallSessionsTableUpdateCompanionBuilder,
    (
      VoiceCallSession,
      BaseReferences<_$AppDatabase, $VoiceCallSessionsTable, VoiceCallSession>
    ),
    VoiceCallSession,
    PrefetchHooks Function()> {
  $$VoiceCallSessionsTableTableManager(
      _$AppDatabase db, $VoiceCallSessionsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$VoiceCallSessionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$VoiceCallSessionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$VoiceCallSessionsTableAnnotationComposer(
                  $db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> characterId = const Value.absent(),
            Value<String> userId = const Value.absent(),
            Value<int> startedAt = const Value.absent(),
            Value<int?> endedAt = const Value.absent(),
            Value<String?> summary = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              VoiceCallSessionsCompanion(
            id: id,
            characterId: characterId,
            userId: userId,
            startedAt: startedAt,
            endedAt: endedAt,
            summary: summary,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String characterId,
            required String userId,
            required int startedAt,
            Value<int?> endedAt = const Value.absent(),
            Value<String?> summary = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              VoiceCallSessionsCompanion.insert(
            id: id,
            characterId: characterId,
            userId: userId,
            startedAt: startedAt,
            endedAt: endedAt,
            summary: summary,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$VoiceCallSessionsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $VoiceCallSessionsTable,
    VoiceCallSession,
    $$VoiceCallSessionsTableFilterComposer,
    $$VoiceCallSessionsTableOrderingComposer,
    $$VoiceCallSessionsTableAnnotationComposer,
    $$VoiceCallSessionsTableCreateCompanionBuilder,
    $$VoiceCallSessionsTableUpdateCompanionBuilder,
    (
      VoiceCallSession,
      BaseReferences<_$AppDatabase, $VoiceCallSessionsTable, VoiceCallSession>
    ),
    VoiceCallSession,
    PrefetchHooks Function()>;
typedef $$VoiceCallMessagesTableCreateCompanionBuilder
    = VoiceCallMessagesCompanion Function({
  Value<int> id,
  required String sessionId,
  required String role,
  required String content,
  required int createdAt,
});
typedef $$VoiceCallMessagesTableUpdateCompanionBuilder
    = VoiceCallMessagesCompanion Function({
  Value<int> id,
  Value<String> sessionId,
  Value<String> role,
  Value<String> content,
  Value<int> createdAt,
});

class $$VoiceCallMessagesTableFilterComposer
    extends Composer<_$AppDatabase, $VoiceCallMessagesTable> {
  $$VoiceCallMessagesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get sessionId => $composableBuilder(
      column: $table.sessionId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get role => $composableBuilder(
      column: $table.role, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get content => $composableBuilder(
      column: $table.content, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));
}

class $$VoiceCallMessagesTableOrderingComposer
    extends Composer<_$AppDatabase, $VoiceCallMessagesTable> {
  $$VoiceCallMessagesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get sessionId => $composableBuilder(
      column: $table.sessionId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get role => $composableBuilder(
      column: $table.role, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get content => $composableBuilder(
      column: $table.content, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));
}

class $$VoiceCallMessagesTableAnnotationComposer
    extends Composer<_$AppDatabase, $VoiceCallMessagesTable> {
  $$VoiceCallMessagesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get sessionId =>
      $composableBuilder(column: $table.sessionId, builder: (column) => column);

  GeneratedColumn<String> get role =>
      $composableBuilder(column: $table.role, builder: (column) => column);

  GeneratedColumn<String> get content =>
      $composableBuilder(column: $table.content, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$VoiceCallMessagesTableTableManager extends RootTableManager<
    _$AppDatabase,
    $VoiceCallMessagesTable,
    VoiceCallMessage,
    $$VoiceCallMessagesTableFilterComposer,
    $$VoiceCallMessagesTableOrderingComposer,
    $$VoiceCallMessagesTableAnnotationComposer,
    $$VoiceCallMessagesTableCreateCompanionBuilder,
    $$VoiceCallMessagesTableUpdateCompanionBuilder,
    (
      VoiceCallMessage,
      BaseReferences<_$AppDatabase, $VoiceCallMessagesTable, VoiceCallMessage>
    ),
    VoiceCallMessage,
    PrefetchHooks Function()> {
  $$VoiceCallMessagesTableTableManager(
      _$AppDatabase db, $VoiceCallMessagesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$VoiceCallMessagesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$VoiceCallMessagesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$VoiceCallMessagesTableAnnotationComposer(
                  $db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String> sessionId = const Value.absent(),
            Value<String> role = const Value.absent(),
            Value<String> content = const Value.absent(),
            Value<int> createdAt = const Value.absent(),
          }) =>
              VoiceCallMessagesCompanion(
            id: id,
            sessionId: sessionId,
            role: role,
            content: content,
            createdAt: createdAt,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required String sessionId,
            required String role,
            required String content,
            required int createdAt,
          }) =>
              VoiceCallMessagesCompanion.insert(
            id: id,
            sessionId: sessionId,
            role: role,
            content: content,
            createdAt: createdAt,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$VoiceCallMessagesTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $VoiceCallMessagesTable,
    VoiceCallMessage,
    $$VoiceCallMessagesTableFilterComposer,
    $$VoiceCallMessagesTableOrderingComposer,
    $$VoiceCallMessagesTableAnnotationComposer,
    $$VoiceCallMessagesTableCreateCompanionBuilder,
    $$VoiceCallMessagesTableUpdateCompanionBuilder,
    (
      VoiceCallMessage,
      BaseReferences<_$AppDatabase, $VoiceCallMessagesTable, VoiceCallMessage>
    ),
    VoiceCallMessage,
    PrefetchHooks Function()>;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$TasksTableTableManager get tasks =>
      $$TasksTableTableManager(_db, _db.tasks);
  $$KvStoreTableTableManager get kvStore =>
      $$KvStoreTableTableManager(_db, _db.kvStore);
  $$AgentActivityMessagesTableTableManager get agentActivityMessages =>
      $$AgentActivityMessagesTableTableManager(_db, _db.agentActivityMessages);
  $$CardCacheTableTableManager get cardCache =>
      $$CardCacheTableTableManager(_db, _db.cardCache);
  $$SystemActionsTableTableManager get systemActions =>
      $$SystemActionsTableTableManager(_db, _db.systemActions);
  $$ClarificationRequestsTableTableManager get clarificationRequests =>
      $$ClarificationRequestsTableTableManager(_db, _db.clarificationRequests);
  $$PersonaChatMessagesTableTableManager get personaChatMessages =>
      $$PersonaChatMessagesTableTableManager(_db, _db.personaChatMessages);
  $$ConversationCaptureCursorsTableTableManager
      get conversationCaptureCursors =>
          $$ConversationCaptureCursorsTableTableManager(
              _db, _db.conversationCaptureCursors);
  $$SharedLifeEventOperationsTableTableManager get sharedLifeEventOperations =>
      $$SharedLifeEventOperationsTableTableManager(
          _db, _db.sharedLifeEventOperations);
  $$SharedLifeEntitiesTableTableManager get sharedLifeEntities =>
      $$SharedLifeEntitiesTableTableManager(_db, _db.sharedLifeEntities);
  $$UserNotificationsTableTableManager get userNotifications =>
      $$UserNotificationsTableTableManager(_db, _db.userNotifications);
  $$SystemMessageQueueTableTableManager get systemMessageQueue =>
      $$SystemMessageQueueTableTableManager(_db, _db.systemMessageQueue);
  $$AiFinanceLedgerTableTableManager get aiFinanceLedger =>
      $$AiFinanceLedgerTableTableManager(_db, _db.aiFinanceLedger);
  $$AiPurchaseLogTableTableManager get aiPurchaseLog =>
      $$AiPurchaseLogTableTableManager(_db, _db.aiPurchaseLog);
  $$VoiceCallSessionsTableTableManager get voiceCallSessions =>
      $$VoiceCallSessionsTableTableManager(_db, _db.voiceCallSessions);
  $$VoiceCallMessagesTableTableManager get voiceCallMessages =>
      $$VoiceCallMessagesTableTableManager(_db, _db.voiceCallMessages);
}
