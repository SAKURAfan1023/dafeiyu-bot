"""Registered technical sprite extraction from image_gen sources; no semantic drawing/inpainting.

Authoring-only dependencies: Pillow and numpy. Generated occlusion plates provide hidden artwork.
Neutral feature pixels come from neutral.png at their source coordinates, never a resized face atlas.
"""
import hashlib
import json
from pathlib import Path
import tempfile

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "docs/design/deepseek-model-sources"
OUTPUT = ROOT / "packages/avatar/models"
CALIBRATION = json.loads((ROOT / "scripts/avatar-calibration.json").read_text())
EXPRESSION_PROFILES = json.loads((ROOT / "packages/avatar/expressions.json").read_text())
LABELS = dict(zip(CALIBRATION, ["蓝白水手服", "鲸鱼帽衫", "深海小研究员", "海洋轻礼装", "经典鲸鱼女仆"]))
W, H = 1024, 1536


def polygon(points):
    mask = Image.new("L", (W, H))
    if points:
        ImageDraw.Draw(mask).polygon([tuple(p) for p in points], fill=255)
    return np.asarray(mask) > 0


def rectangle(box):
    x0, y0, x1, y1 = box
    mask = np.zeros((H, W), bool)
    mask[y0:y1, x0:x1] = True
    return mask


def mirror(points):
    return [[W - x, y] for x, y in points]


def connected_arm(mask, elbow):
    yy, xx = np.where(mask)
    if not len(xx):
        raise ValueError("Empty arm mask")
    nearest = np.argmin((xx - elbow[0]) ** 2 + (yy - elbow[1]) ** 2)
    image = Image.fromarray(mask.astype(np.uint8) * 255).copy()
    ImageDraw.floodfill(image, (int(xx[nearest]), int(yy[nearest])), 128)
    return np.asarray(image) == 128


def load(path, cleanup=False):
    image = Image.open(path).convert("RGBA")
    if image.size != (W, H):
        raise ValueError(f"Unregistered source {path.name}: {image.size}")
    data = np.asarray(image).copy()
    if cleanup:
        # Retain original alpha only beside actual opaque sprite pixels, excluding the generated transparent glow.
        core = Image.fromarray((data[:, :, 3] > 220).astype(np.uint8) * 255).filter(ImageFilter.MaxFilter(3))
        data[:, :, 3] = np.where(np.asarray(core) > 0, data[:, :, 3], 0)
        data[:, :, 3] = np.where(data[:, :, 3] > 235, 255, data[:, :, 3])
    return Image.fromarray(data)


def masked(image, mask):
    data = np.asarray(image).copy()
    data[:, :, 3] = np.round(data[:, :, 3] * np.asarray(mask).astype(float)).astype(np.uint8)
    return Image.fromarray(data)


def soft_matte(core, radius=2):
    image = Image.fromarray(core.astype(np.uint8) * 255)
    halo = image.filter(ImageFilter.MaxFilter(3)).filter(ImageFilter.GaussianBlur(radius))
    return np.maximum(core.astype(float), np.asarray(halo) / 255)


def match_skin(original, generated, core, skin, region):
    """Match a generated skin plate to the original surrounding skin; no feature is redrawn."""
    surround = np.asarray(Image.fromarray(core.astype(np.uint8) * 255).filter(ImageFilter.MaxFilter(35))) > 0
    samples = surround & ~core & skin & region
    yy, xx = np.where(samples)
    if len(xx) < 20:
        raise ValueError("Insufficient original skin around a facial feature")
    cy, cx = np.mean(yy), np.mean(xx)
    design = np.column_stack([np.ones(len(xx)), (xx - cx) / 50, (yy - cy) / 50])
    delta = original[yy, xx, :3].astype(float) - generated[yy, xx, :3].astype(float)
    # Regularization prevents a narrow ring below the fringe from extrapolating an unstable gradient.
    coefficients = np.linalg.solve(design.T @ design + np.diag([1, 25, 25]), design.T @ delta)
    ys, xs = np.mgrid[:H, :W]
    correction = coefficients[0] + (xs[:, :, None] - cx) / 50 * coefficients[1] + (ys[:, :, None] - cy) / 50 * coefficients[2]
    result = generated.copy()
    result[:, :, :3] = np.clip(generated[:, :, :3].astype(float) + np.clip(correction, -35, 35), 0, 255).round().astype(np.uint8)
    return result


