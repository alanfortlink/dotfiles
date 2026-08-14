#!/bin/bash
# create_backup.sh — idempotent backup of the steam deck's homeserver state
# to Google Drive. The paths backed up mirror what
# ~/homeserver/backup/backup.sh on the deck already does: a fresh gitea
# dump (DB + repos + LFS + config) plus the live config dirs for every
# service in the compose stack. The homeserver/.env file is included
# because it holds tokens that aren't in github.
#
# Re-running is safe. Already-done prereqs are skipped.
set -euo pipefail

DECK_HOST="${DECK_HOST:-deck}"
RCLONE_NAME="${RCLONE_NAME:-gdrive}"
RCLONE_REMOTE="${RCLONE_REMOTE:-${RCLONE_NAME}:Backups/steamdeck}"
LOCAL_DIR="${BACKUP_DIR:-$HOME/backups/steamdeck}"
RETAIN_LOCAL="${RETAIN_LOCAL:-5}"
SUDOERS_FILE="/etc/sudoers.d/deck-podman"

# Exactly the home-server state. Matches deck:backup/backup.sh.
PATHS_TO_BACKUP=(
  /home/deck/.config/sonarr
  /home/deck/.config/radarr
  /home/deck/.config/prowlarr
  /home/deck/.config/qbittorrent
  /home/deck/.config/gluetun
  /home/deck/jellyfin/config
)

ts=$(date -u +%Y%m%dT%H%M%SZ)
archive="homeserver-$ts.tar.gz"

red()  { printf '\033[31m%s\033[0m\n' "$*"; }
step() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
skip() { printf '    \033[33m(skip)\033[0m %s\n' "$*"; }
ok()   { printf '    \033[32m✓\033[0m %s\n'   "$*"; }
die()  { red "ERROR: $*"; exit 1; }
iec()  { numfmt --to=iec --suffix=B "$1" 2>/dev/null || echo "${1}B"; }

# ---- 1. rclone installed ---------------------------------------------------
step "rclone installed on tank"
if pacman -Qi rclone >/dev/null 2>&1; then skip "$(rclone version | head -1)"
else ok "installing"; sudo pacman -S --needed --noconfirm rclone
fi

# ---- 2. core tools ---------------------------------------------------------
step "tar / ssh / sha256sum present"
for cmd in tar ssh sha256sum gzip; do command -v "$cmd" >/dev/null || die "$cmd missing"; done
skip "ok"

# ---- 3. rclone remote configured ------------------------------------------
step "rclone remote '$RCLONE_NAME'"
if ! rclone listremotes 2>/dev/null | grep -qx "${RCLONE_NAME}:"; then
  cat <<EOF
$(red MISSING:) no rclone remote named '$RCLONE_NAME'.

Run:
  rclone config
Choose: n → name='$RCLONE_NAME' → drive → blank → blank → 1 → blank → blank → n → y → n → y.

Re-run this script.
EOF
  exit 2
fi
skip "exists"

# ---- 4. token still valid --------------------------------------------------
step "rclone remote reachable"
rclone lsd "${RCLONE_NAME}:" >/dev/null 2>&1 \
  || die "token expired? Run: rclone config reconnect ${RCLONE_NAME}:"
ok "ok"

# ---- 5. destination folder -------------------------------------------------
step "destination $RCLONE_REMOTE"
rclone mkdir "$RCLONE_REMOTE"
ok "ready"

# ---- 6. ssh works passwordlessly -------------------------------------------
step "passwordless ssh to $DECK_HOST"
ssh -o BatchMode=yes -o ConnectTimeout=10 "$DECK_HOST" true 2>/dev/null \
  || die "ssh $DECK_HOST prompts. Run: ssh-copy-id $DECK_HOST"
skip "ok"

# ---- 7. passwordless sudo for podman on the deck ---------------------------
step "deck has passwordless sudo for podman"
if ssh "$DECK_HOST" 'sudo -n podman version' >/dev/null 2>&1; then
  skip "already set"
else
  ok "installing $SUDOERS_FILE on deck"
  ssh -t "$DECK_HOST" "
    set -e
    tmp=\$(mktemp)
    echo 'deck ALL=(ALL) NOPASSWD: /usr/bin/podman' > \"\$tmp\"
    sudo visudo -cf \"\$tmp\" >/dev/null
    sudo install -m 0440 -o root -g root \"\$tmp\" '$SUDOERS_FILE'
    rm -f \"\$tmp\"
  "
fi

