> Updated contract (2026-11-22): [Hero Chronicle, mortality and 1-7 star rarity](../HERO_CHRONICLE.md) supersedes the legacy origin-based death/duplicate rules and Divine Grace sections below. All Heroes die as DEAD and drop equipped gear; one RESURRECTION_GEM_7 revives to full HP with no Silver fee or escalating cycle. NORMAL/SPECIAL/LIMITED remain payment/banner types only.

# Business Requirements Document (BRD) – Phase P3

> **L?u tr? thi?t k? l?ch s?.** Checklist v? k?t qu? ki?m tra ph?n ?nh th?i ?i?m vi?t; c?c m? t? Web/Unity, pity v? duplicate c? th? ?? ???c thay th?. Xem [README hi?n h?nh](../../README.md) v? [backlog Godot](../../GODOT_BACKLOG.md), c?p nh?t 22/11/2026 (UTC+7).

| Field | Value |
|---|---|
| Document ID | IG-BA-BRD-P3-001 |
| Version | 0.1 Draft |
| Project | Infinite Gacha (Hero Management & Survival Strategy RPG) |
| Source of Truth | MBFL.docx, Phase_Scope_Matrix_P3.csv, Project Concept |
| Domain Scope | DM-13: Multiplayer & World Conquest (37 Functions across 7 Modules) |
| Status | Draft for Review |

---

## 1. Mục đích tài liệu (Purpose)

Tài liệu Đặc tả Yêu cầu Nghiệp vụ (BRD) Giai đoạn **P3: Multiplayer & World Conquest** xác định chi tiết phạm vi 37 chức năng nghiệp vụ mở rộng trò chơi ra không gian nhiều người chơi (MMO Strategy). Trọng tâm của giai đoạn P3 là bản đồ thế giới mở chung (Global World Map), kiểm soát lãnh thổ, điều động quân đoàn thời gian thực, chiến đấu PvP, hệ thống liên minh (Alliance) và chiến tranh công thành/chinh phục thế giới theo mùa giải (World Conquest).

---

## 2. Phạm vi giai đoạn P3 (Scope)

### 2.1. Nằm trong phạm vi P3 (In Scope)
Toàn bộ Domain 13 (DM-13: Multiplayer & World Conquest) gồm 37 chức năng phân bổ trong 7 Module:
- **MOD-13-01: Global World & Map Exploration (5 chức năng)**
  - Mở khóa quyền gia nhập thế giới chung (`FUN-13-01-001`).
  - Bản đồ thế giới lưới tọa độ X, Y toàn cục (`FUN-13-01-002`).
  - Phân vùng lãnh thổ (Region) và sương mù khám phá (Fog of War) (`FUN-13-01-003`, `FUN-13-01-004`).
  - Ghi nhận tiến trình khai phá toàn cầu (`FUN-13-01-005`).
- **MOD-13-02: Territory Control & Expansion (5 chức năng)**
  - Quản lý thông tin và trạng thái ô đất lãnh thổ (`FUN-13-02-001`).
  - Chiếm đóng lãnh thổ vô chủ hoặc sau giao tranh (`FUN-13-02-002`).
  - Nâng cấp tiền đồn, tháp tài nguyên (`FUN-13-02-003`).
  - Từ bỏ quyền kiểm soát ô đất (`FUN-13-02-004`).
  - Quản lý chủ sở hữu và sản lượng thuế (`FUN-13-02-005`).
- **MOD-13-03: Scouting & Intelligence (3 chức năng)**
  - Phái do thám căn cứ và quân đội đối phương (`FUN-13-03-001`).
  - Trinh sát ô lãnh thổ và lực lượng đồn trú (`FUN-13-03-002`).
  - Báo cáo tình báo theo cấp độ chính xác (`FUN-13-03-003`).
- **MOD-13-04: Army Management & Movement (5 chức năng)**
  - Tạo quân đoàn hành quân (`FUN-13-04-001`).
  - Bổ nhiệm Chủ tướng và Hero đi cùng (`FUN-13-04-002`).
  - Điều động xuất quân đến tọa độ chỉ định (`FUN-13-04-003`).
  - Lệnh thu hồi quân đoàn quay về (`FUN-13-04-004`).
  - Theo dõi lộ trình và thời gian hành quân ETA thời gian thực (`FUN-13-04-005`).
- **MOD-13-05: PvP Combat & Territory Defense (7 chức năng)**
  - Khởi tạo tấn công đối thủ (`FUN-13-05-001`).
  - Kiểm tra điều kiện PvP và rào chắn an toàn (`FUN-13-05-002`).
  - Thực thi tính toán giao tranh PvP (`FUN-13-05-003`).
  - Xử lý kết quả, cướp tài nguyên và thương vong (`FUN-13-05-004`).
  - Bố trí lực lượng phòng thủ lãnh thổ (`FUN-13-05-005`).
  - Cơ chế Khiên hòa bình (Peace Shield) và chống farm bắt nạt (`FUN-13-05-006`).
  - Chiến báo PvP chi tiết (`FUN-13-05-007`).
