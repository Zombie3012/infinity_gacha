# Godot 4 Client Backlog & Architecture Roadmap

> **Chuyển giao Kiến trúc**: Dự án chính thức dừng hoàn toàn phát triển Web UI (`packages/client`) và chuyển đổi engine phát triển Client chính thức từ Unity sang **Godot 4 (GDScript 2.0)**.
> Backend REST API và Engine Combat v2 đã hoàn thiện 100%, sẵn sàng làm máy chủ backend độc lập cho Godot Client.

---

## 1. Hero Awakening & Progression Presentation
- **Imprint Evolution (Rank S/A/B, Trait/Ability)**: Backend đã cung cấp đầy đủ API ấn ký (`imprint_definitions`, `hero_imprints`) và 6 ability hooks (`LOW_HP_EMPOWER`, `PHOENIX_REVIVE`, `CC_RESISTANCE`, `CRIT_EVASION`, `ARCANE_EMPOWER`, `ACCURACY_EMPOWER`). Godot Client triển khai giao diện khảm ấn ký, mở khóa slot theo sao và hiển thị huy hiệu ấn ký.
- **Trait Tiers**: Hiển thị thẻ đặc tính (trait card) nhận được khi thức tỉnh, so sánh chỉ số trước/sau, hiệu ứng hạt Particles2D khi thức tỉnh thành công.
- **Skill Awakening Selection**: UI cho phép người chơi chọn kỹ năng muốn thức tỉnh thay vì mặc định kỹ năng đầu tiên.
- **VFX / SFX**: Hiệu ứng chuyển động tweening, âm thanh nâng cấp và hoạt ảnh mở rộng sức mạnh.

---

## 2. Thăng Sao Tướng (Star Promotion — Pick Me Up style)
- **Backend Complete**: `GET /api/heroes/:heroId/promote-star/preview` và `POST /api/heroes/:heroId/promote-star`.
  - Quy tắc: Tướng được nâng phải đạt Max Level hiện tại ($10 \times \text{Sao}$).
  - Tiêu tốn $N$ tướng hiến tế cùng hạng $N$★.
  - Tự động tháo trang bị của tướng hiến tế trả về túi đồ và dọn dẹp slot đội hình.
  - Mở rộng ngân sách chỉ số gốc (`BASE_STAT_BUDGET`) theo sao mới và giữ nguyên tỷ lệ phân bổ archetype.
- **Godot Client Scope**:
  - Giao diện chọn tướng hiến tế (checklist fodder selection).
  - Hoạt ảnh hiến tế (sacrifice animation/particles), thẻ bài tướng phát sáng và số sao tăng từ $N$ lên $N+1$.
  - Popup so sánh các chỉ số STR/INT/STA/AGI, Max HP, ATK, DEF tăng lên vượt bậc.

---

## 3. Đấu Trường & Replay Combat v2 (Combat v2 Arena)
- **Đặc tả Combat v2**:
  - Hiển thị thanh AGI Turn Order (danh sách avatar các tướng theo thứ tự lượt đánh).
  - Thanh máu HP / năng lượng MP mượt mà (TextureProgressBar kết hợp Tween).
  - Floating Combat Text: Nhảy số sát thương vật lý (cam/đỏ), sát thương phép (lam/tím), chữ CHÍ MẠNG (to, rung camera), NÉ TRÁNH, ĐỠ ĐÒN.
  - Trình phát Timeline Replay: Đọc mảng `battleLog` trả về từ API (`/api/combat/v2/simulate`, `/api/combat/v2/session/...`, `/api/world/pvp/battles`), diễn hoạt lần lượt từng hiệp đánh chân thực.
  - Hiệu ứng hồi sinh phượng hoàng (`PHOENIX_REVIVE`), kích hoạt khiên hộ thể và hút máu lifesteal.

---

## 4. Hệ Thống Trang Bị v2 (Equipment System v2)
- **Multi-slot**: `MAIN_HAND`, `OFF_HAND`, `CHEST`, `HELMET`, `BOOTS`, `ACCESSORY`.
- Giao diện Inventory / Character Equipment Sheet:
  - Hiển thị 6 ô trang bị xung quanh nhân vật.
  - Tooltip trang bị chi tiết: chỉ số cơ bản (+STR, +INT, +STA, +AGI), chỉ số phụ (+Matk, +Mdef, +HP), chỉ số chiến đấu đặc biệt (+CritRate%, +CritDamage%, +ArmorPen%, +Lifesteal%).
  - Nút Trang bị nhanh / Tháo đồ đồng bộ tức thì với API `/api/equipment/equip` và `/api/equipment/unequip`.

---

## 5. Bản Đồ Thế Giới & PvP Lãnh Thổ (World Grid 1000x1000)
- **Bản đồ ô đất**: TileMap / TileMapLayer 2D tối ưu render ô đất, tài nguyên, quái gác cổng và thành trì của các Master khác.
- **Hành quân & Thám hiểm**: Vẽ đường mũi tên hành quân (March line), hiển thị đồng hồ đếm ngược ETA di chuyển.
- **Chiến báo PvP**: Modal xem danh sách các trận công/thủ lãnh thổ, xem lại Replay toàn bộ trận đánh PvP v2.

---

## 6. Dịch Vụ Nền Tảng & Đóng Gói (Production Services)
- Xác thực tài khoản: Đăng ký / Đăng nhập JWT Token lưu an toàn trong `user://auth.dat`.
- Tối ưu hóa đa nền tảng: PC (Windows/macOS), Mobile (Android APK / iOS).
- Âm thanh: AudioStreamPlayer cho BGM và SFX chiến đấu, mở thẻ gacha.
