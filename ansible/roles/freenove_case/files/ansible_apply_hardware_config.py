#!/usr/bin/env python3
"""Apply Freenove app_config.json values directly to the expansion board."""

from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path
from typing import Any

from api_expansion import Expansion


LED_MODE_MAP = {
    0: 4,  # Rainbow
    1: 3,  # Breathing
    2: 2,  # Follow
    3: 1,  # Manual RGB
    5: 0,  # Close
}


def load_config(config_path: Path) -> dict[str, Any]:
    with config_path.open("r", encoding="utf-8") as config_file:
        return json.load(config_file)


def as_int(value: Any, key: str, minimum: int, maximum: int) -> int:
    try:
        parsed = int(value)
    except (TypeError, ValueError) as error:
        raise ValueError(f"{key} must be an integer") from error

    if parsed < minimum or parsed > maximum:
        raise ValueError(f"{key} must be between {minimum} and {maximum}")

    return parsed


def section(config: dict[str, Any], name: str) -> dict[str, Any]:
    value = config.get(name, {})
    if not isinstance(value, dict):
        raise ValueError(f"{name} must be a JSON object")
    return value


def read_state(expansion: Expansion) -> dict[str, Any]:
    state: dict[str, Any] = {
        "board_type": expansion.get_board_type(),
        "version": expansion.get_version(),
    }

    for state_key, reader_name in (
        ("led_mode", "get_led_mode"),
        ("all_led_color", "get_all_led_color"),
        ("fan_mode", "get_fan_mode"),
        ("fan_duty", "get_fan_duty"),
        ("fan_threshold", "get_fan_threshold"),
    ):
        reader = getattr(expansion, reader_name, None)
        if reader is None:
            continue
        try:
            state[state_key] = reader()
        except Exception as error:  # noqa: BLE001
            state[state_key] = f"read-error: {error}"

    return state


def color_matches(value: Any, expected: list[int]) -> bool:
    if not isinstance(value, list) or len(value) < 3:
        return False

    groups = [value[index:index + 3] for index in range(0, len(value), 3)]
    return all(group == expected for group in groups if len(group) == 3)


def apply_led(
    expansion: Expansion,
    config: dict[str, Any],
    before: dict[str, Any],
    operations: list[str],
    warnings: list[str],
) -> bool:
    led = section(config, "LED")
    mode = as_int(led.get("mode", 0), "LED.mode", 0, 5)
    rgb = [
        as_int(led.get("red_value", 0), "LED.red_value", 0, 255),
        as_int(led.get("green_value", 0), "LED.green_value", 0, 255),
        as_int(led.get("blue_value", 255), "LED.blue_value", 0, 255),
    ]

    if led.get("is_run_on_startup", False):
        warnings.append("LED task is enabled; task_led.py can override LED mode and color.")

    if mode == 4:
        warnings.append("LED mode 4 is Freenove custom-script mode; no static LED mode is applied.")
        return False

    desired_mode = LED_MODE_MAP[mode]
    changed = False

    if before.get("led_mode") != desired_mode:
        expansion.set_led_mode(desired_mode)
        operations.append(f"set_led_mode={desired_mode}")
        changed = True

    if mode in (1, 2, 3, 5) and not color_matches(before.get("all_led_color"), rgb):
        expansion.set_all_led_color(*rgb)
        operations.append(f"set_all_led_color={rgb}")
        changed = True

    return changed


def apply_fan_fnk0100(
    expansion: Expansion,
    fan: dict[str, Any],
    before: dict[str, Any],
    operations: list[str],
    warnings: list[str],
) -> bool:
    mode = as_int(fan.get("mode", 0), "Fan.mode", 0, 3)
    changed = False

    if mode == 0:
        desired_mode = 2
        desired_threshold = [
            as_int(fan.get("mode2_low_temp_threshold", 30), "Fan.mode2_low_temp_threshold", 0, 255),
            as_int(fan.get("mode2_high_temp_threshold", 50), "Fan.mode2_high_temp_threshold", 0, 255),
        ]
        if before.get("fan_mode") != desired_mode:
            expansion.set_fan_mode(desired_mode)
            operations.append(f"set_fan_mode={desired_mode}")
            changed = True
        if before.get("fan_threshold") != desired_threshold:
            expansion.set_fan_temp_mode_threshold(*desired_threshold)
            operations.append(f"set_fan_temp_mode_threshold={desired_threshold}")
            changed = True
    elif mode == 1:
        desired_mode = 1
        desired_duty = [
            as_int(fan.get("mode1_fan_group1", 75), "Fan.mode1_fan_group1", 0, 255),
            as_int(fan.get("mode1_fan_group2", 75), "Fan.mode1_fan_group2", 0, 255),
        ]
        if before.get("fan_mode") != desired_mode:
            expansion.set_fan_mode(desired_mode)
            operations.append(f"set_fan_mode={desired_mode}")
            changed = True
        if before.get("fan_duty") != desired_duty:
            expansion.set_fan_duty(*desired_duty)
            operations.append(f"set_fan_duty={desired_duty}")
            changed = True
    elif mode == 2:
        warnings.append("FNK0100 fan mode 2 is custom-script mode; no static fan mode is applied.")
    elif mode == 3:
        desired_mode = 0
        desired_duty = [0, 0]
        if before.get("fan_mode") != desired_mode:
            expansion.set_fan_mode(desired_mode)
            operations.append(f"set_fan_mode={desired_mode}")
            changed = True
        if before.get("fan_duty") != desired_duty:
            expansion.set_fan_duty(*desired_duty)
            operations.append("set_fan_duty=[0, 0]")
            changed = True

    return changed


