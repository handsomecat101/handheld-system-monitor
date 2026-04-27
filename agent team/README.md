# COLLABORATION KIT - Hướng Dẫn Sử Dụng

> Folder template chuẩn để bắt đầu project với nhiều agents làm việc cùng nhau

---

## 📂 Cấu Trúc Folder

```
collaboration_kit/
├── README.md              ← Bạn đang đọc
├── SOUL.md               ← Identity: Project là gì?
├── GOVERNANCE.md         ← Luật: Quy tắc chung
├── PROJECT_STATE.md      ← Trạng thái: Ai đang làm gì?
├── AGENT_CHAT.md         ← Chat: Giao việc, trao đổi
├── ISSUE_LOG.md          ← Lỗi: Ghi lỗi đã gặp
└── QUY_TRINH.md         ← Quy trình: 5 bước làm việc
```

---

## 🚀 Cách Sử Dụng

### Bước 1: Copy Folder

```
1. Copy toàn bộ folder collaboration_kit/
2. Dán vào thư mục gốc của project
3. Đổi tên thành tên phù hợp (vd: .agent, handover, workflow...)
```

### Bước 2: Điền Thông Tin

Mở và điền thông tin vào các file:

| File | Điền gì |
|------|---------|
| **SOUL.md** | Tên project, mô tả, mục tiêu |
| **PROJECT_STATE.md** | Thành viên, task đang làm |
| **GOVERNANCE.md** | Thêm/sửa agent roles nếu cần |

### Bước 3: Bắt Đầu

```
1. Tất cả agents đọc SOUL.md + GOVERNANCE.md (lần đầu)
2. Mỗi ngày: Đọc PROJECT_STATE.md + AGENT_CHAT.md
3. Nhận task, làm việc, cập nhật trạng thái
```

---

## 📋 Quy Trình 5 Bước

```
┌────────────────────────────────────────────────────────────────┐
│  BƯỚC 1: NHẬN TASK                                           │
│  ├─ Đọc PROJECT_STATE.md                                      │
│  ├─ Đọc AGENT_CHAT.md                                         │
│  └─ Self-assign hoặc được assign                              │
├────────────────────────────────────────────────────────────────┤
│  BƯỚC 2: CHUẨN BỊ                                             │
│  ├─ Xác định files cần làm                                    │
│  ├─ Kiểm tra constraints                                      │
│  └─ Backup nếu làm production                                 │
├────────────────────────────────────────────────────────────────┤
│  BƯỚC 3: THỰC HIỆN                                           │
│  ├─ Làm việc theo task                                        │
│  ├─ Test locally                                              │
│  └─ Deploy khi ready                                         │
├────────────────────────────────────────────────────────────────┤
│  BƯỚC 4: CẬP NHẬT                                           │
│  ├─ Cập nhật PROJECT_STATE.md                                 │
│  ├─ Ghi vào AGENT_CHAT.md                                     │
│  └─ Git commit                                                │
├────────────────────────────────────────────────────────────────┤
│  BƯỚC 5: REVIEW (nếu cần)                                    │
│  ├─ Gửi cho agent review                                      │
│  └─ Fix nếu có feedback                                       │
└────────────────────────────────────────────────────────────────┘
```

---

## 👥 Thêm/Sửa Agent

### Cách 1: Sửa GOVERNANCE.md

Mở file `GOVERNANCE.md`, tìm phần "Agent Roles", thêm:

```markdown
| **[Tên Agent]** | **[Vai trò]** | **[Files được phép]** | **[Files không được]** |
```

### Cách 2: Cập nhật PROJECT_STATE.md

Thêm vào bảng "Thành viên":

```markdown
| **[Tên Agent]** | **[Vai trò]** | 🟡 Active | |
```

---

## 🔧 Ví Dụ Sử Dụng

### Ví dụ 1: Giao task

**Agent A giao task cho Agent B:**

```markdown
### 10:00 - Claude

**@assign**

**Nội dung:**
Fix bug login - user không redirect sau khi đăng nhập

**Files liên quan:** script.js, firebase-auth.js

**Test:** Thử đăng nhập bằng test account
```

### Ví dụ 2: Xin help

**Agent gặp lỗi không biết fix:**

```markdown
### 14:30 - Gemini

**@help**

**Nội dung:**
Không biết fix lỗi gì - modal không hiển thị

**Files liên quan:** style.css

**Đã thử:** Thay đổi z-index nhưng không được

**Cần:** Ý kiến từ Claude
```

### Ví dụ 3: Hoàn thành task

**Agent xong task:**

```markdown
### 16:00 - Claude

**@done**

**Nội dung:**
✅ Bug login đã fix - user được redirect về dashboard sau khi đăng nhập

**Files đã sửa:** script.js (line 45)

**Test:** Đã verify = OK
```

---

## ⚡ Quick Commands

### Giao việc
```markdown
### [Thời gian] - [Agent]

**@assign**

**Nội dung:**
[Task description]

**Files liên quan:** [file1, file2]
**Test:** [Cách test]
```

### Xin help
```markdown
### [Thời gian] - [Agent]

**@help**

**Nội dung:**
[Mô tả vấn đề]
**Đã thử:** [Cách đã thử]
**Cần:** [Yêu cầu]
```

### Hoàn thành
```markdown
### [Thời gian] - [Agent]

**@done**

**Nội dung:**
✅ [Task đã hoàn thành]
**Files đã sửa:** [files]
**Test:** [Đã verify]
```

---

## 📌 Nhắc Nhở Quan Trọng

> **MỖI NGÀY, trước khi bắt đầu làm việc:**
> 1. Đọc PROJECT_STATE.md
> 2. Đọc AGENT_CHAT.md
> 3. Xem có task mới không

> **SAU KHI HOÀN THÀNH TASK:**
> 1. Cập nhật PROJECT_STATE.md
> 2. Ghi vào AGENT_CHAT.md
> 3. Commit git

---

## 🔄 Khi Nào Cập Nhật File

| File | Khi nào cập nhật |
|------|------------------|
| **PROJECT_STATE.md** | Khi bắt đầu/kết thúc task |
| **AGENT_CHAT.md** | Khi giao việc/hỏi/help/hoàn thành |
| **ISSUE_LOG.md** | Khi gặp lỗi mới |
| **SOUL.md** | Khi thay đổi mục tiêu project |
| **GOVERNANCE.md** | Khi thay đổi quy tắc |

---

## 🆘 Khi Cần Help

| Tình huống | Action |
|------------|--------|
| Gặp lỗi không biết fix | Ghi ISSUE_LOG + hỏi trong AGENT_CHAT |
| Cần sửa file không được phép | Xin phép trong AGENT_CHAT |
| Cần approve cho production | Dừng, hỏi Human |
| Conflict với agent khác | Báo trong AGENT_CHAT |

---

## 📈 Nâng Cấp

Khi team lớn hơn, cần thêm:

- [ ] Task Envelope (JSON format)
- [ ] Lock mechanism cho production
- [ ] Parallel task distribution
- [ ] Audit trail chi tiết

→ Tham khảo COORDINATION.md (đầy đủ hơn)

---

*COLLABORATION KIT v1.0*
*Copy vào project, điền thông tin, bắt đầu làm việc!*
