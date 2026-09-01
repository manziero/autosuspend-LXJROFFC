#!/usr/bin/env bash
set -Eeuo pipefail

# ============================================================
# Auto Suspend - Admin Panel Setting Installer
# Narik 2 file (Controller + Blade) dari GitHub kamu,
# lalu otomatis nyambungin ke route + Kernel.php
# ============================================================

# >>>> EDIT DULU 2 BARIS INI SESUAI REPO GITHUB KAMU <<<<
CONTROLLER_URL="https://raw.githubusercontent.com/USERNAME/REPO/main/AutoSuspendController.php"
BLADE_URL="https://raw.githubusercontent.com/USERNAME/REPO/main/autosuspend.blade.php"

PTERODACTYL="/var/www/pterodactyl"
BACKUP_DIR="/root/pterodactyl-autosuspend-setting-backup-$(date +%Y%m%d-%H%M%S)"

log() { printf '[AUTOSUSPEND-SETTING] %s\n' "$*"; }
die() { printf '[AUTOSUSPEND-SETTING] ERROR: %s\n' "$*" >&2; exit 1; }

[[ "${EUID}" -eq 0 ]] || die "Jalankan sebagai root."
[[ -f "$PTERODACTYL/artisan" ]] || die "Pterodactyl tidak ditemukan di $PTERODACTYL."

backup_file() {
    local file="$1"
    if [[ -f "$file" ]]; then
        mkdir -p "$BACKUP_DIR"
        cp -a "$file" "$BACKUP_DIR/$(basename "$file")"
    fi
}

download_files() {
    log "Mengunduh AutoSuspendController.php..."
    mkdir -p "$PTERODACTYL/app/Http/Controllers/Admin/Settings"
    curl -fsSL "$CONTROLLER_URL" \
        -o "$PTERODACTYL/app/Http/Controllers/Admin/Settings/AutoSuspendController.php"

    log "Mengunduh autosuspend.blade.php..."
    mkdir -p "$PTERODACTYL/resources/views/admin/settings"
    curl -fsSL "$BLADE_URL" \
        -o "$PTERODACTYL/resources/views/admin/settings/autosuspend.blade.php"

    [[ -s "$PTERODACTYL/app/Http/Controllers/Admin/Settings/AutoSuspendController.php" ]] ||
        die "Gagal mengunduh AutoSuspendController.php (cek URL GitHub)."
    [[ -s "$PTERODACTYL/resources/views/admin/settings/autosuspend.blade.php" ]] ||
        die "Gagal mengunduh autosuspend.blade.php (cek URL GitHub)."
}

patch_routes() {
    local file="$PTERODACTYL/routes/admin.php"
    [[ -f "$file" ]] || die "routes/admin.php tidak ditemukan."

    backup_file "$file"

    if grep -Fq "admin.settings.autosuspend" "$file"; then
        log "Route autosuspend sudah terpasang."
        return
    fi

    if grep -Fq "Route::group(['prefix' => 'settings']" "$file"; then
        sed -i \
            "/Route::group(\['prefix' => 'settings'\]/a\\
    Route::get('/autosuspend', [\\\\Pterodactyl\\\\Http\\\\Controllers\\\\Admin\\\\Settings\\\\AutoSuspendController::class, 'index'])->name('admin.settings.autosuspend');\\
    Route::post('/autosuspend', [\\\\Pterodactyl\\\\Http\\\\Controllers\\\\Admin\\\\Settings\\\\AutoSuspendController::class, 'update']);" \
            "$file"
        log "Route autosuspend berhasil ditambahkan."
    else
        log "PERINGATAN: pattern grup route 'settings' tidak ditemukan."
        log "Tambahkan manual 2 baris route di dalam grup settings routes/admin.php:"
        log "  Route::get('/autosuspend', [\\Pterodactyl\\Http\\Controllers\\Admin\\Settings\\AutoSuspendController::class, 'index'])->name('admin.settings.autosuspend');"
        log "  Route::post('/autosuspend', [\\Pterodactyl\\Http\\Controllers\\Admin\\Settings\\AutoSuspendController::class, 'update']);"
    fi
}

patch_kernel_use_setting() {
    local file="$PTERODACTYL/app/Console/Kernel.php"
    [[ -f "$file" ]] || die "Kernel.php tidak ditemukan."

    backup_file "$file"

    if grep -Fq "settings::autosuspend:time" "$file"; then
        log "Kernel.php sudah pakai setting jam dari panel."
        return
    fi

    if ! grep -Fq "Server::whereNotNull('exp_date')" "$file"; then
        log "PERINGATAN: scheduler Auto Suspend tidak ditemukan di Kernel.php."
        log "Jalankan dulu installer Auto Suspend utama sebelum script ini."
        return
    fi

    python3 - "$file" <<'PY'
import re
import sys

path = sys.argv[1]

with open(path, "r", encoding="utf-8") as f:
    text = f.read()

new_block = r'''        $schedule->call(function () {
            $settingsRepo = \App::make(
                \Pterodactyl\Contracts\Repository\SettingsRepositoryInterface::class
            );
            $cutoffTime = $settingsRepo->get('settings::autosuspend:time', '00:00:00');

            $servers = Server::whereNotNull('exp_date')->get();

            $suspensionService = \App::make(
                'Pterodactyl\Services\Servers\SuspensionService'
            );

            foreach ($servers as $server) {
                if (
                    $server->status === 'suspended' ||
                    $server->status === 'installing' ||
                    $server->exp_date === null
                ) {
                    continue;
                }

                $expireAt = \Carbon\Carbon::parse($server->exp_date)
                    ->setTimeFromTimeString($cutoffTime);

                if ($expireAt->isFuture()) {
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
        })->timezone('Asia/Jakarta')->everyMinute();'''

# Cocokkan blok scheduler lama, baik versi dailyAt('23:55') maupun versi everyMinute()
pattern = re.compile(
    r"\$schedule->call\(function \(\) \{.*?Server::whereNotNull\('exp_date'\).*?\}\)->(?:dailyAt\('23:55'\)|timezone\('Asia/Jakarta'\)->everyMinute\(\));",
    re.DOTALL,
)

if not pattern.search(text):
    raise SystemExit("Blok scheduler lama tidak cocok dengan pola yang diketahui.")

text = pattern.sub(new_block, text, count=1)

with open(path, "w", encoding="utf-8") as f:
    f.write(text)
PY

    if [[ $? -eq 0 ]]; then
        log "Kernel.php berhasil diupdate untuk pakai setting jam dari panel."
    else
        log "PERINGATAN: patch otomatis Kernel.php gagal (pola tidak cocok)."
        log "Kirim isi Kernel.php ke saya, biar dikasih patch manual yang pas."
    fi
}

clear_cache() {
    cd "$PTERODACTYL"
    log "Membersihkan cache Laravel..."
    php artisan route:clear
    php artisan config:clear
    php artisan view:clear
    chown -R www-data:www-data "$PTERODACTYL"
}

main() {
    log "=============================================="
    log "INSTALL AUTO SUSPEND - ADMIN PANEL SETTING"
    log "=============================================="

    download_files
    patch_routes
    patch_kernel_use_setting
    clear_cache

    log "=============================================="
    log "SELESAI"
    log "=============================================="
    log "Buka: https://<domain-panel-kamu>/admin/settings/autosuspend"
    log "Backup file lama tersimpan di: $BACKUP_DIR (jika ada perubahan)"
}

main "$@"
