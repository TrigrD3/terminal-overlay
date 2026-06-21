# Terminal Overlay 🖥️⚡️

A zero-dependency, lag-free, floating status overlay for macOS `Terminal.app`. It visually differentiates your active terminal environments (e.g. Blue for Dev, Green for Staging, Red for Prod) using animated shapes or custom GIFs.

---

## 🌟 Key Features

* ☸️ **Kubernetes Context-Aware:** Automatically matches active `kubectl` cluster context substrings to switch environments dynamically.
* 🖥️ **Tab-Specific Separation:** Tracks and separates environments, styles, and sizes per individual terminal tab (TTY).
* ⚡️ **Zero-Lag Tracking:** Direct macOS `CGWindowList` API integration tracks active window geometry at 50Hz with 0% CPU footprint.
* 👾 **Interactive TUI:** Keyboard-navigable Terminal UI (`./terminal_overlay tui`) for toggling settings, cycling custom gifs, adjusting overlay size, and toggling daemon power.
* 🎨 **Custom GIFs Support:** Drop any `.gif` file into the `gifs/` directory and cycle through them interactively in the TUI.
* 🔒 **Automatic Hiding:** Hides instantly when switching active applications (Chrome, Safari, etc.) and shows when you return to `Terminal.app`.

---

## 📦 Installation

To install `terminal_overlay` using Homebrew:

```bash
# Add your custom Tap repository
brew tap yourusername/tap

# Install the application
brew install terminal-overlay
```

---

## 🚀 Usage

### Command-Line Arguments
```bash
Usage:
  terminal_overlay <command> [options]
  
Commands:
  start              Launch the overlay daemon in the background
  stop               Stop the running overlay daemon
  status             Show current daemon state and environment matching info
  tui                Open the interactive settings Terminal UI
  help, -h, --help   Show usage instructions screen
```

### Examples
* **Auto-switch based on Kubernetes context:**
  ```bash
  terminal_overlay start --env auto
  ```
* **Toggle settings interactively:**
  ```bash
  terminal_overlay tui
  ```
* **Check status & active contexts:**
  ```bash
  terminal_overlay status
  ```
* **Manually set size & cluster matches:**
  ```bash
  terminal_overlay config --size 140 --prod-k8s production-gke-cluster
  ```

---

## 🎨 Customizing GIFs

1. Create a `gifs/` folder inside the workspace.
2. Drop any `.gif` file into it.
3. Open `./terminal_overlay tui` and navigate to `Dev Env GIF`, `Staging Env GIF`, or `Prod Env GIF`.
4. Use **◀ / ▶ (Left / Right)** keys to cycle through your custom GIFs and hit **Exit** to save.

---

## ⚙️ How K8s Auto-Detection Works

When environment mode is set to `auto` (default), the overlay daemon polls your `~/.kube/config` context modification timestamps. Whenever you switch contexts using `kubectl config use-context <name>`:
1. It reads the new active context name.
2. It checks matches:
   * Contains **Prod Match** (e.g., `prod-cluster`) -> Switches to **Prod** style.
   * Contains **Staging Match** (e.g., `staging-cluster`) -> Switches to **Staging** style.
   * Contains **Dev Match** (e.g., `minikube`) -> Switches to **Dev** style.
3. If no match is found, it defaults to the **Dev** environment style.
