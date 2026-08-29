#!/usr/bin/env bash

set -Eeuo pipefail

# ============================================================
# PTERODACTYL AUTO SUSPEND + EXPIRATION DATE INSTALLER
# ============================================================

wget -O /tmp/autosuspend.zip "https://cdn.jsdelivr.net/gh/Bangsano/themeinstaller@main/autosuspend.zip"
file /tmp/autosuspend.zip
unzip -t /tmp/autosuspend.zip

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info() {
    echo -e "${CYAN}[INFO]${NC} $1"
}

success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

banner() {
    clear 2>/dev/null || true

    echo -e "${CYAN}"
    echo "============================================================"
    echo "       PTERODACTYL AUTO SUSPEND INSTALLER"
    echo "       EXPIRATION DATE + AUTO SUSPEND"
    echo "============================================================"
    echo -e "${NC}"
}

cleanup() {
    if [[ -n "${TEMP_DIR:-}" && -d "${TEMP_DIR:-}" ]]; then
        rm -rf "$TEMP_DIR"
    fi
}

trap cleanup EXIT

# ============================================================
# ROOT CHECK
# ============================================================

if [[ "$EUID" -ne 0 ]]; then
    error "Script harus dijalankan sebagai root."
    echo
    echo "Gunakan:"
    echo "  sudo bash install-auto-suspend.sh"
    exit 1
fi

banner

# ============================================================
# CHECK PTERODACTYL
# ============================================================

info "Memeriksa instalasi Pterodactyl..."

if [[ ! -d "$PTERO_DIR" ]]; then
    error "Folder Pterodactyl tidak ditemukan:"
    echo "  $PTERO_DIR"
    exit 1
fi

if [[ ! -f "$PTERO_DIR/artisan" ]]; then
    error "File artisan tidak ditemukan."
    error "Kemungkinan path Pterodactyl bukan $PTERO_DIR."
    exit 1
fi

success "Pterodactyl ditemukan."

cd "$PTERO_DIR"

# ============================================================
# CHECK COMMANDS
# ============================================================

info "Memeriksa dependency sistem..."

for cmd in curl wget unzip php; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        error "Command '$cmd' tidak ditemukan."
        echo
        echo "Install terlebih dahulu command tersebut."
        exit 1
    fi
done

success "Dependency dasar tersedia."

# ============================================================
# CONFIRMATION
# ============================================================

echo
warning "Installer akan memodifikasi file Pterodactyl."
warning "Backup akan dibuat terlebih dahulu."
echo

read -r -p "Lanjutkan instalasi Auto Suspend? (y/n): " CONFIRMATION

if [[ ! "$CONFIRMATION" =~ ^[Yy]$ ]]; then
    echo "Instalasi dibatalkan."
    exit 0
fi

# ============================================================
# BACKUP
# ============================================================

echo
info "Membuat backup Pterodactyl..."

mkdir -p "$BACKUP_DIR"

cp -a \
    "$PTERO_DIR/app" \
    "$PTERO_DIR/resources" \
    "$PTERO_DIR/database" \
    "$PTERO_DIR/package.json" \
    "$PTERO_DIR/yarn.lock" \
    "$BACKUP_DIR/" 2>/dev/null || true

success "Backup dibuat:"
echo "  $BACKUP_DIR"

# ============================================================
# DOWNLOAD AUTOSUSPEND ZIP
# ============================================================

TEMP_DIR="$(mktemp -d)"

cd "$TEMP_DIR"

info "Mengunduh autosuspend.zip..."

if ! wget -q --show-progress "$DOWNLOAD_URL" -O autosuspend.zip; then
    error "Gagal mengunduh autosuspend.zip."
    exit 1
fi

if [[ ! -s autosuspend.zip ]]; then
    error "autosuspend.zip kosong atau tidak valid."
    exit 1
fi

success "autosuspend.zip berhasil diunduh."

# ============================================================
# EXTRACT
# ============================================================

info "Mengekstrak autosuspend.zip..."

mkdir -p extracted

if ! unzip -oq autosuspend.zip -d extracted; then
    error "Gagal mengekstrak autosuspend.zip."
    exit 1
fi

success "File berhasil diekstrak."

# ============================================================
# FIND PTERODACTYL DIRECTORY INSIDE ZIP
# ============================================================

