# Thương Thuyền Khinh Khí

Cập nhật 25/11/2026 (UTC+7). Công trình `SHOP_AIRSHIP` là cửa hàng dạng **khinh khí cầu neo tại căn cứ**: bóng khí, giỏ hàng, dây treo và chuyển động nhấp nhô. Sau khi vượt tầng Tháp 5, mở danh mục xây dựng để xây công trình, sau đó chọn **Cửa hàng** trên thanh hành động.

- Mở sau khi vượt Tháp tầng 5, một cấp công trình, không cần nhân sự; giá xây mẫu 1.000 bạc.
- **Giá bán tạm thời: 1 bạc mỗi món**, gồm Ngọc hồi sinh 7★, Đá dịch chuyển, thuốc điều trị, thức ăn, sách EXP, nguyên liệu phát triển/chế tạo, trang bị và Thiên Thư thường.
- Không giới hạn ngày hoặc xoay vòng ngày bán trong catalog tạm này. Mỗi lệnh mua 1–99 món. Admin vẫn có thể cấu hình giá và giới hạn cho từng mặt hàng; khi tạo hàng mới mà không nhập giá, mặc định là 1 bạc.
- Không bán Thần Lệ đã ngừng dùng, vật phẩm rác hoặc Bình Thể Lực chưa có logic sử dụng. Không thêm Gem hay Hero vào danh mục vật phẩm bán.
- Vật phẩm/nguyên liệu hiện độ hiếm 1–7★; có tìm theo tên, lọc theo loại hàng, mô tả, đơn giá, số lượng và tổng tiền.
- Cửa sổ căn giữa màn hình, có lề cân hai bên và điều chỉnh kích thước theo viewport.

## Nhận hàng và thanh toán

Server khóa ví Master, kiểm tra số dư hiện tại, trừ bạc và giao hàng trong cùng giao dịch. Không chi vượt số dư khi gửi nhiều lệnh đồng thời. Lỗi giao hàng hủy cả lần trừ tiền.

- Vật phẩm/nguyên liệu vào `master_items`.
- Trang bị tạo instance thật trong `equipment_instances`, trạng thái `INVENTORY`; không tạo bản vật liệu giả trong túi. Cấp ghép/cường hóa ban đầu giống trang bị mới chế tạo.
- Thiên Thư thường vào `master_summon_inventory`, dùng được ngay cho triệu hồi.
- Số dư, kho và trang bị được tải lại sau khi mua. Ngọc hồi sinh mua tại đây xuất hiện trong Sử Điện Anh Hùng và vẫn hồi sinh đầy HP, không phí thêm.

`POST /api/shop/purchase` nhận `{itemCode, quantity}` và hỗ trợ header `Idempotency-Key`. Cùng Master, cùng key và cùng nội dung trả lại biên nhận đã lưu, không trừ bạc/giao hàng/tính tiến độ chi tiêu lần nữa. Đổi nội dung với cùng key bị từ chối 409. Client giữ key khi chưa nhận được kết quả và cho bấm **Kiểm tra lại giao dịch**; không tự tạo lần mua mới cho lần thử lại đó. Các client cũ chưa gửi key vẫn được hỗ trợ.

Các endpoint `GET /api/shop`, `GET /api/shop/items/:code` và `POST /api/shop/purchase` yêu cầu vượt Tháp tầng 5; chưa yêu cầu phải xây công trình. API quản trị shop có xác thực riêng.

## Dữ liệu và kiểm chứng

Migration `0054` thêm công trình, biên nhận `shop_purchases`, giá mặc định và danh mục tạm. Migration `0055` loại Bình Thể Lực chưa dùng được. Seed cũng được cập nhật để cơ sở dữ liệu mới nhận cùng danh mục. Catalog shop lấy vật phẩm đang hoạt động từ `item_templates` và trang bị từ `equipment_templates`; không đổi sao, kho hoặc ví sẵn có của người chơi.

Kiểm tra có mục tiêu:

```powershell
node --test --test-concurrency=1 packages/server/tests/http.airship-shop.test.mjs packages/server/tests/shop.test.mjs
node scripts/test-godot-shop.mjs
```

Runner Godot dùng PostgreSQL/API thật và proxy cố ý ngắt phản hồi sau khi server đã chốt mua, để xác nhận thử lại không trả tiền hai lần. Đặt `GODOT_BIN` nếu engine chưa nằm trong PATH. Kiểm tra headless xác minh logic giao diện và mô hình chạy trong engine; chưa thay thế kiểm tra hình ảnh thủ công.

Không chạy full test hoặc `npm run verify` khi chưa được yêu cầu.
