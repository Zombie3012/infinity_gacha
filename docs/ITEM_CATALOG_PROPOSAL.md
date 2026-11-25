# Danh mục vật phẩm đề xuất

**Trạng thái: bản thiết kế chờ duyệt, không phải dữ liệu đang triển khai.** Danh mục gồm 141 mục, kết hợp các mã đã thấy trong mã nguồn/seed với đề xuất mới. Số sao và công dụng của mục mới chỉ là định hướng, chưa chốt cân bằng, giá, tỷ lệ rơi hoặc công thức. Không tự tạo vật phẩm, mở tính năng hay đổi dữ liệu dựa trên tài liệu này.

## Cách đọc và đối chiếu hiện tại

- **Đã có**: tìm thấy mã và mục đích tương ứng trong seed hoặc logic hiện tại; nguồn liệt kê là ví dụ và có thể cần điều kiện mở. Không mặc định mọi nguồn đều tồn tại.
- **Cần điều chỉnh**: đã có mã hoặc dữ liệu mẫu nhưng cần kiểm tra tên, công dụng, tính khả dụng hay cân bằng trước khi đưa vào danh mục chính thức. Giữ nguyên mã hiện tại cho đến khi có kế hoạch chuyển đổi.
- **Đề xuất mới**: chưa xác nhận tồn tại; nguồn nhận, công dụng và ô trang bị chỉ là thiết kế. Cột **Tương lai** chỉ rõ phụ thuộc chưa triển khai; các mục mới khác cũng chưa được triển khai dù dựa trên hệ thống đang có.
- Độ hiếm dùng thang 1–7★ hiện hành; không mặc định độ hiếm quyết định sức mạnh tuyến tính. Trang bị sử dụng sáu ô `MAIN_HAND`, `OFF_HAND`, `HELMET`, `CHEST`, `BOOTS`, `ACCESSORY`; các hiệu ứng mới cần thiết kế và kiểm chứng riêng.
- Tháp đang cho phép thu gỗ, đá, lương khô và dược liệu 1★ trên map phù hợp; Thương Thuyền mở sau vượt tầng 5, Đại Sảnh Ma Thuật sau vượt tầng 10, Viễn Chinh sau vượt tầng 25. Hầm Ngục Cổ Đại chỉ có thông báo đang phát triển; Khám Phá Hằng Ngày cũng mới là đề xuất, không phải nguồn nhận hiện có.
- Đồ trong cửa hàng hiện có giá thử 1 bạc; không dùng giá đó làm cân bằng cuối. Sách EXP ở đây chỉ dành cho **Hero**. Thiên Thư được lưu trong kho triệu hồi riêng; mã hàng cửa hàng khác loại thư. Trang bị là instance riêng, không phải vật phẩm xếp chồng thông thường.

### Phụ thuộc cần bảo toàn khi triển khai về sau

`WOOD`, `STONE`, `FOOD`, `FOOD_RAW`, `IRON`, `ENHANCEMENT_STONE`, `TELEPORT_STONE`, `ALCHEMY_HERB_1`, ba thuốc giả kim, `CLASS_CHANGE_TOKEN` và `RESURRECTION_GEM_7` có liên kết với các luồng hiện tại. Những mã `SAMPLE_HERO_*` vẫn được dùng cho sản xuất, phát triển Hero hoặc pool triệu hồi; `SAMPLE_IRON_SWORD`, `SAMPLE_LEATHER_CHEST`, `SAMPLE_SWIFT_CHARM` còn nằm trong công thức rèn, và một số trang bị mẫu được cấp khởi đầu. Không xóa/đổi mã chỉ vì có chữ `SAMPLE`.

`DIVINE_TEAR` đã ngừng dùng cho hồi sinh; `STAMINA_POTION` có seed nhưng tài liệu cửa hàng cho biết chưa có logic sử dụng. Ba mã `SAMPLE_TRASH_BROKEN_CHARM`, `SAMPLE_TRASH_DULL_SHARD`, `SAMPLE_TRASH_TORN_SCROLL` vẫn xuất hiện trong pool seed triệu hồi; cần quyết định thay thế và xử lý dữ liệu trước khi loại bỏ. Chúng không được tính vào danh mục đề xuất bên dưới.

**Nguồn kiểm tra:** [seed vật phẩm](../packages/server/src/database/seeds/item_templates.sample.sql), [seed trang bị](../packages/server/src/database/seeds/equipment_templates.sample.sql), [công thức rèn](../packages/server/src/database/seeds/crafting_recipes.sample.sql), [pool triệu hồi](../packages/server/src/database/seeds/banner_001.sample.sql), [giả kim](ALCHEMY_PVE_CONSUMABLES.md), [cửa hàng](SHOP_AIRSHIP.md), [tiến độ Tháp](TOWER_PROGRESSION.md). Đây là kiểm kê repository, không khẳng định nội dung database vận hành tại mọi thời điểm.

## Định hướng kinh tế