SOURCE_DIR=""

if [[ -d "$TEMP_DIR/extracted/pterodactyl" ]]; then
    SOURCE_DIR="$TEMP_DIR/extracted/pterodactyl"
else
    FOUND_DIR="$(find "$TEMP_DIR/extracted" -maxdepth 2 -type d -name pterodactyl | head -n 1 || true)"

    if [[ -n "$FOUND_DIR" ]]; then
        SOURCE_DIR="$FOUND_DIR"
    fi
fi

if [[ -z "$SOURCE_DIR" ]]; then
    error "Folder 'pterodactyl' tidak ditemukan di dalam autosuspend.zip."
    echo
    echo "https://cdn.jsdelivr.net/gh/Bangsano/themeinstaller@main/autosuspend.zip:"
    find "$TEMP_DIR/extracted" -maxdepth 3 -type f | head -50
    exit 1
fi

# ============================================================
# COPY FILE DARI ZIP
# ============================================================

info "Menyalin file Auto Suspend..."

cp -a "$SOURCE_DIR/." "$PTERO_DIR/"

success "File Auto Suspend berhasil disalin."

cd "$PTERO_DIR"

# ============================================================
# KERNEL.PHP
# ============================================================

KERNEL_FILE="app/Console/Kernel.php"

if [[ -f "$KERNEL_FILE" ]]; then

    if ! grep -q "Server::where('exp_date'" "$KERNEL_FILE"; then

        info "Menambahkan scheduler Auto Suspend..."

        if ! grep -q "use Pterodactyl\\\\Models\\\\Server;" "$KERNEL_FILE"; then
            sed -i \
                '/use Ramsey\\\\Uuid\\\\Uuid;/a use Pterodactyl\\Models\\Server;' \
                "$KERNEL_FILE"
        fi

        if grep -q "\$schedule->command(CleanServiceBackupFilesCommand::class)->daily();" "$KERNEL_FILE"; then

            sed -i "/\$schedule->command(CleanServiceBackupFilesCommand::class)->daily();/a\\
\\
        \$schedule->call(function () {\\
            \$servers = Server::where('exp_date', '<', now())->get();\\
            \$suspensionService = \\\\App::make('Pterodactyl\\\\Services\\\\Servers\\\\SuspensionService');\\
            foreach (\$servers as \$server) {\\
                if (\$server->status != 'suspended') {\\
                    if (\$server->status != 'installing') {\\
                        if (\$server->exp_date != null) {\\
                            \$suspensionService->toggle(\$server, 'suspend');\\
                        }\\
                    }\\
                }\\
            }\\
        })->dailyAt('23:55');" \
                "$KERNEL_FILE"

            success "Scheduler Auto Suspend berhasil ditambahkan."

        else
            warning "Baris scheduler CleanServiceBackupFilesCommand tidak ditemukan."
            warning "Scheduler Auto Suspend tidak ditambahkan otomatis."
        fi

    else
        warning "Scheduler Auto Suspend sudah ada. Dilewati."
    fi
else
    error "$KERNEL_FILE tidak ditemukan."
    exit 1
fi

# ============================================================
# ADMIN SERVER CONTROLLER
# ============================================================

FILE="app/Http/Controllers/Admin/ServersController.php"

if [[ -f "$FILE" ]]; then

    if ! grep -q "'exp_date'" "$FILE"; then
        info "Menambahkan exp_date ke ServersController..."

        sed -i \
            "/'owner_id', 'external_id', 'name', 'description',/a\\
            'exp_date'," \
            "$FILE" || warning "Gagal memodifikasi ServersController."

    else
        warning "exp_date sudah ada di ServersController."
    fi
fi

# ============================================================
# STORE SERVER REQUEST
# ============================================================

FILE="app/Http/Requests/Api/Application/Servers/StoreServerRequest.php"

if [[ -f "$FILE" ]]; then

    if ! grep -q "'exp_date' => \$rules\['exp_date'\]" "$FILE"; then

        info "Menambahkan exp_date ke StoreServerRequest..."

        sed -i \
            "/'oom_disabled' => 'sometimes|boolean',/a\\
            'exp_date' => \$rules['exp_date']," \
            "$FILE" || warning "Gagal menambahkan validation exp_date."

    fi

    if ! grep -q "'exp_date' => array_get(\$data, 'exp_date')" "$FILE"; then

        sed -i \
            "/'oom_disabled' => array_get(\$data, 'oom_disabled'),/a\\
            'exp_date' => array_get(\$data, 'exp_date')," \
            "$FILE" || warning "Gagal menambahkan exp_date ke data."
    fi
