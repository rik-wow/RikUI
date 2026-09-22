"""Exact empty M2 placement proofs; uninterpreted flags are not broadly admitted.
All 17 complete files agree with the unmodified pinned wow.export loader.
A changed model, flag combination, static array or extra physics stays unsupported.
"""
import collision_probe as collision
import terrain_probe as terrain
REFERENCE_SHA = "8fc03db917c4c3b24f5222a534e4d153a741995b2f704d2250ea748a95135c4f"
PINS = {
    5925296: ("4666db83b90a1818653d8c60f31164c0ec5f9538c123bbdca0c0f1f3d135e342", (96,)),
    7545268: ("4543e826ef4700b15bcfb2e3da01ccbef45f411d81940d3255a47ce1d8915a78", (96,)),
    7545269: ("5f17708b49141082b437adb8ec8a275dacc693880edc43750ff06f0d461d5d1d", (96,100)),
    7545270: ("a65061a209cef275ed64cfab59efcb49e7182fa5ab07948bf551b16cd17d144a", (96,100)),
    7545271: ("b0cddce95ea40480d827ab5b6393e2e77f7f4e7a98c201d8e440099e897a8932", (96,)),
    7545272: ("445029738fa2553e0077f84e02d234a46f7863301fb63fdddce550533659fd43", (96,100)),
    7545273: ("cc91b8cb18ef34f3f7f0dffa1a2750048c3acadc283238589abb2d6cf06ce283", (96,)),
    7545275: ("2ab1262cbcede2c319fdf034ec10aac396944bd67e2cd9e1f6a67be8c20766a4", (96,)),
    7545276: ("1784f50cbb92969d7ac09b41f8ada9f4d5f84e82fa084aeb5384e538e2370268", (96,)),
    7545278: ("0877aeb13df038fbac5d5cde5534e765b9b61b6ca4ec77f34caeb062d913afe5", (96,)),
    7545279: ("9309e22fafd49e50a3a1d00227bbb1f098cbc5355da36cbe7d7464b87d301a8d", (96,)),
    7545280: ("ebcd88a9edf8dcd00d44a0412a7d36d5ef2fe92cdd44afec426e6ba3ba6348a0", (96,)),
    7545281: ("74c40b6a05bece6a863c1a757fb1cdd903067d6094ed7116d03d5c81a8799128", (96,)),
    7545282: ("8ae9279649f55a7d5af9a47db9d589ed1e88ae5bc570b0468dc375ef8996404f", (96,)),
    7568169: ("f9640312ce2f918c5ecb5814756e16047b48e11fe63e208a90a334fe7ce8d3b9", (96,100)),
    7651389: ("0c9108ace2e5f6124135ff8af1aee838e2e4f18718d21da9a3e963940cfb8fdb", (100,)),
    8029659: ("5f3dbf982681898187241a4130df19beabe6bf0ff100ce228cba4d04659c2c5b", (96,100)),
}

def empty_mddf(placement, data):
    pin = PINS.get(placement["reference"])
    if not pin or placement["flags"] not in pin[1] or terrain.digest(data) != pin[0]:
        terrain.fail("unsupported-world-MDDF-flags:" + str(placement["flags"]))
    model = collision.m2(data)
    if (model["positions"] or model["indices"] or model["normals"]
            or any(tag in model["chunks"] for tag in collision.EXTRA_PHYSICS)):
        terrain.fail("empty-placement-proof-contradiction")
    return True