- **1–2★:** nguyên liệu và dụng cụ nền cho căn cứ, chuẩn bị đội và công thức nhập môn. **3–4★:** lựa chọn theo vai trò, dành cho tiến bộ trung hạn. **5–7★:** mục tiêu dài hạn, khác biệt về vai trò; không mặc định có nguồn nhận hay công thức sẵn.
- Vòng dự kiến: Tháp cung cấp lương thực, gỗ, đá và dược liệu → căn cứ, bếp, giả kim và Xưởng Rèn tiêu hao → đội chuẩn bị tốt hơn để tiếp tục Tháp. Phần mở rộng kết nối Khám Phá Hằng Ngày với nguyên liệu và di vật; Viễn Chinh cung cấp vật liệu chuyên biệt khi thiết kế nguồn nhận được duyệt.
- Tránh nguồn vô hạn không có nơi tiêu hao, nguyên liệu không có công dụng, và biến vật phẩm hiếm thành bắt buộc để tiếp tục chơi. Phân biệt phần thưởng lần đầu và chơi lại khi cân bằng về sau; chưa quy định số lượng hoặc xác suất.
- Trang bị đề xuất mô tả **vai trò**, không cam kết có sẵn hiệu ứng mới. Các món hồi sinh, triệu hồi và mở khóa không thay đổi quy tắc hiện tại. Giá, lượng rơi và công thức cần một đợt cân bằng riêng.

Trong các bảng, **Nguồn → nơi dùng** là hướng dự kiến; nếu ghi “hiện tại” thì chỉ khẳng định nơi đã đối chiếu. Các ký hiệu ô: tay chính `MAIN_HAND`, tay phụ `OFF_HAND`, đầu `HELMET`, thân `CHEST`, chân `BOOTS`, phụ kiện `ACCESSORY`.

## Nguyên liệu (30)

| Mã | Tên | Nhóm | ★ | Công dụng | Nguồn → nơi dùng | Trạng thái | Tương lai |
|---|---|---|---:|---|---|---|---|
| WOOD | Gỗ | Xây dựng | 1 | Xây dựng và chế tác cơ bản | Tháp, cửa hàng → căn cứ, rèn | Đã có | — |
| STONE | Đá | Xây dựng | 1 | Xây dựng và chế tác | Tháp, cửa hàng → căn cứ, rèn | Đã có | — |
| IRON | Quặng sắt | Khoáng | 2 | Nguyên liệu chế tạo | Cửa hàng → Xưởng Rèn | Đã có | — |
| ENHANCEMENT_STONE | Đá Tăng Cường | Cường hóa | 3 | Cường hóa trang bị | Cửa hàng → Xưởng Rèn | Đã có | — |
| ALCHEMY_HERB_1 | Dược liệu 1★ | Giả kim | 1 | Nghiên cứu và chế thuốc | Tháp, cửa hàng → Đại Sảnh Ma Thuật | Đã có | — |
| ALCHEMY_HERB_2 | Dược liệu 2★ | Giả kim | 2 | Dược liệu bậc cao | Cửa hàng → công thức tương lai | Cần điều chỉnh | Công thức bậc cao chưa có |
| ALCHEMY_HERB_3 | Dược liệu 3★ | Giả kim | 3 | Dược liệu bậc cao | Cửa hàng → công thức tương lai | Cần điều chỉnh | Công thức bậc cao chưa có |
| ALCHEMY_HERB_4 | Dược liệu 4★ | Giả kim | 4 | Dược liệu bậc cao | Cửa hàng → công thức tương lai | Cần điều chỉnh | Công thức bậc cao chưa có |
| ALCHEMY_HERB_5 | Dược liệu 5★ | Giả kim | 5 | Dược liệu bậc cao | Cửa hàng → công thức tương lai | Cần điều chỉnh | Công thức bậc cao chưa có |
| ALCHEMY_HERB_6 | Dược liệu 6★ | Giả kim | 6 | Dược liệu bậc cao | Cửa hàng → công thức tương lai | Cần điều chỉnh | Công thức bậc cao chưa có |
| ALCHEMY_HERB_7 | Dược liệu 7★ | Giả kim | 7 | Dược liệu bậc cao | Cửa hàng → công thức tương lai | Cần điều chỉnh | Công thức bậc cao chưa có |
| FOOD_RAW | Lương thực thô | Thực phẩm thô | 1 | Chế biến lương thực | Cửa hàng, sản xuất → Bếp | Đã có | — |
| MAT_OAK_HEARTWOOD | Lõi gỗ sồi | Gỗ hiếm | 2 | Làm cán vũ khí bền | Tháp đề xuất → Xưởng Rèn | Đề xuất mới | — |
| MAT_MOON_TIMBER | Gỗ ánh trăng | Gỗ hiếm | 4 | Khung trượng và cung phép | Khám Phá → Xưởng Rèn | Đề xuất mới | Khám Phá Hằng Ngày chưa triển khai |
| MAT_GRANITE | Đá hoa cương | Đá | 2 | Gia cố khiên và công trình | Tháp đề xuất → rèn, căn cứ | Đề xuất mới | — |
| MAT_SKY_CRYSTAL | Tinh thể trời | Tinh thể | 4 | Chế phụ kiện ma lực | Viễn Chinh đề xuất → Xưởng Rèn | Đề xuất mới | Nguồn rơi chưa thiết kế |
| MAT_COPPER_ORE | Quặng đồng | Khoáng | 1 | Chế phụ kiện nhập môn | Tháp đề xuất → Xưởng Rèn | Đề xuất mới | — |
| MAT_SILVER_ORE | Quặng bạc | Khoáng | 3 | Chế trang sức kháng phép | Khám Phá → Xưởng Rèn | Đề xuất mới | Khám Phá Hằng Ngày chưa triển khai |
| RARE_ORE | Quặng hiếm | Khoáng | 3 | Hợp kim trang bị tinh xảo | Khám Phá → Xưởng Rèn | Đề xuất mới | Khám Phá Hằng Ngày chưa triển khai |
| MAT_METEOR_IRON | Thiên thạch sắt | Khoáng | 5 | Rèn vũ khí chịu lực | Viễn Chinh đề xuất → Xưởng Rèn | Đề xuất mới | Nguồn rơi chưa thiết kế |
| MAT_SOFT_LEATHER | Da mềm | Da | 1 | May giáp linh hoạt | Tháp đề xuất → Xưởng Rèn | Đề xuất mới | — |
| MAT_HARD_HIDE | Da cứng | Da | 3 | Chế giáp phòng thủ | Tháp đề xuất → Xưởng Rèn | Đề xuất mới | — |
| MAT_SILK_THREAD | Tơ mịn | Vải | 2 | May trang bị pháp sư | Khám Phá → Xưởng Rèn | Đề xuất mới | Khám Phá Hằng Ngày chưa triển khai |
| MAT_SUN_FIBER | Sợi nắng | Vải | 4 | Dệt áo hỗ trợ | Khám Phá → Xưởng Rèn | Đề xuất mới | Khám Phá Hằng Ngày chưa triển khai |
| MAT_BEAST_FANG | Nanh thú | Chiến lợi phẩm | 2 | Chế dao và bùa tấn công | Tháp đề xuất → Xưởng Rèn | Đề xuất mới | — |
| MAT_GUARDIAN_CORE | Lõi hộ vệ | Chiến lợi phẩm | 4 | Chế khiên phòng thủ | Tháp đề xuất → Xưởng Rèn | Đề xuất mới | — |
| MAT_EMBER_DUST | Bụi hỏa tinh | Tinh chất | 3 | Chế trang bị thiên về tấn công | Tháp đề xuất → Xưởng Rèn | Đề xuất mới | — |
| MAT_TIDAL_ESSENCE | Tinh chất thủy triều | Tinh chất | 3 | Chế trang bị hỗ trợ | Viễn Chinh đề xuất → Xưởng Rèn | Đề xuất mới | Nguồn rơi chưa thiết kế |
| MAT_STAR_FRAGMENT | Mảnh sao rơi | Tinh chất | 5 | Chế phụ kiện hiếm | Viễn Chinh đề xuất → Xưởng Rèn | Đề xuất mới | Nguồn rơi chưa thiết kế |
| ANCIENT_RELIC | Di vật cổ | Di vật | 4 | Thành phần chế tác cổ vật | Khám Phá → Xưởng Rèn | Đề xuất mới | Khám Phá Hằng Ngày chưa triển khai |

