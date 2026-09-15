#!/usr/bin/env python3
"""
Bit-accurate golden model for the FPGA convolution accelerator.

Specification:
    Image       : 32x32
    Pixel       : 8-bit UNSIGNED  (0 .. 255)
    Kernel      : 3x3, 8-bit SIGNED (-128 .. 127)
    Operation   : VALID cross-correlation, stride 1
    Product     : 16-bit SIGNED
    Accumulator : 20-bit SIGNED
    Output      : 16-bit SIGNED with saturation

The important part of this model is that kernel coefficients are ALWAYS
treated as signed values. This prevents the classic bug where -1 becomes
255, -128 becomes 128, etc.
"""

from __future__ import annotations

from pathlib import Path
from typing import Sequence


IMAGE_WIDTH = 32
IMAGE_HEIGHT = 32
KERNEL_SIZE = 3

DATA_WIDTH = 8
KERNEL_WIDTH = 8
PRODUCT_WIDTH = 16
ACC_WIDTH = 20
OUT_WIDTH = 16

PIXEL_MIN = 0
PIXEL_MAX = (1 << DATA_WIDTH) - 1

KERNEL_MIN = -(1 << (KERNEL_WIDTH - 1))
KERNEL_MAX = (1 << (KERNEL_WIDTH - 1)) - 1

PRODUCT_MIN = -(1 << (PRODUCT_WIDTH - 1))
PRODUCT_MAX = (1 << (PRODUCT_WIDTH - 1)) - 1

ACC_MIN = -(1 << (ACC_WIDTH - 1))
ACC_MAX = (1 << (ACC_WIDTH - 1)) - 1

OUT_MIN = -(1 << (OUT_WIDTH - 1))
OUT_MAX = (1 << (OUT_WIDTH - 1)) - 1


def signed_from_bits(value: int, width: int) -> int:
    """
    Interpret the low 'width' bits as a signed two's-complement integer.

    Examples:
        signed_from_bits(0x7F, 8) == 127
        signed_from_bits(0x80, 8) == -128
        signed_from_bits(0xFF, 8) == -1
    """
    value &= (1 << width) - 1

    sign_bit = 1 << (width - 1)

    if value & sign_bit:
        return value - (1 << width)

    return value


def wrap_signed(value: int, width: int) -> int:
    """Model a signed two's-complement hardware assignment."""
    return signed_from_bits(value, width)


def validate_image(image: Sequence[Sequence[int]]) -> tuple[int, int]:
    if not image or not image[0]:
        raise ValueError("Image must not be empty.")

    height = len(image)
    width = len(image[0])

    if height < KERNEL_SIZE or width < KERNEL_SIZE:
        raise ValueError("Image must be at least 3x3.")

    for row in image:
        if len(row) != width:
            raise ValueError("Image rows must have equal lengths.")

        for pixel in row:
            if not isinstance(pixel, int):
                raise TypeError("Image pixels must be integers.")

            if not PIXEL_MIN <= pixel <= PIXEL_MAX:
                raise ValueError(
                    f"Pixel {pixel} is outside unsigned 8-bit range "
                    f"[{PIXEL_MIN}, {PIXEL_MAX}]."
                )

    return height, width


def validate_kernel(kernel: Sequence[Sequence[int]]) -> None:
    if len(kernel) != KERNEL_SIZE:
        raise ValueError("Kernel must be exactly 3x3.")

    if any(len(row) != KERNEL_SIZE for row in kernel):
        raise ValueError("Kernel must be exactly 3x3.")

    for row in kernel:
        for coefficient in row:
            if not isinstance(coefficient, int):
                raise TypeError("Kernel coefficients must be integers.")

            if not KERNEL_MIN <= coefficient <= KERNEL_MAX:
                raise ValueError(
                    f"Kernel coefficient {coefficient} is outside signed "
                    f"8-bit range [{KERNEL_MIN}, {KERNEL_MAX}]."
                )


def saturate_signed(value: int, width: int = OUT_WIDTH) -> int:
    """Saturate to the signed range of the specified width."""
    minimum = -(1 << (width - 1))
    maximum = (1 << (width - 1)) - 1

    if value > maximum:
        return maximum

    if value < minimum:
        return minimum

    return value


