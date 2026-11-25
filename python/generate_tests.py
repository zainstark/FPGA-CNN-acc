#!/usr/bin/env python3
"""
Generate deterministic test vectors and golden outputs for the
32x32 -> 30x30, 3x3 convolution accelerator.

The generated directory is:
    ./test_vectors/

Each test case contains:
    image.txt
    kernel.txt
    expected.txt
    metadata.json

IMPORTANT:
    Kernel values are written as normal signed decimal integers.
    For example, -128, -1, 0, 1, 127.
"""

from __future__ import annotations

from pathlib import Path
import json
import random
import shutil

from golden_model import (
    IMAGE_HEIGHT,
    IMAGE_WIDTH,
    KERNEL_SIZE,
    KERNEL_MIN,
    KERNEL_MAX,
    OUT_MIN,
    OUT_MAX,
    run_case,
)


ROOT = Path(__file__).resolve().parent
TEST_ROOT = ROOT / "test_vectors"
SEED = 20260913


def constant_image(value: int) -> list[list[int]]:
    return [[value] * IMAGE_WIDTH for _ in range(IMAGE_HEIGHT)]


def ramp_image() -> list[list[int]]:
    return [
        [(r * IMAGE_WIDTH + c) & 0xFF for c in range(IMAGE_WIDTH)]
        for r in range(IMAGE_HEIGHT)
    ]


def random_image(rng: random.Random) -> list[list[int]]:
    return [
        [rng.randint(0, 255) for _ in range(IMAGE_WIDTH)]
        for _ in range(IMAGE_HEIGHT)
    ]


