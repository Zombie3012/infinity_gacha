> Updated contract (2026-11-22): [Hero Chronicle, mortality and 1-7 star rarity](../HERO_CHRONICLE.md) supersedes the legacy origin-based death/duplicate rules and Divine Grace sections below. All Heroes die as DEAD and drop equipped gear; one RESURRECTION_GEM_7 revives to full HP with no Silver fee or escalating cycle. NORMAL/SPECIAL/LIMITED remain payment/banner types only.

# Acceptance Criteria Specification — Phase P1

> **L?u tr? thi?t k? l?ch s?.** Checklist v? k?t qu? ki?m tra ph?n ?nh th?i ?i?m vi?t; c?c m? t? Web/Unity, pity v? duplicate c? th? ?? ???c thay th?. Xem [README hi?n h?nh](../../README.md) v? [backlog Godot](../../GODOT_BACKLOG.md), c?p nh?t 22/11/2026 (UTC+7).

| Field | Value |
|---|---|
| Document ID | IG-BA-AC-P1-001 |
| Version | 0.1 Draft |
| Project | Infinite Gacha (Hero Management & Survival Strategy RPG) |
| Source Baseline | BRD_P1_Draft.md, Use_Case_Spec_P1_Draft.md, Data_Model_P1_Draft.md |
| Target Scope | 17 Use Cases (93 P1 Functions) |

---

## 1. Quy ước kiểm thử Giai đoạn P1

Tài liệu này xác định các tiêu chí nghiệm thu chi tiết, rõ ràng và có thể kiểm thử tự động cho **toàn bộ 17 Use Cases (93 Chức năng P1)** theo định dạng BDD chuẩn (**Given - When - Then**).

---

## 2. Tiêu chí nghiệm thu chi tiết theo từng Use Case

### UC-P1-01: Link and Recover Account
**Functions:** `FUN-01-01-004`, `FUN-01-01-005`

#### Scenario 1.1: Liên kết tài khoản bên thứ 3 thành công
- **Given** một tài khoản người chơi hợp lệ chưa từng liên kết Google Play Games.
- **When** người chơi xác thực thành công qua OAuth Google và gửi `provider_user_id`.
- **Then** hệ thống ghi nhận một bản ghi mới trong `account_external_identities`.
- **And** tài khoản được gắn cờ bảo vệ an toàn danh tính.

#### Scenario 1.2: Chặn liên kết trùng lặp ID bên thứ ba
- **Given** ID Google `"google_uid_999"` đã được liên kết với Tài khoản A.
- **When** Tài khoản B cố gắng liên kết với `"google_uid_999"`.
- **Then** hệ thống từ chối với lỗi `ERR_AUTH_EXTERNAL_ID_ALREADY_LINKED`.

---

### UC-P1-02: Manage Hero Personality and Loyalty
**Functions:** `FUN-03-04-001` through `FUN-03-04-006`

#### Scenario 2.1: Khởi tạo đầy đủ 4 nhóm Traits khi tạo Hero
- **Given** một Hero Instance mới được triệu hồi.
- **When** hệ thống kích hoạt `FUN-03-04-001`.
- **Then** bản ghi `hero_personality_traits` được tạo lập với đủ 4 trường: `core_trait`, `social_trait`, `behavioral_trait`, `special_trait`.
- **And** `loyalty_score` được khởi tạo mặc định bằng `50` (Trạng thái `NORMAL`).

#### Scenario 2.2: Quy tắc Bất Biến — Không bao giờ bỏ rơi Master
- **Given** Hero chịu nhiều thất bại, đói khát và điểm trung thành rơi xuống mức tối thiểu (`loyalty_score = 0`).
- **When** hệ thống đánh giá `FUN-03-04-006`.
- **Then** Hero chuyển sang trạng thái `loyalty_state = 'DANGER'`.
- **And** Hero tuyệt đối **KHÔNG** bị xóa khỏi danh sách sở hữu của Master (`hero_instances` vẫn tồn tại).
- **And** Hero bị suy giảm chỉ số chiến đấu từ 20% đến 50%.
- **And** khi phân công xuất trận, hệ thống tung xúc xắc với xác suất 30% Hero từ chối ra trận (`ERR_HERO_DISOBEDIENCE`).

