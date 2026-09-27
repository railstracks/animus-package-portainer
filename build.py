#!/usr/bin/env python3
# build.py — emits built/manifest.json: standalone run(ctx) scripts (shared
# helpers inlined), lint-clean single-file publishable manifest.
import json
import os
import re

ROOT = os.path.dirname(os.path.abspath(__file__))


def load_shared():
    src = open(os.path.join(ROOT, "scripts", "_shared.lua"), encoding="utf-8").read()
    src = re.sub(r"\nreturn shared\s*$", "\n", src)
    return src


def load_stack_write_shared():
    src = open(os.path.join(ROOT, "scripts", "_stack_write_shared.lua"), encoding="utf-8").read()
    return src


def main():
    shared = load_shared()
    m = json.load(open(os.path.join(ROOT, "manifest", "manifest.json"), encoding="utf-8"))
    out = json.loads(json.dumps(m))

    stack_shared = load_stack_write_shared()
    for c in out["commands"]:
        sf = c.pop("script_file", None)
        if sf is None:
            continue
        script = open(os.path.join(ROOT, sf), encoding="utf-8").read()
        # ORDER MATTERS: _shared.lua declares `local shared = {}`; helpers
        # and commands must follow it LEXICALLY to capture the upvalue
        # (sandbox has no global `shared` — field-caught, stubs masked it).
        prefix = ""
        if "shared." in script or "stack_write_shared." in script:
            prefix += shared + "\n"
        if "stack_write_shared." in script:
            prefix += stack_shared + "\n"
        script = prefix + script
        assert "function run(" in script, f"{sf}: missing run(ctx)"
        c["script"] = script

    os.makedirs(os.path.join(ROOT, "built"), exist_ok=True)
    dest = os.path.join(ROOT, "built", "manifest.json")
    json.dump(out, open(dest, "w", encoding="utf-8"), indent=2, ensure_ascii=False)
    print(f"built {dest}: {len(out['commands'])} commands")


if __name__ == "__main__":
    main()
