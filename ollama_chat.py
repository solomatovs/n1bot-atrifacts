#!/usr/bin/env python3
"""
Удобный CLI-клиент для LLM с поддержкой tool calling.

Поддерживаемые провайдеры:
- ollama   — нативный /api/chat (по умолчанию http://localhost:11434)
- openai   — OpenAI-совместимый /v1/chat/completions (OpenRouter, LM Studio,
             vLLM, LiteLLM-прокси, сам OpenAI и т.п.)

API-ключи берутся ТОЛЬКО из переменных окружения:
  OPENROUTER_API_KEY, OPENAI_API_KEY и т.п.
Можно явно через --api-key, но это небезопасно (попадёт в history shell).

Примеры:
    # Ollama (по умолчанию)
    python ollama_chat.py

    # OpenRouter с ключом из окружения
    export OPENROUTER_API_KEY="sk-or-v1-..."
    python ollama_chat.py --preset openrouter -m anthropic/claude-3.5-sonnet

    # Один вопрос:
    python ollama_chat.py --preset openrouter -m openai/gpt-4o-mini \\
        -q "сколько будет 2+2"
"""

import argparse
import inspect
import json
import os
import re
import subprocess
import sys
from pathlib import Path
from typing import Any, Callable

import requests


# ─────────────────────────────────────────────────────────────────────────────
# Реестр инструментов
# ─────────────────────────────────────────────────────────────────────────────

TOOLS_REGISTRY: dict[str, dict] = {}


def tool(func: Callable) -> Callable:
    """Декоратор: регистрирует функцию как tool для модели."""
    sig = inspect.signature(func)
    doc = (func.__doc__ or "").strip()

    type_map = {str: "string", int: "integer", float: "number", bool: "boolean"}
    properties = {}
    required = []

    for name, param in sig.parameters.items():
        py_type = param.annotation if param.annotation != inspect.Parameter.empty else str
        json_type = type_map.get(py_type, "string")
        properties[name] = {"type": json_type, "description": f"Параметр {name}"}
        if param.default == inspect.Parameter.empty:
            required.append(name)

    schema = {
        "type": "function",
        "function": {
            "name": func.__name__,
            "description": doc or f"Функция {func.__name__}",
            "parameters": {
                "type": "object",
                "properties": properties,
                "required": required,
            },
        },
    }

    TOOLS_REGISTRY[func.__name__] = {"func": func, "schema": schema}
    return func


# ─────────────────────────────────────────────────────────────────────────────
# Примеры инструментов
# ─────────────────────────────────────────────────────────────────────────────

@tool
def read_file(path: str) -> str:
    """Прочитать содержимое текстового файла. Принимает путь к файлу."""
    try:
        content = Path(path).read_text(encoding="utf-8")
        if len(content) > 10000:
            return content[:10000] + f"\n\n[...обрезано, всего {len(content)} символов]"
        return content
    except FileNotFoundError:
        return f"ОШИБКА: файл не найден: {path}"
    except Exception as e:
        return f"ОШИБКА чтения: {e}"


@tool
def list_dir(path: str = ".") -> str:
    """Показать список файлов и папок в директории."""
    try:
        entries = sorted(Path(path).iterdir())
        lines = []
        for e in entries:
            kind = "DIR " if e.is_dir() else "FILE"
            lines.append(f"{kind}  {e.name}")
        return "\n".join(lines) if lines else "(пусто)"
    except Exception as e:
        return f"ОШИБКА: {e}"


@tool
def grep(pattern: str, path: str = ".") -> str:
    """Найти строки с заданным паттерном в файлах рекурсивно."""
    try:
        result = subprocess.run(
            ["grep", "-rn", "--include=*", pattern, path],
            capture_output=True, text=True, timeout=10,
        )
        out = result.stdout.strip()
        if not out:
            return "Совпадений не найдено"
        lines = out.splitlines()
        if len(lines) > 50:
            return "\n".join(lines[:50]) + f"\n\n[...ещё {len(lines)-50} совпадений]"
        return out
    except Exception as e:
        return f"ОШИБКА: {e}"


@tool
def create_todo_list(content: str) -> str:
    """Сохранить план задач. Принимает текст плана как одну строку."""
    Path("todo.txt").write_text(content, encoding="utf-8")
    items = len([line for line in content.splitlines() if line.strip()])
    return json.dumps({"status": "ok", "saved_to": "todo.txt", "items": items}, ensure_ascii=False)


