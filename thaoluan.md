Vấn đề core game
Tôi định thiết kế dạng map giống như azur lane nhưng rất lớn 10x10 - 20x20 sẽ phù hợp cho việc sử dụng nhiều đội
Khi giao chiến thì mở giao diện 3x3 đối đấu nhau, nhưng chưa thể xác định là turnbase hay thể loại nàoPhân tích Core Gameplay
Bạn đang hướng tới mô hình:

Map lớn (kiểu Azur Lane nhưng scale lên) → 10x10 đến 20x20
Sử dụng nhiều đội cùng lúc
Khi giao chiến → mở giao diện 3x3
Chưa chốt được combat là Turn-based hay thể loại nào

1. Về kích thước Map





























Kích thướcSố ôĐánh giáPhù hợp khi nào10x10100 ôVừa phải, dễ kiểm soátGame tập trung vào chiến thuật đội hình + gacha sâu12x12 – 15x15144–225 ôCân bằng tốt nhấtCó nhiều đội (4–8 đội), có không gian cơ động18x18 – 20x20324–400 ôRất lớnDễ bị trống trải, người chơi mất phương hướng nếu không có hệ thống hỗ trợ tốt
Khuyến nghị: Bắt đầu với 12x12 hoặc 15x15.

20x20 chỉ nên dùng khi đã có hệ thống fog of war, điểm chiếm đóng, hoặc nhiều lớp map (surface + underground…).
Map lớn sẽ phát huy tốt nếu:

Có nhiều đội hoạt động đồng thời
Có cơ chế “điểm phối hợp” (như bạn đang thiết kế) → khuyến khích giữ đội cố định lâu dài
Có tài nguyên / điểm chiếm / sự kiện trên map để tạo lý do di chuyển

2. Về việc dùng nhiều đội
Đây là hướng đi đúng với map lớn. Một số cách tổ chức hiệu quả:

Mỗi đội có giới hạn số hero (ví dụ 5–6 người) + điểm phối hợp riêng.
Người chơi có thể triển khai 3–6 đội cùng lúc trên map.
Mỗi đội có “vùng ảnh hưởng” hoặc “tầm hoạt động” riêng → không thể chồng chéo quá nhiều.
Khi hai đội của mình ở gần nhau → có thể hỗ trợ hoặc hợp nhất tạm thời (nhưng điểm phối hợp bị ảnh hưởng).

3. Combat 3x3 – Nên chọn thể loại nào?
Đây là phần quan trọng nhất hiện tại.
So sánh nhanh các hướng









































Thể loạiƯu điểmNhược điểmMức độ phù hợpTurn-based (Classic)Dễ cân bằng, thể hiện kỹ năng rõ, hợp gacha sâuChậm, dễ nhàm nếu map lớn phải đánh nhiều trậnCaoTurn-based + Action Order (kiểu Honkai Star Rail / FE)Nhanh hơn classic, vẫn có chiều sâuCần thiết kế gauge tốtRất caoReal-time Auto (kiểu Azur Lane)Mượt, hợp map lớn, ít thao tácDễ bị “set and forget”, khó thể hiện điểm phối hợpTrung bìnhReal-time có Pause + Chỉ huyVừa tự động vừa có kiểm soátKhó cân bằng, tốn công làmTrung bình-CaoHybrid (Auto mặc định + có thể can thiệp)Linh hoạtPhức tạp khi thiết kếCao nếu làm tốt
Đề xuất theo hướng của bạn
Vì bạn đang có:

Hệ thống điểm phối hợp (càng đánh cùng nhau càng mạnh)
Hero mang tính “sống” và có thể chết vĩnh viễn
Map lớn cần nhiều đội

→ Nên chọn Turn-based có Action Gauge (kiểu Star Rail / Persona / Fire Emblem Engage) là hướng ổn định và dễ phát huy điểm mạnh nhất.
Lý do:

Dễ thể hiện buff từ điểm phối hợp (tăng tốc độ, tăng sát thương khi đứng cạnh đồng đội…).
Mỗi trận 3x3 không kéo quá dài.
Người chơi vẫn cảm thấy có quyết định quan trọng thay vì chỉ nhìn auto.
Phù hợp với việc một số hero “hiểu ý” nhau nhờ điểm phối hợp cao.

Gợi ý cụ thể cho Combat 3x3

Sân đấu cố định 3 hàng × 3 cột (hoặc 3x4 nếu muốn rộng hơn một chút).
Hero có vị trí đứng (tiền/trung/hậu) ảnh hưởng đến skill và điểm phối hợp.
Điểm phối hợp có thể cho thêm hiệu ứng vị trí (ví dụ 2 hero có điểm cao đứng cạnh nhau → giảm sát thương nhận vào hoặc tăng tốc độ hành động).
Có thể thêm cơ chế “Liên kết” khi điểm phối hợp ≥ 80: cho phép 1 lần/trận kích hoạt skill kết hợp.


Câu hỏi để chốt hướng:

