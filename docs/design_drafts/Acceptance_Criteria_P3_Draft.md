# Acceptance Criteria – Phase P3: Multiplayer & World Conquest

> **L?u tr? thi?t k? l?ch s?.** Checklist v? k?t qu? ki?m tra ph?n ?nh th?i ?i?m vi?t; c?c m? t? Web/Unity, pity v? duplicate c? th? ?? ???c thay th?. Xem [README hi?n h?nh](../../README.md) v? [backlog Godot](../../GODOT_BACKLOG.md), c?p nh?t 22/11/2026 (UTC+7).

| Field | Value |
|---|---|
| Document ID | IG-BA-AC-P3-001 |
| Version | 0.1 Draft |
| Project | Infinite Gacha (Hero Management & Survival Strategy RPG) |
| Source of Truth | BRD_P3_Draft.md, Use_Case_Spec_P3_Draft.md, Data_Model_P3_Draft.md |
| Total Scenarios Covered | 8 Use Cases (`UC-P3-01` đến `UC-P3-08`), 100% Phase P3 Scope |

---

## UC-P3-01: Mở khóa Thế giới chung & Khám phá Bản đồ

```gherkin
Feature: Mở khóa Thế giới chung và Khám phá Bản đồ
  Là một người chơi đã đạt đủ trình độ phát triển căn cứ PvE
  Tôi muốn mở khóa bản đồ thế giới chung để bắt đầu mở rộng lãnh thổ và tương tác với các người chơi khác

  Scenario: Master đủ điều kiện mở khóa thế giới chung lần đầu
    Given Master có Level là 15
    And Master đã vượt qua Dungeon Tầng 10
    When Master nhấn vào biểu tượng "Bản đồ Thế Giới (Global World)"
    Then Hệ thống mở khóa tính năng Global World
    And Hệ thống cấp phát ngẫu nhiên một tọa độ căn cứ (X, Y) tại Vùng Rìa (Outer Rim Region)
    And Hệ thống cấp Khiên Tân Thủ 48 giờ (Novice Shield)
    And Bản đồ hiển thị khu vực bán kính 5 ô xung quanh căn cứ đã giải tỏa sương mù

  Scenario: Master chưa đủ điều kiện cố gắng truy cập Global World
    Given Master có Level là 12
    And Master chỉ mới vượt qua Dungeon Tầng 8
    When Master nhấn vào biểu tượng "Bản đồ Thế Giới"
    Then Hệ thống hiển thị thông báo "Yêu cầu Master Cấp 15 và vượt qua Dungeon Tầng 10 để mở khóa"
    And Không cho phép vào màn hình bản đồ thế giới
```

---

## UC-P3-02: Quản lý, Chiếm đóng & Nâng cấp Lãnh thổ

```gherkin
Feature: Chiếm đóng, Nâng cấp và Từ bỏ Lãnh thổ
  Là một Master trên bản đồ thế giới
  Tôi muốn chiếm đóng các ô tài nguyên để gia tăng sản lượng căn cứ

  Scenario: Chiếm đóng ô tài nguyên vô chủ thành công
    Given Master đang sở hữu 5 ô đất trên giới hạn tối đa 10 ô
    And Ô đất tại tọa độ (240, 150) là ô Mỏ Đá (Stone Mine) vô chủ
    When Quân đoàn của Master đánh bại quái vật thủ hộ tại ô đất
    Then Hệ thống gán quyền sở hữu ô đất cho Master
    And Trạng thái bảo hộ chiếm đóng 30 phút được kích hoạt
    And Số lượng ô đất sở hữu tăng lên 6/10
    And Sản lượng Đá của Master được cộng thêm theo giờ

  Scenario: Chiếm đất khi đã đạt giới hạn ô tối đa
    Given Master đang sở hữu 10 ô đất trên giới hạn tối đa 10 ô
    When Master ra lệnh cho quân đoàn chiếm thêm một ô đất mới
    Then Hệ thống từ chối và hiển thị thông báo "Đã đạt giới hạn lãnh thổ tối đa (10/10). Vui lòng nâng cấp Nhà Chỉ Huy hoặc từ bỏ bớt ô đất cũ"

  Scenario: Từ bỏ ô đất sở hữu
    Given Master đang sở hữu ô đất tại tọa độ (210, 180)
    When Master chọn thao tác "Từ bỏ lãnh thổ (Abandon Territory)"
    Then Hệ thống hiển thị đồng hồ đếm ngược 10 phút
    And Sau khi hết 10 phút, ô đất chuyển thành trạng thái Vô chủ
    And Giới hạn ô đất của Master giảm đi 1 ô
```

