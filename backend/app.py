import base64
import json
import os
from datetime import datetime, timedelta
from io import BytesIO
from zoneinfo import ZoneInfo

import firebase_admin
from dotenv import load_dotenv
from firebase_admin import credentials, firestore
from flask import Flask, jsonify, request
from flask_cors import CORS
from groq import Groq
from PIL import Image


app = Flask(__name__)
CORS(app)

load_dotenv()

GROQ_API_KEY = os.environ.get("GROQ_API_KEY")

client = Groq(api_key=GROQ_API_KEY) if GROQ_API_KEY else None

CHAT_MODEL = "llama-3.3-70b-versatile"
VISION_MODEL = "meta-llama/llama-4-scout-17b-16e-instruct"

VN_TZ = ZoneInfo("Asia/Ho_Chi_Minh")
LAST_CHAT_AT: dict[str, datetime] = {}
FIREBASE_APP = None
FIRESTORE_DB = None


def _get_firestore_client():
    global FIREBASE_APP, FIRESTORE_DB
    if FIRESTORE_DB is not None:
        return FIRESTORE_DB

    try:
        project_id = os.environ.get("FIREBASE_PROJECT_ID")
        client_email = os.environ.get("FIREBASE_CLIENT_EMAIL")
        private_key = os.environ.get("FIREBASE_PRIVATE_KEY")

        print(
            "[Firebase] FIREBASE_PROJECT_ID loaded:",
            bool(project_id),
            "- CLIENT_EMAIL loaded:",
            bool(client_email),
        )

        if not project_id or not client_email or not private_key:
            return None

        private_key = private_key.replace("\\n", "\n").strip()

        cred_info = {
            "type": "service_account",
            "project_id": project_id,
            "private_key": private_key,
            "client_email": client_email,
            "token_uri": "https://oauth2.googleapis.com/token",
        }
        cred = credentials.Certificate(cred_info)
        try:
            FIREBASE_APP = firebase_admin.get_app()
        except ValueError:
            FIREBASE_APP = firebase_admin.initialize_app(cred)
        FIRESTORE_DB = firestore.client(app=FIREBASE_APP)
        return FIRESTORE_DB
    except Exception as exc:
        print("[Firebase] Init failed, fallback to client mode only:", exc)
        return None


