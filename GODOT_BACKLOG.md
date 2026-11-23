# Godot client: trạng thái và backlog

Cập nhật: **23/11/2026 (UTC+7)**. Đối chiếu với code hiện tại; checklist thiết kế P0–P3 chỉ phản ánh phạm vi prototype tại thời điểm viết.

## Đã có trong code

- Căn cứ 3D isometric, camera, tương tác ô đất/công trình, xây/nâng cấp tức thì, phân công đa nhân sự & giải phóng nhân sự.
- HUD màn hình chính gọn: Top-Right 3 tài nguyên + thanh Sự Kiện (`Thương Thuyền`, `Sự Kiện`, `Hòm Thư`), nút xoay vòng góc nhìn T1/T2/Toàn cảnh, Build Drawer ẩn mặc định và Bottom-Right Dock + CTA `Tháp PvE`.
- Hệ thống thẻ dùng chung 1–7★ (`RarityStyle` + viền Rainbow 7★), thẻ vật phẩm `92×92` + `ItemDetailPopover`, tách 3 lớp browser (`BaseCardBrowser`, `CardGridBrowser`, `ItemGridBrowser`).
- Nhà Kho Tổng Hợp (`GearWarehouseModal`) chứa mọi loại vật phẩm theo 6 phân loại, bộ lọc riêng từng phân loại và thu hồi đồ rơi tầng.
- Modal hồi phục, bếp/nhà ăn (tâm lý/loyalty), ký túc xá tách biệt từng tòa, huấn luyện, lò rèn (có lọc `+15`), Đại Sảnh Ma Thuật, Thương Thuyền Khinh Khí, Sử Điện Anh Hùng, và Công trình 3D Đại Sảnh Liên Minh (`ALLIANCE_HALL`).
- Modal Sự Kiện/Nhiệm Vụ/Thành Tựu (`events_quests_modal.gd`), Hòm Thư & Sổ Giao Dịch (`mailbox_modal.gd`), Hầm Ngục Cổ Đại (`ancient_dungeon_modal.gd`), Viễn Chinh Thế Giới (`world_expedition_modal.gd`), và Chat 3 kênh Thế Giới / Liên Minh / Riêng Tư (`chat_panel_modal.gd`).
- Hero roster dạng thẻ, xem nhân vật 3D, khóa, huấn luyện, kỹ năng, thức tỉnh, ấn ký, trang bị và chọn phôi thăng sao.
- HUD Master, hồ sơ, avatar, giftcode, tab Bảo mật/Định danh/Mã khôi phục (giữ auto-demo khi mở game để test nhanh) và gửi ticket hỗ trợ.
- Gacha hai banner, chọn ngang, tỷ lệ lấy từ API, lịch sử triệu hồi, đổi Thiên Thư nhanh, ×1/×10, hiệu ứng triệu hồi và chống double-submit.
- Đấu trường PvE (Auto/Thủ công 10s/lượt, 5 ô thuốc/Hero) với diễn hoạt replay, tốc độ phát và dynamic camera.
- REST client và đồng bộ profile, Hero (gồm trạng thái đi PvE & Viễn chinh), căn cứ, trang bị, vật phẩm, đội hình.

## PvE đã triển khai theo `thaoluan.md`

- [x] Map PvE riêng 12×12, fog, tài nguyên, boss và ba đội hoạt động độc lập qua `/api/pve`.
- [x] Tạo/sửa party 1–5 Hero, xếp vị trí 0–8 và đặt ưu tiên mục tiêu/thứ tự kỹ năng.
- [x] Di chuyển 1 giây/ô bằng thời gian server, ETA và polling khoảng một giây khi mở map/replay; bật/tắt tự khám phá từng đội.
- [x] Tự giao chiến và quyết toán một lần; hiển thị chiến báo, thưởng và đồng bộ Hero/tài nguyên/tầng.
- [x] Replay đọc báo cáo đã lưu, gồm HP/MP, heal, crit và revive; không còn simulation/fallback demo trong luồng này.
- [x] Phục hồi lệnh chưa xác nhận sau mất phản hồi hoặc khởi động lại; giữ bản nháp đội hình khi lỗi.
- [x] Hero triển khai được đánh dấu và loại khỏi chọn nhân sự/trang bị tại căn cứ.
- [x] Kiểm thử headless bằng Godot thật và HTTP/PostgreSQL; có ca đổi tài khoản và khởi động lại cả API/client.

PvE dùng map và encounter riêng theo đội, tái sử dụng Combat v2. Luồng session/dungeon cũ được giữ để tương thích và bị chặn khi có map mới đang ACTIVE. Không còn kế hoạch nối đấu trường vào luồng đánh từng phòng. Bằng chứng và giới hạn kiểm thử ở [PVE_IMPLEMENTATION.md](docs/PVE_IMPLEMENTATION.md).

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
- [x] Hầm Ngục Cổ Đại (`AncientDungeonModal`) & Viễn Chinh Thế Giới (`WorldExpeditionModal`) — đã bỏ chế độ Chinh Phạt Lãnh Thổ khỏi `PveModeModal`.
- [x] Công trình 3D Đại Sảnh Liên Minh (`ALLIANCE_HALL` + `AllianceModal`) & Hệ thống Chat 3 kênh Thế Giới / Liên Minh / Riêng Tư (`ChatPanelModal`); Công nghệ & Chiến tranh Liên minh chủ động để lại cho đợt sau.
- [ ] Luồng mua hàng sau khi tích hợp store thật; không coi receipt HMAC hiện tại là IAP sản xuất.

## Ưu tiên 4: tài khoản và phát hành

- [x] Hoàn thiện tab Bảo mật, Định danh, Mã khôi phục và Đăng xuất trong `PlayerProfileModal` (`scripts/test-godot-auth-account.mjs`), giữ nguyên auto-demo khi khởi động để test nhanh.
- [ ] Bỏ tự đăng nhập demo ở scene khởi động khi đóng gói bản phát hành thật.
- [ ] Thay dữ liệu mặc định trên client bằng trạng thái tải/lỗi rõ ràng.
- [ ] Hoàn thiện BGM, SFX, asset nhân vật, VFX và tối ưu hiệu năng.
- [ ] Thiết lập và kiểm thử export PC/mobile theo nền tảng đã chọn.
- [ ] Bổ sung kiểm tra Godot vào quy trình xác minh; `npm run verify` hiện chỉ bao phủ Node/TypeScript.

Backend còn dùng balance mẫu, một số timer giải quyết khi đọc dữ liệu, chưa kết nối Redis, OAuth/store còn mô phỏng. Không dùng tuyên bố “backend hoàn thiện 100%” làm điều kiện phát hành.
