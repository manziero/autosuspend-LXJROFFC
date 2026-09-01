#!/usr/bin/env bash
set -Eeuo pipefail

# ============================================================
# Auto Suspend - Per Server Date + Time (bulan/tanggal/jam/menit)
# Narik migration dari GitHub kamu, ubah exp_date jadi datetime,
# ubah form Create/Edit Server jadi datetime-local,
# sederhanakan scheduler Kernel.php
# ============================================================

# >>>> EDIT DULU BARIS INI SESUAI REPO GITHUB KAMU <<<<
MIGRATION_URL="https://raw.githubusercontent.com/manziero/autosuspend-LXJROFFC/main/exp_date_to_datetime_migration.php"

PTERODACTYL="/var/www/pterodactyl"
BACKUP_DIR="/root/pterodactyl-autosuspend-datetime-backup-$(date +%Y%m%d-%H%M%S)"

log() { printf '[AUTOSUSPEND-DATETIME] %s\n' "$*"; }
die() { printf '[AUTOSUSPEND-DATETIME] ERROR: %s\n' "$*" >&2; exit 1; }

[[ "${EUID}" -eq 0 ]] || die "Jalankan sebagai root."
[[ -f "$PTERODACTYL/artisan" ]] || die "Pterodactyl tidak ditemukan di $PTERODACTYL."

backup_file() {
    local file="$1"
    if [[ -f "$file" ]]; then
        mkdir -p "$BACKUP_DIR"
        cp -a "$file" "$BACKUP_DIR/$(basename "$file")"
    fi
}

download_migration() {
    local target="$PTERODACTYL/database/migrations/$(date +%Y_%m_%d_%H%M%S)_exp_date_to_datetime.php"

    log "Mengunduh migration exp_date -> datetime..."
    curl -fsSL "$MIGRATION_URL" -o "$target"

    [[ -s "$target" ]] || die "Gagal mengunduh migration (cek URL GitHub)."
    log "Migration disimpan di: $target"
}

patch_create_form() {
    local file="$PTERODACTYL/resources/views/admin/servers/new.blade.php"
    [[ -f "$file" ]] || { log "PERINGATAN: $file tidak ditemukan, skip."; return; }

    backup_file "$file"

    if grep -Fq 'name="exp_date"' "$file"; then
        if grep -Fq 'type="date" class="form-control" id="expiration" name="exp_date"' "$file"; then
            sed -i \
                's|type="date" class="form-control" id="expiration" name="exp_date" value="{{ old('"'"'exp_date'"'"') }}"|type="datetime-local" class="form-control" id="expiration" name="exp_date" value="{{ old('"'"'exp_date'"'"') }}"|' \
                "$file"
            log "Form Create Server: input exp_date diubah ke datetime-local."
        else
            log "PERINGATAN: pola input exp_date di Create Server tidak cocok persis, cek manual."
        fi
    else
        log "PERINGATAN: field exp_date tidak ditemukan di Create Server."
    fi
}

patch_edit_form() {
    local file="$PTERODACTYL/resources/views/admin/servers/view/details.blade.php"
    [[ -f "$file" ]] || { log "PERINGATAN: $file tidak ditemukan, skip."; return; }

    backup_file "$file"

    if grep -Fq 'name="exp_date"' "$file"; then
        if grep -Fq 'type="date" name="exp_date"' "$file"; then
            sed -i \
                's|type="date" name="exp_date" value="{{ old('"'"'exp_date'"'"', \$server->exp_date) }}"|type="datetime-local" name="exp_date" value="{{ old('"'"'exp_date'"'"', optional($server->exp_date)->format('"'"'Y-m-d\\TH:i'"'"')) }}"|' \
                "$file"
            log "Form Edit Server: input exp_date diubah ke datetime-local."
        else
            log "PERINGATAN: pola input exp_date di Edit Server tidak cocok persis, cek manual."
        fi
    else
        log "PERINGATAN: field exp_date tidak ditemukan di Edit Server."
    fi
}

patch_model_cast() {
    local file="$PTERODACTYL/app/Models/Server.php"
    [[ -f "$file" ]] || die "Server.php tidak ditemukan."

    backup_file "$file"

    if grep -Fq "'exp_date' => 'datetime'" "$file"; then
        log "Cast exp_date sudah ada di Server.php."
        return
    fi

    if grep -Fq 'protected $casts = [' "$file"; then
        sed -i \
            "/protected \$casts = \[/a\\
        'exp_date' => 'datetime'," \
            "$file"
        log "Cast exp_date ditambahkan ke Server.php."
    else
        log "PERINGATAN: \$casts array tidak ditemukan di Server.php, tambahkan manual:"
        log "  'exp_date' => 'datetime',"
    fi
}

patch_kernel_simple() {
    local file="$PTERODACTYL/app/Console/Kernel.php"
    [[ -f "$file" ]] || die "Kernel.php tidak ditemukan."

    backup_file "$file"

    if ! grep -Fq "Server::whereNotNull('exp_date')" "$file"; then
        log "PERINGATAN: scheduler Auto Suspend tidak ditemukan di Kernel.php."
        return
    fi

    python3 - "$file" <<'PY'
import re
import sys

path = sys.argv[1]

with open(path, "r", encoding="utf-8") as f:
    text = f.read()

new_block = r'''        $schedule->call(function () {
            $servers = Server::whereNotNull('exp_date')
                ->where('exp_date', '<', now())
                ->get();

            $suspensionService = \App::make(
                'Pterodactyl\Services\Servers\SuspensionService'
            );

            foreach ($servers as $server) {
                if (
                    $server->status === 'suspended' ||
                    $server->status === 'installing'
                ) {
                    continue;
                }

                try {
                    $suspensionService->toggle($server, 'suspend');
                } catch (\Throwable $e) {
                    \Log::error(
                        'Auto Suspend failed for server ' .
                        $server->id . ': ' .
                        $e->getMessage()
                    );
                }
            }
        })->everyMinute();'''

pattern = re.compile(
    r"\$schedule->call\(function \(\) \{.*?Server::whereNotNull\('exp_date'\).*?\}\)->[^;]*;",
    re.DOTALL,
)

if not pattern.search(text):
    raise SystemExit("Blok scheduler lama tidak cocok.")

text = pattern.sub(new_block, text, count=1)

with open(path, "w", encoding="utf-8") as f:
    f.write(text)
PY

    if [[ $? -eq 0 ]]; then
        log "Kernel.php disederhanakan: cek exp_date (datetime) setiap menit, langsung suspend begitu lewat."
    else
        log "PERINGATAN: patch otomatis Kernel.php gagal. Kirim isi Kernel.php untuk dibuatkan patch manual."
    fi
}

migrate_and_clear() {
    cd "$PTERODACTYL"
    log "Menjalankan migration..."
    php artisan migrate --force

    log "Membersihkan cache..."
    php artisan route:clear
    php artisan config:clear
    php artisan view:clear
    php artisan cache:clear

    chown -R www-data:www-data "$PTERODACTYL"
}

main() {
    log "=============================================="
    log "INSTALL AUTO SUSPEND - DATETIME PER SERVER"
    log "=============================================="

    download_migration
    patch_create_form
    patch_edit_form
    patch_model_cast
    patch_kernel_simple
    migrate_and_clear

    log "=============================================="
    log "SELESAI"
    log "=============================================="
    log "Buka Create Server / Edit Server di Admin Panel,"
    log "field Expiration Date sekarang bisa pilih jam & menit."
    log "Backup file lama (jika ada perubahan) di: $BACKUP_DIR"
}

main "$@"
