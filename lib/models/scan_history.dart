class ScanHistory {
  final String content;
  final DateTime timestamp;

  ScanHistory({required this.content, required this.timestamp});

  Map<String, dynamic> toJson() => {
        'content': content,
        'timestamp': timestamp.toIso8601String(),
      };

  factory ScanHistory.fromJson(Map<String, dynamic> json) => ScanHistory(
        content: json['content'],
        timestamp: DateTime.parse(json['timestamp']),
      );
}