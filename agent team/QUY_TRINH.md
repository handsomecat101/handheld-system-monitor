# QUY_TRINH.md - Quy Trình Làm Việc

> 5 bước chuẩn để hoàn thành một task - TẤT CẢ agents phải tuân theo

---

## ⚠️ QUAN TRỌNG: Thế nào là 1 PHIÊN (Session)?

**1 PHIÊN = Mỗi khi bạn:**
- 🆕 Mở Claude/Gemini/Codex lên lần đầu
- 🔄 Refresh lại trang/cửa sổ
- ❌ Đóng cửa sổ rồi mở lại
- 💻 Tắt máy tính rồi bật lại
- 📱 Mở tab mới trong browser

**→ Mỗi khi bắt đầu PHIÊN MỚI → PHẢI ĐỌC CONTEXT!**

---

## 📋 Tổng Quan 6 Bước

```
┌─────────────────────────────────────────────────────────────────┐
│                    6 BƯỚC LÀM VIỆC                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  BƯỚC 0: KHỞI ĐỘNG      ⏱️ 2-3 phút (MỖI PHIÊN MỚI)     │
│  ─────────────────────────────────────────────                 │
│  □ Đọc PROJECT_STATE.md                                        │
│  □ Đọc AGENT_CHAT.md                                           │
│  □ Đọc ISSUE_LOG.md (học từ lỗi cũ)                          │
│                                                                  │
├─────────────────────────────────────────────────────────────────┤
│  BƯỚC 1: NHẬN TASK         ⏱️ 5 phút                       │
│  ─────────────────────────────────────────────                 │
│  □ Self-assign hoặc được assign                               │
│                                                                  │
├─────────────────────────────────────────────────────────────────┤
│  BƯỚC 2: CHUẨN BỊ           ⏱️ 10 phút                      │
│  ─────────────────────────────────────────────                 │
│  □ Xác định files cần làm                                      │
│  □ Kiểm tra constraints (xem Agent Roles)                     │
│  □ Đọc ISSUE_LOG.md xem có lỗi liên quan không               │
│  □ Backup nếu làm production                                   │
│                                                                  │
├─────────────────────────────────────────────────────────────────┤
│  BƯỚC 3: THỰC HIỆN           ⏱️ Tùy thuộc                   │
│  ─────────────────────────────────────────────                 │
│  □ Làm việc theo task                                         │
│  □ Test locally                                                │
│  □ Deploy khi ready                                            │
│                                                                  │
├─────────────────────────────────────────────────────────────────┤
│  BƯỚC 4: CẬP NHẬT           ⏱️ 5 phút                       │
│  ─────────────────────────────────────────────                 │
│  □ Cập nhật PROJECT_STATE.md                                   │
│  □ Ghi vào AGENT_CHAT.md                                       │
│  □ Ghi vào ISSUE_LOG.md nếu có lỗi mới                       │
│  □ Git commit                                                  │
│                                                                  │
├─────────────────────────────────────────────────────────────────┤
│  BƯỚC 5: REVIEW (nếu cần)    ⏱️ 10 phút                      │
│  ─────────────────────────────────────────────                 │
│  □ Gửi cho agent review                                        │
│  □ Fix nếu có feedback                                         │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## 🔍 Chi Tiết Từng Bước

### BƯỚC 0: KHỞI ĐỘNG (Mỗi Phiên Mới)

**Mục đích:** AI nhớ context - tránh quên như trường hợp "quên team"

**Hành động:**

```
1. Đọc PROJECT_STATE.md
   → Xem project đang ở trạng thái gì
   → Xem ai đang làm gì
   → Xem task nào đang chờ

2. Đọc AGENT_CHAT.md
   → Xem có tin nhắn mới không
   → Có task mới không

3. Đọc ISSUE_LOG.md
   → Xem các lỗi đã gặp
   → Tránh lặp lại lỗi cũ

4. Tổng hợp:
   → Cho biết project đang ở trạng thái gì
   → Nhắc nhở team cập nhật nếu cần
```

**Checklist:**
- [ ] Đã đọc PROJECT_STATE.md
- [ ] Đã đọc AGENT_CHAT.md
- [ ] Đã đọc ISSUE_LOG.md
- [ ] Đã tổng hợp context cho user

---

### BƯỚC 1: NHẬN TASK

**Mục đích:** Biết mình cần làm gì, tránh overlap

**Hành động:**

```
1. Xem task đang chờ trong PROJECT_STATE.md
2. Nhận task:
   - Self-assign: "Tôi sẽ làm task này"
   - Hoặc được assign từ agent khác / user
```

**Checklist:**
- [ ] Đã xác định task cần làm
- [ ] Đã biết files liên quan
- [ ] Đã biết deadline (nếu có)

---

### BƯỚC 2: CHUẨN BỊ

**Mục đích:** Chuẩn bị kỹ trước khi làm, tránh sai sót

**Hành động:**

```
1. Xác định files cần làm
   → List ra: file1.js, file2.css

