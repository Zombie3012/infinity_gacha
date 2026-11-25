# Kho thiết kế lịch sử P0–P3

Các BRD, use case, data model, acceptance criteria, scope matrix và checklist trong thư mục này là bản lưu thiết kế ở thời điểm phát triển P0–P3. Chúng được giữ để tra cứu quyết định và phạm vi ban đầu.

**Không dùng các dấu “Done”, “100%”, quy tắc hoặc kết quả test trong thư mục này như trạng thái hiện tại.** Các bản dự thảo từng mô tả EXP/cấp Master, điểm kỹ năng, Hầm Ngục và điều kiện mở khác hiện hành; tham chiếu Web React, Unity, pity và duplicate Hero cũng có thể đã lỗi thời.

Nguồn hiện hành để đối chiếu:

- [README dự án](../../README.md): kiến trúc, quy tắc gacha, cách chạy và giới hạn prototype.
- [Tiến độ Tháp](../TOWER_PROGRESSION.md): quy tắc mở khóa, căn cứ, EXP Master và Hầm Ngục hiện tại.
- [Backlog Godot](../../GODOT_BACKLOG.md): client đã có và những luồng cần nối tiếp.
- [Combat v2](../../Combat_V2_Spec.md): cơ chế combat và phát triển Hero.
- [API inventory](../../API_Routes.md): route được sinh từ code đang chạy.

Thay đổi thay thế thiết kế cũ: client chính là Godot; Web đã gỡ; summon dùng pool theo trọng số cố định, không pity; SPECIAL dùng Gem; Hero procedural tạo instance riêng. Không có thực thể army: Hero trực tiếp tham gia expedition.

Migration SQL trong `packages/server/drizzle/` là lịch sử nâng cấp database, không phải code thừa. Không sửa/xóa migration đã áp dụng chỉ vì một cơ chế gameplay đã thay đổi.
