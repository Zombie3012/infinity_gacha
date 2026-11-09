# Use Case Specifications – Phase P3: Multiplayer & World Conquest

| Field | Value |
|---|---|
| Document ID | IG-BA-UCS-P3-001 |
| Version | 0.1 Draft |
| Project | Infinite Gacha (Hero Management & Survival Strategy RPG) |
| Source of Truth | MBFL.docx, BRD_P3_Draft.md, Phase_Scope_Matrix_P3.csv |
| Total Use Cases | 8 Use Cases (`UC-P3-01` đến `UC-P3-08`) |
| Total Functions Covered | 37 Functions (100% Phase P3 Scope) |

---

## 1. Danh sách Ma trận Ánh xạ Use Case (Use Case Mapping Matrix)

| UC ID | Tên Use Case | Module ID | Danh sách Function ID bao phủ | Actor chính |
|---|---|---|---|---|
| `UC-P3-01` | Mở khóa Thế giới chung & Khám phá Bản đồ | MOD-13-01 | FUN-13-01-001, FUN-13-01-002, FUN-13-01-003, FUN-13-01-004, FUN-13-01-005 | Master, Server System |
| `UC-P3-02` | Quản lý, Chiếm đóng & Nâng cấp Lãnh thổ | MOD-13-02 | FUN-13-02-001, FUN-13-02-002, FUN-13-02-003, FUN-13-02-004, FUN-13-02-005 | Master, Server System |
| `UC-P3-03` | Do thám & Báo cáo Tình báo Chiến thuật | MOD-13-03 | FUN-13-03-001, FUN-13-03-002, FUN-13-03-003 | Master, Server System |
| `UC-P3-04` | Thành lập, Phân công & Điều động Quân đoàn | MOD-13-04 | FUN-13-04-001, FUN-13-04-002, FUN-13-04-003, FUN-13-04-004, FUN-13-04-005 | Master, Server System |
| `UC-P3-05` | Khởi tạo Tấn công & Xử lý Trận đánh PvP | MOD-13-05 | FUN-13-05-001, FUN-13-05-002, FUN-13-05-003, FUN-13-05-004 | Master, Server System |
| `UC-P3-06` | Phòng thủ Lãnh thổ, Khiên Hòa Bình & Chiến báo | MOD-13-05 | FUN-13-05-005, FUN-13-05-006, FUN-13-05-007 | Master, Server System |
| `UC-P3-07` | Thành lập, Quản lý & Giao tiếp Liên minh | MOD-13-06 | FUN-13-06-001, FUN-13-06-002, FUN-13-06-003, FUN-13-06-004, FUN-13-06-005, FUN-13-06-006 | Master, Alliance Officer, Server |
| `UC-P3-08` | Tuyên chiến, Công thành & Xếp hạng Chinh phục Mùa giải | MOD-13-07 | FUN-13-07-001, FUN-13-07-002, FUN-13-07-003, FUN-13-07-004, FUN-13-07-005, FUN-13-07-006 | Master, Alliance Leader, Server |

---

## 2. Chi tiết Đặc tả Các Use Case

