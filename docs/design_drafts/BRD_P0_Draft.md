# Business Requirements Document (BRD) - P0

> **L?u tr? thi?t k? l?ch s?.** Checklist v? k?t qu? ki?m tra ph?n ?nh th?i ?i?m vi?t; c?c m? t? Web/Unity, pity v? duplicate c? th? ?? ???c thay th?. Xem [README hi?n h?nh](../../README.md) v? [backlog Godot](../../GODOT_BACKLOG.md), c?p nh?t 22/11/2026 (UTC+7).

| Field | Value |
|---|---|
| Document ID | IG-BA-BRD-P0-001 |
| Version | 0.2 Draft |
| Project | Infinite Gacha |
| Source of truth | MBFL.docx and Phase_Scope_Matrix_P0.csv |
| Status | Draft for review |

> This document translates the approved P0 scope into reviewable business requirements. Unknown details remain TBD; this draft does not define unapproved game rules.

## 1. Purpose

Define the P0 business scope and trace its 164 functions in the current P0 draft matrix to the Master Business Function List. Use this document as the basis for detailed use cases and acceptance criteria.

## 2. Scope

### Included in P0

- Account registration/login/security and single-Master lifecycle. Account Linking and Account Recovery are P1.
- Gacha banners, summon items, summon results, Hero collection/development, Pity, duplicate conversion, and summon-origin recording.
- Hero death processing for Normal and Special/Limited origins.
- Party, formation, auto battle, Hero AI, Master commands, and battle results.
- Minimal World initialization for Dungeon Seed, Dungeon setup, floor progression, exploration, encounters, and rewards; expanded World/Base progression remains P1.
- Basic inventory and equipment state (view, equip, unequip, validation, and stat calculation) to support P0 death drops. Equipment progression/crafting remains P1.
- The minimum Silver Coin / normal summon-scroll exchange loop.
- P0 administration: Gacha/Dungeon configuration, system monitoring, audit, and security.

### Excluded from P0

- P1: account linking and account recovery; expanded World/Base progression; personality/loyalty/relationships; medical recovery; survival; advanced equipment progression and crafting; expanded economy and quests.
- P2: IAP/payment, live operations, event operations, analytics beyond P0 monitoring.
- P3: global multiplayer, PvP, alliances, wars, and world conquest. PvP begins after PvE is complete.
- Third-party account linking (Google, Apple, and similar) and account recovery are deferred to P1.
- Acquisition setup for red Limited and seven-color Special summon items is deferred; their summon result types are represented in the scope.

## 3. Actors

| Code | Actor | Description |
|---|---|---|
| ACT-01 | Player | Người chơi |
| ACT-02 | Master | Vai trò chỉ huy trong game |
| ACT-03 | Game System | Hệ thống game tự xử lý |
| ACT-04 | Game Admin | Quản trị viên |
| ACT-05 | Game Operator | Nhân viên vận hành |
| ACT-06 | Game Designer | Người thiết kế game |
| ACT-07 | Payment Gateway | Hệ thống thanh toán bên ngoài |
| ACT-08 | Customer Support | Nhân viên hỗ trợ |

## 4. Confirmed business rules

| Rule ID | Domain | Rule |
|---|---|---|
| BR-01-001 | Player | Quy tắc: mỗi tài khoản chỉ có duy nhất một Master. |
| BR-01-002 | Player | Quy tắc tăng cấp Master |
| BR-02-001 | Gacha | Quy tắc tỷ lệ triệu hồi |
| BR-02-002 | Gacha | Pity applies to all banners; each banner has a separate counter, with no carry-over between banners. |
| BR-02-003 | Gacha | Quy tắc Summon Origin |
| BR-03-001 | Hero | Quy tắc tạo Hero Instance |
| BR-03-002 | Hero | Quy tắc phát triển Hero |
| BR-04-001 | Hero Death | Hero Normal tử trận vĩnh viễn; trang bị đang mặc rơi ra, tài nguyên đã dùng để nâng cấp/huấn luyện không được hoàn trả. |
| BR-04-002 | Hero Death | Special/Limited Hero Disabled |
| BR-05-001 | Party | Điều kiện Hero tham gia đội hình |
| BR-06-001 | Combat | Auto Battle |
| BR-06-002 | Combat | Master có thể thay Tactical Buff trong trận; mỗi lần thay đổi cách nhau tối thiểu 15 giây. |
| BR-06-003 | Combat | Xử lý thương vong |
| BR-07-001 | Dungeon | Fixed Floor Progression |
| BR-07-002 | Dungeon | Seed được tạo khi khởi tạo World, quyết định độ khó của World và giữ cố định trong suốt vòng đời World. |
| BR-07-003 | Dungeon | Difficulty Generation |
| BR-10-001 | Inventory | Quy tắc sở hữu vật phẩm |
| BR-14-001 | Administration | Quyền quản trị |
| BR-14-002 | Administration | Audit Log |
| BR-14-003 | Administration | Configuration Versioning |
| BR-02-004 | Gacha | Chỉ Hero từ 5★ trở lên thuộc banner Limited/Special khi trùng mới chuyển đổi thành 1 Thiên Mệnh trên chính Hero đã sở hữu; Banner Normal và toàn bộ Hero <5★ khi triệu hồi luôn tạo cá thể Hero mới với chỉ số gốc ngẫu nhiên phục vụ thăng sao (Pick Me Up style) và tùy biến lối chơi. |
| BR-04-005 | Hero Death | Hero Normal tử trận làm rơi trang bị đang mặc; không hoàn trả tài nguyên nâng cấp/huấn luyện. |
| BR-06-004 | Combat | Cooldown thay Tactical Buff cố định 15 giây. |
| BR-07-004 | Dungeon | Seed phải duy nhất trên toàn game; sử dụng định danh UUID/GUID chuẩn toàn cầu khi khởi tạo World, không trùng lặp và không đổi khi thất bại. |
| BR-02-005 | Gacha | Vật phẩm triệu hồi gọi là Thiên Thư: màu trắng dùng cho triệu hồi thường, màu đỏ cho banner giới hạn, bảy màu cho banner đặc biệt. Chi phí: 1 vé cho 1 lượt triệu hồi (Single), 10 vé cho 10 lượt liên tiếp (Multi). |
| BR-11-003 | Economy | Xu Bạc là tiền tệ cơ bản; Ngọc là tiền tệ nạp. Dùng 10.000 Xu Bạc đổi một Thiên Thư thường, tối đa 50 vé mỗi tuần cố định; reset 00:00 thứ Năm theo UTC+7. Cách nhận vé giới hạn/vé đặc biệt và Ngọc sẽ cài đặt sau. |
| BR-02-006 | Gacha | Pity dùng chung đường cong cho mọi banner. Rolls 1-60: 0.4% five-star, 49.6% Hero (1★-4★), 50.0% nguyên liệu. Khi xác suất 5 sao tăng ở rolls 61-70, xác suất còn lại tiếp tục chia theo tỷ lệ gốc 49.6:50. Dùng P_n = 0.4% + (100% - 0.4%) * ((n - 60) / 10)^4, k=4. Roll 70 bảo đảm Hero 5 sao bất kỳ trong pool banner hiện tại, không riêng Limited/Featured. Reset sau mọi Hero 5 sao; pity tách riêng giữa các banner. |
| BR-08-003 | Private World | Khởi tạo World tối thiểu cho Master thuộc P0, là tiền đề tạo Seed và vào Dungeon; Base/World progression nâng cao thuộc P1. |
| BR-10-002 | Inventory & Equipment | Trang bị cơ bản (xem, trang bị, tháo, kiểm tra, tính chỉ số) thuộc P0 để hỗ trợ quy tắc rơi trang bị khi Hero Normal tử trận; nâng cấp/crafting thuộc P1. |

