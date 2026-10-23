// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $SessionsTable extends Sessions with TableInfo<$SessionsTable, Session> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SessionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _startedAtMeta = const VerificationMeta(
    'startedAt',
  );
  @override
  late final GeneratedColumn<DateTime> startedAt = GeneratedColumn<DateTime>(
    'started_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _durationSecondsMeta = const VerificationMeta(
    'durationSeconds',
  );
  @override
  late final GeneratedColumn<int> durationSeconds = GeneratedColumn<int>(
    'duration_seconds',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _billedAudioSecondsMeta =
      const VerificationMeta('billedAudioSeconds');
  @override
  late final GeneratedColumn<int> billedAudioSeconds = GeneratedColumn<int>(
    'billed_audio_seconds',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _actualCostMeta = const VerificationMeta(
    'actualCost',
  );
  @override
  late final GeneratedColumn<double> actualCost = GeneratedColumn<double>(
    'actual_cost',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _modelMeta = const VerificationMeta('model');
  @override
  late final GeneratedColumn<String> model = GeneratedColumn<String>(
    'model',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _languageMeta = const VerificationMeta(
    'language',
  );
  @override
  late final GeneratedColumn<String> language = GeneratedColumn<String>(
    'language',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _audioPathMeta = const VerificationMeta(
    'audioPath',
  );
  @override
  late final GeneratedColumn<String> audioPath = GeneratedColumn<String>(
    'audio_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    startedAt,
    durationSeconds,
    billedAudioSeconds,
    actualCost,
    model,
    language,
    status,
    audioPath,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sessions';
  @override
  VerificationContext validateIntegrity(
    Insertable<Session> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('started_at')) {
      context.handle(
        _startedAtMeta,
        startedAt.isAcceptableOrUnknown(data['started_at']!, _startedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_startedAtMeta);
    }
    if (data.containsKey('duration_seconds')) {
      context.handle(
        _durationSecondsMeta,
        durationSeconds.isAcceptableOrUnknown(
          data['duration_seconds']!,
          _durationSecondsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_durationSecondsMeta);
    }
    if (data.containsKey('billed_audio_seconds')) {
      context.handle(
        _billedAudioSecondsMeta,
        billedAudioSeconds.isAcceptableOrUnknown(
          data['billed_audio_seconds']!,
          _billedAudioSecondsMeta,
        ),
      );
    }
    if (data.containsKey('actual_cost')) {
      context.handle(
        _actualCostMeta,
        actualCost.isAcceptableOrUnknown(data['actual_cost']!, _actualCostMeta),
      );
    }
    if (data.containsKey('model')) {
      context.handle(
        _modelMeta,
        model.isAcceptableOrUnknown(data['model']!, _modelMeta),
      );
    } else if (isInserting) {
      context.missing(_modelMeta);
    }
    if (data.containsKey('language')) {
      context.handle(
        _languageMeta,
        language.isAcceptableOrUnknown(data['language']!, _languageMeta),
      );
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
    if (data.containsKey('audio_path')) {
      context.handle(
        _audioPathMeta,
        audioPath.isAcceptableOrUnknown(data['audio_path']!, _audioPathMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => const {};
  @override
  Session map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Session(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      startedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}started_at'],
      )!,
      durationSeconds: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}duration_seconds'],
      )!,
      billedAudioSeconds: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}billed_audio_seconds'],
      ),
      actualCost: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}actual_cost'],
      ),
      model: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}model'],
      )!,
      language: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}language'],
      ),
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      audioPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}audio_path'],
      ),
    );
  }

  @override
  $SessionsTable createAlias(String alias) {
    return $SessionsTable(attachedDatabase, alias);
  }
}

class Session extends DataClass implements Insertable<Session> {
  /// Stable session id; also the file name of the session audio
  /// (`<id>.wav` in the app's documents directory).
  final String id;

  /// When the session started (wall clock).
  final DateTime startedAt;

  /// Session duration in seconds.
  final int durationSeconds;

  /// Audio seconds billed by the API (realtime session + post-session
  /// diarization pass), when reported.
  final int? billedAudioSeconds;

  /// Actual cost in USD, when known.
  final double? actualCost;

  /// Realtime model id used for the session.
  final String model;

  /// Detected or pinned language, when known.
  final String? language;

  /// `provisional` until the post-session diarization pass replaces the
  /// transcript, `final` afterwards.
  final String status;

