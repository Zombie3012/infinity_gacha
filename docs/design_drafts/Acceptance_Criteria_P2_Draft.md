# Acceptance Criteria Specification — Phase P2

> **L?u tr? thi?t k? l?ch s?.** Checklist v? k?t qu? ki?m tra ph?n ?nh th?i ?i?m vi?t; c?c m? t? Web/Unity, pity v? duplicate c? th? ?? ???c thay th?. Xem [README hi?n h?nh](../../README.md) v? [backlog Godot](../../GODOT_BACKLOG.md), c?p nh?t 22/11/2026 (UTC+7).

| Field | Value |
|---|---|
| Document ID | IG-BA-AC-P2-001 |
| Version | 0.1 Draft |
| Project | Infinite Gacha (Hero Management & Survival Strategy RPG) |
| Source Baseline | BRD_P2_Draft.md, Use_Case_Spec_P2_Draft.md, Data_Model_P2_Draft.md |
| Target Scope | 8 Use Cases (40 P2 Functions) |

---

## 1. Quy ước kiểm thử Giai đoạn P2

Tài liệu này xác định các tiêu chí nghiệm thu kiểm thử tự động cho **toàn bộ 8 Use Cases (40 Chức năng P2)** theo định dạng BDD chuẩn (**Given - When - Then**).

---

## 2. Tiêu chí nghiệm thu chi tiết theo từng Use Case

### UC-P2-01: Purchase IAP Packages and Validate Payment Receipts
**Functions:** `FUN-11-03-001` through `FUN-11-03-006`

#### Scenario 1.1: Mua gói nạp IAP và xác thực biên lai thành công
- **Given** người chơi sở hữu tài khoản hợp lệ, chọn gói `PKG_GEMS_TIER_1` (1,000 Gems giá $9.99).
- **When** người chơi hoàn tất thanh toán trên Apple App Store và client gửi biên lai về Game Server.
- **Then** Game Server gọi API Apple xác thực thành công.
- **And** tạo bản ghi `payment_transactions` với `status = 'COMPLETED'`.
- **And** cộng chính xác 1,000 Gems vào ví `master_currencies.gems`.

#### Scenario 1.2: Chặn biên lai giả hoặc tái sử dụng biên lai (Replay Attack)
- **Given** một biên lai với `store_transaction_id = 'TX_APPLE_88888'` đã từng được xác thực thành công trước đó.
- **When** client gửi lại biên lai này để yêu cầu nhận thêm Gems.
- **Then** hệ thống phát hiện trùng lặp khóa duy nhất `UNIQUE(store_type, store_transaction_id)`.
- **And** từ chối giao dịch với mã lỗi `ERR_IAP_DUPLICATE_RECEIPT`.
- **And** không có số Gems nào được cộng thêm.

---

### UC-P2-02: Process Refunds and Manage Gem Debt
**Functions:** `FUN-11-03-007`

#### Scenario 2.1: Hoàn tiền khi số dư Gems còn đủ trong ví
- **Given** Master đang có số dư 1,500 Gems trong ví và `gem_debt = 0`.
- **When** nhận được thông báo hoàn tiền gói 1,000 Gems từ Google Play Console.
- **Then** hệ thống tự động khấu trừ 1,000 Gems khỏi ví, số dư còn lại 500 Gems.
- **And** `gem_debt` vẫn bằng `0`.

#### Scenario 2.2: Hoàn tiền khi đã tiêu xài — Ghi nhận Nợ Ngọc (Gem Debt)
- **Given** Master đã tiêu hết Gems, số dư ví hiện tại chỉ còn `200` Gems, `gem_debt = 0`.
- **When** nhận được thông báo hoàn tiền gói `1,000` Gems.
- **Then** hệ thống thu hồi toàn bộ 200 Gems còn lại (số dư ví về 0).
- **And** phần thiếu hụt 800 Gems được ghi nhận vào nợ: `masters.gem_debt = 800`.
- **And** tài khoản **KHÔNG BỊ KHÓA**; người chơi vẫn đăng nhập và chơi bình thường.

