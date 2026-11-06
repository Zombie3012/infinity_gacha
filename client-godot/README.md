# Infinite Gacha — Godot 4 Client (Isometric 3D Architecture)

Client phát triển chính thức cho tựa game **Infinite Gacha** trên nền tảng **Godot Engine 4.3+ (GDScript 2.0)**.
Sử dụng kiến trúc **Isometric 3D Xuyên Suốt + Dynamic Action Camera** cho cả khu vực Phòng chờ / Căn cứ (Base) và Đấu trường / Hầm ngục (PvE Combat v2).

---

## 1. Yêu cầu & Cài đặt
- **Godot Engine**: Phiên bản Godot 4.3 trở lên (Standard version, không cần .NET / Mono). Tải tại: [https://godotengine.org/download](https://godotengine.org/download).
- **Backend Server**: Đang chạy tại `http://localhost:3000` (khởi động bằng `npm run dev:server` tại root monorepo).

---

## 2. Hướng dẫn Mở & Chạy dự án
1. Khởi động **Godot Engine**.
2. Chọn **Import** (Nhập dự án) và trỏ tới thư mục `f:/infiniti_gacha/client-godot`.
3. Chọn file `project.godot` và bấm **Import & Edit**.
4. Bấm phím **F5** (hoặc nút Play ở góc trên bên phải) để chạy game.

---

## 3. Cấu trúc Thư mục & Kiến trúc Isometric 3D
```
client-godot/
├── project.godot                              # File cấu hình dự án Godot (1280x720, Autoloads)
├── scripts/
│   ├── camera/
│   │   └── isometric_camera_rig.gd            # Camera Isometric 3D (-35.264°, 45°) + Zoom/Pan/Shake
│   ├── actors/
│   │   └── unit_actor_3d.gd                   # Prefab Nhân vật 3D (Wander, Work, Injured, Dragged & Combat v2)
│   ├── base/
│   │   └── base_plot_3d.gd                    # Ô đất 3D (6 Khu x 3 Ô = 18 Ô) + Mesh công trình theo loại/cấp
│   ├── network/
│   │   └── api_client.gd                      # HTTPRequest Singleton kết nối REST API Backend
│   ├── state/
│   │   └── game_state.gd                      # Singleton quản lý dữ liệu Master, Base, Kho vật liệu, Heroes
│   ├── core/
│   │   └── event_bus.gd                       # Event Bus phát tín hiệu toàn cục
│   └── constants/
│       └── game_constants.gd                  # Enums & bảng công thức (Star max level, fodder count)
└── scenes/
    ├── common/
    │   ├── isometric_camera_rig.tscn          # Scene Camera Isometric 3D tái sử dụng
    │   └── unit_actor_3d.tscn                 # Scene Nhân vật 3D (Speech Bubble + Nameplate + Collider)
    ├── base/
    │   ├── base_plot_3d.tscn                  # Scene Ô đất / Công trình 3D có Raycast Collider
    │   ├── isometric_base_3d.gd               # Logic Sảnh Chờ 3D: 18 Ô đất, Kéo-thả Tướng Pick Me Up, Inspector
    │   └── isometric_base_3d.tscn             # Scene Căn cứ Isometric 3D (Phòng chờ chính)
    ├── pve/
    │   ├── isometric_pve_arena_3d.gd          # Trình phát Timeline Combat v2 3D + Dynamic Camera
    │   └── isometric_pve_arena_3d.tscn        # Scene Đấu trường & Hầm ngục PvE Isometric 3D
    ├── heroes/
    │   ├── hero_roster.gd                     # Logic Doanh trại, xem chỉ số v2 & Thăng sao Pick Me Up
    │   └── hero_roster.tscn                   # Scene Quản lý tướng & Nghi thức Thăng sao
    ├── auth/
    │   ├── login_screen.gd                    # Logic Đăng nhập / Đăng ký
    │   └── login_screen.tscn                  # Giao diện Đăng nhập
    └── hub/
        ├── main_hub.gd                        # Menu quản lý nhanh
        └── main_hub.tscn                      # Giao diện Menu Sảnh
```

---

## 4. Điểm nổi bật của Giải pháp Isometric 3D (Phương án 1)
- **Tái sử dụng 100% tài nguyên 3D (`UnitActor3D`)**:
  - Ở **Base (`isometric_base_3d.tscn`)**: Các Hero của người chơi chạy ở chế độ `BASE_WANDER`, đi dạo sinh động quanh Đài Triệu Hồi, Doanh Trại và Cổng Tháp.
  - Ở **PvE (`isometric_pve_arena_3d.tscn`)**: Chính các `UnitActor3D` đó chuyển sang chế độ `PVE_COMBAT`, xếp đội hình Tiền vệ / Hậu vệ ở góc Dưới-Trái đối đầu Quái/Boss ở góc Trên-Phải.
- **Dynamic Action Camera (`IsometricCameraRig`)**:
  - Giữ góc nhìn chiến thuật Isometric chuẩn (`Orthogonal`, Pitch $-35.264^\circ$, Yaw $45^\circ$).
  - Tự động **Zoom cận cảnh & nghiêng góc máy** mượt bằng `Tween` khi Hero tung **Skill**, nổ **Chí mạng (`CRIT`)**, hoặc kích hoạt **Phượng Hoàng Tái Sinh (`PHOENIX_REVIVE`)**, kèm hiệu ứng rung chấn (`shake`).
