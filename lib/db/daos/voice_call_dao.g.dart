// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'voice_call_dao.dart';

// ignore_for_file: type=lint
mixin _$VoiceCallDaoMixin on DatabaseAccessor<AppDatabase> {
  $VoiceCallSessionsTable get voiceCallSessions =>
      attachedDatabase.voiceCallSessions;
  $VoiceCallMessagesTable get voiceCallMessages =>
      attachedDatabase.voiceCallMessages;
  VoiceCallDaoManager get managers => VoiceCallDaoManager(this);
}

class VoiceCallDaoManager {
  final _$VoiceCallDaoMixin _db;
  VoiceCallDaoManager(this._db);
  $$VoiceCallSessionsTableTableManager get voiceCallSessions =>
      $$VoiceCallSessionsTableTableManager(
          _db.attachedDatabase, _db.voiceCallSessions);
  $$VoiceCallMessagesTableTableManager get voiceCallMessages =>
      $$VoiceCallMessagesTableTableManager(
          _db.attachedDatabase, _db.voiceCallMessages);
}