def checkerboard_image(square: int = 4) -> list[list[int]]:
    return [
        [
            255 if ((r // square) + (c // square)) % 2 == 0 else 0
            for c in range(IMAGE_WIDTH)
        ]
        for r in range(IMAGE_HEIGHT)
    ]


def write_metadata(
    case_dir: Path,
    name: str,
    description: str,
    seed: int | None,
) -> None:
    metadata = {
        "name": name,
        "description": description,
        "image_shape": [IMAGE_HEIGHT, IMAGE_WIDTH],
        "kernel_shape": [KERNEL_SIZE, KERNEL_SIZE],
        "operation": "valid stride-1 cross-correlation",
        "input_width": 8,
        "kernel_width": 8,
        "product_width": 16,
        "accumulator_width": 20,
        "output_width": 16,
        "output_policy": "signed saturation",
        "random_seed": seed,
    }

    (case_dir / "metadata.json").write_text(
        json.dumps(metadata, indent=2) + "\n",
        encoding="utf-8",
    )


def add_case(
    name: str,
    description: str,
    image: list[list[int]],
    kernel: list[list[int]],
    seed: int | None = None,
) -> None:
    case_dir = TEST_ROOT / name

    expected = run_case(case_dir, image, kernel)
    write_metadata(case_dir, name, description, seed)

    assert len(expected) == IMAGE_HEIGHT - KERNEL_SIZE + 1
    assert len(expected[0]) == IMAGE_WIDTH - KERNEL_SIZE + 1

    for row in expected:
        for value in row:
            assert OUT_MIN <= value <= OUT_MAX


def main() -> None:
    if TEST_ROOT.exists():
        shutil.rmtree(TEST_ROOT)

    TEST_ROOT.mkdir(parents=True)

    rng = random.Random(SEED)
    case_count = 0

    def case(*args, **kwargs):
        nonlocal case_count
        add_case(*args, **kwargs)
        case_count += 1

    # ------------------------------------------------------------
    # 1. Zero image
    # ------------------------------------------------------------
    case(
        "zero",
        "32x32 all-zero image. Output must be zero for any kernel.",
        constant_image(0),
        [
            [1, -2, 3],
            [-4, 5, -6],
            [7, -8, 9],
        ],
    )

    # ------------------------------------------------------------
    # 2. Constant image + all positive kernel
    # ------------------------------------------------------------
    case(
        "constant_positive",
        "Constant image with an all-ones kernel. Every output is 90.",
        constant_image(10),
        [
            [1, 1, 1],
            [1, 1, 1],
            [1, 1, 1],
        ],
    )

    # ------------------------------------------------------------
    # 3. Constant image + all negative kernel
    # ------------------------------------------------------------
    case(
        "constant_negative",
        "Constant image with an all-minus-one kernel. Every output is -90.",
        constant_image(10),
        [
            [-1, -1, -1],
            [-1, -1, -1],
            [-1, -1, -1],
        ],
    )

    # ------------------------------------------------------------
    # 4. Positive kernel
    # ------------------------------------------------------------
    case(
        "positive_kernel",
        "Ramp image with only positive coefficients.",
        ramp_image(),
        [
            [1, 2, 3],
            [2, 3, 4],
            [3, 4, 5],
        ],
    )

    # ------------------------------------------------------------
    # 5. Negative kernel
    # ------------------------------------------------------------
    case(
        "negative_kernel",
        "Ramp image with only negative coefficients.",
        ramp_image(),
        [
            [-1, -2, -3],
            [-2, -3, -4],
            [-3, -4, -5],
        ],
    )

    # ------------------------------------------------------------
    # 6. Mixed signed kernel
    # ------------------------------------------------------------
    case(
        "mixed_sign_kernel",
        "Ramp image with positive, negative and zero coefficients.",
        ramp_image(),
        [
            [-1, 0, 1],
            [-2, 0, 2],
            [-1, 0, 1],
        ],
    )

    # ------------------------------------------------------------
    # 7. Random signed test
    # ------------------------------------------------------------
    random_image_data = random_image(rng)
    random_kernel = [
        [rng.randint(KERNEL_MIN, KERNEL_MAX) for _ in range(KERNEL_SIZE)]
        for _ in range(KERNEL_SIZE)
    ]

    case(
        "random",
        "Deterministic random unsigned image and signed kernel.",
        random_image_data,
        random_kernel,
        seed=SEED,
    )

    # ------------------------------------------------------------
    # 8. Maximum pixel value
    # ------------------------------------------------------------
    case(
        "maximum_pixels",
        "All pixels are 255 with a mixed signed kernel.",
        constant_image(255),
        [
            [1, -1, 2],
            [-2, 3, -3],
            [4, -4, 5],
        ],
    )

    # ------------------------------------------------------------
    # 9. Maximum positive coefficient
    # ------------------------------------------------------------
    case(
        "maximum_positive_kernel",
        "All pixels are 255 and all coefficients are +127.",
        constant_image(255),
        [
            [127, 127, 127],
            [127, 127, 127],
            [127, 127, 127],
        ],
    )

    # ------------------------------------------------------------
    # 10. Maximum negative coefficient
    # ------------------------------------------------------------
    case(
        "maximum_negative_kernel",
        "All pixels are 255 and all coefficients are -128.",
        constant_image(255),
        [
            [-128, -128, -128],
            [-128, -128, -128],
            [-128, -128, -128],
        ],
    )

    # ------------------------------------------------------------
    # 11. Positive saturation
    # ------------------------------------------------------------
    case(
        "saturation_positive",
        "Maximum positive accumulation. Expected output saturates to +32767.",
        constant_image(255),
        [
            [127, 127, 127],
            [127, 127, 127],
            [127, 127, 127],
        ],
    )

    # ------------------------------------------------------------
    # 12. Negative saturation
    # ------------------------------------------------------------
    case(
        "saturation_negative",
        "Maximum negative accumulation. Expected output saturates to -32768.",
        constant_image(255),
        [
            [-128, -128, -128],
            [-128, -128, -128],
            [-128, -128, -128],
        ],
    )

    # ------------------------------------------------------------
    # 13. Checkerboard
    # ------------------------------------------------------------
    case(
        "checkerboard",
        "0/255 checkerboard image with mixed signed coefficients.",
        checkerboard_image(),
        [
            [1, -1, 1],
            [-1, 1, -1],
            [1, -1, 1],
        ],
    )

    # ------------------------------------------------------------
    # 14. Sobel X
    # ------------------------------------------------------------
    case(
        "sobel_x",
        "Ramp image with the Sobel-X edge detector.",
        ramp_image(),
        [
            [-1, 0, 1],
            [-2, 0, 2],
            [-1, 0, 1],
        ],
    )

    # ------------------------------------------------------------
    # 15. Random edge-heavy test
    #
    # Deliberately use many values near -128 and +127.
    # This is useful for catching signedness bugs.
    # ------------------------------------------------------------
    edge_values = [-128, -127, -126, -2, -1, 0, 1, 2, 125, 126, 127]

    edge_kernel = [
        [rng.choice(edge_values) for _ in range(KERNEL_SIZE)]
        for _ in range(KERNEL_SIZE)
    ]

    case(
        "signed_edge_values",
        "Random kernel containing many signed 8-bit boundary values.",
        random_image(rng),
        edge_kernel,
        seed=SEED,
    )

    # ------------------------------------------------------------
    # Explicit arithmetic sanity checks
    # ------------------------------------------------------------
    positive_sum = 9 * 255 * 127
    negative_sum = 9 * 255 * -128

    assert positive_sum == 291465
    assert negative_sum == -293760

    assert positive_sum > OUT_MAX
    assert negative_sum < OUT_MIN

    print("==========================================")
    print("TEST VECTOR GENERATION COMPLETE")
    print("==========================================")
    print(f"Cases generated : {case_count}")
    print(f"Output directory: {TEST_ROOT}")
    print("Output size      : 30 x 30")
    print()
    print("Signed arithmetic checks:")
    print(f"  255 * 127  = {255 * 127}")
    print(f"  255 * -128 = {255 * -128}")
    print(f"  positive 9-term sum = {positive_sum} -> +32767")
    print(f"  negative 9-term sum = {negative_sum} -> -32768")
    print()
    print("All generated expected values are signed decimal integers.")


if __name__ == "__main__":
    main()