### UC-P3-01: Mở khóa Thế giới chung & Khám phá Bản đồ
- **Mã Use Case**: `UC-P3-01`
- **Tên Use Case**: Mở khóa Thế giới chung & Khám phá Bản đồ
- **Chức năng phụ trách**: `FUN-13-01-001`, `FUN-13-01-002`, `FUN-13-01-003`, `FUN-13-01-004`, `FUN-13-01-005`
- **Tác nhân (Actor)**: Master (Người chơi), Server System
- **Tiền điều kiện (Pre-conditions)**: Master đạt cấp độ $\ge 15$ và đã vượt qua tầng 10 của Dungeon chính (P0).
- **Hậu điều kiện (Post-conditions)**: Master được cấp vị trí căn cứ trên Global Map, sương mù mở rộng và tiến trình thế giới được ghi nhận.
- **Luồng sự kiện chính (Main Flow)**:
  1. Người chơi truy cập giao diện "Bản đồ Thế Giới (Global World)".
  2. Hệ thống kiểm tra điều kiện cấp độ $\ge 15$ và tiến độ Dungeon $\ge 10$ (`FUN-13-01-001`).
  3. Khi đủ điều kiện lần đầu, hệ thống tự động chọn một tọa độ ngẫu nhiên $(X, Y)$ tại Vùng Rìa (Outer Rim Region) và gán làm căn cứ chính của Master.
  4. Hệ thống tải dữ liệu lưới bản đồ $1000 \times 1000$ xung quanh vị trí căn cứ với bán kính tầm nhìn cơ bản 5 ô (`FUN-13-01-002`).
  5. Người chơi cuộn màn hình hoặc bấm chọn các Phân vùng (Region) khác nhau để xem thuộc tính tài nguyên, cấp độ quái và liên minh kiểm soát (`FUN-13-01-003`).
  6. Khi quân đội hoặc thám báo của Master tiến vào vùng chưa khám phá, hệ thống giải tỏa sương mù (Fog of War) và kích hoạt trạng thái "Đã khám phá" (`FUN-13-01-004`).
  7. Hệ thống cập nhật tỷ lệ phần trăm tiến trình khám phá thế giới chung của người chơi (`FUN-13-01-005`).

---

### UC-P3-02: Quản lý, Chiếm đóng & Nâng cấp Lãnh thổ
- **Mã Use Case**: `UC-P3-02`
- **Tên Use Case**: Quản lý, Chiếm đóng & Nâng cấp Lãnh thổ
- **Chức năng phụ trách**: `FUN-13-02-001`, `FUN-13-02-002`, `FUN-13-02-003`, `FUN-13-02-004`, `FUN-13-02-005`
- **Tác nhân (Actor)**: Master, Server System
- **Tiền điều kiện**: Master đã mở khóa Global World và sở hữu ít nhất một quân đoàn sẵn sàng.
- **Hậu điều kiện**: Quyền sở hữu ô đất được cập nhật, tài nguyên được sản xuất theo chu kỳ.
- **Luồng sự kiện chính (Main Flow)**:
  1. Người chơi nhấn vào một ô đất bất kỳ trên bản đồ để xem thông tin chi tiết: Loại ô, cấp độ tài nguyên, trạng thái vô chủ hoặc tên người sở hữu hiện tại (`FUN-13-02-001`).
  2. Người chơi chọn lệnh "Chiếm đóng (Claim Territory)" và điều quân đoàn tiếp cận (`FUN-13-02-002`).
  3. Hệ thống kiểm tra giới hạn ô lãnh thổ tối đa hiện tại của Master ($Current < Cap$). Nếu chưa đầy, cho phép tấn công quái thủ vệ.
  4. Sau khi dọn sạch quái vệ binh, hệ thống chuyển quyền sở hữu ô đất cho Master và áp dụng thời gian bảo hộ chiếm đóng 30 phút (`FUN-13-02-005`).
  5. Người chơi có thể tiêu tốn Đá & Gỗ để nâng cấp Trạm Thu Hoạch hoặc Tiền đồn trên ô đất nhằm tăng tốc độ sản xuất tài nguyên (`FUN-13-02-003`).
  6. Khi muốn mở rộng sang vị trí đắc địa khác mà đã chạm trần giới hạn ô, người chơi chọn "Từ bỏ lãnh thổ (Abandon)" (`FUN-13-02-004`).
  7. Hệ thống đếm ngược 10 phút trước khi giải phóng quyền sở hữu ô đất về trạng thái vô chủ.

---

