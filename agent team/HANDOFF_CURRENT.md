# Handoff hiện tại - System Monitor Widget

> Cập nhật: 2026-05-29, múi giờ Asia/Saigon. File này dùng để agent khác tiếp quản dự án nhanh, tránh đọc nhầm tài liệu cũ.

## Tóm tắt dự án

- Tên dự án: `SystemMonitor-Widget-next`
- Đường dẫn workspace: `C:\ai app\SystemMonitor-Widget-next`
- Loại app: Windows desktop widget viết bằng PowerShell + WPF, đóng gói thành EXE bằng `ps2exe`.
- Mục tiêu sản phẩm: app monitor và điều khiển nhanh cho GPD Win Mini/AMD handheld, thay thế một phần Motion Assistant khi app gốc không ổn định.
- Thiết bị mục tiêu của chủ dự án: GPD Win Mini bản Ryzen 7 7840U.
- Ngôn ngữ trao đổi với chủ dự án: tiếng Việt, nói thẳng, thực dụng, ưu tiên có file EXE để test.

## Trạng thái chạy hiện tại

- Bản mới nhất trong máy: `dist-hotfix38\SystemMonitor.exe`
- Launcher hiện tại: `Launch-TdpDrainWidget.cmd`
- Launcher đang ưu tiên chạy `dist-hotfix38` trước, sau đó fallback về các hotfix cũ.
- Nhánh git hiện tại: `next`
- Remote git: `https://github.com/handsomecat101/handheld-system-monitor.git`
- Working tree đang rất bẩn, có nhiều file sửa và nhiều thư mục `dist-hotfix*` chưa track. Không push/commit nếu chưa chốt lại với chủ dự án.

## File quan trọng

- `TdpDrainWidget.ps1`: source chính của app, chứa UI WPF, monitor, TDP, gyro, fan, localization.
- `Launch-TdpDrainWidget.cmd`: launcher chọn bản EXE mới nhất để chạy.
- `scripts\Build-SystemMonitorExe.ps1`: script build EXE bằng `ps2exe`.
- `amd\ryzenadj.exe`: backend TDP.
- `amd\inpoutx64.dll`: backend đọc/ghi EC cho fan.
- `agent team\*.md`: tài liệu vận hành dự án.

## Tính năng đã có

- Monitor realtime CPU package power, CPU temp, battery, network speed.
- Card CPU Power có graph nhỏ, đã fix lỗi graph tràn khỏi card.
- Card Power Flow có graph nhỏ, đã fix lỗi graph tràn khỏi card.
- Battery ETA hiển thị pin còn lại, Wh, điện áp/dòng và ước lượng thời gian.
- TDP Control có preset `6W`, `10W`, `12W`, `Custom`, gọi `ryzenadj`.
- Custom TDP slider trong khoảng 4-25W.
- Refresh rate 60Hz/120Hz từng có trong UI, có thể bật/tắt bằng Display Settings.
- Fan Profile có `Off`, `Low`, `Medium`, `Max`, `Auto`.
- Gyro có UI đơn giản kiểu Nintendo Switch: badge `Available/Unavailable`, nút `Off/On`.
- Gyro hiển thị thiết bị là `Handheld Mode`, không ghi USB.
- Display Settings cho phép show/hide các block như TDP, Gyro, Fan, FPS, các card.
- Có nút compact/full `C`.
- Có nút pin cửa sổ.
- Có nút ngôn ngữ `ENG/VIE`, chuyển UI giữa tiếng Anh và tiếng Việt.
- UI mặc định yêu cầu của chủ dự án: full mode, không pin, nút `X` nằm ngoài cùng bên phải.

## Tính năng đã bỏ hoặc đang ẩn

- Profile manager: chủ dự án bảo bỏ/tạm ẩn vì UI rối.
- Charge limit: không còn coi là tính năng thật. Trên GPD Win Mini 7840U chưa tìm được cơ chế BIOS/EC ổn định để ngắt sạc thật ở 80/90/95%. Cảnh báo phần mềm không có giá trị nên đã tắt/ẩn hướng này.
- Sidebar mode/thu nhỏ kiểu cạnh màn hình: từng gây lỗi không gọi app lên được, đã bỏ khỏi hướng phát triển hiện tại.

## Vấn đề lớn còn mở

### Fan control chưa ổn định

