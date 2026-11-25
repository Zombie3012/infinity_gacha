# Tiến độ Tháp và điều kiện mở khóa

Cập nhật: **25/11/2026 (UTC+7)**. Tài liệu này mô tả trạng thái đang triển khai; tham chiếu thiết kế và nhật ký cũ chỉ dùng làm lịch sử. Client và server có thể còn lưu các trường cũ để tương thích dữ liệu.

## Cách tính tiến độ

Tài khoản mới bắt đầu ở tầng Tháp 1. `worlds.current_floor` là **tầng cao nhất đã mở**, không phải tầng cao nhất đã thắng. Vượt tầng 5 mở tầng 6: `current_floor = 6`, số tầng đã vượt là `current_floor - 1 = 5`. Thắng boss cập nhật tiến độ bằng giá trị lớn hơn giữa tiến độ đã lưu và tầng vừa thắng cộng một. Có thể chọn chơi lại tầng cũ đã mở; chơi lại không làm giảm tiến độ.

| Điều kiện | Công trình, chức năng |
|---|---|
| Tạo tài khoản | Cả hai tầng căn cứ, 16 ô xây dựng; tính năng nền; Sử Điện Anh Hùng, Khu Cư Trú, Biệt Thự Tổ Đội, Nhà Kho, Khu Huấn Luyện đầu tiên, Xưởng Rèn, Bếp, Trung Tâm Hồi Phục |
| Vượt tầng 5 | Thương Thuyền Khinh Khí; mục Hầm Ngục Cổ Đại hiển thị đang phát triển, chưa thể chơi |
| Vượt tầng 10 | Đại Sảnh Ma Thuật; Khu Huấn Luyện thứ hai |
| Mỗi 10 tầng tiếp theo | Thêm một Khu Huấn Luyện: vượt tầng 20 được ba khu, vượt tầng 30 được bốn khu; tổng số thực tế còn phụ thuộc ô xây dựng |
| Vượt tầng 25 | Đại Sảnh và chức năng Liên Minh, Viễn Chinh, Cảng Tàu Bay |

Mở một loại công trình nghĩa là **được phép xây**, không tự xây miễn phí; người chơi vẫn cần ô và bạc. Công trình cũ có thể còn trên căn cứ trước mốc mới nhưng bị chặn sử dụng cho đến khi đủ điều kiện. Khu Cư Trú và Biệt Thự Tổ Đội là hai loại công trình riêng; không còn API chuyển đổi giữa chúng.

EXP và cấp Master không còn dùng trong tiến trình hoặc hiển thị trên hồ sơ. Thưởng chiến đấu vẫn có EXP Hero. Cột và dữ liệu Master cũ được giữ trong database để tương thích, không dùng để tăng cấp hay mở khóa. Kỹ năng Master hiện tại được giữ lại; thiết kế tiếp theo chưa được chốt. Cấp Hero, công trình, tàu và Liên Minh là các hệ riêng.

## API và chế độ phát triển

- `GET /api/base/overview` trả `world.currentFloor`, hai tầng căn cứ, danh mục `buildingTypes`, `requiredTowerFloor` và `maxAllowedCount`; API xây kiểm tra lại điều kiện. Các mốc theo Tháp dùng số tầng **đã vượt**.
- `/api/shop/*` yêu cầu vượt tầng 5; `/api/alchemy/*` yêu cầu vượt tầng 10; `/api/alliance/*` và các đường gameplay Viễn Chinh được bảo vệ từ sau tầng 25. Snapshot RTS trả `clearedFloor` và `requiredFloor` theo số tầng đã vượt; khi chưa mở, `base` và `chunkCenter` có thể là `null`.
- `/api/dungeon/*` hiện trả 403 trước mốc tầng 5, sau đó trả 503 với thông báo đang phát triển. Các route cũ còn trong source nhưng không phải nội dung người chơi có thể truy cập. Không nhầm Hầm Ngục Cổ Đại đang chờ thiết kế với Hầm Ngục Nổi của bản đồ Viễn Chinh.
- `POST /api/pve/dev/reset-tower` là công cụ dev/test: yêu cầu xác nhận, idempotency key, lưu trữ map cũ, giải phóng đội và đưa tiến độ về tầng 1; production từ chối. Đây không phải thao tác người chơi thông thường.

## Tài liệu liên quan

- [Xây dựng căn cứ](BASE_CONSTRUCTION.md), [Đại Sảnh Ma Thuật](MAGIC_HALL.md), [Thương Thuyền](SHOP_AIRSHIP.md).
- [PvE map và reset](PVE_IMPLEMENTATION.md), [combat](../Combat_V2_Spec.md), [API inventory](../API_Routes.md).
- [Thiết kế P0–P3](design_drafts/README.md) và `AGENT_HANDOFF_NOTES.md` là lịch sử, có thể mô tả luật đã bị thay thế.