#### Scenario 2.3: Tăng điểm Loyalty khi được ăn món khoái khẩu
- **Given** Hero có `favorite_food = 'ROAST_CHICKEN'` và `loyalty_score = 50`.
- **When** người chơi cho Hero ăn 1 phần `'ROAST_CHICKEN'`.
- **Then** điểm `loyalty_score` tăng lên `55` điểm.

---

### UC-P1-03: Manage Hero Relationships and Bonding Events
**Functions:** `FUN-03-05-001` through `FUN-03-05-004`

#### Scenario 3.1: Tăng điểm hảo cảm khi cùng đội hình
- **Given** Hero A và Hero B cùng tham gia và chiến thắng 5 trận đấu Dungeon.
- **When** hệ thống tính toán kết quả trận đấu.
- **Then** điểm `affinity_points` giữa A và B tăng từ `0` lên `10`.
- **And** khi đạt mốc `50`, cấp quan hệ nâng lên `COMRADE`, kích hoạt buff thụ động `+5% ATK` khi A và B đứng cạnh nhau trong formation.

---

### UC-P1-04: Process Hero Injury and Temporary Stat Reduction
**Functions:** `FUN-04-02-001` through `FUN-04-02-005`

#### Scenario 4.1: Áp dụng suy giảm chỉ số tạm thời khi bị thương nặng
- **Given** Hero sống sót sau trận đánh với HP còn dưới 15%.
- **When** hệ thống phân loại chấn thương `FUN-04-02-001`.
- **Then** tạo bản ghi `hero_injuries` với `severity = 'SEVERE'`, giảm tạm thời 25% ATK/DEF.
- **And** thiết lập đồng hồ đếm ngược tự chữa lành 7200 giây (2 giờ).
- **And** khi hết 7200 giây, chỉ số được khôi phục nguyên trạng.

---

### UC-P1-05: Construct and Operate Medical Facility
**Functions:** `FUN-04-03-001` .. `004`, `FUN-04-04-001` .. `004`, `FUN-04-04-008`

#### Scenario 5.1: Xây dựng Viện Y Tế và giới hạn công suất giường bệnh
- **Given** Master sở hữu đủ gỗ và đá tại căn cứ.
- **When** người chơi xây dựng Medical Facility Cấp 1.
- **Then** công trình hoàn tất với `bed_capacity = 2` giường bệnh.

#### Scenario 5.2: Tiếp nhận điều trị và chữa trị khẩn cấp
- **Given** Hero đang bị thương nặng và buồng bệnh còn chỗ trống.
- **When** người chơi đưa Hero vào viện và dùng dược liệu `Emergency Treatment`.
- **Then** vết thương lập tức được chữa lành trong 0 giây, Hero rời viện ở trạng thái hoàn toàn khỏe mạnh.

---

### UC-P1-06: Resurrect a deceased Hero at Hero Chronicle
**Functions:** `FUN-04-04-005` through `FUN-04-04-008`

#### Scenario 6.1: All summon sources share one resurrection rule
- **Given** any owned Hero instance is DEAD with zero HP and the Master owns one RESURRECTION_GEM_7.
- **When** the player uses resurrection from Hero Chronicle.
- **Then** exactly one gem is consumed; Hero becomes HEALTHY at 100% HP, without a Silver fee or recreated equipment.
- **And** the existing biography is preserved and RESURRECTED is appended to the timeline.

#### Scenario 6.2: Cost is constant on later deaths
- **Given** a Hero has died and revived before.
- **Then** resurrection still costs one gem, with no 30-day pricing cycle.

#### Scenario 6.3: Retry, ownership and consumed instances
- **Then** concurrent requests can consume at most one gem per death; retries after success return 409.
- **And** another Master's record is inaccessible; living or consumed instances cannot resurrect.

---

### UC-P1-07: Expand Private World and Manage Base Buildings
**Functions:** `FUN-08-01-002` .. `005`, `FUN-08-02-001` .. `005`

#### Scenario 7.1: Khai hoang mở rộng ô đất xây dựng
- **Given** Master đạt World Level 2 và có đủ 5,000 Xu Bạc.
- **When** người chơi mở rộng vùng đất số 3.
- **Then** các ô đất xây dựng mới được mở khóa từ trạng thái sương mù sang sẵn sàng xây dựng.

#### Scenario 7.2: Nâng cấp công trình căn cứ
- **Given** Nông trại Cấp 1 đang hoạt động.
- **When** người chơi nộp đủ gỗ và đá để nâng cấp lên Cấp 2.
- **Then** công trình tăng cấp ngay, giữ trạng thái `READY` và áp dụng sản lượng cấp mới trong cùng giao dịch; không có đồng hồ đếm ngược. Xem [quy tắc hiện hành](../BASE_CONSTRUCTION.md).

