# Giả kim, công nghệ và vật phẩm tiêu hao PvE

## Công thức và nghiên cứu

Đại Sảnh Ma Thuật sẵn sàng cho phép nghiên cứu tức thì. Tiến độ lưu theo Master, không mất khi phá hoặc xây lại Đại Sảnh.

| Công nghệ | Điều kiện | Bạc | Dược liệu 1★ |
|---|---|---:|---:|
| Nền tảng giả kim | Có Đại Sảnh | 1.000 | 5 |
| Dược học hồi phục | Nền tảng giả kim | 2.000 | 10 |
| Tinh chế ma lực | Nền tảng giả kim | 2.000 | 10 |
| Dược học cường lực | Nền tảng giả kim | 2.000 | 10 |

Ba nhánh sau nền tảng độc lập nhau. Mỗi công thức đã mở tiêu 3 dược liệu 1★ và 100 bạc để chế một viên; mỗi lệnh chế 1–99 viên. Thông số tập trung trong `alchemy-rules.ts`.

| Thuốc | Sao | Hiệu lực |
|---|---:|---|
| MEDICINE | 3★ | Ngoài trận: hồi đầy HP, xóa thương tích, hoàn tất điều trị hiện tại; không hồi sinh |
| MANA_POTION | 2★ | Hồi 50% MP tối đa cho Hero dùng thuốc; không vượt trần |
| STRENGTH_POTION | 3★ | Tăng 20% ATK trong một trận PvE; dùng ngoài trận sẽ dành cho trận kế tiếp; không tăng MATK và không cộng dồn |

Dược liệu có catalog 1–7★, bản đầu chỉ rơi `ALCHEMY_HERB_1`. Map mới dùng phiên bản khám phá 3, thay một phần điểm tài nguyên bằng dược liệu. Map phiên bản 2 đã lưu giữ nguyên địa hình/tài nguyên; công trình chưa mở của map cũ vẫn sinh tài nguyên theo luật cũ. Dungeon hằng ngày chưa triển khai. Theo quy tắc cửa hàng thử nghiệm hiện tại, dược liệu và hai thuốc mới cũng có tại Thương Thuyền với giá 1 bạc.

## Năm ô tiêu hao

Trong **Đội hình & chiến thuật**, chọn Hero và mở **Túi tiêu hao • 5 ô**. Mỗi ô chứa một loại thuốc với 1–4 viên; cùng loại có thể xuất hiện ở nhiều ô. Bản nháp chưa trừ kho. Lưu đội xác nhận cấu hình; triển khai chuyển lượng đã chọn từ kho vào túi trong cùng giao dịch với chi phí lương thực. Không đủ hàng thì toàn bộ triển khai hoàn tác.

Hero chỉ dùng vật phẩm trong túi của mình khi triển khai. Trên map, mở **Vật phẩm đội đã chọn** để dùng ngoài trận. Hero chưa triển khai có thể dùng thuốc từ kho tại Đại Sảnh. Không dùng cho Hero tử trận hoặc vô hiệu hóa.

- Thu hồi hoặc hoàn thành tầng: trả lượng chưa dùng của Hero sống về kho và làm trống túi.
- Tử trận: lượng chưa dùng thành đồ rơi ở đúng map/khu vực/ô. Đội khác tới ô sẽ nhặt vào kho một lần; map hiển thị biểu tượng túi ở ô đã khám phá.
- Đồ rơi thuộc lần chạy/map đó, không tự chuyển sang tầng mới hoặc hoàn lại khi hồi sinh Hero. Reset dev không tự nhận đồ rơi cũ.
- Auto: cấu hình ngưỡng HP để dùng MEDICINE ngoài trận, ngưỡng MP để dùng thuốc mana và bật/tắt thuốc cường lực. Ngưỡng 0 tắt tự dùng. MEDICINE không được dùng trong trận.

## Combat tự động và thủ công

Chọn chế độ trước khi triển khai. Combat giữ lượt theo AGI, phục kích, MP, hồi chiêu, mục tiêu và kỹ năng của Combat v2.

Đội thủ công có cửa sổ 10 giây để mở trận từ danh sách chiến báo. Trong trận đang xem, Hero tới lượt có 10 giây để chọn đánh thường/kỹ năng và mục tiêu. Dùng thuốc không tốn lượt, không kéo dài thời hạn; mỗi lượt Hero chỉ dùng tối đa hai loại khác nhau, mỗi loại một viên. Server kiểm tra kỹ năng, MP, hồi chiêu, mục tiêu, số thuốc và khóa lượt cũ.