### Pity probability curve & Pool breakdown

- Pity applies to every banner using the same curve; each banner keeps a separate counter, and counters do not carry between banners.
- Base pool on rolls 1-60:
  - 5-star Hero: 0.40%
  - Other Heroes (1-star to 4-star): 49.60%
  - Misc / Materials (Nguyên liệu vặt): 50.00%
  - Total pool: 100% (50% Hero / 50% Materials).
- For roll number `n` from 60 through 70: `P_n = 0.4% + (100% - 0.4%) * ((n - 60) / 10)^4`. The exponent is `k = 4`.
- As `P_n` rises, split the remaining probability between 1–4-star Heroes and Materials in the confirmed base ratio `49.6:50`.
- Roll 70 guarantees any five-star Hero in the active banner pool. It does not guarantee a Limited or Featured Hero.
- Reset the banner counter after any five-star Hero is obtained.

### Summon-item and currency rules

- Summon items are called Heavenly Scrolls: white = Normal, red = Limited, seven-color = Special.
- Cost: 1 scroll for Single Summon; 10 scrolls for Multi Summon (10 rolls). No automatic 4-star guarantee on Multi.
- Silver Coins are basic currency; Gems are premium currency. One white Normal Heavenly Scroll costs 10,000 Silver Coins.
- A player may exchange for at most 50 white Normal Heavenly Scrolls per fixed week. Reset is Thursday at 00:00 UTC+7.
- Acquisition settings for red Limited and seven-color Special scrolls, and Gem acquisition, are later configuration.
- Duplicate handling: Only 5★+ duplicate Heroes on Special/Limited banners convert into 1 "Thien Menh" on the owned Hero. Normal banner summons and all <5★ Hero summons generate new independent Hero instances with level-1 rolled base stats (STR/INT/STA/AGI), class, and elemental affinities for specialized builds and Star Promotion fodder (Pick Me Up style).

### Hero death, combat, and Dungeon rules

- A Normal Hero dies permanently, drops equipped gear, and does not refund upgrade or training resources.
- A Special/Limited-origin Hero becomes Disabled on death; detailed recovery is outside P0.
- The Master may change Tactical Buffs during battle with a fixed 15-second cooldown.
- A World receives a fixed Seed generated as a globally unique UUID/GUID at creation. The Seed determines World difficulty, stays fixed, and does not change on failure.
- Combat damage calculation and EXP progression formulas are represented structurally in the data model (placeholders with concrete parameters finalized later).
- PvP is deferred until PvE is complete.

## 5. Indicative P0 flows

1. **Account and Master:** register/login -> initialize exactly one Master -> create/initialize World.
2. **Summoning:** select an active banner -> validate and consume the relevant summon item -> calculate result and Pity -> create Hero Instance -> record its immutable summon origin. Exact resource consumption for each banner remains TBD where not specified.
3. **Hero preparation:** view the collection -> develop Hero/skills -> assign Hero to a party and formation. Detailed costs and progression formulas remain TBD.
4. **Dungeon battle:** enter a floor in the World with its fixed Seed -> generate/explore encounters -> run auto battle with Hero AI and Master commands -> process result, rewards, and Hero death state. Generation and combat formulas remain TBD.
5. **Normal scroll acquisition:** obtain Silver Coins -> exchange 10,000 Silver Coins for one white scroll, subject to the weekly cap and Thursday 00:00 UTC+7 reset. Sources of Silver Coin rewards are configured by other reward functions.

## 6. P0 functional requirements and traceability

Every row below is a draft requirement traced to the corresponding `Function ID`. Priority and dependencies are carried over from the P0 matrix. Dependency alternatives are marked `Any one of`; Domain-level dependencies remain as recorded. Detailed acceptance criteria will be written in the use-case specifications.

### DM-01

#### MOD-01-01 - Account Management

| Function ID | Function | Business description | Actor | Priority | Dependency |
|---|---|---|---|---|---|
| FUN-01-01-001 | Register Account – Đăng ký tài khoản | Tạo tài khoản người chơi mới | ACT-01, ACT-03 | Must | — |
| FUN-01-01-002 | Login – Đăng nhập | Xác thực người chơi | ACT-01, ACT-03 | Must | FUN-01-01-001 |
| FUN-01-01-003 | Logout – Đăng xuất | Kết thúc phiên đăng nhập | ACT-01, ACT-03 | Must | FUN-01-01-002 |
| FUN-01-01-006 | Account Security – Bảo mật tài khoản | Kiểm tra và quản lý trạng thái bảo mật | ACT-01, ACT-03 | Must | FUN-01-01-002 |
#### MOD-01-02 - Player Profile