# ─────────────────────────────────────────────────────────────────────────────
# Провайдеры
# ─────────────────────────────────────────────────────────────────────────────

class Provider:
    name = "base"

    def __init__(self, host: str, api_key: str | None = None, extra_headers: dict | None = None):
        self.host = host.rstrip("/")
        self.api_key = api_key
        self.extra_headers = extra_headers or {}

    def endpoint(self) -> str:
        raise NotImplementedError

    def headers(self) -> dict:
        h = {"Content-Type": "application/json"}
        if self.api_key:
            h["Authorization"] = f"Bearer {self.api_key}"
        h.update(self.extra_headers)
        return h

    def build_payload(self, model, messages, tools):
        raise NotImplementedError

    def parse_response(self, data):
        raise NotImplementedError


class OllamaProvider(Provider):
    name = "ollama"

    def endpoint(self):
        return f"{self.host}/api/chat"

    def build_payload(self, model, messages, tools):
        payload = {"model": model, "stream": False, "messages": messages}
        if tools:
            payload["tools"] = tools
        return payload

    def parse_response(self, data):
        return data.get("message", {})


class OpenAIProvider(Provider):
    """OpenAI-совместимый: OpenRouter, LiteLLM, LM Studio, vLLM, сам OpenAI."""
    name = "openai"

    def endpoint(self):
        # хост может быть и с /v1, и без — поддерживаем оба варианта
        if self.host.endswith("/v1"):
            return f"{self.host}/chat/completions"
        return f"{self.host}/v1/chat/completions"

    def build_payload(self, model, messages, tools):
        payload = {"model": model, "stream": False, "messages": messages}
        if tools:
            payload["tools"] = tools
        return payload

    def parse_response(self, data):
        choices = data.get("choices") or []
        if not choices:
            return {"role": "assistant", "content": ""}
        return choices[0].get("message", {})


PROVIDERS = {"ollama": OllamaProvider, "openai": OpenAIProvider}


# ─────────────────────────────────────────────────────────────────────────────
# Клиент
# ─────────────────────────────────────────────────────────────────────────────

