# Hàng Đợi Mục Tiêu Tự Hành (`/goal`)

> **Trạng thái 25/11/2026:** Đây là đề xuất cho Khám Phá, chưa phải chức năng đã triển khai và chưa thay thế [tiến độ Tháp hiện hành](docs/TOWER_PROGRESSION.md). Các đường dẫn máy, lịch sử kiểm thử và chỉ dẫn vận hành bên dưới là bối cảnh của lần soạn; dùng `AGENTS.md`, môi trường hiện tại và yêu cầu mới nhất khi thực hiện. `0065` và `0066` đã được dùng: chọn số migration tiếp theo còn trống. `/api/dungeon/*` hiện bị chặn, không coi là gameplay khả dụng. Không tự triển khai hàng đợi chỉ vì tài liệu tồn tại.

## Ghi chú vận hành tại thời điểm soạn (kiểm tra lại trước khi dùng)
1. **Tuân thủ `AGENTS.md`:**
   - **TUYỆT ĐỐI KHÔNG** chạy full test suite (`npm run verify`, `npm test`, v.v.). Chỉ chạy các lệnh kiểm thử **targeted** của mốc đang làm.
   - **KHÔNG** sửa/xóa lịch sử cũ trong `AGENT_HANDOFF_NOTES.md`; chỉ **append** phần tổng kết mới vào cuối file khi hoàn thành.
   - Trả lời và ghi chú bằng **tiếng Việt**.
2. **Quy tắc Build & Kiểm thử Backend:**
   - Mỗi khi sửa file TypeScript trong `packages/server/src/**`, **BẮT BUỘC** chạy `npm --prefix packages/server run build` trước khi chạy test.
   - Nếu thêm migration `.sql` mới, apply vào PostgreSQL local (port `5433`) trước khi chạy test.
   - Dọn sạch mọi tài khoản/dữ liệu test tạm trong `finally` của script test.
3. **Quy tắc UI & Cài đặt chung:**
   - Mọi tùy chọn cài đặt mới (nếu có) đều đặt tập trung trong **Avatar Master → `PlayerProfileModal` → Tab `⚙️ Cài Đặt`**.
4. **Thông số môi trường:**
   - Godot Headless: đặt `GODOT_BIN` theo engine trên máy hiện tại.
   - Project Godot: `client-godot/` trong workspace hiện tại.
   - PowerShell 5.1: Không dùng `&&`, dùng `; if ($LASTEXITCODE -eq 0) { ... }`.

---

## Hạng Mục Đã Chốt: Chế Độ **Khám Phá Hàng Ngày — Isometric Adventure Exploration** (`EXP-01` → `EXP-05`)

> **Nguồn thảo luận & thiết kế:** `dungeon_thaoluan.txt` (đã chốt đổi tên từ *Hầm Ngục* → **🌿 Khám Phá / Exploration**).  
> **Thể loại gameplay đã khóa:** **Isometric Adventure Exploration 3D Thời Gian Thực (KHÔNG Turn-Based)** kéo dài ~1–2 phút/chuyến trên bản đồ `48m × 48m`, kèm nút **⚡ Tự Khám Phá Nhanh** ngay tại sảnh chọn địa hình (đi thủ công cho tỷ lệ đồ hiếm cao hơn rõ rệt `×2.2`).

### Các mốc triển khai tuần tự

- [ ] **EXP-01 — Database Migration, Schema & Seed 5 Vật Phẩm Khám Phá**
  - **Phạm vi:** migration mới có số tiếp theo còn trống (hiện sau `0066`), `packages/server/src/database/drizzle-schema.ts`.
  - **Nội dung:**
    - Tạo bảng `master_exploration_progress` (`master_id`, `level`, `exp`, `energy` mặc định 6/ngày tăng tới 8 theo cấp, `max_energy`, `last_reset_date` UTC+7, `daily_discovery_date`, `daily_discovery_claimed`, `weekly_key`, `weekly_runs_completed`, `weekly_milestones_claimed`).
    - Tạo bảng `exploration_runs` (`id`, `master_id`, `date_key`, `biome_code`, `tier`, `is_daily_discovery`, `mode` `MANUAL | QUICK`, `hero_ids`, `map_layout`, `collected_node_ids`, `defeated_monster_ids`, `rewards`, `status`, `created_at`, `completed_at`).
    - Seed bổ sung vào `item_templates` (`ON CONFLICT DO NOTHING`): `WILD_MUSHROOM` (2★), `RARE_ORE` (3★), `ANCIENT_RELIC` (4★), `CRAFTING_BLUEPRINT` (4★), `LOST_RUNE` (5★).
  - **Kiểm chứng dự kiến:** áp dụng migration mới vào database test riêng + `npm --prefix packages/server run build`; xác nhận kết quả sau khi triển khai.

