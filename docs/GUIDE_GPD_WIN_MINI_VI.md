# Hướng dẫn sử dụng - System Monitor Widget cho GPD Win Mini

![System Monitor Widget cho GPD Win Mini](images/gpd-win-mini-hero.png)

## Giới thiệu nhanh

System Monitor Widget là công cụ monitor và điều khiển nhanh cho Windows handheld. App đã được thử nghiệm trên **GPD Win Mini Ryzen 7 7840U** và được thiết kế theo nhu cầu dùng máy GPD màn hình nhỏ: xem nhanh điện năng CPU, nhiệt độ, pin, mạng, TDP và một số chế độ handheld ngay trong một cửa sổ nhỏ.

Khả năng tương thích dự kiến:

- Đã thử nghiệm trực tiếp trên GPD Win Mini dùng Ryzen 7 7840U.
- Có thể tương thích với các máy GPD khác dùng nền tảng AMD Ryzen 7840U hoặc 8840U.
- TDP và monitor cảm biến thường dễ tương thích hơn fan control.
- Fan control phụ thuộc EC của từng máy, nên vẫn cần test riêng trên từng model.

## Điểm mạnh hiện tại

- Giao diện gọn, dễ nhìn trên màn hình handheld.
- Có chế độ full/compact để dùng khi chơi game.
- Có chuyển ngôn ngữ `ENG/VIE`.
- Có điều khiển TDP nhanh qua `ryzenadj`.
- Có hiển thị battery ETA, power flow, CPU power, network speed.
- Có gyro block đơn giản: phát hiện `Available/Unavailable`, bật/tắt bằng một nút.
- Có fan profile `Off`, `Low`, `Medium`, `Max`, `Auto` để tiếp tục test thay thế Motion Assistant.

## Cách chạy nhanh

Cách khuyên dùng cho người test:

1. Tải file ZIP đầy đủ: `releases/SystemMonitor-hotfix38.zip`.
2. Giải nén ra một thư mục bình thường.
3. Double click `Run-SystemMonitor-Admin.cmd`.
4. Bấm đồng ý khi Windows hỏi quyền Administrator.

Lưu ý quan trọng: điều khiển TDP cần quyền Administrator. Nếu chỉ chạy `SystemMonitor.exe` không có quyền Admin, giao diện monitor có thể vẫn mở nhưng chỉnh TDP có thể không hoạt động.

Link tải trực tiếp:

- ZIP đầy đủ: `https://github.com/handsomecat101/handheld-system-monitor/raw/next/releases/SystemMonitor-hotfix38.zip`
- EXE riêng: `https://github.com/handsomecat101/handheld-system-monitor/raw/next/dist-hotfix38/SystemMonitor.exe`

Chạy từ source:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -Sta -File .\TdpDrainWidget.ps1
```

## Cấu hình gợi ý

Chơi nhẹ hoặc ưu tiên pin:

- TDP: 6W-8W
- Fan: Auto hoặc Low
- Refresh: 60Hz nếu cần tiết kiệm pin

Dùng cân bằng:

- TDP: 10W-12W
- Fan: Auto hoặc Medium
- Theo dõi nhiệt độ trong card CPU Power

Chơi nặng khi cắm sạc:

- TDP: 15W trở lên tùy game
- Fan: Auto hoặc Max nếu fan control hoạt động ổn trên máy của bạn
- Dừng test nếu nhiệt độ tăng nhanh mà quạt không quay

## Lưu ý quan trọng về quạt

Fan control hiện vẫn là phần cần kiểm chứng thêm trên GPD Win Mini 7840U. App có thể ghi PWM vào EC, nhưng trên máy test đã có trường hợp UI báo đã apply mà RPM vẫn là `0 rpm`.

Nếu quạt không chạy:

1. Chuyển về `Auto`.
2. Đóng app.
3. Reboot nếu máy vẫn giữ trạng thái lạ.
4. Không chơi game nặng khi nhiệt độ cao mà quạt không quay.

## Những thứ đã bỏ khỏi hướng hiện tại

- Profile manager: tạm bỏ vì làm UI rối.
- Charge limit 80/90/95: không giữ vì chưa có cách ngắt sạc thật ổn định trên GPD Win Mini 7840U; cảnh báo phần mềm không đủ giá trị.
- Sidebar mode: tạm bỏ vì từng gây lỗi không gọi cửa sổ app lên được.

## Gửi feedback

Khi gửi lỗi, nên kèm:

- Ảnh chụp app.
- Bản đang chạy, ví dụ `dist-hotfix38`.
- Máy đang cắm sạc hay dùng pin.
- TDP đang set bao nhiêu W.
- Fan đang ở mode nào và RPM hiển thị bao nhiêu.
- Game/app đang chạy nếu lỗi xảy ra khi chơi game.

## Mục tiêu dự án

Mục tiêu là tạo một widget nhẹ, dễ dùng, đã thử nghiệm trên GPD Win Mini và có khả năng tương thích với các thiết bị GPD dùng Ryzen 7840U/8840U, đủ tốt để chia sẻ cho bạn bè test và cập nhật dần qua từng bản hotfix.