class Chat:
    def __init__(
        self,
        provider: Provider,
        model: str,
        system: str | None = None,
        use_tools: bool = True,
        debug: bool = False,
        max_iterations: int = 10,
        timeout: int = 300,
    ):
        self.provider = provider
        self.model = model
        self.use_tools = use_tools
        self.debug = debug
        self.max_iterations = max_iterations
        self.timeout = timeout

        self.messages: list[dict] = []
        if system:
            self.messages.append({"role": "system", "content": system})

    def _log(self, label: str, payload: Any) -> None:
        if not self.debug:
            return
        print(f"\n\033[90m── {label} ──\033[0m", file=sys.stderr)
        if isinstance(payload, (dict, list)):
            print(json.dumps(payload, ensure_ascii=False, indent=2), file=sys.stderr)
        else:
            print(payload, file=sys.stderr)

    def _post(self, payload: dict) -> dict:
        url = self.provider.endpoint()
        headers = self.provider.headers()
        # В дебаге показываем заголовки без api-ключа
        if self.debug:
            safe_headers = {**headers, "Authorization": "Bearer ***"} if "Authorization" in headers else headers
            self._log(f"REQUEST → {url}", {"headers": safe_headers, "body": payload})

        r = requests.post(url, json=payload, headers=headers, timeout=self.timeout)
        if not r.ok:
            print(f"\033[31mHTTP {r.status_code}\033[0m: {r.text[:500]}", file=sys.stderr)
            r.raise_for_status()
        data = r.json()
        self._log("RESPONSE", data)
        return data

    def _tools_payload(self):
        if not self.use_tools or not TOOLS_REGISTRY:
            return None
        return [t["schema"] for t in TOOLS_REGISTRY.values()]

    def ask(self, user_text: str) -> str:
        self.messages.append({"role": "user", "content": user_text})

        for _ in range(self.max_iterations):
            payload = self.provider.build_payload(
                self.model, self.messages, self._tools_payload()
            )
            data = self._post(payload)
            msg = self.provider.parse_response(data)
            self.messages.append(msg)

            tool_calls = msg.get("tool_calls") or []
            if not tool_calls:
                return msg.get("content") or ""

            for call in tool_calls:
                self._handle_tool_call(call)

        return f"[Достигнут лимит итераций ({self.max_iterations})]"

    def _handle_tool_call(self, call: dict) -> None:
        func_info = call.get("function", {})
        name = func_info.get("name", "")
        args = func_info.get("arguments", {})
        call_id = call.get("id", "")

        if isinstance(args, str):
            try:
                args = json.loads(args)
            except json.JSONDecodeError:
                args = {}

        if self.debug:
            print(f"\033[36m→ tool: {name}({args})\033[0m", file=sys.stderr)

        if name not in TOOLS_REGISTRY:
            result = f"ОШИБКА: инструмент '{name}' не зарегистрирован. Доступны: {list(TOOLS_REGISTRY)}"
        else:
            try:
                result = TOOLS_REGISTRY[name]["func"](**args)
            except TypeError as e:
                result = f"ОШИБКА аргументов: {e}"
            except Exception as e:
                result = f"ОШИБКА выполнения: {e}"

        if not isinstance(result, str):
            result = json.dumps(result, ensure_ascii=False)

        if self.debug:
            preview = result if len(result) < 200 else result[:200] + "..."
            print(f"\033[32m← {preview}\033[0m", file=sys.stderr)

        self.messages.append({
            "role": "tool",
            "tool_call_id": call_id,
            "name": name,
            "content": result,
        })

    def reset(self, keep_system: bool = True) -> None:
        if keep_system and self.messages and self.messages[0]["role"] == "system":
            self.messages = self.messages[:1]
        else:
            self.messages = []

    def save(self, path: str) -> None:
        Path(path).write_text(
            json.dumps(self.messages, ensure_ascii=False, indent=2),
            encoding="utf-8",
        )

    def load(self, path: str) -> None:
        self.messages = json.loads(Path(path).read_text(encoding="utf-8"))

    def show_history(self) -> None:
        for i, m in enumerate(self.messages):
            role = m["role"]
            content = m.get("content") or ""
            tool_calls = m.get("tool_calls")
            preview = content[:120] + ("..." if len(content) > 120 else "")
            print(f"[{i}] \033[1m{role}\033[0m: {preview}")
            if tool_calls:
                for tc in tool_calls:
                    fn = tc.get("function", {})
                    print(f"     \033[36m→ {fn.get('name')}({fn.get('arguments')})\033[0m")


# ─────────────────────────────────────────────────────────────────────────────
# CLI
# ─────────────────────────────────────────────────────────────────────────────

HELP_TEXT = """
Команды:
  /help              — эта справка
  /reset             — очистить историю (system остаётся)
  /history           — показать историю
  /save <file>       — сохранить историю в JSON
  /load <file>       — загрузить историю
  /model <name>      — сменить модель
  /tools             — список инструментов
  /debug             — переключить debug-режим
  /system <text>     — задать новый system-промпт (сбрасывает историю)
  /quit, /exit       — выход
"""

PRESETS = {
    "ollama": {
        "provider": "ollama",
        "host": "http://localhost:11434",
        "api_key_env": None,
        "model": "qwen3:8b",
    },
    "ollama-docker": {
        "provider": "ollama",
        "host": "http://172.18.0.2:11434",
        "api_key_env": None,
        "model": "qwen3:8b",
    },
    "openrouter": {
        "provider": "openai",
        "host": "https://openrouter.ai/api/v1",
        "api_key_env": "OPENROUTER_API_KEY",
        "model": "anthropic/claude-3.5-sonnet",
    },
    "openai": {
        "provider": "openai",
        "host": "https://api.openai.com/v1",
        "api_key_env": "OPENAI_API_KEY",
        "model": "gpt-4o-mini",
    },
}