Rời màn điều khiển sẽ cho AI tiếp tục ngay. Hết 10 giây hoặc mất kết nối, AI hoàn tất trận theo chiến thuật đã lưu. Chỉ một trận được điều khiển: mở một trận sẽ cho các trận thủ công khác tự đánh; đội khác gặp địch trong khi đang xem trận cũng tự đánh. Map và đội khác tiếp tục hoạt động.

Server lưu snapshot đầu trận, seed riêng, lịch sử lệnh và hạn lượt. Engine phát lại cùng prefix quyết định để tiếp tục một cách xác định; client không gửi seed/kết quả. Trận chỉ quyết toán khi kết thúc; thuốc, Hero, thưởng, đồ rơi và mục tiêu cùng giao dịch. Hoàn thành mục tiêu chốt các trận còn chờ thành hòa theo trạng thái hiện tại, lưu lượng thuốc đã dùng và thu hồi đội sống; không bỏ mất hoặc nhân đôi vật phẩm.

Các hạn lượt nằm trong dòng thời gian server cùng di chuyển đội/quái. Prototype xử lý thời gian đã trôi khi có đọc/lệnh API, không cần tiến trình nền. Replay ghi riêng sự kiện `ITEM`, MP sau dùng và kết quả combat.

## API

Các lệnh POST dưới đây yêu cầu `Idempotency-Key`; cùng key và cùng nội dung trả lại kết quả cũ, đổi nội dung với key cũ bị từ chối. Kho và phí được cập nhật dưới khóa Master; chi phí bạc có sổ giao dịch.

| API | Nội dung |
|---|---|
| GET `/api/alchemy` | Công nghệ, công thức, kho, cấu hình túi, định hướng Bến Thiên Hành |
| POST `/api/alchemy/research` | `{code}`: một trong bốn mã `ALCHEMY_*` |
| POST `/api/alchemy/craft` | `{code, quantity}`: code là mã thuốc |
| POST `/api/alchemy/configure` | `{heroId, config}`; config có `slots[5]`, `autoHpBelow`, `autoManaBelow`, `autoStrength` |
| POST `/api/alchemy/use` | `{heroId, itemId, slotIndex?}`: ngoài trận; Hero triển khai bắt buộc dùng đúng ô |
| POST `/api/pve/consumables/use` | Cùng nội dung dùng ngoài trận; dành cho client map có lưu lệnh retry |
| POST `/api/pve/battles/:id/action` | `{watching:true/false}` hoặc `{turnKey, action:'BASIC'/'SKILL', skillCode?, targetId?}` hoặc `{turnKey,itemId}` |
| GET `/api/pve/battles/:id` | Trận đang chờ: `live`, `deadline`, report có `pending`; trận xong: report và settlement |

Lưu đội hỗ trợ thêm `loadouts` theo Hero và `plan.battleMode` (`AUTO`/`MANUAL`, mặc định `AUTO`). `/api/pve/state` trả túi đang giữ, trạng thái `FIGHTING`, `lastBattleId` và đồ rơi đã khám phá. `pending.skills` chỉ liệt kê kỹ năng hiện đủ MP/hồi chiêu; `pending.key` xác định lượt. Deadline là Unix millisecond do server cấp.

## Bến Thiên Hành và kiểm chứng

**Bến Thiên Hành** là tên đã chọn cho hướng công trình chế tạo phương tiện. Mốc định hướng đạt khi hoàn thành tầng 25; API dùng `planned: true` và `milestoneReached`. Chưa tạo công trình, phương tiện hoặc bản đồ thế giới RTS. Các nhánh sản xuất/hậu cần khác và chuyển đổi nguyên liệu để thiết kế sau.

Kiểm tra có mục tiêu: `http.alchemy.test.mjs`, engine Combat v2, sinh map PvE và hồi quy combat/map/thu hồi. Godot: `scripts/test-godot-magic-hall.mjs`, `scripts/test-godot-pve-consumables.mjs`, scene `pve_ui_test.tscn`. Các runner mạng tạo tài khoản thử rồi dọn dữ liệu. Đặt `GODOT_BIN` tới engine nếu chưa có trong PATH. Không chạy full suite hoặc `npm run verify` khi chưa được yêu cầu; headless chưa thay thế chơi thử bằng cửa sổ tương tác.