fi

# ============================================================
# SERVER MODEL
# ============================================================

FILE="app/Models/Server.php"

if [[ -f "$FILE" ]]; then

    if ! grep -q "'exp_date' =>" "$FILE"; then

        info "Menambahkan exp_date ke Server model..."

        sed -i \
            "/'backup_limit' => 'present|nullable|integer|min:0',/a\\
        'exp_date' => 'sometimes|nullable'," \
            "$FILE" || warning "Gagal menambahkan exp_date ke Server model."

    else
        warning "exp_date sudah ada di Server model."
    fi
fi

# ============================================================
# DETAILS MODIFICATION SERVICE
# ============================================================

FILE="app/Services/Servers/DetailsModificationService.php"

if [[ -f "$FILE" ]]; then

    if ! grep -q "'exp_date' => Arr::get(\$data, 'exp_date')" "$FILE"; then

        info "Menambahkan exp_date ke DetailsModificationService..."

        sed -i \
            "/'description' => Arr::get(\$data, 'description') ?? '',/a\\
                'exp_date' => Arr::get(\$data, 'exp_date') ?? null," \
            "$FILE" || warning "Gagal memodifikasi DetailsModificationService."

    fi
fi

# ============================================================
# SERVER CREATION SERVICE
# ============================================================

FILE="app/Services/Servers/ServerCreationService.php"

if [[ -f "$FILE" ]]; then

    if ! grep -q "'exp_date' => Arr::get(\$data, 'exp_date')" "$FILE"; then

        info "Menambahkan exp_date ke ServerCreationService..."

        sed -i \
            "/'backup_limit' => Arr::get(\$data, 'backup_limit') ?? 0,/a\\
                'exp_date' => Arr::get(\$data, 'exp_date') ?? null," \
            "$FILE" || warning "Gagal memodifikasi ServerCreationService."

    fi
fi

# ============================================================
# SERVER TRANSFORMER
# ============================================================

FILE="app/Transformers/Api/Client/ServerTransformer.php"

if [[ -f "$FILE" ]]; then

    if ! grep -q "'exp_date' => \$server->exp_date" "$FILE"; then

        info "Menambahkan exp_date ke ServerTransformer..."

        sed -i \
            "/'name' => \$server->name,/a\\
                'exp_date' => \$server->exp_date," \
            "$FILE" || warning "Gagal memodifikasi ServerTransformer."

    fi
fi

# ============================================================
# FRONTEND getServer.ts
# ============================================================

FILE="resources/scripts/api/server/getServer.ts"

if [[ -f "$FILE" ]]; then

    if ! grep -q "expDate: string;" "$FILE"; then

        info "Menambahkan expDate ke frontend API..."

        sed -i \
            "/name: string;/a\\
        expDate: string;" \
            "$FILE"
    fi

    if ! grep -q "expDate: data.exp_date" "$FILE"; then

        sed -i \
            "/name: data.name,/a\\
        expDate: data.exp_date," \
            "$FILE"
    fi

    success "Frontend API diperbarui."
else
    warning "getServer.ts tidak ditemukan. Dilewati."
fi

# ============================================================
# SERVER DETAILS BLOCK
# ============================================================

FILE="resources/scripts/components/server/console/ServerDetailsBlock.tsx"

if [[ -f "$FILE" ]]; then

    if ! grep -q "faCalendarDay" "$FILE"; then

        info "Menambahkan ikon Expiration Date..."

        sed -i \
            "/faMicrochip,/a\\
        faCalendarDay," \
            "$FILE"
    fi

    if ! grep -q "const expDate" "$FILE"; then

        sed -i \
            "/const limits = ServerContext.useStoreState((state) => state.server.data!.limits);/a\\
        const expDate = ServerContext.useStoreState((state) => state.server.data!.expDate);" \
            "$FILE"
    fi

    if ! grep -q "title={'Expiration Date'}" "$FILE"; then

        info "Menambahkan tampilan Expiration Date..."

        python3 - "$FILE" <<'PY'