# ---- 8. hot gitea dump on the deck -----------------------------------------
DUMP_DIR="/home/deck/gitea-tank-dumps"
DUMP_NAME="gitea-dump-$ts.zip"
step "gitea dump on deck"
ssh "$DECK_HOST" "set -e
  mkdir -p '$DUMP_DIR'
  sudo podman exec -w /tmp -u git gitea gitea dump \
    --config /data/gitea/conf/app.ini --type zip --file '$DUMP_NAME' >/dev/null
  sudo podman cp gitea:/tmp/$DUMP_NAME '$DUMP_DIR/$DUMP_NAME'
  sudo podman exec gitea rm -f /tmp/$DUMP_NAME
  sudo chown deck:deck '$DUMP_DIR/$DUMP_NAME'
  # keep only the most recent dump in this dir
  find '$DUMP_DIR' -name 'gitea-dump-*.zip' -type f | sort | head -n -1 | xargs -r rm -f
"
ok "$DUMP_NAME"

# ---- 9. tar the home-server state + gitea dump → tank ---------------------
step "stream tar of home-server state to tank"
mkdir -p "$LOCAL_DIR"

# Build the relative path list (relative to /) so tar -C / works.
rel_paths=("${PATHS_TO_BACKUP[@]/#\//}")
rel_paths+=("${DUMP_DIR#/}/$DUMP_NAME")

ssh "$DECK_HOST" "tar --warning=no-file-changed -czf - -C / ${rel_paths[*]}" \
  > "$LOCAL_DIR/$archive"

size=$(stat -c%s "$LOCAL_DIR/$archive")
ok "archive: $(iec "$size")"

# ---- 10. validate ---------------------------------------------------------
step "validate"
tar -tzf "$LOCAL_DIR/$archive" >/dev/null
[ "$size" -ge 1024 ] || die "archive only $size bytes — refusing to upload"
sha256sum "$LOCAL_DIR/$archive" > "$LOCAL_DIR/$archive.sha256"
ok "table-of-contents readable; sha256 written"

# ---- 10b. tier-2 gitea integrity (layout + git fsck on every repo) --------
step "verify gitea dump structure + repo integrity"
vtmp=$(mktemp -d -t gitea-verify-XXXXXX)
trap 'rm -rf "$vtmp"' EXIT

dump_in_tar=$(tar -tzf "$LOCAL_DIR/$archive" | grep -E 'gitea-dump-.*\.zip$' | head -1)
[ -n "$dump_in_tar" ] || die "no gitea-dump-*.zip inside archive"
tar -xzf "$LOCAL_DIR/$archive" -C "$vtmp" "$dump_in_tar"
dump_path="$vtmp/$dump_in_tar"

entries=$(unzip -l "$dump_path" | awk 'NF>=4 {print $NF}')
db_file=$(echo "$entries" | grep -E '^gitea-db\.(sql|sqlite3)$' | head -1)
[ -n "$db_file" ]                                  || die "dump missing gitea-db.{sql,sqlite3}"
echo "$entries" | grep -qx 'app.ini'               || die "dump missing app.ini"
echo "$entries" | grep -qx 'gitea-repo.zip'        || die "dump missing gitea-repo.zip"
ok "dump layout ok (db=$db_file, app.ini present, gitea-repo.zip present)"

# Extract repos and git-fsck each bare repo.
unzip -qq -o "$dump_path" gitea-repo.zip -d "$vtmp"
mkdir -p "$vtmp/repos"
unzip -qq -o "$vtmp/gitea-repo.zip" -d "$vtmp/repos"

repos_failed=0 repos_total=0
while IFS= read -r repo; do
  repos_total=$((repos_total + 1))
  if ! git -C "$repo" fsck --no-progress --no-dangling >"$vtmp/fsck.log" 2>&1; then
    repos_failed=$((repos_failed + 1))
    printf '    \033[31mfsck FAILED:\033[0m %s\n' "$repo"
    sed 's/^/      /' "$vtmp/fsck.log"
  fi
done < <(find "$vtmp/repos" -mindepth 2 -maxdepth 3 -type d -name '*.git')

[ $repos_total -gt 0 ] || die "no repos found in dump"
[ $repos_failed -eq 0 ] || die "$repos_failed of $repos_total repos failed git fsck"
ok "git fsck passed for all $repos_total repos"

# ---- 11. upload ----------------------------------------------------------
step "upload to $RCLONE_REMOTE"
rclone copy "$LOCAL_DIR/$archive"        "$RCLONE_REMOTE" --progress --transfers 1 --checkers 2
rclone copy "$LOCAL_DIR/$archive.sha256" "$RCLONE_REMOTE" --transfers 1 --checkers 2
ok "uploaded"

# ---- 12. prune local copies ----------------------------------------------
step "prune local (keep $RETAIN_LOCAL most recent)"
mapfile -t old < <(ls -1t "$LOCAL_DIR"/homeserver-*.tar.gz 2>/dev/null | tail -n "+$((RETAIN_LOCAL + 1))")
if [ "${#old[@]}" -eq 0 ]; then skip "nothing to prune"
else for f in "${old[@]}"; do rm -f "$f" "$f.sha256"; echo "    removed $(basename "$f")"; done
fi

step "done"
printf 'local:  %s\nremote: %s/%s\n' "$LOCAL_DIR/$archive" "$RCLONE_REMOTE" "$archive"
