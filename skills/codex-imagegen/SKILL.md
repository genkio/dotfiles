---
name: codex-imagegen
description: Generate a high-quality raster image (photo, illustration, texture, background) with the local Codex CLI and save it to a file. Use whenever a task needs a generated image.
---

# Codex image generation

`scripts/codex-image` in this skill's directory runs one local `codex exec` turn with Codex's built-in image tool and saves exactly one PNG. It uses the signed-in ChatGPT account, so no API key is needed.

```sh
codex-image out.png --aspect 16:9 "A ferry crossing a misty harbor at dawn, watercolor"
codex-image out.png --aspect 9:16 -i style-ref.png -f prompt.txt
```

- Codex must be signed in (`~/.codex/auth.json`). If it isn't, ask the user to run `npx -y @openai/codex login`.
- An image takes one to three minutes. Run at most two at once.
- Describe the scene, subject, style, composition and palette, and say what each `-i` reference is for. Generated lettering is often garbled, so add text afterwards when you can.
- The size only approximates the aspect ratio (9:16 gave 941×1672). Crop or scale if exact pixels matter.
- Look at the image before using it. Regenerate under a new name if it has stray text or broken hands or faces.
- Run Codex locally only, never as a cloud task or share link.