  /// Absolute path of the session audio WAV in app-private storage, or null
  /// once the audio was deleted.
  final String? audioPath;
  const Session({
    required this.id,
    required this.startedAt,
    required this.durationSeconds,
    this.billedAudioSeconds,
    this.actualCost,
    required this.model,
    this.language,
    required this.status,
    this.audioPath,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['started_at'] = Variable<DateTime>(startedAt);
    map['duration_seconds'] = Variable<int>(durationSeconds);
    if (!nullToAbsent || billedAudioSeconds != null) {
      map['billed_audio_seconds'] = Variable<int>(billedAudioSeconds);
    }
    if (!nullToAbsent || actualCost != null) {
      map['actual_cost'] = Variable<double>(actualCost);
    }
    map['model'] = Variable<String>(model);
    if (!nullToAbsent || language != null) {
      map['language'] = Variable<String>(language);
    }
    map['status'] = Variable<String>(status);
    if (!nullToAbsent || audioPath != null) {
      map['audio_path'] = Variable<String>(audioPath);
    }
    return map;
  }

  SessionsCompanion toCompanion(bool nullToAbsent) {
    return SessionsCompanion(
      id: Value(id),
      startedAt: Value(startedAt),
      durationSeconds: Value(durationSeconds),
      billedAudioSeconds: billedAudioSeconds == null && nullToAbsent
          ? const Value.absent()
          : Value(billedAudioSeconds),
      actualCost: actualCost == null && nullToAbsent
          ? const Value.absent()
          : Value(actualCost),
      model: Value(model),
      language: language == null && nullToAbsent
          ? const Value.absent()
          : Value(language),
      status: Value(status),
      audioPath: audioPath == null && nullToAbsent
          ? const Value.absent()
          : Value(audioPath),
    );
  }

  factory Session.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Session(
      id: serializer.fromJson<String>(json['id']),
      startedAt: serializer.fromJson<DateTime>(json['startedAt']),
      durationSeconds: serializer.fromJson<int>(json['durationSeconds']),
      billedAudioSeconds: serializer.fromJson<int?>(json['billedAudioSeconds']),
      actualCost: serializer.fromJson<double?>(json['actualCost']),
      model: serializer.fromJson<String>(json['model']),
      language: serializer.fromJson<String?>(json['language']),
      status: serializer.fromJson<String>(json['status']),
      audioPath: serializer.fromJson<String?>(json['audioPath']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'startedAt': serializer.toJson<DateTime>(startedAt),
      'durationSeconds': serializer.toJson<int>(durationSeconds),
      'billedAudioSeconds': serializer.toJson<int?>(billedAudioSeconds),
      'actualCost': serializer.toJson<double?>(actualCost),
      'model': serializer.toJson<String>(model),
      'language': serializer.toJson<String?>(language),
      'status': serializer.toJson<String>(status),
      'audioPath': serializer.toJson<String?>(audioPath),
    };
  }

  Session copyWith({
    String? id,
    DateTime? startedAt,
    int? durationSeconds,
    Value<int?> billedAudioSeconds = const Value.absent(),
    Value<double?> actualCost = const Value.absent(),
    String? model,
    Value<String?> language = const Value.absent(),
    String? status,
    Value<String?> audioPath = const Value.absent(),
  }) => Session(
    id: id ?? this.id,
    startedAt: startedAt ?? this.startedAt,
    durationSeconds: durationSeconds ?? this.durationSeconds,
    billedAudioSeconds: billedAudioSeconds.present
        ? billedAudioSeconds.value
        : this.billedAudioSeconds,
    actualCost: actualCost.present ? actualCost.value : this.actualCost,
    model: model ?? this.model,
    language: language.present ? language.value : this.language,
    status: status ?? this.status,
    audioPath: audioPath.present ? audioPath.value : this.audioPath,
  );
  Session copyWithCompanion(SessionsCompanion data) {
    return Session(
      id: data.id.present ? data.id.value : this.id,
      startedAt: data.startedAt.present ? data.startedAt.value : this.startedAt,
      durationSeconds: data.durationSeconds.present
          ? data.durationSeconds.value
          : this.durationSeconds,
      billedAudioSeconds: data.billedAudioSeconds.present
          ? data.billedAudioSeconds.value
          : this.billedAudioSeconds,
      actualCost: data.actualCost.present
          ? data.actualCost.value
          : this.actualCost,
      model: data.model.present ? data.model.value : this.model,
      language: data.language.present ? data.language.value : this.language,
      status: data.status.present ? data.status.value : this.status,
      audioPath: data.audioPath.present ? data.audioPath.value : this.audioPath,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Session(')
          ..write('id: $id, ')
          ..write('startedAt: $startedAt, ')
          ..write('durationSeconds: $durationSeconds, ')
          ..write('billedAudioSeconds: $billedAudioSeconds, ')
          ..write('actualCost: $actualCost, ')
          ..write('model: $model, ')
          ..write('language: $language, ')
          ..write('status: $status, ')
          ..write('audioPath: $audioPath')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    startedAt,
    durationSeconds,
    billedAudioSeconds,
    actualCost,
    model,
    language,
    status,
    audioPath,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Session &&
          other.id == this.id &&
          other.startedAt == this.startedAt &&
          other.durationSeconds == this.durationSeconds &&
          other.billedAudioSeconds == this.billedAudioSeconds &&
          other.actualCost == this.actualCost &&
          other.model == this.model &&
          other.language == this.language &&
          other.status == this.status &&
          other.audioPath == this.audioPath);
}

class SessionsCompanion extends UpdateCompanion<Session> {
  final Value<String> id;
  final Value<DateTime> startedAt;
  final Value<int> durationSeconds;
  final Value<int?> billedAudioSeconds;
  final Value<double?> actualCost;
  final Value<String> model;
  final Value<String?> language;
  final Value<String> status;
  final Value<String?> audioPath;
  final Value<int> rowid;
  const SessionsCompanion({
    this.id = const Value.absent(),
    this.startedAt = const Value.absent(),
    this.durationSeconds = const Value.absent(),
    this.billedAudioSeconds = const Value.absent(),
    this.actualCost = const Value.absent(),
    this.model = const Value.absent(),
    this.language = const Value.absent(),
    this.status = const Value.absent(),
    this.audioPath = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SessionsCompanion.insert({
    required String id,
    required DateTime startedAt,
    required int durationSeconds,
    this.billedAudioSeconds = const Value.absent(),
    this.actualCost = const Value.absent(),
    required String model,
    this.language = const Value.absent(),
    required String status,
    this.audioPath = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       startedAt = Value(startedAt),
       durationSeconds = Value(durationSeconds),
       model = Value(model),
       status = Value(status);
  static Insertable<Session> custom({
    Expression<String>? id,
    Expression<DateTime>? startedAt,
    Expression<int>? durationSeconds,
    Expression<int>? billedAudioSeconds,
    Expression<double>? actualCost,
    Expression<String>? model,
    Expression<String>? language,
    Expression<String>? status,
    Expression<String>? audioPath,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (startedAt != null) 'started_at': startedAt,
      if (durationSeconds != null) 'duration_seconds': durationSeconds,
      if (billedAudioSeconds != null)
        'billed_audio_seconds': billedAudioSeconds,
      if (actualCost != null) 'actual_cost': actualCost,
      if (model != null) 'model': model,
      if (language != null) 'language': language,
      if (status != null) 'status': status,
      if (audioPath != null) 'audio_path': audioPath,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SessionsCompanion copyWith({
    Value<String>? id,
    Value<DateTime>? startedAt,
    Value<int>? durationSeconds,
    Value<int?>? billedAudioSeconds,
    Value<double?>? actualCost,
    Value<String>? model,
    Value<String?>? language,
    Value<String>? status,
    Value<String?>? audioPath,
    Value<int>? rowid,
  }) {
    return SessionsCompanion(
      id: id ?? this.id,
      startedAt: startedAt ?? this.startedAt,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      billedAudioSeconds: billedAudioSeconds ?? this.billedAudioSeconds,
      actualCost: actualCost ?? this.actualCost,
      model: model ?? this.model,
      language: language ?? this.language,
      status: status ?? this.status,
      audioPath: audioPath ?? this.audioPath,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (startedAt.present) {
      map['started_at'] = Variable<DateTime>(startedAt.value);
    }
    if (durationSeconds.present) {
      map['duration_seconds'] = Variable<int>(durationSeconds.value);
    }
    if (billedAudioSeconds.present) {
      map['billed_audio_seconds'] = Variable<int>(billedAudioSeconds.value);
    }
    if (actualCost.present) {
      map['actual_cost'] = Variable<double>(actualCost.value);
    }
    if (model.present) {
      map['model'] = Variable<String>(model.value);
    }
    if (language.present) {
      map['language'] = Variable<String>(language.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (audioPath.present) {
      map['audio_path'] = Variable<String>(audioPath.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SessionsCompanion(')
          ..write('id: $id, ')
          ..write('startedAt: $startedAt, ')
          ..write('durationSeconds: $durationSeconds, ')
          ..write('billedAudioSeconds: $billedAudioSeconds, ')
          ..write('actualCost: $actualCost, ')
          ..write('model: $model, ')
          ..write('language: $language, ')
          ..write('status: $status, ')
          ..write('audioPath: $audioPath, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SegmentsTable extends Segments with TableInfo<$SegmentsTable, Segment> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SegmentsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _sessionIdMeta = const VerificationMeta(
    'sessionId',
  );
  @override
  late final GeneratedColumn<String> sessionId = GeneratedColumn<String>(
    'session_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES sessions (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _speakerLabelMeta = const VerificationMeta(
    'speakerLabel',
  );
  @override
  late final GeneratedColumn<String> speakerLabel = GeneratedColumn<String>(
    'speaker_label',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _segmentTextMeta = const VerificationMeta(
    'segmentText',
  );
  @override
  late final GeneratedColumn<String> segmentText = GeneratedColumn<String>(
    'text',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _startSecondsMeta = const VerificationMeta(
    'startSeconds',
  );
  @override
  late final GeneratedColumn<double> startSeconds = GeneratedColumn<double>(
    'start_seconds',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _endSecondsMeta = const VerificationMeta(
    'endSeconds',
  );
  @override
  late final GeneratedColumn<double> endSeconds = GeneratedColumn<double>(
    'end_seconds',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _orderMeta = const VerificationMeta('order');
  @override
  late final GeneratedColumn<int> order = GeneratedColumn<int>(
    'order',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    sessionId,
    speakerLabel,
    segmentText,
    startSeconds,
    endSeconds,
    order,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'segments';
  @override
  VerificationContext validateIntegrity(
    Insertable<Segment> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('session_id')) {
      context.handle(
        _sessionIdMeta,
        sessionId.isAcceptableOrUnknown(data['session_id']!, _sessionIdMeta),
      );
    } else if (isInserting) {
      context.missing(_sessionIdMeta);
    }
    if (data.containsKey('speaker_label')) {
      context.handle(
        _speakerLabelMeta,
        speakerLabel.isAcceptableOrUnknown(
          data['speaker_label']!,
          _speakerLabelMeta,
        ),
      );
    }
    if (data.containsKey('text')) {
      context.handle(
        _segmentTextMeta,
        segmentText.isAcceptableOrUnknown(data['text']!, _segmentTextMeta),
      );
    } else if (isInserting) {
      context.missing(_segmentTextMeta);
    }
    if (data.containsKey('start_seconds')) {
      context.handle(
        _startSecondsMeta,
        startSeconds.isAcceptableOrUnknown(
          data['start_seconds']!,
          _startSecondsMeta,
        ),
      );
    }
    if (data.containsKey('end_seconds')) {
      context.handle(
        _endSecondsMeta,
        endSeconds.isAcceptableOrUnknown(data['end_seconds']!, _endSecondsMeta),
      );
    }
    if (data.containsKey('order')) {
      context.handle(
        _orderMeta,
        order.isAcceptableOrUnknown(data['order']!, _orderMeta),
      );
    } else if (isInserting) {
      context.missing(_orderMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {sessionId, order};
  @override
  Segment map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Segment(
      sessionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}session_id'],
      )!,
      speakerLabel: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}speaker_label'],
      ),
      segmentText: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}text'],
      )!,
      startSeconds: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}start_seconds'],
      ),
      endSeconds: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}end_seconds'],
      ),
      order: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}order'],
      )!,
    );
  }

  @override
  $SegmentsTable createAlias(String alias) {
    return $SegmentsTable(attachedDatabase, alias);
  }
}

class Segment extends DataClass implements Insertable<Segment> {
  /// The session this segment belongs to; deleted together with the session.
  final String sessionId;

  /// Speaker label (`speaker_1`, ...), or null when the transcript was
  /// produced without diarization.
  final String? speakerLabel;

  /// The segment text. The Dart getter is `segmentText` because a getter
  /// named `text` would clash with drift's `Table.text()` builder; the SQL
  /// column is still `text`.
  final String segmentText;

  /// Start time in seconds within the session audio, when known.
  final double? startSeconds;

  /// End time in seconds within the session audio, when known.
  final double? endSeconds;

  /// Position of the segment within the session transcript.
  final int order;
  const Segment({
    required this.sessionId,
    this.speakerLabel,
    required this.segmentText,
    this.startSeconds,
    this.endSeconds,
    required this.order,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['session_id'] = Variable<String>(sessionId);
    if (!nullToAbsent || speakerLabel != null) {
      map['speaker_label'] = Variable<String>(speakerLabel);
    }
    map['text'] = Variable<String>(segmentText);
    if (!nullToAbsent || startSeconds != null) {
      map['start_seconds'] = Variable<double>(startSeconds);
    }
    if (!nullToAbsent || endSeconds != null) {
      map['end_seconds'] = Variable<double>(endSeconds);
    }
    map['order'] = Variable<int>(order);
    return map;
  }

  SegmentsCompanion toCompanion(bool nullToAbsent) {
    return SegmentsCompanion(
      sessionId: Value(sessionId),
      speakerLabel: speakerLabel == null && nullToAbsent
          ? const Value.absent()
          : Value(speakerLabel),
      segmentText: Value(segmentText),
      startSeconds: startSeconds == null && nullToAbsent
          ? const Value.absent()
          : Value(startSeconds),
      endSeconds: endSeconds == null && nullToAbsent
          ? const Value.absent()
          : Value(endSeconds),
      order: Value(order),
    );
  }

  factory Segment.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Segment(
      sessionId: serializer.fromJson<String>(json['sessionId']),
      speakerLabel: serializer.fromJson<String?>(json['speakerLabel']),
      segmentText: serializer.fromJson<String>(json['segmentText']),
      startSeconds: serializer.fromJson<double?>(json['startSeconds']),
      endSeconds: serializer.fromJson<double?>(json['endSeconds']),
      order: serializer.fromJson<int>(json['order']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'sessionId': serializer.toJson<String>(sessionId),
      'speakerLabel': serializer.toJson<String?>(speakerLabel),
      'segmentText': serializer.toJson<String>(segmentText),
      'startSeconds': serializer.toJson<double?>(startSeconds),
      'endSeconds': serializer.toJson<double?>(endSeconds),
      'order': serializer.toJson<int>(order),
    };
  }

  Segment copyWith({
    String? sessionId,
    Value<String?> speakerLabel = const Value.absent(),
    String? segmentText,
    Value<double?> startSeconds = const Value.absent(),
    Value<double?> endSeconds = const Value.absent(),
    int? order,
  }) => Segment(
    sessionId: sessionId ?? this.sessionId,
    speakerLabel: speakerLabel.present ? speakerLabel.value : this.speakerLabel,
    segmentText: segmentText ?? this.segmentText,
    startSeconds: startSeconds.present ? startSeconds.value : this.startSeconds,
    endSeconds: endSeconds.present ? endSeconds.value : this.endSeconds,
    order: order ?? this.order,
  );
  Segment copyWithCompanion(SegmentsCompanion data) {
    return Segment(
      sessionId: data.sessionId.present ? data.sessionId.value : this.sessionId,
      speakerLabel: data.speakerLabel.present
          ? data.speakerLabel.value
          : this.speakerLabel,
      segmentText: data.segmentText.present
          ? data.segmentText.value
          : this.segmentText,
      startSeconds: data.startSeconds.present
          ? data.startSeconds.value
          : this.startSeconds,
      endSeconds: data.endSeconds.present
          ? data.endSeconds.value
          : this.endSeconds,
      order: data.order.present ? data.order.value : this.order,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Segment(')
          ..write('sessionId: $sessionId, ')
          ..write('speakerLabel: $speakerLabel, ')
          ..write('segmentText: $segmentText, ')
          ..write('startSeconds: $startSeconds, ')
          ..write('endSeconds: $endSeconds, ')
          ..write('order: $order')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    sessionId,
    speakerLabel,
    segmentText,
    startSeconds,
    endSeconds,
    order,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Segment &&
          other.sessionId == this.sessionId &&
          other.speakerLabel == this.speakerLabel &&
          other.segmentText == this.segmentText &&
          other.startSeconds == this.startSeconds &&
          other.endSeconds == this.endSeconds &&
          other.order == this.order);
}

class SegmentsCompanion extends UpdateCompanion<Segment> {
  final Value<String> sessionId;
  final Value<String?> speakerLabel;
  final Value<String> segmentText;
  final Value<double?> startSeconds;
  final Value<double?> endSeconds;
  final Value<int> order;
  final Value<int> rowid;
  const SegmentsCompanion({
    this.sessionId = const Value.absent(),
    this.speakerLabel = const Value.absent(),
    this.segmentText = const Value.absent(),
    this.startSeconds = const Value.absent(),
    this.endSeconds = const Value.absent(),
    this.order = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SegmentsCompanion.insert({
    required String sessionId,
    this.speakerLabel = const Value.absent(),
    required String segmentText,
    this.startSeconds = const Value.absent(),
    this.endSeconds = const Value.absent(),
    required int order,
    this.rowid = const Value.absent(),
  }) : sessionId = Value(sessionId),
       segmentText = Value(segmentText),
       order = Value(order);
  static Insertable<Segment> custom({
    Expression<String>? sessionId,
    Expression<String>? speakerLabel,
    Expression<String>? segmentText,
    Expression<double>? startSeconds,
    Expression<double>? endSeconds,
    Expression<int>? order,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (sessionId != null) 'session_id': sessionId,
      if (speakerLabel != null) 'speaker_label': speakerLabel,
      if (segmentText != null) 'text': segmentText,
      if (startSeconds != null) 'start_seconds': startSeconds,
      if (endSeconds != null) 'end_seconds': endSeconds,
      if (order != null) 'order': order,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SegmentsCompanion copyWith({
    Value<String>? sessionId,
    Value<String?>? speakerLabel,
    Value<String>? segmentText,
    Value<double?>? startSeconds,
    Value<double?>? endSeconds,
    Value<int>? order,
    Value<int>? rowid,
  }) {
    return SegmentsCompanion(
      sessionId: sessionId ?? this.sessionId,
      speakerLabel: speakerLabel ?? this.speakerLabel,
      segmentText: segmentText ?? this.segmentText,
      startSeconds: startSeconds ?? this.startSeconds,
      endSeconds: endSeconds ?? this.endSeconds,
      order: order ?? this.order,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (sessionId.present) {
      map['session_id'] = Variable<String>(sessionId.value);
    }
    if (speakerLabel.present) {
      map['speaker_label'] = Variable<String>(speakerLabel.value);
    }
    if (segmentText.present) {
      map['text'] = Variable<String>(segmentText.value);
    }
    if (startSeconds.present) {
      map['start_seconds'] = Variable<double>(startSeconds.value);
    }
    if (endSeconds.present) {
      map['end_seconds'] = Variable<double>(endSeconds.value);
    }
    if (order.present) {
      map['order'] = Variable<int>(order.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SegmentsCompanion(')
          ..write('sessionId: $sessionId, ')
          ..write('speakerLabel: $speakerLabel, ')
          ..write('segmentText: $segmentText, ')
          ..write('startSeconds: $startSeconds, ')
          ..write('endSeconds: $endSeconds, ')
          ..write('order: $order, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $SessionsTable sessions = $SessionsTable(this);
  late final $SegmentsTable segments = $SegmentsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [sessions, segments];
  @override
  StreamQueryUpdateRules get streamUpdateRules => const StreamQueryUpdateRules([
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'sessions',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('segments', kind: UpdateKind.delete)],
    ),
  ]);
}

typedef $$SessionsTableCreateCompanionBuilder = SessionsCompanion Function({
  required String id,
  required DateTime startedAt,
  required int durationSeconds,
  Value<int?> billedAudioSeconds,
  Value<double?> actualCost,
  required String model,
  Value<String?> language,
  required String status,
  Value<String?> audioPath,
  Value<int> rowid,
});
typedef $$SessionsTableUpdateCompanionBuilder = SessionsCompanion Function({
  Value<String> id,
  Value<DateTime> startedAt,
  Value<int> durationSeconds,
  Value<int?> billedAudioSeconds,
  Value<double?> actualCost,
  Value<String> model,
  Value<String?> language,
  Value<String> status,
  Value<String?> audioPath,
  Value<int> rowid,
});

final class $$SessionsTableReferences
    extends BaseReferences<_$AppDatabase, $SessionsTable, Session> {
  $$SessionsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$SegmentsTable, List<Segment>> _segmentsRefsTable(
    _$AppDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.segments,
    aliasName: 'sessions__id__segments__session_id',
  );

  $$SegmentsTableProcessedTableManager get segmentsRefs {
    final manager = $$SegmentsTableTableManager(
      $_db,
      $_db.segments,
    ).filter((f) => f.sessionId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_segmentsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$SessionsTableFilterComposer
    extends Composer<_$AppDatabase, $SessionsTable> {
  $$SessionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get startedAt => $composableBuilder(
    column: $table.startedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get durationSeconds => $composableBuilder(
    column: $table.durationSeconds,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get billedAudioSeconds => $composableBuilder(
    column: $table.billedAudioSeconds,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get actualCost => $composableBuilder(
    column: $table.actualCost,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get model => $composableBuilder(
    column: $table.model,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get language => $composableBuilder(
    column: $table.language,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get audioPath => $composableBuilder(
    column: $table.audioPath,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> segmentsRefs(
    Expression<bool> Function($$SegmentsTableFilterComposer f) f,
  ) {
    final $$SegmentsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.segments,
      getReferencedColumn: (t) => t.sessionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SegmentsTableFilterComposer(
            $db: $db,
            $table: $db.segments,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$SessionsTableOrderingComposer
    extends Composer<_$AppDatabase, $SessionsTable> {
  $$SessionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get startedAt => $composableBuilder(
    column: $table.startedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get durationSeconds => $composableBuilder(
    column: $table.durationSeconds,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get billedAudioSeconds => $composableBuilder(
    column: $table.billedAudioSeconds,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get actualCost => $composableBuilder(
    column: $table.actualCost,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get model => $composableBuilder(
    column: $table.model,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get language => $composableBuilder(
    column: $table.language,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get audioPath => $composableBuilder(
    column: $table.audioPath,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SessionsTableAnnotationComposer
    extends Composer<_$AppDatabase, $SessionsTable> {
  $$SessionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<DateTime> get startedAt =>
      $composableBuilder(column: $table.startedAt, builder: (column) => column);

  GeneratedColumn<int> get durationSeconds => $composableBuilder(
    column: $table.durationSeconds,
    builder: (column) => column,
  );

  GeneratedColumn<int> get billedAudioSeconds => $composableBuilder(
    column: $table.billedAudioSeconds,
    builder: (column) => column,
  );

  GeneratedColumn<double> get actualCost => $composableBuilder(
    column: $table.actualCost,
    builder: (column) => column,
  );

  GeneratedColumn<String> get model =>
      $composableBuilder(column: $table.model, builder: (column) => column);

  GeneratedColumn<String> get language =>
      $composableBuilder(column: $table.language, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get audioPath =>
      $composableBuilder(column: $table.audioPath, builder: (column) => column);

  Expression<T> segmentsRefs<T extends Object>(
    Expression<T> Function($$SegmentsTableAnnotationComposer a) f,
  ) {
    final $$SegmentsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.segments,
      getReferencedColumn: (t) => t.sessionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SegmentsTableAnnotationComposer(
            $db: $db,
            $table: $db.segments,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$SessionsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SessionsTable,
          Session,
          $$SessionsTableFilterComposer,
          $$SessionsTableOrderingComposer,
          $$SessionsTableAnnotationComposer,
          $$SessionsTableCreateCompanionBuilder,
          $$SessionsTableUpdateCompanionBuilder,
          (Session, $$SessionsTableReferences),
          Session,
          PrefetchHooks Function({bool segmentsRefs})
        > {
  $$SessionsTableTableManager(_$AppDatabase db, $SessionsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SessionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SessionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SessionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<DateTime> startedAt = const Value.absent(),
                Value<int> durationSeconds = const Value.absent(),
                Value<int?> billedAudioSeconds = const Value.absent(),
                Value<double?> actualCost = const Value.absent(),
                Value<String> model = const Value.absent(),
                Value<String?> language = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<String?> audioPath = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SessionsCompanion(
                id: id,
                startedAt: startedAt,
                durationSeconds: durationSeconds,
                billedAudioSeconds: billedAudioSeconds,
                actualCost: actualCost,
                model: model,
                language: language,
                status: status,
                audioPath: audioPath,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required DateTime startedAt,
                required int durationSeconds,
                Value<int?> billedAudioSeconds = const Value.absent(),
                Value<double?> actualCost = const Value.absent(),
                required String model,
                Value<String?> language = const Value.absent(),
                required String status,
                Value<String?> audioPath = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SessionsCompanion.insert(
                id: id,
                startedAt: startedAt,
                durationSeconds: durationSeconds,
                billedAudioSeconds: billedAudioSeconds,
                actualCost: actualCost,
                model: model,
                language: language,
                status: status,
                audioPath: audioPath,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SessionsTable, Session>(table),
                  $$SessionsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({segmentsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [if (segmentsRefs) db.segments],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (segmentsRefs)
                    await $_getPrefetchedData<Session, $SessionsTable, Segment>(
                      currentTable: table,
                      referencedTable: $$SessionsTableReferences
                          ._segmentsRefsTable(db),
                      managerFromTypedResult: (p0) =>
                          $$SessionsTableReferences(db, table, p0).segmentsRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where((e) => e.sessionId == item.id),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$SessionsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SessionsTable,
      Session,
      $$SessionsTableFilterComposer,
      $$SessionsTableOrderingComposer,
      $$SessionsTableAnnotationComposer,
      $$SessionsTableCreateCompanionBuilder,
      $$SessionsTableUpdateCompanionBuilder,
      (Session, $$SessionsTableReferences),
      Session,
      PrefetchHooks Function({bool segmentsRefs})
    >;
typedef $$SegmentsTableCreateCompanionBuilder = SegmentsCompanion Function({
  required String sessionId,
  Value<String?> speakerLabel,
  required String segmentText,
  Value<double?> startSeconds,
  Value<double?> endSeconds,
  required int order,
  Value<int> rowid,
});
typedef $$SegmentsTableUpdateCompanionBuilder = SegmentsCompanion Function({
  Value<String> sessionId,
  Value<String?> speakerLabel,
  Value<String> segmentText,
  Value<double?> startSeconds,
  Value<double?> endSeconds,
  Value<int> order,
  Value<int> rowid,
});

final class $$SegmentsTableReferences
    extends BaseReferences<_$AppDatabase, $SegmentsTable, Segment> {
  $$SegmentsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $SessionsTable _sessionIdTable(_$AppDatabase db) =>
      db.sessions.createAlias('segments__session_id__sessions__id');

  $$SessionsTableProcessedTableManager get sessionId {
    final $_column = $_itemColumn<String>('session_id')!;

    final manager = $$SessionsTableTableManager(
      $_db,
      $_db.sessions,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_sessionIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$SegmentsTableFilterComposer
    extends Composer<_$AppDatabase, $SegmentsTable> {
  $$SegmentsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get speakerLabel => $composableBuilder(
    column: $table.speakerLabel,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get segmentText => $composableBuilder(
    column: $table.segmentText,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get startSeconds => $composableBuilder(
    column: $table.startSeconds,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get endSeconds => $composableBuilder(
    column: $table.endSeconds,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get order => $composableBuilder(
    column: $table.order,
    builder: (column) => ColumnFilters(column),
  );

  $$SessionsTableFilterComposer get sessionId {
    final $$SessionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sessionId,
      referencedTable: $db.sessions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SessionsTableFilterComposer(
            $db: $db,
            $table: $db.sessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SegmentsTableOrderingComposer
    extends Composer<_$AppDatabase, $SegmentsTable> {
  $$SegmentsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get speakerLabel => $composableBuilder(
    column: $table.speakerLabel,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get segmentText => $composableBuilder(
    column: $table.segmentText,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get startSeconds => $composableBuilder(
    column: $table.startSeconds,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get endSeconds => $composableBuilder(
    column: $table.endSeconds,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get order => $composableBuilder(
    column: $table.order,
    builder: (column) => ColumnOrderings(column),
  );

  $$SessionsTableOrderingComposer get sessionId {
    final $$SessionsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sessionId,
      referencedTable: $db.sessions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SessionsTableOrderingComposer(
            $db: $db,
            $table: $db.sessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SegmentsTableAnnotationComposer
    extends Composer<_$AppDatabase, $SegmentsTable> {
  $$SegmentsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get speakerLabel => $composableBuilder(
    column: $table.speakerLabel,
    builder: (column) => column,
  );

  GeneratedColumn<String> get segmentText => $composableBuilder(
    column: $table.segmentText,
    builder: (column) => column,
  );

  GeneratedColumn<double> get startSeconds => $composableBuilder(
    column: $table.startSeconds,
    builder: (column) => column,
  );

  GeneratedColumn<double> get endSeconds => $composableBuilder(
    column: $table.endSeconds,
    builder: (column) => column,
  );

  GeneratedColumn<int> get order =>
      $composableBuilder(column: $table.order, builder: (column) => column);

  $$SessionsTableAnnotationComposer get sessionId {
    final $$SessionsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sessionId,
      referencedTable: $db.sessions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SessionsTableAnnotationComposer(
            $db: $db,
            $table: $db.sessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SegmentsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SegmentsTable,
          Segment,
          $$SegmentsTableFilterComposer,
          $$SegmentsTableOrderingComposer,
          $$SegmentsTableAnnotationComposer,
          $$SegmentsTableCreateCompanionBuilder,
          $$SegmentsTableUpdateCompanionBuilder,
          (Segment, $$SegmentsTableReferences),
          Segment,
          PrefetchHooks Function({bool sessionId})
        > {
  $$SegmentsTableTableManager(_$AppDatabase db, $SegmentsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SegmentsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SegmentsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SegmentsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> sessionId = const Value.absent(),
                Value<String?> speakerLabel = const Value.absent(),
                Value<String> segmentText = const Value.absent(),
                Value<double?> startSeconds = const Value.absent(),
                Value<double?> endSeconds = const Value.absent(),
                Value<int> order = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SegmentsCompanion(
                sessionId: sessionId,
                speakerLabel: speakerLabel,
                segmentText: segmentText,
                startSeconds: startSeconds,
                endSeconds: endSeconds,
                order: order,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String sessionId,
                Value<String?> speakerLabel = const Value.absent(),
                required String segmentText,
                Value<double?> startSeconds = const Value.absent(),
                Value<double?> endSeconds = const Value.absent(),
                required int order,
                Value<int> rowid = const Value.absent(),
              }) => SegmentsCompanion.insert(
                sessionId: sessionId,
                speakerLabel: speakerLabel,
                segmentText: segmentText,
                startSeconds: startSeconds,
                endSeconds: endSeconds,
                order: order,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SegmentsTable, Segment>(table),
                  $$SegmentsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({sessionId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (sessionId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.sessionId,
                        referencedTable: $$SegmentsTableReferences
                            ._sessionIdTable(db),
                        referencedColumn: $$SegmentsTableReferences
                            ._sessionIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$SegmentsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SegmentsTable,
      Segment,
      $$SegmentsTableFilterComposer,
      $$SegmentsTableOrderingComposer,
      $$SegmentsTableAnnotationComposer,
      $$SegmentsTableCreateCompanionBuilder,
      $$SegmentsTableUpdateCompanionBuilder,
      (Segment, $$SegmentsTableReferences),
      Segment,
      PrefetchHooks Function({bool sessionId})
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$SessionsTableTableManager get sessions =>
      $$SessionsTableTableManager(_db, _db.sessions);
  $$SegmentsTableTableManager get segments =>
      $$SegmentsTableTableManager(_db, _db.segments);
}