- [ ] **EXP-02 — Backend Rules, Balanced Weekly Schedule UTC+7, Map Generator & Service API**
  - **Phạm vi:** `packages/server/src/modules/exploration/exploration-rules.ts` [NEW], `packages/server/src/modules/exploration/exploration.service.ts` [NEW], `packages/server/src/server.ts`.
  - **Nội dung:**
    - **Lịch luân phiên theo ngày UTC+7 chung toàn server (Balanced Weekly Shuffle):**
      - Thứ 2, 4, 6 — Nhóm **Hoang Dã**: random theo ngày giữa **🌿 Rừng Xanh (`GREEN_FOREST`)** và **🌾 Thảo Nguyên (`GRASSLAND`)** (đảm bảo cả tuần luôn có ít nhất 1 ngày mỗi loại).
      - Thứ 3, 5, 7 — Nhóm **Cổ Đại**: random theo ngày giữa **⛏️ Hầm Mỏ (`DEEP_MINE`)** và **🏛️ Di Tích Cổ Đại (`ANCIENT_RUINS`)** (đảm bảo cả tuần luôn có ít nhất 1 ngày mỗi loại).
      - **Chủ Nhật**: mở chọn tự do cả **4 địa hình**.
      - Sinh 1 **Địa điểm Khám phá Đặc biệt trong ngày (`Daily Discovery`)** thưởng ×1.5 (tối đa 1 lần/ngày).
    - **Hệ số phân phối tài nguyên (`BIOME_LOOT_WEIGHTS`):**
      - `GREEN_FOREST`: Thảo dược `ALCHEMY_HERB` ×2.5, Nấm `WILD_MUSHROOM` ×2.0, Gỗ `WOOD` ×1.5, `FOOD_RAW` ×0.8.
      - `GRASSLAND`: `FOOD_RAW` ×2.5, Thịt/món thô ×2.0, `WOOD` ×1.0, Thảo dược ×0.8.
      - `DEEP_MINE`: `IRON` & `STONE` ×2.5, `RARE_ORE` & `ENHANCEMENT_STONE` ×2.0, `LOST_RUNE` ×0.5.
      - `ANCIENT_RUINS`: `LOST_RUNE` ×2.0 (cực hiếm), `CRAFTING_BLUEPRINT` ×2.0, `ANCIENT_RELIC` ×2.0, Khoáng sản ×0.8.
    - **Trình sinh bản đồ `48m × 48m` (`generateExplorationMapLayout`)**: `spawn` + `exitPortal`, `8–10` điểm `GATHERING`, `4–6` bãi `MONSTER` tuần tra (có `aggroRadius`, `hp`, `atk`, `isElite`), `2–3` điểm `DISCOVERY` (Kho báu & Bệ đá bí mật), `12–16` vật cản địa hình tạo lối lách né.
    - **API:** `GET /api/exploration/status`, `POST /api/exploration/runs/start`, `POST /api/exploration/runs/:runId/complete` (xác thực ID, bonus đồ hiếm thủ công `×2.2`, cộng kho + EXP + mốc tuần), `POST /api/exploration/quick` (skip bản đồ, ~80% sản lượng, tỷ lệ đồ hiếm cơ bản `×1.0`), `POST /api/exploration/weekly/:target/claim` (`5 / 12 / 20` chuyến/tuần).
    - `/api/dungeon/*` cũ hiện bị chặn; không mở lại mà chưa có yêu cầu mới. Cập nhật test liên quan theo thiết kế được duyệt khi triển khai.
  - **Kiểm chứng:** `npm --prefix packages/server run build` + tạo & chạy `scripts/test-daily-exploration-api.mjs` PASS (kèm dọn tài khoản test sạch).

