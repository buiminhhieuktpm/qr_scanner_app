# Hướng dẫn bật dịch vụ vị trí

## Hiện tại ứng dụng đang thông báo: "Location service disabled"

Để khắc phục vấn đề này, bạn cần bật dịch vụ vị trí trên thiết bị:

### Trên Android:
1. Mở **Cài đặt** (Settings)
2. Tìm và chọn **Vị trí** (Location) hoặc **Bảo mật & Vị trí** (Security & Location)
3. Bật công tắc **Vị trí** (Location) hoặc **Sử dụng vị trí** (Use location)
4. Đảm bảo chế độ vị trí được đặt là **Độ chính cao** (High accuracy) hoặc **Chế độ thiết bị** (Device only)

### Các cách khác:
- Kéo xuống thanh thông báo và bật biểu tượng **GPS/Vị trí**
- Vào **Cài đặt > Google > Dịch vụ vị trí** và bật các dịch vụ cần thiết

### Trong ứng dụng:
- Khi ứng dụng hiển thị dialog "Dịch vụ vị trí bị tắt", chọn **"Mở cài đặt"**
- Hoặc nhấn vào biểu tượng vị trí (📍) trong ứng dụng để kiểm tra trạng thái

### Sau khi bật:
- Ứng dụng sẽ tự động phát hiện và bắt đầu theo dõi vị trí
- Bạn sẽ thấy thông tin vị trí được in ra console mỗi 5 giây:
  ```
  === LOCATION CHECK (2025-07-04 10:30:15.123) ===
  Latitude: 21.0285
  Longitude: 105.8542
  Accuracy: 5.0 meters
  ...
  === END LOCATION CHECK ===
  ```

### Lưu ý:
- Ứng dụng cần quyền vị trí để hoạt động đúng cách
- Đảm bảo thiết bị có kết nối GPS hoặc mạng để xác định vị trí chính xác
