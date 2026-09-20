"""SVG アイコン (images/memoma3_icon.svg) を PNG / ICO に変換するスクリプト。

生成物:
  - web/icons/Icon-192.png
  - web/icons/Icon-512.png
  - web/icons/Icon-maskable-192.png
  - web/icons/Icon-maskable-512.png
  - web/favicon.png
  - windows/runner/resources/app_icon.ico

マスク可能アイコン (maskable) は、OS が円形・ドロップ形などにクロップしても
内容が切れないよう、中央 80% のセーフゾーンに収めるため余白を確保する。
"""

import os
import subprocess
import sys

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SVG_PATH = os.path.join(ROOT, "images", "memoma3_icon.svg")

# ヘッドレスレンダリングに使うブラウザ（Windows 標準の Edge / Chrome）。
_CHROME_CANDIDATES = [
    r"C:\Program Files\Google\Chrome\Application\chrome.exe",
    r"C:\Program Files (x86)\Google\Chrome\Application\chrome.exe",
    r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe",
    r"C:\Program Files\Microsoft\Edge\Application\msedge.exe",
]


def _find_browser() -> str:
    for p in _CHROME_CANDIDATES:
        if os.path.exists(p):
            return p
    raise RuntimeError("Chrome / Edge が見つかりません")


def render(size: int, background: str = "#ffffff") -> Image.Image:
    """SVG を指定サイズ (px) の RGBA PNG 画像としてレンダリングする。

    ヘッドレスブラウザで SVG を固定サイズで描画し、スクリーンショットする。
    [background] はレンダリング時の背景色（CSS 色）。
    - "#ffffff" 等: その色で背景を埋める（Web 用アイコンなど）。
    - "transparent": 背景を透過にする（Android ランチャーアイコンなど）。
      この場合 Chrome の --default-background-color も透明にする。
    """
    browser = _find_browser()
    transparent = background == "transparent"

    if transparent:
        bg_css = "background:transparent"
    else:
        bg_css = f"background:{background}"

    svg_url = "file:///" + SVG_PATH.replace("\\", "/")
    html = (
        "<!doctype html><html><head><meta charset='utf-8'>"
        "<style>html,body{margin:0;padding:0;width:%dpx;height:%dpx;"
        "%s;overflow:hidden}"
        "img{width:%dpx;height:%dpx;display:block}</style></head>"
        "<body><img src='%s'></body></html>"
    ) % (size, size, bg_css, size, size, svg_url)

    tmp_html = os.path.join(ROOT, "tools", "_tmp_icon.html")
    tmp_png = os.path.join(ROOT, "tools", "_tmp_icon.png")
    with open(tmp_html, "w", encoding="utf-8") as f:
        f.write(html)

    cmd = [
        browser,
        "--headless=new",
        "--disable-gpu",
        "--hide-scrollbars",
        "--force-device-scale-factor=1",
        "--virtual-time-budget=3000",
        f"--window-size={size},{size}",
        f"--screenshot={tmp_png}",
        "file:///" + tmp_html.replace("\\", "/"),
    ]
    # 透過背景の場合、Chrome のデフォルト背景色を透明（ARGB 00000000）にする。
    if transparent:
        cmd.append("--default-background-color=00000000")

    subprocess.run(cmd, check=True, capture_output=True)

    img = Image.open(tmp_png).convert("RGBA")
    for tmp in (tmp_html, tmp_png):
        if os.path.exists(tmp):
            os.remove(tmp)
    return img


def save_maskable(img: Image.Image, path: str) -> None:
    """マスク可能アイコンとして保存する。

    中央 80% のセーフゾーンに収めるため、元画像を 80% に縮小して
    中央配置し、周囲を白で埋める。
    """
    canvas = Image.new("RGBA", img.size, (255, 255, 255, 255))
    inner = int(img.size[0] * 0.8)
    resized = img.resize((inner, inner), Image.LANCZOS)
    offset = (img.size[0] - inner) // 2
    canvas.paste(resized, (offset, offset), resized)
    canvas.save(path, "PNG")


def main() -> int:
    if not os.path.exists(SVG_PATH):
        print(f"SVG not found: {SVG_PATH}")
        return 1

    web_icons = os.path.join(ROOT, "web", "icons")
    os.makedirs(web_icons, exist_ok=True)

    # 通常アイコン
    for size in (192, 512):
        img = render(size)
        out = os.path.join(web_icons, f"Icon-{size}.png")
        img.save(out, "PNG")
        print(f"wrote {out}")

    # マスク可能アイコン（セーフゾーン確保）
    for size in (192, 512):
        img = render(size)
        out = os.path.join(web_icons, f"Icon-maskable-{size}.png")
        save_maskable(img, out)
        print(f"wrote {out}")

    # favicon
    favicon = render(64)
    favicon_path = os.path.join(ROOT, "web", "favicon.png")
    favicon.save(favicon_path, "PNG")
    print(f"wrote {favicon_path}")

    # Windows ICO（複数サイズ）
    # 背景は透過にする（タスクバー/タイトルバーでダーク・ライト両対応）。
    ico_sizes = [16, 24, 32, 48, 64, 128, 256]
    base = render(256, background="transparent")
    ico_path = os.path.join(ROOT, "windows", "runner", "resources", "app_icon.ico")
    os.makedirs(os.path.dirname(ico_path), exist_ok=True)
    base.save(
        ico_path,
        "ICO",
        sizes=[(s, s) for s in ico_sizes],
    )
    print(f"wrote {ico_path}")

    # Android ランチャーアイコン（mipmap）
    # 背景は透過色にする（SVG の背景矩形が透過のため、レンダリング時も
    # 背景を透明にして透過を維持する）。
    android_mipmaps = {
        "mdpi": 48,
        "hdpi": 72,
        "xhdpi": 96,
        "xxhdpi": 144,
        "xxxhdpi": 192,
    }
    for density, size in android_mipmaps.items():
        img = render(size, background="transparent")
        out_dir = os.path.join(
            ROOT, "android", "app", "src", "main", "res", f"mipmap-{density}"
        )
        os.makedirs(out_dir, exist_ok=True)
        out = os.path.join(out_dir, "ic_launcher.png")
        img.save(out, "PNG")
        print(f"wrote {out}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
