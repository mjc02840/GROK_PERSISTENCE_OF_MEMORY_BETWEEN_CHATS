# chat-persist-fossil

One-click plain-text capture of AI chats → auto-versioned in Fossil SCM

Captures plain selectable text from AI chat pages (Grok, Claude, etc.) via bookmarklet → auto-commits to Fossil SCM → versioned, searchable, syncable.

## Features
- One-click bookmarklet: downloads .txt with URL + timestamp + page text
- Background watcher: auto-commits new/modified .txt files after delay
- Panic alias for instant commit
- Runs as systemd user service
- MIT licensed

## Requirements
- Linux (Debian 12+)
- Fossil SCM
- inotify-tools
- Chrome browser

## Quick Setup
1. Clone repo
2. cd into directory
3. chmod +x chat-watcher.sh
4. Run once (creates Fossil repo):
   ./chat-watcher.sh &
5. Set up systemd service (see below)

## Systemd Service
mkdir -p ~/.config/systemd/user
cp g2rok-watcher.service.example ~/.config/systemd/user/g2rok-watcher.service
systemctl --user daemon-reload
systemctl --user enable --now g2rok-watcher.service

## Aliases (add to ~/.bashrc)
alias chat-start='systemctl --user start g2rok-watcher.service && chat-status'
alias chat-status='systemctl --user status g2rok-watcher.service'
alias chat-log='journalctl --user -u g2rok-watcher.service -f'

## Why Fossil?
- Single-file repo → easy backup/sync
- Built-in UI: fossil ui
- Distributed & offline-first

MIT licensed — see LICENSE.

Contributions welcome!
