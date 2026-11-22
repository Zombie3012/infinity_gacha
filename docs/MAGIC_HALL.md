# Đại Sảnh Ma Thuật là công trình ma thuật duy nhất

Quy tắc từ 22/11/2026: chỉ xây **Đại Sảnh Ma Thuật** (`HALL_OF_MAGIC`). Bỏ ba công trình riêng `LIBRARY`, `ALCHEMY_WORKSHOP`, `MAGIC_RESEARCH_LAB` khỏi danh mục xây dựng, bản đồ căn cứ và luồng xây mới. Ba mã này vẫn được dùng nội bộ để xác định chức năng/phân khu.

## Chức năng giữ lại

Chọn Đại Sảnh Ma Thuật trên căn cứ, bấm **Đại sảnh ma thuật** trên thanh thao tác để mở cửa sổ ở giữa màn hình. Cửa sổ có ba tab, bộ chọn Hero và nhân sự dùng chung:

- **Thư viện**: sản xuất sách EXP, tu luyện MAGE, đọc sách EXP và thao tác kỹ năng hiện có. Cần MAGE để sản xuất sách.
- **Giả kim**: sản xuất/thu hoạch Đá Cường Hóa, chế thuốc theo công thức đã nghiên cứu, điều trị và dùng thuốc ma lực/cường lực.
- **Nghiên cứu**: chuyển chức, thức tỉnh và cây Giả kim gồm nền tảng cùng ba nhánh thuốc độc lập. Nghiên cứu tức thì và giữ theo Master khi phá/xây lại đại sảnh.

Xem [giả kim và vật phẩm PvE](ALCHEMY_PVE_CONSUMABLES.md) để biết chi phí, công thức, năm ô tiêu hao mỗi Hero, combat thủ công và API. Chuyển đổi nguyên liệu cùng nhánh Bến Thiên Hành vẫn là định hướng, chưa có gameplay.

Hero tử trận hoặc đang triển khai PvE không xuất hiện trong bộ chọn. Nút phát triển kiểm tra khóa Hero, cấp, vật phẩm và chi phí; khi đang gửi yêu cầu, các thao tác bị khóa để tránh nhấn lặp. Hero cần rời vị trí nhân sự trước khi chuyển chức/thức tỉnh. Sau mỗi thao tác, cửa sổ tải lại Hero, kho và đại sảnh; vật phẩm dùng hết không còn giữ số lượng cũ. Khi mất phản hồi, không tự gửi lại lệnh tiêu hao.

Đại sảnh giữ ba cấp, tối đa sáu Hero. Nhân sự dùng chung: ưu tiên tối đa hai MAGE cho sản xuất sách; hai Hero tiếp theo hỗ trợ giả kim. Các thao tác nghiên cứu tiếp tục dùng quy tắc cũ. Không thêm hệ thống phân công độc lập mới.

Sản xuất sách và đá được lưu riêng trong `magic_production_nodes`; không còn phụ thuộc công trình con. Tỷ lệ theo cấp giữ nguyên: sách 100/50/15 mỗi giờ theo bậc sách sơ/trung/cao, đá 15/30/60 mỗi giờ. Lệnh thu hoạch ở đại sảnh nhận đồng thời các sản phẩm và trả danh sách `resources`. Hai lệnh thu đồng thời không trả lại cùng lượng hàng.

Thêm/bỏ nhân sự chốt lượng đã sản xuất trước khi đổi hiệu suất; không tính sách ngược về thời gian chưa có MAGE. Nâng cấp đại sảnh cập nhật cả hai phân khu ngay; sản phẩm bậc sách cũ được chuyển vào kho trước khi đổi bậc, không đổi sách sơ cấp thành sách cao cấp.

## Dữ liệu đã xây theo bản cũ

Migration `0056` gộp các công trình con:

1. Dùng đại sảnh hiện có đầu tiên của Master; nếu chưa có, chuyển một công trình con thành đại sảnh tại ô cũ.
2. Giữ cấp cao nhất đã đạt/đã thanh toán nâng cấp, tối đa cấp 3.
3. Chuyển sản phẩm tồn và sản lượng đã tích lũy của công trình con vào kho đúng loại cũ. Phần lẻ được làm tròn lên một lần để không mất tiến độ khi bỏ công trình; đổi bậc sách trong đại sảnh cũng áp dụng nguyên tắc bảo toàn sản phẩm này.
4. Chuyển nhân sự về đại sảnh. Nếu vượt sáu chỗ, Hero dư trở về nhóm chưa phân công, không bị xóa. Không thu thêm phí, không tự hoàn bạc xây dựng; đầu tư cấp được gộp vào đại sảnh.
5. Xóa các instance công trình con, giải phóng ô đất, bỏ ba loại công trình khỏi catalog. Không xóa Hero, trang bị, lịch sử hoặc các tính năng tương ứng.

Các đại sảnh đã tồn tại được giữ nguyên instance; không gộp những đại sảnh độc lập với nhau. Hàm bảo trì nội bộ `consolidate_magic_buildings(master_id)` có thể áp dụng lại an toàn cho dữ liệu cũ chưa gộp; gọi lại khi không còn công trình con không tạo thưởng lặp.

Danh mục và điều kiện xây đại sảnh thống nhất: World Level 2 hoặc Master Lv.15. Giữ cách nâng cấp tức thì.

## Kiểm chứng có mục tiêu

`http.magic-hall.test.mjs` kiểm tra danh mục/khóa xây công trình cũ, sản xuất, thu hoạch đồng thời, tu luyện MAGE, nâng cấp và chuyển dữ liệu có/không có đại sảnh, gồm trường hợp thừa nhân sự. Scene Godot `magic_hall_ui_test.tscn` kiểm tra ba tab cũ của bảng thông tin.

`node scripts/test-godot-magic-hall.mjs` tạo tài khoản thử, chạy cửa sổ chuyên dụng trong Godot qua HTTP/PostgreSQL thật và dọn dữ liệu sau kiểm tra. Đặt `GODOT_BIN` tới engine khi engine chưa nằm trong PATH. Gồm 26 kiểm tra: vị trí giữa màn hình, ba tab, chọn Hero sống, nhân sự, tu luyện, sách EXP, thuốc, thu hoạch, thức tỉnh, chuyển chức, kỹ năng, cập nhật kho, khóa thao tác, nghiên cứu công thức, chế thuốc và năm ô tiêu hao. Runner `test-godot-pve-consumables.mjs` kiểm tra thêm điều khiển trận và dùng thuốc qua API thật. Kiểm tra headless chưa thay thế nghiệm thu hình ảnh bằng cửa sổ game tương tác. Không chạy full test hoặc `npm run verify` khi chưa được yêu cầu.
