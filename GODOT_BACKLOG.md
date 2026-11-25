# Godot client: trạng thái và backlog

Cập nhật: **25/11/2026 (UTC+7)**. Checklist và kết quả kiểm thử ghi thời điểm triển khai, không bảo đảm vẫn đi qua sau các thay đổi sau đó. Quy tắc hiện hành: [tiến độ Tháp](docs/TOWER_PROGRESSION.md); checklist thiết kế P0–P3 là tài liệu lịch sử.

## Đã có trong code

- Căn cứ 3D isometric, camera, tương tác ô đất/công trình, xây/nâng cấp tức thì, 3 slot Layout Presets, Thu hoạch tất cả thông minh, phân công đa nhân sự & giải phóng nhân sự.
- Đời sống Hero 3D tự chủ (`Hero Daily Routine AI`), đối thoại xã giao 2 chiều (`hero_dialogue_bank.gd`), tương tác trực tiếp (`HeroQuickInteractPopup`), nhịp sinh hoạt Ngày/Hoàng hôn/Đêm và đồng bộ Tính cách/Tâm trạng/Loyalty.
- HUD màn hình chính gọn: Top-Right 3 tài nguyên + thanh Sự Kiện (`Thương Thuyền`, `Sự Kiện`, `Hòm Thư`, `Bạn Bè`) kèm chấm đỏ thông báo (Red-Dot), hàng đợi Toast mượt, nút xoay vòng góc nhìn T1/T2/Toàn cảnh, Build Drawer ẩn mặc định và Bottom-Right Dock + CTA `Tháp PvE`.
- Hệ thống thẻ dùng chung 1–7★ (`RarityStyle` + viền Rainbow 7★), thẻ vật phẩm `92×92` + `ItemDetailPopover`, 3 lớp browser (`BaseCardBrowser` phân trang + debounce `0.15s`, `CardGridBrowser`, `ItemGridBrowser`) và `SummonResultModal` lật thẻ Gacha tối đa 5★.
- Bản Đồ Hành Tinh 3D Viễn Chinh RTS (`world_rts_map.tscn` + `world_map/`): hành tinh `600×300 = 180.000` ô gồm 5 lục địa + Đại Dương (`OCEAN`), RTS Smart Random Spawn, Chunk Streaming, Cảng Tàu Bay (`AIRSHIP_PORT` + Tech Tree + Dock Grid), morph 2D↔3D (`≤ 3 Draw Calls`), cảnh quan 3D `MultiMesh`, sương mù mây mềm 1h, tàu bay 60 FPS không dead-zone, nhập tọa độ Minimap `(X, Y)` + nút hình cầu `🌐`, và nhấn hộp Hạm đội nhảy thẳng theo tàu.
- Tự động nhận diện thiết bị PC vs Mobile (`DeviceProfile`): Mobile khóa an toàn **Hybrid**, PC mở khóa toàn bộ preset & thanh trượt đồ họa trong **Avatar Master → Tab `⚙️ Cài Đặt`** (`player_profile_modal.gd`, `docs/WORLD_MAP_GRAPHICS_PC_MOBILE.md`).
- Hệ thống Bạn bè (`FriendsModal`), Bách Khoa Toàn Thư 4 tab (`CodexModal`), Liên Minh (`ALLIANCE_HALL` + `AllianceModal`), Chat 3 kênh Real-Time SSE (`ChatPanelModal`), Sự Kiện/Nhiệm Vụ/Thành Tựu (`EventsQuestsModal`) và Hòm Thư/Sổ Giao Dịch (`MailboxModal`).
- Đấu trường PvE (Auto/Thủ công 10s/lượt, 5 ô thuốc/Hero, Floating Damage/Crit/Heal/Revive Numbers) với diễn hoạt replay, tốc độ phát và dynamic camera.
- REST client, cấu hình `user://client_config.json`, `export_presets.cfg` cho Windows Desktop, và đồng bộ profile/Hero/căn cứ/trang bị/đội hình.

## PvE đã triển khai

- [x] Map PvE riêng 12×12, fog, tài nguyên, boss và ba đội hoạt động độc lập qua `/api/pve`.
- [x] Tạo/sửa party 1–5 Hero, xếp vị trí 0–8 và đặt ưu tiên mục tiêu/thứ tự kỹ năng.
- [x] Di chuyển 1 giây/ô bằng thời gian server, ETA và polling khoảng một giây khi mở map/replay; bật/tắt tự khám phá từng đội.
- [x] Tự giao chiến và quyết toán một lần; hiển thị chiến báo, thưởng và đồng bộ Hero/tài nguyên/tầng.
- [x] Replay đọc báo cáo đã lưu, gồm HP/MP, heal, crit và revive; không còn simulation/fallback demo trong luồng này.
- [x] Phục hồi lệnh chưa xác nhận sau mất phản hồi hoặc khởi động lại; giữ bản nháp đội hình khi lỗi.
- [x] Hero triển khai được đánh dấu và loại khỏi chọn nhân sự/trang bị tại căn cứ.
- [x] Kiểm thử headless bằng Godot thật và HTTP/PostgreSQL; có ca đổi tài khoản và khởi động lại cả API/client.

