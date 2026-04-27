# PROJECT_STATE.md - Trạng Thái Project

> Bản snapshot trạng thái dự án tại thời điểm khôi phục context.

---

## Project Info

| Field | Value |
|-------|-------|
| **Project Name** | SystemMonitor-Widget-next |
| **Ngày bắt đầu** | 2026-03-23 (theo commit baseline) |
| **Ngày dự kiến hoàn thành** | Chưa chốt (đang ở mức release candidate nội bộ) |
| **Trạng thái** | 🟡 Active |

## URLs (nếu có)

| Service | URL |
|---------|-----|
| **Production** | N/A (desktop app local) |
| **Staging** | N/A |
| **Backend API** | N/A |
| **Firebase Console** | N/A |

---

## Thành Viên

| Agent | Vai trò | Status | Ghi chú |
|-------|---------|--------|---------|
| **Human** | Product owner, test trên máy thật, approve release | 👤 Available | |
| **Codex** | Code audit, tổng hợp trạng thái, cập nhật tài liệu | 🟡 Active | Đã đọc code + cập nhật hồ sơ 2026-04-28 |

---

## Task Đang Làm

| ID | Task | Agent | Priority | Status | Deadline |
|----|------|-------|----------|--------|----------|
| 101 | Chốt release strategy (commit/tag cho hotfix16) | Human + Codex | 🔴 HIGH | 🟡 In Progress | TBD |
| 102 | Verify TDP/Fan control trên máy mục tiêu với quyền driver phù hợp | Human | 🔴 HIGH | 🟡 In Progress | TBD |

---

## Task Chờ

| ID | Task | Agent | Priority | Ghi chú |
|----|------|-------|----------|---------|
| 103 | Dọn artifact build trong repo (`dist-hotfix*`) theo chính sách release | - | 🟡 MEDIUM | Cần quyết định giữ hay tách thành release package |
| 104 | Bổ sung smoke-test/checklist vận hành sau build EXE | - | 🟡 MEDIUM | Hiện chưa có test automation |
| 105 | Chuẩn hóa script test EC để bỏ hard-coded path | - | ⚪ LOW | `test-ec*.ps1` đang trỏ path máy cũ |

---

## Task Hoàn Thành

| ID | Task | Agent | Ngày hoàn thành | Ghi chú |
|----|------|-------|-----------------|---------|
| 001 | Widget monitor cơ bản (CPU/battery/network/tray) | Historical | 2026-03-23 | Có trong baseline ban đầu |
| 002 | Thêm TDP/Fan/Refresh controls và UI panel liên quan | Historical | 2026-03-26 | Mở rộng lớn trong `TdpDrainWidget.ps1` |
| 003 | Thêm edge sidebar mode + internet notification flow | Historical | 2026-03-26 | Có logic auto-hide và alert state |
| 004 | Build nhiều bản internal hotfix đến `dist-hotfix16` | Historical | 2026-03-28 | Launcher ưu tiên bản mới nhất |
| 005 | Cập nhật bộ tài liệu `agent team` theo trạng thái thực tế | Codex | 2026-04-28 | Hoàn tất khôi phục context |

---

## Recent Activity

### 2026-04-28

| Thời gian | Agent | Action |
|-----------|-------|--------|
| 02:30 | Codex | Rà soát toàn bộ cấu trúc repo + script chính |
| 02:37 | Codex | Chạy `-DumpSnapshot` xác nhận app còn xuất dữ liệu runtime |
| 02:45 | Codex | Điền lại `SOUL.md`, `PROJECT_STATE.md`, `AGENT_CHAT.md`, `ISSUE_LOG.md` |

### 2026-03-24 -> 2026-03-28

| Thời gian | Agent | Action |
|-----------|-------|--------|
| Nhiều mốc | Historical | Build liên tiếp các bản `dist-hotfix`, bản mới nhất là `dist-hotfix16` |

---

## Blockers / Issues

| Issue | Agent | Status | Ghi chú |
|-------|-------|--------|---------|
| `ryzenadj --info` lỗi `Driver not loaded` trên môi trường hiện tại | Human | 🔴 Open | Cần test với quyền/driver đúng máy mục tiêu |
| Chưa có commit lịch sử cho toàn bộ thay đổi hậu-baseline | Human + Codex | 🔴 Open | Khó truy vết nếu rollback |

---

## Notes

- Nhánh hiện tại: `next` (trùng `main/stable` ở commit cũ), còn nhiều thay đổi chưa commit.
- `Launch-TdpDrainWidget.cmd` đã ưu tiên `dist-hotfix16\SystemMonitor.exe`.
- `README.md` đã cập nhật mô tả các tính năng mới (fan/TDP custom/refresh/sidebar).

---

*PROJECT_STATE.md - Cập nhật gần nhất: 2026-04-28*