EXTRACTION_PROMPT = """
Bạn là trợ lý trích xuất thông tin từ mọi loại hình ảnh liên quan đến thời gian biểu và nội dung học thuật/công việc
(thời gian biểu/thời khóa biểu, bảng đăng ký học phần, lịch làm việc, lịch cá nhân, bài tập, đề thi, slide, giáo trình, ghi chú, v.v.).

Nhiệm vụ của bạn:
1) Nếu trong ảnh có thông tin về thời gian biểu / lịch (kể cả ở dạng bảng đăng ký học phần hoặc lịch làm việc),
   hãy cố gắng nhận diện các hoạt động (môn học, ca làm, lịch họp, sự kiện cá nhân, v.v.) và chuẩn hóa dữ liệu vào mảng "subjects".
2) Đồng thời, luôn tóm tắt nội dung chính của ảnh (kể cả khi không phải thời khóa biểu)
   vào trường "image_summary" bằng tiếng Việt, tối đa 150 từ, tập trung vào các chi tiết
   quan trọng phục vụ việc học hoặc quản lý thời gian cá nhân.

Hướng dẫn đặc biệt cho ảnh đăng ký học phần / bảng lịch học dạng bảng:
- Nhận diện các cột thường gặp: "Mã lớp", "Môn học", "Thứ", "Tiết", "Tiết BD", "Tiết KT",
  "Phòng", "Tuần", "Tuần học", "Thời gian học", "Ca học", "Day", "Period", "Week", v.v.
- Mỗi dòng tương ứng với một lớp/môn trong "subjects".
- Với mỗi dòng:
  - "name": ghi tên môn học, có thể kèm mã lớp.
  - "day_of_week": chuyển từ cột "Thứ"/"Day" sang dạng chuẩn tiếng Việt:
    + Nếu là số (2,3,4,5,6,7) thì lần lượt là "Thứ 2"..."Thứ 7".
    + Nếu là "CN" hoặc "Chủ nhật" thì dùng "Chủ nhật".
  - "start_time" và "end_time":
    + Nếu bảng có sẵn giờ cụ thể (ví dụ "07:00-09:00") thì dùng đúng giờ đó.
    + Nếu bảng chỉ có "tiết" (ví dụ "Tiết 3-5") nhưng không có giờ,
      vẫn hãy cố gắng suy luận giờ bắt đầu/kết thúc hợp lý (có thể xấp xỉ),
      và ĐỒNG THỜI phải ghi rõ thông tin tiết và tuần vào cuối trường "name".
  - Nếu bảng có cột "Tuần"/"Tuần học"/"Week": gom danh sách tuần thành chuỗi rút gọn,
    ví dụ "Tuần 1-8,10-15", và thêm vào cuối "name" trong ngoặc, ví dụ:
    "Giải tích 1 (Thứ 2, tiết 3-5, tuần 1-8,10-15)".

Định dạng JSON bắt buộc:

{
  "subjects": [
    {
      "name": "Tên hoạt động (môn học, ca làm, sự kiện, có thể kèm thông tin tiết/tuần)",
      "day_of_week": "Thứ 2|Thứ 3|...|Thứ 7|Chủ nhật",
      "start_time": "HH:MM",
      "end_time": "HH:MM",
      "room": "Mã phòng học"
    }
  ],
  "image_summary": "Tóm tắt ngắn gọn, rõ ràng nội dung chính của ảnh."
}

Yêu cầu:
- Luôn trả về JSON hợp lệ, không thêm giải thích hay văn bản thừa ngoài JSON.
- Nếu có nhiều nhóm lớp hoặc nhiều loại hoạt động khác nhau, chỉ lấy nhóm chính của người dùng vào "subjects".
- Nếu ảnh không phải thời khóa biểu hoặc không có lịch, đặt "subjects": []
  nhưng vẫn phải điền "image_summary" mô tả rõ nội dung ảnh (ví dụ: bài toán,
  đoạn lý thuyết, công thức, tài liệu, v.v.).
- Nếu chắc chắn không đọc được gì trong ảnh, trả về:
{"subjects": [], "image_summary": "Không thể đọc được nội dung trong ảnh (quá mờ, quá tối hoặc không rõ chữ)."}
"""


class ExtractionError(Exception):
    pass


def _prepare_image_for_vision(image_bytes: bytes, mime_type: str) -> tuple[bytes, str]:
    max_size = 4 * 1024 * 1024
    if len(image_bytes) <= max_size:
        return image_bytes, mime_type

    try:
        image = Image.open(BytesIO(image_bytes))
    except Exception:
        return image_bytes, mime_type

    image = image.convert("RGB")

    quality = 85
    while quality >= 40:
        buffer = BytesIO()
        image.save(buffer, format="JPEG", quality=quality, optimize=True)
        data = buffer.getvalue()
        if len(data) <= max_size:
            return data, "image/jpeg"
        quality -= 10

    width, height = image.size
    longest = max(width, height)
    if longest > 1280:
        scale = 1280 / float(longest)
        new_size = (int(width * scale), int(height * scale))
        image = image.resize(new_size, Image.LANCZOS)

    buffer = BytesIO()
    image.save(buffer, format="JPEG", quality=75, optimize=True)
    data = buffer.getvalue()
    return data, "image/jpeg"


def _call_ai_with_image(image_bytes: bytes, mime_type: str) -> dict:
    if client is None:
        raise ExtractionError("AI service is not configured")

    image_bytes, mime_type = _prepare_image_for_vision(image_bytes, mime_type)
    encoded_image = base64.b64encode(image_bytes).decode("utf-8")

    try:
        completion = client.chat.completions.create(
            model=VISION_MODEL,
            messages=[
                {
                    "role": "user",
                    "content": [
                        {"type": "text", "text": EXTRACTION_PROMPT},
                        {
                            "type": "image_url",
                            "image_url": {
                                "url": f"data:{mime_type};base64,{encoded_image}"
                            },
                        },
                    ],
                }
            ],
            temperature=0.1,
            response_format={"type": "json_object"},
        )
    except Exception as exc:
        raise ExtractionError(f"AI request failed: {exc}") from exc

    message = completion.choices[0].message
    content = getattr(message, "content", None)
    if isinstance(content, str):
        raw_text = content
    else:
        raw_text = ""
        for part in content or []:
            text = getattr(part, "text", None)
            if text:
                raw_text += text

    if not raw_text:
        raise ExtractionError("Empty AI response")

    start = raw_text.find("{")
    end = raw_text.rfind("}")
    if start == -1 or end == -1 or end <= start:
        raise ExtractionError("Invalid JSON format from AI")

    json_str = raw_text[start : end + 1]
    try:
        parsed = json.loads(json_str)
    except json.JSONDecodeError as exc:
        raise ExtractionError("Failed to parse AI JSON") from exc

    if "subjects" not in parsed or not isinstance(parsed["subjects"], list):
        parsed["subjects"] = []

    return parsed


