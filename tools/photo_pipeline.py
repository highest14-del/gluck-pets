#!/usr/bin/env python3
"""나나·모모 실사 PNG 96종 → 펫 엔진용 규격화 파이프라인 (의존성 0, 멀티프로세스).

- 순수 파이썬 PNG 디코드 (IDAT/필터 복원)
- 알파 가중 박스 다운스케일 1024 → 384 (프린지 방지)
- ASCII 파일명 변환 + manifest.json 생성
- QA용 컨택트시트 렌더 (방향 판별용)
"""
import json
import os
import struct
import sys
import zlib
from multiprocessing import Pool

SRC = "/workspace/gluck-pets/풀림/나나모모_데스크톱펫_96종/transparent"
DST = "/workspace/gluck-pets/dist/img"
QA = "/tmp/claude-0/-home-user-gluck-hr/d9f4f73a-7338-571c-8913-82b01575717c/scratchpad/qa"
TARGET = 384

DOG = {"나나": "nana", "모모": "momo"}
VIEW = {"옆": "side", "정면": "front", "대각60": "diag60", "대각30": "diag30"}
POSE = {
    "걷기": "walk", "걷기1": "walk1", "걷기2": "walk2", "걷기3": "walk3", "걷기4": "walk4",
    "달리기1": "run1", "달리기2": "run2", "달리기3": "run3", "구르기": "roll", "귀긁기": "scratch", "급정지": "skid",
    "기지개": "stretch", "까치발": "tiptoe", "냄새맡기": "sniff", "놀람": "startle",
    "달리기": "run", "당당함": "proud", "덮치기": "pounce", "덮치기준비": "crouch",
    "두발서기": "standup", "뒤돌아보기": "lookback", "몸털기": "shake",
    "미끄러짐": "slide", "배보이기": "belly", "비틀비틀": "wobble",
    "살금살금": "sneak", "서기": "stand", "시무룩": "sulk", "신남": "excited",
    "아래쳐다보기": "lookdown", "앉기": "sit", "앞발들기": "pawup",
    "앞발핥기": "lickpaw", "위쳐다보기": "lookup", "으르렁": "growl",
    "자기": "sleep", "재채기": "sneeze", "점프": "jump", "종종걸음": "trot",
    "지침": "tired", "착지": "land", "코핥기": "licknose", "하품": "yawn",
    "엎드리기": "prone", "눕기": "liedown", "일어나기": "rise", "주저앉기": "sitdown",
    "심심호소": "bored", "카메라전환": "camturn", "헤어짐아쉬움": "farewell",
    "시선추적": "gaze", "인사하기": "greeting", "질투반응": "jealous",
    "코비비기": "nuzzle", "앞발인사": "pawgreet", "쓰다듬기": "pet",
    "놀자초대": "playinvite", "칭찬세리머니": "praise", "톡건드리기": "tap",
    "창문두드리기": "windowknock", "창가올라보기": "windowpeek",
    "겁먹음": "scared", "궁금": "curious", "메롱": "tongue", "슬픔": "sad",
    "애원": "beg", "윙크": "wink", "졸림": "sleepy", "집중": "focus",
    "크게웃기": "laugh", "행복": "happy", "화남": "angry",
}


def decode_png(path):
    d = open(path, "rb").read()
    assert d[:8] == b"\x89PNG\r\n\x1a\n", path
    i, W, H, ct, idat = 8, 0, 0, None, b""
    while i < len(d):
        ln = struct.unpack(">I", d[i:i + 4])[0]
        tag = d[i + 4:i + 8]
        data = d[i + 8:i + 8 + ln]
        if tag == b"IHDR":
            W, H, bd, ct = struct.unpack(">IIBB", data[:10])
            assert bd == 8, f"{path}: bit depth {bd}"
        elif tag == b"IDAT":
            idat += data
        elif tag == b"IEND":
            break
        i += 8 + ln + 4
    raw = zlib.decompress(idat)
    ch = {6: 4, 2: 3, 0: 1}[ct]
    stride = W * ch
    out = bytearray(W * H * 4)
    prev = bytearray(stride)
    pos = 0
    for y in range(H):
        f = raw[pos]; pos += 1
        line = bytearray(raw[pos:pos + stride]); pos += stride
        if f == 1:
            for x in range(ch, stride):
                line[x] = (line[x] + line[x - ch]) & 255
        elif f == 2:
            for x in range(stride):
                line[x] = (line[x] + prev[x]) & 255
        elif f == 3:
            for x in range(stride):
                a = line[x - ch] if x >= ch else 0
                line[x] = (line[x] + ((a + prev[x]) >> 1)) & 255
        elif f == 4:
            for x in range(stride):
                a = line[x - ch] if x >= ch else 0
                b = prev[x]
                c = prev[x - ch] if x >= ch else 0
                p = a + b - c
                pa = p - a if p > a else a - p
                pb = p - b if p > b else b - p
                pc = p - c if p > c else c - p
                line[x] = (line[x] + (a if pa <= pb and pa <= pc else (b if pb <= pc else c))) & 255
        o = y * W * 4
        if ch == 4:
            out[o:o + stride] = line
        elif ch == 3:
            for x in range(W):
                out[o + x * 4:o + x * 4 + 3] = line[x * 3:x * 3 + 3]
                out[o + x * 4 + 3] = 255
        else:
            for x in range(W):
                v = line[x]
                out[o + x * 4:o + x * 4 + 4] = bytes((v, v, v, 255))
        prev = line
    return W, H, out


