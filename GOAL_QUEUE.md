# Hàng Đợi Mục Tiêu Tự Hành (`/goal` — Phạm Vi 8 Tiếng)

## Quy Tắc Vận Hành Bắt Buộc (Đọc kỹ trước mỗi mốc)
1. **Tuân thủ `AGENTS.md`:**
   - **TUYỆT ĐỐI KHÔNG** chạy full test suite (`npm run verify`, `npm test`, v.v.). Chỉ chạy các lệnh test **targeted** của mốc đang làm.
   - **KHÔNG** sửa/xóa lịch sử cũ trong `AGENT_HANDOFF_NOTES.md`; chỉ **append** phần tổng kết mới vào cuối file khi hoàn thành từng giai đoạn hoặc kết thúc phiên.
   - Trả lời và ghi chú bằng **tiếng Việt**.
2. **Chế độ treo máy tự hành (Unattended):**
   - **KHÔNG** gọi `ask_question` hay dừng lại chờ người dùng duyệt. Tự quyết định phương án an toàn, nhất quán với codebase hiện tại.
   - Làm tuần tự từng mốc `[ ]` từ `M01` → `M12`. Mỗi mốc hoàn thành phải:
     1) Viết đủ code + test targeted cho mốc đó.
     2) Chạy test targeted (Godot headless + `npx tsc -p packages/server/tsconfig.json --noEmit` nếu sửa server) cho tới khi **PASS 100%** (0 lỗi script/engine).
     3) Đổi `[ ]` thành `[x]` ngay trong file `GOAL_QUEUE.md` này (và cập nhật `GODOT_BACKLOG.md` nếu có hạng mục tương ứng).
     4) Dọn sạch mọi tài khoản/dữ liệu test tạm trong PostgreSQL nếu test có tạo mới, giữ nguyên dữ liệu gốc (`2 accounts / 190 Heroes / 2 Worlds`).
3. **Thông số môi trường:**
   - Godot Headless: `C:\Users\k\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe`
   - Project Godot: `e:\infiniti_gacha\client-godot`
   - Server TypeScript check: `npx tsc -p packages/server/tsconfig.json --noEmit`
   - PowerShell 5.1: Không dùng `&&`, dùng `; if ($LASTEXITCODE -eq 0) { ... }`.

---

## Danh Sách 12 Mốc Công Việc

### Giai đoạn A — Chuẩn hóa Card/Browser & Hoàn thiện các luồng cốt lõi

- [x] **M01 — Đồng bộ hệ thống Card 1★–7★, Rainbow Border & Browser cho các màn hình còn lại**
  - **Phạm vi:** Rà soát và đồng bộ `hero_roster.gd`, `pve_consumable_editor.gd`, `pve_field_items_modal.gd`, và kho nguyên liệu trong `magic_hall_modal.gd` theo `RarityStyle` (1★–7★ + shader Rainbow 7★), `UniversalItemCard` (`92×92` + `ItemDetailPopover`) và `ItemGridBrowser` / `CardGridBrowser`.
  - **Kiểm chứng:** Mở rộng & chạy `res://tests/base_presentation_ui_test.tscn` và `res://tests/pve_ui_test.tscn` PASS.

- [x] **M02 — Hoàn thiện & Kiểm thử toàn luồng Gacha, Đổi Thiên Thư & Lịch sử Triệu hồi**
  - **Phạm vi:** Trong `client-godot/scripts/ui/summon_banner_modal.gd`, bổ sung bảng xem Lịch sử Triệu hồi (`GET /api/gacha/history`), nút Đổi Thiên Thư nhanh (`POST /api/economy/exchange-scrolls`), kiểm tra luồng `NORMAL` (dùng scroll) & `SPECIAL` (100 Gem/lượt), xử lý thiếu tài nguyên, khóa nút chống double-submit và đồng bộ ví/kho/tướng.
  - **Kiểm chứng:** Tạo & chạy `client-godot/tests/gacha_flow_network_test.tscn` (tạo tài khoản test tạm và tự dọn dẹp sau khi chạy) PASS.

- [x] **M03 — Hoàn thiện & Kiểm thử toàn luồng Xưởng Rèn (`Craft / Enhance / Fuse`) & Nhà Kho (`Equip / Unequip / Use / Sell`)**
  - **Phạm vi:** Kiểm tra và hoàn thiện luồng chế tạo (`POST /api/crafting/craft`), cường hóa +1..+15 (`enhance`), ghép sao (`fuse`), mặc/tháo nhanh (`quick-equip`, `quick-unequip`), nhặt đồ rơi tầng (`floor-drops`, `pickup`), dùng sách EXP và bán vật phẩm từ `GearWarehouseModal`.
  - **Kiểm chứng:** Tạo & chạy `client-godot/tests/forge_warehouse_network_test.tscn` PASS.