| Function ID | Function | Business description | Actor | Priority | Dependency |
|---|---|---|---|---|---|
| FUN-01-02-001 | View Player Profile – Xem hồ sơ | Hiển thị thông tin người chơi | ACT-01 | Must | FUN-01-01-002 |
| FUN-01-02-002 | Update Player Profile – Cập nhật hồ sơ | Thay đổi tên, avatar và thông tin cho phép | ACT-01 | Should | FUN-01-01-002 |
| FUN-01-02-003 | Player Settings – Cài đặt người chơi | Quản lý ngôn ngữ, âm thanh, thông báo | ACT-01 | Should | FUN-01-02-002 |
| FUN-01-02-004 | Player Progress – Tiến trình người chơi | Theo dõi tiến trình tổng thể | ACT-01, ACT-03 | Must | FUN-01-02-001 |
#### MOD-01-03 - Master Progression

| Function ID | Function | Business description | Actor | Priority | Dependency |
|---|---|---|---|---|---|
| FUN-01-03-001 | Initialize Master – Khởi tạo Master | Tạo Master khi bắt đầu game | ACT-03 | Must | FUN-01-01-002 |
| FUN-01-03-002 | View Master Profile – Xem hồ sơ Master | Hiển thị thông tin và chỉ số Master | ACT-01 | Must | FUN-01-03-001 |
| FUN-01-03-003 | Master EXP – Quản lý kinh nghiệm | Tích lũy và cập nhật EXP | ACT-03 | Must | FUN-01-03-001 |
| FUN-01-03-004 | Master Level Up – Tăng cấp Master | Tăng cấp khi đủ điều kiện | ACT-03 | Must | FUN-01-03-003 |
| FUN-01-03-005 | Master Skill Management – Quản lý kỹ năng | Mở khóa và nâng cấp kỹ năng Master | ACT-01, ACT-03 | Should | FUN-01-03-004 |
| FUN-01-03-006 | Feature Unlock – Mở khóa tính năng | Mở tính năng dựa trên điều kiện tiến trình | ACT-03 | Must | FUN-01-03-004 |
### DM-02

#### MOD-02-01 - Banner Management

| Function ID | Function | Business description | Actor | Priority | Dependency |
|---|---|---|---|---|---|
| FUN-02-01-001 | View Banner List – Danh sách banner | Hiển thị banner đang hoạt động | ACT-01 | Must | — |
| FUN-02-01-002 | View Banner Detail – Chi tiết banner | Hiển thị thông tin, thời hạn, Hero Pool và tỷ lệ | ACT-01 | Must | FUN-02-01-001 |
| FUN-02-01-003 | Configure Banner – Cấu hình banner | Tạo và cấu hình banner | ACT-04, ACT-05 | Must | — |
| FUN-02-01-004 | Configure Hero Pool – Cấu hình Hero Pool | Thiết lập Hero có thể được triệu hồi | ACT-04, ACT-06 | Must | FUN-02-01-003 |
| FUN-02-01-005 | Banner Schedule – Lịch banner | Thiết lập thời gian hoạt động | ACT-05 | Must | FUN-02-01-003 |
| FUN-02-01-006 | Activate Banner – Kích hoạt banner | Kích hoạt banner theo lịch | ACT-03, ACT-05 | Must | FUN-02-01-005 |
#### MOD-02-02 - Normal Summon

| Function ID | Function | Business description | Actor | Priority | Dependency |
|---|---|---|---|---|---|
| FUN-02-02-001 | Normal Single Summon – Triệu hồi thường 1 lần | Thực hiện triệu hồi thường bằng Thiên Thư màu trắng. | ACT-01, ACT-03 | Must | FUN-02-01-006 |
| FUN-02-02-002 | Normal Multi Summon – Triệu hồi thường nhiều lần | Thực hiện triệu hồi thường bằng Thiên Thư màu trắng. | ACT-01, ACT-03 | Must | FUN-02-02-001 |
| FUN-02-02-003 | Normal Summon Result – Kết quả triệu hồi thường | Trả kết quả và tạo Hero Instance | ACT-03 | Must | FUN-02-02-001 |
| FUN-02-02-004 | Normal Summon History – Lịch sử triệu hồi | Tra cứu lịch sử | ACT-01 | Should | FUN-02-02-003 |
#### MOD-02-03 - Special & Limited Summon

| Function ID | Function | Business description | Actor | Priority | Dependency |
|---|---|---|---|---|---|
| FUN-02-03-001 | Special Single Summon – Triệu hồi đặc biệt 1 lần | Thực hiện triệu hồi đặc biệt bằng Thiên Thư bảy màu; cơ chế nhận vé cài đặt sau. | ACT-01, ACT-03 | Must | FUN-02-01-006 |
| FUN-02-03-002 | Special Multi Summon – Triệu hồi đặc biệt nhiều lần | Thực hiện triệu hồi đặc biệt bằng Thiên Thư bảy màu; cơ chế nhận vé cài đặt sau. | ACT-01, ACT-03 | Should | FUN-02-03-001 |
| FUN-02-03-003 | Limited Single Summon – Triệu hồi giới hạn 1 lần | Thực hiện triệu hồi giới hạn bằng Thiên Thư màu đỏ; cơ chế nhận vé cài đặt sau. | ACT-01, ACT-03 | Should | FUN-02-03-001 |
| FUN-02-03-004 | Limited Multi Summon – Triệu hồi giới hạn nhiều lần | Thực hiện triệu hồi giới hạn bằng Thiên Thư màu đỏ; cơ chế nhận vé cài đặt sau. | ACT-01, ACT-03 | Should | FUN-02-03-001 |
| FUN-02-03-005 | Special Summon Result – Kết quả đặc biệt | Xử lý kết quả và gán Summon Origin | ACT-03 | Must | FUN-02-03-001 |
| FUN-02-03-006 | Limited Summon Result – Kết quả giới hạn | Xử lý kết quả và gán Summon Origin | ACT-03 | Should | FUN-02-03-003 |
#### MOD-02-04 - Probability & Pity Management

