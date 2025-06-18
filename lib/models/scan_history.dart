class ScanHistory {
  final String productName;
  final String qrImage; // Ảnh QR code dạng base64
  final String url;
  final DateTime scannedAt;

  ScanHistory({
    required this.productName,
    required this.qrImage,
    required this.url,
    required this.scannedAt,
  });

  Map<String, dynamic> toJson() => {
        'productName': productName,
        'qrImage': qrImage,
        'url': url,
        'scannedAt': scannedAt.toIso8601String(),
      };

  factory ScanHistory.fromJson(Map<String, dynamic> json) => ScanHistory(
        productName: json['productName'] ?? '',
        qrImage: json['qrImage'] ?? '',
        url: json['url'] ?? '',
        scannedAt: DateTime.parse(json['scannedAt']),
      );
}