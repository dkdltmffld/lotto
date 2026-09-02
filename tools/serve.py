#!/usr/bin/env python3
"""웹 빌드 로컬 테스트 서버.

Godot 웹 export(build/web/index.html)는 file://로 못 열고 HTTP로 서빙해야 한다.
이 스크립트는 정적 서버 + 올바른 MIME(.wasm 등) + COOP/COEP 헤더를 제공한다.

사용:
    python tools/serve.py            # build/web 을 8000 포트로, 브라우저 자동 오픈
    python tools/serve.py -p 9000    # 포트 지정
    python tools/serve.py -d build/web --no-open

종료: Ctrl+C

참고:
- 현재 export는 thread_support=false(단일 스레드)라 COOP/COEP가 필수는 아니지만,
  Godot 권장 설정이고 추후 스레드 켤 때를 대비해 켜둔다. 동일 출처 리소스라 무해.
"""
import argparse
import http.server
import os
import socketserver
import webbrowser

ENTRY = "index.html"  # export_presets.cfg 의 export_path 파일명과 일치


class Handler(http.server.SimpleHTTPRequestHandler):
    extensions_map = {
        **http.server.SimpleHTTPRequestHandler.extensions_map,
        ".js": "text/javascript",
        ".mjs": "text/javascript",
        ".wasm": "application/wasm",
        ".pck": "application/octet-stream",
        ".json": "application/json",
        ".html": "text/html",
    }

    def end_headers(self):
        # 크로스 오리진 격리 (스레드/SharedArrayBuffer 대비, 단일 스레드엔 무해)
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        # 캐시 끄기 — 새 빌드가 바로 반영되도록
        self.send_header("Cache-Control", "no-store")
        super().end_headers()


def main() -> None:
    ap = argparse.ArgumentParser(description="Godot 웹 빌드 로컬 테스트 서버")
    ap.add_argument("-p", "--port", type=int, default=8000)
    ap.add_argument("-d", "--dir", default="build/web", help="서빙할 폴더 (기본 build/web)")
    ap.add_argument("--no-open", action="store_true", help="브라우저 자동 오픈 안 함")
    args = ap.parse_args()

    # 스크립트 위치 기준 프로젝트 루트로 이동 (어디서 실행하든 동일 동작)
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    serve_dir = os.path.join(root, args.dir)
    if not os.path.isdir(serve_dir):
        raise SystemExit(f"폴더 없음: {serve_dir}\n먼저 웹 빌드를 하세요 (tools/build_web.ps1).")

    os.chdir(serve_dir)
    url = f"http://localhost:{args.port}/{ENTRY}"

    socketserver.TCPServer.allow_reuse_address = True
    with socketserver.TCPServer(("127.0.0.1", args.port), Handler) as httpd:
        print(f"서빙: {serve_dir}")
        print(f"열기: {url}")
        print("종료: Ctrl+C")
        if not args.no_open and os.path.isfile(ENTRY):
            webbrowser.open(url)
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            print("\n서버 종료")


if __name__ == "__main__":
    main()