- [ ] **EXP-03 — Đổi Tên Thẻ 2 Trong `PveModeModal` & Xây Dựng Sảnh Chọn Địa Hình (`DailyExplorationModal`)**
  - **Phạm vi:** `client-godot/scripts/ui/pve_mode_modal.gd`, `client-godot/scenes/base/isometric_base_3d.gd`, `client-godot/scripts/ui/daily_exploration_modal.gd` [NEW].
  - **Nội dung:**
    - Đổi thẻ thứ 2 trong `PveModeModal` từ `Hầm Ngục Cổ Đại` → **`🌿 Khám Phá (Exploration)`**, mở `DailyExplorationModal`.
    - Giao diện sảnh hiển thị: ngày UTC+7, Năng lượng (`6/6`), Cấp Khám Phá (`Lv.X`), 3 Mốc Thưởng Tuần (`5 / 12 / 20`), 4 thẻ địa hình (sáng rõ địa hình mở hôm nay + hệ số ưu tiên; Chủ Nhật mở cả 4), thẻ **✨ Địa Điểm Bí Mật Hôm Nay**, chọn Bậc (`I → V`), chọn Đội `1–5` Hero.
    - Đặt 2 nút xuất kích song song ngay tại sảnh:
      - **🧭 Khám Phá Thủ Công (3D Isometric • Tỷ lệ Đồ Hiếm ×2.2)**
      - **⚡ Tự Khám Phá Nhanh (Bỏ qua & Nhận kết quả ngay)** → gọi `/api/exploration/quick` và mở popup chiến lợi phẩm ngay.
  - **Kiểm chứng:** Mở rộng & chạy `res://tests/base_presentation_ui_test.tscn` PASS.

- [ ] **EXP-04 — Cảnh Phiêu Lưu 3D Isometric Thời Gian Thực (`isometric_exploration_3d.tscn` / `.gd`)**
  - **Phạm vi:** `client-godot/scenes/exploration/isometric_exploration_3d.tscn` [NEW], `client-godot/scenes/exploration/isometric_exploration_3d.gd` [NEW].
  - **Nội dung (100% Real-Time, KHÔNG Turn-Based, 1–2 phút/chuyến):**
    - Bản đồ `48m × 48m` thay đổi bảng màu đất, ánh sáng, cây/cột đá/vách mỏ/bụi cỏ theo đúng 4 Biome + sương mù mở mượt quanh đội hình + Camera Isometric bám đội trưởng (cuộn chuột zoom).
    - Điều khiển đội `1–5` Hero (`UnitActor3D`) bằng **Click chuột lên mặt đất** hoặc **WASD / Phím mũi tên**; đồng đội chạy theo đội hình mượt phía sau.
    - **Thu thập tài nguyên 3D (`Gathering`)**: đi tới hoặc click vào cụm Thảo dược / Nấm / Gỗ / Quặng / Tinh thể → vòng tiến độ `0.9s` + chữ bay nổi 3D.
    - **Quái tuần tra & Chiến đấu / Tránh né thời gian thực**: mỗi bãi quái có **vòng Aggro đỏ mờ trên mặt đất**; đi ngoài vòng đỏ để **tránh né**, bấm vào quái hoặc bước vào vòng đỏ để **giao chiến thời gian thực** (đánh theo cooldown, thanh HP, số sát thương bay nổi), kéo đội ra xa vòng aggro để **thoát giao tranh**. Không Permadeath vĩnh viễn.
    - **Kho báu & Địa điểm bí mật (`Discovery`)**: Rương Vàng & Bệ Đá Cổ phát sáng.
    - **Rút lui chủ động**: chạy về **Cổng Rút Lui (`Extraction Portal`)** hoặc bấm **🚪 Rút Lui & Nhận Đồ** trên HUD bất kỳ lúc nào → gọi `/api/exploration/runs/:runId/complete` → hiện bảng tổng kết chiến lợi phẩm & về Lâu Đài hoặc đi chuyến mới.
  - **Kiểm chứng:** Tạo & chạy `client-godot/tests/test_daily_exploration_isometric.tscn` (test khởi tạo 4 biome, di chuyển thực, thu thập, lách né ngoài aggro, giao chiến thời gian thực hạ quái, mở kho báu & rút lui hoàn tất) PASS.

- [ ] **EXP-05 — Chuẩn Hóa Tài Liệu, Kiểm Thử Tổng Hợp Targeted & Bàn Giao**
  - **Phạm vi:** `API_Routes.md`, `README.md`, `client-godot/README.md`, `GODOT_BACKLOG.md`, `AGENT_HANDOFF_NOTES.md`.
  - **Nội dung:** Chạy `npm run docs:routes`, `node scripts/check-encoding.mjs`, chạy lại `node scripts/test-daily-exploration-api.mjs` + `res://tests/test_daily_exploration_isometric.tscn` + `res://tests/base_presentation_ui_test.tscn`, cập nhật tài liệu và append tổng kết vào cuối `AGENT_HANDOFF_NOTES.md`.
