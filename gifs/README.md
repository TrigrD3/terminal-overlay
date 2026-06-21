# Terminal Pet GIFs Directory

Place your custom animated `.gif` files in this directory.

## Recommended setup:
- `gifs/prod.gif` (e.g. flashing warning sign or red siren)
- `gifs/staging.gif` (e.g. calm green sleeping pet)
- `gifs/dev.gif` (e.g. blue bouncing character)

## Usage:
Configure the pet to use a GIF in this directory via relative path:
```bash
./terminal_pet config --gif gifs/prod.gif
```
