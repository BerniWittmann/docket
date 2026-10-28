#!/usr/bin/env python3
"""Scrubs a recorded gh/Linear/Orca JSON response for use as a test fixture.

Usage: scrub-fixture.py <github|linear|orca> <in.json> <out.json> [keep-login ...]
Other people's logins become user-1, user-2, ...; titles and free text are replaced.
Bot logins and the logins passed as arguments are kept.
"""
import json, sys

kind, src, dst, *keep = sys.argv[1:]
logins = {}

def anon(login, typename=None):
    if login is None or login in keep or typename == "Bot" or login.endswith("[bot]"):
        return login
    return logins.setdefault(login, f"user-{len(logins) + 1}")

def walk(node, parent_key=None):
    if isinstance(node, list):
        return [walk(n, parent_key) for n in node]
    if not isinstance(node, dict):
        return node
    out = {}
    for k, v in node.items():
        if k == "login" and isinstance(v, str):
            out[k] = anon(v, node.get("__typename"))
        elif k == "title" and isinstance(v, str):
            out[k] = "Scrubbed title"
        elif k in ("preview", "prompt", "toolInput", "comment") and isinstance(v, str):
            out[k] = ""
        elif k == "lastAssistantMessage" and isinstance(v, str):
            out[k] = "Scrubbed agent message"
        elif k == "displayName" and kind == "orca" and isinstance(v, str):
            out[k] = "Scrubbed workspace"
        elif k == "name" and kind == "linear" and parent_key == "viewer":
            out[k] = "Viewer"
        else:
            out[k] = walk(v, k)
    return out

json.dump(walk(json.load(open(src))), open(dst, "w"), indent=1)