- [x] **M04 — Hoàn thiện & Kiểm thử luồng Sinh tồn Căn cứ (Nhà Bếp, Ký Túc Xá, Trung Tâm Hồi Phục & Tâm Lý/Loyalty)**
  - **Phạm vi:** Hoàn thiện & kiểm thử nấu ăn/tiếp lương/báo giá (`/api/survival/kitchen/cook`, `feed`, `rations/quote`, `upkeep`), món ăn yêu thích & độ trung thành (`/api/personality`), Ký túc xá tách riêng danh sách nghỉ từng tòa & chặn Hero 0% mệt mỏi, Trung tâm hồi phục (`treatments/batch`, `emergency/batch`, `history`).
  - **Kiểm chứng:** Chạy `res://tests/medical_network_test.tscn` + tạo & chạy `client-godot/tests/survival_dorm_network_test.tscn` PASS.

- [x] **M05 — Hoàn thiện & Kiểm thử toàn luồng Phát triển Hero (Khóa, Đột phá, Thăng bậc, Thăng sao, Ấn ký, Kỹ năng AI, Thức tỉnh)**
  - **Phạm vi:** Kiểm tra và hoàn thiện khóa/mở khóa Hero (`PATCH /api/heroes/:heroId/lock`), lên cấp/đột phá (`level-up`, `breakthrough`), thăng bậc/thăng sao kèm chọn phôi (`promote`, `promote-star`), gắn Ấn ký (`/api/heroes/:heroId/imprints`), cấu hình hành vi kỹ năng (`behavior`), và chặn thao tác khi Hero tử trận / đang đi PvE / đang đi Viễn chinh.
  - **Kiểm chứng:** Mở rộng & chạy `res://tests/hero_lifecycle_ui_test.tscn` PASS.

### Giai đoạn B — Sự Kiện, Hòm Thư, Hầm Ngục Cổ Đại, Viễn Chinh, Công Trình Liên Minh & Chat 3 Kênh

- [x] **M06 — Tinh chỉnh Thanh Sự Kiện Top-Right & Xây dựng Modal Sự Kiện + Nhiệm Vụ + Thành Tựu (`events_quests_modal.gd`)**
  - **Phạm vi:**
    - Bỏ nút `🎁 Phúc Lợi` khỏi thanh Sự Kiện Top-Right trong `isometric_base_3d.tscn` & `isometric_base_3d.gd`; thay bằng 3 nút gọn: `🎈 Thương Thuyền`, `📜 Sự Kiện`, `✉️ Hòm Thư`.
    - Tạo `client-godot/scripts/ui/events_quests_modal.gd` nối vào nút `📜 Sự Kiện` gồm 3 tab (không có Bảng Xếp Hạng): Sự Kiện LiveOps (`GET /api/events`, `POST /api/events/missions/:missionId/claim`), Nhiệm Vụ (`GET /api/quests`, `accept`, `claim`), Thành Tựu (`POST /api/achievements/:code/claim`).
  - **Kiểm chứng:** Tạo & chạy `client-godot/tests/events_quests_network_test.tscn` PASS.

- [x] **M07 — Xây dựng Modal Hòm Thư & Sổ Giao Dịch (`mailbox_modal.gd`)**
  - **Phạm vi:** Tạo `client-godot/scripts/ui/mailbox_modal.gd` nối vào nút `✉️ Hòm Thư` (không lặp lại Giftcode vì đã có trong Avatar Master), gồm 2 tab: Hòm Thư (`GET /api/mailbox`, `POST /api/mailbox/:messageId/claim` + Nhận tất cả) và Sổ Giao Dịch Ví (`GET /api/economy/balances`, `GET /api/economy/transactions`).
  - **Kiểm chứng:** Tạo & chạy `client-godot/tests/mailbox_network_test.tscn` PASS.

- [x] **M08 — Cập nhật `PveModeModal` (Bỏ Chinh Phạt Lãnh Thổ) & Phát triển Hầm Ngục Cổ Đại (`ancient_dungeon_modal.gd`)**
  - **Phạm vi:**
    - Trong `pve_mode_modal.gd`, xóa bỏ thẻ `CONQUEST` (Chinh Phạt Lãnh Thổ), giữ 3 thẻ `TOWER`, `DUNGEON`, `EXPEDITION` và bật `available = true` cho cả 3.
    - Tạo `client-godot/scripts/ui/ancient_dungeon_modal.gd` nối `/api/dungeon/floors`, `/api/dungeon/templates`, `/api/dungeon/world-seed/reconstruct/:floorNumber`, `enter`, `instance/active`, `explore`, `retreat`.
  - **Kiểm chứng:** Tạo & chạy `client-godot/tests/ancient_dungeon_network_test.tscn` PASS.

