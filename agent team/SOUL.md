# SOUL.md - Identity & Purpose

> Định nghĩa ngắn gọn về dự án để agent mới vào có thể nắm bối cảnh ngay.

---

## Project Identity

| Field | Value |
|-------|-------|
| **Project Name** | SystemMonitor-Widget-next |
| **Type** | Tool/Utility (Windows desktop widget) |
| **Description** | Widget desktop viết bằng PowerShell + WPF để theo dõi system/battery/network và điều khiển hiệu năng thiết bị AMD handheld/laptop. |
| **Tech Stack** | PowerShell 5+, WPF (.NET), ps2exe, LibreHardwareMonitorLib, ryzenadj, inpoutx64/WinRing0 |

---

## Goals & Objectives

### Primary Goal
Tạo một widget desktop nhẹ, chạy độc lập (không phụ thuộc MotionAssistant), hiển thị trạng thái hệ thống theo thời gian thực và cho phép chỉnh TDP/fan/refresh rate nhanh.

### Success Criteria
- [x] Có widget UI chạy nền + tray icon + compact/full mode.
- [x] Đọc được battery/network/sensor snapshot theo chu kỳ refresh.
- [x] Có pipeline build ra EXE và đã có nhiều bản hotfix nội bộ.
- [ ] Hoàn thiện bước release chính thức (versioning/commit/tag phát hành).

---

## Target Users

- Người dùng Windows handheld/laptop AMD cần theo dõi drain/TDP/fan/network liên tục.
- Người dùng muốn chỉnh nhanh TDP/fan/Hz ngay từ widget nổi trên desktop.

---

## Key Features

| Feature | Priority | Status |
|---------|----------|--------|
| CPU/battery/network realtime monitor | 🔴 High | ✅ Done |
| Internet offline/restore alert + tray balloon | 🔴 High | ✅ Done |
| TDP presets + custom slider (4W-25W) qua ryzenadj | 🔴 High | ✅ Done (phụ thuộc quyền/driver máy) |
| Fan presets Low/Medium/Max/Auto qua EC | 🔴 High | ✅ Done (phụ thuộc phần cứng) |
| Refresh rate preset 60Hz/120Hz | 🟡 Medium | ✅ Done |
| Right-edge sidebar mode + auto hide | 🟡 Medium | ✅ Done |
| Startup with Windows + config persistence | 🟡 Medium | ✅ Done |
| Quy trình release sạch (commit/tag/changelog) | 🟡 Medium | ⏳ In progress |

---

## Constraints & Limitations

- **Timeline:** Code nền từ 23/03/2026, chuỗi hotfix nội bộ đến bản `dist-hotfix16` (28/03/2026, có cập nhật runtime đến 25/04/2026).
- **Budget:** Không ghi nhận ràng buộc ngân sách.
- **Dependencies:** `LibreHardwareMonitorLib.dll`, `amd/ryzenadj.exe`, `amd/inpoutx64.dll`, `WinRing0x64.*`.
- **Hardware permission:** Một số tính năng cần quyền phù hợp (driver/EC access), nếu thiếu sẽ fallback trạng thái unavailable.

---

## Important Notes

- Launcher hiện ưu tiên chạy `dist-hotfix16/SystemMonitor.exe`; nếu không có mới fallback xuống các bản cũ rồi mới chạy script source.
- Repo đang có nhiều thay đổi lớn nhưng chưa commit (bao gồm script chính, launcher, tài liệu, dist-hotfix artifacts).
- `SystemMonitor.config.json` là cấu hình local, trạng thái UI (pin/compact/sidebar/startup) được lưu tại đây.

---

*SOUL.md - Cập nhật gần nhất: 2026-04-28*
