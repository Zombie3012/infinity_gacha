# Infinite Gacha — Godot client

Client chính thức đang phát triển: **3D isometric** cho căn cứ/đấu trường và **Hành tinh Fantasy 3D** cho chế độ Viễn Chinh. Cập nhật **24/11/2026 (UTC+7)**.

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
| `scripts/core/event_bus.gd` | Tín hiệu dùng chung (`graphics_quality_changed`, `world_graphics_settings_changed`, ...) |
| `scripts/core/device_profile.gd` | Tự động nhận diện thiết bị PC vs Mobile, áp guardrails Hybrid trên Mobile & mở khóa đồ họa PC |
| `scripts/core/scene_transition.gd` | Chuyển cảnh mượt kèm thông điệp trạng thái |
| `world_map/` | Hệ thống Bản Đồ Hành Tinh 3D (`PlanetCoordinates`, `PlanetRenderer`, `LocalTerrainPatch`, `PlanetFogManager`, `TacticalTerrainSplat`, `TacticalGroundProps3D`, `HorizontalMinimap`) |
| `scenes/world/` | Bản Đồ Viễn Chinh RTS (`world_rts_map.tscn`) |
| `scripts/camera/isometric_camera_rig.gd` | Camera, zoom, pan và shake |
| `scripts/actors/unit_actor_3d.gd` | Nhân vật 3D ở căn cứ (Daily Routine AI, đối thoại xã giao) và trong replay |
| `scripts/ui/` | Modal công trình, Cảng Tàu Bay, Bạn bè, Bách Khoa, Hồ sơ & Cài đặt (`player_profile_modal.gd`) |
| `scenes/base/` | Căn cứ 3D và tương tác công trình |
| `scenes/heroes/` | Hero roster, chi tiết, trang bị và thăng sao |
| `scenes/pve/` | Map tầng/khu vực/công trình, điều quân nhiều đội, radar và replay Combat v2 |
| `scripts/state/pve_state.gd` | Polling map, ETA theo server và lưu khóa retry qua khởi động lại |
| `tests/` | Kiểm thử engine cho UI, HTTP, Hành tinh 3D và phục hồi kết nối |
| `scenes/auth/`, `scenes/hub/` | Màn tài khoản và menu phụ |

Autoload: `EventBus`, `ApiClient`, `GameState`, `PveState`, `SceneTransition`.

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

## Kiến trúc UI, Màn hình chính & Các hệ thống mới (23/11/2026)

- **Thẻ & Độ hiếm 1–7★ (`rarity_style.gd`, `universal_item_card.gd`, `universal_hero_card.gd`, `item_detail_popover.gd`):**
  - Thứ tự màu chuẩn: `1★` Bạc, `2★` Xanh lá, `3★` Xanh dương, `4★` Tím, `5★` Vàng, `6★` Đỏ, `7★` viền Rainbow chuyển sắc.
  - Thẻ vật phẩm gọn `92×92` tự giãn số cột theo khung chứa; di chuột hoặc chạm mở `ItemDetailPopover` (chi tiết, nguồn gốc, chia số lượng, Dùng / Mặc / Tháo / Bỏ).
- **Tách lớp Browser dùng chung:**
  - `base_card_browser.gd`: Khung dùng chung (Header, Search, Sort, Filter Pills tự reset index về `0` khi đổi bộ lọc, Bottom Action Bar ẩn/hiện tùy chọn).
  - `card_grid_browser.gd`: Kế thừa `BaseCardBrowser`, chuyên biệt cho Hero.
  - `item_grid_browser.gd`: Kế thừa `BaseCardBrowser`, chuyên biệt cho Vật phẩm (Nhà Kho, Xưởng Rèn với bộ lọc `+15`, sắp xếp theo ★ / Số lượng / Tên / Cường hóa).
- **Nhà Kho Tổng Hợp (`gear_warehouse_modal.gd`):** Lưu trữ và hiển thị toàn bộ vật phẩm (Trang bị, Tiêu hao/Thuốc, Nguyên liệu, Sách/Phát triển, Lương thực & Thiên Thư) với 6 tab phân loại, bộ lọc riêng từng phân loại và nút thu hồi đồ rơi tầng.
- **HUD Màn hình chính (`isometric_base_3d.tscn` / `.gd`):**
  - Top-Right: 3 tài nguyên gọn (`💎 Gem`, `🪙 Bạc`, `🍖 Lương thực`) và thanh Sự Kiện thu gọn được (`🎈 Thương Thuyền`, `📜 Sự Kiện`, `✉️ Hòm Thư`).
  - Bottom-Left: 1 nút xoay vòng góc nhìn (`🏰 Tầng 1 ↻` → `👑 Tầng 2 ↻` → `🌐 Toàn Cảnh ↻`), nút `👥 Nhân Sự`, nút `💬 Chat` (3 kênh: Thế Giới, Liên Minh, Riêng Tư qua `chat_panel_modal.gd`) và thanh toast mảnh.
  - Bottom-Right: Cụm Dock (`✨ Triệu Hồi`, `🛡️ Anh Hùng`, `📦 Nhà Kho`, `🏗️ Xây Dựng` bật/tắt Build Drawer ẩn mặc định) và nút CTA `⚔️ THÁP PvE`.