### UC-P3-03: Do thám & Báo cáo Tình báo Chiến thuật
- **Mã Use Case**: `UC-P3-03`
- **Tên Use Case**: Do thám & Báo cáo Tình báo Chiến thuật
- **Chức năng phụ trách**: `FUN-13-03-001`, `FUN-13-03-002`, `FUN-13-03-003`
- **Tác nhân (Actor)**: Master, Server System
- **Tiền điều kiện**: Master có Tháp Trinh Sát (Scout Tower) tại căn cứ và mục tiêu nằm trong tầm do thám.
- **Hậu điều kiện**: Báo cáo trinh sát được gửi vào hòm thư tình báo của Master.
- **Luồng sự kiện chính (Main Flow)**:
  1. Người chơi chọn một căn cứ người chơi khác hoặc ô đất có quân đồn trú trên bản đồ.
  2. Người chơi chọn "Do thám (Scout)" và xác nhận chi phí Silver Coins (`FUN-13-03-001`, `FUN-13-03-002`).
  3. Hệ thống điều động trinh sát viên di chuyển tốc độ cao (nhanh gấp 3 lần quân đoàn thông thường) tới mục tiêu.
  4. Khi tiếp cận, hệ thống tính toán tỷ lệ thành công dựa trên chênh lệch cấp độ Tháp Trinh Sát của người công và người thủ.
  5. Hệ thống khởi tạo Báo cáo Trinh Sát (`Scouting Report`) chứa thông tin tùy theo cấp độ thành công (`FUN-13-03-003`):
     - *Cấp 1*: Ước lượng tổng lực chiến và lượng tài nguyên khả dụng.
     - *Cấp 2*: Danh sách Hero đồn trú và cấp độ của họ.
     - *Cấp 3*: Chi tiết trang bị, kỹ năng và bẫy phòng thủ của đối phương.
  6. Nếu mục tiêu đang có Khiên bảo vệ, hệ thống cảnh báo và từ chối xuất trinh sát.

---

### UC-P3-04: Thành lập, Phân công & Điều động Quân đoàn
- **Mã Use Case**: `UC-P3-04`
- **Tên Use Case**: Thành lập, Phân công & Điều động Quân đoàn
- **Chức năng phụ trách**: `FUN-13-04-001`, `FUN-13-04-002`, `FUN-13-04-003`, `FUN-13-04-004`, `FUN-13-04-005`
- **Tác nhân (Actor)**: Master, Server System
- **Tiền điều kiện**: Master có ít nhất 1 Hero đang rảnh (không làm việc hoặc điều trị trong cơ sở y tế).
- **Hậu điều kiện**: Quân đoàn hành quân trên bản đồ thế giới với lộ trình thời gian thực.
- **Luồng sự kiện chính (Main Flow)**:
  1. Người chơi truy cập Trại Lính (Barracks) và chọn "Tạo Quân Đoàn Mới (Create Army)" (`FUN-13-04-001`).
  2. Người chơi chọn 1 Chủ Tướng (Commander) và tối đa 4 Hero đồng đội từ danh sách Hero khả dụng (`FUN-13-04-002`).
  3. Hệ thống kiểm tra thể lực và độ đói của các Hero (Fatigue $\le 80$, Hunger $\le 80$).
  4. Người chơi chọn mục tiêu trên bản đồ (tọa độ ô đất, quái vật, hoặc căn cứ địch) và nhấn "Xuất Quân (Deploy Army)" (`FUN-13-04-003`).
  5. Hệ thống tính toán thời gian hành quân theo công thức ETA và bắt đầu tiến trình di chuyển thời gian thực (`FUN-13-04-005`).
  6. Trong quá trình hành quân, nếu người chơi đổi ý trước khi tới đích 30 giây, người chơi nhấn "Thu Hồi (Recall)" (`FUN-13-04-004`).
  7. Quân đoàn lập tức đảo chiều và hành quân ngược lại căn cứ.

---