## Tiêu hao và thức ăn (25)

| Mã | Tên | Nhóm | ★ | Công dụng | Nguồn → nơi dùng | Trạng thái | Tương lai |
|---|---|---|---:|---|---|---|---|
| FOOD | Lương khô | Thức ăn | 1 | Khẩu phần cho Hero và triển khai | Tháp, Bếp, cửa hàng → sinh tồn, Tháp | Đã có | — |
| MEDICINE | Dược liệu điều trị | Thuốc | 3 | Hồi HP và xử lý thương tích ngoài trận | Giả kim, cửa hàng → Hero | Đã có | — |
| MANA_POTION | Thuốc ma lực | Thuốc | 2 | Hồi MP | Giả kim, cửa hàng → Hero | Đã có | — |
| STRENGTH_POTION | Thuốc cường lực | Thuốc | 3 | Tăng ATK trong một trận PvE | Giả kim, cửa hàng → Hero | Đã có | — |
| TELEPORT_STONE | Đá dịch chuyển | Tiện ích | 3 | Tạo điểm thu hồi đội tại ô PvE | Cửa hàng → Tháp | Đã có | — |
| RESURRECTION_GEM_7 | Ngọc hồi sinh 7★ | Hồi sinh | 7 | Hồi sinh một Hero theo quy tắc hiện tại | Cửa hàng → Sử Điện Anh Hùng | Đã có | — |
| ROAST_CHICKEN | Gà Quay | Món ăn | 3 | Món ăn theo sở thích Hero | Cửa hàng → hệ thống thức ăn | Cần điều chỉnh | Xác nhận nguồn và hiệu quả |
| HONEY_BREAD | Bánh Mật Ong | Món ăn | 2 | Món ăn theo sở thích Hero | Cửa hàng → hệ thống thức ăn | Cần điều chỉnh | Xác nhận nguồn và hiệu quả |
| SPICED_STEW | Hầm Gia Vị | Món ăn | 3 | Món ăn theo sở thích Hero | Cửa hàng → hệ thống thức ăn | Cần điều chỉnh | Xác nhận nguồn và hiệu quả |
| MOON_CAKE | Bánh Trăng | Món ăn | 3 | Món ăn đặc biệt | Cửa hàng → hệ thống thức ăn | Cần điều chỉnh | Xác nhận điều kiện bán và hiệu quả |
| WILD_MUSHROOM | Nấm hoang | Thực phẩm | 2 | Nguyên liệu cho món ăn | Khám Phá → Bếp | Đề xuất mới | Khám Phá Hằng Ngày chưa triển khai |
| FOOD_FOREST_SOUP | Súp rừng | Món ăn | 2 | Hỗ trợ hồi phục sau chuyến đi | Bếp → Hero | Đề xuất mới | Hiệu ứng chưa có |
| FOOD_TRAVEL_BREAD | Bánh đường xa | Món ăn | 1 | Khẩu phần cho chuyến ngắn | Bếp → đội Tháp | Đề xuất mới | Công thức chưa có |
| FOOD_HERB_TEA | Trà thảo mộc | Món ăn | 2 | Hỗ trợ hồi phục tinh thần | Bếp → Hero ở căn cứ | Đề xuất mới | Hiệu ứng chưa có |
| FOOD_MINER_STEW | Canh thợ mỏ | Món ăn | 3 | Bữa ăn thiên về sức bền | Bếp → Hero ở căn cứ | Đề xuất mới | Hiệu ứng chưa có |
| FOOD_SKY_FISH | Cá nướng mây | Món ăn | 4 | Bữa ăn đặc sản Viễn Chinh | Viễn Chinh đề xuất, Bếp → Hero | Đề xuất mới | Nguyên liệu và công thức chưa có |
| FOOD_BERRY_JAM | Mứt quả rừng | Món ăn | 2 | Món ăn cải thiện tâm trạng | Khám Phá, Bếp → Hero | Đề xuất mới | Khám Phá Hằng Ngày chưa triển khai |
| FOOD_ROYAL_FEAST | Đại tiệc hoàng gia | Món ăn | 5 | Bữa tiệc hỗ trợ nhóm | Bếp → Hero ở căn cứ | Đề xuất mới | Cơ chế tiệc chưa có |
| CONS_ANTIDOTE | Thuốc giải độc | Thuốc | 2 | Giải hiệu ứng độc | Giả kim → Hero | Đề xuất mới | Trạng thái và cách dùng cần thiết kế |
| CONS_WARD_TONIC | Thuốc hộ thân | Thuốc | 3 | Hỗ trợ phòng thủ tạm thời | Giả kim → Hero trong PvE | Đề xuất mới | Hiệu ứng chưa có |
| CONS_SWIFT_TONIC | Thuốc nhanh nhẹn | Thuốc | 3 | Hỗ trợ tốc độ hành động | Giả kim → Hero trong PvE | Đề xuất mới | Hiệu ứng chưa có |
| CONS_FOCUS_TONIC | Thuốc tập trung | Thuốc | 4 | Hỗ trợ sức mạnh phép | Giả kim → Hero trong PvE | Đề xuất mới | Hiệu ứng chưa có |
| CONS_CAMP_KIT | Bộ dựng trại | Tiện ích | 3 | Tạo điểm nghỉ ngắn cho đội | Chế tạo đề xuất → Tháp | Đề xuất mới | Cơ chế dựng trại chưa có |
| CONS_TORCH | Đuốc khám phá | Tiện ích | 1 | Hỗ trợ soi đường | Chế tạo đề xuất → Khám Phá | Đề xuất mới | Khám Phá Hằng Ngày chưa triển khai |
| CONS_FIELD_RATION | Khẩu phần dã chiến | Thức ăn | 2 | Dự trữ cho hành trình | Bếp → Khám Phá | Đề xuất mới | Khám Phá Hằng Ngày chưa triển khai |

