"""Managed Redis 캐시 내용 확인 (읽기 전용).

설치 불필요 — Python 표준 라이브러리만 사용. Azure CLI 로그인 상태 필요.
실행:  python scripts/check_redis.py
"""

import socket
import ssl
import subprocess


def az(*args: str) -> str:
    out = subprocess.run(["az", *args], capture_output=True, text=True, shell=True)
    return out.stdout.strip()


HOST = az("redisenterprise", "list", "-g", "rg-ai200ws-dev", "--query", "[0].hostName", "-o", "tsv")
PORT = 10000
USER = az("ad", "signed-in-user", "show", "--query", "id", "-o", "tsv")
TOKEN = az("account", "get-access-token", "--resource", "https://redis.azure.com", "--query", "accessToken", "-o", "tsv")


def encode(*args):
    out = [f"*{len(args)}\r\n".encode()]
    for a in args:
        b = a.encode() if isinstance(a, str) else a
        out.append(f"${len(b)}\r\n".encode() + b + b"\r\n")
    return b"".join(out)


class Reader:
    def __init__(self, sock):
        self.s, self.buf = sock, b""

    def _line(self):
        while b"\r\n" not in self.buf:
            self.buf += self.s.recv(65536)
        line, self.buf = self.buf.split(b"\r\n", 1)
        return line

    def read(self):
        line = self._line()
        t, rest = line[:1], line[1:]
        if t in (b"+", b"-", b":"):
            return rest.decode(errors="replace")
        if t == b"$":
            n = int(rest)
            if n == -1:
                return None
            while len(self.buf) < n + 2:
                self.buf += self.s.recv(65536)
            data, self.buf = self.buf[:n], self.buf[n + 2:]
            return data.decode(errors="replace")
        if t == b"*":
            n = int(rest)
            return None if n == -1 else [self.read() for _ in range(n)]
        return line.decode(errors="replace")


ctx = ssl.create_default_context()
sock = ctx.wrap_socket(socket.create_connection((HOST, PORT), timeout=15), server_hostname=HOST)
r = Reader(sock)


def cmd(*args):
    sock.sendall(encode(*args))
    return r.read()


print(f"host = {HOST}")
print("AUTH      :", cmd("AUTH", USER, TOKEN))
print("PING      :", cmd("PING"))
print("DBSIZE    :", cmd("DBSIZE"))
print("FT._LIST  :", cmd("FT._LIST"))

info = cmd("FT.INFO", "rag_cache_idx")
if isinstance(info, list):
    d = {info[i]: info[i + 1] for i in range(0, len(info) - 1, 2)}
    print("FT.INFO   : num_docs =", d.get("num_docs"),
          "| hash_indexing_failures =", d.get("hash_indexing_failures"))
else:
    print("FT.INFO   :", info)

keys = cmd("KEYS", "rag:*") or []
print(f"KEYS rag:*: {len(keys)} keys")
for k in keys[:5]:
    ttl = cmd("TTL", k)
    q = cmd("HGET", k, "question")
    print(f"   - {k}  (TTL={ttl}s)  question={q!r}")

sock.close()
