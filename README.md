# Infinite Gacha

Game quản lý Hero, sinh tồn và chiến thuật. Client hiện tại là **Godot 3D isometric**, kết nối REST API Node.js/Express và PostgreSQL. Web React/Vite đã được gỡ khỏi workspace.

Cập nhật: **25/11/2026 (UTC+7)**. Đây là bản prototype đang hoàn thiện, với dữ liệu cân bằng mẫu; các checklist P0–P3 và handoff cũ là lịch sử, không mô tả chắc chắn trạng thái hiện tại. Xem [tiến độ và điều kiện mở khóa](docs/TOWER_PROGRESSION.md).

Hero và vật liệu dùng độ hiếm **1–7★** (1★ Bạc, 2★ Xanh lá, 3★ Xanh dương, 4★ Tím, 5★ Vàng, 6★ Đỏ, 7★ viền Rainbow). Mọi Hero đều có thể tử trận; hồ sơ được giữ tại công trình **Sử Điện Anh Hùng**. Dùng **1 Ngọc hồi sinh 7★** để hồi sinh một Hero về **100% HP**, không phí thêm. Xem [cơ chế và API](docs/HERO_CHRONICLE.md).

Công trình **[Thương Thuyền Khinh Khí](docs/SHOP_AIRSHIP.md)** là cửa hàng dạng khinh khí cầu tại căn cứ. Danh mục tạm bán vật phẩm dùng được, trang bị và Thiên Thư thường với giá **1 bạc/món**, gồm cả Ngọc hồi sinh 7★.

**Xây mới và nâng cấp công trình hoàn tất ngay**, không có thời gian chờ hoặc thanh đếm ngược. Công trình đang chờ từ bản cũ được hoàn tất khi đọc lại căn cứ. Xem [quy tắc xây dựng](docs/BASE_CONSTRUCTION.md).

**[Đại Sảnh Ma Thuật](docs/MAGIC_HALL.md)** tích hợp Thư viện, Giả kim và Nghiên cứu. Ba phân khu giữ chức năng nhưng không còn là công trình xây riêng.

**[Danh mục vật phẩm đề xuất](docs/ITEM_CATALOG_PROPOSAL.md)** tổng hợp vật phẩm hiện có và ý tưởng mở rộng để duyệt; đây chưa phải danh mục hoặc cân bằng đang triển khai.

Công trình **Đại Sảnh Liên Minh (`ALLIANCE_HALL`)** cho phép lập hội, tìm kiếm, gia nhập, quản lý thành viên và thông báo nội bộ sau khi vượt Tháp tầng 25 (chưa mở Công nghệ & Chiến tranh Liên minh).

## Cấu trúc

```text
client-godot/                   Client Godot, giao diện và diễn hoạt 3D
packages/shared/               Combat v2, sinh chỉ số, công thức, hằng số
packages/server/               Express API, domain services, Drizzle ORM
packages/server/drizzle/       Lịch sử migration (0000–0066)
packages/server/src/database/seeds/  Dữ liệu mẫu
docs/                          Tài liệu kỹ thuật hệ thống (PvE, Căn cứ, Đồ họa PC/Mobile, ...)
docs/design_drafts/            Đặc tả/checklist lịch sử P0–P3
scripts/                       Build cleanup, encoding, seed hành tinh, test Godot và tài liệu API
```

## Trạng thái hiện tại