## Phát triển Hero (16)

| Mã | Tên | Nhóm | ★ | Công dụng | Nguồn → nơi dùng | Trạng thái | Tương lai |
|---|---|---|---:|---|---|---|---|
| SAMPLE_HERO_EXP_100 | Sách EXP Hero Sơ Cấp | Kinh nghiệm Hero | 2 | Tăng EXP Hero | Khu Huấn Luyện, triệu hồi, cửa hàng → Hero | Cần điều chỉnh | Tên mã và nhãn thưởng seed chưa thống nhất |
| SAMPLE_HERO_EXP_1000 | Sách EXP Hero Trung Cấp | Kinh nghiệm Hero | 3 | Tăng EXP Hero | Khu Huấn Luyện, cửa hàng → Hero | Cần điều chỉnh | Tên mã không phản ánh lượng EXP hiện tại |
| SAMPLE_HERO_EXP_10000 | Sách EXP Hero Cao Cấp | Kinh nghiệm Hero | 4 | Tăng EXP Hero | Khu Huấn Luyện, cửa hàng → Hero | Cần điều chỉnh | Tên mã không phản ánh lượng EXP hiện tại |
| SAMPLE_HERO_PROMOTION_SEAL | Ấn Thăng Bậc Hero | Đột phá | 3 | Phát triển giới hạn cấp Hero | Triệu hồi, cửa hàng → Hero | Cần điều chỉnh | Mã mẫu đang được dùng |
| SAMPLE_HERO_AWAKENING_CORE | Lõi Thức Tỉnh Hero | Thức tỉnh | 4 | Nguyên liệu thức tỉnh | Triệu hồi, cửa hàng → Hero | Cần điều chỉnh | Mã mẫu đang được dùng |
| SAMPLE_HERO_SKILL_BOOK | Sách Kỹ Năng Hero | Kỹ năng Hero | 3 | Nguyên liệu nâng kỹ năng Hero | Triệu hồi, cửa hàng → Hero | Cần điều chỉnh | Mã mẫu đang được dùng |
| CLASS_CHANGE_TOKEN | Ấn Chuyển Nghề | Chuyển nghề | 4 | Đổi nghề Hero | Cửa hàng → Đại Sảnh Ma Thuật | Đã có | — |
| HERO_TOME_TACTICS | Sổ chiến thuật | Kỹ năng Hero | 2 | Phát triển kỹ năng chiến thuật | Nhiệm vụ đề xuất → Hero | Đề xuất mới | Cơ chế sử dụng chưa có |
| HERO_TOME_GUARD | Sổ hộ vệ | Kỹ năng Hero | 3 | Phát triển kỹ năng phòng thủ | Tháp đề xuất → Hero | Đề xuất mới | Cơ chế sử dụng chưa có |
| HERO_TOME_ARCANE | Sổ huyền thuật | Kỹ năng Hero | 3 | Phát triển kỹ năng phép | Tháp đề xuất → Hero | Đề xuất mới | Cơ chế sử dụng chưa có |
| HERO_TOME_SUPPORT | Sổ trợ chiến | Kỹ năng Hero | 3 | Phát triển kỹ năng hỗ trợ | Nhiệm vụ đề xuất → Hero | Đề xuất mới | Cơ chế sử dụng chưa có |
| HERO_AWAKEN_EMBER | Lõi thức tỉnh hỏa | Thức tỉnh | 4 | Vật liệu thức tỉnh thiên hỏa | Tháp đề xuất → Hero | Đề xuất mới | Thức tỉnh theo nguyên tố chưa thiết kế |
| HERO_AWAKEN_TIDE | Lõi thức tỉnh thủy | Thức tỉnh | 4 | Vật liệu thức tỉnh thiên thủy | Viễn Chinh đề xuất → Hero | Đề xuất mới | Thức tỉnh theo nguyên tố chưa thiết kế |
| HERO_AWAKEN_WIND | Lõi thức tỉnh phong | Thức tỉnh | 4 | Vật liệu thức tỉnh thiên phong | Khám Phá → Hero | Đề xuất mới | Khám Phá Hằng Ngày chưa triển khai |
| HERO_PROMOTION_INSIGNIA | Huy hiệu đột phá | Đột phá | 5 | Hỗ trợ đột phá bậc cao | Tháp đề xuất → Hero | Đề xuất mới | Công thức đột phá chưa thiết kế |
| HERO_MEMORY_CRYSTAL | Tinh thể ký ức Hero | Phát triển Hero | 5 | Hỗ trợ phát triển chuyên sâu | Nhiệm vụ đề xuất → Hero | Đề xuất mới | Công dụng chi tiết chưa thiết kế |

