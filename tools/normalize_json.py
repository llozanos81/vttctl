#!/usr/bin/env python3
"""
Normalize arbitrary JSON into canonical schema for vttctl.
Output schema:
  {
    "running": <string|bool>,
    "http": <int>,
    "active": <bool>,
    "version": <string|null>,
    "world": <string|null>,
    "system": <string|null>,
    "timestamp": <RFC3339 UTC string>
  }

Reads JSON from stdin or from first argument (path). Writes canonical JSON to stdout.
"""
import sys
import json
from datetime import datetime, timezone


def load_input(path=None):
    if path:
        with open(path, 'r') as f:
            return json.load(f)
    else:
        try:
            return json.load(sys.stdin)
        except Exception:
            return None


def to_rfc3339(dt=None):
    if dt is None:
        return datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')
    if isinstance(dt, (int, float)):
        return datetime.fromtimestamp(dt, tz=timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')
    if isinstance(dt, str):
        return dt
    return datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')


def normalize(obj):
    if not isinstance(obj, dict):
        return {
            'running': 'error',
            'http': 0,
            'active': False,
            'version': None,
            'world': None,
            'system': None,
            'timestamp': to_rfc3339(None),
        }
    running = obj.get('running', obj.get('ok', 'unknown'))
    http = obj.get('http', 200)
    active = obj.get('active', False)
    version = obj.get('version') if obj.get('version') is not None else None
    world = obj.get('world') if obj.get('world') is not None else None
    system = obj.get('system') if obj.get('system') is not None else None
    timestamp = obj.get('timestamp') if obj.get('timestamp') else to_rfc3339(obj.get('time') if 'time' in obj else None)
    return {
        'running': running,
        'http': http,
        'active': active,
        'version': version,
        'world': world,
        'system': system,
        'timestamp': timestamp,
    }


def main():
    path = sys.argv[1] if len(sys.argv) > 1 else None
    obj = load_input(path)
    norm = normalize(obj)
    json.dump(norm, sys.stdout, ensure_ascii=False)

if __name__ == '__main__':
    main()