def interactive(chat: Chat) -> None:
    print(f"\033[1m{chat.provider.name}\033[0m  model=\033[33m{chat.model}\033[0m  "
          f"host={chat.provider.host}  "
          f"tools={'on' if chat.use_tools else 'off'}  "
          f"debug={'on' if chat.debug else 'off'}")
    print("Введи /help для справки, /quit для выхода.\n")

    while True:
        try:
            line = input("\033[1m>\033[0m ").strip()
        except (EOFError, KeyboardInterrupt):
            print()
            break

        if not line:
            continue
        if line in ("/quit", "/exit"):
            break
        if line == "/help":
            print(HELP_TEXT); continue
        if line == "/reset":
            chat.reset(); print("История очищена."); continue
        if line == "/history":
            chat.show_history(); continue
        if line == "/tools":
            for name, t in TOOLS_REGISTRY.items():
                print(f"  {name}: {t['schema']['function']['description']}")
            continue
        if line == "/debug":
            chat.debug = not chat.debug; print(f"debug = {chat.debug}"); continue
        m = re.match(r"/save\s+(.+)", line)
        if m: chat.save(m.group(1)); print(f"Сохранено в {m.group(1)}"); continue
        m = re.match(r"/load\s+(.+)", line)
        if m: chat.load(m.group(1)); print(f"Загружено ({len(chat.messages)} сообщений)"); continue
        m = re.match(r"/model\s+(.+)", line)
        if m: chat.model = m.group(1).strip(); print(f"model = {chat.model}"); continue
        m = re.match(r"/system\s+(.+)", line, re.DOTALL)
        if m:
            chat.messages = [{"role": "system", "content": m.group(1).strip()}]
            print("System-промпт обновлён, история сброшена."); continue

        try:
            answer = chat.ask(line)
            print(f"\n\033[1m<\033[0m {answer}\n")
        except requests.HTTPError as e:
            print(f"\033[31mHTTP ошибка: {e}\033[0m")
        except Exception as e:
            print(f"\033[31mОшибка: {e}\033[0m")


def main() -> None:
    p = argparse.ArgumentParser(description="CLI-клиент для LLM с tool calling.")
    p.add_argument("--preset", choices=PRESETS.keys(),
                   default="ollama",
                   help="Готовый пресет (по умолчанию ollama)")
    p.add_argument("--provider", choices=PROVIDERS.keys(),
                   help="Переопределить провайдера")
    p.add_argument("--host", help="Переопределить URL хоста")
    p.add_argument("-m", "--model", help="Имя модели")
    p.add_argument("--api-key-env", help="Имя переменной окружения с API-ключом")
    p.add_argument("--api-key", help="API-ключ напрямую (НЕБЕЗОПАСНО)")
    p.add_argument("-s", "--system",
                   default="Ты ассистент по документации. Отвечай по-русски. "
                           "Используй доступные инструменты для поиска информации в файлах.")
    p.add_argument("--no-tools", action="store_true")
    p.add_argument("-d", "--debug", action="store_true")
    p.add_argument("-q", "--query", help="Один вопрос и выход")
    p.add_argument("--header", action="append", default=[],
                   help="Дополнительный заголовок 'Key: Value' (можно несколько)")
    args = p.parse_args()

    preset = PRESETS[args.preset]
    provider_name = args.provider or preset["provider"]
    host = args.host or preset["host"]
    model = args.model or preset["model"]
    api_key_env = args.api_key_env or preset.get("api_key_env")

    api_key = args.api_key
    if not api_key and api_key_env:
        api_key = os.getenv(api_key_env)
        if not api_key:
            print(f"\033[31mОшибка: переменная {api_key_env} не задана.\033[0m", file=sys.stderr)
            print(f"Выполни: export {api_key_env}='твой-ключ'", file=sys.stderr)
            sys.exit(1)

    extra_headers = {}
    for h in args.header:
        if ":" not in h:
            print(f"Пропускаю некорректный заголовок: {h}"); continue
        k, v = h.split(":", 1)
        extra_headers[k.strip()] = v.strip()

    # OpenRouter любит видеть эти заголовки для статистики (необязательно)
    if "openrouter" in host:
        extra_headers.setdefault("HTTP-Referer", "http://localhost")
        extra_headers.setdefault("X-Title", "llm-chat-cli")

    provider = PROVIDERS[provider_name](host=host, api_key=api_key, extra_headers=extra_headers)

    chat = Chat(
        provider=provider,
        model=model,
        system=args.system,
        use_tools=not args.no_tools,
        debug=args.debug,
    )

    if args.query:
        print(chat.ask(args.query))
    else:
        interactive(chat)


if __name__ == "__main__":
    main()
