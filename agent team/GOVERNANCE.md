# GOVERNANCE.md - Luật & Quy Tắc

> Quy tắc chung mà TẤT CẢ agents phải tuân theo

---

## 1. Quy Tắc Chung

### 1.1 Trước Khi Bắt Đầu

| Bước | Action |
|------|--------|
| 1 | Đọc SOUL.md - Hiểu project là gì |
| 2 | Đọc PROJECT_STATE.md - Xem ai đang làm gì |
| 3 | Đọc AGENT_CHAT.md - Xem có task mới không |

### 1.2 Trong Khi Làm Việc

- ✅ **Chỉ sửa file được phép** (xem bảng Agent Roles)
- ✅ **Test trước khi deploy**
- ✅ **Cập nhật trạng thái** sau khi xong
- ✅ **Backup trước khi sửa production**

- ❌ **Không sửa file không được phép**
- ❌ **Không deploy code chưa test**
- ❌ **Không xóa data production không backup**
- ❌ **Không overwrite code của agent khác**

### 1.3 Sau Khi Xong

- ✅ **Deploy** (nếu cần)
- ✅ **Cập nhật PROJECT_STATE.md**
- ✅ **Thông báo trong AGENT_CHAT.md**
- ✅ **Git commit** với message rõ ràng

---

## 2. Agent Roles & Constraints

### Mặc định

| Agent | Vai trò | Được phép sửa | KHÔNG được sửa |
|-------|---------|---------------|-----------------|
| **Claude** | Bug fixes, Logic, Backend | script.js, *.py, *.md | style.css, index.html |
| **Gemini** | UI/UX, Design | style.css, index.html | script.js, *.py |
| **Codex** | Review, Optimization | Tat ca .js files | style.css, index.html |
| **Human** | Review, Approve | Tat ca | - |

### Thêm Agent Mới

| Agent | Vai trò | Được phép sửa | KHÔNG được sửa |
|-------|---------|---------------|-----------------|
| **[Ten]** | **[Vai tro]** | **[Files]** | **[Files]** |

### Khi Cần Sửa File Không Được Phép

1. **Xin phép** trong AGENT_CHAT.md
2. **Giải thích** lý do
3. **Chờ đồng ý** rồi mới làm

---

## 3. Git Rules

### 3.1 Khi Nào Commit

| Action | Khi nào commit |
|--------|----------------|
| Deploy code | Ngay sau khi deploy thành công |
| Fix bug | Sau khi test OK |
| UI change | Sau khi verify trên browser |

### 3.2 Commit Message Format

```
[PREFIX]: [Mo ta]

Ví dụ:
- Deploy: Fix login redirect
- Fix: Button color issue
- UI: Update dark mode colors
- Chore: Add new feature
```

### 3.3 KHÔNG Làm

| Action | Lý do |
|--------|-------|
| Commit code chưa test | Có thể break production |
| Revert không thông báo | Agent khác không biết |
| Push lên master/main | Khó rollback |
| Amend commit | Mất lịch sử |

---

## 4. Deployment Rules

### 4.1 Deploy Process

```
1. Test locally hoặc via browsing
2. [Deploy command - ví dụ: firebase deploy]
3. Verify trên browser
4. Git commit
```

### 4.2 Production Safety

**BẮT BUỘC khi làm việc với PRODUCTION:**

- [ ] Backup trước khi sửa
- [ ] Tạo branch riêng: `fix/[ten-loi]`
- [ ] Test trên staging trước
- [ ] Xin APPROVE nếu là DELETE hoặc MODIFY lớn
- [ ] Monitor sau khi deploy (5 phút)

### 4.3 Khi Deploy Lỗi

1. **Dừng** - Không push thêm code
2. **Check** - Xem lỗi gì
3. **Fix** - Sửa lỗi
4. **Re-test** - Chắc chắn chạy được
5. **Deploy lại** - Sau khi fix

### 4.4 Rollback

```bash
# Xem log
git log --oneline -5

# Rollback
git revert [commit_hash]

# Deploy lại
[Deploy command]
```

---

## 5. Communication Rules

### 5.1 Khi Nào Dùng File Nào

| File | Dùng cho |
|------|----------|
| **AGENT_CHAT.md** | Giao việc, thông báo, hỏi ý kiến |
| **ISSUE_LOG.md** | Ghi lỗi kỹ thuật + Screenshot bằng chứng |
| **PROJECT_STATE.md** | Cập nhật trạng thái task |
| **SCREENSHOTS/** | Lưu hình ảnh lỗi khi tìm thấy bằng trình duyệt |

### 5.2 Format Chat

```markdown
### [Thời gian] - [Agent]

**Loại:** @assign / @help / @done / @question

**Nội dung:**
[Mô tả]

**Files liên quan:** [file1.js]
**Test:** [Cách verify]
```

### 5.3 Format Issue

```markdown
### [Tên lỗi]

- **Mô tả:** [Chi tiết]
- **File:** [Tên file]
- **Đã thử:** [Cách đã fix / chưa fix]
- **Status:** 🔴 Open / 🟡 Fixing / ✅ Fixed
```

---

## 6. Approval Levels

### Khi Nào Cần Approval

| Level | Khi nào | Action |
|-------|---------|--------|
| **INFO** | Thay đổi nhỏ, chỉ ghi log | Tự làm |
| **CONFIRM** | Thay đổi có thể ảnh hưởng | Pause, hỏi rồi làm |
| **APPROVE** | DELETE/MODIFY production | PHẢI có approval |
| **ESCALATE** | Lỗi nghiêm trọng, data loss | Dừng ngay, báo Human |

### Approval Request Template

```markdown
### Approval Request

**Task:** [Tên task]
**Type:** [DELETE / MODIFY / DEPLOY]
**Risk:** [Thấp / Trung bình / Cao]
**Impact:** [Mô tả impact]

** Xin approve để tiếp tục **
```

---

## 7. Emergency Protocol

### Stop Conditions (Dừng NGAY lập tức)

- ❌ Policy conflict
- ❌ Backup failure
- ❌ Data loss detected
- ❌ Missing approval for critical action

### Emergency Checklist

```
1. Dừng mọi operation
2. Check GOVERNANCE.md cho stop condition
3. Tạo incident artifact (backup ref, log ref)
4. Alert Human supervisor
5. Preserve state for debugging
6. Chờ instructions
```

---

## 8. Checklist Trước Khi Deploy

- [ ] Code đã test (local/browsing)
- [ ] Không sửa file không được phép
- [ ] Backup nếu là production
- [ ] Encoding đúng (UTF-8)
- [ ] Commit message đúng format
- [ ] PROJECT_STATE.md đã cập nhật
- [ ] AGENT_CHAT.md đã thông báo

---

## 9. Vi Phạm & Hậu Quả

| Vi phạm | Hậu quả |
|---------|---------|
| Sửa file không được phép | Rollback code |
| Deploy code chưa test | Break production |
| Commit chưa deploy | Mất tracking |
| Không cập nhật trạng thái | Agent khác bị overlap |
| Xóa production không backup | Data loss - RẤT NGUY HIỂM |

---

*GOVERNANCE.md - Tất cả agents phải tuân theo*