| Function ID | Function | Business description | Actor | Priority | Dependency |
|---|---|---|---|---|---|
| FUN-02-04-001 | Configure Drop Rate – Cấu hình tỷ lệ | Configure the same Pity probability curve for all banners; base five-star rate is 0.4%, with k=4 exponential growth from roll 60 to 70. | ACT-04, ACT-06 | Must | FUN-02-01-004 |
| FUN-02-04-002 | Calculate Summon Probability – Tính xác suất | P_n = 0.4% + (100% - 0.4%) * ((n - 60) / 10)^4, for n=60..70; k=4. Applies to all banners. Roll 70 guarantees any five-star Hero in that banner pool, not necessarily Limited/Featured. | ACT-03 | Must | FUN-02-04-001 |
| FUN-02-04-003 | Update Pity Counter – Cập nhật Pity | Track a separate Pity counter per banner. Apply 0.4% on rolls 1-60, then P_n = 0.4% + (100% - 0.4%) * ((n - 60) / 10)^4, for n=60..70; k=4. Reset after any five-star; no counter carry-over between banners. | ACT-03 | Must | FUN-02-04-001 |
| FUN-02-04-004 | Guaranteed Reward – Bảo đảm phần thưởng | Bảo đảm nhận một Hero 5 sao bất kỳ ở lượt Pity 70; reset bộ đếm sau khi nhận Hero 5 sao. | ACT-03 | Must | FUN-02-04-003 |
| FUN-02-04-005 | Pity Isolation – Tách bộ đếm Pity theo banner | Maintain a separate Pity counter for each banner; apply the same probability curve to all banners and do not carry counters between banners. | ACT-03, ACT-04 | Should | FUN-02-04-003 |
| FUN-02-04-006 | View Pity Progress – Xem tiến trình Pity | Hiển thị số lượt đã tích lũy | ACT-01 | Should | FUN-02-04-003 |
#### MOD-02-05 - Duplicate & Summon Origin

| Function ID | Function | Business description | Actor | Priority | Dependency |
|---|---|---|---|---|---|
| FUN-02-05-001 | Duplicate Detection – Phát hiện Hero trùng | Kiểm tra Hero đã sở hữu | ACT-03 | Must | FUN-02-05-003 |
| FUN-02-05-002 | Duplicate Conversion – Chuyển đổi Hero trùng | Chuyển đổi thành tài nguyên theo quy tắc | ACT-03 | Should | FUN-02-05-001 |
| FUN-02-05-003 | Assign Summon Origin – Gán nguồn gốc | Gán và lưu Summon Origin không thay đổi cho Hero Instance cùng lúc xử lý kết quả triệu hồi: Normal, Special hoặc Limited. | ACT-03 | Must | Any one of: FUN-02-02-003; FUN-02-03-005; FUN-02-03-006 |
| FUN-02-05-004 | View Summon History – Xem lịch sử | Tra cứu kết quả các lượt triệu hồi | ACT-01 | Should | FUN-02-05-003 |
### DM-03

#### MOD-03-01 - Hero Collection

| Function ID | Function | Business description | Actor | Priority | Dependency |
|---|---|---|---|---|---|
| FUN-03-01-001 | View Hero List – Danh sách Hero | Hiển thị Hero người chơi sở hữu | ACT-01 | Must | FUN-02-02-003 |
| FUN-03-01-002 | View Hero Detail – Chi tiết Hero | Hiển thị thông tin chi tiết | ACT-01 | Must | FUN-03-01-001 |
| FUN-03-01-003 | Filter Hero – Lọc Hero | Lọc theo Rarity, Class, Status | ACT-01 | Should | FUN-03-01-001 |
| FUN-03-01-004 | Sort Hero – Sắp xếp Hero | Sắp xếp theo Level, Power, Rarity | ACT-01 | Should | FUN-03-01-001 |
| FUN-03-01-005 | Lock Hero – Khóa Hero | Ngăn thao tác nhầm trên Hero | ACT-01 | Should | FUN-03-01-001 |
| FUN-03-01-006 | View Hero History – Lịch sử Hero | Xem lịch sử phát triển và hoạt động | ACT-01 | Could | FUN-03-01-002 |
#### MOD-03-02 - Hero Attributes & Development

| Function ID | Function | Business description | Actor | Priority | Dependency |
|---|---|---|---|---|---|
| FUN-03-02-001 | View Hero Stats – Xem chỉ số | Xem HP, ATK, DEF, SPD và thuộc tính | ACT-01 | Must | FUN-03-01-002 |
| FUN-03-02-002 | Level Up Hero – Tăng cấp | Sử dụng EXP hoặc tài nguyên tăng cấp | ACT-01, ACT-03 | Must | FUN-03-02-001 |
| FUN-03-02-003 | Hero EXP Management – Quản lý EXP | Tích lũy và phân phối EXP | ACT-03 | Must | FUN-03-02-002 |
| FUN-03-02-004 | Hero Promotion – Thăng cấp bậc | Mở rộng giới hạn phát triển | ACT-01, ACT-03 | Should | FUN-03-02-002 |
| FUN-03-02-005 | Hero Awakening – Thức tỉnh | Mở khóa tiềm năng đặc biệt | ACT-01, ACT-03 | Should | FUN-03-02-004 |
| FUN-03-02-006 | Hero Evolution – Tiến hóa | Thay đổi cấp tiến hóa | ACT-01, ACT-03 | Could | FUN-03-02-004 |
#### MOD-03-03 - Hero Skill Management

| Function ID | Function | Business description | Actor | Priority | Dependency |
|---|---|---|---|---|---|
| FUN-03-03-001 | View Hero Skills – Xem kỹ năng | Xem danh sách kỹ năng | ACT-01 | Must | FUN-03-01-002 |
| FUN-03-03-002 | Unlock Hero Skill – Mở khóa kỹ năng | Mở khóa kỹ năng theo điều kiện | ACT-03 | Should | FUN-03-03-001 |
| FUN-03-03-003 | Upgrade Hero Skill – Nâng cấp kỹ năng | Nâng cấp hiệu quả kỹ năng | ACT-01, ACT-03 | Should | FUN-03-03-002 |
| FUN-03-03-004 | Configure Skill Behavior – Cấu hình hành vi kỹ năng | Cấu hình điều kiện AI sử dụng kỹ năng | ACT-01 | Could | FUN-03-03-001 |
### DM-04

#### MOD-04-01 - Death Classification & Processing

| Function ID | Function | Business description | Actor | Priority | Dependency |
|---|---|---|---|---|---|
| FUN-04-01-001 | Detect Hero Death – Phát hiện tử trận | Xác định Hero đã tử trận trong Battle | ACT-03 | Must | FUN-06-02-001 |
| FUN-04-01-002 | Determine Death Rule – Xác định quy tắc tử trận | Kiểm tra Summon Origin | ACT-03 | Must | FUN-04-01-001, FUN-02-05-003 |
| FUN-04-01-003 | Process Permadeath – Xử lý chết vĩnh viễn | Đánh dấu Hero Normal tử trận vĩnh viễn | ACT-03 | Must | FUN-04-01-002 |
| FUN-04-01-004 | Process Disabled State – Vô hiệu hóa Hero | Đánh dấu Hero Special/Limited bị vô hiệu hóa | ACT-03 | Must | FUN-04-01-002 |
| FUN-04-01-005 | Create Death Record – Lưu hồ sơ tử trận | Ghi nhận nguyên nhân và thời điểm tử trận | ACT-03 | Must | FUN-04-01-003, FUN-04-01-004 |
| FUN-04-01-006 | Update Hero Availability – Cập nhật khả năng sử dụng | Loại Hero không khả dụng khỏi đội hình và nhiệm vụ | ACT-03 | Must | FUN-04-01-003, FUN-04-01-004 |
### DM-05