---

### UC-P1-08: Produce Base Resources and Assign Hero Workers
**Functions:** `FUN-08-03-001` .. `005`, `FUN-08-04-001` .. `004`

#### Scenario 8.1: Sản xuất liên tục khi người chơi offline
- **Given** Mỏ Đá có sản lượng 100 đá/giờ, dung lượng kho tối đa là 1,000 đá.
- **When** người chơi offline liên tục trong 12 giờ.
- **Then** mỏ đá sản xuất đạt tối đa 1,000 đá sau 10 giờ đầu tiên.
- **And** trong 2 giờ tiếp theo mỏ đá tạm ngừng sản xuất để chờ người chơi thu thập, không bị mất tài nguyên.

#### Scenario 8.2: Phân công Hero làm việc và tăng hiệu suất
- **Given** Hero có Trait `Aggressive` (tăng 20% năng suất khai khoáng).
- **When** người chơi phân công Hero vào Mỏ Đá.
- **Then** sản lượng mỏ đá tăng từ 100 đá/h lên 120 đá/h.
- **And** Hero tăng đều đặn +5 điểm Đói và +8 điểm Mệt mỏi sau mỗi ca làm việc.

---

### UC-P1-09: Manage Hero Hunger, Food Distribution, and Starvation
**Functions:** `FUN-09-01-001` through `FUN-09-01-005`

#### Scenario 9.1: Tăng điểm đói theo thời gian và trận đánh
- **Given** Hero có điểm đói ban đầu `hunger_score = 10`.
- **When** Hero trải qua 5 giờ sinh hoạt và tham gia 2 trận đánh Dungeon.
- **Then** điểm đói tăng: $10 + (5 \times 1) + (2 \times 8) = 31$ điểm (`Satisfied`).

#### Scenario 9.2: Hình phạt suy nhược khi đói kiệt (Starvation)
- **Given** Hero bị bỏ đói đạt `hunger_score = 85` (`Starving`).
- **When** Hero bước vào trận chiến.
- **Then** hệ thống áp dụng debuff suy nhược: -40% ATK, -40% DEF, tốc độ hồi năng lượng giảm một nửa.

---

### UC-P1-10: Manage Hero Fatigue, Resting Quarters, and Overexertion
**Functions:** `FUN-09-02-001` through `FUN-09-02-006`

#### Scenario 10.1: Chặn xuất trận khi đạt 100 điểm mệt mỏi
- **Given** Hero hoạt động liên tục đạt `fatigue_score = 100` (`Overexhausted`).
- **When** người chơi cố gắng xếp Hero này vào đội hình chiến đấu.
- **Then** hệ thống từ chối với thông báo `ERR_HERO_OVEREXHAUSTED_MUST_REST`.

#### Scenario 10.2: Hồi phục thể lực khi ngủ trong phòng Ký Túc Xá
- **Given** Hero có `fatigue_score = 80`.
- **When** người chơi chỉ định Hero vào giường ngủ trong Dormitory (-15 điểm/giờ).
- **Then** sau 4 giờ nghỉ ngơi, điểm mệt mỏi giảm về $80 - 60 = 20$ điểm (`Normal`).

---

### UC-P1-11: Manage Food Supply and Resource Consumption
**Functions:** `FUN-09-03-001` through `FUN-09-03-005`

#### Scenario 11.1: Khấu trừ quân lương khi đi thám hiểm Dungeon
- **Given** một đội hình 4 Hero chuẩn bị thám hiểm Dungeon Tầng 3 (yêu cầu 40 khẩu phần lương khô).
- **When** người chơi bấm xuất quân.
- **Then** hệ thống kiểm tra và trừ 40 đơn vị lương khô từ kho lương thực căn cứ trước khi khởi hành.

---

### UC-P1-12: Craft, Upgrade, and Fuse Equipment
**Functions:** `FUN-10-03-001` through `FUN-10-03-004`

#### Scenario 12.1: Chế tạo vũ khí từ nguyên liệu Dungeon
- **Given** Master có 10 Quặng Sắt, 2 Da Thú và 1,000 Xu Bạc.
- **When** người chơi chọn chế tạo `Kiếm Sắt Thô`.
- **Then** hệ thống khấu trừ nguyên liệu và tạo ra một `equipment_instances` mới trong túi đồ.

