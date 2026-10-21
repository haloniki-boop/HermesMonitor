"""Small noninteractive adapter to Hermes's canonical provider/model switch."""
import contextlib
import io
import json
import sys
from pathlib import Path


def main() -> int:
    probe = len(sys.argv) == 2 and sys.argv[1] == "--probe"
    if not probe and len(sys.argv) != 3:
        print(json.dumps({"ok": False, "error": "expected provider and model"}))
        return 2
    provider, model = ("", "") if probe else (value.strip() for value in sys.argv[1:])
    if not probe and (not provider or not model or any(c in provider + model for c in "\r\n")):
        print(json.dumps({"ok": False, "error": "invalid provider or model"}))
        return 2

    hermes_source = Path.home() / ".hermes" / "hermes-agent"
    sys.path.insert(0, str(hermes_source))
    try:
        with contextlib.redirect_stdout(io.StringIO()):
            from hermes_cli.inventory import load_picker_context
            from hermes_cli.model_switch import switch_model, persist_model_selection

            current = load_picker_context()
            if probe:
                result = None
            else:
                result = switch_model(
                    model,
                    current_provider=current.current_provider,
                    current_model=current.current_model,
                    current_base_url=current.current_base_url,
                    is_global=True,
                    explicit_provider=provider,
                    user_providers=current.user_providers,
                    custom_providers=current.custom_providers,
                )
                if result.success:
                    persist_model_selection(result)
        if probe:
            print(json.dumps({"ok": True, "provider": current.current_provider, "model": current.current_model}))
            return 0
        if not result.success:
            print(json.dumps({"ok": False, "error": result.error_message or "Hermes rejected the selection"}))
            return 1
        print(json.dumps({"ok": True, "provider": result.target_provider, "model": result.new_model}))
        return 0
    except Exception as exc:
        print(json.dumps({"ok": False, "error": str(exc)}))
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