2. Kiểm tra constraints
   → Xem GOVERNANCE.md - Agent Roles
   → Chỉ được sửa file trong danh sách "Được phép sửa"

3. Đọc ISSUE_LOG.md
   → Xem có lỗi nào liên quan đến files này không
   → Tránh lặp lại lỗi cũ

4. Backup (nếu làm production)
   → Copy file
   → Hoặc tạo branch mới: git checkout -b fix/[ten-loi]
```

**Checklist:**
- [ ] Đã xác định files cần sửa
- [ ] Đã kiểm tra được phép sửa
- [ ] Đã đọc ISSUE_LOG.md (học từ lỗi cũ)
- [ ] Đã backup (nếu production)

---

### BƯỚC 3: THỰC HIỆN

**Mục đích:** Làm task theo yêu cầu

**Hành động:**

```
1. Đọc code/files liên quan
   → Hiểu code hiện tại
   → Tìm nơi cần sửa

2. Thực hiện thay đổi
   → Sửa code
   → Thêm feature
   → Fix bug

3. Test locally
   → Chạy npm start / npm run dev
   → Test trên browser
   → Verify kết quả

4. Deploy (nếu cần)
   → Deploy lên staging/production
   → Verify sau khi deploy
```

**Checklist:**
- [ ] Đã hiểu code hiện tại
- [ ] Đã thực hiện thay đổi
- [ ] Đã test locally
- [ ] Đã deploy (nếu cần)

---

### BƯỚC 4: CẬP NHẬT

**Mục đích:** Thông báo cho team biết đã xong

**Hành động:**

```
1. Cập nhật PROJECT_STATE.md
   → Chuyển task từ "Đang Làm" sang "Hoàn Thành"
   → Cập nhật Agent status

2. Ghi vào AGENT_CHAT.md
   → Thông báo đã hoàn thành
   → Mô tả đã làm gì
   → Files đã sửa
   → Test kết quả

3. Ghi vào ISSUE_LOG.md (NẾU CÓ LỖI)
   → Ghi lỗi mới gặp phải
   → Cách đã fix / chưa fix
   → Status: 🔴 Open / 🟡 Fixing

4. Git commit
   → git add -A
   → git commit -m "[PREFIX]: [Mo ta]"
```

**Checklist:**
- [ ] PROJECT_STATE.md đã cập nhật
- [ ] AGENT_CHAT.md đã thông báo
- [ ] ISSUE_LOG.md đã ghi (nếu có lỗi)
- [ ] Git commit đã làm

---

### BƯỚC 5: REVIEW (nếu cần)

**Mục đích:** Đảm bảo code chất lượng

**Hành động:**

```
1. Gửi cho agent review
   → Codex hoặc agent khác review code

2. Nhận feedback
   → Fix nếu có suggestion
   → Giải thích nếu không đồng ý

3. Hoàn tất
   → Nếu OK → ✅ DONE
   → Nếu cần fix → Quay lại Bước 3
```

**Checklist:**
- [ ] Đã gửi review (nếu cần)
- [ ] Đã fix feedback (nếu có)
- [ ] ✅ DONE

---

## 📊 Flow Chart (Cập nhật)

```
                    ┌─────────────────┐
                    │ BƯỚC 0: KHỞI  │
                    │    ĐỘNG        │
                    │ (Mỗi phiên mới)│
                    └────────┬────────┘
                             │
         ┌───────────────────┼───────────────────┐
         ▼                   ▼                   ▼
  PROJECT_STATE      AGENT_CHAT          ISSUE_LOG
         │                   │                   │
         └───────────────────┼───────────────────┘
                             │
                             ▼
                    ┌─────────────────┐
                    │  BƯỚC 1: NHẬN  │
                    │      TASK       │
                    └────────┬────────┘
                             │
              ┌──────────────┴──────────────┐
              ▼                             ▼
        Có task                  Không có task
              │                             │
     ┌────────┴────────┐                  │
     ▼                 ▼                  ▼
Self-assign      Được assign      Check AGENT_CHAT
     │                 │                  │
     └────────┬────────┘                  │
              ▼                           │
        BƯỚC 2: CHUẨN BỊ                 │
              │                           │
              ▼                           │
        BƯỚC 3: THỰC HIỆN               │
              │                           │
              ▼                           │
        Test OK?                         │
         /    \                          │
       YES    NO                         │
       /        \                        │
       ▼          ▼                      │
  BƯỚC 4:    Sửa lại                    │
  CẬP NHẬT       │                       │
       │          └────────┬──────────────┘
       ▼                  │
  BƯỚC 5:                │
  REVIEW                  │
    │                    │
    ▼                    │
  Cần review? ──YES──► Gửi review
    │                    │
   NO                    ▼
    │               Fix feedback
    │                    │
    └────────┬───────────┘
             │
             ▼
        ✅ DONE