Bạn muốn cảm giác combat nghiêng về chiến thuật từng lượt (Turn-based) hay nhịp độ nhanh, ít thao tác (Auto/Real-time)?
Map lớn chủ yếu để chiếm đóng / khám phá hay để điều quân đánh nhau liên tục?
Người chơi có được phép tạm dừng và ra lệnh trong combat không?

Bạn trả lời 3 ý trên, mình sẽ chốt giúp một bộ khung core rõ ràng hơn (map size + số đội + combat type + cách điểm phối hợp tác động vào trận đánh).Master- player sẽ không được thao tác trong trận nhưng sẽ được ra chiến thuật ví dụ như hero nào sẽ ưu tiên làm gì, hoặc combo phối hợp trước khi giao chiến.
Map lớn để khám phá tài nguyên, và điều quân liên tục.
Một khi pve diễn ra master chỉ có thể đợi kết thúcĐã rõ hướng Core rồi.
Tóm tắt quyết định hiện tại của bạn:

Master không thao tác trong trận.
Chỉ được thiết lập chiến thuật trước trận (ưu tiên mục tiêu, combo, vị trí, hành vi…).
Map lớn dùng để khám phá tài nguyên + điều quân liên tục.
Khi PvE bắt đầu → Master chỉ việc chờ kết quả.

Đây là mô hình Strategic Command + Auto Execution. Rất hợp với hệ thống điểm phối hợp và cảm giác “nuôi hero” của Pick Me Up.
1. Combat nên đi theo hướng nào?
Vì Master không can thiệp trong trận, có 2 hướng khả thi:


























HướngMô tảƯu điểmNhược điểmĐộ phù hợpA. Pure Auto (Azur Lane style)Hero tự đánh theo AI + chiến thuật đã setNhanh, mượt, dễ làm map lớnDễ nhàm, khó thể hiện chiều sâu chiến thuậtTrung bìnhB. Auto có Logic chiến thuật sâu (Khuyến nghị)Hero thực hiện theo bộ quy tắc ưu tiên + combo đã thiết lậpVẫn có chiều sâu, điểm phối hợp phát huy tốtCần thiết kế AI/behavior tốtCao
Nên chọn hướng B.
Lý do:

Bạn đã có điểm phối hợp. Nếu combat chỉ là auto thuần túy thì điểm này gần như vô nghĩa. Cần để điểm phối hợp ảnh hưởng rõ đến cách hero hành xử với nhau (tự động bảo vệ, ưu tiên skill kết hợp, đứng vị trí hỗ trợ…).
2. Hệ thống Chiến thuật trước trận (Pre-battle Strategy)
Đây sẽ là phần “não” của người chơi. Gợi ý cấu trúc:
Các lớp chiến thuật Master có thể set:

Ưu tiên mục tiêu (Target Priority)
Đánh healer trước / Đánh DPS cao nhất / Đánh hero đang thấp máu / Bảo vệ đồng đội yếu nhất…

Hành vi cá nhân (Individual Behavior)
Aggressive / Balanced / Defensive / Support-focused
Có thể gắn với điểm phối hợp (hero có điểm cao với nhau sẽ tự động ưu tiên hỗ trợ lẫn nhau)

Combo / Liên kết (Coordination Combo)
Khi 2–3 hero đạt điểm phối hợp cao → mở khóa “Combo đã đăng ký”
Ví dụ: Hero A dùng skill → tự động kích hoạt skill của Hero B trong cùng lượt logic

Vị trí đứng (Formation)
Vẫn giữ 3x3 hoặc 3x4
Vị trí ảnh hưởng đến việc nhận sát thương và khả năng hỗ trợ

Điều kiện rút lui / Hy sinh (nếu muốn hardcore hơn)
Cho phép set “nếu máu dưới X% thì cố giữ mạng” hoặc “sẵn sàng hy sinh để bảo vệ core”


3. Map lớn + Điều quân
Vì map dùng để khám phá + điều quân liên tục, nên thiết kế theo hướng:

Map chia thành vùng (region), mỗi vùng có tài nguyên, sự kiện, nguy hiểm khác nhau.
Mỗi đội có thời gian di chuyển giữa các ô (không phải click là đến ngay).
Có thể triển khai nhiều đội cùng lúc, nhưng phải quản lý:
Độ mệt mỏi / Morale
Điểm phối hợp (đội đánh nhiều cùng nhau thì điểm tăng)
Rủi ro bị phục kích khi đang di chuyển


Kích thước map đề xuất điều chỉnh:

Giai đoạn đầu: 12x12
Về sau mở rộng lên 15x15 hoặc có nhiều tầng map
20x20 chỉ nên dùng khi đã có fog of war + hệ thống thông tin trinh sát tốt

4. Tóm tắt hướng Core nên chốt

































Thành phầnHướng đề xuấtMap12x12 → 15x15, khám phá + điều quânSố đội4–8 đội hoạt động đồng thờiCombatAuto có chiều sâu chiến thuật (không thao tác trong trận)Tương tác của MasterChỉ set chiến thuật + formation + combo trước trậnĐiểm phối hợpẢnh hưởng mạnh đến AI hành vi và mở khóa comboCảm giác chungNgười chơi là chỉ huy cấp cao, không phải người cầm tay đánh