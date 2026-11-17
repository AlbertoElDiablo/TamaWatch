"""Route Crossing's walking trainers (TamaWatch's own characters): GBA-era proportions, 16 x 24,
three tones and an outline, 4 views x 2 walking frames. Returns {char: {view: [frame0, frame1]}}
as lists of 24 strings of 16 colour letters ('.' clear)."""

def mirror(rows):
    return [r[::-1] for r in rows]

def full(half):
    return [r + r[::-1] for r in half]

# ---------------- the boy: green cap, brown jacket over a yellow shirt, navy trousers, backpack
BOY_FRONT = full([
    "....KKKK", "...KccCC", "..KcCCCC", "..KCCCCC", ".KDCCCCC", ".KBBBBBB", "KDDDDDDD", ".KHSSSSS",
    ".KHSKSSS", ".KHSKSSS", "..KsSSSS", "...KsSSS", "..KJJjTT", ".KJJJjTT", ".KSKJJTT", ".KsKGJTT",
    "..KKGJJJ", "...KPPPP", "...KPPPP", "...KPpPP", "...KPPK.", "...KPPK.", "..KOOOK.", "..KKKKK.",
])
BOY_BACK = full([
    "....KKKK", "...KccCC", "..KcCCCC", "..KCCCCC", ".KDCCCCC", ".KDDDDDD", ".KHHHHHH", ".KHhHHHH",
    ".KHHHHHH", ".KHHHHHH", "..KHHHHH", "...KsSSS", "..KJAAAA", ".KJJAaAA", ".KSKAAAA", ".KsKAaAA",
    "..KKGAAA", "...KPPPP", "...KPPPP", "...KPpPP", "...KPPK.", "...KPPK.", "..KOOOK.", "..KKKKK.",
])
BOY_LEFT = [
    ".....KKKKK......", "....KccCCCK.....", "...KcCCCCCCK....", "...KCCCCCCCK....", "..KDCCCCCCCK....",
    "KDDDBBBBBBBK....", ".KKKHHHHHHHK....", "..KSSSHHHHHK....", "..KSKSSHHHHK....", "..KSSSSSHHK.....",
    "...KsSSSSHK.....", "....KsSSK.......", "....KJJJJAK.....", "...KJJJjJAAK....", "...KJSSJJAAK....",
    "...KJsSJGAAK....", "....KKJJGAK.....", ".....KPPPPK.....", ".....KPPPPK.....", ".....KPPpPK.....",
    ".....KPPPPK.....", ".....KPPPPK.....", "....KOOOOOK.....", "....KKKKKKK.....",
]
# ---------------- the girl: purple cap, long dark hair, pink top, navy skirt, lilac boots
GIRL_FRONT = full([
    "....KKKK", "...KccCC", "..KcCCCC", "..KCCCCC", ".KDCCCCC", ".KBBBBBB", "KDDDDDDD", "KHHSSSSS",
    "KHHSKSSS", "KHHSKSSS", "KHHsSSSS", "KHHKsSSS", "KHHJJjTT", ".KHJJjTT", ".KSKJJTT", ".KsKGJTT",
    "..KQQQQQ", ".KQQQQQQ", ".KQqQQQQ", "..KKSSSS", "...KSSK.", "...KSSK.", "..KLLLK.", "..KKKKK.",
])
GIRL_BACK = full([
    "....KKKK", "...KccCC", "..KcCCCC", "..KCCCCC", ".KDCCCCC", ".KDDDDDD", "KHHHHHHH", "KHhHHHHH",
    "KHHHHHHH", "KHHHHHHH", "KHHHHHHH", "KHHHHHHH", "KHHHAAAA", ".KHJAaAA", ".KSKAAAA", ".KsKAaAA",
    "..KQQQQQ", ".KQQQQQQ", ".KQqQQQQ", "..KKSSSS", "...KSSK.", "...KSSK.", "..KLLLK.", "..KKKKK.",
])
GIRL_LEFT = [
    ".....KKKKK......", "....KccCCCK.....", "...KcCCCCCCK....", "...KCCCCCCCK....", "..KDCCCCCCCK....",
    "KDDDBBBBBBBK....", ".KKKHHHHHHHHK...", "..KSSSHHHHHHK...", "..KSKSSHHHHHK...", "..KSSSSSHHHHK...",
    "...KsSSSSHHHK...", "....KsSSKHHHK...", "....KJJJJAHK....", "...KJJJjJAAK....", "...KJSSJJAAK....",
    "...KJsSJGAAK....", "....KQQQQQK.....", "...KQQQQQQQK....", "...KQQqQQQQK....", "....KKSSSSK.....",
    ".....KSSSSK.....", ".....KSSSSK.....", "....KLLLLLK.....", "....KKKKKKK.....",
]

def step_front(rows, leg, boot):
    """The walking frame seen from the front or back: one foot lifted, the other planted."""
    out = list(rows)
    out[20] = "...K%s%sK..K%s%sK..." % (leg, leg, leg, leg)
    out[21] = "..K%s%s%sK..K%s%sK..." % (boot, boot, boot, leg, leg)
    out[22] = "..KKKKK..K%s%s%sK.." % (boot, boot, boot)
    out[23] = ".........KKKKK.."
    return out

def step_side(rows, leg, boot):
    out = list(rows)
    out[20] = "....K%s%sKK%s%sK...." % (leg, leg, leg, leg)
    out[21] = "...K%s%sK..K%s%sK..." % (leg, leg, leg, leg)
    out[22] = "..K%s%s%sK..K%s%sK..." % (boot, boot, boot, boot, boot)
    out[23] = "..KKKKK..KKKK..."
    return out

def views(front, back, left, leg, boot):
    return {
        "front": [front, step_front(front, leg, boot)],
        "back": [back, step_front(back, leg, boot)],
        "left": [left, step_side(left, leg, boot)],
        "right": [mirror(left), mirror(step_side(left, leg, boot))],
    }

WALKERS = {
    "boy": views(BOY_FRONT, BOY_BACK, BOY_LEFT, "P", "O"),
    "girl": views(GIRL_FRONT, GIRL_BACK, GIRL_LEFT, "S", "L"),
}
COLOURS = {
    "boy": {"K": (0, 0, 0), "c": (85, 255, 85), "C": (0, 170, 0), "D": (0, 85, 0), "B": (255, 255, 0),
            "H": (85, 0, 0), "h": (170, 85, 0), "S": (255, 170, 85), "s": (170, 85, 0), "J": (170, 85, 0),
            "j": (255, 170, 85), "G": (85, 0, 0), "T": (255, 255, 85), "P": (0, 0, 85), "p": (0, 85, 170),
            "O": (85, 85, 85), "A": (170, 0, 0), "a": (255, 85, 85)},
    "girl": {"K": (0, 0, 0), "c": (255, 85, 255), "C": (170, 0, 170), "D": (85, 0, 85), "B": (255, 85, 170),
             "H": (85, 0, 0), "h": (170, 85, 0), "S": (255, 170, 85), "s": (170, 85, 0), "J": (255, 85, 170),
             "j": (255, 170, 255), "G": (170, 0, 85), "T": (255, 255, 255), "Q": (0, 0, 85), "q": (0, 85, 170),
             "L": (170, 170, 255), "A": (0, 85, 170), "a": (85, 170, 255)},
}

for who in WALKERS:
    for v in WALKERS[who].values():
        for fr in v:
            assert len(fr) == 24 and all(len(r) == 16 for r in fr), (who, [len(r) for r in fr])
