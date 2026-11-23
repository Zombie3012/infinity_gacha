# Hàng Đợi Mục Tiêu Tự Hành — Phase 2 (`P2-01` → `P2-16`)

## Quy Tắc Vận Hành Bắt Buộc (Đọc kỹ trước mỗi mốc)
1. **Tuân thủ `AGENTS.md`:**
   - **TUYỆT ĐỐI KHÔNG** chạy full test suite (`npm run verify`, `npm test`, v.v.). Chỉ chạy các lệnh kiểm thử **targeted** của mốc đang làm.
   - **KHÔNG** sửa/xóa lịch sử cũ trong `AGENT_HANDOFF_NOTES.md`; chỉ **append** phần tổng kết mới vào cuối file khi hoàn thành.
   - Trả lời và ghi chú bằng **tiếng Việt**.
2. **Quy tắc Build & Kiểm thử Backend:**
   - Mỗi khi sửa file TypeScript trong `packages/server/src/**`, **BẮT BUỘC** chạy `npm --workspace=@infiniti_gacha/server run build` trước khi chạy test harness (`harness.mjs` nạp từ `packages/server/dist/server.js`).
   - Nếu thêm migration `.sql` mới, apply vào PostgreSQL local (port 5433) trước khi chạy test.
   - Dọn sạch mọi tài khoản/dữ liệu test tạm trong `finally` của script test.
3. **Chế độ tự hành (`/goal`):**
   - **KHÔNG** gọi `ask_question` hay dừng chờ duyệt plan giữa chừng.
   - Làm tuần tự từng mốc `[ ]` từ `P2-01` → `P2-16`. Sau khi test targeted của mốc PASS 100%, đổi `[ ]` thành `[x]` ngay trong file `GOAL_QUEUE_PHASE2.md` này rồi chuyển sang mốc tiếp theo.
4. **Ràng buộc nghiệp vụ đã khóa:**
   - **Gacha:** Chỉ triệu hồi tối đa **5★** (6★–7★ không triệu hồi từ Gacha).
   - **Chat 3 kênh:** Real-time push (SSE); **không có Mini-Chat Preview** trên HUD chính; thoát game vào lại **CHỈ lưu lịch sử Liên Minh & Riêng Tư** (kênh Thế Giới chỉ giữ in-memory phiên hiện tại).
   - **Không làm trong Phase 2:** Hầm Ngục Cổ Đại (chờ thiết kế lại), Viễn Chinh Thế Giới (chờ thảo luận content), AudioManager/SFX, Bảng thống kê MVP Combat, Mô phỏng cân bằng.
5. **Thông số môi trường:**
   - Godot Headless: `C:\Users\k\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe`
   - Project Godot: `e:\infiniti_gacha\client-godot`
   - PowerShell 5.1: Không dùng `&&`, dùng `; if ($LASTEXITCODE -eq 0) { ... }`.

---

## Danh Sách 16 Mốc Công Việc Phase 2

### Giai đoạn 1 — HUD Thông Minh, Bạn Bè, Chat Real-Time & Gacha 1–5★

- [ ] **P2-01 — Hệ thống Chấm Đỏ Thông Báo (Red-Dot) & Hàng Đợi Toast Mượt trên HUD Chính**
  - **Phạm vi:** `client-godot/scenes/base/isometric_base_3d.gd`, `client-godot/scripts/state/game_state.gd`.
  - **Nội dung:** Badge đỏ tự cập nhật trên nút `✉️ Hòm Thư` (thư chưa nhận), `📜 Sự Kiện` (nhiệm vụ/thành tựu/sự kiện đủ điều kiện nhận), `👥 Bạn Bè` (lời mời kết bạn hoặc quà chưa nhận), `💬 Chat` (tin riêng mới chưa đọc). Nâng cấp `StatusToastPanel` thành hàng đợi Toast fade-in/fade-out có màu theo mức độ.
  - **Kiểm chứng:** Mở rộng & chạy `res://tests/base_presentation_ui_test.tscn` PASS.

