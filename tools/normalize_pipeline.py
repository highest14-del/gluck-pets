#!/usr/bin/env python3
"""크기 정규화 파이프라인 v2 — 포즈마다 커졌다 작아졌다 하는 문제 해결.

원리: 강아지 실루엣 면적의 제곱근(sqrt-area)은 포즈와 무관하게 몸집에 비례.
각 원본(1024)에서 sqrt-area를 재고, 기준(=서기 포즈)에 맞춰 스케일을 보정한 뒤
발바닥 중심을 (192, 353) 고정 기준선에 정렬해 384 캔버스에 재배치한다.
전 과정 원본(1024)에서 다운스케일만 하므로 화질 손실 없음.
"""
import json
import math
import os
import sys
from multiprocessing import Pool

sys.path.insert(0, "/tmp/claude-0/-home-user-gluck-hr/d9f4f73a-7338-571c-8913-82b01575717c/scratchpad")
from photo_pipeline import DOG, POSE, VIEW, bbox_alpha, decode_png, encode_png, resolve_pose

SRC = "/workspace/gluck-pets"          # 사장님 정리 후 108장이 루트에 위치
DST = "/workspace/gluck-pets/dist/img"
TARGET = 384
ANCHOR_Y = 353                          # 발바닥 기준선 (기존 데이터 최빈값)
ANCHOR_X = 192
CLAMP = (0.72, 1.45)

HANG_L = {"hang90", "hang60", "hang30"}   # facing=L 유지 대상

# 개별 컷 색감 보정 (사장님 피드백): 감마 >1 = 중간톤 어둡게, 흰 부분 유지
TONE_GAMMA = {"나나_정면_크게웃기.png": 1.15}

MAP_EXTRA = {
    ("옆", "대롱대롱"): ("side", "hang90"),
    ("대각60", "대롱대롱"): ("side", "hang60"),
    ("대각30", "대롱대롱"): ("side", "hang30"),
    ("정면", "대롱대롱"): ("front", "hang0"),
    ("옆", "벽기대서기"): ("side", "wallstand"),
    ("정면", "빤히보기"): ("front", "stare"),
}


def parse(fname):
    parts = fname[:-4].split("_")
    if len(parts) != 3 or parts[0] not in DOG:
        return None
    dog = DOG[parts[0]]
    if (parts[1], parts[2]) in MAP_EXTRA:
        view, pose = MAP_EXTRA[(parts[1], parts[2])]
    elif parts[1] in VIEW:
        try:
            view, pose = VIEW[parts[1]], resolve_pose(parts[2])
        except KeyError:
            return None
    else:
        return None
    return dog, view, pose, parts[2]


def alpha_area(W, H, rgba, thr=12):
    n = 0
    for i in range(3, W * H * 4, 4):
        if rgba[i] > thr:
            n += 1
    return n


def measure(fname):
    W, H, rgba = decode_png(os.path.join(SRC, fname))
    return fname, alpha_area(W, H, rgba), bbox_alpha(W, H, rgba)


def rescale_place(W, H, src, s, bb):
    """원본을 s배로 박스 리샘플하고 bbox 발바닥 중심을 앵커에 정렬해 384 캔버스로."""
    out = bytearray(TARGET * TARGET * 4)
    # 목적지에서 역변환 샘플: dst(x,y) ← src 영역 평균
    fx_c = (bb[0] + bb[2]) / 2.0   # bbox 중심 x (원본)
    fy_b = bb[3]                    # bbox 바닥 y (원본)
    for ty in range(TARGET):
        sy0f = (ty - 0.5 - (ANCHOR_Y - fy_b * s)) / s + 0.5
        sy1f = (ty + 0.5 - (ANCHOR_Y - fy_b * s)) / s + 0.5
        y0 = max(0, int(math.floor(sy0f)))
        y1 = min(H, max(y0 + 1, int(math.ceil(sy1f))))
        if y0 >= H or y1 <= 0:
            continue
        for tx in range(TARGET):
            sx0f = (tx - 0.5 - (ANCHOR_X - fx_c * s)) / s + 0.5
            sx1f = (tx + 0.5 - (ANCHOR_X - fx_c * s)) / s + 0.5
            x0 = max(0, int(math.floor(sx0f)))
            x1 = min(W, max(x0 + 1, int(math.ceil(sx1f))))
            if x0 >= W or x1 <= 0:
                continue
            r = g = b = a = n = 0
            for yy in range(y0, y1):
                base = yy * W * 4
                for xx in range(x0, x1):
                    p = base + xx * 4
                    av = src[p + 3]
                    r += src[p] * av; g += src[p + 1] * av; b += src[p + 2] * av
                    a += av; n += 1
            if a > 0:
                o = (ty * TARGET + tx) * 4
                out[o] = r // a; out[o + 1] = g // a; out[o + 2] = b // a
                out[o + 3] = a // n
    return out


