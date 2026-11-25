# Sử Điện Anh Hùng, tử trận và độ hiếm

Quy tắc hiện hành từ 22/11/2026. Tài liệu này thay thế các mô tả cũ về Hero Normal chết vĩnh viễn, SPECIAL/LIMITED được bảo hộ, Thần Lệ và chi phí hồi sinh theo chu kỳ.

## Hero và triệu hồi

- Mọi Hero dùng cùng luật sinh tử: HP về 0 là `DEAD`, ngừng chiến đấu, làm việc, nghỉ ngơi và điều trị thường. Không có Hero bất tử theo nguồn triệu hồi.
- `NORMAL`, `SPECIAL`, `LIMITED` chỉ còn là loại banner/phương thức thanh toán; vẫn giữ nguyên scroll/Gem, giá và tỷ lệ pool hiện có. `heroes.category` được giữ để tương thích dữ liệu, luôn là `HERO` và không tham gia quyết định tử vong.
- Mỗi phần thưởng Hero tạo một instance riêng, kể cả trùng template cố định. Không còn chuyển bản trùng SPECIAL/LIMITED thành Thiên Mệnh. Thiên Mệnh đã có trước cập nhật được giữ nguyên.
- Tử trận trong cả combat cũ và Combat v2 làm rơi trang bị đang mặc tại tầng giao chiến. Hồi sinh không tạo lại hoặc tự thu hồi trang bị đó. Tài nguyên phát triển đã dùng không được hoàn trả.

## Công trình Sử Điện Anh Hùng

Mã `HERO_CHRONICLE`, được phép xây từ khi tạo tài khoản; một cấp công trình, không cần nhân sự. Giá xây mẫu 1.200 Silver. Chọn công trình ở căn cứ → **Sử Điện Anh Hùng** để xem hồ sơ.

- Lưu riêng từng instance: tên, sao, nghề, thời điểm triệu hồi, tiểu sử và dòng thời gian. Tiểu sử là nội dung hư cấu sinh xác định theo ID, giữ nguyên khi thăng sao/hồi sinh.
- Bộ lọc: tất cả, đang sống, tử trận, đã tiêu hao; có phân trang 50 hồ sơ. Hồ sơ người tử trận vẫn hiển thị tại đây.
- Hồ sơ được ghi ngay khi Hero được tạo, kể cả chưa xây Sử Điện. Phá công trình không xóa hồ sơ.
- Hero bị dùng làm nguyên liệu có trạng thái hồ sơ `SACRIFICED`, không thể hồi sinh. Nếu instance tử trận đã bị xóa bởi thao tác quản trị, hồ sơ vẫn còn nhưng không còn đối tượng để hồi sinh.
- Database trigger ghi hồ sơ cùng giao dịch tạo Hero, tử trận, hồi sinh, thăng sao và tiêu hao; rollback không để lại mốc giả. API chỉ đọc/sửa hồ sơ thuộc Master đã đăng nhập.

## Ngọc hồi sinh 7★

Mã vật phẩm `RESURRECTION_GEM_7`, độ hiếm **7★**, tiêu hao đúng **1 viên cho 1 Hero tử trận**. Hero trở lại `HEALTHY`, **100% HP**, không mất Silver, không có chi phí tăng dần và không cần chờ chu kỳ 30 ngày. MP và các chỉ số sinh tồn theo trạng thái hiện có; hồi sinh không cấp lại trang bị đã rơi.

Chọn hồ sơ tử trận trong Sử Điện rồi bấm **Hồi sinh**. Kho vật phẩm hiển thị đủ bảy sao; vật phẩm không sử dụng trực tiếp bằng nút dùng chung trong túi. Ngọc có bán tại [Thương Thuyền Khinh Khí](SHOP_AIRSHIP.md) với giá tạm **1 bạc/viên** theo quyết định mới, đồng thời có thể dùng trong cấu hình thưởng/pool và công cụ quản trị.

Lệnh hồi sinh khóa Master rồi Hero, kiểm tra trạng thái và trừ ngọc trong cùng giao dịch. Gửi đồng thời hoặc gửi lại sau thành công chỉ có một lần tiêu hao; lệnh sau trả 409 khi Hero đã sống. Bảng chu kỳ cũ giữ để tương thích/lịch sử, không tính giá nữa. Thần Lệ cũ giữ trong kho lịch sử, ngừng bán và không dùng để hồi sinh; không tự đổi vật phẩm.

## Độ hiếm 1–7★

Hero và vật phẩm/nguyên liệu dùng số nguyên `rarity` từ 1 đến 7; giao diện dùng sao, không dùng SSR/SR/R hoặc S/A/B/C làm thước độ hiếm. Màu viền chỉ hỗ trợ nhận diện.

- Hero 6–7★ được mở trong sinh Hero, cấu hình admin và thăng sao; 7★ là trần. Không tự tăng tỷ lệ banner hoặc cấp sao cho Hero cũ.
- Thăng N★ lên N+1★ vẫn cần đúng N Hero sống cùng N★ làm nguyên liệu và đạt trần cấp hiện tại. Chi phí mẫu 5→6: 250.000 Silver; 6→7: 500.000 Silver.
- Trần sao là 10 cấp/sao, tối đa Lv.70, kết hợp trần đột phá: `min(sao × 10, (bậc đột phá + 1) × 10)`. Bổ sung đột phá bậc 5/6 và EXP Lv.51–70.
- Giữ công thức chỉ số 1–5★; 6–7★ tiếp tục ngân sách đã có. Sau Lv.50 tiếp tục tăng 8 điểm/cấp, phần bù tăng trưởng giữ tại mốc Lv.50.
- Độ hiếm vật liệu lấy từ `item_templates` khi trả kho và kết quả triệu hồi. Vật liệu cũ chưa có catalog dùng 1★ dự phòng; không dùng rarity 0 cho phần thưởng mới.

## API

| Endpoint | Chức năng |
|---|---|
| `GET /api/chronicles/heroes?status=DEAD&page=1` | Hồ sơ, tổng số, trang và số Ngọc hồi sinh đang sở hữu |
| `GET /api/chronicles/heroes/:id` | Tiểu sử và dòng thời gian của một instance |
| `POST /api/chronicles/heroes/:id/resurrect` | Dùng 1 ngọc, hồi sinh đầy HP |
| `POST /api/medical/resurrect` | Endpoint tương thích, cùng luật mới; body `{heroId}` |

## Nâng cấp dữ liệu và giới hạn

Migration `0053` bổ sung bảng `hero_chronicles`, trigger, catalog, công trình và cấu hình phát triển. Dữ liệu đang có được backfill; `DISABLED` và Hero 0 HP được chuẩn hóa thành `DEAD`, loại Hero chuẩn hóa thành `HERO`. Không tự hồi sinh người chơi. Trang bị lịch sử giữ nguyên vị trí trước migration; quy tắc rơi đồng nhất áp dụng các trận được quyết toán sau cập nhật.

Hồ sơ cũ chỉ khôi phục được từ instance còn tồn tại, death records và lịch sử điều trị đã lưu; không thể tái tạo chính xác các instance đã tiêu hao/xóa trước migration. Báo cáo trận và lịch sử thanh toán cũ được giữ nguyên như chứng cứ lịch sử.

Chỉ chạy kiểm tra có mục tiêu; không chạy full test hay `npm run verify` khi chưa được yêu cầu.
