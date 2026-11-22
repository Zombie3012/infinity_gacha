# Infinite Gacha — Godot client

Client chính thức đang phát triển: **3D isometric** cho căn cứ và đấu trường. Cập nhật **22/11/2026 (UTC+7)**.

## Mở dự án

1. Chạy backend theo [README gốc](../README.md#chạy-local), bao gồm migration và seed.
2. Trong Godot, chọn **Import** và mở `client-godot/project.godot` từ checkout hiện tại.
3. Project hiện khai báo **Godot 4.7 / Forward Plus**, viewport 1280×720.
4. Bấm **F5**. Scene khởi động là `scenes/base/isometric_base_3d.tscn`.

API mặc định: `http://127.0.0.1:3000`. Thay `base_url` trong `scripts/network/api_client.gd` khi backend chạy ở địa chỉ khác.

Scene căn cứ hiện tự đăng nhập/đăng ký tài khoản phát triển `demo` qua `GameState.ensure_demo_session()`. Các giá trị ví/cấp ban đầu trong singleton có dữ liệu mẫu trước khi đồng bộ API; cần hoàn thiện luồng này trước phát hành.

## Các phần chính

| Đường dẫn | Vai trò |
|---|---|
| `scripts/network/api_client.gd` | HTTP bất đồng bộ, Bearer token và xử lý response |
| `scripts/state/game_state.gd` | Đồng bộ Master, Hero, ví, đội hình và căn cứ |
| `scripts/core/event_bus.gd` | Tín hiệu dùng chung |
| `scripts/camera/isometric_camera_rig.gd` | Camera, zoom, pan và shake |
| `scripts/actors/unit_actor_3d.gd` | Nhân vật 3D ở căn cứ và trong replay |
| `scripts/ui/` | Modal công trình, Hero/item card, hồ sơ và gacha |
| `scenes/base/` | Căn cứ 3D và tương tác công trình |
| `scenes/heroes/` | Hero roster, chi tiết, trang bị và thăng sao |
| `scenes/pve/` | Map riêng 12×12, điều quân nhiều đội và replay Combat v2 đã lưu |
| `scripts/state/pve_state.gd` | Polling map, ETA theo server và lưu khóa retry qua khởi động lại |
| `tests/pve_*_test.*` | Kiểm thử engine cho UI, HTTP và phục hồi kết nối |
| `scenes/auth/`, `scenes/hub/` | Màn tài khoản và menu phụ |

Autoload: `EventBus`, `ApiClient`, `GameState`, `PveState`.

## Gacha

- Modal chọn banner theo hàng ngang, xem chi phí/tỷ lệ rồi triệu hồi ×1 hoặc ×10.
- NORMAL seed dùng 1 scroll/lượt, Hero 1–3★ và vật liệu.
- SPECIAL seed dùng 100 Gem/lượt, Hero 2–5★ và vật liệu; tỷ lệ 5★ là 0,4% theo pool seed.
- Không có pity. Dùng dữ liệu `rates`, `costType`, `costPerRoll` của API để hiển thị.
- Kết quả procedural tạo instance Hero riêng; xem quy tắc duplicate tại [README gốc](../README.md#quy-tắc-gacha-hiện-hành).

## PvE

Vào cổng **Chinh phạt** ở căn cứ để mở `scenes/pve/pve_map.tscn`. Tạo/chọn đội 1–5 Hero, sắp chín vị trí và chọn chiến thuật trước khi triển khai. Có tối đa ba đội và mỗi Hero cần 10 FOOD cho một lần triển khai. Di chuyển bốn hướng, một giây/ô theo server; bật/tắt auto để từng đội tự khám phá và thu tài nguyên. Auto dừng khi thua, hòa hoặc kiệt sức. Map hiển thị mô hình Hero đầu tiên còn sống của đội.

Chiến báo mở đấu trường dưới dạng replay chỉ đọc. Các đội khác tiếp tục hành quân khi xem trận. HP/MP, kỹ năng, hồi máu và hồi sinh lấy từ báo cáo Combat v2, không tạo trận demo khi API lỗi. Thưởng/tử vong đã được server lưu trước khi xem. Thắng boss kết thúc tầng và thu hồi đội sống sót; bấm vào tầng tiếp theo để tiếp tục.

Lệnh đang chờ được lưu với khóa retry, không lưu token. Khi mất kết nối hoặc mở lại game, bấm **Thử lại lệnh** để nhận lại kết quả; server không trả thưởng/trừ lương thực lần hai. Bản nháp đội hình giữ nguyên khi lưu lỗi. Hero đang triển khai bị khóa thao tác xung đột tại căn cứ.

Từ root, đặt `GODOT_BIN` tới engine console và `DATABASE_URL` tới DB test đã migrate/seed rồi chạy:

```powershell
npm run test:godot:pve
npm run test:godot:pve -- --integration
npm run test:godot:pve:recovery
```

Chi tiết hợp đồng và kiểm thử ở [PVE_IMPLEMENTATION.md](../docs/PVE_IMPLEMENTATION.md).

## Giới hạn hiện tại

Các API nhiệm vụ, mailbox, LiveOps, bản đồ PvP và liên minh chưa có giao diện Godot đầy đủ. Map PvE vẫn dùng balance/asset prototype; chưa có phối hợp liên đội, phục kích hoặc morale mới.

`npm run verify` ở root kiểm tra encoding, build và test Node/TypeScript; không xác minh scene hay gameplay trong engine. Chạy project bằng Godot để kiểm tra UI, input, camera, VFX và tương tác thực tế.

Theo dõi việc còn lại trong [GODOT_BACKLOG.md](../GODOT_BACKLOG.md).