def ink_sprite(painted, background, core):
    """Remove the existing skin from antialiased ink edges instead of moving skin with the feature."""
    pixels = painted[:, :, :3].astype(float)
    skin = background[:, :, :3].astype(float)
    support = np.asarray(Image.fromarray(core.astype(np.uint8) * 255).filter(ImageFilter.MaxFilter(3))) > 0
    candidates = pixels[core]
    brightness = candidates.sum(axis=1)
    foreground = np.median(candidates[brightness <= np.quantile(brightness, .1)], axis=0)
    direction = skin - foreground
    alpha = np.clip(np.sum((skin - pixels) * direction, axis=2) / np.maximum(1, np.sum(direction ** 2, axis=2)), 0, 1)
    alpha *= support & (painted[:, :, 3] > 180)
    alpha[alpha < .035] = 0
    rgb = (pixels - skin * (1 - alpha[:, :, None])) / np.maximum(alpha[:, :, None], .001)
    result = np.zeros_like(painted, dtype=np.uint8)
    result[:, :, :3] = np.clip(rgb, 0, 255).round().astype(np.uint8)
    result[:, :, 3] = np.round(alpha * 255).astype(np.uint8)
    return Image.fromarray(result)


def build(id_, cfg, glyphs, output):
    source = SOURCE / id_
    dest = output / id_
    textures = dest / "textures"
    textures.mkdir(parents=True, exist_ok=True)
    original = load(source / "neutral.png", True)
    concealed = load(source / "concealed.png", True)
    white = load(source / "sclera.png")
    closed = load(source / "closed.png")
    skin_plate = load(source / "skin-fill-v2.png")
    plate_data = np.asarray(skin_plate).astype(np.int16)
    data = np.asarray(original).astype(np.int16)
    r, g, b = (data[:, :, i] for i in range(3))
    warm = (r > g + 7) & (g > b + 1) & (r > 90)
    ys, xs = np.mgrid[:H, :W]
    layers = []
    joints = {}

    def save(image, name, group, **props):
        bbox = image.getbbox()
        if not bbox:
            raise ValueError(f"Empty layer {id_}/{name}")
        x0, y0, x1, y1 = bbox
        x0, y0, x1, y1 = max(0, x0 - 2), max(0, y0 - 2), min(W, x1 + 2), min(H, y1 + 2)
        image.crop((x0, y0, x1, y1)).save(textures / (name + ".png"))
        layer = {"id": name, "texture": "textures/" + name + ".png", "x": x0, "y": y0, "w": x1 - x0, "h": y1 - y0, "group": group, "depth": 0, **props}
        layers.append(layer)
        return layer

    hand_box = cfg["hand_box"]
    hands = rectangle(hand_box) | rectangle([W - hand_box[2], hand_box[1], W - hand_box[0], hand_box[3]])
    torso = polygon(cfg["torso"]) | ((ys >= cfg["lower"]) & ~hands)
    if id_ != "researcher":
        # The neck column is skin/white collar, not the blue hair beside it.
        # Keep the hood's wider shoulder silhouette explicitly below this split.
        neck_surface = warm | ((np.minimum.reduce([r, g, b]) > 175) & (np.maximum.reduce([r, g, b]) - np.minimum.reduce([r, g, b]) < 45))
        torso &= (ys >= cfg["torso"][2][1]) | neck_surface
    torso |= polygon(cfg.get("torso_extra", []))
    # Follow the painted neck's flare rather than a fixed-width column: small skin
    # corners outside that column used to be mislabelled as hair and leave L-shaped seams.
    torso |= rectangle([cfg["head"][0] - 95, cfg["neck"], cfg["head"][0] + 95, cfg["collar"] + 6]) & warm
    if id_ == "classic-maid":
        shoulder_frill = rectangle([365, cfg["neck"] + 12, 660, cfg["shoulder"][1] + 8])
        torso |= shoulder_frill & (np.minimum.reduce([r, g, b]) > 110) & (np.maximum.reduce([r, g, b]) - np.minimum.reduce([r, g, b]) < 55)
    raw_arms = [polygon(cfg["arm"]), polygon(mirror(cfg["arm"]))]
    arm_regions = raw_arms.copy()
    front_lock = polygon(cfg["front_lock"]) | polygon(mirror(cfg["front_lock"]))
    lock_colour = Image.fromarray(((b > r + 8) & front_lock).astype(np.uint8) * 255).filter(ImageFilter.MaxFilter(3))
    front_lock &= np.asarray(lock_colour) > 0
    accessory = polygon(cfg.get("hair_accessory", []))
    front_lock |= accessory
    front_lock |= polygon(cfg.get("hair_overlay", [])) & (b > r + 8)
    tail = polygon(cfg.get("tail", []))
    if cfg.get("tail"):
        tail |= rectangle([740, 730, W, 1200]) & ~torso & (g < r + 18)
    # White sleeves/skin and dark navy sleeves separate chromatically from rear hair at their silhouettes.
    hair_color = (g > r + 18) & (b > r + 35)
    cuff = polygon(cfg.get("cuff", [])) | polygon(mirror(cfg.get("cuff", [])))
    cuff = np.asarray(Image.fromarray(cuff.astype(np.uint8) * 255).filter(ImageFilter.MaxFilter(13))) > 0
    if id_ in {"sailor", "researcher", "ocean-dress", "classic-maid"}:
        remove_hair = hair_color & ~cuff
        arm_regions = [mask & ~remove_hair for mask in arm_regions]
    # Painted sleeve edges just beyond a traced polygon belong to the arm, not to a static hair layer.
    for index, raw in enumerate(raw_arms):
        nearby = np.asarray(Image.fromarray(raw.astype(np.uint8) * 255).filter(ImageFilter.MaxFilter(25))) > 0
        sleeve_color = ~hair_color | cuff
        arm_regions[index] |= nearby & sleeve_color & ~torso & (ys > cfg["shoulder"][1]) & (ys < cfg["hand_box"][3]) & (data[:, :, 3] > 180)
        sx, sy = cfg["shoulder"]
        if index:
            sx = W - sx
        socket = (xs - sx) ** 2 + (ys - sy) ** 2 < 36 ** 2
        arm_regions[index] &= ~torso | socket
        if id_ == "ocean-dress":
            skin = raw & warm & (data[:, :, 3] > 180)
            edge = np.asarray(Image.fromarray(skin.astype(np.uint8) * 255).filter(ImageFilter.MaxFilter(3))) > 0
            arm_regions[index] = edge & raw & ~torso
        if id_ in {"sailor", "researcher"}:
            cloth = (r > 95) & (g > 95) & (np.abs(r - g) < 25) & (r > b - 28)
            core = arm_regions[index] & (cloth | warm | cuff) & (data[:, :, 3] > 180)
            filled = np.zeros((H, W), bool)
            for row in np.where(core.any(axis=1))[0]:
                xx = np.where(core[row])[0]
                filled[row, xx.min():xx.max() + 1] = True
            edge = np.asarray(Image.fromarray(filled.astype(np.uint8) * 255).filter(ImageFilter.MaxFilter(5))) > 0
            arm_regions[index] &= edge
        ex, ey = cfg["elbow"]
        arm_regions[index] = connected_arm(arm_regions[index] & (data[:, :, 3] > 120), [W - ex if index else ex, ey])
        # The connected core omits antialiased finger/sleeve edge pixels. They must
        # follow the arm too, rather than remain as a pale stationary hand in the hair.
        edge = np.asarray(Image.fromarray(arm_regions[index].astype(np.uint8) * 255).filter(ImageFilter.MaxFilter(5))) > 0
        arm_regions[index] |= edge & (data[:, :, 3] > 0)
    arm_mask = arm_regions[0] | arm_regions[1]
    torso &= ~tail
    original_body = (torso | arm_mask) & ~front_lock & ~tail

    eye_masks = []
    for box in cfg["eyes"]:
        x0, y0, x1, y1 = box
        width, height = x1 - x0, y1 - y0
        eye_masks.append(polygon([[x0, y0 + .48 * height], [x0 + .13 * width, y0 + .20 * height],
            [x0 + .40 * width, y0 + .12 * height], [x0 + .7 * width, y0 + .16 * height], [x1, y0 + .48 * height],
            [x0 + .84 * width, y0 + .78 * height], [x0 + .55 * width, y1], [x0 + .24 * width, y0 + .86 * height]]))
    mx, my = cfg["mouth"]
    mouth_mask = rectangle([mx - 30, my - 16, mx + 30, my + 20])
    brow_mask = np.zeros((H, W), bool)
    for stroke in cfg["brow_strokes"]:
        band = polygon([[x, y - 2] for x, y in stroke] + [[x, y + 2] for x, y in reversed(stroke)])
        brow_mask |= band & (r < 190) & (plate_data[:, :, 0] - r > 10)
    # Trace the facial surface, not a rectangle that also catches hair clips and ribbons.
    face_region = polygon(cfg["face_outline"])
    # Warm painted contours include the original jaw ink; blue fringe pixels stay in one continuous hair layer.
    face_skin = (r > g + 7) & (r > b + 10) & (r > 90) & (data[:, :, 3] > 200)
    visible_face = face_region & face_skin
    lower_face = np.zeros((H, W), bool)
    jaw_start = max(box[3] for box in cfg["eyes"])
    for row in range(jaw_start, cfg["neck"] + 1):
        xx = np.where(visible_face[row] & face_skin[row])[0]
        if len(xx):
            lower_face[row, max(0, xx.min() - 1):min(W, xx.max() + 2)] = True
    visible_face |= lower_face
    skin_context = face_region & (r > 200) & (r > g + 7) & (r > b + 10) & (data[:, :, 3] > 230)
    closed_data = np.asarray(closed).astype(np.int16)
    eye_parts = []
    eye_ink = np.zeros((H, W), bool)
    # One continuous face underpaint, calibrated once across the whole face, rather than per-eye skin patches.
    background = match_skin(data, np.asarray(skin_plate), eye_masks[0] | eye_masks[1] | mouth_mask | brow_mask, skin_context, face_region)
    clean_face = background.copy()
    skin_colour = (background[:, :, 0].astype(int) > 150) & (background[:, :, 0].astype(int) > background[:, :, 1].astype(int) + 4) & (background[:, :, 0].astype(int) > background[:, :, 2].astype(int) - 5) & (background[:, :, 3] > 220)
    clean_face[~skin_colour] = np.asarray(concealed)[~skin_colour]
    jaw_ink = (ys >= jaw_start) & face_region & face_skin & (r < 155)
    clean_face[jaw_ink] = data.astype(np.uint8)[jaw_ink]
    clean_face[:, :, 3] = data[:, :, 3].astype(np.uint8)
    for index, (eye_mask, box, iris) in enumerate(zip(eye_masks, cfg["eyes"], cfg["irises"])):
        ix, iy, irx, iry = iris
        aperture = polygon(cfg["eye_apertures"][index])
        near_eye = np.asarray(Image.fromarray(aperture.astype(np.uint8) * 255).filter(ImageFilter.MaxFilter(13))) > 0
        cr, cg, cb = [closed_data[:, :, channel] for channel in range(3)]
        protected_hair = (b > r + 18) & (cb > cr + 18)
        iris_ellipse = ((xs - ix) / (irx + 3)) ** 2 + ((ys - iy) / (iry + 3)) ** 2 <= 1
        # A blue closed eyelid can cross the pupil's old position. It is not a piece
        # of fringe and must not punch horizontal holes through the moving iris.
        protected_hair &= ~iris_ellipse
        # The registered closed-eye plate distinguishes blue iris pixels from the overlapping blue fringe.
        original_iris = near_eye & ~protected_hair & (b > r + 12) & iris_ellipse
        original_white = near_eye & (np.minimum.reduce([r, g, b]) > 180) & (r - b < 10) & (r - g < 10) & (np.maximum.reduce([r, g, b]) - np.minimum.reduce([r, g, b]) < 30)
        aperture |= original_iris | original_white
        aperture &= ~protected_hair
        aperture &= ~((r > 180) & (r - g > 14) & (r - b > 18))
        # Warm iris highlights are not skin holes. Fill only enclosed mask holes;
        # the outside contour and any fringe entering it remain untouched.
        ax0, ay0, ax1, ay1 = box[0] - 10, box[1] - 10, box[2] + 10, box[3] + 10
        tile = Image.fromarray(aperture[ay0:ay1, ax0:ax1].astype(np.uint8) * 255).copy()
        ImageDraw.floodfill(tile, (0, 0), 128)
        if tile.getpixel((0, 0)) != 128:
            raise ValueError("Eye aperture outside flood fill failed: " + id_)
        aperture[ay0:ay1, ax0:ax1] |= np.asarray(tile) == 0
        corner = box[0] if index == 0 else box[2]
        wing = rectangle([corner - 3, int(iy - 6), corner + 14, int(iy + 6)]) if index == 0 else rectangle([corner - 14, int(iy - 6), corner + 3, int(iy + 6)])
        lash = rectangle([box[0] - 3, box[1], box[2] + 3, box[3] + 2]) & (near_eye | wing) & ~brow_mask & ~protected_hair & (r < 190) & (g < r + 25) & (b < r + 45)
        lash &= ~((b > r + 8) & iris_ellipse)
        eye_ink |= lash
        iris_region = aperture & iris_ellipse
        core = aperture | lash
        visible_face |= core
        lashes = ink_sprite(data, background, lash)
        white_pixels = np.asarray(white).copy()
        wr, wg, wb = [white_pixels[:, :, channel].astype(int) for channel in range(3)]
        valid_white = aperture & (np.minimum.reduce([wr, wg, wb]) > 185) & (np.maximum.reduce([wr, wg, wb]) - np.minimum.reduce([wr, wg, wb]) < 30) & (wr - wb < 14) & (wr - wg < 10)
        vy, vx = np.where(valid_white)
        by, bx = np.where(aperture & ~valid_white)
        if not len(vx):
            raise ValueError("Missing registered sclera: " + id_)
        if len(bx):
            nearest = np.argmin((by[:, None] - vy) ** 2 + (bx[:, None] - vx) ** 2, axis=1)
            # Pad a few misregistered edge texels from this same eye's actual white plate, never from facial skin.
            white_pixels[by, bx, :3] = white_pixels[vy[nearest], vx[nearest], :3]
        white_pixels[:, :, 3] = 255
        eye = masked(Image.fromarray(white_pixels), aperture)
        eye.alpha_composite(lashes)
        pixels = np.asarray(eye).astype(np.int16)
        peach = (pixels[:, :, 3] > 200) & (pixels[:, :, 0] > 210) & (pixels[:, :, 0] - pixels[:, :, 1] > 14) & (pixels[:, :, 0] - pixels[:, :, 2] > 18)
        if peach.any() or aperture.sum() > (box[2] - box[0]) * (box[3] - box[1]) * .7:
            raise ValueError("Opaque skin or oversized eye aperture: " + id_)
        lr, lg, lb = [closed_data[:, :, channel] for channel in range(3)]
        lid_core = rectangle([box[0], int(iy - 13), box[2], int(iy + 17)]) & (lr < 165) & (lg < 140) & (lr > lg + 4) & (lb < lr + 20)
        lid = ink_sprite(closed_data, background, lid_core)
        eye_parts.append((eye, aperture, iris_region, lid))
    mouth_core = rectangle([mx - 22, my - 7, mx + 22, my + 11]) & (r < 250) & (r > g + 12) & (b < r + 12)
    neutral_mouth = ink_sprite(data, background, mouth_core)
    # A face mask must not own pieces of the blue fringe: those pieces otherwise move
    # with the face while their neighbours move with the hair, exposing a polygon edge.
    openings = eye_parts[0][1] | eye_parts[1][1]
    painted_hair = (b > r + 8) & (~openings | protected_hair) & ~brow_mask
    painted_hair = np.asarray(Image.fromarray(painted_hair.astype(np.uint8) * 255).filter(ImageFilter.MaxFilter(3))) > 0
    painted_hair &= (~openings | protected_hair) & ~eye_ink
    visible_face &= ~painted_hair
    brow_over_hair = brow_mask & (plate_data[:, :, 2] > plate_data[:, :, 0] + 8)
    visible_face &= ~brow_over_hair
    hair = ~(original_body | visible_face | tail)
    front = (ys < cfg["neck"] + 16) | front_lock
    if (source / "rear.png").exists():
        # Generated art is only the hidden hair below the original body/arm occlusion.
        # Replacing visible original hair with a different plate caused hard neck-height bands.
        rear = load(source / "rear.png", True)
        hidden = np.asarray(Image.fromarray((original_body & (data[:, :, 3] > 220)).astype(np.uint8) * 255).filter(ImageFilter.MaxFilter(17))) > 0
        hidden &= data[:, :, 3] > 220
        hidden &= ys > cfg["neck"] - 12
        if id_ == "researcher":
            hidden &= (ys < cfg["neck"] + 25) | (xs > cfg["head"][0] + 45)
        fill = save(masked(rear, hidden), "hidden_back_hair", "hair_back", depth=0)
        fill["bones"] = ["hair_left", "hair_right"]
    # Both sides of this split have original pixels and a shared underlap. No rectangular
    # silhouette closing, and no generated hair leaks into the fine outer-strand gaps.
    behind = np.asarray(Image.fromarray((~front).astype(np.uint8) * 255).filter(ImageFilter.MaxFilter(17))) > 0
    back = save(masked(original, hair & behind & (ys >= cfg["neck"] - 12)), "back_hair", "hair_back", depth=0)
    if id_ != "hoodie":
        back["bones"] = ["hair_left", "hair_right"]
    if tail.any():
        save(masked(original, tail), "whale_tail", "body", bones=["whale_tail"])
    neck_underlap = rectangle([cfg["head"][0] - 32, cfg["neck"] - 20, cfg["head"][0] + 32, cfg["neck"] + 4]) & face_skin
    body_base = masked(concealed, (((ys >= cfg["neck"] - 1) & torso) | neck_underlap) & (data[:, :, 3] > 200))
    # Keep painted material below the shoulder socket; complementary hard masks leave
    # a half-transparent one-texel seam after bilinear sampling, even in the rest pose.
    torso_underlap = np.asarray(Image.fromarray(torso.astype(np.uint8) * 255).filter(ImageFilter.MaxFilter(9))) > 0
    body_base.alpha_composite(masked(original, torso_underlap & original_body & ~front_lock))
    save(body_base, "body", "body")

    for side, arm in zip(["left", "right"], arm_regions):
        sx, sy = cfg["shoulder"]
        ex, ey = cfg["elbow"]
        wx, wy = cfg["wrist"]
        hand_box = cfg["hand_box"].copy()
        if side == "right":
            sx, ex, wx = W - sx, W - ex, W - wx
            hand_box = [W - hand_box[2], hand_box[1], W - hand_box[0], hand_box[3]]
        hand_box[1] -= 25
        # Keep the hand's original dark ink with its skin, including the outlines between fingers.
        hand = arm & rectangle(hand_box) & ((xs - wx) * (wx - ex) + (ys - wy) * (wy - ey) >= -3 * ((wx - ex) ** 2 + (wy - ey) ** 2) ** .5)
        wrist_overlap = np.asarray(Image.fromarray(hand.astype(np.uint8) * 255).filter(ImageFilter.MinFilter(9))) > 0
        sleeve = arm & ~wrist_overlap
        # One continuous sleeve/arm mesh blends elbow weights across the original painted fold.
        arm_id, hand_id = "arm_" + side, "hand_" + side
        save(masked(original, sleeve), arm_id, "body")
        save(masked(original, hand), hand_id, "body")
        distance = ((wx - ex) ** 2 + (wy - ey) ** 2) ** .5
        shoulder = {"pivot": [sx, sy], "control": side + "_shoulder"}
        elbow = {"pivot": [ex, ey], "control": side + "_elbow"}
        joints[arm_id] = [{**elbow, "axis": [(wx - ex) / distance, (wy - ey) / distance], "span": 85}, shoulder]
        joints[hand_id] = [{"pivot": [wx, wy], "control": side + "_wrist"}, elbow, shoulder]

    cx, cy, rx, ry = cfg["head"]
    # The source head is continuous: facial skin and rooted fringe share its mesh and
    # alpha, so colour-keyed adjacent layers cannot tear at the cheek or across a strand.
    # Only the feature-free facial surface is blended in; moving features remain separate.
    skin_weight = np.asarray(Image.fromarray(visible_face.astype(np.uint8) * 255).filter(ImageFilter.GaussianBlur(1.5))) / 255
    skin_weight *= visible_face
    # Erase whole registered feature zones, including small lash tips and blue iris
    # pixels a colour key mistakes for hair. These are baked into this single head,
    # never opaque moving skin patches. The generated plate keeps its own fringe.
    feature_core = mouth_mask.copy()
    for box in cfg["eyes"] + cfg["brows"]:
        x0, y0, x1, y1 = box
        feature_core |= rectangle([x0 - 5, y0 - 4, x1 + 5, y1 + 4])
    feature_weight = soft_matte(feature_core, 1.5)
    skin_weight = np.maximum(skin_weight, feature_weight)
    clean_face[feature_weight > 0] = background[feature_weight > 0]
    generated_hair = plate_data[:, :, 2] > plate_data[:, :, 0] + 8
    clean_face[generated_hair & (feature_weight > 0), :3] = plate_data[generated_hair & (feature_weight > 0), :3].astype(np.uint8)
    face = original.copy()
    face.alpha_composite(masked(Image.fromarray(clean_face), skin_weight))
    face = masked(face, (ys < cfg["neck"] + 4) & ~original_body & ~tail)
    save(face, "face", "head")
    if brow_mask.any():
        save(ink_sprite(data, background, brow_mask), "brows", "head")
    for side, parts, box, iris in zip(["L", "R"], eye_parts, cfg["eyes"], cfg["irises"]):
        ix, iy, irx, iry = iris
        eye, aperture, iris_region, lid = parts
        pivot = [ix, box[1] + 9]
        layer = save(eye, "eye_" + side, "head", role="eye_" + side, pivot=pivot)
        mask = Image.fromarray(aperture.astype(np.uint8) * 255).convert("RGBA")
        mask.putalpha(Image.fromarray(aperture.astype(np.uint8) * 255))
        x, y, w, h = (layer[k] for k in ["x", "y", "w", "h"])
        mask.crop((x, y, x + w, y + h)).save(textures / ("eye_" + side + "-mask.png"))
        layer["mask"] = "textures/eye_" + side + "-mask.png"
        save(masked(original, iris_region), "iris_" + side, "head", role="iris_" + side, pivot=pivot, clip="eye_" + side, range=[5, 3])
        save(lid, "lid_" + side, "head", role="lid_" + side)

    mouth_box = [mx - 30, my - 16, mx + 30, my + 20]
    def mouth_patch(image):
        # The mesh uses a global lattice: UVs outside the crop clamp to its edge, which must be transparent.
        a = np.asarray(image).copy()
        yy, xx = np.mgrid[:36, :60]
        a[:, :, 3] = np.round(a[:, :, 3] * np.minimum(1, np.minimum.reduce([xx, yy, 59 - xx, 35 - yy]) / 5)).astype(np.uint8)
        return Image.fromarray(a)

    mouth_patch(neutral_mouth.crop(tuple(mouth_box))).save(textures / "mouth-closed.png")
    mouth_files = ["textures/mouth-closed.png"]
    fill = masked(face, soft_matte(mouth_core, 1)).crop(tuple(mouth_box))
    widths = [22, 27, 14, 29]
    for index, name in enumerate(["half", "open", "round", "wide"]):
        glyph = glyphs[index]
        width = widths[index]
        height = max(2, round(glyph.height * width / glyph.width))
        image = Image.new("RGBA", (60, 36))
        image.alpha_composite(glyph.resize((width, height), Image.Resampling.LANCZOS), ((60 - width) // 2, max(0, 17 - height // 2)))
        mouth_patch(image).save(textures / ("mouth-" + name + ".png"))
        mouth_files.append("textures/mouth-" + name + ".png")
    layers.append({"id": "mouth", "texture": mouth_files[0], "frames": mouth_files, "visemes": ["closed", "half", "open", "round", "wide"], "role": "mouth", "group": "head", "depth": 0, "x": mx - 30, "y": my - 16, "w": 60, "h": 36})
    for name, profile in EXPRESSION_PROFILES.items():
        if name == "neutral":
            continue
        patch = fill.copy()
        glyph = glyphs[profile["glyph"]]
        width = profile["width"]
        height = max(2, round(glyph.height * width / glyph.width))
        patch.alpha_composite(glyph.resize((width, height), Image.Resampling.LANCZOS), ((60 - width) // 2, max(0, 17 - height // 2)))
        for suffix, image in [("", patch), ("-talk", fill.copy())]:
            mouth_patch(image).save(textures / ("expr-" + name + suffix + ".png"))
        layers.append({"id": "expr_" + name, "texture": "textures/expr-" + name + ".png", "talk": "textures/expr-" + name + "-talk.png", "role": "expr", "expression": name, "group": "head", "depth": 0, "x": mx - 30, "y": my - 16, "w": 60, "h": 36})
    in_front = np.asarray(Image.fromarray(front.astype(np.uint8) * 255).filter(ImageFilter.MaxFilter(17))) > 0
    fringe = save(masked(original, hair & in_front & (ys >= cfg["neck"] - 12)), "bangs", "hair_front", depth=0)
    if id_ != "hoodie":
        fringe["bones"] = ["hair_left", "hair_right"]
    effects = Image.open(SOURCE / "expression-effects-v1.png").convert("RGBA")
    for kind in ["hatch", "sweat"]:
        tile = effects.crop((0, 0, effects.width // 2, effects.height)) if kind == "hatch" else effects.crop((effects.width // 2, 0, effects.width, effects.height))
        if kind == "hatch":
            a = np.asarray(tile).copy().astype(int)
            a[:, :, 3] *= (a[:, :, 1] < 155) & (a[:, :, 0] > a[:, :, 1] + 20)
            tile = Image.fromarray(a.astype(np.uint8))
        bbox = tile.getchannel("A").point(lambda value: 255 if value > 48 else 0).getbbox()
        if not bbox:
            raise ValueError("Missing expression effect: " + kind)
        tile = tile.crop(bbox)
        placements = [("L", cfg["irises"][0][0] - 25, cfg["eyes"][0][3] + 3, 24, 11), ("R", cfg["irises"][1][0] + 1, cfg["eyes"][1][3] + 3, 24, 11)] if kind == "hatch" else [("R", cfg["eyes"][1][2] - 2, cfg["eyes"][1][1] - 4, 10, 21)]
        for side, x, y, width, height in placements:
            sprite = Image.new("RGBA", (width + 4, height + 4))
            sprite.alpha_composite(tile.resize((width, height), Image.Resampling.LANCZOS), (2, 2))
            name = "effect_" + kind + "_" + side
            sprite.save(textures / (name + ".png"))
            layers.append({"id": name, "texture": "textures/" + name + ".png", "x": x - 2, "y": y - 2, "w": width + 4, "h": height + 4, "group": "head", "depth": 0, "show": {"shy": .65} if kind == "hatch" else {"embarrassed": .85}})
    chains = []
    if id_ != "hoodie":
        for name, x in [("hair_left", 370), ("hair_right", 655)]:
            chains.append({"id": name, "points": [[x, cfg["neck"] + 35], [x, cfg["neck"] + 150], [x + (20 if x > cx else -20), cfg["hair_end"]]], "attach": "head", "depth": 0, "k": [200, 110], "damp": 15, "drive": .08, "hang": .06, "wind": .15, "freq": .35, "limit": 4, "sigma": 115, "reach": 145})
    if tail.any():
        chains.append({"id": "whale_tail", "points": [[775, 1055], [858, 969], [914, 850]], "attach": "body", "depth": 0, "k": [220, 150], "damp": 17, "drive": .05, "hang": .01, "wind": .08, "freq": .25, "limit": 3, "sigma": 115, "reach": 150})
    license_ = {"id": "MIT", "text": "Original AI-generated DaFeiYu character artwork; not an official DeepSeek character."}
    author = "DaFeiYu original AI-generated character project"
    if id_ == "classic-maid":
        author = "上善无形 / ZipZipPipe / 大肥鱼 AI 重绘"
        license_ = {"id": "CC-BY-NC-SA-4.0", "url": "https://creativecommons.org/licenses/by-nc-sa/4.0/", "text": "Community whale-girl derivative; retain author chain, noncommercial/share-alike artwork terms separately from MIT code."}
    model = {"format": "livliv-model", "version": 4, "name": LABELS[id_], "canvas": [W, H],
        "meta": {"generator": {"name": "DaFeiYu registered sprite extraction", "build": "avatar-v2-continuous-face"}, "author": {"name": author}, "license": license_, "watermark": {"kind": "none"}},
        "requires": [], "files": {"cover": "cover.png"}, "profile": {"id": "anime_half", "facing": "front"},
        "anchors": {"head": dict(zip(["cx", "cy", "rx", "ry"], cfg["head"])), "face": cfg["face"], "neck_y": cfg["neck"], "collar_y": cfg["collar"], "top_y": 0, "bottom_y": 1536, "hair_root_y": int(cy), "eyes": cfg["eyes"], "brows": cfg["brows"], "jaw": {"top": my - 16, "chin": cfg["neck"], "half": 0, "open": 0, "round": 0, "wide": 0}},
        "rig": {"yaw": .28, "pitch": .22, "roll": .42, "bulge": .65, "bulge_extent": [1.25, 1.2, 1.1], "body": {"yaw": .15, "roll": .18, "breath": .5, "bust": 0}, "neck": {"twist": .5, "reach": .6}, "hair": {"front": [200, 25, .05, 180, 25], "back": [110, 22, .2, 100, 22]}, "wind": .03, "brow": .04, "chains": chains},
        "expressions": [{"id": name, "label": {"zh": profile["label"]}} for name, profile in EXPRESSION_PROFILES.items() if name != "neutral"], "layers": layers,
        "x-dafeiyu-joints": joints}
    controls = {"head_yaw": [-1, 1], "head_pitch": [-1, 1], "head_tilt": [-1, 1], "gaze_x": [-1, 1], "gaze_y": [-1, 1], "left_close": [0, 1], "right_close": [0, 1], "body_lean": [-1, 1]}
    controls.update({"mouth_open": [0, 1], "vowel": [-1, 1], "brow_left": [-1, 1], "brow_right": [-1, 1]})
    for side in ["left", "right"]:
        for joint in ["shoulder", "elbow", "wrist"]:
            controls[side + "_" + joint] = [-1, 1]
    stage = {"model_id": id_, "default_view": {"head": True, "zoom": 2.9, "x": 0, "y": .14}, "controls": controls, "joints": joints, "joint_degrees": {"shoulder": 30, "elbow": 45, "wrist": 18},
        "expression_params": {name: profile["params"] for name, profile in EXPRESSION_PROFILES.items()},
        "expression_profiles": {name: {key: value for key, value in profile.items() if key not in {"params", "glyph", "width"}} for name, profile in EXPRESSION_PROFILES.items()}}
    original.save(dest / "cover.png")
    (dest / "model.json").write_text(json.dumps(model, ensure_ascii=False, indent=2) + "\n")
    (dest / "stage.json").write_text(json.dumps(stage, ensure_ascii=False, indent=2) + "\n")
    (dest / "manifest.json").write_text(json.dumps({"id": id_, "layers": len(layers), "files": {p.relative_to(dest).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(dest.rglob("*.png"))}}, indent=2) + "\n")
    print(id_, len(layers), "layers", len(joints), "joint-driven segments")


def main():
    atlas = Image.open(SOURCE / "mouth-atlas.png").convert("RGBA")
    glyphs = []
    for row in range(2):
        for col in range(4):
            tile = atlas.crop((round(col * atlas.width / 4), round(row * atlas.height / 2), round((col + 1) * atlas.width / 4), round((row + 1) * atlas.height / 2)))
            a = np.asarray(tile).copy()
            a[:, :, 3] = np.where(a[:, :, 3] > 150, a[:, :, 3], 0)
            tile = Image.fromarray(a)
            bbox = tile.getbbox()
            if not bbox:
                raise ValueError("Empty mouth atlas cell")
            glyphs.append(tile.crop(bbox))
    # Failed extraction must leave the currently playable model set intact.
    with tempfile.TemporaryDirectory(prefix=".avatar-models-", dir=OUTPUT.parent) as temp:
        staging, previous = Path(temp) / "models", Path(temp) / "previous"
        for id_, cfg in CALIBRATION.items():
            build(id_, cfg, glyphs, staging)
        if OUTPUT.exists():
            OUTPUT.rename(previous)
        try:
            staging.rename(OUTPUT)
        except OSError:
            if previous.exists():
                previous.rename(OUTPUT)
            raise


if __name__ == "__main__":
    main()