```

---

## 💡 Ví Dụ Thực Tế

### Tình huống: Claude fix bug login (Phiên mới)

```
BƯỚC 0: KHỞI ĐỘNG (MỞ APP LẦN ĐẦU TRONG NGÀY)
──────────────────────
Claude đọc PROJECT_STATE.md:
  → Thấy: "Task 003: Fix bug login - Agent: Claude - Status: ⏳ TODO"

Claude đọc AGENT_CHAT.md:
  → Thấy: "@Claude: Fix bug login - File: script.js - Test: thử đăng nhập"

Claude đọc ISSUE_LOG.md:
  → Thấy: "Login redirect not working - Fixed" (lỗi cũ)
  → Biết: Cẩn thận với redirect!

→ Tổng hợp: "Project đang fix bug login, đang ở 60%, lỗi cũ
   liên quan đến redirect"

BƯỚC 1: NHẬN TASK
──────────────────────
→ Claude tự assign: "Tôi sẽ làm task này"

BƯỚC 2: CHUẨN BỊ
──────────────────────
□ Files cần: script.js, firebase-auth.js
□ Constraints: Claude được sửa *.js, *.py
□ ISSUE_LOG: Thấy lỗi cũ về redirect → Cẩn thận
□ Backup: Copy script.js → script.js.backup

BƯỚC 3: THỰC HIỆN
──────────────────────
□ Đọc code script.js
□ Tìm lỗi: redirect không hoạt động
□ Fix: Thêm window.location.href = '/dashboard'
□ Test: Thử đăng nhập → OK
□ Deploy: firebase deploy --only hosting

BƯỚC 4: CẬP NHẬT
──────────────────────
□ PROJECT_STATE.md:
  Task 003 → Status: ✅ Done

□ AGENT_CHAT.md:
  "@all: ✅ Bug login đã fix, user được redirect về dashboard"

□ ISSUE_LOG.md:
  (Không cần thêm vì không có lỗi mới)

□ Git commit:
  "Fix: login redirect after successful authentication"

BƯỚC 5: REVIEW
──────────────────────
□ Gửi cho Codex review
→ Codex: "Code OK" → ✅ DONE
```

---

## ⚡ Checklist Tổng Kết

### Mỗi phiên mới (Bước 0)
- [ ] Đọc PROJECT_STATE.md
- [ ] Đọc AGENT_CHAT.md
- [ ] Đọc ISSUE_LOG.md
- [ ] Tổng hợp context

### Trước khi bắt đầu (Bước 1-2)
- [ ] Xác định task
- [ ] Xác định files cần sửa
- [ ] Kiểm tra constraints
- [ ] Đọc ISSUE_LOG.md (học từ lỗi cũ)
- [ ] Backup nếu production

### Sau khi code (Bước 3-4)
- [ ] Test locally
- [ ] Deploy (nếu cần)
- [ ] Verify kết quả
- [ ] Cập nhật PROJECT_STATE.md
- [ ] Ghi AGENT_CHAT.md
- [ ] Ghi ISSUE_LOG.md (nếu có lỗi mới)
- [ ] Git commit

### Sau khi xong (Bước 5)
- [ ] Gửi review (nếu cần)
- [ ] Fix feedback (nếu có)
- [ ] ✅ DONE

---

## 🆘 Troubleshooting

| Vấn đề | Giải pháp |
|--------|-----------|
| AI quên context | Đọc lại PROJECT_STATE + AGENT_CHAT + ISSUE_LOG |
| Không biết task là gì | Đọc lại AGENT_CHAT.md |
| Không biết file nào sửa | Xem GOVERNANCE.md - Agent Roles |
| Gặp lỗi cũ | Đọc ISSUE_LOG.md - có thể đã có cách fix |
| Cần sửa file không được phép | Xin phép trong AGENT_CHAT.md |
| Gặp lỗi mới | Ghi ISSUE_LOG.md + hỏi help |
| Bị overlap với agent khác | Báo trong AGENT_CHAT.md |

---

## 💡 NHẮC NHỞ: Mỗi Phiên Mới

```
┌─────────────────────────────────────────────────────────────────┐
│  ⚠️ NHỚ: Mỗi khi mở app/refresh/đóng mở lại                  │
│         → ĐỌC PROJECT_STATE.md + AGENT_CHAT.md + ISSUE_LOG.md │
│         → RỒI MỚI BẮT ĐẦU LÀM VIỆC                          │
└─────────────────────────────────────────────────────────────────┘
```

---

*QUY_TRINH.md - Cập nhật: Thêm Bước 0 + ISSUE_LOG*