- **Chế độ PvE, Sự kiện, Hòm thư & Đại Sảnh Liên Minh:**
  - `pve_mode_modal.gd` có 3 chế độ mở khóa: **Tháp PvE (`TOWER`)**, **Hầm Ngục Cổ Đại (`DUNGEON` → `ancient_dungeon_modal.gd`)**, và **Viễn Chinh Thế Giới (`EXPEDITION` → `world_expedition_modal.gd`)** (đã gỡ Chinh Phạt Lãnh Thổ).
  - `events_quests_modal.gd` (Sự Kiện LiveOps, Nhiệm Vụ, Thành Tựu) và `mailbox_modal.gd` (Hòm Thư + Sổ Giao Dịch).
  - Công trình 3D **Đại Sảnh Liên Minh (`ALLIANCE_HALL`)** mở `alliance_modal.gd` (lập hội, tìm kiếm, gia nhập, quản lý thành viên & thông báo; chưa gồm Công nghệ/Chiến tranh Liên minh).
  - Hồ sơ Master (`player_profile_modal.gd`) bổ sung tab **Bảo Mật & Tài Khoản** (định danh, mã khôi phục, đăng xuất) trong khi vẫn giữ auto-demo khi mở game để test nhanh.

## Bản Đồ Hành Tinh 3D, Viễn Chinh RTS & Đồ Họa PC/Mobile (24/11/2026)

- **Bản Đồ Hành Tinh 3D (`world_rts_map.tscn` / `world_map/`):**
  - Hành tinh Fantasy Stylized 5 lục địa + Kỳ Quan Hoàng Đế + Đại Dương (`600×300 = 180.000` ô), morph liền mạch `2D chiến thuật ↔ 3D cầu` trong ngân sách `≤ 3 Draw Calls` (`LocalTerrainPatch` 1 Draw Call ở tầm gần, `PlanetSurface + CloudLayer + AtmosphereShell` ở tầm xa).
  - Góc nghiêng chiến thuật `22°`, `TacticalTerrainSplat` phân hóa vật liệu từng ô (gồm mặt biển `OCEAN`), `TacticalGroundProps3D` (`MultiMeshInstance3D` cho Lâu Đài, Lâu Đài đối thủ, Rừng, Núi, Đồi, Phế tích, Cổng Hầm Ngục).
  - Tàu Scout / Hạm đội bay mượt **60 FPS** không có vùng chết hiển thị (`fleet_overlay_alpha` gối đầu 3D Beacons), Dirty-Hash Caching chống khựng khung hình mỗi chu kỳ poll, **0-frame lag** giữa Camera 3D & Canvas 2D.
  - Minimap ngang `2:1` hỗ trợ **nhập tọa độ `(X, Y)`** nhảy nhanh (`Enter` hoặc `➜`), nút hình cầu **`🌐`** gọn đẹp; nhấn vào bất kỳ vùng nào trong **khung Hạm đội** tự bay tới vị trí hiện tại con tàu đang di chuyển.
- **Tự động nhận diện thiết bị PC / Mobile & Cài đặt tập trung:**
  - `DeviceProfile` (`scripts/core/device_profile.gd`) tự động nhận diện nền tảng ngay khi mở game: **Mobile** khóa an toàn chế độ **Hybrid** (`R ≤ 12`, `MSAA ≤ 2x`, `FPS ≤ 60`), **PC** mở khóa toàn bộ preset tới `ULTRA` / `PLANET_WIDE` (`R = 8..32`, mật độ 3D tới `150%`, `MSAA 4x`, `FPS 240`).
  - **Quy tắc tập trung:** 100% tùy chọn cài đặt nằm trong **Avatar Master → `PlayerProfileModal` → Tab `⚙️ Cài Đặt`**. Chi tiết tại [WORLD_MAP_GRAPHICS_PC_MOBILE.md](../docs/WORLD_MAP_GRAPHICS_PC_MOBILE.md).

## Kiểm thử Headless Targeted

Từ root, đặt `GODOT_BIN` tới engine console rồi chạy từng suite mục tiêu (không chạy full suite trừ khi được yêu cầu):

```powershell
# Server & Bản Đồ Hành Tinh 3D
node scripts/test-planet-spawn-and-chunks.mjs
node scripts/test-airship-rts-api.mjs
& $env:GODOT_BIN --headless --path client-godot res://tests/test_world_planet_milestone1.tscn
& $env:GODOT_BIN --headless --path client-godot res://tests/test_world_planet_milestone2.tscn
& $env:GODOT_BIN --headless --path client-godot res://tests/test_world_planet_milestone3.tscn
& $env:GODOT_BIN --headless --path client-godot res://tests/test_world_planet_milestone5.tscn
& $env:GODOT_BIN --headless --path client-godot res://tests/test_airship_port_and_rts_map.tscn

# Các luồng Căn cứ, Gacha, Bạn bè, Bách khoa & Tài khoản
node scripts/test-godot-gacha.mjs
node scripts/test-godot-forge-warehouse.mjs
node scripts/test-godot-survival-dorm.mjs
node scripts/test-godot-hero-dev.mjs
node scripts/test-godot-events-quests.mjs
node scripts/test-godot-mailbox.mjs
node scripts/test-godot-friends.mjs
node scripts/test-godot-codex.mjs
node scripts/test-godot-alliance-building.mjs
node scripts/test-godot-chat-channels.mjs
node scripts/test-godot-auth-account.mjs
```

## Giới hạn hiện tại

Các tính năng chủ động để lại cho đợt sau gồm: Bảng xếp hạng, Công nghệ Liên minh, Chiến tranh Liên minh, tích hợp IAP store thật và gỡ auto-demo trước khi phát hành. Map PvE vẫn dùng balance/asset prototype; kiểm thử headless không thay thế việc chơi thử trực quan trên engine.

Theo dõi việc còn lại trong [GODOT_BACKLOG.md](../GODOT_BACKLOG.md).