#### MOD-05-01 - Party Management

| Function ID | Function | Business description | Actor | Priority | Dependency |
|---|---|---|---|---|---|
| FUN-05-01-001 | Create Party – Tạo đội hình | Tạo đội hình mới | ACT-01 | Must | FUN-03-01-001 |
| FUN-05-01-002 | Edit Party – Chỉnh sửa đội hình | Thay đổi thông tin đội hình | ACT-01 | Must | FUN-05-01-001 |
| FUN-05-01-003 | Delete Party – Xóa đội hình | Xóa đội hình không còn sử dụng | ACT-01 | Should | FUN-05-01-001 |
| FUN-05-01-004 | View Party – Xem đội hình | Xem danh sách đội hình | ACT-01 | Must | FUN-05-01-001 |
| FUN-05-01-005 | Set Default Party – Đặt đội hình mặc định | Chọn đội hình sử dụng mặc định | ACT-01 | Should | FUN-05-01-001 |
#### MOD-05-02 - Hero Assignment

| Function ID | Function | Business description | Actor | Priority | Dependency |
|---|---|---|---|---|---|
| FUN-05-02-001 | Add Hero to Party – Thêm Hero | Thêm Hero vào đội hình | ACT-01 | Must | FUN-05-01-001 |
| FUN-05-02-002 | Remove Hero from Party – Xóa Hero | Loại Hero khỏi đội hình | ACT-01 | Must | FUN-05-02-001 |
| FUN-05-02-003 | Replace Hero – Thay Hero | Thay Hero trong đội hình | ACT-01 | Should | FUN-05-02-001 |
| FUN-05-02-004 | Validate Hero Availability – Kiểm tra khả dụng | Kiểm tra Hero có đang bị thương, tử trận hoặc được điều động không | ACT-03 | Must | FUN-04-01-006 |
#### MOD-05-03 - Formation Management

| Function ID | Function | Business description | Actor | Priority | Dependency |
|---|---|---|---|---|---|
| FUN-05-03-001 | Set Hero Position – Đặt vị trí | Thiết lập vị trí Hero | ACT-01 | Must | FUN-05-02-001 |
| FUN-05-03-002 | Change Hero Position – Đổi vị trí | Thay đổi vị trí trong đội | ACT-01 | Should | FUN-05-03-001 |
| FUN-05-03-003 | Save Formation Preset – Lưu đội hình | Lưu đội hình mẫu | ACT-01 | Should | FUN-05-03-001 |
| FUN-05-03-004 | Validate Formation – Kiểm tra đội hình | Kiểm tra điều kiện hợp lệ | ACT-03 | Must | FUN-05-03-001 |
### DM-06

#### MOD-06-01 - Battle Initialization

| Function ID | Function | Business description | Actor | Priority | Dependency |
|---|---|---|---|---|---|
| FUN-06-01-001 | Create Battle – Khởi tạo trận đấu | Tạo Battle Instance | ACT-03 | Must | FUN-07-05-001 |
| FUN-06-01-002 | Assign Combatants – Phân bổ chiến binh | Xác định Hero và Enemy | ACT-03 | Must | FUN-06-01-001 |
| FUN-06-01-003 | Initialize Battle State – Khởi tạo trạng thái | Khởi tạo HP, trạng thái và chỉ số | ACT-03 | Must | FUN-06-01-002 |
| FUN-06-01-004 | Initialize Battle Strategy – Khởi tạo chiến thuật | Áp dụng thiết lập chiến thuật của Master | ACT-03 | Should | FUN-06-01-003 |
#### MOD-06-02 - Auto Battle & Hero AI

| Function ID | Function | Business description | Actor | Priority | Dependency |
|---|---|---|---|---|---|
| FUN-06-02-001 | Execute Auto Battle – Thực hiện chiến đấu tự động | Chạy toàn bộ quy trình chiến đấu | ACT-03 | Must | FUN-06-01-003 |
| FUN-06-02-002 | AI Target Selection – Chọn mục tiêu | Hero AI lựa chọn mục tiêu | ACT-03 | Must | FUN-06-02-001 |
| FUN-06-02-003 | AI Action Selection – Chọn hành động | AI quyết định hành động | ACT-03 | Must | FUN-06-02-001 |
| FUN-06-02-004 | AI Skill Execution – Sử dụng kỹ năng | AI lựa chọn và sử dụng kỹ năng | ACT-03 | Must | FUN-06-02-003 |
| FUN-06-02-005 | AI Personality Influence – Ảnh hưởng tính cách | Personality tác động đến hành vi chiến đấu | ACT-03 | Should | FUN-03-04-003 |
| FUN-06-02-006 | AI Relationship Influence – Ảnh hưởng quan hệ | Relationship tác động phối hợp chiến đấu | ACT-03 | Could | FUN-03-05-002 |
#### MOD-06-03 - Battle Mechanics

| Function ID | Function | Business description | Actor | Priority | Dependency |
|---|---|---|---|---|---|
| FUN-06-03-001 | Damage Calculation – Tính sát thương | Tính sát thương theo công thức | ACT-03 | Must | FUN-06-02-001 |
| FUN-06-03-002 | Buff & Debuff – Hiệu ứng | Áp dụng hiệu ứng chiến đấu | ACT-03 | Must | FUN-06-03-001 |
| FUN-06-03-003 | Status Effect – Trạng thái | Xử lý các hiệu ứng trạng thái | ACT-03 | Should | FUN-06-03-001 |
| FUN-06-03-004 | Critical Hit – Chí mạng | Xử lý sát thương chí mạng | ACT-03 | Should | FUN-06-03-001 |
| FUN-06-03-005 | Combat Element – Thuộc tính | Áp dụng cơ chế khắc chế thuộc tính | ACT-03 | Could | FUN-06-03-001 |
#### MOD-06-04 - Master Command & Tactical Buff