- **MOD-13-06: Alliance System (6 chức năng)**
  - Thành lập liên minh bang hội (`FUN-13-06-001`).
  - Tìm kiếm và lọc danh sách bang (`FUN-13-06-002`).
  - Gia nhập liên minh (`FUN-13-06-003`).
  - Rời bang và thời gian chờ (cooldown) (`FUN-13-06-004`).
  - Phân quyền lãnh đạo và quản lý thành viên (`FUN-13-06-005`).
  - Kênh chat bang và đánh dấu chiến thuật (`FUN-13-06-006`).
- **MOD-13-07: World War & Conquest (6 chức năng)**
  - Tuyên chiến chiến dịch liên minh (`FUN-13-07-001`).
  - Theo dõi tiến độ và điểm số chiến tranh (`FUN-13-07-002`).
  - Tranh đoạt kỳ quan/căn cứ trung tâm (`FUN-13-07-003`).
  - Xác định liên minh chiến thắng mùa giải (`FUN-13-07-004`).
  - Phát thưởng mùa giải và danh hiệu bá chủ (`FUN-13-07-005`).
  - Bảng vinh danh World Conquest Ranking (`FUN-13-07-006`).

### 2.2. Ngoài phạm vi P3 (Out of Scope)
- Tính năng voice chat thời gian thực trong bang hội (chỉ hỗ trợ văn bản và ping tọa độ).
- Giao dịch trực tiếp Hero hoặc trang bị giữa hai người chơi (Player-to-Player Direct Trade).
- Đấu giá tài nguyên mở liên cụm máy chủ (Cross-cluster Global Auction).

---

## 3. Quy tắc nghiệp vụ cốt lõi (Core Business Rules)

### 3.1. Điều kiện mở khóa Global World (`FUN-13-01-001`)
- **Ngưỡng cấp bậc Master**: Master phải đạt Cấp độ 15 trở lên.
- **Tiến trình PvE tối thiểu**: Master phải vượt qua Tầng 10 của Dungeon chính (P0).
- Sau khi mở khóa, căn cứ của Master sẽ được sinh ra (spawn) ngẫu nhiên tại một khu vực rìa (Outer Rim Region) trên Bản đồ Thế giới chung với tọa độ $(X, Y)$ cụ thể.

### 3.2. Quy tắc Bản đồ & Kiểm soát Lãnh thổ (`MOD-13-01`, `MOD-13-02`)
- **Lưới tọa độ**: Thế giới chung được phân chia theo dạng lưới vuông tọa độ $(X, Y)$ từ $(0, 0)$ đến $(1000, 1000)$.
- **Giới hạn ô chiếm đóng (Territory Cap)**:
  - Mỗi Master ban đầu sở hữu hạn mức chiếm tối đa **10 ô lãnh thổ**.
  - Có thể mở rộng hạn mức tối đa lên 30 ô thông qua nâng cấp Công trình Chỉ Huy (Master Base Command Center).
- **Phân loại ô đất**:
  - *Ô Vô Chủ (Wilderness/Ruins)*: Cần tiêu diệt quái vật bảo vệ trấn giữ để chiếm đóng.
  - *Ô Tài Nguyên (Resource Mine/Farm/Lumber)*: Sản sinh tài nguyên theo giờ, chuyển thẳng về kho căn cứ khi đến chu kỳ thu hoạch.
  - *Ô Đối Thủ*: Thuộc quyền kiểm soát của người chơi khác, bắt buộc đánh bại lực lượng đồn trú để tước đoạt quyền sở hữu.
- **Từ bỏ lãnh thổ**: Master có thể chủ động bỏ ô đất với thời gian đếm ngược 10 phút. Sau 10 phút, ô đất trở về trạng thái vô chủ.

### 3.3. Quy tắc Di chuyển & Quân đoàn (Army Marching) (`MOD-13-04`)
- **Cấu trúc Quân đoàn**: Mỗi quân đoàn gồm tối đa **1 Chủ tướng (Commander)** và **4 Hero phó tá (Sub-Heroes)**.
- **Giới hạn quân đoàn**: Master có thể duy trì tối đa 3 quân đoàn xuất chinh cùng lúc (nâng cấp thêm thông qua viện nghiên cứu).
- **Tốc độ hành quân (March Speed)**:
  - Tốc độ cơ bản: 1 ô tọa độ / 30 giây.
  - Thời gian hành quân tính theo khoảng cách Euclid:
    $$\text{ETA (giây)} = \sqrt{(X_2 - X_1)^2 + (Y_2 - Y_1)^2} \times 30 \times \text{TerrainModifier}$$
- **Lệnh thu hồi (Recall)**:
  - Khi quân đang hành quân và chưa tiếp cận mục tiêu trong vòng 30 giây cuối, Master có thể ra lệnh thu hồi (`Recall Army`).
  - Quân đoàn sẽ lập tức quay đầu trở về căn cứ với 100% tốc độ di chuyển hiện tại.