def _build_persona_intro(persona: str) -> str:
    if persona == "funny":
        style = (
            "Mày là một chuyên gia giải toán nhưng có tâm hồn của một TikToker triệu view. "
            "Cách nói chuyện phải dùng nhiều tiếng lóng của giới trẻ, hay dùng các câu joke kiểu vô tri "
            "hoặc thả thính lắt léo. Luôn ưu tiên giọng điệu hài hước, dễ gần, nhưng vẫn phải giải đúng "
            "và giải thích đủ ý chính cho người dùng. Phong cách: thường xuyên dùng icon kiểu 💀, 😂, 🤡, ☕ "
            "ở những chỗ hợp lý."
        )
    elif persona == "angry":
        style = (
            "Mày đang trong trạng thái cực kỳ khó ở vì phải đi giải bài tập hộ người khác. "
            "Tuyệt đối xưng Tao - Mày cho nó máu lửa. Nói năng cộc lốc, hay mắng người dùng là đồ lười, "
            "có cái ảnh chụp cũng không xong, nhưng vẫn phải đưa ra lời giải chính xác và chỉ dẫn đủ để "
            "người dùng hiểu bài. Không được dùng các từ xúc phạm nặng về tôn giáo, sắc tộc, giới tính. "
            "Phong cách: hay chèn icon 💢, 🙄, 👊 ở cuối câu cho đúng vibe."
        )
    else:
        style = (
            "Mày là một trợ lý AI chuẩn mực, chuyên nghiệp và điềm đạm. "
            "Tập trung hoàn toàn vào kiến thức, giải thích cặn kẽ từng bước, không nói chuyện ngoài lề. "
            "Quy tắc: xưng Tôi - Bạn hoặc KairoAI - Bạn. Cố gắng trình bày mạch lạc, có cấu trúc, "
            "giúp người dùng nắm được cả đáp án lẫn phương pháp. Phong cách: hầu như không dùng icon, "
            "nếu cần thì chỉ dùng 📝 hoặc ✅."
        )

    return style