from pathlib import Path
import sys

file = Path(sys.argv[1])
text = file.read_text()

needle = """<StatBlock icon={faMicrochip} title={'CPU Load'} color={getBackgroundColor(stats.cpu, limits.cpu)}>"""

insert = """<StatBlock icon={faCalendarDay} title={'Expiration Date'}>
                {expDate ? expDate : 'Unlimited'}
            </StatBlock>
            """

if needle in text:
    text = text.replace(needle, insert + needle, 1)
    file.write_text(text)
else:
    print("CPU Load StatBlock tidak ditemukan.")
PY

        success "Expiration Date ditambahkan ke tampilan server."
    else
        warning "Expiration Date frontend sudah ada."
    fi

else
    warning "ServerDetailsBlock.tsx tidak ditemukan."
    warning "Kemungkinan versi Pterodactyl berbeda."
fi

# ============================================================
# ADMIN SERVER DETAILS PAGE
# ============================================================

TARGET_BLADE="resources/views/admin/servers/view/details.blade.php"

if [[ -f "$TARGET_BLADE" ]]; then

    if ! grep -q "name=\"exp_date\"" "$TARGET_BLADE"; then

        info "Menambahkan input Expiration Date ke halaman server..."

        python3 - "$TARGET_BLADE" <<'PY'
from pathlib import Path
import sys

file = Path(sys.argv[1])
text = file.read_text()

if 'name="exp_date"' in text:
    raise SystemExit(0)

needle = '<p class="text-muted small">Character limits: <code>a-zA-Z0-9_-</code> and <code>[Space]</code>.</p>'

if needle in text:
    block = '''
                    <div class="form-group">
                        <label for="exp_date" class="control-label">Expiration date</label>
                        <input type="date"
                               name="exp_date"
                               value="{{ old('exp_date', $server->exp_date) }}"
                               class="form-control" />
                        <p class="text-muted small">
                            Server akan kadaluarsa (suspend) di akhir hari pada tanggal yang dipilih.
                            Kosongkan jika ingin server permanen.
                        </p>
                    </div>
'''

    pos = text.find('</div>', text.find(needle))

    if pos != -1:
        text = text[:pos + 6] + block + text[pos + 6:]
        file.write_text(text)
    else:
        print("Container form tidak ditemukan.")
else:
    print("Target form tidak ditemukan.")
PY

        success "Expiration Date ditambahkan ke halaman server."
    else
        warning "Input Expiration Date sudah ada."
    fi
else
    warning "details.blade.php tidak ditemukan."
fi

# ============================================================
# NEW SERVER PAGE
# ============================================================

TARGET_NEW="resources/views/admin/servers/new.blade.php"

if [[ -f "$TARGET_NEW" ]]; then

    if ! grep -q "name=\"exp_date\"" "$TARGET_NEW"; then

        info "Menambahkan Expiration Date ke halaman Create Server..."

        python3 - "$TARGET_NEW" <<'PY'
from pathlib import Path
import sys

file = Path(sys.argv[1])
text = file.read_text()

if 'name="exp_date"' in text:
    raise SystemExit(0)

needle = '<p class="small text-muted no-margin">Email address of the Server Owner.</p>'

if needle in text:
    block = '''
                        
                        <div class="form-group">
                            <label for="exp_date">Expiration date</label>
                            <input type="date"
                                   class="form-control"
                                   id="expiration"
                                   name="exp_date"
                                   value="{{ old('exp_date') }}"
                                   placeholder="Expiration Date">
                            <p class="small text-muted no-margin">
                                Server akan kadaluarsa (suspend) di akhir hari pada tanggal yang dipilih.
                                Kosongkan jika ingin server permanen.
                            </p>
                        </div>
'''

    start = text.find(needle)
    end = text.find('</div>', start)

    if end != -1:
        text = text[:end + 6] + block + text[end + 6:]
        file.write_text(text)
    else:
        print("Container form tidak ditemukan.")
else:
    print("Target Email Owner tidak ditemukan.")
PY

        success "Expiration Date ditambahkan ke Create Server."
    else
        warning "Input Expiration Date sudah ada di Create Server."
    fi
else
    warning "new.blade.php tidak ditemukan."