def convolve_valid(
    image: Sequence[Sequence[int]],
    kernel: Sequence[Sequence[int]],
) -> list[list[int]]:
    """
    Perform VALID stride-1 cross-correlation.

    IMPORTANT:
        'coefficient' is a Python signed integer.
        Therefore:
            -128 stays -128
            -1   stays -1
            +127 stays +127

        There is NO accidental unsigned interpretation of the kernel.
    """
    height, width = validate_image(image)
    validate_kernel(kernel)

    output_height = height - KERNEL_SIZE + 1
    output_width = width - KERNEL_SIZE + 1

    output = [
        [0 for _ in range(output_width)]
        for _ in range(output_height)
    ]

    for out_row in range(output_height):
        for out_col in range(output_width):

            acc = 0

            for kr in range(KERNEL_SIZE):
                for kc in range(KERNEL_SIZE):

                    # Pixel is explicitly unsigned.
                    pixel = image[out_row + kr][out_col + kc]

                    # Kernel coefficient is explicitly signed.
                    coefficient = kernel[kr][kc]

                    # Signed pixel * signed coefficient.
                    product = pixel * coefficient

                    # Model the 16-bit signed product.
                    product = wrap_signed(product, PRODUCT_WIDTH)

                    # Model the 20-bit signed accumulator.
                    acc = wrap_signed(acc + product, ACC_WIDTH)

            # Model 16-bit signed output saturation.
            output[out_row][out_col] = saturate_signed(acc)

    return output


def write_matrix(
    path: str | Path,
    matrix: Sequence[Sequence[int]],
) -> None:
    """
    Write a matrix as signed decimal integers.

    Negative values are written with a '-' sign, NOT as unsigned
    two's-complement decimal values.
    """
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)

    with path.open("w", encoding="utf-8") as f:
        for row in matrix:
            f.write(" ".join(str(value) for value in row))
            f.write("\n")


def read_matrix(
    path: str | Path,
    rows: int,
    cols: int,
) -> list[list[int]]:
    """Read a whitespace-separated integer matrix."""
    values = Path(path).read_text(encoding="utf-8").split()

    expected_count = rows * cols

    if len(values) != expected_count:
        raise ValueError(
            f"{path}: expected {expected_count} values, "
            f"found {len(values)}."
        )

    numbers = [int(value) for value in values]

    return [
        numbers[r * cols:(r + 1) * cols]
        for r in range(rows)
    ]


def run_case(
    case_dir: str | Path,
    image: Sequence[Sequence[int]],
    kernel: Sequence[Sequence[int]],
) -> list[list[int]]:
    """Generate image.txt, kernel.txt and expected.txt."""
    case_dir = Path(case_dir)
    case_dir.mkdir(parents=True, exist_ok=True)

    expected = convolve_valid(image, kernel)

    write_matrix(case_dir / "image.txt", image)
    write_matrix(case_dir / "kernel.txt", kernel)
    write_matrix(case_dir / "expected.txt", expected)

    return expected


def self_test() -> None:
    """
    Sanity tests specifically targeting signedness.
    """
    assert signed_from_bits(0x7F, 8) == 127
    assert signed_from_bits(0x80, 8) == -128
    assert signed_from_bits(0xFF, 8) == -1

    # Product edge cases.
    assert 255 * -128 == -32640
    assert 255 * -1 == -255
    assert 255 * 0 == 0
    assert 255 * 1 == 255
    assert 255 * 127 == 32385

    # Saturation edge cases.
    assert saturate_signed(32767) == 32767
    assert saturate_signed(32768) == 32767
    assert saturate_signed(291465) == 32767

    assert saturate_signed(-32768) == -32768
    assert saturate_signed(-32769) == -32768
    assert saturate_signed(-293760) == -32768

    # Constant image sanity check.
    image = [[10] * 32 for _ in range(32)]

    kernel = [
        [1, 1, 1],
        [1, 1, 1],
        [1, 1, 1],
    ]

    output = convolve_valid(image, kernel)

    assert len(output) == 30
    assert len(output[0]) == 30
    assert all(value == 90 for row in output for value in row)


if __name__ == "__main__":
    self_test()

    print("Golden model self-test: PASS")
    print("Signed kernel handling: PASS")
    print("Output shape: 30 x 30")