| Hệ thống | Backend | Client Godot |
|---|---|---|
| Tài khoản, Master, World | JWT có thu hồi phiên, định danh, mã khôi phục, lưu PostgreSQL | Có đăng nhập/đăng ký, tab Bảo mật & Tài khoản trong Hồ sơ Master; vẫn giữ auto-demo khi mở game để test nhanh |
| Gacha | Pool theo trọng số cố định, giao dịch nguyên tử, idempotency, lịch sử summon | Hai banner, chọn ngang, xem tỷ lệ, lịch sử triệu hồi, đổi Thiên Thư nhanh, triệu hồi ×1/×10 và chống double-submit |
| Hero | Sinh instance ngẫu nhiên, huấn luyện, kỹ năng, đổi nghề, thức tỉnh, ấn ký, thăng sao | Thẻ Hero dùng chung 1–7★ (`CardGridBrowser`), chi tiết 3D, khóa/đột phá/ấn ký/trang bị/thăng sao |
| Căn cứ & HUD chính | Hai tầng và 16 ô mở từ đầu, xây/nâng cấp tức thì, sản xuất, cư trú và phân công Hero | Căn cứ 3D với thanh tài nguyên, nút góc nhìn T1/T2/Toàn cảnh và danh mục xây dựng |
| Sinh tồn, y tế, rèn & kho | Có API đầy đủ và lưu trạng thái | Bếp/tâm lý, ký túc xá, hồi phục, lò rèn (`ItemGridBrowser` + lọc `+15`) và Nhà Kho tổng hợp mọi vật phẩm theo phân loại + thu hồi đồ rơi tầng |
| Giả kim và công nghệ | Nghiên cứu tức thì, chế ba loại thuốc, dược liệu 1–7★ và tiến độ theo Master | Cây Giả kim, chế/dùng thuốc và thẻ kho vật phẩm 1–7★ trong Đại Sảnh; [hướng dẫn](docs/ALCHEMY_PVE_CONSUMABLES.md) |
| PvE, Hầm Ngục & Viễn Chinh Hành Tinh 3D | Tháp PvE và Combat v2; Hầm Ngục Cổ Đại đang phát triển; Viễn Chinh sau tầng 25 có hành tinh `600×300`, tàu bay, Hầm Ngục Nổi và cứu hộ | Map Tháp, thẻ Hầm Ngục đang phát triển và `WorldRtsMap` hành tinh 3D |
| Cửa hàng khinh khí cầu | Danh mục, mua bằng bạc, chống trả tiền hai lần | Mô hình khinh khí cầu và giao diện mua hàng auto-fit thẻ 92×92 Godot |
| Sự kiện, nhiệm vụ, hòm thư & Bách khoa | API LiveOps, nhiệm vụ, thành tựu, hòm thư, sổ giao dịch ví & dữ liệu từ điển | `EventsQuestsModal`, `MailboxModal`, chấm đỏ thông báo (Red-Dot), hàng đợi Toast mượt và `CodexModal` (Bách Khoa 4 tab trong Avatar Master) |
| Bạn bè, Liên minh & Chat 3 kênh SSE | API Bạn bè + tặng quà ngày + chặn chat, Liên minh cơ bản, Chat 3 kênh + SSE Stream (`/api/chat/stream`; Thế Giới in-memory, Liên Minh & Riêng Tư lưu DB) | `FriendsModal` (3 tab), công trình 3D `ALLIANCE_HALL` → `AllianceModal`, `ChatPanelModal` real-time SSE & liên kết chéo Bạn bè/Liên minh |
| Cài đặt đồ họa PC / Mobile | Chế độ Chunk Streaming tương thích Hybrid & PC mở rộng | Tự động nhận diện thiết bị (`DeviceProfile`): Mobile khóa **Hybrid** an toàn (`R ≤ 12`), PC mở khóa toàn bộ tới `ULTRA` / `PLANET_WIDE` — tập trung 100% tại **Avatar Master → Tab Cài Đặt**; xem [chuẩn đồ họa PC/Mobile](docs/WORLD_MAP_GRAPHICS_PC_MOBILE.md) |
| Vận hành | Admin API key, cấu hình, audit, analytics, hỗ trợ | Có gửi ticket trong hồ sơ; console quản trị Web cũ đã gỡ |

## Tiến độ mở khóa

Tiến độ mở khóa dựa trên **tầng Tháp cao nhất đã vượt**. Hai tầng căn cứ và công trình cơ bản mở từ đầu; vượt tầng 5 mở Thương Thuyền và mục Hầm Ngục Cổ Đại đang phát triển; vượt tầng 10 mở Đại Sảnh Ma Thuật và thêm một Khu Huấn Luyện, sau đó mỗi 10 tầng mở thêm một khu; vượt tầng 25 mở Liên Minh, Viễn Chinh và Cảng Tàu Bay. Các tầng Tháp đã mở có thể chơi lại. Khu Cư Trú và Biệt Thự Tổ Đội là hai công trình độc lập. EXP và cấp Master không còn được sử dụng.

Chi tiết và ý nghĩa `currentFloor`: [Tiến độ Tháp](docs/TOWER_PROGRESSION.md).

## Quy tắc gacha hiện hành

Mỗi lượt chọn trực tiếp từ các dòng đang bật trong `summon_reward_pool`: xác suất = trọng số dòng / tổng trọng số. **Không có pity hoặc lượt bảo đảm**; quay ×10 là 10 lượt theo cùng cơ chế.

