"""Swift release version mappings.

This module defines the SWIFT_RELEASES dictionary, which maps each Swift version
to its supported platforms and their corresponding SHA256 checksums. This data is
used to download and verify Swift toolchain releases for different platforms.

The structure is:
    SWIFT_RELEASES = {
        "version": {
            "platform": "sha256_checksum",
            ...
        },
        ...
    }

Supported platforms include various Linux distributions (amazonlinux2, debian12,
fedora39, ubi9, ubuntu22.04, ubuntu24.04) in both x86_64 and aarch64 architectures,
as well as Xcode toolchains for macOS.
"""

SWIFT_RELEASES = {
    "6.2.1": {
        "amazonlinux2": "218fc55ba7224626fd25f8ca285b083fda020e3737146e2fe10b8ae9aaf2ae97",
        "amazonlinux2-aarch64": "00999039a82a81b1e9f3915eb2c78b63552fe727bcbfe9a2611628ac350287f2",
        "debian12": "d6405e4fb7f092cbb9973a892ce8410837b4335f67d95bf8607baef1f69939e4",
        "debian12-aarch64": "522d231bb332fe5da9648ca7811e8054721f05eccd1eefae491cf4a86eab4155",
        "fedora39": "ec78360dfa7817d7637f207b1ffb3a22164deb946c9a9f8c40ab8871856668e8",
        "fedora39-aarch64": "d8bc04e7e283e314d1b96adc55e1803dd01a0106dc0d0263e784a5c9f2a46d3b",
        "ubi9": "9a082c3efdeda2e65cbc7038d0c295b75fa48f360369b2538449fc665192da3e",
        "ubi9-aarch64": "47f109f1f63fa24df3659676bb1afac2fdd05c0954d4f00977da6a868dd31e66",
        "ubuntu22.04": "5ec23d4004f760fafdbb76c21e380d3bacef1824300427a458dc88c1c0bef381",
        "ubuntu22.04-aarch64": "ab5f3eb0349c575c38b96ed10e9a7ffa2741b0038285c12d56251a38749cadf0",
        "ubuntu24.04": "4022cb64faf7e2681c19f9b62a22fb7d9055db6194d9e4a4bef9107b6ce10946",
        "ubuntu24.04-aarch64": "3b70a3b23b9435c37112d96ee29aa70061e23059ef9c4d3cfa4951f49c4dfedb",
        "xcode": "4ca13d0abd364664d19facd75e23630c0884898bbcaf1920b45df288bdb86cb2",
    },
    "6.2.2": {
        "amazonlinux2": "2de884b0ccf1012750fd93c710506c3d216e34676b488ba318fefe711a136125",
        "amazonlinux2-aarch64": "4bb5714a683d8ddf78bc69027cb2acc9854ae51e91e55badba2e5c231b923a42",
        "debian12": "d4817caaf70e95639702b69be24730057f4220f76796573397cdc067a4360041",
        "debian12-aarch64": "1e225d1f9a78de78d5f4d0cdc4e58531b125788a7c5f904db68a3f6f21f639d9",
        "fedora39": "c68971618737c66e76e39e7304a59f6af332c68dca64f0a97ff2393bfd09e136",
        "fedora39-aarch64": "aaec949e278427fc8ba095a4edf67b80d1a8230a5c7c43ef9383d6860407dd75",
        "ubi9": "a90b616b97616fdc4906babced4961982ab36a1e3ce44cf07d4a036298529abb",
        "ubi9-aarch64": "a90b616b97616fdc4906babced4961982ab36a1e3ce44cf07d4a036298529abb",
        "ubuntu22.04": "b3cafe1ca87ba0bf253639aec53052b545c9fcccd810da8cf15ac9ad62561f7e",
        "ubuntu22.04-aarch64": "6f3bff4c2a69163e56d2bacfa8ede2535ae52f5a29824f3c13d9e4c3ad1ac155",
        "ubuntu24.04": "2e226607d419f7b6197a6a0a9b317ee1cdb4125c21c72b0b24adfb82d4274fa9",
        "ubuntu24.04-aarch64": "53152dfed20e971f4cdbb40a205e9b4a8d8d34a84e1d0fefbdfce7af87072db1",
        "xcode": "1173886e2084a6705a774875e4b1b2fceeb890d79ced54ee824cfd10bdc26328",
    },
    "6.2.3": {
        "amazonlinux2": "fe1513e441ab653a134f9fd35855fe5dddac5fa716c0b0fe119eb76757525f05",
        "amazonlinux2-aarch64": "0753ec4fb786c626a681803c25ea3c681df583f0f576a6e326a25bd92294b4c6",
        "debian12": "d47b7416f68e75b3b8ed538c939dc6e5a9e9a8de2d605389661d2ef31e75b772",
        "debian12-aarch64": "6d9703968ef399b953e67229c5feb0781ceca12d089208ecef8157b59e22582b",
        "fedora39": "34314fab3f8e975980bcddf6b372b10e6430fb5c469e7232b95e06ae2762f449",
        "fedora39-aarch64": "802154a68eade7051ddaa290cf30d51a801a6b291edfc34643398acde9dffde9",
        "ubi9": "a43399aad9d5b19f7d7d6f88ed19129ca6afaf34bb6b455ca01e61a98ec425f2",
        "ubi9-aarch64": "a43399aad9d5b19f7d7d6f88ed19129ca6afaf34bb6b455ca01e61a98ec425f2",
        "ubuntu22.04": "23653abba4b153aa6625f73e63e3f119bdaf18363b00e3770a306fbd9b192aef",
        "ubuntu22.04-aarch64": "fbb4282ec60107cc844700aac6c7a8115534defb1c9b36867bd77c0829e5b163",
        "ubuntu24.04": "3e0b8eaf9210131a1756e6a1a9e9103bac83609a0ae604d6f2e791053f98f115",
        "ubuntu24.04-aarch64": "48dc99bcabc54feadd2942f4830be854ca2396e2db4ca4ec6b6c926a25c87d55",
        "xcode": "c1ed84cf543286c549caaccc47e0b47d8c61c3c8fedbce1205dedcbebe7601a8",
    },
}