#### Scenario 2.3: Tự động cấn trừ Nợ Ngọc khi nạp tiền mới hoặc nhận quà
- **Given** Master đang có `gem_debt = 800` và số dư ví `0` Gems.
- **When** người chơi nạp gói mới nhận được `1,000` Gems.
- **Then** hệ thống tự động trừ 800 Gems vào nợ (`gem_debt = 0`).
- **And** số dư ví thực nhận tăng lên `200` Gems.

---

### UC-P2-03: Manage and Participate in LiveOps Events
**Functions:** `FUN-12-04-001` through `FUN-12-04-007`

#### Scenario 3.1: Kiểm tra quy tắc chu kỳ Standard Event (14 ngày)
- **Given** một sự kiện Standard Event được lên lịch.
- **When** người vận hành cấu hình `start_time = 2026-11-10 00:00:00 UTC+7`.
- **Then** hệ thống tự động gán `end_time = 2026-11-24 00:00:00 UTC+7` (đúng 14 ngày).
- **And** gán thời hạn nhận thưởng `claim_deadline = 2026-11-26 00:00:00 UTC+7` (thêm 48 giờ ân hạn).

#### Scenario 3.2: Chặn chồng chéo 2 Standard Event chính
- **Given** Event A (Standard Event) đang diễn ra từ ngày 1 đến ngày 14.
- **When** nhân viên vận hành cố gắng kích hoạt Event B (Standard Event khác) vào ngày 10.
- **Then** hệ thống từ chối kích hoạt với lỗi `ERR_LIVEOPS_STANDARD_EVENT_OVERLAP`.

#### Scenario 3.3: Kiểm tra 7 ngày hồi sau Major Event
- **Given** Major Event vừa kết thúc vào ngày 15.
- **When** người vận hành cấu hình một Major Event mới bắt đầu vào ngày 18.
- **Then** hệ thống cảnh báo và từ chối vì chưa đủ khoảng nghỉ 7 ngày (`ERR_MAJOR_EVENT_COOLDOWN_VIOLATION`).

#### Scenario 3.4: Thời gian ân hạn nhận thưởng 48 giờ
- **Given** sự kiện đã bước qua mốc `end_time` (đang trong khoảng 48h trước `claim_deadline`).
- **When** người chơi hoàn thành một trận đánh dungeon.
- **Then** hệ thống KHÔNG cộng thêm điểm tiến độ sự kiện.
- **And** người chơi vẫn bấm nhận được các mốc quà đã hoàn thành trước đó.

---

### UC-P2-04: Compete in Dual PVE Leaderboards and Claim Season Rewards
**Functions:** `FUN-12-05-001` through `FUN-12-05-003`

#### Scenario 4.1: Xếp hạng Tiến độ Dungeon theo Tầng và Thời gian
- **Given** Người chơi A vượt Tầng 50 trong 120 giây; Người chơi B vượt Tầng 50 trong 95 giây.
- **When** hệ thống tính toán bảng xếp hạng `DUNGEON_PROGRESS`.
- **Then** Người chơi B xếp trên Người chơi A (cùng tầng nhưng thời gian ngắn hơn).

#### Scenario 4.2: Xếp hạng Tổng Lực Chiến
- **Given** Người chơi C có tổng lực chiến 5 Hero mạnh nhất là 150,000 CP.
- **When** hệ thống cập nhật bảng xếp hạng `COMBAT_POWER`.
- **Then** điểm số của Người chơi C ghi nhận đúng 150,000.

#### Scenario 4.3: Kết toán mùa giải và gửi thưởng qua Hòm thư
- **Given** mùa giải bảng xếp hạng kết thúc vào lúc 00:00 UTC+7.
- **When** hệ thống chốt top `FUN-12-05-003`.
- **Then** tự động tạo thư hệ thống gửi vào Mailbox của người chơi Top 1–10 kèm Danh hiệu đặc biệt và 10 Vé Thiên Thư.

