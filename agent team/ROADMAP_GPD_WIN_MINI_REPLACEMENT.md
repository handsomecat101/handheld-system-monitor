# ROADMAP_GPD_WIN_MINI_REPLACEMENT.md

> Ke hoach mo rong de System Monitor Widget dong vai tro thay the Motion Assistant tren GPD Win Mini.

---

## 1) Muc tieu

- Dat muc **feature parity thuc dung** voi Motion Assistant cho nhu cau choi game hang ngay tren GPD Win Mini.
- Uu tien cac tinh nang anh huong truc tiep den FPS, nhiet do, pin va do on dinh.

---

## 2) Doi chieu theo anh Motion Assistant

| Nhom tinh nang (tu app goc) | Trang thai hien tai | Ke hoach |
|---|---|---|
| TDP preset + custom | Da co co ban | Nang cap thanh AC/DC profile rieng + quick apply |
| AC TDP / DC TDP tach rieng | Chua co | Them 2 muc TDP rieng cho cam sac va pin |
| Unify AC/DC TDP | Chua co | Them toggle dong bo profile |
| CPU Boost toggle | Chua co | Them bat/tat CPU boost theo profile |
| Auto limit TDP | Chua co | Them rule gioi han TDP theo nhiet do/pin |
| FPS Limit | Moi la profile UI | Tich hop limiter thuc (RTSS/API) + verify |
| Unify AC/DC FPS limit | Chua co | Them toggle dong bo FPS limit theo profile |
| GPU Lock (MHz) | Chua co | Them lock clock GPU min/max |
| Auto Lock GPU | Chua co | Them che do auto khoa GPU theo muc tieu hieu nang |
| Optimize GPU (Stable/Float) | Chua co | Them policy algorithm + benchmark preset |
| Custom Float GPU range | Chua co | Them min/max dynamic range |
| Fan mode co ban | Da co (Low/Medium/Max/Auto) | Nang cap fan profile nang cao |
| Fan profile Fan1..Fan4 | Chua co | Them 4 profile fan de save/load nhanh |
| Fan Curve editor + Delay | Chua co | Them curve 4 diem nhiet do + delay anti-oscillation |
| General Profile (New/Load/Del/Reset) | Chua co day du | Them CRUD profile trong app |
| Process Profile + Bind theo game | Chua co | Auto apply profile theo executable |
| Hotkeys tab | Chua co | Global hotkeys doi profile nhanh |
| Gyro Input / Gyro Simulate / Gyro Enable | Chua co | Dat sau, phase cuoi |
| RTSS OSD | Chua co | OSD overlay tuy chon cho nguoi choi game |
| Device tab / Advanced tab | Chua co | Dat sau, sau khi on dinh core controls |
| Telemetry CPU/GPU usage + Fan RPM top bar | Co mot phan | Bo sung CPU/GPU usage va fan rpm realtime ro rang |

---

## 3) Backlog uu tien (de trien khai)

| ID | Task | Priority | Status | Gia tri cho GPD Win Mini |
|---|---|---|---|---|
| MA-001 | AC/DC TDP profile + Unify AC/DC TDP | High | Done (2026-04-28) | Dung profile rieng khi cam sac va dung pin |
| MA-002 | FPS limiter thuc + Unify AC/DC FPS limit | High | Todo | Giu on dinh FPS, giam nhiet va drain |
| MA-003 | Profile Manager (New/Load/Del/Reset) | High | Done (2026-04-28) | Doi profile nhanh cho tung kich ban |
| MA-004 | Process Profile binding theo game EXE | High | Todo | Tu dong apply profile khi mo game |
| MA-005 | GPU Lock + Auto Lock + Stable/Float policy | High | Todo | Toi uu 780M cho tung game |
| MA-006 | Fan profile 1..4 + fan curve editor + delay | High | Todo | Can bang on/noise/nhiet theo so thich |
| MA-007 | CPU Boost toggle + Auto limit TDP rule | Medium | Todo | Giam spike nhiet, toi uu pin |
| MA-008 | Global hotkeys switch profile | Medium | Todo | Chuyen profile khong can mo app |
| MA-009 | RTSS OSD integration | Medium | Todo | Hien thong so trong game |
| MA-010 | Gyro modules (input/simulate/enable) | Low | Todo | Nang cao, khong phai nhu cau so 1 |
| MA-011 | Device + Advanced diagnostics tab | Low | Todo | Ho tro debug va tuong thich thiet bi |
| MA-012 | Charge limit guard 80/90/95 + desktop reminder | High | Done (2026-05-23) | Ho tro bao ve pin khi cam sac |

---

## 4) De xuat lo trinh sprint

### Sprint 1 (Core replacement)
- MA-001 AC/DC TDP profile
- MA-003 Profile Manager
- MA-004 Process Profile binding (ban dau theo ten EXE)

### Sprint 2 (Performance control)
- MA-005 GPU lock/policy
- MA-006 Fan curve + fan profiles
- MA-007 CPU boost + auto TDP rules

### Sprint 3 (Quality of life + overlay)
- MA-002 FPS limiter thuc
- MA-008 Global hotkeys
- MA-009 RTSS OSD

### Sprint 4 (Advanced parity)
- MA-010 Gyro modules
- MA-011 Device/Advanced diagnostics

---

## 5) Dinh huong thay the Motion Assistant tren GPD Win Mini

- Muc "must-have de thay the" truoc: `AC/DC profile + GPU/Fan/TDP + per-game profile`.
- Muc "nice-to-have" sau: `Gyro`, `OSD nang cao`, `Device diagnostics`.
- Luon uu tien tinh on dinh va fail-safe: neu driver/EC khong san sang thi fallback an toan, khong treo app.

---

*Cap nhat roadmap: 2026-04-28*
