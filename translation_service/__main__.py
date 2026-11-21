import argparse
import logging
import os

from waitress import serve

from .app import create_app


def main() -> None:
    parser = argparse.ArgumentParser(description="校园双语办事卡翻译服务")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8000)
    args = parser.parse_args()

    logging.basicConfig(level=logging.INFO)
    if not os.environ.get("ZHIPUAI_API_KEY", "").strip():
        logging.getLogger(__name__).warning(
            "ZHIPUAI_API_KEY is missing. Translation requests will return HTTP 502."
        )
    serve(create_app(), host=args.host, port=args.port)


if __name__ == "__main__":
    main()
