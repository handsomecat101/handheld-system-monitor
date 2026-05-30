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

### 03:00 - Codex

**Loại:** @done

**Nội dung:**
Đã đối chiếu screenshot Motion Assistant (app gốc GPD Win Mini) và tạo roadmap thay thế theo feature parity. Đã bổ sung backlog theo mức ưu tiên, gồm AC/DC TDP profile, GPU lock policy, fan curve, process-profile bind, hotkeys, RTSS OSD, gyro.

**Files liên quan:**
- `agent team/ROADMAP_GPD_WIN_MINI_REPLACEMENT.md`

**Test:**
N/A

---

### 03:10 - Codex

**Loai:** @done

**Noi dung:**
Da hoan thanh MA-001 trong roadmap: bo sung AC/DC TDP profile, toggle Unify AC/DC, va auto-apply TDP khi chuyen trang thai cam sac/rut sac.

**Files lien quan:**
- `TdpDrainWidget.ps1`
- `README.md`
- `agent team/ROADMAP_GPD_WIN_MINI_REPLACEMENT.md`

**Test:**
- `powershell -NoProfile -ExecutionPolicy Bypass -Sta -File .\\TdpDrainWidget.ps1 -DumpSnapshot`
- `powershell -NoProfile -ExecutionPolicy Bypass -Sta -File .\\TdpDrainWidget.ps1 -AutoCloseSeconds 2`

---

### 03:14 - Codex

**Loai:** @done

**Noi dung:**
Da hoan thanh MA-003: Profile Manager trong app (New/Save/Load/Del/Reset), luu vao `ProfileStore` trong config va cho phep doi profile nhanh ngay tren panel TDP.

**Files lien quan:**
- `TdpDrainWidget.ps1`
- `SystemMonitor.config.json` (schema moi)
- `README.md`
- `docs/GUIDE_GPD_WIN_MINI_VI.md`

**Test:**
- `powershell -NoProfile -ExecutionPolicy Bypass -Sta -File .\\TdpDrainWidget.ps1 -DumpSnapshot`
- `powershell -NoProfile -ExecutionPolicy Bypass -Sta -File .\\TdpDrainWidget.ps1 -AutoCloseSeconds 2`

---

### 03:40 - Codex

**Loai:** @done

**Noi dung:**
Da bo sung tinh nang Charge Limit Guard theo yeu cau: nguong Off/80/90/95 trong UI va thong bao desktop khi pin dat nguong trong luc dang cam sac.

**Files lien quan:**
- `TdpDrainWidget.ps1`
- `README.md`
- `docs/GUIDE_GPD_WIN_MINI_VI.md`
- `agent team/ROADMAP_GPD_WIN_MINI_REPLACEMENT.md`

**Test:**
- `powershell -NoProfile -ExecutionPolicy Bypass -Sta -File .\\TdpDrainWidget.ps1 -DumpSnapshot`
- `powershell -NoProfile -ExecutionPolicy Bypass -Sta -File .\\TdpDrainWidget.ps1 -AutoCloseSeconds 2`

---

### 12:05 - Codex

**Loai:** @done

**Noi dung:**
Da sua fan mode theo feedback: `Low` khong con la tat quat, va da them nut `Off` rieng de tat quat.

**Files lien quan:**
- `TdpDrainWidget.ps1`
- `README.md`
- `docs/GUIDE_GPD_WIN_MINI_VI.md`

**Test:**
- `powershell -NoProfile -ExecutionPolicy Bypass -Sta -File .\\TdpDrainWidget.ps1 -DumpSnapshot`
- `powershell -NoProfile -ExecutionPolicy Bypass -Sta -File .\\TdpDrainWidget.ps1 -AutoCloseSeconds 2`

---

---

## 2026-05-29

### Handoff trạng thái hiện tại - Codex

**Loại:** @handoff

**Nội dung:**
Đã rà lại trạng thái dự án sau chuỗi hotfix UI, gyro, language, graph và fan. Bản chạy mới nhất trong máy là `dist-hotfix38\SystemMonitor.exe`; launcher đã ưu tiên hotfix38. App hiện là widget PowerShell/WPF cho GPD Win Mini 7840U, có monitor realtime, TDP control, gyro On/Off, fan profile, settings show/hide block, compact/full và chuyển ngôn ngữ ENG/VIE.

**Điểm nghẽn chính:**
Fan control vẫn chưa ổn định. App ghi PWM EC được nhưng quạt vẫn có lúc 0 rpm trên máy thật. Cần ưu tiên tìm đúng register/mode control cho GPD Win Mini 7840U, tốt nhất bằng cách so sánh với Handheld Companion hoặc nguồn cộng đồng.

**Files liên quan:**
- `agent team\HANDOFF_CURRENT.md`
- `agent team\PROJECT_STATE.md`
- `agent team\ISSUE_LOG.md`
- `TdpDrainWidget.ps1`
- `Launch-TdpDrainWidget.cmd`

**Test:**
Không build/test app trong bước handoff này; chỉ cập nhật tài liệu để agent sau tiếp quản.
