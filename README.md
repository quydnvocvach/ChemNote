# ChemNote Pro v3.0.0 — Ứng Dụng Ghi Chú Hóa Học Cho Huawei MatePad 11.5"S & Android

**ChemNote Pro v3.0.0** kết hợp trải nghiệm viết tay **Huawei Notes × GoodNotes 6** với bộ công cụ chuyên sâu cho sinh viên Hóa học, tối ưu đặc biệt cho **Huawei MatePad 11.5"S (144Hz PaperMatte, 3:2) + Huawei M-Pencil 3 (NearLink)**, hỗ trợ **Cập nhật tự động (OTA PWA)** và **Đồng bộ Google Drive không cần GMS**.

---

## Các Cách Cài Đặt Lên Huawei MatePad 11.5"S

### 1. Cài đặt & Tự động cập nhật (OTA) qua GitHub Pages (Khuyên dùng nhất)
Phiên bản trên **GitHub Pages (HTTPS)** giúp bạn:
- Cài **1 chạm** thành ứng dụng độc lập ngoài màn hình chính MatePad (`standalone` toàn màn hình, chạy offline 100%).
- **Tự động báo cập nhật OTA** ngay trong app (*"Đã có phiên bản ChemNote mới — Cập nhật ngay"*) mỗi khi có tính năng mới, không cần cắm cáp hay cài lại!
- **Đồng bộ Google Drive thật** hoạt động trực tiếp trên HTTPS không cần Google Play Services (GMS).

**Cách cài đặt trực tiếp (chỉ mất 10 giây):**
1. Mở địa chỉ **`https://quydnvocvach.github.io/ChemNote/`** trên trình duyệt Brave / Huawei Browser / Chrome của MatePad 11.5"S.
2. Chạm biểu tượng **Cài ứng dụng** trên thanh địa chỉ (hoặc menu `⋮` → **Thêm vào màn hình chính**).
3. **Cấu hình Đồng bộ Google Drive (OAuth 2.0):** Trong Google Cloud Console → *Authorized JavaScript origins*, nhập đúng: **`https://quydnvocvach.github.io`**.

*(Dành cho chủ kho mã nguồn `https://github.com/quydnvocvach/ChemNote`: vào **Settings → Pages → Source: GitHub Actions** 1 lần duy nhất để tự động triển khai từ `.github/workflows/deploy-pages.yml`.)*

---

### 2. Cài nhanh qua Wi-Fi nội bộ (Không cần GitHub, không cần cáp USB)
1. Nhấp đúp chạy **`Chay_Server_Cai_Qua_WiFi.bat`** trên máy tính Windows.
2. Mở trình duyệt Brave / Huawei Browser / Chrome trên MatePad 11.5"S (cùng mạng Wi-Fi), nhập địa chỉ hiện trên màn hình (ví dụ **`http://192.168.0.111:8080/`**).
3. Chạm biểu tượng **Cài ứng dụng** trên thanh địa chỉ để ghim ChemNote Pro v3.0.0 ra màn hình chính.

---

### 3. Dùng 1 File Độc Lập (Không cần mạng) & Build File APK Gốc
- **1-File Portable Offline:** Gửi duy nhất tệp **`ChemNote_MatePad_AllInOne.html`** sang MatePad qua Huawei Share / Zalo / Drive / USB và mở trực tiếp để dùng offline 100%.
- **Build APK Native (Flutter 144Hz + M-Pencil 3):**
  - *Tự động trên đám mây:* Vào **[GitHub Actions (`https://github.com/quydnvocvach/ChemNote/actions`)](https://github.com/quydnvocvach/ChemNote/actions)** → chọn workflow **`.github/workflows/build-apk.yml`** → tải về **`ChemNote-MatePad-11.5s-release.apk`** ở mục Artifacts.
  - *Build trực tiếp trên Windows:* Nhấp đúp chạy **`Build_APK_Va_Cai_Len_MatePad.bat`** (tự động kiểm tra Flutter SDK và cài thẳng qua cáp USB nếu MatePad đang kết nối).

---

## Điểm Nổi Bật Trên ChemNote Pro v3.0.0

- **Viết tay 144Hz M-Pencil 3 không trễ, không đen nền:** Kiến trúc tách lớp canvas tiêu chuẩn (không dùng `desynchronized` gây đen nền GPU MatePad), phân tách tuyệt đối `pointerId` / `pointerType === 'pen'` giúp tì lòng bàn tay viết liên tục không bị mất nét.
- **Tách biệt `Khoá lòng bàn tay` & `Chế độ chỉ đọc (Read-Only)`:** Bật `Khoá lòng bàn tay` để viết bằng bút và cuộn trang bằng 1 ngón tay; bật `Chỉ đọc` khi ôn bài.
- **Ghi âm bài giảng đồng bộ nét viết (Audio Note Replay):** Ghi âm trực tiếp trong trang ghi chú bằng `MediaRecorder` (lưu trong IndexedDB), phát lại kèm tốc độ `1× / 1.5× / 2×` và làm nổi bật từng nét viết đúng thời điểm giảng bài.
- **Lưu trữ IndexedDB & Ảo hóa trang (`IntersectionObserver`):** Chịu tải mượt mà sổ tay nhiều chục trang kèm ảnh độ phân giải gốc, PDF bài giảng nhiều trang mà không tràn RAM/VRAM.
- **Chèn & Cắt ảnh độ phân giải gốc:** Popover `Ảnh gần đây`, chọn/di chuyển/cắt ảnh không vỡ nét (cắt chữ nhật siêu nhỏ xuống `8×8 px` hoặc cắt tự do), viết trực tiếp lên trên ảnh khi chọn bút.
- **10 mẫu giấy học thuật thẩm mỹ:** Kẻ ngang ruy-băng xanh (`sageRibbon`), Ô ly tiêu đề pastel (`pastelGrid`), Giấy cổ điển viền khung (`vintageCream`), Chia 2 cột bài tập (`twoColumnStudy`), Lưới lục giác Hóa hữu cơ (`hexagonal`), Cornell, Kẻ ngang, Ô ly, Chấm dot, Giấy trắng.
- **Bộ công cụ Sinh viên Hóa học:** Bảng tuần hoàn 118 nguyên tố, Máy tính phân tử khối, **Cân bằng phương trình phân tử & phương trình ion** (`MnO4- + Fe2+ + H+ -> Mn2+ + Fe3+ + H2O`), Sổ tay công thức & 21 khuôn vẽ dụng cụ/cấu trúc Hóa học.
- **Đồng bộ Google Drive REST v3 (GMS-free) & Sao lưu `.chemnote.json`:** Tự động đồng bộ 2 chiều theo mốc `updatedAt`, khóa sổ bằng mã PIN mã hóa SHA-256 (có dự phòng thuần JS khi chạy trên Wi-Fi HTTP).