---

## UC-P3-03: Do thám & Báo cáo Tình báo Chiến thuật

```gherkin
Feature: Trinh sát đối thủ và ô lãnh thổ
  Là một Master chuẩn bị tấn công
  Tôi muốn do thám lực lượng phòng thủ của đối phương để lên chiến thuật phù hợp

  Scenario: Do thám mục tiêu không có Khiên thành công
    Given Tháp Trinh Sát của Master đạt Cấp 5
    And Căn cứ đối thủ tại tọa độ (300, 420) không có Khiên Hòa Bình
    When Master tiêu tốn 2,000 Silver Coins và phái Trinh sát viên
    Then Trinh sát di chuyển với tốc độ gấp 3 lần quân đoàn
    And Sau khi tiếp cận, Báo cáo Trinh Sát Cấp 2 được gửi vào Hòm thư
    And Báo cáo hiển thị chính xác danh sách Hero thủ thành và lượng tài nguyên khả dụng

  Scenario: Do thám mục tiêu đang có Khiên bảo vệ
    Given Căn cứ đối thủ tại tọa độ (300, 420) đang có Khiên Hòa Bình (Peace Shield) hiệu lực
    When Master nhấn chọn lệnh "Do thám (Scout)"
    Then Hệ thống hiển thị cảnh báo "Mục tiêu đang được bảo hộ bởi Khiên Hòa Bình, không thể do thám"
    And Không trừ Silver Coins của Master
```

---

## UC-P3-04: Thành lập, Phân công & Điều động Quân đoàn

```gherkin
Feature: Quản lý và Điều động Quân đoàn
  Là một Master
  Tôi muốn thành lập quân đoàn gồm các Hero mạnh mẽ để hành quân chiến đấu

  Scenario: Tạo quân đoàn và xuất quân hành quân thời gian thực
    Given Master có Hero "Lancelot" đang rảnh rỗi và thể lực tốt (Fatigue < 80)
    When Master tạo Quân đoàn 1 và bổ nhiệm "Lancelot" làm Chủ tướng
    And Master chọn mục tiêu ô đất tại tọa độ cách căn cứ 10 ô
    And Master nhấn "Xuất Quân"
    Then Quân đoàn chuyển sang trạng thái "MARCHING"
    And Hệ thống tính toán thời gian đến đích ETA là 300 giây (10 ô * 30 giây)
    And Đường hành quân hiển thị trực quan trên bản đồ thế giới

  Scenario: Thu hồi quân đoàn khi đang trên đường hành quân
    Given Quân đoàn đang ở trạng thái "MARCHING" và còn 120 giây nữa mới đến đích
    When Master nhấn nút "Thu Hồi (Recall)"
    Then Quân đoàn lập tức chuyển trạng thái sang "RETURNING"
    And Quân đoàn quay đầu hành quân trở về căn cứ với vận tốc không đổi
```

---

## UC-P3-05: Khởi tạo Tấn công & Xử lý Trận đánh PvP

```gherkin
Feature: Chiến đấu PvP và Xử lý Kết quả
  Là một Master tấn công đối thủ
  Tôi muốn cướp đoạt tài nguyên và chứng minh sức mạnh mà vẫn đảm bảo tính công bằng

  Scenario: Tấn công thắng trận, bảo vệ tính mạng Hero Normal
    Given Quân đoàn của Master tiếp cận căn cứ đối thủ không có khiên
    When Trận đánh PvP tự động diễn ra và Master giành chiến thắng
    Then Bên thắng cướp được tối đa 20% tài nguyên chưa được bảo vệ của đối thủ
    And Các Hero Normal của cả hai bên bị tử trận trong trận đánh CHỈ bị chuyển sang trạng thái "CRITICALLY_INJURED"
    And Không có bất kỳ Hero nào bị Permadeath (xóa vĩnh viễn)
    And Các Hero bị thương được đưa vào Cơ sở y tế để điều trị

  Scenario: Người tấn công tự làm mất Khiên bảo hộ khi phát động chiến tranh
    Given Master đang có Khiên Hòa Bình hiệu lực còn lại 12 giờ
    When Master phát lệnh tấn công căn cứ người chơi khác
    Then Hệ thống hiển thị cảnh báo "Phát động tấn công sẽ lập tức hủy bỏ Khiên Hòa Bình của bạn. Bạn có muốn tiếp tục?"
    And Khi Master xác nhận, Khiên Hòa Bình của Master lập tức bị vô hiệu hóa (is_active = FALSE)
```