#### Scenario 12.2: Dung hợp 3 trang bị cùng loại để tăng sao
- **Given** người chơi có 3 thanh `Kiếm Sắt 1 Sao` cùng loại.
- **When** người chơi thực hiện Item Fusion.
- **Then** 3 thanh kiếm cũ được tiêu biến và hệ thống tạo ra 1 thanh `Kiếm Sắt 2 Sao` với thuộc tính cơ bản cao hơn 30%.

---

### UC-P1-13: Manage and Purchase Items from the Base Shop
**Functions:** `FUN-11-02-001` through `FUN-11-02-006`

#### Scenario 13.1: Mua vật phẩm và giới hạn số lượng trong ngày
- **Given** mặt hàng `Bình Thể Lực Nhỏ` có giới hạn mua tối đa 5 bình/ngày và giá 500 Xu Bạc/bình.
- **When** người chơi đã mua 4 bình và yêu cầu mua thêm 2 bình.
- **Then** hệ thống chỉ cho phép mua tối đa 1 bình còn lại và báo lỗi `ERR_SHOP_DAILY_LIMIT_EXCEEDED` đối với bình thứ 2.

---

### UC-P1-14: Receive System Mail and Claim Rewards
**Functions:** `FUN-11-04-001` through `FUN-11-04-006`

#### Scenario 14.1: Nhận quà đính kèm từ thư hệ thống
- **Given** người chơi nhận được thư đền bù bảo trì kèm 5,000 Xu Bạc và 2 Thiên Thư trắng.
- **When** người chơi bấm "Nhận quà".
- **Then** số dư Xu Bạc và vé tăng ngay lập tức trong ví tiền tệ.
- **And** thư được đánh dấu `is_claimed = TRUE`.

#### Scenario 14.2: Tự động xóa thư quá hạn 30 ngày
- **Given** một bức thư thông báo có `expires_at = 2026-10-01`.
- **When** hệ thống kiểm tra định kỳ vào tháng 11/2026.
- **Then** thư quá hạn được dọn dẹp tự động khỏi hòm thư.

---

### UC-P1-15: Progress Main and Side Quests
**Functions:** `FUN-12-01-001` through `FUN-12-01-005`

#### Scenario 15.1: Hoàn thành mục tiêu nhiệm vụ chính tuyến
- **Given** nhiệm vụ chính tuyến yêu cầu: "Nâng cấp Viện Y Tế lên Cấp 2".
- **When** công trình Viện Y Tế hoàn tất nâng cấp lên Cấp 2.
- **Then** trạng thái nhiệm vụ chuyển sang `COMPLETED`.
- **And** người chơi bấm nhận thưởng để nhận 500 Master EXP và 10,000 Xu Bạc.

---

### UC-P1-16: Complete Daily and Weekly Quests
**Functions:** `FUN-12-02-001` through `FUN-12-02-005`

#### Scenario 16.1: Tự động reset nhiệm vụ ngày lúc 00:00 UTC+7
- **Given** danh sách Daily Quest của ngày hôm trước.
- **When** đồng hồ hệ thống điểm 00:00:00 UTC+7 của ngày mới.
- **Then** toàn bộ tiến độ nhiệm vụ ngày cũ được làm mới (reset) và tạo ngẫu nhiên bộ 5 nhiệm vụ ngày mới.

#### Scenario 16.2: Reset nhiệm vụ tuần vào thứ Năm 00:00 UTC+7
- **Given** chuỗi nhiệm vụ tuần đang diễn ra.
- **When** bước sang thứ Năm lúc 00:00:00 UTC+7.
- **Then** chuỗi nhiệm vụ tuần được reset đồng bộ cùng thời điểm reset giới hạn đổi Thiên Thư Gacha.

---

### UC-P1-17: Track and Claim Lifetime Achievements
**Functions:** `FUN-12-03-001` through `FUN-12-03-004`

#### Scenario 17.1: Mở khóa thành tựu thu thập Hero
- **Given** thành tựu "Bộ Sưu Tập Huyền Thoại: Sở hữu 20 Hero khác nhau".
- **When** người chơi triệu hồi thành công Hero thứ 20.
- **Then** hệ thống lập tức mở khóa thành tựu và gửi thông báo hiển thị danh hiệu Master.
- **And** người chơi nhận thưởng 100 Ngọc (Gems).