---

### UC-P2-05: Administer Player Accounts and Issue Compensations
**Functions:** `FUN-14-01-001` through `FUN-14-01-005`

#### Scenario 5.1: Tìm kiếm hồ sơ và khóa tài khoản vi phạm
- **Given** một tài khoản bị phát hiện can thiệp tốc độ trận đấu.
- **When** Admin chọn lệnh `Ban Account` với thời hạn 7 ngày và lý do "Speed hack".
- **Then** trạng thái tài khoản chuyển sang `BANNED`.
- **And** phiên đăng nhập hiện tại của người chơi lập tức bị ngắt kết nối.

#### Scenario 5.2: Gửi quà đền bù trực tiếp vào hòm thư người chơi
- **Given** một lỗi hệ thống làm mất vật phẩm của người chơi ID `M-101`.
- **When** Admin dùng công cụ bồi thường gửi 5,000 Xu Bạc và 1 Vũ khí.
- **Then** một bức thư đền bù mới được tạo lập trong hòm thư của `M-101`.

---

### UC-P2-06: Submit and Handle Customer Support Tickets
**Functions:** `FUN-14-06-001`, `FUN-14-06-002`

#### Scenario 6.1: Gửi ticket khiếu nại in-game
- **Given** người chơi gặp lỗi nạp thẻ nhưng chưa thấy tiền vào ví.
- **When** người chơi gửi ticket loại `PAYMENT_ISSUE` kèm mã giao dịch.
- **Then** hệ thống tạo bản ghi `support_tickets` với trạng thái `OPEN`.

#### Scenario 6.2: Nhân viên CS phản hồi và đóng ticket
- **Given** ticket đang ở trạng thái `OPEN`.
- **When** nhân viên CS kiểm tra log giao dịch và gửi phản hồi "Đã cộng bù 1,000 Gems".
- **Then** người chơi nhận được tin nhắn trong giao diện hỗ trợ, trạng thái ticket chuyển sang `RESOLVED`.

---

### UC-P2-07: Configure Live Game Content and Hotfix Parameters
**Functions:** `FUN-14-02-001` .. `006`, `FUN-14-04-001` .. `005`

#### Scenario 7.1: Hotfix cân bằng Boss và tỷ lệ rớt đồ OTA
- **Given** Boss Tầng 10 có chỉ số máu quá cao khiến người chơi không vượt qua được.
- **When** Game Designer cập nhật lại HP Boss trong CMS và bấm `Publish Hotfix`.
- **Then** hệ thống tạo phiên bản cấu hình mới trong `system_configs`.
- **And** client người chơi tải delta cấu hình mới ngay lần vào game tiếp theo mà không cần tải lại file cài đặt từ App Store.

---

### UC-P2-08: Monitor Game Analytics, Economy Health, and Player Retention
**Functions:** `FUN-14-05-001` through `FUN-14-05-005`

#### Scenario 8.1: Tổng hợp chỉ số kinh tế hàng ngày
- **Given** trong ngày có 10,000 lượt triệu hồi Gacha, tiêu thụ 1,000,000 Gems và sản sinh 50,000,000 Xu Bạc.
- **When** tiến trình tổng kết ngày chạy lúc 00:05 UTC+7.
- **Then** hệ thống ghi nhận chính xác các chỉ số `GEMS_SINK`, `SILVER_MINT`, `GACHA_ROLLS_TOTAL` vào `analytics_daily_aggregates`.

#### Scenario 8.2: Tính toán tỷ lệ giữ chân người chơi Retention D1/D7
- **Given** nhóm người chơi cài đặt game vào ngày 2026-11-01 (1,000 người).
- **When** tiến trình thống kê kiểm tra số người quay lại vào ngày 2026-11-02 (D1) và 2026-11-08 (D7).
- **Then** ghi nhận tỷ lệ chính xác vào `analytics_retention_cohorts`.
