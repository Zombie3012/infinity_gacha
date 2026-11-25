# Xây dựng và nâng cấp tức thì

Quy tắc hiện hành ngày 22/11/2026: **xây mới và nâng cấp công trình không có thời gian chờ**.

Cập nhật tiến độ 25/11/2026: hai tầng căn cứ và 16 ô xây dựng mở từ đầu. Điều kiện xây/sử dụng công trình được xác định bằng tầng Tháp đã vượt; xem [tiến độ Tháp](TOWER_PROGRESSION.md). Khu Cư Trú và Biệt Thự Tổ Đội là hai công trình độc lập.

- `POST /api/base/buildings` trừ bạc, tạo công trình cấp 1 ở trạng thái `READY`, kích hoạt sản xuất ngay trong cùng giao dịch.
- `POST /api/base/buildings/:id/upgrade` trừ bạc/nguyên liệu, tăng cấp và áp dụng sức chứa, năng suất cùng các hiệu ứng cấp công trình ngay. Giá và điều kiện mở khóa/cấp tối đa giữ nguyên.
- Cả hai luồng khóa ví Master và kiểm tra lại dữ liệu trong giao dịch, tránh chi vượt số dư hoặc xây trùng ô khi thao tác đồng thời.
- Tài nguyên đã sản xuất trước nâng cấp được chốt theo năng suất cấp cũ; năng suất mới chỉ tính từ lúc nâng cấp thành công.
- Công trình `CONSTRUCTING`/`UPGRADING` từ bản cũ được hoàn tất khi server đọc lại căn cứ, không phụ thuộc hạn chờ cũ và không thu thêm phí. Nhiều lần đọc đồng thời không tăng cấp lặp lại. Cột `upgradeFinishesAt` giữ để tương thích dữ liệu nhưng lệnh mới luôn trả `null`.
- Godot đã gỡ nút/bộ đếm thi công, hàm cập nhật đếm ngược, polling riêng cho thi công và thông tin số giây trong hộp nâng cấp. Thông báo thành công hiển thị đã xây/nâng cấp xong.

Các bộ đếm điều trị, sản xuất và di chuyển vẫn thuộc cơ chế riêng của chúng.

Kiểm tra có mục tiêu: `base.test.mjs`, `http.base.test.mjs`, `http.instant-buildings.test.mjs` và scene Godot `res://tests/building_instant_ui_test.tscn`. Không chạy full test hoặc `npm run verify` khi chưa được yêu cầu.
