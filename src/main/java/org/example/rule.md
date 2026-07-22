1. Tổng hợp kiến thức theo phương pháp trả lời các câu hỏi
    - What – Nó là gì?
    - How – Nó có những đặc điểm gì?
    - How – Nó hoạt động như nào?
    - Why – Tại sao cần nó?
    - Components – Gồm những thành phần gì?
    - When – Khi nào nên dùng?
    - Compare – So sánh với cái khác?
    - Trade-offs?
    - Real-world usage (Production)
    - Ghi chú(Các thuộc tính, thành phần, keyword vừa đề cập đến làm chủ đề cho tổng hợp kiến thức tiếp theo)
Ví dụ như trong file resource\Tổng hợp kiến thức Lập trình.xlsx
2. Tổng hợp theo từng topic và lưu lại mục lục đã tổng hợp vàomootjt file roadmap.md
ví dụ như topic về java thì tạo một file tổng hợp kiến thức riêng và một file roadmap riêng trong package đó
3. Tổng hợp kiến thức như một chuyên gia thực thụ có chứng chỉ master

---

# 4. QUY ƯỚC GIẢI THÍCH DỄ HIỂU (bắt buộc cho mọi file kiến thức)

Mục tiêu: giữ nguyên độ sâu chuyên môn, nhưng bổ sung lớp giải thích để người mới cũng đọc hiểu. **Không xóa nội dung chuyên sâu — chỉ thêm lớp dễ hiểu bên cạnh.** Dùng tiếng Việt.

Áp dụng đồng thời 4 lớp sau:

### Lớp 1 — Chú thích thuật ngữ tại chỗ (in-place gloss)
Lần **đầu tiên** một thuật ngữ tiếng Anh xuất hiện trong file → thêm nghĩa tiếng Việt trong ngoặc *(in nghiêng)*. Giữ nguyên thuật ngữ gốc vì đó là ngôn ngữ thực tế khi làm việc.
```
Ví dụ: **stop-the-world** *(tạm dừng toàn bộ ứng dụng để dọn rác)*
```

### Lớp 2 — Callout "Giải thích dễ hiểu" + ví von đời thực
Sau mỗi đoạn/cơ chế khó, chèn block callout giữ nguyên nội dung gốc, thêm lớp bình dân kèm **ví von đời thực (analogy)**:
```
> 💡 **Giải thích dễ hiểu:**
> [Diễn giải lại bằng ngôn ngữ đời thường + một ví von quen thuộc]
```

### Lớp 3 — Viết lại đoạn quá súc tích
Những câu nhồi nhét nhiều khái niệm → tách câu, diễn giải lại rõ ràng. Làm có chọn lọc, chỉ ở chỗ thật khó hiểu.

### Lớp 4 — File `glossary.md` mỗi package
Mỗi package có 1 file `glossary.md`: bảng thuật ngữ (Thuật ngữ | Nghĩa tiếng Việt | Giải thích ngắn), sắp xếp A-Z, để tra cứu nhanh. Thêm link tới glossary ở đầu mỗi file kiến thức.

### Nguyên tắc chung
- Giải thích **như đang dạy cho người chưa biết gì** về chủ đề đó, nhưng không hạ thấp độ chính xác.
- Ưu tiên ví von đời thực (nhà hàng, kho bãi, giao thông, thư viện...) cho các cơ chế trừu tượng.
- Không lạm dụng callout — chỉ chèn ở khái niệm thực sự khó, tránh làm loãng file.