fi

# ============================================================
# DATABASE MIGRATION
# ============================================================

cd "$PTERO_DIR"

info "Menjalankan database migration..."

if php artisan migrate --force; then
    success "Database migration berhasil."
else
    error "Database migration gagal."
    error "Backup tersedia di:"
    echo "  $BACKUP_DIR"
    exit 1
fi

# ============================================================
# NODE / YARN
# ============================================================

if ! command -v node >/dev/null 2>&1; then
    warning "Node.js belum tersedia."

    if command -v apt-get >/dev/null 2>&1; then
        info "Menginstall Node.js..."

        apt-get update -y
        apt-get install -y nodejs npm

    else
        error "Tidak dapat menginstall Node.js otomatis."
        exit 1
    fi
fi

success "Node.js tersedia: $(node --version)"

# ============================================================
# YARN
# ============================================================

if ! command -v yarn >/dev/null 2>&1; then

    info "Yarn belum tersedia."

    if command -v corepack >/dev/null 2>&1; then
        corepack enable || true
        corepack prepare yarn@1.22.22 --activate || true
    fi
fi

if ! command -v yarn >/dev/null 2>&1; then
    info "Menginstall Yarn..."

    npm install -g yarn
fi

success "Yarn tersedia: $(yarn --version)"

# ============================================================
# CROSS-ENV
# ============================================================

info "Memeriksa cross-env..."

if [[ -f package.json ]]; then

    if ! node -e '
const p=require("./package.json");
process.exit(
    p.dependencies?.["cross-env"] ||
    p.devDependencies?.["cross-env"]
    ? 0 : 1
)'; then

        info "cross-env belum ada. Menginstall..."

        yarn add cross-env
    else
        success "cross-env sudah tersedia."
    fi
fi

# ============================================================
# YARN INSTALL
# ============================================================

info "Menginstall dependency frontend..."

if yarn install --ignore-engines; then
    success "Dependency berhasil diinstall."
else
    error "yarn install gagal."
    exit 1
fi

# ============================================================
# BUILD FRONTEND
# ============================================================

info "Membangun ulang frontend Pterodactyl..."

export NODE_OPTIONS="${NODE_OPTIONS:---openssl-legacy-provider}"

if yarn run build:production; then
    success "Build frontend berhasil."
else
    error "Build frontend gagal."
    error "Backup tersedia di:"
    echo "  $BACKUP_DIR"
    exit 1
fi

# ============================================================
# CLEAR CACHE
# ============================================================

info "Membersihkan cache Pterodactyl..."

php artisan optimize:clear || true
php artisan view:clear || true
php artisan config:clear || true
php artisan route:clear || true

success "Cache berhasil dibersihkan."

# ============================================================
# PERMISSION
# ============================================================

info "Mengatur permission Pterodactyl..."

chown -R www-data:www-data "$PTERO_DIR"

success "Permission berhasil diatur."

# ============================================================
# RESTART SERVICES
# ============================================================

echo
info "Mencoba restart service..."

systemctl restart nginx 2>/dev/null || warning "Nginx tidak berhasil direstart."
systemctl restart php8.3-fpm 2>/dev/null || true
systemctl restart php8.2-fpm 2>/dev/null || true
systemctl restart php8.1-fpm 2>/dev/null || true
systemctl restart wings 2>/dev/null || warning "Wings tidak berhasil direstart."

# ============================================================
# FINISH
# ============================================================

echo
echo -e "${GREEN}"
echo "============================================================"
echo "       LXJR OFFC AUTO SUSPEND BERHASIL DIPASANG"
echo "============================================================"
echo -e "${NC}"

echo
echo "Fitur:"
echo "  ✓ Expiration Date"
echo "  ✓ Auto Suspend"
echo "  ✓ Database Migration"
echo "  ✓ Admin Create Server"
echo "  ✓ Admin Server Details"
echo "  ✓ Client Server Details"
echo "  ✓ API exp_date"
echo "  ✓ Frontend Build"
echo
echo "Backup:"
echo "  $BACKUP_DIR"
echo
echo "Auto suspend dijadwalkan setiap hari:"
echo "  23:55"
echo
echo "Jika Expiration Date sudah lewat, server akan disuspend."
echo "Expiration Date kosong = Unlimited."
echo