---

## UC-P3-06: Phòng thủ Lãnh thổ, Khiên Hòa Bình & Chiến báo

```gherkin
Feature: Phòng thủ căn cứ và Kích hoạt Khiên Khẩn Cấp
  Là một Master bị tấn công khi đang offline
  Tôi muốn có cơ chế bảo vệ khỏi bị bắt nạt (anti-bullying) và nhận báo cáo đầy đủ

  Scenario: Tự động kích hoạt Khiên khẩn cấp 8 giờ sau khi thất thủ nặng
    Given Căn cứ Master bị đối thủ tấn công và thất bại
    And Căn cứ bị cướp mất hơn 20% lượng tài nguyên tích trữ
    When Trận đánh hoàn tất
    Then Hệ thống tự động kích hoạt "Khiên Cứu Trợ Khẩn Cấp (Emergency Peace Shield)" trong 8 giờ
    And Trong 8 giờ này không người chơi nào có thể do thám hay tấn công căn cứ Master
    And Hệ thống gửi Chiến Báo PvP chi tiết vào Hòm Thư
```

---

## UC-P3-07: Thành lập, Quản lý & Giao tiếp Liên minh

```gherkin
Feature: Hệ thống Liên Minh
  Là một Master
  Tôi muốn cùng người chơi khác xây dựng bang hội hùng mạnh

  Scenario: Tạo liên minh mới thành công
    Given Master đạt Cấp độ 22 và có 5,000 Gems
    And Master hiện không tham gia liên minh nào
    When Master nhập tên liên minh "Vanguard", Tag "[VNG]" và thanh toán 5,000 Gems
    Then Liên minh "Vanguard" được tạo với Master là Leader (Chủ bang)
    And Giới hạn thành viên ban đầu là 30 người

  Scenario: Rời liên minh chịu Cooldown 24 giờ
    Given Master là thành viên của liên minh "Vanguard"
    When Master nhấn chọn "Rời Liên Minh (Leave Alliance)" và xác nhận
    Then Master bị xóa khỏi danh sách thành viên liên minh
    And Master nhận trạng thái Cooldown 24 giờ không thể xin gia nhập liên minh khác
```

---

## UC-P3-08: Tuyên chiến, Công thành & Xếp hạng Chinh phục Mùa giải

```gherkin
Feature: Chiến tranh Thế giới và Xếp hạng Mùa giải
  Là một Chủ Bang (Alliance Leader)
  Tôi muốn dẫn dắt bang hội đoạt Kỳ Quan Trung Tâm và giành danh hiệu Thống Trị Thế Giới

  Scenario: Chiếm giữ Kỳ Quan Trung Tâm và giành chiến thắng Mùa giải
    Given Mùa giải World Conquest đang ở 3 ngày cuối cùng
    And Kỳ Quan Trung Tâm tại tọa độ (500, 500) mở cổng tranh đoạt
    When Liên minh "Vanguard" chiếm giữ và phòng thủ liên tục trong 8 giờ
    Then Liên minh "Vanguard" trở thành "Liên Minh Thống Trị (Conqueror Alliance)" của Mùa giải
    And Khi mùa giải 30 ngày kết thúc, toàn bộ thành viên nhận danh hiệu và Thưởng Mùa Giải (Vé Triệu Hồi Thất Sắc) qua Hòm thư
    And Tên liên minh được vinh danh trên Bảng Xếp Hạng World Conquest Ranking
```
