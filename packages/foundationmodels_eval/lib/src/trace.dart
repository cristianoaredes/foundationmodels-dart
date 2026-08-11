/// A single generation trace record (phase 6).
class FmTraceRecord {
  /// Creates a trace record.
  const FmTraceRecord({
    required this.traceId,
    required this.requestId,
    required this.input,
    this.output,
    this.model,
    this.usage,
    this.errorCode,
    this.startedAt,
    this.endedAt,
    this.metadata = const {},
  });

  final String traceId;
  final String requestId;
  final String input;
  final String? output;
  final String? model;
  final Map<String, Object?>? usage;
  final String? errorCode;
  final DateTime? startedAt;
  final DateTime? endedAt;
  final Map<String, Object?> metadata;

  Map<String, Object?> toJson() => {
        'traceId': traceId,
        'requestId': requestId,
        'input': input,
        if (output != null) 'output': output,
        if (model != null) 'model': model,
        if (usage != null) 'usage': usage,
        if (errorCode != null) 'errorCode': errorCode,
        if (startedAt != null) 'startedAt': startedAt!.toIso8601String(),
        if (endedAt != null) 'endedAt': endedAt!.toIso8601String(),
        'metadata': metadata,
      };
}

/// In-memory trace sink.
class FmTraceSink {
  final List<FmTraceRecord> _records = [];

  /// All captured records (oldest first).
  List<FmTraceRecord> get records => List.unmodifiable(_records);

  /// Appends a record.
  void add(FmTraceRecord record) => _records.add(record);

  /// Clears the sink.
  void clear() => _records.clear();
}