- [ ] **P2-02 — Hệ Thống Bạn Bè: Backend, Database & Đồng Bộ Chặn Chat (`friend.service.ts`)**
  - **Phạm vi:** `packages/server/drizzle/0061_friends_system.sql`, `packages/server/src/database/drizzle-schema.ts`, `packages/server/src/modules/world/friend.service.ts`, `packages/server/src/modules/world/chat.service.ts`, `packages/server/src/server.ts`.
  - **Nội dung:**
    - Tạo bảng `friendships` (`PENDING | ACCEPTED | BLOCKED`) và `friend_daily_gifts` (tặng/nhận quà tình bạn 1 lần/ngày/bạn).
    - Thêm API: `GET /api/friends`, `GET /api/friends/requests`, `GET /api/friends/search`, `POST /api/friends/requests`, `POST /api/friends/requests/:requestId/accept`, `POST /api/friends/requests/:requestId/decline`, `DELETE /api/friends/:friendMasterId`, `POST/DELETE /api/friends/:friendMasterId/block`, `POST /api/friends/:friendMasterId/gift`, `POST /api/friends/gifts/claim-all`, `GET /api/friends/:friendMasterId/profile`.
    - Đồng bộ trong `chat.service.ts`: chặn gửi tin nhắn Riêng Tư nếu một trong hai bên đã `BLOCKED` nhau.
  - **Kiểm chứng:** Apply `0061_friends_system.sql` + `npm --workspace=@infiniti_gacha/server run build` PASS.

- [ ] **P2-03 — Giao Diện Bạn Bè (`FriendsModal`) & Liên Kết Chéo Với Chat + Liên Minh + HUD**
  - **Phạm vi:** `client-godot/scripts/ui/friends_modal.gd`, `client-godot/scenes/base/isometric_base_3d.tscn`, `client-godot/scenes/base/isometric_base_3d.gd`, `client-godot/scripts/ui/alliance_modal.gd`, `client-godot/scripts/ui/chat_panel_modal.gd`.
  - **Nội dung:**
    - Nút `👥 Bạn Bè` trên HUD chính mở `FriendsModal` (3 tab: *Bạn Bè* có Tặng Quà / Nhắn Riêng / Xem Hồ Sơ Công Khai / Chặn / Xóa + Tặng & Nhận Tất Cả; *Lời Mời*; *Tìm Kiếm & Chặn*).
    - Nút `💬 Nhắn Riêng` mở thẳng `ChatPanelModal` tab `🔒 Riêng Tư` với tên bạn bè điền sẵn; `AllianceModal` có nút `➕ Kết Bạn` cạnh từng thành viên; `ChatPanelModal` tab Riêng Tư hiển thị danh sách Bạn Bè chọn 1 chạm.
  - **Kiểm chứng:** Tạo & chạy `scripts/test-godot-friends.mjs` + `client-godot/tests/friends_network_test.tscn` PASS.

- [ ] **P2-04 — Chat 3 Kênh Real-Time (SSE Stream) & Chính Sách Lưu Trữ Đúng Quy Tắc**
  - **Phạm vi:** `packages/server/src/modules/world/chat.service.ts`, `packages/server/src/server.ts`, `client-godot/scripts/ui/chat_panel_modal.gd`, `client-godot/scenes/base/isometric_base_3d.gd`.
  - **Nội dung:**
    - Kênh Thế Giới (`WORLD`) dùng in-memory live stream (thoát game vào lại không tải lịch sử cũ); Liên Minh (`ALLIANCE`) và Riêng Tư (`PRIVATE`) lưu bền vững trong PostgreSQL.
    - Thêm `GET /api/chat/stream` (SSE) đẩy tin nhắn mới tức thì về client; bật chấm đỏ trên nút `💬 Chat` khi modal đang đóng. **Không hiển thị Mini-Chat Preview trên HUD chính.**
  - **Kiểm chứng:** `npm --workspace=@infiniti_gacha/server run build` + `node scripts/test-godot-chat-channels.mjs` (xác minh tin Thế Giới không tải từ DB cũ, tin Liên Minh/Riêng Tư còn sau reload, và nhận tin real-time) PASS.

- [ ] **P2-05 — Chuẩn Hóa Responsive Viewport Toàn Bộ Modal & Gỡ Dữ Liệu Giả Trong `GameState`**
  - **Phạm vi:** `client-godot/scripts/state/game_state.gd`, `events_quests_modal.gd`, `mailbox_modal.gd`, `friends_modal.gd`, `alliance_modal.gd`, `chat_panel_modal.gd`.
  - **Nội dung:** Co giãn kích thước panel theo viewport cho các modal mới; thay các số liệu mẫu cứng (`silver_coins = 5000000`, `gem_stones = 50000`, `master_level = 30`) trong `GameState` bằng `0` + cờ `is_synced` và trạng thái đang đồng bộ/lỗi rõ ràng.
  - **Kiểm chứng:** `res://tests/base_presentation_ui_test.tscn` + `res://tests/base_scene_lifecycle_test.tscn` PASS.

