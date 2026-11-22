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
| `scenes/pve/` | Map tầng/khu vực/công trình, điều quân nhiều đội, radar và replay Combat v2 |
| `scripts/state/pve_state.gd` | Polling map, ETA theo server và lưu khóa retry qua khởi động lại |
| `tests/pve_*_test.*` | Kiểm thử engine cho UI, HTTP và phục hồi kết nối |
| `scenes/auth/`, `scenes/hub/` | Màn tài khoản và menu phụ |

Autoload: `EventBus`, `ApiClient`, `GameState`, `PveState`.

## Cửa hàng khinh khí cầu

Với hệ ma thuật, chọn **Đại Sảnh Ma Thuật** rồi bấm **Đại sảnh ma thuật** để mở cửa sổ giữa màn hình với ba tab Thư viện/Giả kim/Nghiên cứu. Tab Nghiên cứu mở công thức thuốc; tab Giả kim chế và dùng thuốc. Trong Đội hình & chiến thuật PvE, cấu hình năm ô tiêu hao mỗi Hero và chọn tự động/thủ công; trận thủ công có hạn 10 giây mỗi lượt. Xem [hướng dẫn đại sảnh](../docs/MAGIC_HALL.md) và [giả kim/PvE](../docs/ALCHEMY_PVE_CONSUMABLES.md).

Cửa sổ thương thuyền được căn giữa và co theo kích thước màn hình. Nhãn công trình trên bản đồ dùng tên tiếng Việt ngắn, chữ đậm có viền tối và dòng cấp riêng; rê chuột/chọn để xem chi tiết. Cỡ chữ giữ ổn định theo zoom, nhãn chưa chọn được ẩn khi thu quá xa để tránh chồng chữ. Thanh hành động công trình đóng khi nhấp ra ngoài, không còn nút Đóng.

Xây mới/nâng cấp mọi công trình hoàn tất ngay khi server chấp nhận và thanh toán đủ; giao diện đã bỏ bộ đếm thi công và thông tin thời gian chờ. Xem [cơ chế xây dựng tức thì](../docs/BASE_CONSTRUCTION.md).

Xây **Thương Thuyền Khinh Khí** (`SHOP_AIRSHIP`) rồi chọn **Cửa hàng**. Khinh khí cầu có mô hình bóng khí/giỏ/dây treo và chuyển động nhấp nhô. Giao diện cho tìm tên, lọc hàng, chọn số lượng và mua bằng bạc; giá tạm mọi món là **1 bạc**, không giới hạn ngày. Hàng gồm vật phẩm/nguyên liệu dùng được, trang bị và Thiên Thư thường; Ngọc hồi sinh 7★ đã mua dùng ngay tại Sử Điện. Xem [cơ chế cửa hàng](../docs/SHOP_AIRSHIP.md).

Kiểm tra Godot với API thật: `node scripts/test-godot-shop.mjs` từ gốc repo, cấu hình `GODOT_BIN` nếu cần. Kiểm tra có cả tình huống mất phản hồi sau thanh toán và gửi lại cùng giao dịch.

## Sử Điện Anh Hùng

Xây công trình `HERO_CHRONICLE` ở ô căn cứ, chọn công trình rồi mở **Sử Điện Anh Hùng**. Xem từng hồ sơ, tiểu sử và các mốc tử trận/hồi sinh; Hero tử trận không nằm trong danh sách điều trị thường. Dùng 1 **Ngọc hồi sinh 7★** để hồi sinh về 100% HP, không phí Silver. Hero và vật liệu hiển thị độ hiếm 1–7★; giữ các phương thức triệu hồi cũ. Xem [quy tắc hiện hành](../docs/HERO_CHRONICLE.md).

Kiểm tra Godot với API/PostgreSQL: `node scripts/test-godot-chronicle.mjs` từ gốc repo, cấu hình `GODOT_BIN` nếu engine chưa có trong PATH.

## Gacha

