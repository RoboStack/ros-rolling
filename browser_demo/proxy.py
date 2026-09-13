#!/usr/bin/env python3
"""Single-origin reverse proxy for the browser demo.

The Browser pane sandbox only tunnels the one origin actively registered via
preview_start/.claude launch.json -- a page-initiated WebSocket connection to
a *different* host port bypasses that tunnel and hits the sandbox's own
(empty) network stack, regardless of whether the target port is genuinely
open on the real host. So both the static files and the zenoh WS router must
be reachable through the SAME origin/port: this proxy listens on one port and
either (a) forwards a WebSocket upgrade request to zenohd's WS listener, byte
-splicing the raw socket both ways, or (b) forwards a plain HTTP request to
the static file server.
"""
import asyncio
import sys

LISTEN_PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8765
STATIC_PORT = int(sys.argv[2]) if len(sys.argv) > 2 else 8766
ZENOH_WS_PORT = int(sys.argv[3]) if len(sys.argv) > 3 else 7447


async def pipe(reader: asyncio.StreamReader, writer: asyncio.StreamWriter):
    try:
        while True:
            data = await reader.read(65536)
            if not data:
                break
            writer.write(data)
            await writer.drain()
    except (ConnectionResetError, BrokenPipeError):
        pass
    finally:
        writer.close()


async def handle(client_reader: asyncio.StreamReader, client_writer: asyncio.StreamWriter):
    try:
        head = await client_reader.read(65536)
    except Exception:
        client_writer.close()
        return
    if not head:
        client_writer.close()
        return

    is_ws_upgrade = b"upgrade: websocket" in head.lower()
    target_port = ZENOH_WS_PORT if is_ws_upgrade else STATIC_PORT
    print(f"proxy: connection, ws_upgrade={is_ws_upgrade} -> port {target_port}, first_line={head.splitlines()[0] if head else b''}", flush=True)

    try:
        upstream_reader, upstream_writer = await asyncio.open_connection("127.0.0.1", target_port)
    except OSError:
        client_writer.close()
        return

    upstream_writer.write(head)
    await upstream_writer.drain()

    await asyncio.gather(
        pipe(client_reader, upstream_writer),
        pipe(upstream_reader, client_writer),
    )


async def main():
    server = await asyncio.start_server(handle, "127.0.0.1", LISTEN_PORT)
    print(f"proxy: listening on 127.0.0.1:{LISTEN_PORT} -> static:{STATIC_PORT} ws:{ZENOH_WS_PORT}")
    async with server:
        await server.serve_forever()


if __name__ == "__main__":
    asyncio.run(main())