def process(job):
    fname, scale = job
    meta = parse(fname)
    dog, view, pose, kor = meta
    W, H, rgba = decode_png(os.path.join(SRC, fname))
    if fname in TONE_GAMMA:
        lut = [round(255 * (v / 255) ** TONE_GAMMA[fname]) for v in range(256)]
        for i in range(0, W * H * 4, 4):
            if rgba[i + 3]:
                rgba[i] = lut[rgba[i]]; rgba[i + 1] = lut[rgba[i + 1]]; rgba[i + 2] = lut[rgba[i + 2]]
    bb = bbox_alpha(W, H, rgba)
    # 세로로 긴 포즈(대롱대롱·두발서기·정면 등)가 캔버스를 넘으면 머리가 잘림 → 다 들어가게 축소
    bh = bb[3] - bb[1]
    fit = (ANCHOR_Y - 6.0) / bh
    if scale > fit:
        scale = fit
    # 가로로 긴 포즈(달리기 뻗음·눕기)가 캔버스를 넘으면 입/귀가 잘림 → 가로 가드 (v19)
    bw = bb[2] - bb[0]
    fit_w = (TARGET - 10.0) / bw
    if scale > fit_w:
        scale = fit_w
    small = rescale_place(W, H, rgba, scale, bb)
    nbb = bbox_alpha(TARGET, TARGET, small)
    outp = os.path.join(DST, dog, f"{view}_{pose}.png")
    encode_png(outp, TARGET, TARGET, small)
    rec = {"key": f"{dog}_{view}_{pose}", "dog": dog, "view": view, "pose": pose,
           "kor": kor, "file": f"img/{dog}/{view}_{pose}.png", "bbox": nbb,
           "src_size": [W, H], "size": os.path.getsize(outp)}
    if view == "side" and pose in HANG_L:
        rec["facing"] = "L"
    return rec


if __name__ == "__main__":
    files = [f for f in sorted(os.listdir(SRC)) if f.endswith(".png") and parse(f)]
    print(f"{len(files)} sources")
    with Pool(4) as pool:
        stats = dict()
        for fname, area, bb in pool.imap_unordered(measure, files):
            stats[fname] = (area, bb)
            print(f"measured {fname}: sqrtA={math.sqrt(area):.0f}", flush=True)
    # 기준: 각 강아지 side 서기의 sqrt-area
    anchors = {}
    stand_bb = {}
    sit_ref = {}
    for fname in files:
        meta = parse(fname)
        if meta and meta[1] == "side" and meta[2] == "stand":
            anchors[meta[0]] = math.sqrt(stats[fname][0])
            stand_bb[meta[0]] = stats[fname][1]
    base = 384.0 / 1024.0
    for fname in files:
        meta = parse(fname)
        if meta and meta[1] == "side" and meta[2] == "sit":
            f = anchors[meta[0]] / math.sqrt(stats[fname][0])
            f = max(CLAMP[0], min(CLAMP[1], f))
            bb = stats[fname][1]
            sit_ref[meta[0]] = (bb[3] - bb[1]) * base * f   # side_sit 출력 높이
    out_stand_w = {d: (bb[2] - bb[0]) * base for d, bb in stand_bb.items()}
    print("anchors:", anchors, "| stand_w:", {d: round(v) for d, v in out_stand_w.items()},
          "| sit_h:", {d: round(v) for d, v in sit_ref.items()})

    # 면적 규칙이 실패하는 포즈 계열 (v19):
    #  - 정면: 몸이 짧아 면적↓ → 과대 확대. 목표 = side_sit 출력 높이 (같은 앉은 자세의 회전일 뿐)
    #  - 눕기·잠·배: 웅크려 면적↓ → 과대 확대 + 좌우 잘림. 목표 폭 = 서기 폭 (코~꼬리 길이 보존)
    #  - 엎드리기: 스핑크스 = 서기 폭의 1.05배 (앞발이 앞으로 나옴)
    LY_FLAT = {"sleep", "sleep1", "sleep2", "liedown1", "liedown2", "liedown3", "belly"}
    LY_PRONE = {"prone1", "prone2", "prone3"}
    jobs = []
    for fname in files:
        dog, view, pose, _ = parse(fname)
        bb = stats[fname][1]
        if view == "front":
            scale = sit_ref[dog] / (bb[3] - bb[1])
        elif pose in LY_FLAT:
            scale = out_stand_w[dog] / (bb[2] - bb[0])
        elif pose in LY_PRONE:
            scale = out_stand_w[dog] * 1.05 / (bb[2] - bb[0])
        else:
            f = anchors[dog] / math.sqrt(stats[fname][0])
            f = max(CLAMP[0], min(CLAMP[1], f))
            scale = base * f
        jobs.append((fname, scale))
    with Pool(4) as pool:
        recs = []
        for i, rec in enumerate(pool.imap_unordered(process, jobs)):
            recs.append(rec)
            print(f"[{i+1}/{len(jobs)}] {rec['key']} bbox={rec['bbox']}", flush=True)
    recs.sort(key=lambda r: r["key"])
    with open("/workspace/gluck-pets/dist/manifest.json", "w", encoding="utf-8") as fp:
        json.dump({"version": 2, "canvas": TARGET, "images": recs}, fp,
                  ensure_ascii=False, indent=1)
    print("DONE — normalized manifest written")