- Nhấp bất kỳ vị trí nào trong khung banner để xem chi phí/tỷ lệ rồi triệu hồi ×1 hoặc ×10; không còn nút vào banner riêng. Có hover, hỗ trợ Enter/Space và không mở nhầm khi kéo cuộn.
- NORMAL seed dùng 1 scroll/lượt, Hero 1–3★ và vật liệu.
- SPECIAL seed dùng 100 Gem/lượt, Hero 2–5★ và vật liệu; tỷ lệ 5★ là 0,4% theo pool seed.
- Không có pity. Dùng dữ liệu `rates`, `costType`, `costPerRoll` của API để hiển thị.
- Kết quả procedural tạo instance Hero riêng; xem quy tắc duplicate tại [README gốc](../README.md#quy-tắc-gacha-hiện-hành).

## PvE

Vào cổng **Chinh phạt** ở căn cứ để mở `scenes/pve/pve_map.tscn`. Tạo/chọn đội 1–5 Hero, sắp chín vị trí và chọn chiến thuật trước khi triển khai. Có tối đa ba đội và mỗi Hero cần 10 FOOD cho một lần triển khai. Di chuyển bốn hướng, một giây/ô theo server; bật/tắt auto để từng đội tự khám phá và thu tài nguyên. Auto dừng khi thua, hòa hoặc kiệt sức. Map hiển thị mô hình Hero đầu tiên còn sống của đội.

Chiến báo mở đấu trường dưới dạng replay chỉ đọc. Các đội khác tiếp tục hành quân khi xem trận. HP/MP, kỹ năng, hồi máu và hồi sinh lấy từ báo cáo Combat v2, không tạo trận demo khi API lỗi. Thưởng/tử vong đã được server lưu trước khi xem. Thắng boss kết thúc tầng và thu hồi đội sống sót; bấm vào tầng tiếp theo để tiếp tục.

Tầng mới có map tổng quan 12×12 (1 km/ô), khu vực 20×20 (50 m/ô) và công trình 8×8 (5 m/ô). Một ô tổng quan chứa được nhiều công trình nhỏ. Đứng ở cửa rồi chọn hành động qua cửa; mỗi bước ở mọi cấp vẫn mất một giây. Đường dẫn phía trên cho phép xem map cha; bấm đội để trở về khu vực đội đang đứng.

Mặc định tầng chia hết cho 5 cấm thu hồi và dùng Đá dịch chuyển tới khi hoàn thành; cấu hình từng tầng có thể ghi đè. Ở tầng thường, dùng 1 Đá dịch chuyển tại ô đội đang đứng để tạo điểm thu hồi dùng chung tới hết tầng. Đội đứng tại điểm này được thu hồi khi bị truy đuổi, nhưng không giữa trận. Nút **DEV · Reset tháp** có xác nhận, chỉ hiện trong debug khi server cho phép; quay về tầng 1 với lượt tháp mới, giữ Hero/vật phẩm/chiến báo.

Quái đi 1,5 giây/bước, phát hiện trong radar bốn ô khi không bị vật cản che, có thể đuổi qua cửa và tìm vị trí cuối khi mất dấu. Auto né quái thường, tìm chỗ khuất và chủ động đánh boss mục tiêu. Bị quái chưa nhìn thấy chạm vào sẽ gây phục kích: phía quái có pha mở màn trước hiệp 1. Khi bị truy đuổi, cần đứng tại điểm dịch chuyển trên tầng thường mới được thu hồi. Tầng cũ đang chơi giữ cơ chế map v1 tới khi hoàn thành.

Lệnh đang chờ được lưu với khóa retry, không lưu token. Khi mất kết nối hoặc mở lại game, bấm **Thử lại lệnh** để nhận lại kết quả; server không trả thưởng/trừ lương thực lần hai. Bản nháp đội hình giữ nguyên khi lưu lỗi. Hero đang triển khai bị khóa thao tác xung đột tại căn cứ.

Hero NORMAL tử trận được giữ ở mục **Tử trận** để xem lịch sử; không xuất hiện trong danh sách hoạt động. Hero SPECIAL/LIMITED 0 HP thuộc mục **Chờ hồi sinh**, cần Thần Lệ và không thể chữa bằng điều trị thường. Các bộ chọn công trình, đội hình, ăn/nghỉ, huấn luyện và trang bị chỉ cho chọn Hero còn sống; trạng thái và lựa chọn được cập nhật ngay khi có tử vong.

Từ root, đặt `GODOT_BIN` tới engine console và `DATABASE_URL` tới DB test đã migrate/seed rồi chạy:

```powershell
npm run test:godot:pve
npm run test:godot:pve -- --integration
npm run test:godot:pve -- --exploration
npm run test:godot:pve:recovery
node scripts/test-godot-medical.mjs
node scripts/test-godot-pve.mjs --lifecycle
```

Chi tiết hợp đồng và kiểm thử ở [PVE_IMPLEMENTATION.md](../docs/PVE_IMPLEMENTATION.md).

## Giới hạn hiện tại

Các API nhiệm vụ, mailbox, LiveOps, bản đồ PvP và liên minh chưa có giao diện Godot đầy đủ. Map PvE vẫn dùng balance/asset prototype; chưa có phối hợp liên đội, mục tiêu hộ tống/tìm vật phẩm hoặc morale mới.

`npm run verify` ở root kiểm tra encoding, build và test Node/TypeScript; không xác minh scene hay gameplay trong engine. Chạy project bằng Godot để kiểm tra UI, input, camera, VFX và tương tác thực tế.

Theo dõi việc còn lại trong [GODOT_BACKLOG.md](../GODOT_BACKLOG.md).