- [x] **M09 — Phát triển Chế độ Viễn Chinh Thế Giới (`world_expedition_modal.gd`)**
  - **Phạm vi:** Tạo `client-godot/scripts/ui/world_expedition_modal.gd` mở khi chọn `EXPEDITION` từ `PveModeModal`: danh sách đoàn Viễn chinh & lịch sử (`GET /api/world/expeditions`), Hero đang đi xa (`GET /api/world/heroes/away`), cử đoàn mới (`POST /api/world/expeditions`), thu hồi/nhận thưởng (`POST /api/world/expeditions/:expeditionId/recall`), và đồng bộ trạng thái Hero đang đi viễn chinh trong `GameState`.
  - **Kiểm chứng:** Tạo & chạy `client-godot/tests/world_expedition_network_test.tscn` PASS.

- [x] **M10 — Xây dựng Công Trình 3D Đại Sảnh Liên Minh (`ALLIANCE_HALL`) & Modal Liên Minh (`alliance_modal.gd`)**
  - **Phạm vi:**
    - Backend & Seed: Đăng ký `ALLIANCE_HALL` (*Đại Sảnh Liên Minh*, World Lv.1, không cần công nhân, xây tức thì) trong danh mục công trình & migration phụ trợ nếu cần.
    - 3D Base (`base_plot_3d.gd`, `building_label_style.gd`, `isometric_base_3d.gd`): Thêm mô hình 3D đặc trưng cho Đại Sảnh Liên Minh, nhãn `"Liên minh"`, bấm vào mở `BuildingActionBar` → `alliance_modal.gd`.
    - UI (`client-godot/scripts/ui/alliance_modal.gd`): Tạo / Tìm kiếm / Xin vào / Rời / Giải tán Liên minh (`GET/POST/DELETE /api/alliance`, `search`, `join`, `leave`, `requests/:requestId/cancel`), quản lý thành viên & sửa thông báo (`members/:masterId/manage`, `PATCH /api/alliance/notice`). **Không xây dựng** Công nghệ Liên minh và Chiến tranh Liên minh.
  - **Kiểm chứng:** `npx tsc -p packages/server/tsconfig.json --noEmit` + tạo & chạy `client-godot/tests/alliance_building_network_test.tscn` PASS.

- [x] **M11 — Xây dựng Hệ Thống Chat 3 Kênh: Thế Giới, Liên Minh, Riêng Tư (`chat_panel_modal.gd` + Backend Chat Routes)**
  - **Phạm vi:**
    - Backend: Thêm/mở rộng API cho kênh Thế Giới (`GET/POST /api/chat/world`), Riêng Tư (`GET/POST /api/chat/private` theo `recipientMasterId` hoặc tên Master), giữ nguyên kênh Liên Minh (`GET/POST /api/alliance/chat`).
    - Godot UI (`client-godot/scripts/ui/chat_panel_modal.gd`): Nút `💬 Chat` ở góc dưới trái `IsometricBase3D`, mở khung Chat 3 tab `🌍 Thế Giới`, `🏳️ Liên Minh`, `🔒 Riêng Tư` với ô chọn người nhận (tab Riêng Tư), lịch sử tin nhắn và gửi tin.
  - **Kiểm chứng:** `npx tsc -p packages/server/tsconfig.json --noEmit` + tạo & chạy `client-godot/tests/chat_channels_network_test.tscn` PASS.

### Giai đoạn C — Tài khoản (Giữ Auto-Demo) & Nghiệm thu tổng thể

- [x] **M12 — Hoàn thiện Quản lý Tài khoản (Giữ nguyên Auto-Demo không cần login) & Tổng kiểm tra bàn giao**
  - **Phạm vi:**
    - Hoàn thiện tab Bảo mật / Định danh / Mã khôi phục trong `PlayerProfileModal` (`/api/auth/security`, `/api/account/identities`, `/api/account/recovery-token`) và hoàn thiện `login_screen.gd` cho trường hợp đổi tài khoản, nhưng **bắt buộc giữ nguyên mặc định tự động vào thẳng game bằng phiên Demo (`GameState.ensure_demo_session()`)** để test game không cần đăng nhập.
    - Chạy lại `npx tsc -p packages/server/tsconfig.json --noEmit` và tất cả các bộ test Godot targeted (`base_presentation_ui_test`, `pve_ui_test`, `gacha_flow_network_test`, `forge_warehouse_network_test`, `survival_dorm_network_test`, `hero_lifecycle_ui_test`, `events_quests_network_test`, `mailbox_network_test`, `ancient_dungeon_network_test`, `world_expedition_network_test`, `alliance_building_network_test`, `chat_channels_network_test`, `auth_account_network_test`).
    - Kiểm tra PostgreSQL đảm bảo DB sạch (chỉ còn dữ liệu gốc, không còn tài khoản test rác).
    - Cập nhật `GODOT_BACKLOG.md` và append tổng kết đầy đủ vào cuối `AGENT_HANDOFF_NOTES.md`.
