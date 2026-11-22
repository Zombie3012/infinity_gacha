# Infinite Gacha

Game quản lý Hero, sinh tồn và chiến thuật. Client hiện tại là **Godot 3D isometric**, kết nối REST API Node.js/Express và PostgreSQL. Web React/Vite đã được gỡ khỏi workspace.

Cập nhật: **22/11/2026 (UTC+7)**. Đây là bản prototype đang hoàn thiện, với dữ liệu cân bằng mẫu; các checklist P0–P3 cũ không có nghĩa toàn bộ game đã sẵn sàng phát hành.

Hero và vật liệu dùng độ hiếm **1–7★**. Mọi Hero đều có thể tử trận; hồ sơ được giữ tại công trình **Sử Điện Anh Hùng**. Dùng **1 Ngọc hồi sinh 7★** để hồi sinh một Hero về **100% HP**, không phí thêm. Xem [cơ chế và API](docs/HERO_CHRONICLE.md).

Công trình **[Thương Thuyền Khinh Khí](docs/SHOP_AIRSHIP.md)** là cửa hàng dạng khinh khí cầu tại căn cứ. Danh mục tạm bán vật phẩm dùng được, trang bị và Thiên Thư thường với giá **1 bạc/món**, gồm cả Ngọc hồi sinh 7★.

**Xây mới và nâng cấp công trình hoàn tất ngay**, không có thời gian chờ hoặc thanh đếm ngược. Công trình đang chờ từ bản cũ được hoàn tất khi đọc lại căn cứ. Xem [quy tắc xây dựng](docs/BASE_CONSTRUCTION.md).

**[Đại Sảnh Ma Thuật](docs/MAGIC_HALL.md)** tích hợp Thư viện, Giả kim và Nghiên cứu. Ba phân khu giữ chức năng nhưng không còn là công trình xây riêng.

## Cấu trúc

```text
client-godot/                   Client Godot, giao diện và diễn hoạt 3D
packages/shared/               Combat v2, sinh chỉ số, công thức, hằng số
packages/server/               Express API, domain services, Drizzle ORM
packages/server/drizzle/       Lịch sử migration (0000–0052)
packages/server/src/database/seeds/  Dữ liệu mẫu
docs/design_drafts/            Đặc tả/checklist lịch sử P0–P3
scripts/                       Build cleanup, encoding, seed và tài liệu API
```

## Trạng thái hiện tại

| Hệ thống | Backend | Client Godot |
|---|---|---|
| Tài khoản, Master, World | JWT có thu hồi phiên, khởi tạo và lưu PostgreSQL | Có đăng nhập/đăng ký; scene khởi động hiện tự dùng tài khoản demo |
| Gacha | Pool theo trọng số cố định, giao dịch nguyên tử, idempotency, lịch sử summon | Hai banner, chọn ngang, xem tỷ lệ, triệu hồi ×1/×10 và hiệu ứng kết quả |
| Hero | Sinh instance ngẫu nhiên, huấn luyện, kỹ năng, đổi nghề, thức tỉnh, ấn ký, thăng sao | Danh sách/thẻ Hero, chi tiết 3D, trang bị và các thao tác phát triển |
| Căn cứ | Xây/nâng cấp, mở rộng, sản xuất và phân công Hero | Căn cứ 3D, thao tác công trình và các modal chuyên dụng |
| Sinh tồn, y tế, chế tạo | Có API và lưu trạng thái | Có giao diện bếp, ký túc xá, hồi phục, rèn và kho; cần kiểm thử toàn luồng trong engine |
| Giả kim và công nghệ | Nghiên cứu tức thì, chế ba loại thuốc, dược liệu 1–7★ và tiến độ theo Master | Cây Giả kim, chế/dùng thuốc trong Đại Sảnh; [hướng dẫn](docs/ALCHEMY_PVE_CONSUMABLES.md) |
| PvE map / Combat v2 | Map ba cấp, radar/phục kích, ba đội, năm ô tiêu hao/Hero; auto hoặc thủ công 10 giây/lượt | Điều quân, cấu hình thuốc, điều khiển kỹ năng/mục tiêu/vật phẩm, đội hình 3×3 và replay |
| Cửa hàng khinh khí cầu | Danh mục, mua bằng bạc, chống trả tiền hai lần | Mô hình khinh khí cầu và giao diện mua hàng Godot |
| Nhiệm vụ, mail, LiveOps, bảng xếp hạng, IAP | Có API prototype | Chưa có luồng Godot đầy đủ |
| Thế giới, PvP, liên minh, chiến tranh | Có API; PvP Hero dùng Combat v2, siege Kỳ Quan dùng so sánh sức mạnh | Chưa có bản đồ và luồng Godot đầy đủ |
| Vận hành | Admin API key, cấu hình, audit, analytics, hỗ trợ | Có gửi ticket trong hồ sơ; console quản trị Web cũ đã gỡ |

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
npm run build
npm run dev:server
```

Import `client-godot/project.godot` bằng Godot rồi bấm F5. API mặc định là `http://127.0.0.1:3000`, cấu hình tại `client-godot/scripts/network/api_client.gd`.

`dev:server` theo dõi file JavaScript đã build; sau khi sửa TypeScript cần build lại. Không còn lệnh `dev:client` cho Web.

Seed runner dùng `DATABASE_URL` của process hoặc URL mặc định; nếu dùng DB khác, đặt biến môi trường cho các lệnh seed. `db:seed` áp dụng 23 file theo thứ tự phụ thuộc, bao gồm hai banner; chạy lại sẽ cập nhật pool và thời gian banner, vì vậy chỉ dùng với dữ liệu phát triển.

## Kiểm tra

```powershell
npm run verify
npm run docs:routes
```

- `verify`: kiểm tra encoding → build shared/server → test Node.js. Build xóa `dist` tương ứng trước khi biên dịch để không giữ module đã xóa.
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
2. Hoàn thiện UI Godot cho nhiệm vụ, mail, sự kiện, bản đồ và liên minh.
3. Thay auto-login demo bằng luồng tài khoản và lưu phiên phù hợp bản phát hành.
4. Thay mô phỏng OAuth/IAP bằng tích hợp nhà cung cấp thật. Hiện xác minh bằng HMAC; refund mới thu hồi Gem, chưa thu hồi Silver/item đính kèm.
5. Bổ sung Redis/timer dùng chung cho nhiều API instance, rà soát siege Kỳ Quan và cân bằng dữ liệu mẫu.
6. Kiểm thử trực tiếp Godot, âm thanh/asset, hiệu năng và export cho nền tảng mục tiêu.

## Tài liệu

- [Hướng dẫn client Godot](client-godot/README.md)
- [Backlog Godot hiện tại](GODOT_BACKLOG.md)
- [Đặc tả Combat v2](Combat_V2_Spec.md)
- [Danh sách API sinh từ source](API_Routes.md), [OpenAPI PvE](openapi.pve.yaml) và [OpenAPI Combat v2](openapi.combat-v2.yaml)
- [Kho thiết kế P0–P3 lịch sử](docs/design_drafts/README.md)
- [Ghi chú bàn giao](AGENT_HANDOFF_NOTES.md)