### 3.4. Quy tắc Sinh tồn & Thương vong trong PvP (`MOD-13-05`)
- **BẢO VỆ HERO TRONG PVP (NON-PERMADEATH FOR PVP)**:
  - Khác với chế độ PvE Hardcore Dungeon (nơi Normal Hero bị Permadeath), **trong tất cả các hoạt động PvP (tấn công người chơi, công thành, tranh đoạt lãnh thổ)**:
    - Normal Hero khi bị đánh bại **KHÔNG BỊ XÓA VĨNH VIỄN**.
    - Normal Hero bị hạ gục sẽ chuyển sang trạng thái **Trọng Thương (`CRITICALLY_INJURED`)** và tự động được đưa về Cơ sở y tế (Medical Facility) tại căn cứ để điều trị.
    - Hero Limited/Special rơi vào trạng thái **Hôn Mê/Vô Hiệu Hóa (`DISABLED`)** và cần thời gian hồi phục 60 phút hoặc sử dụng Thảo Dược Hồi Phục.
- **Quy tắc Cướp tài nguyên (Resource Plunder)**:
  - Bên thắng trận chỉ có thể cướp tối đa **20%** lượng tài nguyên chưa bảo vệ (ngoài hạn mức Kho an toàn - Vault Protection) của bên thua trong một cuộc tấn công.
- **Cơ chế Khiên Hòa Bình (Peace Shield - `FUN-13-05-006`)**:
  - **Khiên Tân thủ**: Người chơi mới bước vào Global World nhận Khiên 48 giờ.
  - **Khiên Cứu trợ sau thất bại**: Nếu căn cứ bị tấn công và thất thủ, hệ thống tự động kích hoạt Khiên bảo hộ khẩn cấp **8 giờ**.
  - **Quy tắc phá khiên**: Bất kỳ hành động thù địch nào (phái do thám, gửi quân tấn công ô đất hoặc căn cứ của người chơi khác) sẽ **lập tức hủy bỏ Khiên bảo vệ**.

### 3.5. Quy tắc Liên minh (Alliance System - `MOD-13-06`)
- **Điều kiện thành lập**: Master Cấp độ 20 trở lên, chi phí 5,000 Gem hoặc 500,000 Silver Coins.
- **Quy mô thành viên**: Ban đầu tối đa 30 thành viên, có thể mở rộng lên tối đa 100 thành viên qua cống hiến công nghệ liên minh (Alliance Tech).
- **Phân cấp chức vụ**:
  - *Chủ Bang (Leader)*: Toàn quyền, chuyển giao chức vụ, giải tán bang, tuyên chiến.
  - *Phó Bang / Cán sự (Officer)*: Duyệt thành viên, kích hoạt buff bang, đặt cờ hiệu mục tiêu.
  - *Thành viên (Member)*: Tham gia đóng góp, trò chuyện, hỗ trợ quân sự.
- **Rời liên minh**: Thành viên chủ động rời bang hoặc bị trục xuất chịu thời gian chờ **24 giờ Cooldown** trước khi có thể xin gia nhập liên minh mới.

### 3.6. Chiến tranh Thế giới & Chinh phục Mùa giải (World Conquest - `MOD-13-07`)
- **Chu kỳ Mùa giải**: Mỗi mùa giải World Conquest kéo dài cố định **30 ngày**.
- **Kỳ Quan Trung Tâm (Central Imperial Wonder)**:
  - Tọa lạc tại trung tâm bản đồ thế giới $(500, 500)$.
  - Mở cổng tranh đoạt vào 3 ngày cuối cùng của mùa giải.
  - Liên minh chiếm giữ và bảo vệ thành công Kỳ Quan trong thời gian tích lũy 8 giờ liên tục sẽ trở thành **Liên Minh Thống Trị (Conqueror Alliance)**.
- **Phần thưởng mùa giải**: Khung viền Master độc quyền, Danh hiệu Bá Chủ Thế Giới, 10 Vé Triệu Hồi Thất Sắc (Seven-Color Heavenly Scroll), và tượng vinh danh tại Quảng trường Thế Giới cho mùa kế tiếp.

---

## 4. Bảng Ma trận Yêu cầu Chức năng P3

| Mã Module | Tên Module | Số lượng | Danh sách Function ID |
|---|---|---|---|
| `MOD-13-01` | Global World & Map Exploration | 5 | FUN-13-01-001 đến FUN-13-01-005 |
| `MOD-13-02` | Territory Control & Expansion | 5 | FUN-13-02-001 đến FUN-13-02-005 |
| `MOD-13-03` | Scouting & Intelligence | 3 | FUN-13-03-001 đến FUN-13-03-003 |
| `MOD-13-04` | Army Management & Movement | 5 | FUN-13-04-001 đến FUN-13-04-005 |
| `MOD-13-05` | PvP Combat & Territory Defense | 7 | FUN-13-05-001 đến FUN-13-05-007 |
| `MOD-13-06` | Alliance System | 6 | FUN-13-06-001 đến FUN-13-06-006 |
| `MOD-13-07` | World War & Conquest | 6 | FUN-13-07-001 đến FUN-13-07-006 |
| **Tổng cộng** | **7 Modules** | **37** | **37 Chức năng** |
