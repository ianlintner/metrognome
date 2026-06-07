#!/usr/bin/env python3
"""Generate stylized forest 3D models via the Meshy text-to-3D API.

Flow per model: preview task -> poll -> refine task (adds textures) -> poll ->
download GLB into assets/forest/<name>.glb. Runs all models concurrently
through each phase to save wall-clock time.

Run: zsh -ic 'python3 tools/gen_meshy.py'   (needs MESHY_API_KEY in env)
"""
import json, os, sys, time, urllib.request, urllib.error

KEY = os.environ.get("MESHY_API_KEY")
if not KEY:
    print("ERROR: MESHY_API_KEY not set"); sys.exit(1)

BASE = "https://api.meshy.ai/openapi/v2/text-to-3d"
HDR = {"Authorization": f"Bearer {KEY}", "Content-Type": "application/json"}
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "forest")
os.makedirs(OUT, exist_ok=True)

STYLE = ("cute stylized low-poly cartoon, smooth rounded shapes, vibrant "
         "saturated colors, clean topology, mobile game asset, single object, "
         "neutral pose, centered, plain background")

# Full manifest of forest props (delete a GLB and re-run to regenerate just it;
# existing files are overwritten by name).
MODELS = {
    "mushroom_toadstool": f"a classic red toadstool mushroom with a domed red cap and white spots, white stem, {STYLE}",
    "mushroom_tall":      f"a tall whimsical mushroom with a gently curved bending stem and a colorful purple cap, playful storybook look, {STYLE}",
    "mushroom_cluster":   f"a small cluster of three or four slender mushrooms with thin pale stems and small rounded glowing blue and teal caps, isolated mushrooms only, NO ground, NO moss, NO soil, NO dirt base, {STYLE}",
    "fern_plant":         f"a lush leafy fern plant with several curved green fronds spreading from the base, {STYLE}",
    "forest_tree":        f"a stylized cartoon forest tree with a rounded fluffy green leafy canopy and a sturdy brown trunk, whimsical storybook style, {STYLE}",
    "tree_pine":          f"a tall stylized cartoon pine conifer evergreen tree, pointed layered dark green foliage, slim brown trunk, low-poly forest game asset, {STYLE}",
    "tree_round":         f"a big tall stylized cartoon oak tree with a huge dense rounded green canopy and a thick brown trunk, lush full foliage, forest game asset, {STYLE}",
    "bush_shrub":         f"a rounded leafy green bush shrub, dense small leaves, low-poly cartoon forest undergrowth game asset, {STYLE}",
}


def post(body):
    req = urllib.request.Request(BASE, data=json.dumps(body).encode(), headers=HDR, method="POST")
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.load(r)["result"]


def get(task_id):
    req = urllib.request.Request(f"{BASE}/{task_id}", headers=HDR)
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.load(r)


def poll(ids, label):
    """Poll a dict {name: task_id} until all SUCCEEDED/FAILED. Returns same dict."""
    done = {}
    while len(done) < len(ids):
        for name, tid in ids.items():
            if name in done:
                continue
            try:
                d = get(tid)
            except Exception as e:
                print(f"  [{label}] {name}: poll error {e}"); continue
            st = d.get("status")
            if st == "SUCCEEDED":
                done[name] = d; print(f"  [{label}] {name}: SUCCEEDED")
            elif st == "FAILED":
                done[name] = None; print(f"  [{label}] {name}: FAILED {d.get('task_error')}")
            else:
                print(f"  [{label}] {name}: {st} {d.get('progress',0)}%")
        if len(done) < len(ids):
            time.sleep(15)
    return done


def main():
    # Optional CLI filter: regenerate only the named models (default = all).
    only = set(sys.argv[1:])
    models = {k: v for k, v in MODELS.items() if not only or k in only}
    if only:
        print(f"=== Regenerating only: {', '.join(models)} ===")

    # Phase 1: previews
    print("=== Creating preview tasks ===")
    previews = {}
    for name, prompt in models.items():
        body = {"mode": "preview", "prompt": prompt, "art_style": "realistic",
                "should_remesh": True, "ai_model": "meshy-5",
                "topology": "triangle", "target_polycount": 18000}
        try:
            previews[name] = post(body); print(f"  {name}: preview {previews[name]}")
        except Exception as e:
            print(f"  {name}: preview create FAILED {e}")
    pdone = poll(previews, "preview")

    # Phase 2: refine the successful previews
    print("=== Creating refine tasks ===")
    refines = {}
    for name, d in pdone.items():
        if not d:
            continue
        try:
            refines[name] = post({"mode": "refine", "preview_task_id": previews[name]})
            print(f"  {name}: refine {refines[name]}")
        except Exception as e:
            print(f"  {name}: refine create FAILED {e}")
    rdone = poll(refines, "refine")

    # Phase 3: download GLBs
    print("=== Downloading GLBs ===")
    for name, d in rdone.items():
        if not d:
            continue
        url = (d.get("model_urls") or {}).get("glb")
        if not url:
            print(f"  {name}: no glb url"); continue
        path = os.path.join(OUT, f"{name}.glb")
        try:
            urllib.request.urlretrieve(url, path)
            print(f"  {name}: saved {path} ({os.path.getsize(path)} bytes)")
        except Exception as e:
            print(f"  {name}: download FAILED {e}")
    print("=== DONE ===")


if __name__ == "__main__":
    main()