def encode_png(path, W, H, rgba):
    raw = bytearray()
    for y in range(H):
        raw.append(0)
        raw += rgba[y * W * 4:(y + 1) * W * 4]

    def chunk(tag, data):
        return (struct.pack(">I", len(data)) + tag + data
                + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF))

    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n"
                + chunk(b"IHDR", struct.pack(">IIBBBBB", W, H, 8, 6, 0, 0, 0))
                + chunk(b"IDAT", zlib.compress(bytes(raw), 9))
                + chunk(b"IEND", b""))


def resize_rgba(W, H, src, tw, th):
    """알파 가중 박스 리샘플 — 투명 경계 어두운 프린지 방지."""
    out = bytearray(tw * th * 4)
    xr = W / tw
    yr = H / th
    for ty in range(th):
        y0 = int(ty * yr); y1 = max(y0 + 1, int((ty + 1) * yr))
        for tx in range(tw):
            x0 = int(tx * xr); x1 = max(x0 + 1, int((tx + 1) * xr))
            r = g = b = a = n = 0
            for yy in range(y0, min(y1, H)):
                base = yy * W * 4
                for xx in range(x0, min(x1, W)):
                    p = base + xx * 4
                    av = src[p + 3]
                    r += src[p] * av; g += src[p + 1] * av; b += src[p + 2] * av
                    a += av; n += 1
            o = (ty * tw + tx) * 4
            if a > 0:
                out[o] = r // a; out[o + 1] = g // a; out[o + 2] = b // a
                out[o + 3] = a // n
            # else 이미 0
    return out


def bbox_alpha(W, H, rgba, thr=12):
    minx, miny, maxx, maxy = W, H, -1, -1
    for y in range(H):
        base = y * W * 4 + 3
        for x in range(W):
            if rgba[base + x * 4] > thr:
                if x < minx: minx = x
                if x > maxx: maxx = x
                if y < miny: miny = y
                if y > maxy: maxy = y
    if maxx < 0:
        return None
    return (minx, miny, maxx, maxy)


def resolve_pose(kor_pose):
    """숫자 변형 자동 인식: 몸털기2 → shake2 (모든 포즈 공통)."""
    if kor_pose in POSE:
        return POSE[kor_pose]
    import re
    m = re.match(r"(.+?)([1-9])$", kor_pose)
    if m and m.group(1) in POSE:
        return POSE[m.group(1)] + m.group(2)
    raise KeyError(kor_pose)


def process_one(fname):
    kor = fname[:-4]
    parts = kor.split("_")
    dog, view, pose = DOG[parts[0]], VIEW[parts[1]], resolve_pose(parts[2])
    key = f"{dog}_{view}_{pose}"
    W, H, rgba = decode_png(os.path.join(SRC, fname))
    small = resize_rgba(W, H, rgba, TARGET, TARGET)
    bb = bbox_alpha(TARGET, TARGET, small)
    os.makedirs(os.path.join(DST, dog), exist_ok=True)
    out = os.path.join(DST, dog, f"{view}_{pose}.png")
    encode_png(out, TARGET, TARGET, small)
    return {"key": key, "dog": dog, "view": view, "pose": pose, "kor": parts[2],
            "file": f"img/{dog}/{view}_{pose}.png", "bbox": bb, "src_size": [W, H]}


if __name__ == "__main__":
    files = sorted(f for f in os.listdir(SRC) if f.endswith(".png"))
    print(f"{len(files)} files, target {TARGET}px, procs=4")
    with Pool(4) as pool:
        results = []
        for i, r in enumerate(pool.imap_unordered(process_one, files)):
            results.append(r)
            print(f"[{i+1}/{len(files)}] {r['key']} bbox={r['bbox']}", flush=True)
    results.sort(key=lambda r: r["key"])
    os.makedirs(os.path.dirname(os.path.join(DST, "..", "manifest.json")), exist_ok=True)
    with open("/workspace/gluck-pets/dist/manifest.json", "w", encoding="utf-8") as f:
        json.dump({"version": 1, "canvas": TARGET, "images": results}, f,
                  ensure_ascii=False, indent=1)
    print("DONE — manifest written")
