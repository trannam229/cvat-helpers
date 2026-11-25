# CVAT helpers cho gán nhãn cuboid 3D

Bản giao diện CVAT **v2.84.0** có thêm các công cụ hỗ trợ gán nhãn point cloud. Cài một lần bằng file nhấp đúp trên **Windows** và **macOS**; installer tự cài CVAT nếu máy chưa có.

## Tính năng

| Tính năng | Cách dùng |
|---|---|
| **Highlight camera đang nhìn** | Xoay khung Perspective: ảnh camera (cam01…cam09) cùng hướng nhìn có header chuyển xanh đậm. Góc từng camera nằm trong `camera-headings.ts` (0° = đầu xe theo trục −Y của LiDAR); sửa bảng này cho đúng bộ camera của dữ liệu. |
| **Di chuyển tịnh tiến trong Perspective** | Chọn (hoặc rê chuột vào) cuboid: hiện 3 mũi tên X/Y/Z và 3 mặt phẳng. Kéo mũi tên để đi theo một trục, kéo mặt phẳng để trượt. Undo/Save như sửa thường. |
| **Chế độ bay (kiểu FPS)** | Phím **Z**: chuột để nhìn (giữ chuột trái nếu trình duyệt không khoá con trỏ), **WASD** di chuyển, **Q/E** xuống/lên, **Shift** nhanh gấp 4. Tâm ngắm chọn cuboid. **Z/Esc** thoát, camera giữ nguyên chỗ. Đổi phím trong Settings → Shortcuts. |
| **Chỉ giữ points quanh cuboid** | Nút nổi trên cuboid đang chọn: ẩn mọi point ngoài cuboid + 1 m ở cả 4 khung nhìn; bấm lại để hiện tất cả. |
| **Đặt xuống mặt đất** | Nút nổi trên cuboid: tìm mặt đất bằng RANSAC + bình phương tối thiểu rồi hạ đáy cuboid chạm đất (giữ nguyên góc xoay và kích thước). |
| **Copy tất cả cuboid sang frame khác** | Nút **Copy** ở thanh công cụ trái → nhập frame đích. Copy mọi cuboid của frame hiện tại (track thành shape). Không kiểm tra trùng. |
| **Độ sáng và kích thước point** | **Appearance** → **Point brightness** (chỉ thấy trên point cloud có `rgb`) và **Point size** (to hơn khi point trắng nhỏ khó nhìn). Trình duyệt ghi nhớ. |

## Cài đặt

Cần **Docker Desktop** ([tải ở đây](https://www.docker.com/products/docker-desktop/)), nên cấp từ 8 GB RAM. Trên Windows, Docker Desktop chạy bằng WSL 2 (mặc định).

1. Trên GitHub bấm **Code → Download ZIP**, giải nén.
2. Nhấp đúp:
   - **Windows**: `Install-Windows.bat`. Nếu hiện "Windows protected your PC" → **More info** → **Run anyway**.
   - **macOS**: `Install-macOS.command`. Lần đầu macOS chặn file tải về: nhấp chuột phải → **Open** → **Open** (macOS 15 trở lên: **System Settings → Privacy & Security → Open Anyway**).
3. Cửa sổ dòng lệnh hiện tiến trình; xong thì trình duyệt mở `http://localhost:8080`.

Hoặc dán một lệnh:

```bash
curl -fsSL https://raw.githubusercontent.com/trannam229/cvat-helpers/main/scripts/install.sh | bash
```

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/trannam229/cvat-helpers/main/scripts/install.ps1).TrimStart([char]0xFEFF)))
```

### Installer làm gì

1. Kiểm tra Docker, mở Docker Desktop nếu chưa chạy.
2. Tìm CVAT đang chạy (container `cvat_server`) và giữ nguyên mọi file Compose nó đang dùng (ví dụ serverless cho AI Tools).
   - Có CVAT khác **v2.84.0**: hỏi trước khi cài vì giao diện được build cho 2.84.0.
   - Chưa có CVAT: tải các file Compose của CVAT v2.84.0 vào `~/cvat` (Windows: `%USERPROFILE%\cvat`), khởi động và hỏi tạo tài khoản admin.
3. Tải image `ghcr.io/trannam229/cvat-helpers` và ghi `docker-compose.helpers.yml` cạnh `docker-compose.yml` của CVAT, chỉ đổi image của `cvat_ui`. Dữ liệu, tài khoản và các dịch vụ khác giữ nguyên.

Chạy lại installer để cập nhật bản mới. Đổi thư mục cài CVAT mới bằng biến `CVAT_DIR`.

Nếu sau này tự chạy `docker compose up`, thêm `-f docker-compose.helpers.yml` vào cuối để giữ giao diện helpers.

Máy Mac chip M: image `cvat/server` của CVAT chỉ có bản amd64, Docker Desktop chạy giả lập (chậm hơn một chút). Image helpers có cả amd64 và arm64.

## Gỡ

Nhấp đúp `Uninstall-Windows.bat` / `Uninstall-macOS.command` (hoặc `install.sh uninstall`): `cvat_ui` quay về `cvat/ui:v2.84.0`, dữ liệu giữ nguyên.

## Build từ mã nguồn

```bash
git clone --branch v2.84.0 --depth 1 https://github.com/cvat-ai/cvat.git
cd cvat
git apply ../cvat-helpers/patches/cvat-v2.84.0.patch
docker build -f Dockerfile.ui -t cvat-helpers-ui .
```

Bước webpack cần nhiều RAM: nếu Docker Desktop chỉ có 8 GB, tắt các hàm AI (nuclio) trong lúc build. Đặt `CVAT_HELPERS_IMAGE=cvat-helpers-ui` khi chạy installer để dùng image vừa build.

Phát hành bản mới: sửa patch, đổi tag image trong `scripts/install.sh` và `scripts/install.ps1`, rồi push tag cùng tên (ví dụ `v2.84.0-helpers.2`). GitHub Actions build và đẩy image lên GHCR.

## Giấy phép

MIT. Patch sửa [CVAT](https://github.com/cvat-ai/cvat) (MIT).
