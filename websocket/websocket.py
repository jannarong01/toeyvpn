#!/usr/bin/env python3
import socket
import threading
import select
import sys

LISTENING_ADDR = '127.0.0.1'
LISTENING_PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 10015
DEFAULT_HOST = '127.0.0.1:22'
BUFLEN = 4096 * 4
TIMEOUT = 60
RESPONSE = b'HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n\r\n'

class ConnectionHandler(threading.Thread):
    def __init__(self, client, addr):
        super().__init__(daemon=True)
        self.client = client
        self.addr = addr
        self.target = None

    def run(self):
        try:
            data = self.client.recv(BUFLEN)
            if not data:
                return
            host_port = DEFAULT_HOST.split(':')
            self.target = socket.create_connection((host_port[0], int(host_port[1])), timeout=TIMEOUT)
            self.client.sendall(RESPONSE)
            self.forward()
        except Exception:
            pass
        finally:
            if self.target:
                self.target.close()
            self.client.close()

    def forward(self):
        sockets = [self.client, self.target]
        while True:
            r, _, e = select.select(sockets, [], sockets, TIMEOUT)
            if e or not r:
                break
            for s in r:
                data = s.recv(BUFLEN)
                if not data:
                    return
                if s is self.client:
                    self.target.sendall(data)
                else:
                    self.client.sendall(data)

def main():
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind((LISTENING_ADDR, LISTENING_PORT))
    server.listen(128)
    print(f"WebSocket Proxy listening on {LISTENING_ADDR}:{LISTENING_PORT}")
    while True:
        try:
            client, addr = server.accept()
            ConnectionHandler(client, addr).start()
        except KeyboardInterrupt:
            break
        except Exception:
            continue

if __name__ == '__main__':
    main()