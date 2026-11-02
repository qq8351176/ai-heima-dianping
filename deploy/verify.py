"""Local deployment smoke checks; no paid model calls or order writes."""
import json
import os
from pathlib import Path
import re
import socket
import subprocess
from datetime import datetime, timedelta, timezone
from urllib.error import HTTPError
from urllib.parse import urlencode
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parents[1]
BASE = "http://127.0.0.1:8090"
checks = []


def check(name, condition):
    assert condition, name
    checks.append(name)
    print("PASS:", name)


def http(path, body=None, token=None):
    headers = {"Accept": "application/json, text/event-stream"}
    if token:
        headers["authorization"] = token
    if body is not None:
        headers["Content-Type"] = "application/json"
    request = Request(BASE + path, data=json.dumps(body).encode() if body is not None else None, headers=headers)
    with urlopen(request, timeout=15) as response:
        return response.status, response.read()


def api(path, body=None, token=None):
    status, data = http("/api" + path, body, token)
    result = json.loads(data)
    assert status == 200 and result.get("success"), path + ": " + str(result.get("errorMsg"))
    return result.get("data")


redis_config = (ROOT / "runtime/redis/redis.conf").read_text(encoding="utf-8")
redis_password = re.search(r"(?m)^requirepass (.+)$", redis_config).group(1).strip()


def redis(*args):
    def read(stream):
        line = stream.readline()
        kind, value = line[:1], line[1:-2]
        if kind == b"-":
            raise RuntimeError(value.decode())
        if kind == b"$":
            size = int(value)
            if size < 0:
                return None
            data = stream.read(size)
            stream.read(2)
            return data.decode()
        if kind == b"*":
            return [read(stream) for _ in range(int(value))]
        if kind == b":":
            return int(value)
        if kind == b"+":
            return value.decode()
        raise RuntimeError("Invalid Redis response")

    with socket.create_connection(("127.0.0.1", 6380), timeout=5) as connection:
        stream = connection.makefile("rb")
        for command in [("AUTH", redis_password), args]:
            parts = [str(arg).encode() for arg in command]
            connection.sendall(b"*%d\r\n" % len(parts) + b"".join(b"$%d\r\n" % len(p) + p + b"\r\n" for p in parts))
            result = read(stream)
        return result


check("Redis authenticated PING", redis("PING") == "PONG")
status, page = http("/")
check("Frontend HTML and UTF-8 title", status == 200 and "黑马点评" in page.decode("utf-8"))
types = api("/shop-type/list")
check("Shop categories through Nginx", len(types) == 8)
shop = api("/shop/1")
check("Shop detail and Java date serialization", shop["id"] == 1 and bool(shop.get("createTime")))
check("Shop list", len(api("/shop/of/type?typeId=1&current=1")) > 0)
check("Nearby shops / Redis GEO", len(api("/shop/of/type?" + urlencode({"typeId": 1, "current": 1, "x": shop["x"], "y": shop["y"]}))) > 0)
blogs = api("/blog/hot?current=1")
check("Hot blogs and Java date serialization", len(blogs) > 0 and bool(blogs[0].get("createTime")))
status, picture = http(blogs[0]["images"].split(",")[0])
check("Local sample blog image", status == 200 and len(picture) > 100)


def mcp(method, params=None):
    _, body = http("/mcp", {"jsonrpc": "2.0", "id": 1, "method": method, "params": params or {}})
    response = json.loads(body)
    assert "error" not in response, str(response)
    return response["result"]


info = mcp("initialize", {"protocolVersion": "2025-03-26", "capabilities": {}, "clientInfo": {"name": "deployment-check", "version": "1.0"}})
check("MCP initialize", info["serverInfo"]["name"] == "ai-dianping-mcp")
tools = mcp("tools/list")["tools"]
check("MCP tools/list", any(tool["name"] == "queryShopById" for tool in tools))
result = mcp("tools/call", {"name": "queryShopById", "arguments": {"shopId": 1}})
payload = json.loads(result["content"][0]["text"])
check("MCP queryShopById actual invocation", not result.get("isError", False) and payload["success"] and payload["data"]["id"] == 1)
try:
    http("/api/user/me")
    raise AssertionError("Protected endpoint accepted an anonymous request")
except HTTPError as error:
    check("Login protection", error.code == 401)

local = (ROOT / "deploy/application-local.yml").read_text(encoding="utf-8")
username = re.search(r"(?m)^    username: (.+)$", local).group(1).strip()
password = re.search(r'(?m)^    password: "([^"]+)"$', local).group(1)
environment = os.environ.copy()
environment["MYSQL_PWD"] = password
query = subprocess.run(["C:/Program Files/MySQL/MySQL Server 8.0/bin/mysql.exe", "-h", "127.0.0.1", "-u", username, "--batch", "--skip-column-names", "ai_dianping", "-e", "SELECT phone FROM tb_user ORDER BY id LIMIT 1"], env=environment, capture_output=True, text=True, check=True)
phone = query.stdout.strip()
token = None
try:
    api("/user/code?" + urlencode({"phone": phone}), {})
    code = redis("GET", "login:code:" + phone)
    check("Login verification code stored in Redis", bool(code and len(code) == 6))
    token = api("/user/login", {"phone": phone, "code": code})
    check("Login returns a token", isinstance(token, str) and len(token) >= 16)
    me = api("/user/me", token=token)
    check("Authenticated user profile", bool(me.get("id")))
    skills = api("/ai/skills", token=token)
    check("AI skill catalog without a model call", len(skills) > 0)
finally:
    if token:
        api("/user/logout", {}, token)
    redis("DEL", "login:code:" + phone)

report = {"time": datetime.now(timezone(timedelta(hours=8))).isoformat(), "base_url": BASE, "passed": checks, "mcp_tools": [tool["name"] for tool in tools], "deepseek_live_call": "not tested: API key required", "orders": "not exercised"}
(ROOT / "logs/verification.json").write_text(json.dumps(report, indent=2, ensure_ascii=False), encoding="utf-8")
print("All", len(checks), "checks passed. MCP tools:", len(tools))
