import 'package:btox/api/toxcore/tox.dart' as toxcore;
import 'package:btox/sync/fact.dart';

extension RoleTox on Role {
  toxcore.GroupRole get tox => switch (this) {
    Role.founder => toxcore.GroupRole.founder,
    Role.moderator => toxcore.GroupRole.moderator,
    Role.user => toxcore.GroupRole.user,
    Role.observer => toxcore.GroupRole.observer,
  };
}

extension GroupRoleFact on toxcore.GroupRole {
  Role get fact => switch (this) {
    toxcore.GroupRole.founder => Role.founder,
    toxcore.GroupRole.moderator => Role.moderator,
    toxcore.GroupRole.user => Role.user,
    toxcore.GroupRole.observer => Role.observer,
  };
}

extension PrivacyTox on Privacy {
  toxcore.GroupPrivacyState get tox => switch (this) {
    Privacy.public => toxcore.GroupPrivacyState.public,
    Privacy.private => toxcore.GroupPrivacyState.private,
  };
}

extension GroupPrivacyStateFact on toxcore.GroupPrivacyState {
  Privacy get fact => switch (this) {
    toxcore.GroupPrivacyState.public => Privacy.public,
    toxcore.GroupPrivacyState.private => Privacy.private,
  };
}

extension VoiceStateTox on VoiceState {
  toxcore.GroupVoiceState get tox => switch (this) {
    VoiceState.everyone => toxcore.GroupVoiceState.all,
    VoiceState.moderators => toxcore.GroupVoiceState.moderator,
    VoiceState.founder => toxcore.GroupVoiceState.founder,
  };
}

extension GroupVoiceStateFact on toxcore.GroupVoiceState {
  VoiceState get fact => switch (this) {
    toxcore.GroupVoiceState.all => VoiceState.everyone,
    toxcore.GroupVoiceState.moderator => VoiceState.moderators,
    toxcore.GroupVoiceState.founder => VoiceState.founder,
  };
}

extension UserStatusFact on toxcore.UserStatus {
  UserStatus get fact => switch (this) {
    toxcore.UserStatus.none => UserStatus.online,
    toxcore.UserStatus.away => UserStatus.away,
    toxcore.UserStatus.busy => UserStatus.busy,
  };
}

extension ConnectionFact on toxcore.Connection {
  Connection get fact => switch (this) {
    toxcore.Connection.none => Connection.none,
    toxcore.Connection.tcp => Connection.tcp,
    toxcore.Connection.udp => Connection.udp,
  };
}
