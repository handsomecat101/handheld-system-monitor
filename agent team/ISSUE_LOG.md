# ISSUE_LOG.md - Log lỗi

> Ghi các lỗi/điểm nghẽn đã quan sát được trong đợt rà soát.

---

## 2026-04-28

### RyzenAdj driver chưa sẵn sàng trên môi trường hiện tại

- **Mô tả:** Chạy `amd\ryzenadj.exe --info` trả về `WinRing0 Err: Driver not loaded` và `Unable to init ryzenadj`.
- **File:** `amd/ryzenadj.exe` (runtime dependency), luồng gọi trong `TdpDrainWidget.ps1`.
- **Nguyên nhân:** Thiếu quyền hoặc driver WinRing0 chưa được nạp đúng cách trên máy hiện tại.
- **Đã thử:** Gọi trực tiếp CLI từ repo root để kiểm tra nhanh.
- **Status:** 🔴 Open
- **Fix bởi:** Chưa fix (cần kiểm chứng trên máy mục tiêu + quyền phù hợp).

---

### Script test EC chứa hard-coded path máy cũ

- **Mô tả:** `test-ec.ps1` và `test-ec2.ps1` đang dùng đường dẫn tuyệt đối cũ (`c:\Users\PC\Documents\Playground\Workspaces\SystemMonitor-Widget-next\amd`), khó tái sử dụng.
- **File:** `test-ec.ps1`, `test-ec2.ps1`.
- **Nguyên nhân:** Script test được viết ad-hoc cho môi trường cục bộ.
- **Đã thử:** Rà soát nội dung script.
- **Status:** 🟡 Fixing (đã ghi nhận, chưa refactor).
- **Fix bởi:** Chưa assign.

---

### Thiếu commit history cho giai đoạn hotfix

- **Mô tả:** Git hiện chỉ có 1 commit baseline (`2026-03-23`), trong khi working tree chứa thay đổi lớn và nhiều artifact hotfix chưa commit.
- **File:** Toàn repo.
- **Nguyên nhân:** Quá trình thử nghiệm và build nội bộ chưa được commit từng bước.
- **Đã thử:** `git status --short --branch`, `git diff --stat`, `git log --oneline`.
- **Status:** 🔴 Open
- **Fix bởi:** Human + Codex (cần chốt chiến lược commit/release).

---

*ISSUE_LOG.md - Cập nhật gần nhất: 2026-04-28*

---

## 2026-05-29

### Fan control chưa ổn định trên GPD Win Mini 7840U

- **Mô tả:** Chủ dự án test các bản mới nhất và báo quạt vẫn không chạy ổn định. UI có lúc báo đã apply `Max`, `pwm 244`, nhưng RPM vẫn `0 rpm`.
- **File liên quan:** `TdpDrainWidget.ps1`, vùng fan EC control và `Enforce-FanManualHold`.
- **Backend hiện tại:** App chạy độc lập, dùng `amd\inpoutx64.dll` để đọc/ghi EC, không mượn Handheld Companion để điều khiển fan.
- **Đã thử:** Tách `Off` khỏi `Low`, tăng PWM Low/Medium/Max, giữ manual mode liên tục, thêm kickstart pulse khi RPM bằng 0.
- **Nhận định:** Có thể map EC/PWM chưa đủ cho GPD Win Mini 7840U, hoặc còn thiếu thanh ghi bật manual fan/enable fan controller. Cần so sánh EC state với Handheld Companion vì app đó từng điều khiển fan được trên máy này.
- **Status:** Open, ưu tiên cao.
- **Bước tiếp theo đề xuất:** Viết diagnostic dump EC quanh `0x0470-0x048F` trước/sau khi Handheld Companion chỉnh fan, hoặc tìm source/config Handheld Companion/NBFC/Linux GPD fan để xác nhận register đúng.

---

### Charge limit không phải tính năng thật

- **Mô tả:** Chủ dự án hỏi giới hạn sạc 80/90/95 có ngắt sạc thật không. Hiện chưa có cơ chế BIOS/EC ổn định cho GPD Win Mini 7840U để set charge threshold thật.
- **Kết luận:** Cảnh báo phần mềm không đủ giá trị, nên tính năng này đã được tắt/ẩn khỏi hướng sản phẩm.
- **Status:** Closed/Removed.
