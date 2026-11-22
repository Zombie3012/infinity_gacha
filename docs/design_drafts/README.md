# Kho thiết kế lịch sử P0–P3

Các BRD, use case, data model, acceptance criteria, scope matrix và checklist trong thư mục này là bản lưu thiết kế ở thời điểm phát triển P0–P3. Chúng được giữ để tra cứu quyết định và phạm vi ban đầu.

**Không dùng các dấu “Done”, “100%” hoặc kết quả test cũ như báo cáo trạng thái hiện tại.** Tham chiếu Web React, Unity, pity và duplicate Hero có thể đã lỗi thời.

Bản hiện hành ngày **22/11/2026 (UTC+7)**:

- [README dự án](../../README.md): kiến trúc, quy tắc gacha, cách chạy và giới hạn prototype.
- [Backlog Godot](../../GODOT_BACKLOG.md): client đã có và những luồng cần nối tiếp.
- [Combat v2](../../Combat_V2_Spec.md): cơ chế combat và phát triển Hero.
- [API inventory](../../API_Routes.md): route được sinh từ code đang chạy.

Thay đổi thay thế thiết kế cũ: client chính là Godot; Web đã gỡ; summon dùng pool theo trọng số cố định, không pity; SPECIAL dùng Gem; Hero procedural tạo instance riêng. Không có thực thể army: Hero trực tiếp tham gia expedition.

Migration SQL trong `packages/server/drizzle/` là lịch sử nâng cấp database, không phải code thừa. Không sửa/xóa migration đã áp dụng chỉ vì một cơ chế gameplay đã thay đổi.
