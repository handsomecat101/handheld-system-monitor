# AGENT_CHAT.md - Chat & Trao đổi

> Nhật ký phối hợp giữa agents/human.

---

## 2026-04-28

### 02:45 - Codex

**Loại:** @done

**Nội dung:**
Đã đọc lại toàn bộ dự án để khôi phục context bị mất lịch sử chat. Đã xác định đây là Windows PowerShell + WPF widget monitor, hiện phát triển tới bản internal `dist-hotfix16`, có đầy đủ cụm tính năng monitor + TDP/Fan/Refresh + Edge Sidebar + Tray controls.

**Files liên quan:**
- `TdpDrainWidget.ps1`
- `Launch-TdpDrainWidget.cmd`
- `README.md`
- `agent team/SOUL.md`
- `agent team/PROJECT_STATE.md`
- `agent team/ISSUE_LOG.md`

**Test:**
Chạy thành công:
`powershell -NoProfile -ExecutionPolicy Bypass -Sta -File .\TdpDrainWidget.ps1 -DumpSnapshot`

---

### 02:47 - Codex

**Loại:** @question

**Nội dung:**
Đề xuất bước tiếp theo: chốt chiến lược release (giữ `dist-hotfix*` trong repo hay chỉ giữ `dist/` + tag release), sau đó commit toàn bộ thay đổi để tránh mất trace lịch sử lần nữa.

**Files liên quan:**
- `.gitignore`
- `dist-hotfix*/`
- `scripts/Build-SystemMonitorExe.ps1`

**Test:**
N/A

---