| Function ID | Function | Business description | Actor | Priority | Dependency |
|---|---|---|---|---|---|
| FUN-06-04-001 | Configure Combat Strategy – Thiết lập chiến thuật | Chọn chiến thuật trước trận đấu | ACT-02 | Must | FUN-06-01-004 |
| FUN-06-04-002 | Offensive Command – Chỉ thị tấn công | Ưu tiên tấn công | ACT-02 | Should | FUN-06-04-001 |
| FUN-06-04-003 | Defensive Command – Chỉ thị phòng thủ | Ưu tiên phòng thủ | ACT-02 | Should | FUN-06-04-001 |
| FUN-06-04-004 | Tactical Buff – Buff chiến thuật | Hỗ trợ Hero bằng buff gián tiếp | ACT-02, ACT-03 | Must | FUN-06-04-001 |
| FUN-06-04-005 | Target Priority – Ưu tiên mục tiêu | Chọn loại mục tiêu ưu tiên | ACT-02 | Should | FUN-06-04-001 |
| FUN-06-04-006 | Retreat Policy – Chính sách rút lui | Thiết lập điều kiện rút lui | ACT-02, ACT-03 | Could | FUN-06-04-001 |
#### MOD-06-05 - Battle Result & Report

| Function ID | Function | Business description | Actor | Priority | Dependency |
|---|---|---|---|---|---|
| FUN-06-05-001 | Determine Battle Result – Xác định kết quả | Xác định thắng hoặc thua | ACT-03 | Must | FUN-06-02-001 |
| FUN-06-05-002 | Process Hero Survival – Xử lý Hero sống sót | Cập nhật trạng thái Hero | ACT-03 | Must | FUN-06-05-001 |
| FUN-06-05-003 | Process Battle Casualties – Xử lý thương vong | Áp dụng quy tắc tử trận | ACT-03 | Must | FUN-06-05-001 |
| FUN-06-05-004 | Distribute Battle EXP – Phân phối EXP | Cộng EXP cho Hero đủ điều kiện | ACT-03 | Must | FUN-06-05-001 |
| FUN-06-05-005 | Generate Battle Reward – Phần thưởng trận đấu | Tạo phần thưởng | ACT-03 | Must | FUN-06-05-001 |
| FUN-06-05-006 | Generate Battle Report – Báo cáo chiến đấu | Lưu và hiển thị kết quả | ACT-03, ACT-01 | Must | FUN-06-05-001 |
| FUN-06-05-007 | Update Hero Condition – Cập nhật thể trạng | Cập nhật Hunger và Fatigue | ACT-03 | Should | FUN-06-05-001 |
### DM-07

#### MOD-07-01 - Dungeon Configuration

| Function ID | Function | Business description | Actor | Priority | Dependency |
|---|---|---|---|---|---|
| FUN-07-01-001 | Configure Dungeon Template – Cấu hình mẫu Dungeon | Tạo mẫu Dungeon | ACT-04, ACT-06 | Must | — |
| FUN-07-01-002 | Configure Floor – Cấu hình tầng | Thiết lập thông tin từng tầng | ACT-04, ACT-06 | Must | FUN-07-01-001 |
| FUN-07-01-003 | Configure Floor Requirement – Điều kiện tầng | Thiết lập điều kiện mở khóa | ACT-04 | Must | FUN-07-01-002 |
| FUN-07-01-004 | Configure Dungeon Reward – Cấu hình thưởng | Thiết lập phần thưởng Dungeon | ACT-04, ACT-06 | Must | FUN-07-01-002 |
#### MOD-07-02 - Seed Management

| Function ID | Function | Business description | Actor | Priority | Dependency |
|---|---|---|---|---|---|
| FUN-07-02-001 | Generate World Seed – Sinh Seed World | Sinh Seed duy nhất toàn game khi World khởi tạo; Seed cố định theo World và quyết định độ khó. | ACT-03 | Must | FUN-08-01-001 |
| FUN-07-02-002 | Save World Seed – Lưu Seed World | Lưu Seed đã tạo | ACT-03 | Must | FUN-07-02-001 |
| FUN-07-02-003 | Version Seed Algorithm – Phiên bản thuật toán | Quản lý phiên bản thuật toán sinh Dungeon | ACT-03, ACT-04 | Must | FUN-07-02-001 |
| FUN-07-02-004 | Reconstruct Dungeon – Tái tạo Dungeon | Tái tạo Dungeon từ Seed World cố định và phiên bản thuật toán tương ứng; không tạo lại Seed khi thất bại. | ACT-03 | Should | FUN-07-02-002, FUN-07-02-003 |
| FUN-07-02-005 | Manage Seed Lifecycle – Quản lý vòng đời Seed | Quản lý vòng đời Seed cố định theo World. | ACT-03 | Should | FUN-07-02-002 |
#### MOD-07-03 - Procedural Dungeon Generation

| Function ID | Function | Business description | Actor | Priority | Dependency |
|---|---|---|---|---|---|
| FUN-07-03-001 | Generate Dungeon Map – Sinh bản đồ | Tạo bản đồ từ Seed | ACT-03 | Must | FUN-07-02-001 |
| FUN-07-03-002 | Generate Room Layout – Sinh phòng | Tạo cấu trúc phòng và hành lang | ACT-03 | Must | FUN-07-03-001 |
| FUN-07-03-003 | Generate Monster Placement – Bố trí quái vật | Phân bổ quái vật theo Seed | ACT-03 | Must | FUN-07-03-001 |
| FUN-07-03-004 | Generate Dungeon Difficulty – Sinh độ khó | Xác định mức độ khó của Dungeon | ACT-03 | Must | FUN-07-03-001 |
| FUN-07-03-005 | Generate Environment Event – Sinh sự kiện môi trường | Tạo bẫy, sự kiện hoặc vật phẩm đặc biệt | ACT-03 | Should | FUN-07-03-001 |
#### MOD-07-04 - Floor Progression

