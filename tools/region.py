"""Which region a TamaWatch build holds (one per build): set TW_REGION (default kanto).
The region's species (less MISSING) are renumbered 1..COUNT inside the app (resources p001.., d001..); nat(k) is the
national dex number of local number k. Used by make_region.py and the generators it runs.
"""
import os, uuid

# id: (first, last national number, name shown, starters' national numbers)
REGIONS = {
    "kanto": (1, 151, "KANTO", (1, 4, 7)),
    "johto": (152, 251, "JOHTO", (152, 155, 158)),
    "hoenn": (252, 386, "HOENN", (252, 255, 258)),
    "sinnoh": (387, 493, "SINNOH", (387, 390, 393)),
    "unova": (494, 649, "UNOVA", (495, 498, 501)),
    "kalos": (650, 721, "KALOS", (650, 653, 656)),
    "alola": (722, 809, "ALOLA", (722, 725, 728)),
}
ORDER = ["kanto", "johto", "hoenn", "sinnoh", "unova", "kalos", "alola"]
# species PMD SpriteCollab has no sprites for (yet): left out of their region's build; an evolution
# line skips over a missing middle stage
MISSING = {514, 516, 520, 522, 523, 538, 558, 564, 565, 591, 592, 616, 626,     # Unova
           668,                                                                 # Kalos
           732, 735, 756, 765}                                                  # Alola
ID = os.environ.get("TW_REGION", "kanto")
FIRST, LAST, NAME, STARTERS = REGIONS[ID]


def species(rid):
    a, b = REGIONS[rid][0], REGIONS[rid][1]
    return [n for n in range(a, b + 1) if n not in MISSING]


SPECIES = species(ID)
COUNT = len(SPECIES)
KANTO_APP_ID = "20ca04fff8cc4bffb5f0526790d57c02"


def nat(k):
    return SPECIES[k - 1]


def local(n):
    return SPECIES.index(n) + 1 if n in SPECIES else 0


def app_id(rid=None):
    """Kanto keeps the app id TamaWatch always had; every other region is its own app (its own
    save), so switching regions never touches another region's game."""
    rid = rid or ID
    if rid == "kanto":
        return KANTO_APP_ID
    return uuid.uuid5(uuid.NAMESPACE_URL, "tamawatch-region-" + rid).hex