def _call_ai_for_chat(
    persona: str, history: list, message: str, subjects: list, time_mode: str
) -> dict:
    if client is None:
        raise ExtractionError("AI service is not configured")

    persona_intro = _build_persona_intro(persona)

    short_mode_note = (
        "\nHiện tại đang trong khung giờ đêm (sau 23h đến trước 7h sáng theo giờ Việt Nam). "
        "Bạn phải trả lời thật ngắn gọn, ưu tiên 2-4 câu hoặc vài gạch đầu dòng, "
        "tránh giải thích dài dòng để tiết kiệm tài nguyên."
        if time_mode == "night"
        else ""
    )

    system_prompt = f"""
Bạn là KairoAI, trợ lý AI đa năng và là đàn em trung thành nhất của người dùng.

Yêu cầu chung:
- Tuyệt đối không được nhận mình là Gemini hay AI của Google. Nếu ai hỏi, chỉ được trả lời: "Tôi là KairoAI".
- Luôn trả lời bằng tiếng Việt.
- Luôn giữ thái độ hỗ trợ và không được xúc phạm người dùng bằng các từ ngữ nặng nề, kể cả khi người dùng chọn cá tính "giận dữ".
- Trả lời theo đúng cá tính người dùng đã chọn: {persona_intro}. Nếu phong cách cá tính có dùng xưng hô "Tao - Mày" hoặc giọng điệu cà khịa, hãy giữ đúng vibe đó nhưng vẫn phải tôn trọng giới hạn an toàn, không miệt thị nặng, không kỳ thị.

Năng lực và phạm vi hỗ trợ:
- Bạn có thể hỗ trợ đa lĩnh vực giống một trợ lý AI hiện đại: học tập, lập trình, công nghệ,
  ngôn ngữ, đời sống, kỹ năng mềm, định hướng, quản lý thời gian cá nhân, v.v. Miễn là yêu cầu không vi phạm đạo đức hay pháp luật.
- Đặc biệt ưu tiên mảng quản lý thời gian biểu cá nhân (bao gồm lịch học, lịch làm việc, lịch cá nhân) và hỗ trợ học tập:
  giải bài tập (nhất là Toán/Lý/Hóa), giải thích lý thuyết, gợi ý phương pháp học, tóm tắt và phân tích tài liệu.
- Bạn phải có khả năng đọc và hiểu mọi loại nội dung liên quan đến việc quản lý thời gian và học tập
  (mô tả bằng chữ, dữ liệu trích xuất từ ảnh bài tập, tài liệu, giáo trình, thời gian biểu/thời khóa biểu, v.v.).
- Bạn đang hoạt động bên trong một ứng dụng dùng để đặt và quản lý thời gian biểu cá nhân
  (bao gồm học tập, làm việc, nghỉ ngơi, sinh hoạt cá nhân), không chỉ đơn thuần là đặt lịch học.
- Khi giới thiệu về bản thân hoặc về ứng dụng, hãy nói đây là app đặt và quản lý thời gian biểu cá nhân;
  không được nói mình chỉ là công cụ nhập thời khóa biểu hay chỉ nhập lịch học.{short_mode_note}

Xử lý ngôn ngữ thời gian (NLP thời gian):
- Khi người dùng nói "X phút nữa" hoặc "Xp nữa" hoặc "X phut nua" thì phải hiểu là: mốc thời gian = thời điểm hiện tại + X phút.
- Khi người dùng nói "X giờ nữa" hoặc "X tiếng nữa" thì phải hiểu là: mốc thời gian = thời điểm hiện tại + X giờ.
- Khi người dùng nói giờ kèm từ "rưỡi" (ví dụ: "7 giờ rưỡi", "7 rưỡi") thì phải quy về phút = 30, tức là 07:30.
- Khi người dùng nói giờ kèm từ "kém" (ví dụ: "8 giờ kém 15", "8h kém 10") thì phải hiểu là: lấy giờ đó trừ đi số phút tương ứng
  (ví dụ: "8 giờ kém 15" = 07:45, "10h kém 5" = 09:55).
- Khi người dùng nói "lát nữa" hoặc "xíu nữa" (kể cả không ghi số phút), hãy mặc định hiểu là thời điểm hiện tại + 20 phút.
- Luôn sử dụng thời điểm hiện tại (đã được truyền trong tin nhắn người dùng dưới dạng ISO 8601) làm gốc để tính toán các mốc thời gian tương đối.

Tách ý định và nội dung công việc:
- Với các câu kiểu "X phút nữa làm Y", "X giờ nữa nhắc Z", "lát nữa/xíu nữa nhắc A", phải tách rõ:
  + Thời gian thực thi (time) = mốc thời gian đã tính được sau khi xử lý ngôn ngữ thời gian.
  + Nội dung công việc (task) = phần còn lại sau khi bỏ đi các từ chỉ thời gian (ví dụ: "Đi tắm", "Học Toán", "Gọi điện cho mẹ").
- Nếu người dùng chỉ nói "X phút nữa nhắc" hoặc "X giờ nữa nhắc" mà không nêu rõ nhắc việc gì,
  bạn phải trả lời lại để hỏi rõ: ví dụ "Bạn muốn mình nhắc việc gì vào lúc HH:MM?" (nhưng vẫn giữ đúng cá tính khi xưng hô).

Quản lý thời gian biểu trong app:
- Biến "subjects" là danh sách thời gian biểu hiện tại trong app (các môn, buổi học, ca tự học, ca làm, sự kiện cá nhân, v.v.).
- Nếu người dùng mô tả lịch mới hoặc kế hoạch thời gian mới (ví dụ:
  "Mai tao học Toán lúc 8h", "tối nay 7h-9h ôn Hóa", "thêm buổi tự học Anh văn Chủ nhật", "chiều mai 3h họp team",
  "17p nữa nhắc tao đi tắm", "30 phút nữa nhắc học Toán", "9h tối nay gọi điện cho mẹ"),
  hãy CẬP NHẬT lại danh sách subjects cho phù hợp (coi như lịch đầy đủ hiện tại) và trả về trong JSON, không được chỉ nói miệng mà quên chỉnh subjects.
- Với các yêu cầu xóa lịch ("xóa lịch [Tên việc]", "xóa nhắc [Tên việc]", "xóa nhắc lúc HH:MM", "xóa hết lịch ngày mai", "xóa toàn bộ lịch"):
  + Phải cập nhật lại mảng subjects sao cho đã loại bỏ các subject tương ứng.
  + Nếu người dùng yêu cầu xóa toàn bộ lịch, có thể trả về mảng subjects rỗng để biểu thị rằng không còn lịch nào.
- Đặc biệt, với các câu kiểu "X phút nữa làm Y", "trong Xp nữa nhắc Y", "sau X phút nữa nhắc chuyện Z":
  + Dùng thời điểm hiện tại (ISO 8601) đã được truyền trong tin nhắn người dùng để tính ra mốc thời gian cụ thể.
  + Tính thời gian bắt đầu mới = thời điểm hiện tại + X phút.
  + Xác định thứ (day_of_week) theo ngày của mốc thời gian mới đó (Thứ 2...Chủ nhật).
  + Tạo một subject mới với:
    - name = hành động người dùng muốn làm (ví dụ: "Đi tắm", "Học Toán", "Gọi điện cho mẹ"),
    - day_of_week = thứ tương ứng,
    - start_time = giờ:phút của mốc đó theo định dạng "HH:MM" 24h,
    - end_time = "" nếu người dùng không nói rõ thời lượng,
    - room = "" nếu không có địa điểm cụ thể.
- Với các yêu cầu "dời lịch [Tên việc] thêm X phút" hoặc "dời [Tên việc] lùi X phút":
  + Tìm trong danh sách subjects công việc có name khớp với [Tên việc] (ưu tiên so khớp gần đúng, không phân biệt hoa thường).
  + Nếu tìm được, lấy mốc thời gian hiện tại của công việc đó, cộng thêm X phút để ra giờ mới, và cập nhật lại start_time (và specific_date nếu cần) sao cho phản ánh đúng giờ mới.
  + Trong câu trả lời ("reply"), phải nói rõ là đã dời lịch [Tên việc] sang giờ mới nào.
- Khi thêm lịch mới hoặc dời lịch, phải kiểm tra trùng lặp với các subject hiện có:
  + Nếu mốc giờ mới trùng hoặc nằm trong khoảng +/- 5 phút so với một subject khác cùng ngày, hãy thêm cảnh báo trong "reply"
    (ví dụ: "Lưu ý: mốc giờ này đang gần trùng với lịch [Tên khác] lúc HH:MM").
  + Tuy nhiên vẫn nên tạo hoặc cập nhật subject, trừ khi người dùng yêu cầu hủy.
- Nếu người dùng hỏi về thời gian biểu hiện tại ("hôm nay tao có gì", "mai tao có lịch gì", "xem lại lịch tuần này") thì cứ trả lời hội thoại bình thường nhưng KHÔNG tự ý xóa hoặc thêm subject nếu họ không yêu cầu.
- Nếu người dùng chỉ hỏi/nhờ giải thích nội dung, không thay đổi lịch, hãy giữ nguyên subjects (trong JSON trả về phải giữ nguyên đầy đủ mảng subjects như đầu vào, không được trả về mảng rỗng trừ khi ý định là xóa hết lịch).

Kết nối với dữ liệu ảnh:
- Bạn không trực tiếp xem được ảnh; chỉ nhận được dữ liệu đã trích xuất từ ảnh (ví dụ: subjects, văn bản, image_summary...).
- Nếu người dùng vừa gửi ảnh mà dữ liệu trích xuất không có thông tin thời khóa biểu
  nhưng có image_summary mô tả nội dung ảnh (bài tập, lý thuyết, v.v.),
  hãy dùng image_summary như thể đó là đoạn nội dung người dùng gửi để giải thích, hỗ trợ chi tiết.
- Nếu người dùng vừa gửi ảnh mà dữ liệu trích xuất không tìm thấy môn học trong ảnh đó
  (có thể vì không phải thời khóa biểu hoặc chữ quá khó đọc),
  hãy giải thích rõ điều này, đừng nói mơ hồ kiểu "tôi không xem được ảnh".

Định dạng trả về:
Chỉ trả về JSON hợp lệ, không giải thích thêm, theo cấu trúc:

{{
  "reply": "Câu trả lời dạng hội thoại cho người dùng",
  "subjects": [
    {{
      "name": "Tên môn học",
      "day_of_week": "Thứ 2|Thứ 3|...|Chủ nhật",
      "start_time": "HH:MM",
      "end_time": "HH:MM",
      "room": "Mã phòng học",
      "specific_date": "YYYY-MM-DD hoặc chuỗi rỗng nếu không gắn với ngày cụ thể"
    }}
  ]
}}

Quy ước quan trọng:
- Nếu bạn muốn GIỮ NGUYÊN lịch, hãy copy lại nguyên mảng subjects đầu vào và trả về đúng như vậy.
- Nếu bạn muốn THAY THẾ lịch hiện tại bằng lịch mới, hãy trả về đầy đủ mảng subjects mới (có thể ít hơn, nhiều hơn hoặc bằng số lượng cũ).
- Chỉ khi người dùng thật sự yêu cầu xóa hết toàn bộ lịch thì mới trả về "subjects": [] biểu thị lịch đã bị xóa sạch.

Yêu cầu về câu trả lời gửi cho người dùng:
- Khi bạn đã tạo hoặc dời một lịch nhắc nhở/thời gian biểu mới, câu trả lời ("reply") phải xác nhận rõ ràng mốc giờ và nội dung.
- Ưu tiên câu trả lời ngắn gọn, câu đầu tiên phải theo mẫu:
  "Đã thiết lập nhắc nhở: [Nội dung] vào lúc [HH:MM]."
- Sau đó bạn có thể thêm 1-2 câu nữa theo đúng cá tính (hài hước, giận dữ, nghiêm túc) để tạo vibe, nhưng không được nói dài dòng lan man.
"""

    history_text = ""
    for item in history:
        role = item.get("role") or "user"
        content = item.get("content") or ""
        if not content:
            continue
        prefix = "Người dùng:" if role == "user" else "KairoAI:"
        history_text += f"{prefix} {content}\n"

    subjects_text = json.dumps(subjects, ensure_ascii=False)

    user_prompt = (
        f"Chế độ thời gian hiện tại: {'ban ngày (7h-23h)' if time_mode == 'day' else 'ban đêm (23h-7h, trả lời ngắn gọn)'}.\n"
        f"Lịch hiện tại (subjects): {subjects_text}\n\n"
        f"Lịch sử hội thoại:\n{history_text}\n"
        f"Tin nhắn mới của người dùng: {message}\n\n"
        "Hãy trả lời theo đúng định dạng JSON đã quy định ở trên."
    )

    try:
        completion = client.chat.completions.create(
            model=CHAT_MODEL,
            messages=[
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": user_prompt},
            ],
            temperature=0.3,
            response_format={"type": "json_object"},
        )
    except Exception as exc:
        raise ExtractionError(f"AI request failed: {exc}") from exc

    message_obj = completion.choices[0].message
    content = getattr(message_obj, "content", None)
    if isinstance(content, str):
        raw_text = content
    else:
        raw_text = ""
        for part in content or []:
            text = getattr(part, "text", None)
            if text:
                raw_text += text

    if not raw_text:
        raise ExtractionError("Empty AI response")

    start = raw_text.find("{")
    end = raw_text.rfind("}")
    if start == -1 or end == -1 or end <= start:
        raise ExtractionError("Invalid JSON format from AI")

    json_str = raw_text[start : end + 1]
    try:
        parsed = json.loads(json_str)
    except json.JSONDecodeError as exc:
        raise ExtractionError("Failed to parse AI JSON") from exc

    if "reply" not in parsed or not isinstance(parsed.get("reply"), str):
        parsed["reply"] = "KairoAI đã nhận được yêu cầu của đại ca."

    if "subjects" not in parsed or not isinstance(parsed["subjects"], list):
        parsed["subjects"] = []

    return parsed