- [ ] **P2-06 — Màn Hình Lật Thẻ Kết Quả Triệu Hồi Gacha (`SummonResultModal` — Tối Đa 5★)**
  - **Phạm vi:** `client-godot/scripts/ui/summon_result_modal.gd`, `client-godot/scenes/base/isometric_base_3d.gd`.
  - **Nội dung:** Hiển thị lưới kết quả ×1 / ×10 bằng `UniversalHeroCard` & `UniversalItemCard` (`1★`–`5★`, khóa chặt mức cao nhất của Gacha là **5★ Vàng**), hiệu ứng mở thẻ tuần tự + nút *Bỏ qua* & *Triệu hồi tiếp*.
  - **Kiểm chứng:** Mở rộng & chạy `node scripts/test-godot-gacha.mjs` PASS.

### Giai đoạn 2 — Hệ Sinh Thái Đời Sống Hero Trong Lâu Đài 3D

- [ ] **P2-07 — Hành Vi Tự Chủ Của Hero 3D Theo Nhu Cầu & Công Trình (Hero Daily Routine AI)**
  - **Phạm vi:** `client-godot/scripts/actors/unit_actor_3d.gd`, `client-godot/scenes/base/isometric_base_3d.gd`.
  - **Nội dung:** Hero tự tìm đường theo trạng thái thật: công nhân hoạt động quanh công trình được phân công; Hero đói (`hunger >= 55%`) tới quanh Nhà Bếp; Hero mệt (`fatigue >= 55%`) về quanh Ký Túc Xá/Biệt Thự; Hero bị thương (`HP < 80%`) về quanh Trung Tâm Hồi Phục; Hero rảnh & khỏe dạo quanh Đài Phun Nước/Quảng trường.
  - **Kiểm chứng:** Mở rộng & chạy `res://tests/base_presentation_ui_test.tscn` PASS.

- [ ] **P2-08 — Bong Bóng Trạng Thái & Đối Thoại Xã Giao Giữa Các Hero 3D (Hero-to-Hero Social)**
  - **Phạm vi:** `client-godot/scripts/actors/hero_dialogue_bank.gd`, `client-godot/scripts/actors/unit_actor_3d.gd`, `client-godot/scenes/base/isometric_base_3d.gd`.
  - **Nội dung:** Ngân hàng lời thoại tiếng Việt theo nghề nghiệp, tâm trạng, đói/mệt, công trình; khi 2 Hero đi ngang gần nhau (~3.5m) dừng lại quay mặt vào nhau hiện 2 bong bóng thoại nối tiếp; bong bóng icon trạng thái (`🍖`, `💤`, `🩹`, `⚒️`, `📚`, `✨`) tự ẩn khi zoom quá xa.
  - **Kiểm chứng:** Mở rộng & chạy `res://tests/base_presentation_ui_test.tscn` PASS.

- [ ] **P2-09 — Tương Tác Trực Tiếp Master ↔ Hero Trong Sảnh 3D (`HeroQuickInteractPopup`)**
  - **Phạm vi:** `client-godot/scripts/ui/hero_quick_interact_popup.gd`, `client-godot/scenes/base/isometric_base_3d.gd`.
  - **Nội dung:** Chạm ngắn vào Hero 3D trong lâu đài → Hero quay mặt chào Master + mở popup tương tác nhanh cạnh Hero (Tên, Sao, HP/Đói/Mệt, Tâm trạng, Loyalty) với 4 nút 1 chạm: `🍖 Cho ăn nhanh`, `🍰 Tặng món yêu thích`, `💤 Cho đi nghỉ`, `🛡️ Mở Hồ Sơ Chi Tiết`.
  - **Kiểm chứng:** Mở rộng & chạy `res://tests/base_presentation_ui_test.tscn` PASS.

- [ ] **P2-10 — Hệ Thống Tính Cách, Tâm Trạng & Độ Trung Thành Trực Quan (Personality & Mood Sync)**
  - **Phạm vi:** `client-godot/scripts/state/game_state.gd`, `client-godot/scenes/heroes/hero_roster.gd`, `client-godot/scripts/ui/universal_hero_card.gd`.
  - **Nội dung:** Đồng bộ `/api/personality` vào `GameState` (Tính cách, Món ăn yêu thích, Loyalty, Tâm trạng) và hiển thị thẻ Tâm Trạng & Tính Cách trong Hồ sơ Hero kèm nút tặng món yêu thích.
  - **Kiểm chứng:** `node scripts/test-godot-survival-dorm.mjs` + `res://tests/hero_lifecycle_ui_test.tscn` PASS.

