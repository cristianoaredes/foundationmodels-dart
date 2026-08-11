/// Human-in-the-loop interrupt registry (consume-once, TTL).
library;

enum FmInterruptDecision { approve, edit, reject }

/// A pending HITL pause.
final class FmInterrupt {
  FmInterrupt({
    required this.id,
    required this.toolName,
    required this.proposedArgs,
    required this.expiresAt,
  });

  final String id;
  final String toolName;
  final Map<String, Object?> proposedArgs;
  final DateTime expiresAt;
  bool consumed = false;
}

/// Validates edited args against prototype-pollution keys (upstream parity).
bool containsPrototypePollution(Object? value) {
  if (value is Map) {
    for (final e in value.entries) {
      final k = e.key.toString();
      if (k == '__proto__' || k == 'constructor' || k == 'prototype') {
        return true;
      }
      if (containsPrototypePollution(e.value)) return true;
    }
  } else if (value is List) {
    for (final item in value) {
      if (containsPrototypePollution(item)) return true;
    }
  }
  return false;
}

/// In-memory interrupt store: consume-once within TTL.
final class FmInterruptRegistry {
  FmInterruptRegistry({this.ttl = const Duration(minutes: 10)});

  final Duration ttl;
  final Map<String, FmInterrupt> _byId = {};
  int _seq = 0;

  /// Creates a new interrupt for [toolName]/[args].
  FmInterrupt create({
    required String toolName,
    required Map<String, Object?> proposedArgs,
  }) {
    final id = 'int_${++_seq}_${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';
    final interrupt = FmInterrupt(
      id: id,
      toolName: toolName,
      proposedArgs: Map<String, Object?>.from(proposedArgs),
      expiresAt: DateTime.now().toUtc().add(ttl),
    );
    _byId[id] = interrupt;
    return interrupt;
  }

  /// Resumes [id] with [decision]. Throws on replay, expiry, or pollution.
  Map<String, Object?> resume({
    required String id,
    required FmInterruptDecision decision,
    Map<String, Object?>? editedArgs,
  }) {
    final interrupt = _byId[id];
    if (interrupt == null) {
      throw StateError('Unknown interrupt id: $id');
    }
    if (interrupt.consumed) {
      throw StateError('Interrupt $id already consumed (replay blocked).');
    }
    if (DateTime.now().toUtc().isAfter(interrupt.expiresAt)) {
      _byId.remove(id);
      throw StateError('Interrupt $id expired.');
    }
    interrupt.consumed = true;
    _byId.remove(id);

    switch (decision) {
      case FmInterruptDecision.reject:
        throw StateError('Human rejected tool ${interrupt.toolName}');
      case FmInterruptDecision.approve:
        return interrupt.proposedArgs;
      case FmInterruptDecision.edit:
        final args = editedArgs ?? interrupt.proposedArgs;
        if (containsPrototypePollution(args)) {
          throw ArgumentError(
            'editedArgs contains forbidden prototype keys '
            '(__proto__/constructor/prototype)',
          );
        }
        return Map<String, Object?>.from(args);
    }
  }
}