PvE dùng map và encounter riêng theo đội, tái sử dụng Combat v2. Luồng combat session cũ được giữ để tương thích; `/api/dungeon/*` bị chặn và Hầm Ngục Cổ Đại đang chờ thiết kế mới. Không còn kế hoạch nối đấu trường vào luồng đánh từng phòng. Bằng chứng và giới hạn kiểm thử ở [PVE_IMPLEMENTATION.md](docs/PVE_IMPLEMENTATION.md).

## Ưu tiên 1: chơi thử và cân bằng PvE

- [ ] Chơi thử có hình bằng đội Hero thực tế; đánh giá độ khó, thời gian hạ địch, chữa trị và nhịp tài nguyên.
- [ ] Đánh giá camera, hiệu ứng, âm thanh, chuột/phím và kích thước màn hình mục tiêu. Các kiểm thử headless không xác nhận chất lượng trực quan.
- [ ] Thay các hình khối/asset prototype khi có bộ đồ họa thống nhất.

## Ưu tiên 2: hoàn thiện các luồng đã có UI

- [x] Kiểm thử gacha NORMAL dùng scroll và SPECIAL dùng 100 Gem/lượt, lịch sử summon, đổi Thiên Thư, refresh ví, thiếu tài nguyên (`scripts/test-godot-gacha.mjs`).
- [x] Kiểm thử toàn luồng xây/nâng cấp tức thì, rèn/cường hóa/ghép đồ/thu hồi đồ rơi, ăn/nghỉ/hồi phục (`scripts/test-godot-forge-warehouse.mjs`, `scripts/test-godot-survival-dorm.mjs`, `scripts/test-godot-medical.mjs`).
- [x] Kiểm thử Hero bị khóa, chết, đang đi expedition, phôi thăng sao và thay trang bị (`hero_lifecycle_ui_test.tscn`, `scripts/test-godot-hero-dev.mjs`, `scripts/test-godot-world-expedition.mjs`).
- [x] Rà soát thao tác ấn ký, chọn kỹ năng thức tỉnh và thông báo điều kiện chưa đủ (`scripts/test-godot-magic-hall.mjs`, `scripts/test-godot-hero-dev.mjs`).
- [ ] Kiểm tra trực quan layout, resize, input, tooltip và phản hồi lỗi trong engine (chơi thử có hình).

Gacha hiện không có pity. Banner seed NORMAL ra 1–3★, SPECIAL ra 2–5★; Hero procedural luôn sinh instance riêng. Quy tắc đầy đủ ở [README](README.md#quy-tắc-gacha-hiện-hành).

## Ưu tiên 3: đưa các API còn lại lên Godot

- [x] Nhiệm vụ, thành tựu, shop (`SHOP_AIRSHIP`) và hòm thư (`EventsQuestsModal`, `MailboxModal`, `scripts/test-godot-events-quests.mjs`, `scripts/test-godot-mailbox.mjs`).
- [x] LiveOps & mission sự kiện (`EventsQuestsModal`); Bảng xếp hạng chủ động để lại cho đợt sau.
- [ ] Thiết kế và triển khai Hầm Ngục Cổ Đại mới; mục hiện tại chỉ thông báo đang phát triển. Viễn Chinh dùng `world_rts_map.tscn` sau khi vượt tầng 25.
- [x] Công trình 3D Đại Sảnh Liên Minh (`ALLIANCE_HALL` + `AllianceModal`) & Hệ thống Chat 3 kênh Thế Giới / Liên Minh / Riêng Tư (`ChatPanelModal`); Công nghệ & Chiến tranh Liên minh chủ động để lại cho đợt sau.
- [ ] Luồng mua hàng sau khi tích hợp store thật; không coi receipt HMAC hiện tại là IAP sản xuất.

## Ưu tiên 4: tài khoản và phát hành

- [x] Hoàn thiện tab Bảo mật, Định danh, Mã khôi phục và Đăng xuất trong `PlayerProfileModal` (`scripts/test-godot-auth-account.mjs`), giữ nguyên auto-demo khi khởi động để test nhanh.
- [x] Bỏ tự đăng nhập demo ở scene khởi động khi đóng gói bản phát hành thật (giữ `OS.is_debug_build()` cho debug).
- [x] Thay dữ liệu mặc định trên client bằng trạng thái tải/lỗi rõ ràng (`GameState.is_synced`, `sync_error`).
- [ ] Hoàn thiện BGM, SFX, asset nhân vật, VFX và tối ưu hiệu năng.
- [x] Thiết lập preset export PC (`client-godot/export_presets.cfg` cho Windows Desktop).
- [ ] Bổ sung kiểm tra Godot vào quy trình xác minh; `npm run verify` hiện chỉ bao phủ Node/TypeScript.

Backend còn dùng balance mẫu, một số timer giải quyết khi đọc dữ liệu, chưa kết nối Redis, OAuth/store còn mô phỏng. Không dùng tuyên bố “backend hoàn thiện 100%” làm điều kiện phát hành.