- [ ] **P2-11 — Nhịp Sinh Hoạt Ngày/Đêm & Phản Ứng Của Hero Với Sự Kiện Lâu Đài**
  - **Phạm vi:** `client-godot/scenes/base/isometric_base_3d.gd`, `client-godot/scripts/actors/unit_actor_3d.gd`.
  - **Nội dung:** Hành vi & lời thoại Hero đổi theo chế độ Ngày / Hoàng Hôn / Đêm (ban đêm tụ tập quanh Lửa Trại hoặc về Ký túc xá); thêm hiệu ứng chữ tài nguyên bay nổi 3D (`+20 🍖`, `+500 🪙`, `+2 📚`) khi thu hoạch/nâng cấp và Hero gần đó hiện bong bóng chúc mừng.
  - **Kiểm chứng:** `res://tests/base_presentation_ui_test.tscn` PASS.

### Giai đoạn 3 — Combat Feel, Quản Lý Lâu Đài Thông Minh & Tối Ưu

- [ ] **P2-12 — Nâng Cấp Đấu Trường Combat v2: Floating Damage / Crit / Heal / Status Numbers**
  - **Phạm vi:** `client-godot/scenes/pve/isometric_pve_arena_3d.gd`, `client-godot/scripts/ui/pve_live_battle_modal.gd`.
  - **Nội dung:** Số bay nổi trực quan (sát thương, CRIT, `+HP`, `+MP`, `REVIVE`) trong cả Live Manual và Replay; nổi bật thanh đếm ngược 10s và mục tiêu đang chọn. *(Không làm bảng MVP.)*
  - **Kiểm chứng:** `res://tests/pve_ui_test.tscn` PASS.

- [ ] **P2-13 — Quản Lý Lâu Đài Nâng Cao: Layout Presets (3 Slot) & Thu Hoạch Tất Cả Thông Minh**
  - **Phạm vi:** `client-godot/scenes/base/isometric_base_3d.gd`.
  - **Nội dung:** 3 slot Lưu/Nạp Bố Cục Lâu Đài (`Bố cục 1 / 2 / 3`) trong `BuildToolsDrawer`; nút `🌾 Thu Hoạch Tất Cả` thông minh tự hiện khi có ≥1 công trình có sản lượng `stored >= 1`, thu hoạch 1 chạm kèm chữ tài nguyên bay nổi.
  - **Kiểm chứng:** `res://tests/base_presentation_ui_test.tscn` PASS.

- [ ] **P2-14 — Bách Khoa Toàn Thư (`CodexModal`) & Nhật Ký Hoạt Động Lâu Đài**
  - **Phạm vi:** `client-godot/scripts/ui/codex_modal.gd`, `client-godot/scenes/base/isometric_base_3d.gd`.
  - **Nội dung:** Modal 4 tab: Từ Điển Anh Hùng (`/api/hero-templates`), Từ Điển Trang Bị & Công Thức Rèn (`ItemGridBrowser` 1★–7★), Từ Điển Vật Phẩm & Giả Kim (`/api/alchemy`), và Nhật Ký Hoạt Động Lâu Đài gần đây.
  - **Kiểm chứng:** Tạo & chạy `scripts/test-godot-codex.mjs` + `client-godot/tests/codex_network_test.tscn` PASS.

- [ ] **P2-15 — Tối Ưu Hiệu Năng Lưới Thẻ (`BaseCardBrowser`) & Cấu Hình Môi Trường + Export Preset**
  - **Phạm vi:** `client-godot/scripts/ui/base_card_browser.gd`, `client-godot/scripts/network/api_client.gd`, `client-godot/scenes/auth/login_screen.gd`, `client-godot/export_presets.cfg`.
  - **Nội dung:** Debounce `0.15s` cho tìm kiếm + render phân trang / "Xem thêm" khi lưới vượt 80 thẻ; đọc `base_url` từ `user://client_config.json` / `INFINITI_API_URL`, giữ Auto-Demo khi `OS.is_debug_build()`, tạo sẵn `export_presets.cfg` cho Windows Desktop.
  - **Kiểm chứng:** `res://tests/base_presentation_ui_test.tscn` (test lưới 200 vật phẩm) + `node scripts/test-godot-auth-account.mjs` PASS.

- [ ] **P2-16 — Tổng Kiểm Tra Hồi Quy Targeted, Chuẩn Hóa Tài Liệu & Bàn Giao Phase 2**
  - **Phạm vi:** `API_Routes.md`, `README.md`, `client-godot/README.md`, `GODOT_BACKLOG.md`, `GOAL_QUEUE_PHASE2.md`, `AGENT_HANDOFF_NOTES.md`.
  - **Nội dung:** Build server (`npm --workspace=@infiniti_gacha/server run build`), `npm run docs:routes`, `node scripts/check-encoding.mjs`, chạy các suite Godot targeted mới & cũ, cập nhật toàn bộ tài liệu và append báo cáo tổng kết vào cuối `AGENT_HANDOFF_NOTES.md`.