## Trang bị (60)

Các món `SAMPLE_*` sau là template đã có; công dụng ghi theo vai trò chỉ số, không thay đổi chỉ số seed. Các món mới chưa có chỉ số, hiệu ứng hoặc công thức được duyệt.

| Mã | Tên | Nhóm / ô | ★ | Công dụng | Nguồn → nơi dùng | Trạng thái | Tương lai |
|---|---|---|---:|---|---|---|---|
| SAMPLE_IRON_SWORD | Thanh kiếm sắt | Tay chính | 1 | Tấn công vật lý cơ bản | Trang bị khởi đầu, rèn, cửa hàng → Hero | Cần điều chỉnh | Mã và chỉ số mẫu |
| SAMPLE_STEEL_GREATSWORD | Đại kiếm thép | Tay chính | 2 | Tấn công vật lý mạnh | Cửa hàng → Hero | Cần điều chỉnh | Mã và chỉ số mẫu |
| SAMPLE_THIEF_DAGGER | Dao găm bóng tối | Tay chính | 1 | Thiên về nhanh nhẹn | Cửa hàng → Hero | Cần điều chỉnh | Mã và chỉ số mẫu |
| SAMPLE_MAGE_WAND | Trượng ma thuật | Tay chính | 1 | Tấn công phép | Cửa hàng → Hero | Cần điều chỉnh | Mã và chỉ số mẫu |
| SAMPLE_HUNTER_BOW | Cung thợ săn | Tay chính | 1 | Tấn công chính xác | Cửa hàng → Hero | Cần điều chỉnh | Mã và chỉ số mẫu |
| EQ_MAIN_BRONZE_AXE | Rìu đồng khai phá | Tay chính | 1 | Tấn công ổn định | Rèn đề xuất → Hero | Đề xuất mới | — |
| EQ_MAIN_GUARD_SPEAR | Thương hộ vệ | Tay chính | 2 | Tấn công kèm phòng thủ | Rèn đề xuất → Hero | Đề xuất mới | — |
| EQ_MAIN_EMBER_BLADE | Kiếm hỏa tinh | Tay chính | 3 | Tấn công thiên hỏa | Rèn đề xuất → Hero | Đề xuất mới | Hiệu ứng hỏa chưa thiết kế |
| EQ_MAIN_MOON_BOW | Cung trăng non | Tay chính | 3 | Chính xác và cơ động | Rèn đề xuất → Hero | Đề xuất mới | — |
| EQ_MAIN_TIDE_STAFF | Trượng thủy triều | Tay chính | 4 | Phép hỗ trợ đồng đội | Rèn đề xuất → Hero | Đề xuất mới | Hiệu ứng hỗ trợ chưa thiết kế |
| EQ_MAIN_METEOR_HAMMER | Búa thiên thạch | Tay chính | 5 | Sát thương mạnh đổi lấy tốc độ | Rèn đề xuất → Hero | Đề xuất mới | — |
| EQ_MAIN_STAR_SCEPTER | Quyền trượng tinh tú | Tay chính | 6 | Tăng cường phép thuật | Rèn đề xuất → Hero | Đề xuất mới | — |
| EQ_MAIN_DAWN_SWORD | Kiếm bình minh | Tay chính | 7 | Cân bằng tấn công và sinh tồn | Thành tựu đề xuất → Hero | Đề xuất mới | Nguồn thưởng chưa thiết kế |
| EQ_MAIN_FOREST_DAGGER | Dao lá rừng | Tay chính | 2 | Thiên về tốc độ | Khám Phá → Hero | Đề xuất mới | Khám Phá Hằng Ngày chưa triển khai |
| SAMPLE_OAK_SHIELD | Khiên gỗ sồi | Tay phụ | 1 | Chặn đòn cơ bản | Trang bị khởi đầu, cửa hàng → Hero | Cần điều chỉnh | Mã và chỉ số mẫu |
| EQ_OFF_BRONZE_BUCKLER | Khiên tròn đồng | Tay phụ | 1 | Phòng thủ nhẹ | Rèn đề xuất → Hero | Đề xuất mới | — |
| EQ_OFF_IRON_TOWER | Khiên tháp sắt | Tay phụ | 2 | Phòng thủ cao, kém cơ động | Rèn đề xuất → Hero | Đề xuất mới | — |
| EQ_OFF_RUNIC_FOCUS | Pháp khí phù văn | Tay phụ | 3 | Hỗ trợ tấn công phép | Rèn đề xuất → Hero | Đề xuất mới | — |
| EQ_OFF_HUNTER_QUIVER | Ống tên thợ săn | Tay phụ | 2 | Hỗ trợ độ chính xác | Rèn đề xuất → Hero | Đề xuất mới | — |
| EQ_OFF_TIDE_ORB | Cầu thủy triều | Tay phụ | 4 | Hỗ trợ ma lực | Rèn đề xuất → Hero | Đề xuất mới | — |
| EQ_OFF_GUARDIAN_SHIELD | Khiên lõi hộ vệ | Tay phụ | 4 | Chuyên phòng thủ | Rèn đề xuất → Hero | Đề xuất mới | — |
| EQ_OFF_STAR_LANTERN | Đèn sao dẫn lối | Tay phụ | 5 | Hỗ trợ đội hình | Viễn Chinh đề xuất → Hero | Đề xuất mới | Hiệu ứng hỗ trợ chưa thiết kế |
| EQ_OFF_MOON_MIRROR | Gương nguyệt quang | Tay phụ | 6 | Kháng phép | Rèn đề xuất → Hero | Đề xuất mới | — |
| EQ_OFF_DAWN_AEGIS | Khiên bình minh | Tay phụ | 7 | Phòng thủ cho tuyến trước | Thành tựu đề xuất → Hero | Đề xuất mới | Nguồn thưởng chưa thiết kế |
| SAMPLE_IRON_HELM | Mũ giáp sắt | Đầu | 1 | Tăng độ bền và phòng thủ | Cửa hàng → Hero | Cần điều chỉnh | Mã và chỉ số mẫu |
| EQ_HEAD_LEATHER_CAP | Mũ da tuần tra | Đầu | 1 | Phòng thủ nhẹ | Rèn đề xuất → Hero | Đề xuất mới | — |
| EQ_HEAD_MAGE_HOOD | Mũ trùm pháp sư | Đầu | 2 | Hỗ trợ ma lực | Rèn đề xuất → Hero | Đề xuất mới | — |
| EQ_HEAD_SCOUT_HOOD | Mũ trùm trinh sát | Đầu | 2 | Hỗ trợ né tránh | Rèn đề xuất → Hero | Đề xuất mới | — |
| EQ_HEAD_STEEL_HELM | Mũ giáp thép | Đầu | 3 | Tăng sức chống chịu | Rèn đề xuất → Hero | Đề xuất mới | — |
| EQ_HEAD_RUNE_CIRCLET | Vòng trán phù văn | Đầu | 3 | Hỗ trợ phép thuật | Rèn đề xuất → Hero | Đề xuất mới | — |
| EQ_HEAD_GUARD_CROWN | Miện hộ vệ | Đầu | 4 | Hỗ trợ kháng hiệu ứng | Tháp đề xuất → Hero | Đề xuất mới | Chỉ số cần cân bằng |
| EQ_HEAD_SKY_VISOR | Mũ che trời | Đầu | 5 | Hỗ trợ độ chính xác | Viễn Chinh đề xuất → Hero | Đề xuất mới | Nguồn rơi chưa thiết kế |
| EQ_HEAD_MOON_CROWN | Vương miện nguyệt | Đầu | 6 | Hỗ trợ kháng phép | Rèn đề xuất → Hero | Đề xuất mới | — |
| EQ_HEAD_DAWN_HELM | Mũ bình minh | Đầu | 7 | Chống chịu cân bằng | Thành tựu đề xuất → Hero | Đề xuất mới | Nguồn thưởng chưa thiết kế |
| SAMPLE_LEATHER_CHEST | Giáp da hộ thân | Thân | 1 | Phòng thủ và sinh tồn | Trang bị khởi đầu, rèn, cửa hàng → Hero | Cần điều chỉnh | Mã và chỉ số mẫu |
| EQ_CHEST_LINEN_ROBE | Áo vải học giả | Thân | 1 | Hỗ trợ ma lực cơ bản | Rèn đề xuất → Hero | Đề xuất mới | — |
| EQ_CHEST_SCOUT_VEST | Áo trinh sát | Thân | 2 | Phòng thủ linh hoạt | Rèn đề xuất → Hero | Đề xuất mới | — |
| EQ_CHEST_CHAIN_MAIL | Giáp xích | Thân | 2 | Chống chịu vật lý | Rèn đề xuất → Hero | Đề xuất mới | — |
| EQ_CHEST_ARCANE_ROBE | Áo choàng huyền thuật | Thân | 3 | Phép thuật và kháng phép | Rèn đề xuất → Hero | Đề xuất mới | — |
| EQ_CHEST_GUARD_PLATE | Giáp tấm hộ vệ | Thân | 3 | Bảo vệ tuyến trước | Rèn đề xuất → Hero | Đề xuất mới | — |
| EQ_CHEST_SUN_CLOAK | Áo choàng sợi nắng | Thân | 4 | Chống chịu thiên về hỗ trợ | Rèn đề xuất → Hero | Đề xuất mới | — |
| EQ_CHEST_TIDE_COAT | Áo thủy triều | Thân | 4 | Kháng phép và sinh tồn | Viễn Chinh đề xuất → Hero | Đề xuất mới | Nguồn rơi chưa thiết kế |
| EQ_CHEST_METEOR_PLATE | Giáp thiên thạch | Thân | 5 | Chịu đòn, giảm cơ động | Rèn đề xuất → Hero | Đề xuất mới | — |
| EQ_CHEST_DAWN_ARMOR | Giáp bình minh | Thân | 7 | Cân bằng phòng thủ | Thành tựu đề xuất → Hero | Đề xuất mới | Nguồn thưởng chưa thiết kế |
| SAMPLE_WIND_BOOTS | Giày gió lốc | Chân | 1 | Tăng tốc và né tránh | Trang bị khởi đầu, cửa hàng → Hero | Cần điều chỉnh | Mã và chỉ số mẫu |
| EQ_FEET_LEATHER_BOOTS | Giày da lữ hành | Chân | 1 | Cơ động cơ bản | Rèn đề xuất → Hero | Đề xuất mới | — |
| EQ_FEET_IRON_GREAVES | Hộ chân sắt | Chân | 2 | Phòng thủ chân | Rèn đề xuất → Hero | Đề xuất mới | — |
| EQ_FEET_SCOUT_BOOTS | Giày trinh sát | Chân | 2 | Thiên về né tránh | Rèn đề xuất → Hero | Đề xuất mới | — |
| EQ_FEET_MAGE_SLIPPERS | Hài pháp sư | Chân | 3 | Hỗ trợ ma lực | Rèn đề xuất → Hero | Đề xuất mới | — |
| EQ_FEET_GUARD_GREAVES | Hộ chân hộ vệ | Chân | 3 | Giữ vững tuyến trước | Rèn đề xuất → Hero | Đề xuất mới | — |
| EQ_FEET_TIDE_BOOTS | Giày thủy triều | Chân | 4 | Cơ động và kháng phép | Viễn Chinh đề xuất → Hero | Đề xuất mới | Nguồn rơi chưa thiết kế |
| EQ_FEET_STAR_BOOTS | Giày tinh tú | Chân | 5 | Thiên về tốc độ | Rèn đề xuất → Hero | Đề xuất mới | — |
| EQ_FEET_DAWN_GREAVES | Hộ chân bình minh | Chân | 7 | Cơ động và chống chịu | Thành tựu đề xuất → Hero | Đề xuất mới | Nguồn thưởng chưa thiết kế |
| SAMPLE_SWIFT_CHARM | Bùa hộ mệnh thần tốc | Phụ kiện | 1 | Tăng tốc và chỉ số chiến đấu | Trang bị khởi đầu, rèn, cửa hàng → Hero | Cần điều chỉnh | Mã và chỉ số mẫu |
| SAMPLE_BLOODSTONE_RING | Nhẫn huyết thạch | Phụ kiện | 2 | Hỗ trợ sinh tồn và tấn công | Cửa hàng → Hero | Cần điều chỉnh | Mã và chỉ số mẫu |
| EQ_ACC_COPPER_RING | Nhẫn đồng | Phụ kiện | 1 | Chỉ số cân bằng | Rèn đề xuất → Hero | Đề xuất mới | — |
| EQ_ACC_SILVER_PENDANT | Mặt dây bạc | Phụ kiện | 3 | Kháng phép | Rèn đề xuất → Hero | Đề xuất mới | — |
| EQ_ACC_BEAST_CHARM | Bùa nanh thú | Phụ kiện | 2 | Tăng tấn công | Rèn đề xuất → Hero | Đề xuất mới | — |
| EQ_ACC_SKY_PRISM | Lăng kính bầu trời | Phụ kiện | 4 | Hỗ trợ ma lực | Viễn Chinh đề xuất → Hero | Đề xuất mới | Nguồn rơi chưa thiết kế |
| EQ_ACC_STAR_SEAL | Ấn tinh tú | Phụ kiện | 5 | Hỗ trợ vai trò pháp sư | Rèn đề xuất → Hero | Đề xuất mới | — |