### UC-P3-05: Khởi tạo Tấn công & Xử lý Trận đánh PvP
- **Mã Use Case**: `UC-P3-05`
- **Tên Use Case**: Khởi tạo Tấn công & Xử lý Trận đánh PvP
- **Chức năng phụ trách**: `FUN-13-05-001`, `FUN-13-05-002`, `FUN-13-05-003`, `FUN-13-05-004`
- **Tác nhân (Actor)**: Master (Người tấn công), Server System
- **Tiền điều kiện**: Quân đoàn đã tiếp cận mục tiêu người chơi khác.
- **Hậu điều kiện**: Trận đánh được mô phỏng giải quyết, tài nguyên cướp đoạt và thương vong được cập nhật.
- **Luồng sự kiện chính (Main Flow)**:
  1. Quân đoàn của Master tiếp cận tọa độ căn cứ hoặc ô đất mục tiêu và kích hoạt tấn công (`FUN-13-05-001`).
  2. Hệ thống kiểm tra điều kiện an toàn PvP (`FUN-13-05-002`):
     - Mục tiêu có đang trong trạng thái Khiên Hòa Bình (Peace Shield) hay không? Nếu có, quân đoàn tự động quay về.
     - Người tấn công có khiên không? Nếu có, hệ thống hủy bỏ ngay Khiên của người tấn công.
  3. Hệ thống tải dữ liệu quân đội tấn công và quân đội đồn trú phòng thủ của mục tiêu.
  4. Hệ thống chạy thuật toán mô phỏng giao tranh PvP tự động (PvP Auto-Resolve Engine) theo lượt dựa trên chỉ số thuộc tính, kỹ năng và vị trí đội hình (`FUN-13-05-003`).
  5. Hệ thống xử lý kết quả chiến trận (`FUN-13-05-004`):
     - Xác định bên thắng/thua.
     - **Quy tắc bảo vệ Hero**: Normal Hero tử trận được đánh dấu là `CRITICALLY_INJURED` (không bị xóa vĩnh viễn), chuyển về Phòng Y Tế. Hero Special/Limited rơi vào trạng thái `DISABLED`.
     - Tính toán chiến lợi phẩm cướp bóc: Tối đa 20% tài nguyên chưa được kho bảo vệ.
     - Quân tấn công mang tài nguyên cướp được hành quân trở về căn cứ.

---

### UC-P3-06: Phòng thủ Lãnh thổ, Khiên Hòa Bình & Chiến báo
- **Mã Use Case**: `UC-P3-06`
- **Tên Use Case**: Phòng thủ Lãnh thổ, Khiên Hòa Bình & Chiến báo
- **Chức năng phụ trách**: `FUN-13-05-005`, `FUN-13-05-006`, `FUN-13-05-007`
- **Tác nhân (Actor)**: Master (Người phòng thủ), Server System
- **Tiền điều kiện**: Căn cứ hoặc lãnh thổ của người chơi bị tấn công.
- **Hậu điều kiện**: Lực lượng phòng thủ phản kháng, khiên tự động kích hoạt nếu thất thủ nặng, chiến báo gửi tới người chơi.
- **Luồng sự kiện chính (Main Flow)**:
  1. Người chơi thiết lập Đội hình Đồn trú Phòng thủ (Garrison Defense Team) tại căn cứ hoặc ô lãnh thổ sở hữu (`FUN-13-05-005`).
  2. Khi có quân địch tiến công, đội đồn trú tự động tham gia giao chiến bảo vệ.
  3. Nếu phòng thủ thất bại và căn cứ bị thiệt hại vượt quá 20% tài nguyên dự trữ, hệ thống tự động kích hoạt **Khiên Cứu Trợ 8 Giờ (Emergency Peace Shield)** để ngăn chặn việc bị tấn công liên tục (`FUN-13-05-006`).
  4. Hệ thống ghi lại toàn bộ nhật ký giao tranh gồm số lượt, sát thương gây ra, Hero bị thương và tài nguyên tổn thất.
  5. Hệ thống gửi thông báo đẩy (Push Notification) và lưu trữ bản ghi Chiến Báo PvP (`PvP Battle Report`) vào mục Hộp Thư Chiến Trận của cả hai người chơi (`FUN-13-05-007`).

---