| Banner seed | Chi phí/lượt | Phân bố kết quả |
|---|---|---|
| `banner-001` / NORMAL | 1 Thiên Thư thường | Hero 1★: 27%, 2★: 18%, 3★: 5%; vật liệu: 50% |
| `banner-002` / SPECIAL | 100 Gem | Hero 2★: 30%, 3★: 16%, 4★: 3,6%, 5★: 0,4%; vật liệu: 50% |

- Đây là tỷ lệ từ seed hiện tại, không phải xác suất cố định cho mọi banner do operator tạo. API trả `costType`, `costPerRoll` và `rates` theo banner/pool đang lưu.
- Chi phí SPECIAL nằm ở `GAME_CONSTANTS.GACHA.SPECIAL_BANNER_GEM_COST_PER_ROLL`. NORMAL dùng scroll thường; LIMITED vẫn được backend hỗ trợ bằng scroll LIMITED nhưng chưa có trong cặp banner seed.
- Mỗi phần thưởng Hero tạo instance riêng, kể cả trùng template cố định. Bỏ phân loại Hero theo nguồn và đặc quyền sinh tử; giữ các cách triệu hồi hiện có.
- Yêu cầu summon cần `Idempotency-Key`; gửi lại cùng khóa không trừ tài nguyên hoặc tạo kết quả lần nữa.
- Đổi 1 scroll thường tốn 10.000 Silver, tối đa 50/tuần, reset thứ Năm 00:00 UTC+7.
- Tỷ lệ được cấu hình qua pool của banner. `GACHA_PITY` đã bị loại khỏi các loại cấu hình được tạo/kích hoạt. Analytics không còn trả `averagePityAtFiveStar`.
- Bảng `master_banner_pity` và các cột pity trong session/history được giữ để tương thích dữ liệu và migration cũ. Summon mới không dùng bộ đếm; các cột lịch sử của lượt mới ghi 0.

## Chạy local

Yêu cầu: Node.js 22 (cùng phiên bản chính với CI), npm, PostgreSQL 17 hoặc Docker Compose, và Godot phù hợp với project. `project.godot` hiện khai báo Godot 4.7 / Forward Plus.

```powershell
npm ci
docker compose up -d postgres
Copy-Item packages/server/.env.example packages/server/.env
```

Đặt `AUTH_SECRET` riêng trong `.env`; đặt `ADMIN_API_KEY` nếu dùng API quản trị. Database mặc định ở `localhost:5433/infinite_gacha`.

```powershell
npm run db:migrate
npm run db:seed
node scripts/seed-planet-world.mjs
npm run build
npm run dev:server
```

Import `client-godot/project.godot` bằng Godot rồi bấm F5. API mặc định là `http://127.0.0.1:3000`, cấu hình tại `client-godot/scripts/network/api_client.gd`.

Với database local đã có dữ liệu từ bản trước, chạy `npm run db:upgrade` rồi `npm run build` và `npm run dev:server`. Lệnh upgrade áp dụng migration còn thiếu, bổ sung danh mục Liên Minh/Cảng Tàu Bay và seed bản đồ hành tinh; không chạy lại toàn bộ seed mẫu. Căn cứ cũ nằm trên biển được chuyển sang đất liền. Sao lưu database trước khi nâng cấp.

`dev:server` theo dõi file JavaScript đã build; sau khi sửa TypeScript cần build lại. Không còn lệnh `dev:client` cho Web.

Seed runner dùng `DATABASE_URL` của process hoặc URL mặc định; nếu dùng DB khác, đặt biến môi trường cho các lệnh seed. `db:seed` áp dụng 23 file theo thứ tự phụ thuộc, bao gồm hai banner; chạy lại sẽ cập nhật pool và thời gian banner, vì vậy chỉ dùng với dữ liệu phát triển.

## Kiểm tra

```powershell
npm run build
node --test --test-force-exit packages/server/tests/http.tower-unlocks.test.mjs
```

- Theo `AGENTS.md`, chỉ chạy kiểm tra có mục tiêu; không chạy `npm run verify`, `npm test` hoặc toàn bộ suite nếu người dùng chưa yêu cầu. HTTP integration cần database test đã migrate và seed, đặt `DATABASE_URL` tới database đó.
- HTTP integration test có thể skip nếu PostgreSQL không truy cập được. Cần xem số `skipped` để phân biệt kết quả unit test với xác nhận đầy đủ DB.
- CI dựng PostgreSQL 17, migrate, seed rồi chạy `verify`.
- Kiểm tra này không chạy engine Godot. Giao diện, camera, replay và luồng tương tác cần được kiểm tra trong Godot.

Kiểm tra PvE bằng engine đã cài, với database test đã migrate và seed:

```powershell
$env:DATABASE_URL='postgres://postgres:postgres@localhost:5433/infinite_gacha_pve_verify_test'
$env:GODOT_BIN='C:\path\to\godot_console.exe'
npm run test:godot:pve
npm run test:godot:pve -- --integration
npm run test:godot:pve -- --exploration
npm run test:godot:pve:recovery
```

Hai bộ HTTP/engine tích hợp dùng tài khoản tạm và xóa chúng sau kiểm thử. Kiểm thử recovery khởi động ba process game, khởi động lại API hai lần và cố ý làm mất phản hồi của một lệnh đã được server ghi nhận. Kiểm thử headless không thay thế việc đánh giá trực quan camera, âm thanh, input và bản export.

## Vòng chơi PvE

Từ cổng **Chinh phạt** ở căn cứ, tạo hoặc chọn đội 1–5 Hero, xếp chín vị trí và chọn ưu tiên mục tiêu/thứ tự kỹ năng. Triển khai tối đa ba đội; mỗi lần triển khai tiêu thụ 10 FOOD/Hero. Hero đi map được giữ riêng và cần thu hồi trước khi thay đội hình, trang bị hoặc phân công tại căn cứ.

Bấm ô để ra lệnh đi bốn hướng. Mỗi bước mất một giây theo đồng hồ server; map cập nhật mỗi giây. Bật auto cho từng đội để tự khám phá, thu tài nguyên và đánh boss; auto dừng khi thua, hòa hoặc kiệt sức. Hero đầu tiên còn sống của đội xuất hiện trên map. Chiến báo là bản xem lại kết quả đã lưu; các đội khác tiếp tục di chuyển. Hạ boss mở tầng tiếp theo và thu hồi các đội còn sống. Người chơi chủ động bấm vào tầng mới.

Tầng mới dùng ba cấp map: tổng quan 1 km/ô, khu vực 50 m/ô và công trình 5 m/ô; nhiều công trình có thể cùng nằm trong một ô tổng quan. Quái có radar bị chặn bởi địa hình, đuổi qua cửa và phục kích khi đội chưa nhìn thấy trước tiếp xúc. Auto khám phá công trình phụ rồi tìm boss được chỉ định trong mục tiêu tầng. Tầng cũ đang chơi giữ nguyên cơ chế trước tới khi hoàn thành.

Tiến độ và phần thưởng được xử lý khi đọc trạng thái hoặc gửi lệnh. Khi game/API ngừng chạy, thời điểm đến vẫn nằm trong PostgreSQL và được quyết toán lần đọc tiếp theo. Không cần Redis cho prototype này. Luồng PvE mới dùng `/api/pve`; API dungeon/session cũ vẫn tồn tại nhưng không chạy đồng thời với một map PvE đang mở. Chi tiết ở [đặc tả triển khai](docs/PVE_IMPLEMENTATION.md) và [OpenAPI PvE](openapi.pve.yaml).

## Phần còn lại

1. Chơi thử trực quan và cân bằng PvE bằng đội Hero có chỉ số thực tế; hoàn thiện asset, VFX và khả năng sử dụng trên màn hình mục tiêu.
2. Mở rộng thêm khi có nhu cầu: Bảng xếp hạng, Công nghệ Liên minh, Chiến tranh Liên minh.
3. Thay auto-login demo bằng luồng tài khoản và lưu phiên phù hợp khi đóng gói bản phát hành (hiện giữ auto-demo để test nhanh).
4. Thay mô phỏng OAuth/IAP bằng tích hợp nhà cung cấp thật. Hiện xác minh bằng HMAC; refund mới thu hồi Gem, chưa thu hồi Silver/item đính kèm.
5. Bổ sung Redis/timer dùng chung cho nhiều API instance và cân bằng dữ liệu mẫu.
6. Kiểm thử trực tiếp Godot, âm thanh/asset, hiệu năng và export cho nền tảng mục tiêu.

## Tài liệu

- [Hướng dẫn client Godot](client-godot/README.md)
- [Backlog Godot hiện tại](GODOT_BACKLOG.md)
- [Đặc tả Combat v2](Combat_V2_Spec.md)
- [Danh sách API sinh từ source](API_Routes.md), [OpenAPI PvE](openapi.pve.yaml) và [OpenAPI Combat v2](openapi.combat-v2.yaml)
- [Kho thiết kế P0–P3 lịch sử](docs/design_drafts/README.md)
- [Ghi chú bàn giao](AGENT_HANDOFF_NOTES.md)