## Đặc biệt (10)

| Mã | Tên | Nhóm | ★ | Công dụng | Nguồn → nơi dùng | Trạng thái | Tương lai |
|---|---|---|---:|---|---|---|---|
| SHOP_SCROLL_NORMAL | Thiên Thư thường | Triệu hồi | — | Một lượt triệu hồi thường | Cửa hàng → kho Thiên Thư loại NORMAL | Đã có | Không phải mã item kho thường |
| CRAFTING_BLUEPRINT | Bản thiết kế cổ | Bản vẽ | 4 | Mở công thức trang bị cổ | Khám Phá → Xưởng Rèn | Đề xuất mới | Khám Phá Hằng Ngày và mở công thức bằng bản vẽ chưa triển khai |
| LOST_RUNE | Phù văn thất lạc | Phù văn | 5 | Thành phần chế tạo di vật | Khám Phá → Xưởng Rèn | Đề xuất mới | Khám Phá Hằng Ngày chưa triển khai |
| SPECIAL_TOWER_TOKEN | Ấn chứng Tháp | Chứng nhận | 3 | Đổi phần thưởng cột mốc | Tháp đề xuất → đổi thưởng | Đề xuất mới | Cửa hàng đổi thưởng chưa có |
| SPECIAL_EXPLORER_BADGE | Huy hiệu khám phá | Chứng nhận | 3 | Ghi nhận thành tích khám phá | Khám Phá → đổi thưởng | Đề xuất mới | Khám Phá Hằng Ngày chưa triển khai |
| SPECIAL_SKY_COMPASS | La bàn thiên hành | Công cụ | 4 | Hỗ trợ tìm điểm Viễn Chinh | Viễn Chinh đề xuất → bản đồ thế giới | Đề xuất mới | Cơ chế tìm điểm chưa thiết kế |
| SPECIAL_FORGE_BLUEPRINT | Bản vẽ thợ rèn | Bản vẽ | 3 | Mở công thức rèn chọn lọc | Nhiệm vụ đề xuất → Xưởng Rèn | Đề xuất mới | Mở công thức bằng bản vẽ chưa có |
| SPECIAL_ALLIANCE_SEAL | Ấn liên minh | Chứng nhận | 4 | Đổi vật phẩm đóng góp | Liên Minh đề xuất → đổi thưởng liên minh | Đề xuất mới | Cửa hàng đóng góp chưa có |
| SPECIAL_FESTIVAL_LANTERN | Đèn hội nguyện | Sự kiện | 3 | Đổi phần thưởng sự kiện | Sự kiện đề xuất → đổi thưởng | Đề xuất mới | Quy tắc sự kiện chưa thiết kế |
| SPECIAL_ARCHIVE_PAGE | Trang sử anh hùng | Sưu tầm | 4 | Mở ghi chép sưu tầm | Thành tựu đề xuất → Bách khoa | Đề xuất mới | Bộ sưu tập trang sử chưa có |

## Quyết định cần duyệt trước khi triển khai

1. Chọn mục nào được đưa vào từng giai đoạn; xác nhận các nguồn, ô dùng và hiệu ứng mới có phù hợp gameplay.
2. Chốt cân bằng, giá và công thức; thiết kế cách nhận vật phẩm hiếm, tránh xem cửa hàng giá thử là cân bằng chính thức.
3. Lập bảng ánh xạ mã cũ–mới, kiểm tra kho, Hero, trang bị, thưởng, seed, công thức và dữ liệu tài khoản trước mọi thay đổi; ghi rõ xử lý `DIVINE_TEAR`, bình thể lực và ba mã rác trong pool.
4. Xác minh nội dung database thực tế và kế hoạch migration riêng. Không tự xóa tài khoản hay vật phẩm dựa trên tài liệu đề xuất này.
