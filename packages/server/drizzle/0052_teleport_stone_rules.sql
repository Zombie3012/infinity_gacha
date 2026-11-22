-- Custom SQL migration file, put your code below! --
UPDATE shop_items SET description = 'Tạo điểm thu hồi trên tầng thường, cho phép thoát truy đuổi; không dùng ở tầng cấm thu hồi.'
WHERE code = 'TELEPORT_STONE'
  AND description = 'Tạo điểm thu hồi tổ đội trên map PvE, kể cả tầng cấm thu hồi tự do.';