def apply_fan_fnk0107(
    expansion: Expansion,
    fan: dict[str, Any],
    before: dict[str, Any],
    operations: list[str],
    warnings: list[str],
) -> bool:
    mode = as_int(fan.get("mode", 0), "Fan.mode", 0, 4)
    changed = False

    if mode == 0:
        desired_mode = 2
        desired_threshold = [
            as_int(fan.get("mode2_low_temp_threshold", 30), "Fan.mode2_low_temp_threshold", 0, 255),
            as_int(fan.get("mode2_high_temp_threshold", 50), "Fan.mode2_high_temp_threshold", 0, 255),
            as_int(fan.get("mode2_temp_schmitt", 3), "Fan.mode2_temp_schmitt", 0, 255),
        ]
        if before.get("fan_mode") != desired_mode:
            expansion.set_fan_mode(desired_mode)
            operations.append(f"set_fan_mode={desired_mode}")
            changed = True
        if before.get("fan_threshold") != desired_threshold:
            expansion.set_fan_temp_mode_threshold(*desired_threshold)
            operations.append(f"set_fan_temp_mode_threshold={desired_threshold}")
            changed = True
    elif mode == 1:
        desired_mode = 3
        if before.get("fan_mode") != desired_mode:
            expansion.set_fan_mode(desired_mode)
            operations.append(f"set_fan_mode={desired_mode}")
            changed = True
    elif mode == 2:
        desired_mode = 1
        desired_duty = [
            as_int(fan.get("mode1_fan_group1", 75), "Fan.mode1_fan_group1", 0, 255),
            as_int(fan.get("mode1_fan_group2", 75), "Fan.mode1_fan_group2", 0, 255),
            as_int(fan.get("mode1_fan_group3", 75), "Fan.mode1_fan_group3", 0, 255),
        ]
        if before.get("fan_mode") != desired_mode:
            expansion.set_fan_mode(desired_mode)
            operations.append(f"set_fan_mode={desired_mode}")
            changed = True
        if before.get("fan_duty") != desired_duty:
            expansion.set_fan_duty(*desired_duty)
            operations.append(f"set_fan_duty={desired_duty}")
            changed = True
    elif mode == 3:
        warnings.append("FNK0107 fan mode 3 is custom-script mode; no static fan mode is applied.")
    elif mode == 4:
        desired_mode = 0
        desired_duty = [0, 0, 0]
        if before.get("fan_mode") != desired_mode:
            expansion.set_fan_mode(desired_mode)
            operations.append(f"set_fan_mode={desired_mode}")
            changed = True
        if before.get("fan_duty") != desired_duty:
            expansion.set_fan_duty(*desired_duty)
            operations.append("set_fan_duty=[0, 0, 0]")
            changed = True

    return changed


def apply_fan(
    expansion: Expansion,
    config: dict[str, Any],
    before: dict[str, Any],
    operations: list[str],
    warnings: list[str],
) -> bool:
    fan = section(config, "Fan")
    board_type = before.get("board_type")

    if fan.get("is_run_on_startup", False):
        warnings.append("Fan task is enabled; task_fan.py can override fan mode, duty, and thresholds.")

    if board_type == "FNK0100":
        return apply_fan_fnk0100(expansion, fan, before, operations, warnings)
    if board_type == "FNK0107":
        return apply_fan_fnk0107(expansion, fan, before, operations, warnings)

    raise ValueError(f"Unsupported Freenove board type: {board_type}")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", type=Path, default=Path("app_config.json"))
    flash_group = parser.add_mutually_exclusive_group()
    flash_group.add_argument("--save-flash", action="store_true")
    flash_group.add_argument("--no-save-flash", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    config = load_config(args.config)
    operations: list[str] = []
    warnings: list[str] = []

    try:
        expansion = Expansion()
        before = read_state(expansion)
        changed = apply_led(expansion, config, before, operations, warnings)
        changed = apply_fan(expansion, config, before, operations, warnings) or changed

        if changed and args.save_flash:
            expansion.set_save_flash(1)
            operations.append("set_save_flash=1")

        time.sleep(0.2)
        after = read_state(expansion)
        expansion.end()
    except Exception as error:  # noqa: BLE001
        print(json.dumps({"failed": True, "error": str(error)}))
        return 1

    print(json.dumps({
        "changed": changed,
        "operations": operations,
        "warnings": warnings,
        "before": before,
        "after": after,
    }, sort_keys=True))
    return 0


if __name__ == "__main__":
    sys.exit(main())
