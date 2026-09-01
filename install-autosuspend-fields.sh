#!/usr/bin/env bash
set -Eeuo pipefail

# ============================================================
# Auto Suspend - Tambah Field Expiration Date (datetime) ke
# form Create Server & Edit Server
# ============================================================

PTERODACTYL="/var/www/pterodactyl"
BACKUP_DIR="/root/pterodactyl-autosuspend-field-backup-$(date +%Y%m%d-%H%M%S)"

log() { printf '[AUTOSUSPEND-FIELD] %s\n' "$*"; }
die() { printf '[AUTOSUSPEND-FIELD] ERROR: %s\n' "$*" >&2; exit 1; }

[[ "${EUID}" -eq 0 ]] || die "Jalankan sebagai root."
[[ -f "$PTERODACTYL/artisan" ]] || die "Pterodactyl tidak ditemukan di $PTERODACTYL."

backup_file() {
    local file="$1"
    if [[ -f "$file" ]]; then
        mkdir -p "$BACKUP_DIR"
        cp -a "$file" "$BACKUP_DIR/$(basename "$file")"
    fi
}

# ========================================================
# CREATE SERVER
# ========================================================
patch_create_form() {
    local file="$PTERODACTYL/resources/views/admin/servers/new.blade.php"
    [[ -f "$file" ]] || { log "PERINGATAN: $file tidak ditemukan, skip."; return; }

    if grep -Fq 'name="exp_date"' "$file"; then
        log "Field exp_date sudah ada di Create Server, skip."
        return
    fi

    backup_file "$file"

    if grep -Fq 'Email address of the Server Owner.' "$file"; then
        python3 - "$file" <<'PY'
import re
import sys

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as f:
    text = f.read()

anchor = "Email address of the Server Owner."
idx = text.find(anchor)
if idx == -1:
    raise SystemExit("Anchor tidak ditemukan.")

close_idx = text.find("</div>", idx)
if close_idx == -1:
    raise SystemExit("Penutup div tidak ditemukan.")

insert_at = close_idx + len("</div>")

new_field = '''

                        <div class="form-group">
                            <label for="exp_date">Expiration date &amp; time</label>
                            <input type="datetime-local" class="form-control" id="expiration" name="exp_date" value="{{ old('exp_date') }}" placeholder="Expiration Date">
                            <p class="small text-muted no-margin">Server akan disuspend otomatis begitu tanggal &amp; jam ini terlewati. Kosongkan jika ingin server permanen.</p>
                        </div>'''

text = text[:insert_at] + new_field + text[insert_at:]

with open(path, "w", encoding="utf-8") as f:
    f.write(text)
PY
        log "Field Expiration Date berhasil ditambahkan ke Create Server."
    else
        log "PERINGATAN: anchor 'Email address of the Server Owner.' tidak ditemukan."
        log "Kirim isi new.blade.php ke saya untuk dibuatkan patch manual."
    fi
}

# ========================================================
# EDIT SERVER
# ========================================================
patch_edit_form() {
    local file="$PTERODACTYL/resources/views/admin/servers/view/details.blade.php"
    [[ -f "$file" ]] || { log "PERINGATAN: $file tidak ditemukan, skip."; return; }

    if grep -Fq 'name="exp_date"' "$file"; then
        log "Field exp_date sudah ada di Edit Server, skip."
        return
    fi

    backup_file "$file"

    if grep -Fq 'Character limits:' "$file"; then
        python3 - "$file" <<'PY'
import sys

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as f:
    text = f.read()

anchor = "Character limits:"
idx = text.find(anchor)
if idx == -1:
    raise SystemExit("Anchor tidak ditemukan.")

close_idx = text.find("</div>", idx)
if close_idx == -1:
    raise SystemExit("Penutup div tidak ditemukan.")

insert_at = close_idx + len("</div>")

new_field = '''

                    <div class="form-group">
                        <label for="exp_date" class="control-label">Expiration date &amp; time</label>
                        <input type="datetime-local" name="exp_date" value="{{ old('exp_date', optional($server->exp_date)->format('Y-m-d\\TH:i')) }}" class="form-control" />
                        <p class="text-muted small">Server akan disuspend otomatis begitu tanggal &amp; jam ini terlewati. Kosongkan jika ingin server permanen.</p>
                    </div>'''

text = text[:insert_at] + new_field + text[insert_at:]

with open(path, "w", encoding="utf-8") as f:
    f.write(text)
PY
        log "Field Expiration Date berhasil ditambahkan ke Edit Server."
    else
        log "PERINGATAN: anchor 'Character limits:' tidak ditemukan."
        log "Kirim isi details.blade.php ke saya untuk dibuatkan patch manual."
    fi
}

clear_cache() {
    cd "$PTERODACTYL"
    log "Membersihkan cache..."
    php artisan route:clear
    php artisan config:clear
    php artisan view:clear
    php artisan cache:clear
    chown -R www-data:www-data "$PTERODACTYL"
}

main() {
    log "=============================================="
    log "TAMBAH FIELD EXPIRATION DATE KE CREATE/EDIT SERVER"
    log "=============================================="

    patch_create_form
    patch_edit_form
    clear_cache

    log "=============================================="
    log "SELESAI"
    log "=============================================="
    log "Cek di Admin -> Servers -> Create, dan Admin -> Servers -> pilih server -> Manage -> Details."
    log "Backup (jika ada perubahan) di: $BACKUP_DIR"
}

main "$@"
