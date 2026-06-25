#!/usr/bin/env python3
"""
Simplistic WebSocket server for the WebView Bridge audio PoC.

Receives raw PCM audio bytes (16 kHz, mono, 16-bit) from the Flutter
app over a WebSocket connection, computes the RMS volume level, and
sends it back as a 4-byte little-endian float32 (0.0 – 1.0).

Usage
-----
    python server.py [--host HOST] [--port PORT]

Defaults: host 0.0.0.0, port 8080

From the Flutter app connect to:
    ws://<server-ip>:8080
"""

import argparse
import asyncio
import logging
import math
import struct
import time

import websockets
from websockets.asyncio.server import ServerConnection

# ── Logging setup ──────────────────────────────────────────────────────

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%H:%M:%S",
)
log = logging.getLogger("audio-ws-server")

# ── Audio helpers ──────────────────────────────────────────────────────

NOISE_GATE = 300.0  # RMS below this → silence
REF = 32767.0       # 16-bit full-scale


def compute_volume(pcm: bytes) -> float:
    """Compute normalised volume (0.0–1.0) from raw 16-bit PCM bytes."""
    if len(pcm) < 2:
        return 0.0

    # Unpack little-endian int16 samples.
    num_samples = len(pcm) // 2
    samples = struct.unpack_from(f"<{num_samples}h", pcm)

    sum_sq = sum(s * s for s in samples)
    rms = math.sqrt(sum_sq / num_samples)

    if rms < NOISE_GATE:
        return 0.0

    linear = min(rms / REF, 1.0)
    return math.sqrt(linear)


# ── Per-connection handler ─────────────────────────────────────────────

async def handle_client(connection: ServerConnection) -> None:
    """Handle a single WebSocket client connection.

    Receives binary frames (raw PCM audio), computes the volume level,
    and sends it back as a 4-byte little-endian float32.
    """
    client_id = id(connection)
    remote = getattr(connection, "remote_address", "unknown")
    log.info("Client %s connected from %s", client_id, remote)

    total_bytes = 0
    frame_count = 0
    start_time = time.monotonic()

    try:
        async for message in connection:
            if isinstance(message, bytes):
                frame_count += 1
                total_bytes += len(message)

                # Compute volume and send back as float32.
                volume = compute_volume(message)
                await connection.send(struct.pack("<f", volume))

                # Log stats every 50 frames (~1 second of audio).
                if frame_count % 50 == 0:
                    elapsed = time.monotonic() - start_time
                    rate = total_bytes / elapsed if elapsed > 0 else 0
                    log.info(
                        "Client %s: %d frames, %.1f KB total, %.1f KB/s, vol=%.3f",
                        client_id,
                        frame_count,
                        total_bytes / 1024,
                        rate / 1024,
                        volume,
                    )
            else:
                log.debug(
                    "Client %s: received text message: %s", client_id, message
                )

    except websockets.exceptions.ConnectionClosed:
        log.info("Client %s disconnected", client_id)
    except Exception:
        log.exception("Error handling client %s", client_id)
    finally:
        elapsed = time.monotonic() - start_time
        log.info(
            "Client %s session ended: %d frames, %.1f KB total in %.1fs",
            client_id,
            frame_count,
            total_bytes / 1024,
            elapsed,
        )


# ── Server lifecycle ───────────────────────────────────────────────────

async def main(host: str, port: int) -> None:
    log.info("Starting audio WebSocket server on ws://%s:%d", host, port)
    log.info("Connect from Flutter with: ws://%s:%d", "localhost", port)

    async with websockets.serve(handle_client, host, port):
        await asyncio.Future()  # run forever


def cli() -> None:
    parser = argparse.ArgumentParser(
        description="Audio WebSocket echo server for the WebView Bridge PoC."
    )
    parser.add_argument(
        "--host",
        default="0.0.0.0",
        help="Bind address (default: 0.0.0.0, all interfaces).",
    )
    parser.add_argument(
        "--port",
        type=int,
        default=8080,
        help="Listen port (default: 8080).",
    )
    args = parser.parse_args()

    try:
        asyncio.run(main(args.host, args.port))
    except KeyboardInterrupt:
        log.info("Server stopped by user")


if __name__ == "__main__":
    cli()