### UC-P3-07: Thành lập, Quản lý & Giao tiếp Liên minh
- **Mã Use Case**: `UC-P3-07`
- **Tên Use Case**: Thành lập, Quản lý & Giao tiếp Liên minh
- **Chức năng phụ trách**: `FUN-13-06-001`, `FUN-13-06-002`, `FUN-13-06-003`, `FUN-13-06-004`, `FUN-13-06-005`, `FUN-13-06-006`
- **Tác nhân (Actor)**: Master, Alliance Leader/Officer, Server System
- **Tiền điều kiện**: Master đạt cấp độ $\ge 20$ và chưa gia nhập liên minh nào (hoặc đã hết 24h cooldown).
- **Hậu điều kiện**: Liên minh được tạo hoặc tư cách thành viên được thiết lập, quyền giao tiếp bang được kích hoạt.
- **Luồng sự kiện chính (Main Flow)**:
  1. Người chơi mở giao diện "Liên Minh (Alliance)".
  2. Người chơi có thể chọn một trong các hành động:
     - **Tạo Liên Minh**: Nhập tên liên minh (duy nhất, 3-20 ký tự), biểu tượng cờ, khẩu hiệu và thanh toán phí 5,000 Gem hoặc 500,000 Silver Coins (`FUN-13-06-001`).
     - **Tìm kiếm & Gia nhập**: Tìm kiếm liên minh theo tên hoặc lọc theo ngôn ngữ/yêu cầu lực chiến (`FUN-13-06-002`), sau đó gửi yêu cầu xin vào (`FUN-13-06-003`).
  3. Chủ bang hoặc Phó bang duyệt đơn xin vào từ danh sách chờ (`FUN-13-06-005`).
  4. Cán sự bang có thể thăng cấp, giáng cấp thành viên hoặc trục xuất thành viên vi phạm quy chế bang (`FUN-13-06-005`).
  5. Người chơi có thể chủ động nhấn "Rời Liên Minh (Leave Alliance)". Hệ thống hiển thị cảnh báo và áp dụng thời gian chờ 24h trước khi được vào bang mới (`FUN-13-06-004`).
  6. Thành viên sử dụng Kênh Chat Bang Hội để trao đổi văn bản và gửi ping đánh dấu tọa độ chiến thuật $(X, Y)$ trên bản đồ thế giới (`FUN-13-06-006`).

---

### UC-P3-08: Tuyên chiến, Công thành & Xếp hạng Chinh phục Mùa giải
- **Mã Use Case**: `UC-P3-08`
- **Tên Use Case**: Tuyên chiến, Công thành & Xếp hạng Chinh phục Mùa giải
- **Chức năng phụ trách**: `FUN-13-07-001`, `FUN-13-07-002`, `FUN-13-07-003`, `FUN-13-07-004`, `FUN-13-07-005`, `FUN-13-07-006`
- **Tác nhân (Actor)**: Alliance Leader, Server System
- **Tiền điều kiện**: Mùa giải World Conquest đang ở giai đoạn mở chiến dịch hoặc tranh đoạt kỳ quan.
- **Hậu điều kiện**: Kết quả mùa giải được xác định, danh hiệu thống trị và phần thưởng độc quyền được trao tặng.
- **Luồng sự kiện chính (Main Flow)**:
  1. Chủ bang chọn một liên minh đối thủ hoặc một Kỳ Đài/Thành Trì Chiến Thuật trên bản đồ và nhấn "Tuyên Chiến (Declare War)" (`FUN-13-07-001`).
  2. Hệ thống thiết lập trạng thái chiến tranh giữa hai bên trong thời hạn 24 giờ và hiển thị bảng đếm ngược tiến độ chiến sự (`FUN-13-07-002`).
  3. Các thành viên liên minh tiến hành phối hợp xuất quân công thành, vây hãm Kỳ Quan Trung Tâm hoặc ô đất đối phương (`FUN-13-07-003`).
  4. Hệ thống tích lũy Điểm Chinh Phục (Conquest Points) dựa trên số lượng căn cứ phá hủy, quân địch tiêu diệt và thời gian giữ cứ điểm.
  5. Khi thời gian chiến tranh hoặc giai đoạn tranh đoạt Kỳ Quan kết thúc, hệ thống xác định kết quả thắng bại của chiến dịch (`FUN-13-07-004`).
  6. Vào ngày cuối cùng của mùa giải 30 ngày, hệ thống tổng kết Bảng Xếp Hạng Thống Trị Thế Giới (World Conquest Ranking) (`FUN-13-07-006`).
  7. Hệ thống tự động phân phát phần thưởng mùa giải (Vé triệu hồi thất sắc, Gem, khung viền vinh danh) qua Hòm Thư cho toàn bộ thành viên theo thứ hạng đạt được (`FUN-13-07-005`).