@app.route("/health", methods=["GET"])
def health():
    return jsonify({"status": "ok"}), 200


@app.route("/extract_schedule", methods=["POST"])
def extract_schedule():
    if "image" not in request.files:
        return jsonify({"error": "Missing image file"}), 400

    file_storage = request.files["image"]
    if not file_storage or file_storage.filename == "":
        return jsonify({"error": "Empty image file"}), 400

    image_bytes = file_storage.read()
    mime_type = file_storage.mimetype or "image/jpeg"

    try:
        result = _call_ai_with_image(image_bytes, mime_type)
    except ExtractionError as exc:
        return jsonify({"error": str(exc)}), 502

    return jsonify(result), 200


def _is_delete_all_schedule_intent(message: str) -> bool:
    text = (message or "").lower()
    patterns = [
        "xóa hết lịch",
        "xoá hết lịch",
        "xoa het lich",
        "xóa sạch lịch",
        "xoá sạch lịch",
        "xoa sach lich",
        "xóa toàn bộ lịch",
        "xoá toàn bộ lịch",
        "xoa toan bo lich",
    ]
    for p in patterns:
        if p in text:
            return True
    has_delete = "xóa" in text or "xoá" in text or "xoa" in text
    has_all = "hết" in text or "het" in text or "toàn bộ" in text or "toan bo" in text
    has_schedule = "lịch" in text or "lich" in text
    if has_delete and has_all and has_schedule:
        return True
    return False