- Trạng thái hiện tại: chưa đạt yêu cầu.
- App đang điều khiển fan bằng EC trực tiếp qua `inpoutx64.dll`.
- EC config trong source hiện dùng:
  - Address port: `0x4E`
  - Data port: `0x4F`
  - RPM MSB: `0x0478`
  - RPM LSB: `0x0479`
  - PWM write: `0x047A`
  - Off PWM: `1`
  - Low PWM: `92`
  - Medium PWM: `140`
  - Max PWM: `244`
- Các hotfix gần đây đã thử:
  - `Low` không còn tắt quạt.
  - Tách nút `Off` riêng.
  - Giữ manual fan mode mạnh hơn để EC không kéo về 0.
  - Khi RPM vẫn 0 thì kickstart bằng PWM max trong thời gian ngắn rồi trả về PWM đích.
- Kết quả trên máy chủ dự án: UI có lúc báo `pwm 244`, nhưng RPM vẫn `0 rpm`; quạt không chạy ổn định.
- Chủ dự án nói Handheld Companion từng điều khiển quạt được, còn Motion Assistant không ổn định.
- Kết luận kỹ thuật hiện tại: app chưa phụ thuộc Handheld Companion để chạy fan; app chạy độc lập. Nhưng map EC/PWM hiện tại có thể chưa đúng hoặc còn thiếu bước enable fan manual mode trên GPD Win Mini 7840U.

## Ưu tiên tiếp theo

1. Làm fan ổn định trước, vì máy nóng và đây là vấn đề an toàn thiết bị.
2. Tạo diagnostic so sánh EC khi Handheld Companion chỉnh quạt được:
   - Dump vùng EC quanh `0x0470-0x048F` trước/sau khi đổi fan bằng Handheld Companion.
   - Ghi lại PWM, RPM, bit mode auto/manual.
   - Không poke ngẫu nhiên nhiều thanh ghi EC ngoài vùng đã biết nếu chưa có bằng chứng.
3. Tìm nguồn tham chiếu ổn định:
   - Source/issue của Handheld Companion nếu có logic GPD Win Mini fan.
   - NBFC config cho GPD Win Mini.
   - Linux driver/script cộng đồng cho GPD Win Mini fan EC.
4. Sau khi fan ổn, build `dist-hotfix39` và cập nhật launcher lên ưu tiên bản mới.

## Lệnh build

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Build-SystemMonitorExe.ps1 -OutputPath .\dist-hotfix39\SystemMonitor.exe -Version 1.0.39.0
```

Sau build cần copy runtime dependency nếu script chưa tự copy đủ:

- `amd\ryzenadj.exe`
- `amd\inpoutx64.dll`
- `amd\WinRing0x64.dll`
- `amd\WinRing0x64.sys`
- `SystemMonitor.ico`

## Lệnh kiểm tra nhanh source

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -Sta -File .\TdpDrainWidget.ps1 -DumpSnapshot
```

Nếu app build xong double click không mở, kiểm tra lỗi PowerShell trong EXE trước. Trước đây từng lỗi vì dùng cú pháp inline `if` không hợp lệ trong PowerShell.

## Quy ước làm việc với chủ dự án

- Chủ dự án muốn mỗi bản test có folder riêng kiểu `dist-hotfixXX` để nhìn rõ bản mới nhất.
- Không push GitHub khi chủ dự án nói muốn tự chạy thử trước.
- Khi chủ dự án hỏi "bản mới nhất ở đâu", trả lời rõ folder và file EXE.
- Với UI, ưu tiên gọn, dễ bấm trên handheld, không nhồi profile hoặc option phức tạp.
- Tiếng Việt trong UI phải có dấu và dịch tự nhiên, không dịch máy từng chữ.
- Nếu một tính năng chỉ cảnh báo mà không điều khiển được phần cứng thật, nên nói rõ và bỏ nếu không đáng dùng.

## Ghi chú git/release

- Có rất nhiều artifact hotfix trong repo. Nên cân nhắc không commit tất cả EXE vào git lâu dài; tốt hơn là dùng GitHub Releases cho file EXE.
- Tuy vậy hiện chủ dự án quen test bằng folder `dist-hotfixXX`, nên chưa tự ý dọn.
- Trước khi push bản mới, cần kiểm tra lại `git status` và quyết định file nào thật sự cần stage.