| Function ID | Function | Business description | Actor | Priority | Dependency |
|---|---|---|---|---|---|
| FUN-07-04-001 | View Floor List – Danh sách tầng | Hiển thị các tầng | ACT-01 | Must | FUN-07-01-002 |
| FUN-07-04-002 | Unlock Floor – Mở khóa tầng | Mở khóa tầng theo điều kiện | ACT-03 | Must | FUN-07-01-003 |
| FUN-07-04-003 | Enter Floor – Vào tầng | Bắt đầu khám phá tầng | ACT-01, ACT-03 | Must | FUN-07-04-002 |
| FUN-07-04-004 | Track Floor Progress – Theo dõi tiến trình | Theo dõi tiến trình vượt tầng | ACT-03 | Must | FUN-07-04-003 |
| FUN-07-04-005 | Complete Floor – Hoàn thành tầng | Xác nhận tầng đã hoàn thành | ACT-03 | Must | FUN-07-04-004 |
| FUN-07-04-006 | Handle Floor Failure – Xử lý thất bại | Xử lý khi không vượt qua tầng | ACT-03 | Must | FUN-07-04-004 |
#### MOD-07-05 - Dungeon Exploration & Encounter

| Function ID | Function | Business description | Actor | Priority | Dependency |
|---|---|---|---|---|---|
| FUN-07-05-001 | Initialize Dungeon Instance – Khởi tạo Dungeon | Tạo phiên Dungeon để tham gia | ACT-03 | Must | FUN-07-03-001 |
| FUN-07-05-002 | Explore Dungeon – Khám phá Dungeon | Thực hiện tiến trình khám phá | ACT-01, ACT-03 | Must | FUN-07-05-001 |
| FUN-07-05-003 | Trigger Encounter – Kích hoạt chạm trán | Kích hoạt sự kiện hoặc trận chiến | ACT-03 | Must | FUN-07-05-002 |
| FUN-07-05-004 | Spawn Monster – Sinh quái vật | Tạo Monster Instance | ACT-03 | Must | FUN-07-05-003 |
| FUN-07-05-005 | Trigger Boss Encounter – Chạm trán Boss | Kích hoạt Boss Battle | ACT-03 | Must | FUN-07-05-003 |
| FUN-07-05-006 | Complete Dungeon – Hoàn thành Dungeon | Xác nhận kết quả toàn bộ Dungeon | ACT-03 | Must | FUN-07-05-005 |
#### MOD-07-06 - Dungeon Reward

| Function ID | Function | Business description | Actor | Priority | Dependency |
|---|---|---|---|---|---|
| FUN-07-06-001 | Calculate Floor Reward – Tính thưởng tầng | Tính phần thưởng vượt tầng | ACT-03 | Must | FUN-07-04-005 |
| FUN-07-06-002 | Calculate Boss Reward – Tính thưởng Boss | Tính thưởng đánh bại Boss | ACT-03 | Must | FUN-07-05-005 |
| FUN-07-06-003 | First Clear Reward – Thưởng lần đầu | Xử lý phần thưởng vượt lần đầu | ACT-03 | Should | FUN-07-06-001 |
| FUN-07-06-004 | Distribute Dungeon Reward – Phân phối thưởng | Cộng tài nguyên và vật phẩm | ACT-03 | Must | FUN-07-06-001 |
### DM-08

#### MOD-08-01 - Private World Management

| Function ID | Function | Business description | Actor | Priority | Dependency |
|---|---|---|---|---|---|
| FUN-08-01-001 | Initialize Private World – Khởi tạo thế giới riêng | Tạo World tối thiểu cho Master; cần thiết để tạo Seed World và vào Dungeon. Tiến trình World/Base nâng cao thuộc P1. | ACT-03 | Must | FUN-01-03-001 |
### DM-10

#### MOD-10-01 - Inventory Management

| Function ID | Function | Business description | Actor | Priority | Dependency |
|---|---|---|---|---|---|
| FUN-10-01-001 | View Inventory – Xem túi đồ | Hiển thị danh sách vật phẩm | ACT-01 | Must | FUN-01-03-001 |
| FUN-10-01-002 | Filter Inventory – Lọc vật phẩm | Lọc theo loại và thuộc tính | ACT-01 | Should | FUN-10-01-001 |
| FUN-10-01-003 | Sort Inventory – Sắp xếp vật phẩm | Sắp xếp vật phẩm | ACT-01 | Should | FUN-10-01-001 |
| FUN-10-01-004 | Add Item – Thêm vật phẩm | Cộng vật phẩm vào kho | ACT-03 | Must | FUN-10-01-001 |
| FUN-10-01-005 | Remove Item – Xóa vật phẩm | Trừ vật phẩm khỏi kho | ACT-03 | Must | FUN-10-01-001 |
| FUN-10-01-006 | Use Item – Sử dụng vật phẩm | Sử dụng vật phẩm hợp lệ | ACT-01, ACT-03 | Must | FUN-10-01-001 |
| FUN-10-01-007 | Sell Item – Bán vật phẩm | Chuyển vật phẩm thành tiền tệ | ACT-01, ACT-03 | Should | FUN-10-01-001 |
#### MOD-10-02 - Equipment Management (basic P0 scope)

| Function ID | Function | Business description | Actor | Priority | Dependency |
|---|---|---|---|---|---|
| FUN-10-02-001 | View Equipment – Xem trang bị | Hiển thị trang bị | ACT-01 | Should | FUN-10-01-001 |
| FUN-10-02-002 | Equip Item – Trang bị | Gắn trang bị cho Hero | ACT-01, ACT-03 | Should | FUN-10-02-001, FUN-10-02-004 |
| FUN-10-02-003 | Unequip Item – Tháo trang bị | Tháo trang bị khỏi Hero | ACT-01 | Should | FUN-10-02-002 |
| FUN-10-02-004 | Validate Equipment – Kiểm tra trang bị | Kiểm tra điều kiện trang bị | ACT-03 | Should | FUN-10-02-001 |
| FUN-10-02-005 | Calculate Equipment Stats – Tính chỉ số | Tính chỉ số cộng thêm | ACT-03 | Should | FUN-10-02-002 |
### DM-11

#### MOD-11-01 - Currency Management