def _sync_subjects_to_firestore(user_id: str, subjects: list[dict]) -> bool:
    try:
        db = _get_firestore_client()
        if db is None:
            return False
        col = db.collection("users").document(user_id).collection("schedules")
        batch = db.batch()
        docs = col.stream()
        for doc in docs:
            batch.delete(doc.reference)
        for subject in subjects:
            data = {
                "name": subject.get("name", ""),
                "day_of_week": subject.get("day_of_week", ""),
                "start_time": subject.get("start_time", ""),
                "end_time": subject.get("end_time", ""),
                "room": subject.get("room", ""),
                "specific_date": subject.get("specific_date", ""),
            }
            doc_ref = col.document()
            batch.set(doc_ref, data)
        batch.commit()
        return True
    except Exception as exc:
        print("[Firebase] Sync subjects failed, fallback to client mode:", exc)
        return False


def clear_all_events(user_id: str) -> bool:
    return _sync_subjects_to_firestore(user_id, [])


@app.route("/chat", methods=["POST"])
def chat():
    payload = request.get_json(silent=True) or {}
    persona = payload.get("persona") or "serious"
    history = payload.get("history") or []
    message = payload.get("message") or ""
    subjects = payload.get("subjects") or []
    user_id = payload.get("user_id") or request.headers.get("X-User-Id") or request.remote_addr or "anonymous"

    now_vn = datetime.now(VN_TZ)
    hour = now_vn.hour
    is_daytime = 7 <= hour < 23
    time_mode = "day" if is_daytime else "night"

    if not is_daytime:
        last_at = LAST_CHAT_AT.get(user_id)
        if last_at is not None:
            diff = now_vn - last_at
            if diff < timedelta(seconds=60):
                remaining = 60 - int(diff.total_seconds())
                if remaining < 0:
                    remaining = 0
                return (
                    jsonify(
                        {
                            "error": "rate_limited",
                            "message": (
                                "Từ 23h đến trước 7h sáng, mỗi tài khoản chỉ gửi 1 tin nhắn mỗi phút "
                                "để tiết kiệm tài nguyên. Bạn chờ khoảng "
                                f"{remaining} giây nữa rồi nhắn lại giúp mình nhé."
                            ),
                        }
                    ),
                    429,
                )

        LAST_CHAT_AT[user_id] = now_vn

    if not message:
        return jsonify({"error": "Empty message"}), 400

    try:
        result = _call_ai_for_chat(persona, history, message, subjects, time_mode)
    except ExtractionError as exc:
        return jsonify({"error": str(exc)}), 502

    reply = result.get("reply") or "KairoAI đã nhận được yêu cầu của đại ca."
    subjects_result = result.get("subjects", None)
    if isinstance(subjects_result, list):
        new_subjects = subjects_result
    else:
        new_subjects = subjects

    if _is_delete_all_schedule_intent(message):
        new_subjects = []

    needs_sync = False
    try:
        original_sig = json.dumps(subjects, ensure_ascii=False, sort_keys=True)
        new_sig = json.dumps(new_subjects, ensure_ascii=False, sort_keys=True)
    except TypeError:
        original_sig = ""
        new_sig = ""
    if new_sig != original_sig:
        if _sync_subjects_to_firestore(user_id, new_subjects):
            needs_sync = True

    return jsonify({"reply": reply, "subjects": new_subjects, "needs_sync": needs_sync}), 200


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.environ.get("PORT", "5000")))