| Function ID | Function | Business description | Actor | Priority | Dependency |
|---|---|---|---|---|---|
| FUN-11-01-001 | View Currency – Xem tiền tệ | Hiển thị số dư Xu Bạc và các vật phẩm triệu hồi; Ngọc nằm ngoài phạm vi P0. | ACT-01 | Must | FUN-01-03-001 |
| FUN-11-01-002 | Add Currency – Cộng tiền | Cộng Xu Bạc hoặc vé triệu hồi khi nhận thưởng/giao dịch hợp lệ. | ACT-03 | Must | FUN-11-01-001 |
| FUN-11-01-003 | Deduct Currency – Trừ tiền | Trừ Xu Bạc hoặc vé Thiên Thư khi triệu hồi/đổi vé. | ACT-03 | Must | FUN-11-01-001 |
| FUN-11-01-004 | Validate Balance – Kiểm tra số dư | Kiểm tra đủ Xu Bạc hoặc vé trước giao dịch. | ACT-03 | Must | FUN-11-01-001 |
| FUN-11-01-005 | Currency Transaction – Giao dịch tiền tệ | Ghi nhận lịch sử biến động Xu Bạc và vé triệu hồi. | ACT-03 | Must | FUN-11-01-002, FUN-11-01-003 |
| FUN-11-01-006 | Currency Limit – Giới hạn tiền tệ | Giới hạn đổi Xu Bạc sang Thiên Thư thường tối đa 50 vé mỗi tuần cố định, reset lúc 00:00 thứ Năm theo UTC+7. | ACT-03, ACT-04 | Should | FUN-11-01-001 |
| FUN-11-01-007 | Exchange Silver for Normal Summon Ticket – Đổi Xu Bạc lấy Thiên Thư thường | Cho phép đổi 10.000 Xu Bạc lấy một Thiên Thư thường, tối đa 50 vé mỗi tuần; reset lúc 00:00 thứ Năm theo UTC+7. | ACT-01, ACT-03 | Must | FUN-11-01-003, FUN-11-01-006 |
### DM-14

#### MOD-14-03 - Gacha & Dungeon Configuration

| Function ID | Function | Business description | Actor | Priority | Dependency |
|---|---|---|---|---|---|
| FUN-14-03-001 | Gacha Rule Configuration – Cấu hình Gacha | Quản lý quy tắc Gacha | ACT-04, ACT-06 | Must | DM-02 |
| FUN-14-03-002 | Pity Configuration – Cấu hình Pity | Quản lý quy tắc bảo đảm | ACT-04, ACT-06 | Must | FUN-14-03-001 |
| FUN-14-03-003 | Death Rule Configuration – Cấu hình tử trận | Quản lý quy tắc tử trận | ACT-04, ACT-06 | Must | DM-04 |
| FUN-14-03-004 | Dungeon Rule Configuration – Cấu hình Dungeon | Quản lý quy tắc Dungeon | ACT-04, ACT-06 | Must | DM-07 |
| FUN-14-03-005 | Seed Algorithm Configuration – Cấu hình Seed | Quản lý phiên bản thuật toán Seed | ACT-04, ACT-06 | Must | FUN-14-03-004 |
| FUN-14-03-006 | Battle Rule Configuration – Cấu hình chiến đấu | Quản lý quy tắc Auto Battle | ACT-04, ACT-06 | Must | DM-06 |
#### MOD-14-05 - Analytics & Monitoring

| Function ID | Function | Business description | Actor | Priority | Dependency |
|---|---|---|---|---|---|
| FUN-14-05-006 | System Monitoring – Giám sát hệ thống | Theo dõi tình trạng hoạt động | ACT-03, ACT-04 | Must | — |
#### MOD-14-06 - Customer Support & Security

| Function ID | Function | Business description | Actor | Priority | Dependency |
|---|---|---|---|---|---|
| FUN-14-06-003 | Audit Log – Nhật ký hệ thống | Lưu hành động quản trị và nghiệp vụ quan trọng | ACT-03, ACT-04 | Must | — |
| FUN-14-06-004 | Anti-cheat Monitoring – Giám sát gian lận | Phát hiện hành vi bất thường | ACT-03, ACT-04 | Must | — |
| FUN-14-06-005 | Abuse Detection – Phát hiện lạm dụng | Phát hiện lợi dụng lỗi game | ACT-03, ACT-04 | Should | FUN-14-06-004 |
| FUN-14-06-006 | Configuration Versioning – Quản lý phiên bản cấu hình | Theo dõi và khôi phục cấu hình | ACT-04, ACT-06 | Must | — |

## 7. Open items and TBDs

### P0 details to resolve before implementing affected behavior

- Exact full Gacha probability distribution by rarity and Hero pool, including any rate-up/featured allocation beyond the confirmed five-star Pity curve.
- Summon-item cost per single/multi summon and exact inventory/consumption behavior where not specified.
- Duplicate conversion quantity and the upgrade/unlock progression funded by provisional Thien Menh.
- Hero level, EXP, skill, promotion, and resource-cost formulas.
- Combat damage, skill timing, AI decision, retreat, and casualty-resolution details.
- Dungeon generation rules beyond the fixed per-World Seed, including Seed generation/collision handling, floor difficulty, and map/encounter parameters.
- Initial Silver Coin sources/reward amounts and any limits other than the confirmed normal-scroll weekly exchange cap.
- Acceptance criteria and failure/exception handling for each P0 Function.

### Decisions deferred to later phases

- **DEC-005 (Resurrection, P1):** Hero Limited được hồi sinh bao nhiêu lần?
- **DEC-006 (Recovery, P1):** Chi phí chữa trị tính theo yếu tố nào?
- **DEC-007 (Loyalty, P1):** Hero Loyalty thấp có thể chống lệnh hoặc rời Master không?
- **DEC-008 (Personality, P1):** Một Hero có thể có bao nhiêu Personality Trait?
- **DEC-009 (Relationship, P1):** Relationship ảnh hưởng AI và chiến đấu đến mức nào?
- **DEC-010 (Survival, P1):** Hunger và Fatigue cập nhật Real-time hay theo chu kỳ?
- **DEC-014 (World, P3):** Private World có bị người chơi khác xâm nhập không?
- **DEC-016 (Offline, P1):** World và Hero tiếp tục hoạt động khi Player offline như thế nào?
- **DEC-017 (War, P3):** Thời gian di chuyển và chiến đấu trên bản đồ thế giới?
- **DEC-018 (Economy, P1 | Giới hạn 50 Thiên Thư thường/tuần đã chốt; giới hạn tích trữ các loại khác còn TBD.):** Các loại tài nguyên có giới hạn tích trữ không?

## 8. Traceability and document control

- Function IDs are the traceability key between this BRD and MBFL.
- P0 scope is currently a draft matrix; this BRD remains Draft until owner review.
- Keep unresolved business rules as TBD. Update MBFL, the P0 matrix, and this BRD together when the owner confirms a rule.
- The dependency review artifact is `Dependency_Review.csv`; do not convert Domain-level dependencies to Function-level links without confirming the required behavior.
